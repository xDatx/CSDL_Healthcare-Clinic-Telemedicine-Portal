"""Admin portal (RECEPTIONIST / SYSTEM_ADMIN): people, schedule, rooms, medication catalog, audit.

The DB role r_admin is shared by both admin types; what each person may do depends on the
permissions in `staff_permission` (BR-20) and on the admin role, both checked here and,
for record access and permission grants, again by the database.
"""
from datetime import date

import pymysql
from flask import Blueprint, abort, flash, redirect, render_template, request, session, url_for

import auth_store
import services
from auth import has_perm, is_system_admin, role_required
from db import get_db
from errors import UserError, explain
from utils import (choice, decimal, integer, page_arg, paginate, parse_date, safe_next, text)
from flask import current_app

bp = Blueprint("admin", __name__, url_prefix="/admin")
PERMISSION_CODES = ("CREATE_DOCTOR", "MANAGE_MEDICATION", "VIEW_ALL_RECORDS", "ASSIGN_PERMISSION")


def me():
    return session["uid"]


def _new_account(role, actor_id, login, name, meta=None):
    """Create/reset the login for a person and flash the one-time password."""
    pw = auth_store.random_password()
    login = auth_store.upsert_account(role, actor_id, login, pw, name, meta)
    flash(f"Tài khoản đăng nhập: {login}  |  Mật khẩu tạm: {pw}  (chỉ hiển thị một lần).", "warning")


def _patient_login(p):
    return (p["email"] or f"patient{p['patient_id']}").lower()


# ------------------------------------------------------------------ dashboard
@bp.route("/")
@role_required("admin")
def home():
    db = get_db()
    stats = db.one(
        "SELECT (SELECT COUNT(*) FROM patient) AS patients, "
        "       (SELECT COUNT(*) FROM doctor WHERE is_active = TRUE) AS doctors, "
        "       (SELECT COUNT(*) FROM v_appointment_detail WHERE appointment_date = CURDATE()) AS today, "
        "       (SELECT COUNT(*) FROM v_appointment_detail WHERE status = 'PENDING') AS pending")
    pending = db.all("SELECT * FROM v_appointment_detail WHERE status = 'PENDING' "
                     "ORDER BY start_time LIMIT 10")
    return render_template("admin/home.html", stats=stats, pending=pending)


# ------------------------------------------------------------------ patients
@bp.route("/patients")
@role_required("admin")
def patients():
    q = request.args.get("q", "").strip()
    where, args = "", []
    if q:
        where = "WHERE full_name LIKE %s OR phone LIKE %s OR email LIKE %s"
        args = [f"%{q}%"] * 3
    data = paginate(get_db(),
                    f"SELECT patient_id, full_name, dob, phone, email FROM patient {where} "
                    f"ORDER BY patient_id DESC",
                    f"SELECT COUNT(*) FROM patient {where}", args, page_arg(), current_app.config["PAGE_SIZE"])
    return render_template("admin/patients.html", data=data, q=q)


def _patient_values(form):
    phone, email = text(form, "phone", max_len=20), text(form, "email", max_len=120, label="email")
    if not phone and not email:
        raise UserError("Cần ít nhất số điện thoại hoặc email.")
    return (text(form, "full_name", True, "họ tên", 100), parse_date(form.get("dob"), "ngày sinh"),
            phone, email, text(form, "address"))


@bp.route("/patients/new", methods=["GET", "POST"])
@role_required("admin")
def patient_new():
    if request.method == "POST":
        db = get_db()
        vals = _patient_values(request.form)
        pid = db.execute("INSERT INTO patient (full_name, dob, phone, email, address) "
                         "VALUES (%s, %s, %s, %s, %s)", vals)
        db.commit()
        p = {"patient_id": pid, "email": vals[3]}
        _new_account("patient", pid, _patient_login(p), vals[0])
        flash("Đã tạo hồ sơ bệnh nhân.", "success")
        return redirect(url_for("admin.patient_detail", patient_id=pid))
    return render_template("admin/patient_form.html", p={}, mode="new")


@bp.route("/patients/<int:patient_id>")
@role_required("admin")
def patient_detail(patient_id):
    db = get_db()
    p = db.one("SELECT * FROM patient WHERE patient_id = %s", (patient_id,))
    if not p:
        abort(404)
    appts = db.all("SELECT * FROM v_appointment_detail WHERE patient_id = %s "
                   "ORDER BY start_time DESC LIMIT 100", (patient_id,))
    return render_template("admin/patient_detail.html", p=p, appts=appts)


@bp.route("/patients/<int:patient_id>/edit", methods=["GET", "POST"])
@role_required("admin")
def patient_edit(patient_id):
    db = get_db()
    p = db.one("SELECT * FROM patient WHERE patient_id = %s", (patient_id,))
    if not p:
        abort(404)
    if request.method == "POST":
        vals = _patient_values(request.form)
        db.execute("UPDATE patient SET full_name=%s, dob=%s, phone=%s, email=%s, address=%s "
                   "WHERE patient_id=%s", (*vals, patient_id))
        db.commit()
        flash("Đã cập nhật thông tin bệnh nhân.", "success")
        return redirect(url_for("admin.patient_detail", patient_id=patient_id))
    return render_template("admin/patient_form.html", p=p, mode="edit")


@bp.post("/patients/<int:patient_id>/account")
@role_required("admin")
def patient_account(patient_id):
    p = get_db().one("SELECT patient_id, full_name, email FROM patient WHERE patient_id = %s", (patient_id,))
    if not p:
        abort(404)
    _new_account("patient", patient_id, _patient_login(p), p["full_name"])
    return redirect(url_for("admin.patient_detail", patient_id=patient_id))


@bp.route("/patients/<int:patient_id>/book", methods=["GET", "POST"])
@role_required("admin")
def patient_book(patient_id):
    db = get_db()
    p = db.one("SELECT patient_id, full_name FROM patient WHERE patient_id = %s", (patient_id,))
    if not p:
        abort(404)
    if request.method == "POST":
        aid = services.book_appointment(db, patient_id, request.form)
        flash(f"Đã đặt lịch hẹn #{aid} cho {p['full_name']}.", "success")
        return redirect(url_for("admin.patient_detail", patient_id=patient_id))
    shifts = db.all("SELECT * FROM v_doctor_availability WHERE free_minutes > 0 AND shift_date >= CURDATE() "
                    "ORDER BY shift_date, shift_start, doctor_name LIMIT 200")
    return render_template("admin/book.html", p=p, shifts=shifts)


# ------------------------------------------------------------------ appointments
@bp.route("/appointments")
@role_required("admin")
def appointments():
    status = request.args.get("status", "")
    day = request.args.get("date", "")
    q = request.args.get("q", "").strip()
    where, args = ["1 = 1"], []
    if status in ("PENDING", "CONFIRMED", "IN_PROGRESS", "COMPLETED", "CANCELLED"):
        where.append("status = %s")
        args.append(status)
    if day:
        where.append("appointment_date = %s")
        args.append(parse_date(day))
    if q:
        where.append("(patient_name LIKE %s OR doctor_name LIKE %s)")
        args += [f"%{q}%"] * 2
    w = " AND ".join(where)
    data = paginate(get_db(), f"SELECT * FROM v_appointment_detail WHERE {w} ORDER BY start_time DESC",
                    f"SELECT COUNT(*) FROM v_appointment_detail WHERE {w}", args, page_arg(),
                    current_app.config["PAGE_SIZE"])
    return render_template("admin/appointments.html", data=data, status=status, day=day, q=q)


@bp.post("/appointments/<int:appointment_id>/status")
@role_required("admin")
def appointment_status(appointment_id):
    new = choice(request.form, "status", ("CONFIRMED", "CANCELLED"), "trạng thái")
    db = get_db()
    db.execute("UPDATE appointment SET status = %s WHERE appointment_id = %s", (new, appointment_id))
    if db.rowcount == 0:
        raise UserError("Không tìm thấy lịch hẹn.")
    db.commit()
    flash(f"Lịch hẹn #{appointment_id} đã chuyển sang {new}.", "success")
    return safe_next("admin.appointments")


# ------------------------------------------------------------------ doctors
@bp.route("/doctors")
@role_required("admin")
def doctors():
    rows = get_db().all(
        "SELECT d.doctor_id, d.full_name, d.email, d.license_no, d.employment_type, d.spec_type, d.is_active, "
        "       sp.name AS specialty, s.years_practice "
        "FROM doctor d LEFT JOIN specialist s ON s.doctor_id = d.doctor_id "
        "LEFT JOIN specialty sp ON sp.specialty_id = s.specialty_id ORDER BY d.is_active DESC, d.full_name")
    return render_template("admin/doctors.html", doctors=rows)


@bp.route("/doctors/new", methods=["GET", "POST"])
@role_required("admin", perm="CREATE_DOCTOR")
def doctor_new():
    db = get_db()
    specialties = db.all("SELECT specialty_id, name FROM specialty ORDER BY name")
    if request.method == "POST":
        try:
            f = request.form
            name = text(f, "full_name", True, "họ tên", 100)
            email = text(f, "email", True, "email", 120).lower()
            license_no = text(f, "license_no", True, "số giấy phép", 50)
            emp = choice(f, "employment_type", ("FULL_TIME", "PART_TIME"), "loại hợp đồng")
            spec = choice(f, "spec_type", ("GP", "SPECIALIST"), "loại bác sĩ")
            did = db.execute(
                "INSERT INTO doctor (full_name, email, license_no, employment_type, spec_type, is_active, created_by) "
                "VALUES (%s, %s, %s, %s, %s, FALSE, %s)", (name, email, license_no, emp, spec, me()))
            if spec == "GP":
                db.execute("INSERT INTO gp (doctor_id) VALUES (%s)", (did,))
            else:
                db.execute("INSERT INTO specialist (doctor_id, specialty_id, years_practice) VALUES (%s, %s, %s)",
                           (did, integer(f, "specialty_id", "chuyên khoa", lo=1),
                            integer(f, "years_practice", "số năm hành nghề", lo=0, hi=70)))
            db.execute("UPDATE doctor SET is_active = TRUE WHERE doctor_id = %s", (did,))  # BR-01 checks the subtype row
            db.commit()
        except (UserError, pymysql.MySQLError) as exc:
            db.rollback()
            flash(explain(exc), "danger")
            return render_template("admin/doctor_form.html", specialties=specialties, form=request.form)
        _new_account("doctor", did, email, name, {"spec_type": spec, "employment_type": emp})
        flash("Đã tạo và kích hoạt bác sĩ.", "success")
        return redirect(url_for("admin.doctors"))
    return render_template("admin/doctor_form.html", specialties=specialties, form={})


@bp.post("/doctors/<int:doctor_id>/toggle")
@role_required("admin", perm="CREATE_DOCTOR")
def doctor_toggle(doctor_id):
    db = get_db()
    row = db.one("SELECT is_active FROM doctor WHERE doctor_id = %s", (doctor_id,))
    if not row:
        abort(404)
    db.execute("UPDATE doctor SET is_active = %s WHERE doctor_id = %s", (not row["is_active"], doctor_id))
    db.commit()
    auth_store.set_active("doctor", doctor_id, not row["is_active"])
    flash("Đã kích hoạt bác sĩ." if not row["is_active"] else "Đã ngừng hoạt động bác sĩ.", "success")
    return redirect(url_for("admin.doctors"))


@bp.post("/doctors/<int:doctor_id>/account")
@role_required("admin", perm="CREATE_DOCTOR")
def doctor_account(doctor_id):
    d = get_db().one("SELECT doctor_id, full_name, email, spec_type, employment_type FROM doctor "
                     "WHERE doctor_id = %s", (doctor_id,))
    if not d:
        abort(404)
    _new_account("doctor", doctor_id, d["email"], d["full_name"],
                 {"spec_type": d["spec_type"], "employment_type": d["employment_type"]})
    return redirect(url_for("admin.doctors"))


# ------------------------------------------------------------------ rooms & specialties
@bp.route("/catalog")
@role_required("admin")
def catalog():
    db = get_db()
    return render_template("admin/catalog.html",
                           rooms=db.all("SELECT * FROM room ORDER BY room_code"),
                           specialties=db.all("SELECT * FROM specialty ORDER BY name"))


@bp.post("/rooms")
@role_required("admin")
def room_add():
    db = get_db()
    db.execute("INSERT INTO room (room_code, floor) VALUES (%s, %s)",
               (text(request.form, "room_code", True, "mã phòng", 20),
                integer(request.form, "floor", "tầng", lo=1, hi=20)))
    db.commit()
    flash("Đã thêm phòng.", "success")
    return redirect(url_for("admin.catalog"))


@bp.post("/specialties")
@role_required("admin")
def specialty_add():
    db = get_db()
    db.execute("INSERT INTO specialty (name) VALUES (%s)", (text(request.form, "name", True, "tên chuyên khoa", 80),))
    db.commit()
    flash("Đã thêm chuyên khoa.", "success")
    return redirect(url_for("admin.catalog"))


# ------------------------------------------------------------------ shifts
@bp.route("/shifts", methods=["GET", "POST"])
@role_required("admin")
def shifts():
    db = get_db()
    if request.method == "POST":
        doc = db.one("SELECT doctor_id, spec_type, employment_type FROM doctor "
                     "WHERE doctor_id = %s AND is_active = TRUE", (integer(request.form, "doctor_id", "bác sĩ"),))
        if not doc:
            raise UserError("Bác sĩ không tồn tại hoặc đã ngừng hoạt động.")
        s = services.build_shift(request.form, doc["doctor_id"], doc["spec_type"], doc["employment_type"])
        services.insert_shift(db, s)
        db.commit()
        flash("Đã tạo ca làm việc.", "success")
        return redirect(url_for("admin.shifts"))
    show_all = request.args.get("all") == "1"
    where = "" if show_all else "WHERE s.shift_date >= CURDATE() - INTERVAL 7 DAY"
    rows = db.all(
        "SELECT s.*, d.full_name AS doctor_name, d.spec_type, r.room_code, COALESCE(v.booked_count, 0) AS booked "
        "FROM shift s JOIN doctor d ON d.doctor_id = s.doctor_id LEFT JOIN room r ON r.room_id = s.room_id "
        f"LEFT JOIN v_doctor_availability v ON v.shift_id = s.shift_id {where} "
        "ORDER BY s.shift_date DESC, s.start_time LIMIT 300")
    return render_template("admin/shifts.html", shifts=rows, show_all=show_all,
                           doctors=db.all("SELECT doctor_id, full_name, spec_type, employment_type "
                                          "FROM doctor WHERE is_active = TRUE ORDER BY full_name"),
                           rooms=db.all("SELECT room_id, room_code FROM room ORDER BY room_code"))


@bp.post("/shifts/<int:shift_id>/cancel")
@role_required("admin")
def shift_cancel(shift_id):
    db = get_db()
    row = db.one("SELECT s.status, COALESCE(v.booked_count, 0) AS booked FROM shift s "
                 "LEFT JOIN v_doctor_availability v ON v.shift_id = s.shift_id WHERE s.shift_id = %s", (shift_id,))
    if not row:
        abort(404)
    if row["status"] == "CANCELLED":
        raise UserError("Ca này đã được hủy trước đó.")
    if row["booked"]:
        raise UserError("Ca còn lịch hẹn chưa hủy. Hãy xử lý các lịch hẹn trước khi hủy ca.")
    db.execute("UPDATE shift SET status = 'CANCELLED' WHERE shift_id = %s", (shift_id,))
    db.commit()
    flash("Đã hủy ca làm việc.", "success")
    return redirect(url_for("admin.shifts"))


# ------------------------------------------------------------------ medication catalog (BR-19, BR-25)
@bp.route("/medications")
@role_required("admin", perm="MANAGE_MEDICATION")
def medications():
    q = request.args.get("q", "").strip()
    rows = get_db().all("SELECT * FROM medication WHERE name LIKE %s ORDER BY is_active DESC, name LIMIT 300",
                        (f"%{q}%",))
    return render_template("admin/medications.html", rows=rows, q=q, edit=None)


@bp.route("/medications/<int:medication_id>/edit", methods=["GET", "POST"])
@role_required("admin", perm="MANAGE_MEDICATION")
def medication_edit(medication_id):
    db = get_db()
    med = db.one("SELECT * FROM medication WHERE medication_id = %s", (medication_id,))
    if not med:
        abort(404)
    if request.method == "POST":
        db.execute("UPDATE medication SET name=%s, unit=%s, description=%s WHERE medication_id=%s",
                   (text(request.form, "name", True, "tên thuốc", 120), text(request.form, "unit", True, "đơn vị", 20),
                    text(request.form, "description"), medication_id))
        db.commit()
        flash("Đã cập nhật thuốc (ghi vào nhật ký danh mục).", "success")
        return redirect(url_for("admin.medications"))
    return render_template("admin/medications.html", rows=[], q="", edit=med)


@bp.post("/medications")
@role_required("admin", perm="MANAGE_MEDICATION")
def medication_add():
    db = get_db()
    db.execute("INSERT INTO medication (name, unit, description) VALUES (%s, %s, %s)",
               (text(request.form, "name", True, "tên thuốc", 120), text(request.form, "unit", True, "đơn vị", 20),
                text(request.form, "description")))
    db.commit()
    flash("Đã thêm thuốc vào danh mục.", "success")
    return redirect(url_for("admin.medications"))


@bp.post("/medications/<int:medication_id>/toggle")
@role_required("admin", perm="MANAGE_MEDICATION")
def medication_toggle(medication_id):
    db = get_db()
    row = db.one("SELECT is_active FROM medication WHERE medication_id = %s", (medication_id,))
    if not row:
        abort(404)
    db.execute("UPDATE medication SET is_active = %s WHERE medication_id = %s", (not row["is_active"], medication_id))
    db.commit()
    flash("Đã ngừng sử dụng thuốc." if row["is_active"] else "Đã kích hoạt lại thuốc.", "success")
    return redirect(url_for("admin.medications"))


# ------------------------------------------------------------------ permissions & staff (BR-20)
@bp.route("/permissions")
@role_required("admin")
def permissions():
    if not is_system_admin():
        abort(403)
    db = get_db()
    staff = db.all("SELECT admin_id, full_name, email, role, is_active FROM admin ORDER BY admin_id")
    grants = {}
    for g in db.all("SELECT sp.admin_id, sp.permission_code, sp.granted_at, a.full_name AS granted_by_name "
                    "FROM staff_permission sp JOIN admin a ON a.admin_id = sp.granted_by ORDER BY sp.permission_code"):
        grants.setdefault(g["admin_id"], []).append(g)
    return render_template("admin/permissions.html", staff=staff, grants=grants, codes=PERMISSION_CODES)


@bp.post("/permissions/grant")
@role_required("admin", perm="ASSIGN_PERMISSION")
def permission_grant():
    db = get_db()
    target = integer(request.form, "admin_id", "nhân sự", lo=1)
    code = choice(request.form, "permission_code", PERMISSION_CODES, "quyền")
    db.execute("INSERT INTO staff_permission (admin_id, permission_code, granted_by) VALUES (%s, %s, %s)",
               (target, code, me()))
    db.commit()
    flash(f"Đã cấp quyền {code}.", "success")
    return redirect(url_for("admin.permissions"))


@bp.post("/staff")
@role_required("admin", perm="ASSIGN_PERMISSION")
def staff_add():
    db = get_db()
    name = text(request.form, "full_name", True, "họ tên", 100)
    email = text(request.form, "email", True, "email", 120).lower()
    role = choice(request.form, "role", ("RECEPTIONIST", "SYSTEM_ADMIN"), "vai trò")
    aid = db.execute("INSERT INTO admin (full_name, email, role) VALUES (%s, %s, %s)", (name, email, role))
    db.commit()
    _new_account("admin", aid, email, name, {"role": role})
    flash("Đã thêm nhân sự quản trị.", "success")
    return redirect(url_for("admin.permissions"))


# ------------------------------------------------------------------ medical records & audit (NFR-04)
@bp.route("/records/<int:record_id>")
@role_required("admin")
def record(record_id):
    """Needs VIEW_ALL_RECORDS - checked inside fn_can_read_record, not only here (BR-20)."""
    db = get_db()
    sets = db.call("sp_read_medical_record", record_id, "ADMIN", me())
    db.commit()
    return render_template("shared/record.html", rec=sets[0][0], items=sets[1],
                           back=url_for("admin.audit"), info=None, can_edit=False)


@bp.route("/audit")
@role_required("admin")
def audit():
    if not is_system_admin():
        abort(403)
    db, kind = get_db(), request.args.get("kind", "record")
    per = current_app.config["PAGE_SIZE"] * 2
    if kind == "medication":
        data = paginate(db,
                        "SELECT a.audit_id, a.medication_id, m.name AS medication_name, ad.full_name AS admin_name, "
                        "a.action, a.action_at, a.old_values, a.new_values FROM medication_audit_log a "
                        "JOIN medication m ON m.medication_id = a.medication_id "
                        "JOIN admin ad ON ad.admin_id = a.admin_id ORDER BY a.audit_id DESC",
                        "SELECT COUNT(*) FROM medication_audit_log", [], page_arg(), per)
        return render_template("admin/audit.html", kind=kind, data=data, record_id="", action="")
    where, args = ["1 = 1"], []
    rid = request.args.get("record_id", "").strip()
    action = request.args.get("action", "")
    if rid.isdigit():
        where.append("a.record_id = %s")
        args.append(int(rid))
    if action in ("INSERT", "UPDATE", "SELECT"):
        where.append("a.action = %s")
        args.append(action)
    w = " AND ".join(where)
    data = paginate(db,
                    "SELECT a.audit_id, a.record_id, a.action, a.action_at, a.details, "
                    "CASE WHEN a.patient_id IS NOT NULL THEN 'PATIENT' WHEN a.doctor_id IS NOT NULL THEN 'DOCTOR' "
                    "ELSE 'ADMIN' END AS actor_type, COALESCE(p.full_name, d.full_name, ad.full_name) AS actor_name "
                    "FROM medical_record_audit_log a LEFT JOIN patient p ON p.patient_id = a.patient_id "
                    "LEFT JOIN doctor d ON d.doctor_id = a.doctor_id LEFT JOIN admin ad ON ad.admin_id = a.admin_id "
                    f"WHERE {w} ORDER BY a.audit_id DESC",
                    f"SELECT COUNT(*) FROM medical_record_audit_log a WHERE {w}", args, page_arg(), per)
    return render_template("admin/audit.html", kind="record", data=data, record_id=rid, action=action)


# ------------------------------------------------------------------ part-time pay (BR-24)
@bp.route("/pay")
@role_required("admin")
def pay():
    month = request.args.get("month") or date.today().strftime("%Y-%m")
    first = parse_date(month + "-01", "tháng")
    last = date(first.year + (first.month == 12), first.month % 12 + 1, 1)
    rows = get_db().all("SELECT * FROM v_part_time_pay WHERE shift_date >= %s AND shift_date < %s "
                        "ORDER BY doctor_name, shift_date", (first, last))
    totals = {}
    for r in rows:
        t = totals.setdefault(r["doctor_id"], {"name": r["doctor_name"], "hours": 0, "pay": 0})
        t["hours"] += r["hours_worked"]
        t["pay"] += r["shift_pay"]
    return render_template("admin/pay.html", rows=rows, totals=list(totals.values()), month=month)
