"""Write-path tests that leave the database untouched.

`Db.commit` is replaced by a no-op, so every request runs its INSERT/UPDATE against MySQL (privileges,
triggers, CHECKs all execute) and is rolled back when the request ends. Each request is therefore
tested on its own: POST routes are asserted by status code / flashed message, not by follow-up reads.
"""
import re

import pytest

import auth_store
from db import Db
from helpers import text


@pytest.fixture(autouse=True)
def no_persist(monkeypatch):
    monkeypatch.setattr(Db, "commit", lambda self: None)
    monkeypatch.setattr(auth_store, "upsert_account", lambda role, actor_id, login, *a, **k: login)


def flashes(client):
    with client.session_transaction() as s:
        return [m for _cat, m in s.get("_flashes", [])]


def ok(resp):
    assert resp.status_code == 302, text(resp)[:300]


def doctor_record_ids(client):
    return [int(x) for x in re.findall(r"/doctor/records/(\d+)", text(client.get("/doctor/appointments?scope=all")))]


# ------------------------------------------------------------------ doctor
def test_doctor_creates_record_with_prescription(doctor1):
    r = doctor1.post("/doctor/appointments/3/record/new", data={
        "systolic_bp": 120, "diastolic_bp": 80, "heart_rate": 72, "temperature_c": "36.8", "oxygen_saturation": 98,
        "symptoms": "Ho nhẹ", "diagnosis": "Viêm họng cấp", "notes": "Tái khám sau 5 ngày",
        "medication_id": ["1", "2", ""], "quantity": ["10", "5", ""], "dosage": ["1 viên", "1 gói", ""],
        "frequency": ["2 lần/ngày", "1 lần/ngày", ""], "duration_days": ["5", "5", ""]})
    ok(r)


def test_record_rejects_duplicate_medication(doctor1):
    r = doctor1.post("/doctor/appointments/3/record/new", data={
        "diagnosis": "x", "medication_id": ["1", "1"], "quantity": ["1", "1"], "dosage": ["a", "a"],
        "frequency": ["b", "b"], "duration_days": ["1", "1"]})
    assert r.status_code == 200 and "BR-16" in text(r)


def test_record_rejects_bad_vitals(doctor1):
    r = doctor1.post("/doctor/appointments/3/record/new", data={"diagnosis": "x", "systolic_bp": 120, "diastolic_bp": 130})
    assert r.status_code == 200 and "tâm trương" in text(r)


def test_record_only_for_own_appointment(doctor1):
    assert doctor1.get("/doctor/appointments/29/record/new").status_code == 404  # belongs to doctor 7


def test_record_needs_completed_appointment(doctor1):
    r = doctor1.get("/doctor/appointments/40/record/new")  # CONFIRMED
    assert r.status_code == 400 and "COMPLETED" in text(r)


def test_doctor_status_transition_and_rules(doctor1):
    ok(doctor1.post("/doctor/appointments/40/status", data={"status": "IN_PROGRESS"}))
    assert "IN_PROGRESS" in flashes(doctor1)[-1]
    # CONFIRMED -> COMPLETED skips a step: trigger BR-11
    doctor1.post("/doctor/appointments/40/status", data={"status": "COMPLETED"})
    assert "BR-11" in flashes(doctor1)[-1]
    # someone else's appointment
    assert doctor1.post("/doctor/appointments/29/status", data={"status": "CANCELLED"}).status_code == 404


def test_doctor_edits_own_record_only(doctor1, doctor4):
    ids = doctor_record_ids(doctor1)
    assert ids
    ok(doctor1.post(f"/doctor/records/{ids[0]}/edit", data={"diagnosis": "Cập nhật chẩn đoán", "notes": "ghi chú"}))
    assert doctor4.get(f"/doctor/records/{ids[0]}/edit").status_code in (403, 400)


def test_doctor_consultation_request_and_response(doctor1, doctor4):
    rid = doctor_record_ids(doctor1)[0]
    ok(doctor1.post(f"/doctor/records/{rid}/consult", data={"consulting_doctor_id": 4, "reason": "Cần ý kiến tim mạch"}))
    # doctor 4 is not treating this record -> cannot invite on it
    assert doctor4.get(f"/doctor/records/{rid}/consult").status_code == 403
    # request 3 is PENDING for doctor 4
    ok(doctor4.post("/doctor/consultations/3/approve", data={"hours": 48}))
    ok(doctor4.post("/doctor/consultations/3/decline"))
    # request 2 is addressed to doctor 1 -> doctor 4 must not touch it
    assert doctor4.post("/doctor/consultations/2/approve", data={"hours": 1}).status_code in (400, 403)
    # request 5 is APPROVED for doctor 4 -> opinion allowed
    ok(doctor4.post("/doctor/consultations/5/complete", data={"opinion": "Đồng ý phác đồ hiện tại."}))


def test_consultation_detail_only_for_parties(doctor1, doctor4):
    assert doctor4.get("/doctor/consultations/3").status_code == 200
    assert doctor1.get("/doctor/consultations/3").status_code == 400  # BR-22: not a party


def test_consulting_doctor_reads_record_through_approved_request(doctor1):
    """Request 2 (record 19) is APPROVED for doctor 1 - if still inside its window the record opens."""
    r = doctor1.get("/doctor/records/19")
    assert r.status_code in (200, 400)
    if r.status_code == 400:
        assert "BR-22" in text(r) or "NFR-02" in text(r)


def test_doctor_registers_shift(doctor1):
    ok(doctor1.post("/doctor/shifts", data={"shift_date": "2027-03-01", "start_time": "08:00", "end_time": "12:00", "room_id": 1}))
    # overlapping with the one just made is not visible (rolled back) - but a GP shift without room must fail
    doctor1.post("/doctor/shifts", data={"shift_date": "2027-03-02", "start_time": "08:00", "end_time": "12:00"})
    assert "BR-03" in flashes(doctor1)[-1]


# ------------------------------------------------------------------ admin
def test_admin_creates_patient(receptionist):
    ok(receptionist.post("/admin/patients/new", data={"full_name": "Test Patient", "dob": "1990-01-01", "phone": "0900000000"}))
    receptionist.post("/admin/patients/new", data={"full_name": "No Contact", "dob": "1990-01-01"})
    assert "ít nhất" in flashes(receptionist)[-1]


def test_admin_creates_doctors(sysadmin):
    base = {"full_name": "BS Test", "license_no": "LIC-TEST-1", "employment_type": "FULL_TIME"}
    ok(sysadmin.post("/admin/doctors/new", data={**base, "email": "gp.test@clinic.local", "spec_type": "GP"}))
    ok(sysadmin.post("/admin/doctors/new", data={**base, "license_no": "LIC-TEST-2", "email": "sp.test@clinic.local",
                                                 "spec_type": "SPECIALIST", "specialty_id": 1, "years_practice": 5}))


def test_admin_cannot_create_doctor_without_permission(receptionist):
    assert receptionist.post("/admin/doctors/new", data={}).status_code == 403


def test_admin_shift_adapts_to_doctor_type(sysadmin):
    # doctor 4 is a SPECIALIST: a room in the form is ignored (BR-26); doctor 1 GP full-time: rate ignored
    ok(sysadmin.post("/admin/shifts", data={"doctor_id": 4, "shift_date": "2027-03-03", "start_time": "08:00",
                                           "end_time": "10:00", "room_id": 1}))
    ok(sysadmin.post("/admin/shifts", data={"doctor_id": 1, "shift_date": "2027-03-03", "start_time": "08:00",
                                           "end_time": "10:00", "room_id": 1, "rate_per_hour": 100000}))


def test_admin_catalog_and_medication(sysadmin):
    ok(sysadmin.post("/admin/rooms", data={"room_code": "Z999", "floor": 9}))
    ok(sysadmin.post("/admin/specialties", data={"name": "Test specialty"}))
    ok(sysadmin.post("/admin/medications", data={"name": "TestMed", "unit": "viên", "description": "x"}))
    ok(sysadmin.post("/admin/medications/1/edit", data={"name": "Renamed", "unit": "viên"}))
    ok(sysadmin.post("/admin/medications/1/toggle"))


def test_admin_permissions(sysadmin, receptionist):
    ok(sysadmin.post("/admin/permissions/grant", data={"admin_id": 3, "permission_code": "VIEW_ALL_RECORDS"}))
    ok(sysadmin.post("/admin/staff", data={"full_name": "New Staff", "email": "new.staff@clinic.local", "role": "RECEPTIONIST"}))
    assert receptionist.post("/admin/permissions/grant", data={"admin_id": 3, "permission_code": "CREATE_DOCTOR"}).status_code == 403


def test_admin_confirms_and_rejects_status(sysadmin):
    pending = re.findall(r"/admin/appointments/(\d+)/status", text(sysadmin.get("/admin/appointments?status=PENDING")))
    assert pending
    ok(sysadmin.post(f"/admin/appointments/{pending[0]}/status", data={"status": "CONFIRMED"}))
    sysadmin.post(f"/admin/appointments/{pending[0]}/status", data={"status": "COMPLETED"})
    assert "không hợp lệ" in flashes(sysadmin)[-1]


# ------------------------------------------------------------------ last: nothing above may have persisted
def test_nothing_persisted(sysadmin):
    assert "BS Test" not in text(sysadmin.get("/admin/doctors"))
    assert "Không tìm thấy bệnh nhân" in text(sysadmin.get("/admin/patients?q=Test+Patient"))
    assert "<td>TestMed</td>" not in text(sysadmin.get("/admin/medications?q=TestMed"))
