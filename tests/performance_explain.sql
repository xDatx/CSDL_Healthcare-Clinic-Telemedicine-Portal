-- Author: Lý Thành Đạt
-- Module: Performance evidence for NFR-03
-- Chạy SAU seed_bulk_patients.sql + 02_indexes.sql
-- MySQL 8.0.18+ required for EXPLAIN ANALYZE

USE healthcare;

-- ============================================================
-- QUERY 1: Doctor directory
-- Kỳ vọng: access_type = ALL (bảng 50 dòng, full scan đúng)
-- ============================================================
EXPLAIN ANALYZE
SELECT d.doctor_id, d.full_name, d.spec_type, d.employment_type
FROM doctor d
WHERE d.is_active = TRUE;

-- ============================================================
-- QUERY 2: Available shifts for one doctor (Q01)
-- Kỳ vọng: dùng idx_shift_doctor_date, access_type = range
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

-- ============================================================
-- QUERY 3: Patient history (Q03) — ĐÃ SỬA FILTER
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
-- QUERY 4: Double-booking check (Q02) — trigger critical
-- Kỳ vọng: dùng idx_appt_shift_time
-- ============================================================
EXPLAIN ANALYZE
SELECT a1.appointment_id, a2.appointment_id
FROM appointment a1
JOIN appointment a2
  ON a1.shift_id = a2.shift_id
 AND a1.appointment_id < a2.appointment_id
WHERE a1.status <> 'CANCELLED'
  AND a2.status <> 'CANCELLED'
  AND a1.start_time < a2.end_time
  AND a2.start_time < a1.end_time;

-- ============================================================
-- QUERY 5: Medication catalog
-- Kỳ vọng: access_type = ALL (502 dòng, full scan đúng)
--          Chứng minh quyết định KHÔNG tạo index trên is_active
-- ============================================================
EXPLAIN ANALYZE
SELECT m.medication_id, m.name, m.unit
FROM medication m
WHERE m.is_active = TRUE;

-- ============================================================
-- QUERY 6: Top prescribed medications (Q05)
-- Kỳ vọng: dùng idx_item_presc (FK auto)
-- ============================================================
EXPLAIN ANALYZE
SELECT m.medication_id, m.name,
       COUNT(pi.item_id) AS times_prescribed,
       SUM(pi.quantity)  AS total_quantity
FROM medication m
JOIN prescription_item pi ON pi.medication_id = m.medication_id
GROUP BY m.medication_id, m.name
HAVING COUNT(pi.item_id) >= 2
ORDER BY times_prescribed DESC, total_quantity DESC
LIMIT 10;
