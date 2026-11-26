"""Logic shared by more than one portal: booking, clinical-record form parsing, shift creation."""
from datetime import datetime, timedelta

from errors import UserError
from utils import choice, decimal, integer, parse_date, parse_time, text

APPT_TYPES = ("IN_PERSON", "TELEMEDICINE")


def book_appointment(db, patient_id, form):
    """FR-03: book through sp_book_appointment. BR-08 / BR-09 / BR-11 are enforced by the triggers."""
    shift_id = integer(form, "shift_id", "ca khám")
    shift = db.one("SELECT shift_id, shift_date, shift_start, shift_end FROM v_doctor_availability "
                   "WHERE shift_id = %s", (shift_id,))
    if not shift:
        raise UserError("Ca khám không tồn tại hoặc đã đóng.")
    start_t = parse_time(form.get("start_time"), "giờ bắt đầu")
    minutes = integer(form, "minutes", "thời lượng", lo=10, hi=240)
    kind = choice(form, "appointment_type", APPT_TYPES, "hình thức khám")
    start = datetime.combine(shift["shift_date"], start_t)
    end = start + timedelta(minutes=minutes)
    sets = db.call("sp_book_appointment", patient_id, shift_id, start, end, kind)
    db.commit()
    return sets[0][0]["appointment_id"]


# ------------------------------------------------------------------ medical record
def parse_record_form(form):
    """Validate the vitals / text part of a medical record (mirrors the CHECKs of 06_medical_record)."""
    sys_bp = integer(form, "systolic_bp", "huyết áp tâm thu", required=False, lo=60, hi=250)
    dia_bp = integer(form, "diastolic_bp", "huyết áp tâm trương", required=False, lo=30, hi=150)
    if sys_bp is not None and dia_bp is not None and dia_bp >= sys_bp:
        raise UserError("Huyết áp tâm trương phải nhỏ hơn tâm thu.")
    return {
        "systolic_bp": sys_bp,
        "diastolic_bp": dia_bp,
        "heart_rate": integer(form, "heart_rate", "nhịp tim", required=False, lo=20, hi=250),
        "temperature_c": decimal(form, "temperature_c", "nhiệt độ", required=False, lo=30, hi=45),
        "oxygen_saturation": integer(form, "oxygen_saturation", "SpO2", required=False, lo=50, hi=100),
        "symptoms": text(form, "symptoms"),
        "diagnosis": text(form, "diagnosis", required=True, label="chẩn đoán"),
        "notes": text(form, "notes"),
    }


def parse_prescription_rows(form):
    """Prescription lines posted as parallel lists. Blank rows are skipped."""
    meds = form.getlist("medication_id")
    rows, seen = [], set()
    for i, med in enumerate(meds):
        if not med.strip():
            continue
        try:
            med_id = int(med)
        except ValueError:
            raise UserError("Thuốc không hợp lệ.")
        if med_id in seen:
            raise UserError("Mỗi loại thuốc chỉ xuất hiện một lần trong đơn (BR-16).")
        seen.add(med_id)

        def at(name):
            lst = form.getlist(name)
            return (lst[i] if i < len(lst) else "").strip()

        qty, days = at("quantity"), at("duration_days")
        dosage, freq = at("dosage"), at("frequency")
        if not (qty.isdigit() and int(qty) > 0):
            raise UserError("Số lượng thuốc phải là số nguyên dương.")
        if not (days.isdigit() and int(days) > 0):
            raise UserError("Số ngày dùng thuốc phải là số nguyên dương.")
        if not dosage or not freq:
            raise UserError("Mỗi thuốc cần có liều dùng và tần suất.")
        rows.append({"medication_id": med_id, "quantity": int(qty), "dosage": dosage[:120],
                     "frequency": freq[:120], "duration_days": int(days)})
    return rows


RECORD_COLS = ("systolic_bp", "diastolic_bp", "heart_rate", "temperature_c",
               "oxygen_saturation", "symptoms", "diagnosis", "notes")


# ------------------------------------------------------------------ shifts
def build_shift(form, doctor_id, spec_type, employment_type):
    """Read a shift form. The room / rate fields are adjusted to the doctor type (BR-03, BR-24, BR-26)
    so the user is not asked for something the rule forbids; the triggers still have the last word."""
    date_ = parse_date(form.get("shift_date"), "ngày làm")
    start = parse_time(form.get("start_time"), "giờ bắt đầu")
    end = parse_time(form.get("end_time"), "giờ kết thúc")
    if end <= start:
        raise UserError("Giờ kết thúc phải sau giờ bắt đầu.")
    room_id = integer(form, "room_id", "phòng", required=False, lo=1)
    rate = decimal(form, "rate_per_hour", "đơn giá theo giờ", required=False, lo=1)
    if spec_type == "SPECIALIST":
        room_id = None
    if employment_type == "FULL_TIME":
        rate = None
    return {"doctor_id": doctor_id, "shift_date": date_, "start_time": start, "end_time": end,
            "room_id": room_id, "rate_per_hour": rate}


def insert_shift(db, s):
    return db.execute(
        "INSERT INTO shift (doctor_id, shift_date, start_time, end_time, room_id, rate_per_hour) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        (s["doctor_id"], s["shift_date"], s["start_time"], s["end_time"], s["room_id"], s["rate_per_hour"]))
