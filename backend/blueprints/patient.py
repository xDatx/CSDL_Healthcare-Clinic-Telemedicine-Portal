"""Patient portal. Every call passes the id of the LOGGED-IN patient (session), never a value from the request."""
from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from datetime import date

import auth_store
import services
from auth import role_required
from db import get_db
from errors import UserError
from utils import parse_date, text

bp = Blueprint("patient", __name__, url_prefix="/patient")


@bp.route("/")
@role_required("patient")
def home():
    appts = get_db().call("sp_patient_appointments", session["uid"])[0]
    active = [a for a in appts if a["status"] in ("PENDING", "CONFIRMED", "IN_PROGRESS")]
    return render_template("patient/home.html", upcoming=active[::-1][:5], total=len(appts))


@bp.route("/doctors")
@role_required("patient")
def doctors():
    q = request.args.get("q", "").strip()
    spec = request.args.get("spec", "")
    show_all = request.args.get("all") == "1"
    sql, args = "SELECT * FROM v_doctor_availability WHERE free_minutes > 0", []
    if not show_all:
        sql += " AND shift_date >= CURDATE()"
    if q:
        sql += " AND doctor_name LIKE %s"
        args.append(f"%{q}%")
    if spec in ("GP", "SPECIALIST"):
        sql += " AND spec_type = %s"
        args.append(spec)
    shifts = get_db().all(sql + " ORDER BY shift_date, shift_start, doctor_name LIMIT 200", args)
    return render_template("patient/doctors.html", shifts=shifts, q=q, spec=spec, show_all=show_all)


@bp.post("/book")
@role_required("patient")
def book():
    db = get_db()
    appt_id = services.book_appointment(db, session["uid"], request.form)
    flash(f"Đã đặt lịch hẹn #{appt_id}. Lịch đang chờ xác nhận (PENDING).", "success")
    return redirect(url_for("patient.appointments"))


@bp.route("/appointments")
@role_required("patient")
def appointments():
    rows = get_db().call("sp_patient_appointments", session["uid"])[0]
    return render_template("patient/appointments.html", appts=rows)


@bp.post("/appointments/<int:appointment_id>/cancel")
@role_required("patient")
def cancel(appointment_id):
    db = get_db()
    db.call("sp_cancel_appointment", session["uid"], appointment_id)
    db.commit()
    flash("Đã hủy lịch hẹn.", "success")
    return redirect(url_for("patient.appointments"))


@bp.route("/history")
@role_required("patient")
def history():
    """sp_patient_history writes one audit row per record it returns (NFR-04), so commit."""
    db = get_db()
    rows = db.call("sp_patient_history", session["uid"])[0]
    db.commit()
    return render_template("patient/history.html", rows=rows)


@bp.route("/records/<int:record_id>")
@role_required("patient")
def record(record_id):
    db = get_db()
    sets = db.call("sp_read_medical_record", record_id, "PATIENT", session["uid"])
    db.commit()
    return render_template("shared/record.html", rec=sets[0][0], items=sets[1],
                           back=url_for("patient.history"), info=None, can_edit=False)


@bp.route("/profile", methods=["GET", "POST"])
@role_required("patient")
def profile():
    """FR-01: the patient maintains his / her own demographic and contact data (sp_get/update_my_profile)."""
    db = get_db()
    if request.method == "POST":
        phone, email = text(request.form, "phone", max_len=20, label="số điện thoại"), text(request.form, "email", max_len=120, label="email")
        if not phone and not email:
            raise UserError("Cần ít nhất số điện thoại hoặc email.")
        dob = parse_date(request.form.get("dob"), "ngày sinh")
        if dob > date.today():
            raise UserError("Ngày sinh không được ở tương lai.")
        name = text(request.form, "full_name", True, "họ tên", 100)
        db.call("sp_update_my_profile", session["uid"], name, dob, phone, email, text(request.form, "address"))
        db.commit()
        auth_store.set_display_name("patient", session["uid"], name)
        session["name"] = name
        flash("Đã cập nhật hồ sơ cá nhân.", "success")
        return redirect(url_for("patient.profile"))
    sets = db.call("sp_get_my_profile", session["uid"])
    return render_template("patient/profile.html", p=sets[0][0])


@bp.route("/medications")
@role_required("patient")
def medications():
    q = request.args.get("q", "").strip()
    rows = get_db().all("SELECT name, unit, description FROM v_active_medication "
                        "WHERE name LIKE %s ORDER BY name LIMIT 200", (f"%{q}%",))
    return render_template("shared/medications_ro.html", rows=rows, q=q,
                           endpoint="patient.medications")
