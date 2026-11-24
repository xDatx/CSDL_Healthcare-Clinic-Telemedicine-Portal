-- Author: Lý Thành Đạt
-- Module: Bulk seed 3/3 - 41 doctors, shifts, ~19,700 appointments, records, prescriptions (NFR-03)
-- Run AFTER seed_bulk_patients.sql and seed_bulk_medications.sql.
-- Brings the clinic to 50 ACTIVE doctors (9 original + 41 bulk) as assumed by NFR-03.
-- Everything goes through the real triggers, so the data respects BR-01/03/05/08/09/11/12.
-- Bulk doctors are SPECIALISTs (no room needed), working 08:00-12:00 for 60 consecutive days
-- starting 2026-01-05, 8 slots of 30 minutes per shift.
-- Idempotent: the doctor / shift / appointment / record steps skip what already exists.
USE healthcare;

SET SESSION cte_max_recursion_depth = 100000;

-- ---------- 1. doctors (BR-01: insert inactive, add subtype row, then activate) ----------
INSERT INTO doctor (full_name, email, license_no, employment_type, spec_type, is_active, created_by)
WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 41)
SELECT CONCAT('Bulk Doctor ', LPAD(i, 2, '0')),
       CONCAT('bulk.doctor', i, '@clinic.local'),
       CONCAT('BULK-LIC-', LPAD(i, 4, '0')),
       IF(i % 2 = 0, 'PART_TIME', 'FULL_TIME'),
       'SPECIALIST', FALSE, 1
FROM n
WHERE NOT EXISTS (SELECT 1 FROM doctor WHERE license_no LIKE 'BULK-LIC-%');

INSERT INTO specialist (doctor_id, specialty_id, years_practice)
SELECT d.doctor_id, 1 + d.doctor_id % 6, 3 + d.doctor_id % 25
FROM doctor d
WHERE d.license_no LIKE 'BULK-LIC-%'
  AND NOT EXISTS (SELECT 1 FROM specialist sp WHERE sp.doctor_id = d.doctor_id);

UPDATE doctor SET is_active = TRUE WHERE license_no LIKE 'BULK-LIC-%' AND is_active = FALSE;

-- ---------- 2. shifts: 41 doctors x 60 days (BR-24: part-time shifts carry a rate) ----------
INSERT INTO shift (doctor_id, shift_date, start_time, end_time, status, room_id, rate_per_hour)
WITH RECURSIVE days (k) AS (SELECT 0 UNION ALL SELECT k + 1 FROM days WHERE k < 59)
SELECT d.doctor_id, DATE_ADD('2026-01-05', INTERVAL days.k DAY), '08:00:00', '12:00:00', 'ACTIVE', NULL,
       IF(d.employment_type = 'PART_TIME', 200000 + (d.doctor_id % 5) * 20000, NULL)
FROM doctor d
CROSS JOIN days
WHERE d.license_no LIKE 'BULK-LIC-%'
  AND NOT EXISTS (SELECT 1 FROM shift s WHERE s.doctor_id = d.doctor_id AND s.shift_date >= '2026-01-05'
                                           AND s.shift_date < '2026-03-06');

-- ---------- 3. appointments: 8 slots per bulk shift, all start as PENDING (BR-11) ----------
-- Every 64th slot goes to one "heavy user" (the first bulk patient) so Q03 has a long history.
SET @p0 = (SELECT MIN(patient_id) FROM patient WHERE full_name LIKE 'Bulk Patient %');

INSERT INTO appointment (patient_id, shift_id, start_time, end_time, appointment_type, status)
WITH RECURSIVE slots (j) AS (SELECT 0 UNION ALL SELECT j + 1 FROM slots WHERE j < 7)
SELECT IF((s.shift_id * 8 + slots.j) % 64 = 0, @p0, @p0 + ((s.shift_id * 8 + slots.j) * 7919) % 10000),
       s.shift_id,
       TIMESTAMP(s.shift_date, s.start_time) + INTERVAL (slots.j * 30) MINUTE,
       TIMESTAMP(s.shift_date, s.start_time) + INTERVAL (slots.j * 30 + 30) MINUTE,
       IF((s.shift_id + slots.j) % 3 = 0, 'TELEMEDICINE', 'IN_PERSON'),
       'PENDING'
FROM shift s
JOIN doctor d ON d.doctor_id = s.doctor_id AND d.license_no LIKE 'BULK-LIC-%'
CROSS JOIN slots
WHERE NOT EXISTS (SELECT 1 FROM appointment a WHERE a.shift_id = s.shift_id);

-- ---------- 4. lifecycle (BR-11): 10% cancelled, 70% completed, 20% stay PENDING ----------
-- (appointment_id % 10:  0 -> CANCELLED,  1..7 -> COMPLETED,  8..9 -> PENDING)
SET @first_bulk_appt = (SELECT MIN(a.appointment_id)
                          FROM appointment a JOIN shift s ON s.shift_id = a.shift_id
                          JOIN doctor d ON d.doctor_id = s.doctor_id AND d.license_no LIKE 'BULK-LIC-%');

UPDATE appointment SET status = 'CANCELLED'
 WHERE appointment_id >= @first_bulk_appt AND appointment_id % 10 = 0 AND status = 'PENDING';
UPDATE appointment SET status = 'CONFIRMED'
 WHERE appointment_id >= @first_bulk_appt AND appointment_id % 10 BETWEEN 1 AND 7 AND status = 'PENDING';
UPDATE appointment SET status = 'IN_PROGRESS'
 WHERE appointment_id >= @first_bulk_appt AND appointment_id % 10 BETWEEN 1 AND 7 AND status = 'CONFIRMED';
UPDATE appointment SET status = 'COMPLETED'
 WHERE appointment_id >= @first_bulk_appt AND appointment_id % 10 BETWEEN 1 AND 7 AND status = 'IN_PROGRESS';

-- ---------- 5. medical records for 3 of every 10 appointments (BR-12, audited by trigger) ----------
INSERT INTO medical_record (appointment_id, systolic_bp, diastolic_bp, heart_rate, temperature_c,
                            oxygen_saturation, symptoms, diagnosis, notes)
SELECT a.appointment_id,
       100 + a.appointment_id % 40, 60 + a.appointment_id % 25, 60 + a.appointment_id % 40,
       36.2 + (a.appointment_id % 15) / 10, 95 + a.appointment_id % 6,
       ELT(1 + a.appointment_id % 5, 'Cough and sore throat', 'Headache', 'Back pain', 'Fever', 'Dizziness'),
       ELT(1 + a.appointment_id % 5, 'Upper respiratory infection', 'Tension headache', 'Lumbar strain',
                                     'Viral fever', 'Orthostatic hypotension'),
       'Bulk seeded record'
FROM appointment a
WHERE a.appointment_id >= @first_bulk_appt AND a.status = 'COMPLETED' AND a.appointment_id % 10 IN (1, 2, 3)
  AND NOT EXISTS (SELECT 1 FROM medical_record mr WHERE mr.appointment_id = a.appointment_id);

-- ---------- 6. prescriptions for every second bulk record, 2 drugs each (BR-14 / BR-16) ----------
INSERT INTO prescription (record_id, issued_at)
SELECT mr.record_id, mr.created_at
FROM medical_record mr
JOIN appointment a ON a.appointment_id = mr.appointment_id
WHERE mr.notes = 'Bulk seeded record' AND mr.record_id % 2 = 0
  AND NOT EXISTS (SELECT 1 FROM prescription p WHERE p.record_id = mr.record_id);

SET @med_count = (SELECT COUNT(*) FROM medication);

INSERT INTO prescription_item (prescription_id, medication_id, quantity, dosage, frequency, duration_days)
WITH RECURSIVE k (x) AS (SELECT 0 UNION ALL SELECT 1)
SELECT p.prescription_id,
       1 + (p.prescription_id * 31 + k.x * 17) % @med_count,
       1 + (p.prescription_id + k.x) % 20,
       '1 unit', 'Twice daily', 3 + p.prescription_id % 10
FROM prescription p
JOIN medical_record mr ON mr.record_id = p.record_id AND mr.notes = 'Bulk seeded record'
CROSS JOIN k
WHERE NOT EXISTS (SELECT 1 FROM prescription_item pi WHERE pi.prescription_id = p.prescription_id);

-- ---------- summary ----------
SELECT (SELECT COUNT(*) FROM doctor WHERE is_active)  AS active_doctors,
       (SELECT COUNT(*) FROM patient)                 AS patients,
       (SELECT COUNT(*) FROM shift)                   AS shifts,
       (SELECT COUNT(*) FROM appointment)             AS appointments,
       (SELECT COUNT(*) FROM medical_record)          AS medical_records,
       (SELECT COUNT(*) FROM prescription_item)       AS prescription_items,
       (SELECT COUNT(*) FROM medical_record_audit_log) AS audit_rows;
