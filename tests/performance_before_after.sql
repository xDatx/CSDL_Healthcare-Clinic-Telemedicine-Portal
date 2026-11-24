-- Author: Lý Thành Đạt
-- Module: Before / after index comparison for NFR-03
-- Technique: IGNORE INDEX forces the plan the query would get WITHOUT the index, so the index
-- does not have to be dropped (appointment's FK columns are covered by these same indexes).
-- Run AFTER the bulk seeds. Needs MySQL 8.0.18+. Compare "actual time" and "rows" of each pair.
USE healthcare;

ANALYZE TABLE shift, appointment, medical_record_audit_log;

SET @heavy_patient = (SELECT MIN(patient_id) FROM patient WHERE full_name LIKE 'Bulk Patient %');
SET @a_shift = (SELECT MIN(shift_id) FROM shift WHERE doctor_id > 10);
SET @a_doctor = 1, @a_date = '2026-11-25';

-- ===== Pair 1: patient history (Q03) =====
-- BEFORE: table scan of appointment
EXPLAIN ANALYZE
SELECT a.appointment_id, a.start_time, a.status
FROM appointment a IGNORE INDEX (idx_appt_patient_date)
WHERE a.patient_id = @heavy_patient
ORDER BY a.start_time DESC;
-- AFTER: index range scan, already sorted (no filesort)
EXPLAIN ANALYZE
SELECT a.appointment_id, a.start_time, a.status
FROM appointment a
WHERE a.patient_id = @heavy_patient
ORDER BY a.start_time DESC;

-- ===== Pair 2: shifts of a doctor on a day (Q01) =====
EXPLAIN ANALYZE
SELECT shift_id, start_time, end_time
FROM shift IGNORE INDEX (idx_shift_doctor_date, idx_shift_room_date)
WHERE doctor_id = @a_doctor AND shift_date = @a_date AND status = 'ACTIVE';

EXPLAIN ANALYZE
SELECT shift_id, start_time, end_time
FROM shift
WHERE doctor_id = @a_doctor AND shift_date = @a_date AND status = 'ACTIVE';

-- ===== Pair 3: BR-09 overlap probe executed by the booking trigger on every INSERT =====
EXPLAIN ANALYZE
SELECT 1 FROM appointment a IGNORE INDEX (idx_appt_shift_time, idx_appt_patient_date)
WHERE a.shift_id = @a_shift AND a.status <> 'CANCELLED'
  AND '2026-01-05 10:00:00' < a.end_time AND a.start_time < '2026-01-05 10:30:00'
LIMIT 1;

EXPLAIN ANALYZE
SELECT 1 FROM appointment a
WHERE a.shift_id = @a_shift AND a.status <> 'CANCELLED'
  AND '2026-01-05 10:00:00' < a.end_time AND a.start_time < '2026-01-05 10:30:00'
LIMIT 1;

-- ===== Pair 4: audit trail of a record (NFR-04) =====
EXPLAIN ANALYZE
SELECT audit_id, action, action_at
FROM medical_record_audit_log IGNORE INDEX (idx_mr_audit_record)
WHERE record_id = 1 ORDER BY action_at DESC;

EXPLAIN ANALYZE
SELECT audit_id, action, action_at
FROM medical_record_audit_log
WHERE record_id = 1 ORDER BY action_at DESC;
