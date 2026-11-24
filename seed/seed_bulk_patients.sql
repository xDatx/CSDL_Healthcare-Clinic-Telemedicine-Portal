-- Author: Lý Thành Đạt
-- Module: Bulk seed 1/3 - 10,000 patients (NFR-03)
-- Run order: run_all.sql  ->  seed_bulk_patients.sql  ->  seed_bulk_medications.sql  ->  seed_bulk_activity.sql
-- Idempotent: does nothing if bulk patients already exist.
-- To reset everything just run sql/run_all.sql again (medical records and audit rows are
-- append-only by design, so they cannot be deleted selectively).
USE healthcare;

SET SESSION cte_max_recursion_depth = 100000;

INSERT INTO patient (full_name, dob, phone, email)
WITH RECURSIVE n (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 10000
)
SELECT CONCAT('Bulk Patient ', LPAD(i, 5, '0')),
       DATE_ADD('1950-01-01', INTERVAL (i * 37) % 22000 DAY),
       CONCAT('09', LPAD(i, 8, '0')),
       CONCAT('bulk.patient', i, '@mail.test')
FROM n
WHERE NOT EXISTS (SELECT 1 FROM patient WHERE full_name LIKE 'Bulk Patient %');

SELECT COUNT(*) AS bulk_patients FROM patient WHERE full_name LIKE 'Bulk Patient %';
