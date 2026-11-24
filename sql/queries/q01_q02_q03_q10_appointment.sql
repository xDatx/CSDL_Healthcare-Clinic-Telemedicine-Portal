USE healthcare;

-- Q01: free shifts for a doctor on a given date
-- Params: replace 1 and CURRENT_DATE
SELECT sh.shift_id, sh.start_time AS shift_start, sh.end_time AS shift_end
FROM shift sh
WHERE sh.status = 'ACTIVE'
  AND sh.doctor_id = 1
  AND sh.shift_date = CURRENT_DATE
  AND NOT EXISTS (
      SELECT 1 FROM appointment a
      WHERE a.shift_id = sh.shift_id AND a.status <> 'CANCELLED'
  );

-- Q02: double-booking detector (expect 0 rows)
SELECT a1.appointment_id AS a, a2.appointment_id AS b,
       a1.shift_id, a1.start_time, a1.end_time, a2.start_time, a2.end_time
FROM appointment a1
JOIN appointment a2
  ON a1.shift_id = a2.shift_id
 AND a1.appointment_id < a2.appointment_id
WHERE a1.status <> 'CANCELLED' AND a2.status <> 'CANCELLED'
  AND a1.start_time < a2.end_time
  AND a2.start_time < a1.end_time;

-- Q03: patient full history
-- Param: replace :patient_id
SELECT a.appointment_id, a.start_time, a.status, a.appointment_type,
       d.full_name AS doctor_name, d.spec_type,
       mr.diagnosis, mr.symptoms,
       pr.prescription_id, COUNT(pi.item_id) AS meds
FROM appointment a
JOIN patient p      ON p.patient_id = a.patient_id
JOIN shift s        ON s.shift_id = a.shift_id
JOIN doctor d       ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr    ON mr.appointment_id = a.appointment_id
LEFT JOIN prescription pr      ON pr.record_id = mr.record_id
LEFT JOIN prescription_item pi ON pi.prescription_id = pr.prescription_id
WHERE p.patient_id = 1
GROUP BY a.appointment_id, a.start_time, a.status, a.appointment_type,
         d.full_name, d.spec_type, mr.diagnosis, mr.symptoms, pr.prescription_id
ORDER BY a.start_time DESC;

-- Q10: audit log of SELECTs on medical records
SELECT al.audit_id, al.record_id, al.actor_type, al.actor_id,
       al.action, al.action_at,
       CASE al.actor_type
         WHEN 'PATIENT' THEN (SELECT full_name FROM patient WHERE patient_id = al.actor_id)
         WHEN 'DOCTOR'  THEN (SELECT full_name FROM doctor  WHERE doctor_id  = al.actor_id)
         WHEN 'ADMIN'   THEN (SELECT full_name FROM admin   WHERE admin_id   = al.actor_id)
       END AS actor_name
FROM medical_record_audit_log al
WHERE al.action = 'SELECT'
ORDER BY al.action_at DESC
LIMIT 50;