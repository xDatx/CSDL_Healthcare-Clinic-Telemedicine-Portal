USE healthcare;

-- Q04: full prescription detail
SELECT pr.prescription_id, pr.issued_at, mr.record_id,
       p.full_name AS patient_name, d.full_name AS doctor_name,
       m.name AS medication_name, pi.quantity, pi.dosage, pi.frequency, pi.duration_days
FROM prescription pr
JOIN medical_record mr     ON mr.record_id = pr.record_id
JOIN appointment a         ON a.appointment_id = mr.appointment_id
JOIN patient p             ON p.patient_id = a.patient_id
JOIN shift s               ON s.shift_id = a.shift_id
JOIN doctor d              ON d.doctor_id = s.doctor_id
JOIN prescription_item pi  ON pi.prescription_id = pr.prescription_id
JOIN medication m          ON m.medication_id = pi.medication_id
WHERE pr.prescription_id = 1
ORDER BY m.name;

-- Q05: top prescribed medications
SELECT m.medication_id, m.name,
       COUNT(pi.item_id) AS times_prescribed,
       SUM(pi.quantity)  AS total_quantity
FROM medication m
JOIN prescription_item pi ON pi.medication_id = m.medication_id
GROUP BY m.medication_id, m.name
HAVING COUNT(pi.item_id) >= 1
ORDER BY times_prescribed DESC, total_quantity DESC
LIMIT 10;

-- Q09: approved consultations expiring within 24h
SELECT cr.request_id, cr.record_id,
       rdoc.full_name AS requesting_doctor,
       cdoc.full_name AS consulting_doctor,
       cr.expires_at,
       TIMESTAMPDIFF(MINUTE, NOW(), cr.expires_at) AS minutes_remaining
FROM consultation_request cr
JOIN doctor rdoc ON rdoc.doctor_id = cr.requesting_doctor_id
JOIN doctor cdoc ON cdoc.doctor_id = cr.consulting_doctor_id
WHERE cr.status = 'APPROVED'
  AND cr.expires_at BETWEEN NOW() AND NOW() + INTERVAL 24 HOUR
ORDER BY cr.expires_at;
