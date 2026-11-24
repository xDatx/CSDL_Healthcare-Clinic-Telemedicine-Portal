-- Author: Phạm Trần Quốc Việt
-- Module: Prescription + consultation queries
--   Q04 full detail of one prescription           (7-table join)
--   Q05 most prescribed drugs with rank and share (aggregate + window over aggregate)
--   Q09 approved consultations and their access window (CASE on time)
--   Q13 drugs that are prescribed together        (self-join on the associative table)
--   Q16 who may read a given record right now     (UNION of the two access paths, BR-21 / BR-22)
USE healthcare;

SET @q_prescription_id = 1;
SET @q_record_id       = 19;

-- -----------------------------------------------------------------------------
-- Q04: full prescription detail
-- -----------------------------------------------------------------------------
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
WHERE pr.prescription_id = @q_prescription_id
ORDER BY m.name;

-- -----------------------------------------------------------------------------
-- Q05: top 10 prescribed drugs: count, units, rank and share of all prescribed lines.
-- Ties share a rank (RANK), the share uses a window over the grouped result.
-- -----------------------------------------------------------------------------
SELECT medication_id, name, times_prescribed, total_quantity, rnk, share_pct
FROM (
    SELECT m.medication_id, m.name,
           COUNT(*)         AS times_prescribed,
           SUM(pi.quantity) AS total_quantity,
           RANK() OVER (ORDER BY COUNT(*) DESC, SUM(pi.quantity) DESC)  AS rnk,
           ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS share_pct
    FROM medication m
    JOIN prescription_item pi ON pi.medication_id = m.medication_id
    GROUP BY m.medication_id, m.name
) ranked
WHERE rnk <= 10
ORDER BY rnk, name;

-- -----------------------------------------------------------------------------
-- Q09: every APPROVED consultation and whether its access window is still open.
-- -----------------------------------------------------------------------------
SELECT cr.request_id, cr.record_id,
       rq.full_name AS requesting_doctor,
       cs.full_name AS consulting_doctor,
       cr.expires_at,
       CASE WHEN cr.expires_at IS NULL                          THEN 'NO_EXPIRY'
            WHEN cr.expires_at <= NOW()                         THEN 'EXPIRED'
            WHEN cr.expires_at <= NOW() + INTERVAL 24 HOUR      THEN 'EXPIRING_WITHIN_24H'
            ELSE 'ACTIVE' END AS access_state,
       TIMESTAMPDIFF(HOUR, NOW(), cr.expires_at) AS hours_remaining
FROM consultation_request cr
JOIN doctor rq ON rq.doctor_id = cr.requesting_doctor_id
JOIN doctor cs ON cs.doctor_id = cr.consulting_doctor_id
WHERE cr.status = 'APPROVED'
ORDER BY cr.expires_at IS NULL, cr.expires_at;

-- -----------------------------------------------------------------------------
-- Q13: pairs of drugs prescribed together on the same prescription (a < b avoids mirrors).
-- -----------------------------------------------------------------------------
SELECT m1.name AS drug_a, m2.name AS drug_b, COUNT(*) AS prescribed_together
FROM prescription_item p1
JOIN prescription_item p2 ON p2.prescription_id = p1.prescription_id
                         AND p1.medication_id < p2.medication_id
JOIN medication m1 ON m1.medication_id = p1.medication_id
JOIN medication m2 ON m2.medication_id = p2.medication_id
GROUP BY m1.medication_id, m1.name, m2.medication_id, m2.name
ORDER BY prescribed_together DESC, drug_a, drug_b
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Q16: everybody who can read a record right now: the treating doctor (BR-21) plus consulting
-- doctors with a live APPROVED request (BR-22). Mirrors fn_can_read_record for doctors.
-- -----------------------------------------------------------------------------
SELECT 'TREATING' AS access_path, d.doctor_id, d.full_name, d.spec_type, NULL AS valid_until
FROM medical_record mr
JOIN appointment a ON a.appointment_id = mr.appointment_id
JOIN shift s       ON s.shift_id = a.shift_id
JOIN doctor d      ON d.doctor_id = s.doctor_id
WHERE mr.record_id = @q_record_id
UNION ALL
SELECT 'CONSULTING', d.doctor_id, d.full_name, d.spec_type, v.expires_at
FROM v_active_consultation_access v
JOIN doctor d ON d.doctor_id = v.consulting_doctor_id
WHERE v.record_id = @q_record_id;
