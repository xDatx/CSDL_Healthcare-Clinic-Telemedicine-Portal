USE healthcare;

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

CREATE OR REPLACE VIEW v_doctor_availability AS
SELECT s.shift_id, s.doctor_id, d.full_name AS doctor_name,
       s.shift_date, s.start_time AS shift_start, s.end_time AS shift_end,
       (SELECT COUNT(*) FROM appointment a
        WHERE a.shift_id = s.shift_id AND a.status <> 'CANCELLED') AS booked_count
FROM shift s
JOIN doctor d ON d.doctor_id = s.doctor_id
WHERE s.status = 'ACTIVE' AND d.is_active = TRUE;

CREATE OR REPLACE VIEW v_active_consultation_access AS
SELECT cr.request_id, cr.record_id, cr.consulting_doctor_id, cr.expires_at
FROM consultation_request cr
WHERE cr.status = 'APPROVED'
  AND (cr.expires_at IS NULL OR cr.expires_at > NOW());
