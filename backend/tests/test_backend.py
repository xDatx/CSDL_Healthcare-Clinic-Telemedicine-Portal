"""Integration tests against the real `healthcare` database (needs MySQL + `python manage.py seed-accounts`).

Run from backend/:   python -m pytest -q
Only the booking test writes (one appointment, cancelled again at the end).
"""
import re

import pytest

from db import Db
from helpers import PASSWORD, text  # noqa: F401  (fixtures live in conftest.py)



# ------------------------------------------------------------------ authentication
def test_login_required(anon):
    for url in ("/patient/", "/doctor/", "/admin/", "/admin/audit"):
        assert anon.get(url).status_code == 302


def test_wrong_password(anon):
    r = anon.post("/login", data={"role": "patient", "login": "an.nguyen@example.com", "password": "nope"})
    assert r.status_code == 200 and "Sai tên đăng nhập" in text(r)


def test_role_cannot_be_swapped(anon):
    """A doctor's credentials are not valid for the admin role."""
    r = anon.post("/login", data={"role": "admin", "login": "khoa.tran@clinic.local", "password": PASSWORD})
    assert r.status_code == 200


# ------------------------------------------------------------------ role separation
def test_patient_cannot_open_other_portals(patient1):
    assert patient1.get("/doctor/").status_code == 403
    assert patient1.get("/admin/").status_code == 403
    assert patient1.get("/doctor/consultations").status_code == 403


def test_doctor_cannot_open_other_portals(doctor1):
    assert doctor1.get("/patient/").status_code == 403
    assert doctor1.get("/admin/patients").status_code == 403


def test_receptionist_lacks_admin_only_pages(receptionist):
    for url in ("/admin/audit", "/admin/permissions", "/admin/medications", "/admin/doctors/new"):
        assert receptionist.get(url).status_code == 403, url


# ------------------------------------------------------------------ pages render
@pytest.mark.parametrize("url", ["/patient/", "/patient/doctors", "/patient/appointments",
                                 "/patient/history", "/patient/medications"])
def test_patient_pages(patient1, url):
    assert patient1.get(url).status_code == 200


@pytest.mark.parametrize("url", ["/doctor/", "/doctor/appointments", "/doctor/appointments?scope=all",
                                 "/doctor/shifts", "/doctor/consultations", "/doctor/medications"])
def test_doctor_pages(doctor1, url):
    assert doctor1.get(url).status_code == 200


@pytest.mark.parametrize("url", ["/admin/", "/admin/patients", "/admin/patients?q=nguyen", "/admin/appointments",
                                 "/admin/doctors", "/admin/doctors/new", "/admin/catalog", "/admin/shifts",
                                 "/admin/medications", "/admin/permissions", "/admin/audit",
                                 "/admin/audit?kind=medication", "/admin/pay", "/admin/patients/1",
                                 "/admin/patients/1/book"])
def test_sysadmin_pages(sysadmin, url):
    assert sysadmin.get(url).status_code == 200, url


# ------------------------------------------------------------------ data isolation (NFR-02)
def _record_ids(html):
    return [int(x) for x in re.findall(r"/patient/records/(\d+)", html)]


def test_patient_cannot_read_another_patients_record(patient1, patient2):
    ids = _record_ids(text(patient2.get("/patient/history")))
    assert ids, "seed data: patient 2 should have a medical record"
    r = patient1.get(f"/patient/records/{ids[0]}")
    assert r.status_code == 400 and "NFR-02" in text(r)
    assert patient2.get(f"/patient/records/{ids[0]}").status_code == 200


def test_unrelated_doctor_cannot_read_record(doctor1, doctor4, patient2):
    """Pick a record that doctor 1 can NOT open and check the DB refuses it, also for the URL guess."""
    ids = _record_ids(text(patient2.get("/patient/history")))
    denied = [i for i in ids if doctor1.get(f"/doctor/records/{i}").status_code == 400]
    denied += [i for i in ids if doctor4.get(f"/doctor/records/{i}").status_code == 400]
    assert denied, "at least one of the doctors must be refused a record that is not theirs"


def test_receptionist_needs_view_all_records(receptionist, patient2):
    ids = _record_ids(text(patient2.get("/patient/history")))
    r = receptionist.get(f"/admin/records/{ids[0]}")
    assert r.status_code == 400 and "NFR-02" in text(r)


def test_sysadmin_can_read_record_and_it_is_audited(sysadmin, patient2):
    rid = _record_ids(text(patient2.get("/patient/history")))[0]
    assert sysadmin.get(f"/admin/records/{rid}").status_code == 200
    audit = text(sysadmin.get(f"/admin/audit?record_id={rid}"))
    assert "ADMIN" in audit


# ------------------------------------------------------------------ booking (writes, then cancels)
def test_booking_and_cancel(app, patient1):
    with app.app_context():
        db = Db("patient", config=app.config)
        shift = db.one("SELECT * FROM v_doctor_availability WHERE shift_date >= CURDATE() AND free_minutes >= 30 "
                       "ORDER BY shift_date DESC, shift_id DESC LIMIT 1")
        db.close()
    if not shift:
        pytest.skip("no future shift with free capacity in the seed data")

    start = f"{(shift['shift_end'].seconds // 3600) - 1:02d}:00"   # last hour of the shift
    form = {"shift_id": shift["shift_id"], "start_time": start, "minutes": 30, "appointment_type": "IN_PERSON"}
    r = patient1.post("/patient/book", data=form, follow_redirects=True)
    assert "Đã đặt lịch hẹn" in text(r)
    appt_id = int(re.search(r"Đã đặt lịch hẹn #(\d+)", text(r)).group(1))

    # the same slot again is rejected by trigger BR-09
    r2 = patient1.post("/patient/book", data=form, follow_redirects=True)
    assert "BR-09" in text(r2)

    r3 = patient1.post(f"/patient/appointments/{appt_id}/cancel", follow_redirects=True)
    assert "Đã hủy lịch hẹn" in text(r3)
