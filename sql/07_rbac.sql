-- Author: Nguyễn Hoàng Dũng
-- Module: Role-based access control (MySQL 8.0 roles), least privilege
-- Run as root AFTER the procedures / views exist (run_all.sql does this).
--
-- Design
--   * Clinical content (medical_record, prescription, prescription_item, consultation opinions) is
--     NEVER readable with a plain SELECT by an application role. Reads go through
--       sp_read_medical_record  (one record, authorised + audited)
--       sp_patient_history      (a patient's own history, audited)
--     Both run with DEFINER rights, so the roles need no privilege on the audit tables.
--   * Nobody except the DBA gets DELETE, DROP, ALTER or GRANT OPTION.
--   * Writes that need business checks go through triggers (they fire for every role).
--
-- Trust model: MySQL cannot see the end user behind a pooled app connection. The backend must
-- authenticate the user and pass that user's id to the procedures (see sp_read_medical_record.sql).
-- A patient account that calls sp_patient_history(<other id>) is NOT stopped by MySQL: the backend
-- is responsible for passing the id of the logged-in patient (documented limitation, Phase 4).
--
-- The passwords below are placeholders for the course demo. Change them before any real use.

USE healthcare;

-- ---------- clean slate ----------
DROP USER IF EXISTS 'app_patient'@'%';
DROP USER IF EXISTS 'app_doctor'@'%';
DROP USER IF EXISTS 'app_admin'@'%';
DROP ROLE IF EXISTS 'r_patient', 'r_doctor', 'r_admin';

CREATE ROLE 'r_patient', 'r_doctor', 'r_admin';

-- Make the "nothing by default" state explicit (REVOKE section of the report template, 5.2)
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'r_patient', 'r_doctor', 'r_admin';

-- =====================================================================================
-- PATIENT: book, cancel own booking, see own history/appointments, browse availability
-- =====================================================================================
GRANT EXECUTE ON PROCEDURE healthcare.sp_book_appointment     TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_cancel_appointment   TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_patient_appointments TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_patient_history      TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_read_medical_record  TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_register_patient     TO 'r_patient';  -- FR-01
GRANT EXECUTE ON PROCEDURE healthcare.sp_get_my_profile       TO 'r_patient';  -- FR-01
GRANT EXECUTE ON PROCEDURE healthcare.sp_update_my_profile    TO 'r_patient';  -- FR-01
GRANT SELECT ON healthcare.v_doctor_availability TO 'r_patient';
GRANT SELECT ON healthcare.v_active_medication   TO 'r_patient';

-- =====================================================================================
-- DOCTOR: own schedule, clinical write path, consultation workflow
-- =====================================================================================
GRANT EXECUTE ON PROCEDURE healthcare.sp_read_medical_record    TO 'r_doctor';
GRANT EXECUTE ON PROCEDURE healthcare.sp_list_my_consultations  TO 'r_doctor';
GRANT EXECUTE ON PROCEDURE healthcare.sp_get_consultation       TO 'r_doctor';
GRANT SELECT ON healthcare.v_doctor_availability          TO 'r_doctor';
GRANT SELECT ON healthcare.v_appointment_detail           TO 'r_doctor';
GRANT SELECT ON healthcare.v_active_consultation_access   TO 'r_doctor';
GRANT SELECT ON healthcare.v_active_medication            TO 'r_doctor';
GRANT SELECT ON healthcare.v_active_doctor_directory      TO 'r_doctor';

-- register / adjust shifts (BR-03, BR-05, BR-24, BR-26 are enforced by triggers)
GRANT SELECT, INSERT, UPDATE ON healthcare.shift TO 'r_doctor';
GRANT SELECT ON healthcare.room TO 'r_doctor';   -- room dropdown in the shift form (BR-03); read-only

-- move an appointment through its lifecycle (BR-11); only the key and status are visible
GRANT SELECT (appointment_id, status) ON healthcare.appointment TO 'r_doctor';
GRANT UPDATE (status)                 ON healthcare.appointment TO 'r_doctor';

-- write the record and the prescription; the key columns let UPDATE ... WHERE work without
-- exposing any clinical text
GRANT INSERT ON healthcare.medical_record TO 'r_doctor';
GRANT SELECT (record_id, appointment_id) ON healthcare.medical_record TO 'r_doctor';
GRANT UPDATE (systolic_bp, diastolic_bp, heart_rate, temperature_c, oxygen_saturation,
              symptoms, diagnosis, notes)  ON healthcare.medical_record TO 'r_doctor';
GRANT INSERT ON healthcare.prescription      TO 'r_doctor';
GRANT SELECT (prescription_id, record_id) ON healthcare.prescription TO 'r_doctor';
GRANT INSERT ON healthcare.prescription_item TO 'r_doctor';

-- consultation workflow (BR-22 / BR-23); the reason / opinion text is NOT selectable
GRANT INSERT ON healthcare.consultation_request TO 'r_doctor';
GRANT SELECT (request_id, record_id, requesting_doctor_id, consulting_doctor_id, status)
      ON healthcare.consultation_request TO 'r_doctor';
GRANT UPDATE (status, opinion, responded_at, expires_at)
      ON healthcare.consultation_request TO 'r_doctor';

-- =====================================================================================
-- ADMIN (receptionist / system admin): people, rooms, catalog, reporting
-- Reading a medical record still needs the VIEW_ALL_RECORDS permission (BR-20), which
-- fn_can_read_record checks - the database role alone is not enough.
-- =====================================================================================
GRANT EXECUTE ON PROCEDURE healthcare.sp_read_medical_record TO 'r_admin';
GRANT EXECUTE ON PROCEDURE healthcare.sp_book_appointment    TO 'r_admin';

GRANT SELECT, INSERT, UPDATE ON healthcare.patient    TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.doctor     TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.gp         TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.specialist TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.specialty  TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.room       TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.shift      TO 'r_admin';
GRANT SELECT, INSERT, UPDATE ON healthcare.medication TO 'r_admin';          -- BR-19: no DELETE
GRANT SELECT, INSERT         ON healthcare.admin      TO 'r_admin';
GRANT SELECT, INSERT         ON healthcare.staff_permission TO 'r_admin';    -- grants only, no revoke by DELETE

GRANT SELECT ON healthcare.v_appointment_detail   TO 'r_admin';
GRANT SELECT ON healthcare.v_doctor_availability  TO 'r_admin';
GRANT SELECT ON healthcare.v_part_time_pay        TO 'r_admin';
GRANT SELECT ON healthcare.v_active_medication    TO 'r_admin';
GRANT SELECT ON healthcare.v_active_consultation_access TO 'r_admin';
GRANT SELECT ON healthcare.v_active_doctor_directory    TO 'r_admin';
GRANT SELECT ON healthcare.medical_record_audit_log TO 'r_admin';            -- who read what (NFR-04)
GRANT SELECT ON healthcare.medication_audit_log     TO 'r_admin';            -- BR-25

-- Appointments are created through sp_book_appointment; the front desk may also change status.
GRANT SELECT (appointment_id, patient_id, shift_id, start_time, end_time, appointment_type, status)
      ON healthcare.appointment TO 'r_admin';
GRANT UPDATE (status) ON healthcare.appointment TO 'r_admin';

-- ---------- accounts ----------
CREATE USER 'app_patient'@'%' IDENTIFIED BY 'Patient#2026';
CREATE USER 'app_doctor'@'%'  IDENTIFIED BY 'Doctor#2026';
CREATE USER 'app_admin'@'%'   IDENTIFIED BY 'Admin#2026';

GRANT 'r_patient' TO 'app_patient'@'%';
GRANT 'r_doctor'  TO 'app_doctor'@'%';
GRANT 'r_admin'   TO 'app_admin'@'%';

SET DEFAULT ROLE ALL TO 'app_patient'@'%', 'app_doctor'@'%', 'app_admin'@'%';

FLUSH PRIVILEGES;

-- ---------- quick review ----------
-- SHOW GRANTS FOR 'app_patient'@'%' USING 'r_patient';
-- SHOW GRANTS FOR 'app_doctor'@'%'  USING 'r_doctor';
-- SHOW GRANTS FOR 'app_admin'@'%'   USING 'r_admin';
