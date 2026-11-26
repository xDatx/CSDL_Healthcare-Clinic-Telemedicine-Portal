"""Phase 4 additions: FR-01 patient self-service (register + own profile) and the doctor room dropdown.

Needs the database objects of sql/08_phase4_patch.sql (or a fresh sql/run_all.sql).
Like test_writes.py, nothing is persisted: Db.commit is a no-op, so every request runs against MySQL
(privileges, procedures, CHECKs execute) and is rolled back at the end of the request.
"""
import pytest

import auth
import auth_store
from db import Db
from helpers import text

GOOD = {"full_name": "Nguyễn Test Đăng Ký", "dob": "1995-05-20", "phone": "0900111222",
        "email": "new.patient.test@example.com", "address": "1 Lê Lợi, Q1",
        "password": "Matkhau#2026", "password2": "Matkhau#2026"}


@pytest.fixture(autouse=True)
def no_persist(monkeypatch):
    monkeypatch.setattr(Db, "commit", lambda self: None)
    monkeypatch.setattr(auth_store, "upsert_account", lambda role, actor_id, login, *a, **k: login)
    monkeypatch.setattr(auth_store, "set_display_name", lambda *a, **k: None)
    auth._REGISTRATIONS.clear()


def flashes(client):
    with client.session_transaction() as s:
        return [m for _cat, m in s.get("_flashes", [])]


# ------------------------------------------------------------------ registration (FR-01)
def test_register_page_is_public(anon):
    r = anon.get("/register")
    assert r.status_code == 200 and 'name="password2"' in text(r)


def test_login_page_links_to_register(anon):
    assert "/register" in text(anon.get("/login"))


def test_register_creates_patient(anon):
    r = anon.post("/register", data=GOOD)
    assert r.status_code == 302 and r.headers["Location"].endswith("/login")
    assert "Đăng ký thành công" in flashes(anon)[-1]


def test_register_without_phone_is_allowed(anon):
    r = anon.post("/register", data={**GOOD, "phone": ""})
    assert r.status_code == 302            # BR-00: the e-mail alone is a valid contact


def test_register_rejects_existing_login(anon):
    r = anon.post("/register", data={**GOOD, "email": "an.nguyen@example.com"})
    assert r.status_code == 200 and "đã có tài khoản" in text(r)


@pytest.mark.parametrize("change, fragment", [
    ({"password": "short", "password2": "short"}, "ít nhất 8"),
    ({"password2": "khac-mat-khau"}, "không khớp"),
    ({"email": ""}, "email"),
    ({"email": "khong-phai-email"}, "Email không hợp lệ"),
    ({"dob": "2999-01-01"}, "tương lai"),
    ({"dob": "20/05/1995"}, "không hợp lệ"),
    ({"full_name": "   "}, "họ tên"),
])
def test_register_validation(anon, change, fragment):
    r = anon.post("/register", data={**GOOD, **change})
    assert r.status_code == 200 and fragment in text(r)


def test_register_is_throttled(app, anon, monkeypatch):
    monkeypatch.setitem(app.config, "REGISTER_MAX_PER_HOUR", 0)
    r = anon.post("/register", data=GOOD)
    assert r.status_code == 200 and "Quá nhiều" in text(r)


def test_register_redirects_when_logged_in(patient1):
    assert patient1.get("/register").status_code == 302


# ------------------------------------------------------------------ own profile (FR-01)
def test_profile_requires_patient_role(anon, doctor1):
    assert anon.get("/patient/profile").status_code == 302
    assert doctor1.get("/patient/profile").status_code == 403


def test_profile_shows_own_data(patient1):
    r = patient1.get("/patient/profile")
    assert r.status_code == 200 and "an.nguyen@example.com" in text(r)


def test_profile_update(patient1):
    r = patient1.post("/patient/profile", data={"full_name": "Nguyễn Văn An", "dob": "1990-01-01",
                                                "phone": "0912345678", "email": "an.nguyen@example.com",
                                                "address": "Hà Nội"})
    assert r.status_code == 302 and "Đã cập nhật" in flashes(patient1)[-1]


def test_profile_needs_a_contact(patient1):
    patient1.post("/patient/profile", data={"full_name": "An", "dob": "1990-01-01", "phone": "", "email": ""})
    assert "ít nhất" in flashes(patient1)[-1]


def test_profile_rejects_future_birth_date(patient1):
    patient1.post("/patient/profile", data={"full_name": "An", "dob": "2999-01-01", "phone": "0912345678"})
    assert "tương lai" in flashes(patient1)[-1]


# ------------------------------------------------------------------ doctor: room dropdown (needs GRANT SELECT ON room)
def test_doctor_shift_form_lists_rooms(doctor1):
    html = text(doctor1.get("/doctor/shifts"))
    assert '<select name="room_id"' in html, "run sql/08_phase4_patch.sql: GRANT SELECT ON room TO r_doctor"
