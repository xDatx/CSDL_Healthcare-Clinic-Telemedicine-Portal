# Backend – Telemedicine Portal (Phase 4)

Flask + PyMySQL (raw SQL, no ORM) + Jinja2/Bootstrap. Three portals (patient / doctor / admin) talk to the
`healthcare` database through the **three least-privilege MySQL accounts** created by `sql/07_rbac.sql`.

## Run

```bash
cd backend
python -m venv .venv && .venv\Scripts\activate          # optional
pip install -r requirements.txt
copy .env.example .env                                   # then edit SECRET_KEY (and DB passwords if you changed them)
python manage.py seed-accounts                           # one login per admin / active doctor / first 30 patients
python app.py                                            # http://127.0.0.1:5000
```

Database first: `sql/run_all.sql` (schema, triggers, procedures, views, seed data, RBAC).
All seeded accounts use the password `Demo#2026`. Logins are the e-mail in the database
(patients without e-mail: `patient<id>`; a second patient that shares an e-mail also gets `patient<id>`).

| Role | Example login | Notes |
|---|---|---|
| Patient | `an.nguyen@example.com`, `patient2` | own appointments, booking, history |
| Doctor | `khoa.tran@clinic.local` (GP), `tung.vo@clinic.local` (specialist) | schedule, records, consultations |
| System admin | `lan.nguyen@clinic.local` | has all four permissions |
| Receptionist | `trang.le@clinic.local` | no permissions: patients, appointments, shifts only |

Tests (real DB, expect **76 passed**): `python -m pytest -q`  -  `test_backend.py` reads (and books + cancels one appointment),
`test_selfservice.py` covers registration and profile (FR-01) and the room dropdown, `test_writes.py` runs every write route
inside a rolled-back transaction, so the data is not changed. Run them against a freshly built database
(`sql/run_all.sql`, then `python manage.py seed-accounts`).

## How it is built

```
app.py            app factory, one place that turns DB errors into messages
config.py         .env settings, one DB password per role
db.py             per-request connection as app_<role>; sets @app_actor_type / @app_actor_id for the triggers
auth.py           login / logout, @role_required(role, perm), brute-force guard
auth_store.py     accounts (login + password hash) in instance/auth.db (SQLite) - the 17-table schema is unchanged
errors.py         SQLSTATE 45000 (BR-xx / NFR-xx) and constraint errors -> readable Vietnamese + rule id
services.py       booking, record/prescription parsing, shift building (shared by portals)
blueprints/       patient.py  doctor.py  admin.py
templates/ static/ tests/
```

### Security model (what to explain in the defense)
1. **Authenticated id comes from the session**, never from the request. `sp_patient_history`, `sp_read_medical_record`,
   `sp_cancel_appointment`, `sp_list_my_consultations`, ... are always called with `session["uid"]` (07_rbac.sql "Trust model").
2. **Least privilege**: the web app logs in to MySQL as `app_patient` / `app_doctor` / `app_admin`. Even a bug in a route cannot
   read `medical_record` directly - the accounts have no SELECT on it.
3. **Row-level checks the DB cannot do** (column grants only) are done in the route *before* writing: a doctor must own the
   appointment / shift / consultation (`_own_appointment`, `_my_incoming`, `shift_cancel`).
4. **Business rules stay in the database**: triggers (BR-xx) are the last word; the backend only translates their messages.
5. Passwords are PBKDF2-hashed, CSRF tokens on every POST, `HttpOnly` + `SameSite=Lax` cookies, 5 failed logins lock a login for 5 minutes.

## Route -> database object map

| Portal | Route | Database object |
|---|---|---|
| Patient | `/register` (public, FR-01) | `sp_register_patient` (account itself goes to `instance/auth.db`) |
| Patient | `/patient/profile` | `sp_get_my_profile`, `sp_update_my_profile` |
| Patient | `/patient/doctors` | `v_doctor_availability` |
| Patient | `POST /patient/book` | `sp_book_appointment` (triggers BR-08, BR-09, BR-11) |
| Patient | `/patient/appointments`, `POST .../cancel` | `sp_patient_appointments`, `sp_cancel_appointment` |
| Patient | `/patient/history`, `/patient/records/<id>` | `sp_patient_history`, `sp_read_medical_record` (audited, NFR-04) |
| Doctor | `/doctor/appointments`, `POST .../status` | `v_appointment_detail` + `medical_record`(key columns), `UPDATE appointment.status` (BR-11) |
| Doctor | `/doctor/appointments/<id>/record/new` | `INSERT medical_record`, `prescription`, `prescription_item` in one transaction (BR-12, BR-16) |
| Doctor | `/doctor/records/<id>`, `.../edit` | `sp_read_medical_record` (BR-21 / BR-22), `UPDATE medical_record` (audit trigger) |
| Doctor | `/doctor/shifts` | `shift` + `room` (read-only, for the room dropdown) (BR-03, BR-05, BR-24, BR-26) |
| Doctor | `/doctor/consultations/...` | `sp_list_my_consultations`, `sp_get_consultation`, `UPDATE consultation_request` (BR-22, BR-23) |
| Admin | `/admin/patients...` | `patient`, `sp_book_appointment` |
| Admin | `/admin/doctors/new` (needs `CREATE_DOCTOR`) | `doctor` -> `gp`/`specialist` -> activate (BR-01) |
| Admin | `/admin/medications` (needs `MANAGE_MEDICATION`) | `medication` + `medication_audit_log` (BR-19, BR-25) |
| Admin | `/admin/permissions` (SYSTEM_ADMIN) | `staff_permission` (BR-20) |
| Admin | `/admin/audit` (SYSTEM_ADMIN), `/admin/records/<id>` | `medical_record_audit_log`, `medication_audit_log`, `sp_read_medical_record` (needs `VIEW_ALL_RECORDS`) |
| Admin | `/admin/pay` | `v_part_time_pay` (BR-24) |

## Known limits (state them in the report)
- A doctor cannot edit a prescription after it is saved (no UPDATE grant on `prescription_item`).
- Bootstrap is vendored in `static/vendor/`, so the demo does not need internet.
- Application accounts (login + password hash) live in a separate SQLite file (`instance/auth.db`), not in the
  17-table clinical schema; they are created by `python manage.py seed-accounts` or by patient self-registration.
- Clinical data encryption at rest is a deployment setting (`ALTER TABLE ... ENCRYPTION = 'Y'`), not application logic;
  see `docs/traceability_matrix.md`.
- Login throttling is in memory (reset on restart); use a real store for production.
