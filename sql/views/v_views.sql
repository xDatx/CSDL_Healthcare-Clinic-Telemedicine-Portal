USE healthcare;

-- INTERNAL ONLY: contains diagnoses of all patients. No application role is granted SELECT on it
-- (patients use sp_patient_history, doctors/admins use sp_read_medical_record).
CREATE OR REPLACE VIEW v_patient_medical_history AS
SELECT p.patient_id, p.full_name AS patient_name,
       a.appointment_id, a.start_time, a.appointment_type, a.status AS appt_status,
       d.full_name AS doctor_name, d.spec_type,
       mr.record_id, mr.diagnosis, mr.symptoms
FROM patient p
JOIN appointment a ON a.patient_id = p.patient_id
JOIN shift s       ON s.shift_id = a.shift_id
JOIN doctor d      ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr ON mr.appointment_id = a.appointment_id
WHERE a.status = 'COMPLETED';

-- FR-02: free capacity (minutes) of every ACTIVE shift of an active doctor
CREATE OR REPLACE VIEW v_doctor_availability AS
SELECT s.shift_id, s.doctor_id, d.full_name AS doctor_name, d.spec_type,
       s.shift_date, s.start_time AS shift_start, s.end_time AS shift_end,
       r.room_code,
       TIME_TO_SEC(TIMEDIFF(s.end_time, s.start_time)) DIV 60                AS shift_minutes,
       COALESCE(b.booked_minutes, 0)                                         AS booked_minutes,
       TIME_TO_SEC(TIMEDIFF(s.end_time, s.start_time)) DIV 60
         - COALESCE(b.booked_minutes, 0)                                     AS free_minutes,
       COALESCE(b.booked_count, 0)                                           AS booked_count
FROM shift s
JOIN doctor d    ON d.doctor_id = s.doctor_id
LEFT JOIN room r ON r.room_id = s.room_id
LEFT JOIN (SELECT shift_id,
                  CAST(SUM(TIMESTAMPDIFF(MINUTE, start_time, end_time)) AS SIGNED) AS booked_minutes,
                  COUNT(*) AS booked_count
             FROM appointment
            WHERE status <> 'CANCELLED'
            GROUP BY shift_id) b ON b.shift_id = s.shift_id
WHERE s.status = 'ACTIVE' AND d.is_active = TRUE;

-- BR-22: consultations that currently grant read-only access
CREATE OR REPLACE VIEW v_active_consultation_access AS
SELECT cr.request_id, cr.record_id,
       cr.requesting_doctor_id, rq.full_name AS requesting_doctor_name,
       cr.consulting_doctor_id, cs.full_name AS consulting_doctor_name,
       cr.responded_at, cr.expires_at
FROM consultation_request cr
JOIN doctor rq ON rq.doctor_id = cr.requesting_doctor_id
JOIN doctor cs ON cs.doctor_id = cr.consulting_doctor_id
WHERE cr.status = 'APPROVED'
  AND (cr.expires_at IS NULL OR cr.expires_at > NOW());

-- Derived relationship APPOINTMENT -> DOCTOR (the doctor is reached through the shift, 3NF).
-- No clinical content, so it is safe for front-desk and doctor roles.
CREATE OR REPLACE VIEW v_appointment_detail AS
SELECT a.appointment_id, s.shift_date AS appointment_date, a.start_time, a.end_time,
       a.appointment_type, a.status,
       a.patient_id, p.full_name AS patient_name,
       s.doctor_id, d.full_name AS doctor_name, d.spec_type,
       r.room_code, a.shift_id
FROM appointment a
JOIN patient p   ON p.patient_id = a.patient_id
JOIN shift s     ON s.shift_id = a.shift_id
JOIN doctor d    ON d.doctor_id = s.doctor_id
LEFT JOIN room r ON r.room_id = s.room_id;

-- BR-24: pay per shift of PART_TIME doctors (hours x rate agreed for that shift)
CREATE OR REPLACE VIEW v_part_time_pay AS
SELECT s.shift_id, s.doctor_id, d.full_name AS doctor_name, s.shift_date,
       ROUND(TIME_TO_SEC(TIMEDIFF(s.end_time, s.start_time)) / 3600, 2) AS hours_worked,
       s.rate_per_hour,
       ROUND(TIME_TO_SEC(TIMEDIFF(s.end_time, s.start_time)) / 3600 * s.rate_per_hour, 2) AS shift_pay
FROM shift s
JOIN doctor d ON d.doctor_id = s.doctor_id
WHERE d.employment_type = 'PART_TIME' AND s.status = 'ACTIVE';

-- Medication catalog for doctors / patients (FR-13)
CREATE OR REPLACE VIEW v_active_medication AS
SELECT medication_id, name, unit, description
FROM medication
WHERE is_active = TRUE;

-- Active doctor directory for consultation peer selection (hides email, license_no)
CREATE OR REPLACE VIEW v_active_doctor_directory AS
SELECT d.doctor_id, d.full_name, d.spec_type,
       s.name AS specialty_name, sp.years_practice
FROM doctor d
LEFT JOIN specialist sp ON sp.doctor_id = d.doctor_id
LEFT JOIN specialty s   ON s.specialty_id = sp.specialty_id
WHERE d.is_active = TRUE;
