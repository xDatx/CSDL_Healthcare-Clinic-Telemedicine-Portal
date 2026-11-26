"""Doctor portal: own schedule, clinical write path, consultation workflow.

MySQL cannot restrict a doctor to *their* rows (column grants only), so every route below first
proves ownership with a query filtered by the session doctor id (BR-21), then writes.
"""
from flask import Blueprint, abort, flash, redirect, render_template, request, session, url_for

import services
from auth import role_required
from db import get_db
from errors import UserError, explain
from utils import integer, safe_next, text
import pymysql

bp = Blueprint("doctor", __name__, url_prefix="/doctor")

_APPT_SELECT = ("SELECT v.*, mr.record_id FROM v_appointment_detail v "
                "LEFT JOIN medical_record mr ON mr.appointment_id = v.appointment_id ")
# what a doctor may do to an appointment from the UI (the trigger validates the transition, BR-11)
_STATUS_ACTIONS = {"CONFIRMED", "IN_PROGRESS", "COMPLETED", "CANCELLED"}


def me():
    return session["uid"]


def _own_appointment(db, appointment_id):
    row = db.one(_APPT_SELECT + "WHERE v.appointment_id = %s AND v.doctor_id = %s", (appointment_id, me()))
    if not row:
        abort(404)
    return row


# ------------------------------------------------------------------ dashboard
@bp.route("/")
@role_required("doctor")
def home():
    db = get_db()
    today = db.all(_APPT_SELECT + "WHERE v.doctor_id = %s AND v.appointment_date = CURDATE() "
                   "ORDER BY v.start_time", (me(),))
    consults = db.call("sp_list_my_consultations", me())[0]
    incoming = [c for c in consults if c["consulting_doctor_id"] == me() and c["status"] == "PENDING"]
    to_record = db.scalar(
        "SELECT COUNT(*) FROM v_appointment_detail v LEFT JOIN medical_record mr "
        "ON mr.appointment_id = v.appointment_id "
        "WHERE v.doctor_id = %s AND v.status = 'COMPLETED' AND mr.record_id IS NULL", (me(),))
    return render_template("doctor/home.html", today=today, incoming=incoming, to_record=to_record)


# ------------------------------------------------------------------ appointments
@bp.route("/appointments")
@role_required("doctor")
def appointments():
    scope = request.args.get("scope", "upcoming")
    status = request.args.get("status", "")
    sql, args = _APPT_SELECT + "WHERE v.doctor_id = %s", [me()]
    if scope == "upcoming":
        sql += " AND v.appointment_date >= CURDATE()"
    elif scope == "past":
        sql += " AND v.appointment_date < CURDATE()"
    elif scope == "norecord":
        sql += " AND v.status = 'COMPLETED' AND mr.record_id IS NULL"
    if status in ("PENDING", "CONFIRMED", "IN_PROGRESS", "COMPLETED", "CANCELLED"):
        sql += " AND v.status = %s"
        args.append(status)
    order = "ASC" if scope == "upcoming" else "DESC"
    rows = get_db().all(f"{sql} ORDER BY v.start_time {order} LIMIT 300", args)
    return render_template("doctor/appointments.html", appts=rows, scope=scope, status=status)


@bp.post("/appointments/<int:appointment_id>/status")
@role_required("doctor")
def set_status(appointment_id):
    new = request.form.get("status", "")
    if new not in _STATUS_ACTIONS:
        abort(400)
    db = get_db()
    _own_appointment(db, appointment_id)
    db.execute("UPDATE appointment SET status = %s WHERE appointment_id = %s", (new, appointment_id))
    db.commit()
    flash(f"Lịch hẹn #{appointment_id} đã chuyển sang {new}.", "success")
    return safe_next("doctor.appointments")


# ------------------------------------------------------------------ medical records
def _item_rows_from_form(form):
    keys = ("medication_id", "quantity", "dosage", "frequency", "duration_days")
    lists = {k: form.getlist(k) for k in keys}
    n = max((len(v) for v in lists.values()), default=0)
    return [{k: (lists[k][i] if i < len(lists[k]) else "") for k in keys} for i in range(n)] or [{}]


def _record_context(db, record_id):
    """Patient / appointment info for a record the doctor is already authorised to read."""
    return db.one(
        "SELECT v.appointment_id, v.patient_name, v.appointment_date, v.doctor_id, v.doctor_name, "
        "       v.appointment_type "
        "FROM medical_record mr JOIN v_appointment_detail v ON v.appointment_id = mr.appointment_id "
        "WHERE mr.record_id = %s", (record_id,))


@bp.route("/appointments/<int:appointment_id>/record/new", methods=["GET", "POST"])
@role_required("doctor")
def record_new(appointment_id):
    db = get_db()
    appt = _own_appointment(db, appointment_id)
    if appt["record_id"]:
        flash("Lịch hẹn này đã có hồ sơ bệnh án.", "info")
        return redirect(url_for("doctor.record", record_id=appt["record_id"]))
    if appt["status"] != "COMPLETED":
        raise UserError("Chỉ tạo hồ sơ khi lịch hẹn đã hoàn tất (COMPLETED).")
    meds = db.all("SELECT medication_id, name, unit FROM v_active_medication ORDER BY name")

    if request.method == "POST":
        try:
            values = services.parse_record_form(request.form)
            items = services.parse_prescription_rows(request.form)
            rid = db.execute(
                "INSERT INTO medical_record (appointment_id, systolic_bp, diastolic_bp, heart_rate, "
                "temperature_c, oxygen_saturation, symptoms, diagnosis, notes) "
                "VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (appointment_id, *(values[c] for c in services.RECORD_COLS)))
            if items:
                pid = db.execute("INSERT INTO prescription (record_id) VALUES (%s)", (rid,))
                for it in items:
                    db.execute(
                        "INSERT INTO prescription_item (prescription_id, medication_id, quantity, "
                        "dosage, frequency, duration_days) VALUES (%s, %s, %s, %s, %s, %s)",
                        (pid, it["medication_id"], it["quantity"], it["dosage"], it["frequency"],
                         it["duration_days"]))
            db.commit()
        except (UserError, pymysql.MySQLError) as exc:
            db.rollback()
            flash(explain(exc), "danger")
            return render_template("doctor/record_form.html", appt=appt, meds=meds, form=request.form,
                                   rows=_item_rows_from_form(request.form), mode="new")
        flash("Đã lưu hồ sơ bệnh án" + (" và đơn thuốc." if items else "."), "success")
        return redirect(url_for("doctor.record", record_id=rid))

    return render_template("doctor/record_form.html", appt=appt, meds=meds, form={}, rows=[{}], mode="new")


@bp.route("/records/<int:record_id>")
@role_required("doctor")
def record(record_id):
    """Authorised + audited by sp_read_medical_record: treating doctor, or consulting doctor with an
    APPROVED, unexpired request (BR-21 / BR-22)."""
    db = get_db()
    sets = db.call("sp_read_medical_record", record_id, "DOCTOR", me())
    db.commit()
    info = _record_context(db, record_id)
    mine = [c for c in db.call("sp_list_my_consultations", me())[0] if c["record_id"] == record_id]
    return render_template("shared/record.html", rec=sets[0][0], items=sets[1], info=info,
                           back=url_for("doctor.appointments", scope="all"),
                           can_edit=bool(info and info["doctor_id"] == me()), consults=mine)


@bp.route("/records/<int:record_id>/edit", methods=["GET", "POST"])
@role_required("doctor")
def record_edit(record_id):
    db = get_db()
    ctx = _record_context(db, record_id)
    if not ctx or ctx["doctor_id"] != me():
        abort(403)  # only the treating doctor edits; consulting doctors are read-only
    if request.method == "POST":
        try:
            values = services.parse_record_form(request.form)
            db.execute(
                "UPDATE medical_record SET systolic_bp=%s, diastolic_bp=%s, heart_rate=%s, "
                "temperature_c=%s, oxygen_saturation=%s, symptoms=%s, diagnosis=%s, notes=%s "
                "WHERE record_id=%s", (*(values[c] for c in services.RECORD_COLS), record_id))
            db.commit()
        except (UserError, pymysql.MySQLError) as exc:
            db.rollback()
            flash(explain(exc), "danger")
            return render_template("doctor/record_form.html", appt=ctx, meds=[], form=request.form,
                                   rows=[], mode="edit", record_id=record_id)
        flash("Đã cập nhật hồ sơ bệnh án (thay đổi được ghi vào nhật ký).", "success")
        return redirect(url_for("doctor.record", record_id=record_id))
    current = db.call("sp_read_medical_record", record_id, "DOCTOR", me())[0][0]
    db.commit()
    return render_template("doctor/record_form.html", appt=ctx, meds=[], form=current, rows=[],
                           mode="edit", record_id=record_id)


# ------------------------------------------------------------------ shifts
def _my_profile(db):
    row = db.one("SELECT spec_type FROM v_active_doctor_directory WHERE doctor_id = %s", (me(),))
    return {"spec_type": row["spec_type"] if row else None,
            "employment_type": (session.get("meta") or {}).get("employment_type")}


def _rooms(db):
    """Doctors have no grant on `room`; if the DBA adds one the dropdown appears, otherwise a
    plain room-id field is shown."""
    try:
        return db.all("SELECT room_id, room_code, floor FROM room ORDER BY room_code")
    except pymysql.MySQLError:
        db.rollback()
        return []


@bp.route("/shifts", methods=["GET", "POST"])
@role_required("doctor")
def shifts():
    db = get_db()
    prof = _my_profile(db)
    if request.method == "POST":
        s = services.build_shift(request.form, me(), prof["spec_type"], prof["employment_type"])
        services.insert_shift(db, s)
        db.commit()
        flash("Đã đăng ký ca làm việc.", "success")
        return redirect(url_for("doctor.shifts"))
    rows = db.all(
        "SELECT s.*, v.booked_count FROM shift s LEFT JOIN v_doctor_availability v ON v.shift_id = s.shift_id "
        "WHERE s.doctor_id = %s ORDER BY s.shift_date DESC, s.start_time LIMIT 100", (me(),))
    return render_template("doctor/shifts.html", shifts=rows, prof=prof, rooms=_rooms(db))


@bp.post("/shifts/<int:shift_id>/cancel")
@role_required("doctor")
def shift_cancel(shift_id):
    db = get_db()
    row = db.one("SELECT s.shift_id, s.status, COALESCE(v.booked_count, 0) AS booked "
                 "FROM shift s LEFT JOIN v_doctor_availability v ON v.shift_id = s.shift_id "
                 "WHERE s.shift_id = %s AND s.doctor_id = %s", (shift_id, me()))
    if not row:
        abort(404)
    if row["status"] == "CANCELLED":
        raise UserError("Ca này đã được hủy trước đó.")
    if row["booked"]:
        raise UserError("Ca còn lịch hẹn chưa hủy. Hãy xử lý các lịch hẹn trước khi hủy ca.")
    db.execute("UPDATE shift SET status = 'CANCELLED' WHERE shift_id = %s AND doctor_id = %s",
               (shift_id, me()))
    db.commit()
    flash("Đã hủy ca làm việc.", "success")
    return redirect(url_for("doctor.shifts"))


# ------------------------------------------------------------------ consultations
@bp.route("/consultations")
@role_required("doctor")
def consultations():
    rows = get_db().call("sp_list_my_consultations", me())[0]
    incoming = [c for c in rows if c["consulting_doctor_id"] == me()]
    outgoing = [c for c in rows if c["requesting_doctor_id"] == me()]
    return render_template("doctor/consultations.html", incoming=incoming, outgoing=outgoing)


@bp.route("/consultations/<int:request_id>")
@role_required("doctor")
def consultation(request_id):
    c = get_db().call("sp_get_consultation", request_id, me())[0][0]
    return render_template("doctor/consultation.html", c=c, me=me())


def _my_incoming(db, request_id, expected_status):
    """The request must be addressed to me and in the expected state."""
    c = db.call("sp_get_consultation", request_id, me())[0][0]
    if c["consulting_doctor_id"] != me():
        abort(403)
    if c["status"] != expected_status:
        raise UserError(f"Yêu cầu đang ở trạng thái {c['status']}, không thể thực hiện thao tác này.")
    return c


@bp.post("/consultations/<int:request_id>/approve")
@role_required("doctor")
def consultation_approve(request_id):
    db = get_db()
    _my_incoming(db, request_id, "PENDING")
    hours = integer(request.form, "hours", "thời hạn truy cập", lo=1, hi=24 * 30)
    db.execute("UPDATE consultation_request SET status = 'APPROVED', responded_at = NOW(), "
               "expires_at = DATE_ADD(NOW(), INTERVAL %s HOUR) "
               "WHERE request_id = %s AND consulting_doctor_id = %s AND status = 'PENDING'",
               (hours, request_id, me()))
    db.commit()
    flash(f"Đã chấp nhận. Bạn được xem hồ sơ trong {hours} giờ.", "success")
    return redirect(url_for("doctor.consultation", request_id=request_id))


@bp.post("/consultations/<int:request_id>/decline")
@role_required("doctor")
def consultation_decline(request_id):
    db = get_db()
    _my_incoming(db, request_id, "PENDING")
    db.execute("UPDATE consultation_request SET status = 'DECLINED', responded_at = NOW() "
               "WHERE request_id = %s AND consulting_doctor_id = %s AND status = 'PENDING'",
               (request_id, me()))
    db.commit()
    flash("Đã từ chối yêu cầu hội chẩn.", "info")
    return redirect(url_for("doctor.consultation", request_id=request_id))


@bp.post("/consultations/<int:request_id>/complete")
@role_required("doctor")
def consultation_complete(request_id):
    db = get_db()
    _my_incoming(db, request_id, "APPROVED")
    opinion = text(request.form, "opinion", required=True, label="ý kiến chuyên môn")
    db.execute("UPDATE consultation_request SET status = 'COMPLETED', opinion = %s "
               "WHERE request_id = %s AND consulting_doctor_id = %s AND status = 'APPROVED'",
               (opinion, request_id, me()))
    db.commit()
    flash("Đã gửi ý kiến. Quyền xem hồ sơ của yêu cầu này kết thúc.", "success")
    return redirect(url_for("doctor.consultation", request_id=request_id))


@bp.route("/records/<int:record_id>/consult", methods=["GET", "POST"])
@role_required("doctor")
def consultation_new(record_id):
    db = get_db()
    ctx = _record_context(db, record_id)
    if not ctx or ctx["doctor_id"] != me():
        abort(403)  # BR-23: only the treating doctor invites a colleague
    colleagues = db.all("SELECT doctor_id, full_name, spec_type, specialty_name FROM v_active_doctor_directory "
                        "WHERE doctor_id <> %s ORDER BY full_name", (me(),))
    if request.method == "POST":
        target = integer(request.form, "consulting_doctor_id", "bác sĩ được mời", lo=1)
        reason = text(request.form, "reason", required=True, label="lý do hội chẩn")
        rid = db.execute("INSERT INTO consultation_request (record_id, requesting_doctor_id, "
                         "consulting_doctor_id, reason) VALUES (%s, %s, %s, %s)",
                         (record_id, me(), target, reason))
        db.commit()
        flash("Đã gửi yêu cầu hội chẩn.", "success")
        return redirect(url_for("doctor.consultation", request_id=rid))
    return render_template("doctor/consultation_new.html", info=ctx, record_id=record_id,
                           colleagues=colleagues)


@bp.route("/medications")
@role_required("doctor")
def medications():
    q = request.args.get("q", "").strip()
    rows = get_db().all("SELECT name, unit, description FROM v_active_medication "
                        "WHERE name LIKE %s ORDER BY name LIMIT 200", (f"%{q}%",))
    return render_template("shared/medications_ro.html", rows=rows, q=q, endpoint="doctor.medications")
