# Traceability matrix: rule -> implementation -> test

Rule text lives in the project report (section 2, business rules). This file only shows where each rule is
enforced in the database and which automated test proves it. Tests are in [`tests/run_all_tests.sql`](../tests/run_all_tests.sql)
(67 tests, all PASS on a freshly built database). A negative test passes only when the statement fails with the expected rule id.

| Rule | Enforced by | Tests |
|---|---|---|
| BR-01 total specialization (every active doctor is exactly GP or SPECIALIST) | `trg_doctor_activation_insert/update`, `trg_gp_no_orphan_active`, `trg_specialist_no_orphan_active`, composite FK `(doctor_id, spec_type)` | TC-01, TC-02 |
| BR-03 GP shift needs a room, no room double-booking | `sp_validate_shift` via `trg_shift_validate_insert/update` (behavioral trigger; `shift.room_id` is structurally nullable in DDL) | TC-03, TC-08 |
| BR-05 a doctor has no overlapping shifts | `sp_validate_shift` | TC-07 |
| BR-07 appointment belongs to an existing shift | FK `fk_appt_shift`, `sp_validate_appointment_slot` | covered by TC-10..13 |
| BR-08 appointment inside an ACTIVE shift (day and hours) | `sp_validate_appointment_slot`, `sp_validate_shift` | TC-11, TC-12, TC-13 |
| BR-09 no overlapping appointments in a shift | `sp_validate_appointment_slot` via `trg_appointment_validate_insert/update` | TC-10, TC-18 |
| BR-11 appointment status lifecycle | `trg_appointment_validate_insert/update`, `sp_cancel_appointment` | TC-14, TC-15, TC-16, TC-17, TC-64, TC-65 |
| BR-12 record needs a COMPLETED appointment, one record per appointment, never moves | `trg_mr_requires_completed`, `trg_mr_appointment_immutable`, `UNIQUE(appointment_id)` | TC-19, TC-20 |
| BR-14 one prescription per record | `UNIQUE(record_id)` on `prescription` | TC-30 |
| BR-15 prescription has one or more items | Not enforced declaratively by DB (MySQL lacks `DEFERRABLE`); enforced by app transaction (see below) | — |
| BR-16 a drug appears once per prescription | composite PK `(prescription_id, medication_id)` | TC-29 |
| BR-17 quantity and duration are positive | `ck_item_qty`, `ck_item_days` | TC-28 |
| BR-19 medications are deactivated, never deleted | `trg_med_no_hard_delete`, no DELETE grant | TC-31 |
| BR-20 only a SYSTEM_ADMIN holding a permission can grant it; reading all records needs `VIEW_ALL_RECORDS` | `trg_staff_permission_grant_insert`, `fn_can_read_record` | TC-35, TC-36, TC-37, TC-52, TC-53 |
| BR-21 a doctor reads records of his own shifts | `fn_can_read_record` | TC-47, TC-48 |
| BR-22 consultation access only after APPROVED, within its window | `trg_consultation_validate`, `trg_consultation_transition`, `fn_can_read_record`, `sp_list_my_consultations`, `sp_get_consultation`, view `v_active_consultation_access` | TC-39, TC-41, TC-43, TC-44, TC-49, TC-50, TC-51, TC-61, TC-62 |
| BR-23 only the treating doctor requests; request is immutable | `trg_consultation_validate`, `trg_consultation_transition`, `ck_cr_diff` | TC-38, TC-40, TC-42 |
| BR-24 PART_TIME shift has a rate, FULL_TIME has none | `sp_validate_shift`; pay in view `v_part_time_pay`, query Q07 | TC-05, TC-06 |
| BR-25 every catalog change is audited with the acting admin | `sp_require_admin_actor`, `trg_med_audit_*`, append-only triggers | TC-32, TC-33, TC-34 |
| BR-26 a SPECIALIST shift has no room | `sp_validate_shift` | TC-04 |
| NFR-02 case-based access control on clinical data | `sp_read_medical_record`, `sp_patient_history`, `sp_cancel_appointment`, `sp_get_consultation`, `fn_can_read_record`, RBAC (`07_rbac.sql`) | TC-45, TC-46, TC-54, TC-55, TC-56, TC-63 |
| NFR-03 performance with 50 doctors and 10,000 patients | 7 indexes (`02_indexes.sql`), bulk seeds | [`docs/performance.md`](performance.md) |
| NFR-04 append-only audit of every read and write of a record | `trg_mr_audit_*`, `sp_insert_record_audit`, `sp_patient_appointments` (no false read audit), append-only triggers, no DELETE on records | TC-22..TC-27, TC-57, TC-58, TC-59, TC-66, TC-67 |
| Data integrity (CHECK constraints) | `ck_shift_time`, `ck_mr_bp_order`, `ck_patient_contact`, `ck_mr_audit_one_actor` | TC-09, TC-21, TC-25, TC-60 |

## Not covered by a database mechanism

* **Non-empty prescriptions (BR-15).** MySQL does not support `DEFERRABLE` constraints, so a header row in `prescription`
  must be inserted before its child `prescription_item` rows. Ensuring every prescription contains at least one item
  is enforced by the application / transaction layer (inserting header and items atomically).
* **Authentication.** MySQL cannot know the end user behind a pooled application connection. The backend (Phase 4) must
  authenticate the user and pass that user's id to `sp_read_medical_record` / `sp_patient_history`.
  A patient account that calls `sp_patient_history(<another id>)` is not stopped by MySQL.
* **Encryption of clinical data at rest (NFR-04 in the report mentions AES-256).** Designated as deployment-time
  storage-layer Transparent Data Encryption (`ALTER TABLE ... ENCRYPTION = 'Y'`), not encoded in the logical DDL.
