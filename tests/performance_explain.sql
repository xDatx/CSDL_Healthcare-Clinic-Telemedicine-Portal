-- Author: Lý Thành Đạt
-- Module: Performance evidence for NFR-01 / NFR-03 (execution plans of the real access paths)
-- Run AFTER: run_all.sql, seed_bulk_patients.sql, seed_bulk_medications.sql, seed_bulk_activity.sql
-- Needs MySQL 8.0.18+ (EXPLAIN ANALYZE). Refresh statistics first so the optimizer sees the real data.
USE healthcare;

ANALYZE TABLE doctor, shift, patient, appointment, medical_record, prescription_item,
              medication, consultation_request, medical_record_audit_log;

SET @heavy_patient = (SELECT MIN(patient_id) FROM patient WHERE full_name LIKE 'Bulk Patient %');
SET @a_doctor = 1, @a_date = '2026-11-25';

-- P1: doctor directory - 50 rows, a full scan is the right plan (no index on is_active on purpose)
EXPLAIN ANALYZE
SELECT doctor_id, full_name, spec_type, employment_type FROM doctor WHERE is_active = TRUE;

-- P2: shifts of one doctor on one day (Q01 / FR-02)           -> idx_shift_doctor_date
EXPLAIN ANALYZE
SELECT shift_id, start_time, end_time FROM shift
WHERE doctor_id = @a_doctor AND shift_date = @a_date AND status = 'ACTIVE';

-- P3: history of the heaviest patient, newest first (Q03 / FR-04) -> idx_appt_patient_date, no filesort
EXPLAIN ANALYZE
SELECT a.appointment_id, a.start_time, a.status, d.full_name AS doctor_name, mr.diagnosis
FROM appointment a
JOIN shift s  ON s.shift_id = a.shift_id
JOIN doctor d ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr ON mr.appointment_id = a.appointment_id
WHERE a.patient_id = @heavy_patient
ORDER BY a.start_time DESC;

-- P4: the overlap probe that trigger trg_appointment_validate_insert runs on EVERY booking (BR-09)
--                                                              -> idx_appt_shift_time
SET @a_shift = (SELECT MIN(shift_id) FROM shift WHERE doctor_id > 10);
EXPLAIN ANALYZE
SELECT 1 FROM appointment a
WHERE a.shift_id = @a_shift AND a.status <> 'CANCELLED'
  AND '2026-01-05 10:00:00' < a.end_time AND a.start_time < '2026-01-05 10:30:00'
LIMIT 1;

-- P5: access check for a consulting doctor (fn_can_read_record, BR-22)
--     consultation_request has only a handful of rows, so the optimizer may pick a small FK index
--     (fk_cr_consulting) instead of idx_consult_access; both are single-row lookups. The composite
--     index is there for the day this table grows, it costs nothing now.
EXPLAIN ANALYZE
SELECT 1 FROM consultation_request cr
WHERE cr.record_id = 19 AND cr.consulting_doctor_id = 1 AND cr.status = 'APPROVED'
  AND (cr.expires_at IS NULL OR cr.expires_at > NOW());

-- P6: audit trail of one record, newest first (NFR-04)          -> idx_mr_audit_record
EXPLAIN ANALYZE
SELECT audit_id, action, action_at FROM medical_record_audit_log
WHERE record_id = 1 ORDER BY action_at DESC;

-- P7: medication catalog - ~520 rows, full scan is the right plan (no index on is_active on purpose)
EXPLAIN ANALYZE
SELECT medication_id, name, unit FROM medication WHERE is_active = TRUE;

-- P8: most prescribed drugs (Q05): one pass over prescription_item
EXPLAIN ANALYZE
SELECT m.medication_id, m.name, COUNT(*) AS times_prescribed, SUM(pi.quantity) AS total_quantity
FROM medication m
JOIN prescription_item pi ON pi.medication_id = m.medication_id
GROUP BY m.medication_id, m.name
ORDER BY times_prescribed DESC, total_quantity DESC
LIMIT 10;
