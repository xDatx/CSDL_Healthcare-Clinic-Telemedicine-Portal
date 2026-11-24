-- Author: Lý Thành Đạt
-- Module: Before/after index comparison for NFR-03
-- Kỹ thuật: dùng IGNORE INDEX thay vì DROP INDEX
--           (vì idx_appt_patient_date đang là index FK không thể drop)
-- MySQL 8.0.18+ required

USE healthcare;

-- ============================================================
-- Q03 — TRƯỚC index (dùng IGNORE INDEX để ép full scan)
-- Kỳ vọng: Table scan on a, actual time ~40ms
-- ============================================================
EXPLAIN ANALYZE
SELECT a.appointment_id, a.start_time, a.status,
       d.full_name AS doctor_name, mr.diagnosis
FROM appointment a IGNORE INDEX (idx_appt_patient_date)
JOIN shift s        ON s.shift_id = a.shift_id
JOIN doctor d       ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr ON mr.appointment_id = a.appointment_id
WHERE a.patient_id = 1
ORDER BY a.start_time DESC;

-- ============================================================
-- Q03 — SAU index (dùng index bình thường)
-- Kỳ vọng: Index lookup on a using idx_appt_patient_date
--          actual time < 1ms, rows=301
-- ============================================================
EXPLAIN ANALYZE
SELECT a.appointment_id, a.start_time, a.status,
       d.full_name AS doctor_name, mr.diagnosis
FROM appointment a
JOIN shift s        ON s.shift_id = a.shift_id
JOIN doctor d       ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr ON mr.appointment_id = a.appointment_id
WHERE a.patient_id = 1
ORDER BY a.start_time DESC;

-- ============================================================
-- Q01 — TRƯỚC index
-- Kỳ vọng: Table scan on sh
-- ============================================================
EXPLAIN ANALYZE
SELECT sh.shift_id, sh.start_time, sh.end_time
FROM shift sh IGNORE INDEX (idx_shift_doctor_date)
WHERE sh.status = 'ACTIVE'
  AND sh.doctor_id = 1
  AND sh.shift_date = CURRENT_DATE
  AND NOT EXISTS (
      SELECT 1 FROM appointment a
      WHERE a.shift_id = sh.shift_id AND a.status <> 'CANCELLED'
  );

-- ============================================================
-- Q01 — SAU index
-- Kỳ vọng: Index lookup on sh using idx_shift_doctor_date
-- ============================================================
EXPLAIN ANALYZE
SELECT sh.shift_id, sh.start_time, sh.end_time
FROM shift sh
WHERE sh.status = 'ACTIVE'
  AND sh.doctor_id = 1
  AND sh.shift_date = CURRENT_DATE
  AND NOT EXISTS (
      SELECT 1 FROM appointment a
      WHERE a.shift_id = sh.shift_id AND a.status <> 'CANCELLED'
  );
