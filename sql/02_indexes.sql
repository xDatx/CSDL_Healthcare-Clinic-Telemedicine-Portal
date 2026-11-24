-- Author: Lý Thành Đạt
-- Module: Performance indexes for NFR-01 / NFR-03
-- Run order: after the 10 DDL files, before the triggers (run_all.sql does this).
-- Rule: do not duplicate an index that a PRIMARY KEY / UNIQUE / FK already provides.
--       Check with: SHOW INDEX FROM <table>;
-- Deliberately NOT indexed: doctor.is_active (50 rows) and medication.is_active (~500 rows,
-- low selectivity): a full scan is the correct plan, see tests/performance_explain.sql P1 / P7.
-- Creating an index whose leading column is an FK column makes MySQL drop the implicit FK index,
-- so appointment.patient_id / appointment.shift_id / consultation_request.record_id need no extra index.

USE healthcare;

-- Q01 / BR-05: shifts of a doctor on a day, and the shift-overlap check of the shift trigger
CREATE INDEX idx_shift_doctor_date
    ON shift (doctor_id, shift_date, start_time);

-- BR-03: GP room double-booking check
CREATE INDEX idx_shift_room_date
    ON shift (room_id, shift_date, start_time);

-- BR-09: overlap probe run by the booking trigger on every INSERT / UPDATE; also serves FK shift_id
CREATE INDEX idx_appt_shift_time
    ON appointment (shift_id, start_time);

-- Q03: patient history ORDER BY start_time DESC without a filesort; also serves FK patient_id
CREATE INDEX idx_appt_patient_date
    ON appointment (patient_id, start_time DESC);

-- NFR-04: audit trail of one record, newest first; also serves FK record_id
CREATE INDEX idx_mr_audit_record
    ON medical_record_audit_log (record_id, action_at DESC);

-- BR-22: fn_can_read_record probe (record + consulting doctor + live APPROVED request);
-- record_id leads so it also serves FK record_id
CREATE INDEX idx_consult_access
    ON consultation_request (record_id, consulting_doctor_id, status, expires_at);

-- Q09: access windows that are about to expire
CREATE INDEX idx_consult_expires
    ON consultation_request (expires_at);
