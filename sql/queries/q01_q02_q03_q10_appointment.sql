-- Author: Nguyễn Hoàng Dũng
-- Module: Appointment queries
--   Q01 free time gaps of a doctor on a day      (CTE + LAG window)
--   Q02 double-booking / overlapping-shift detector (self-join, expect 0 rows)
--   Q03 full history of one patient               (5-table join + aggregate)
--   Q10 audit trail of reads on medical records   (multi-actor join)
--   Q12 daily load with running total and trend   (window functions)
--   Q14 patients with repeat visits + days between (LAG)
--   Q15 7-day capacity calendar incl. empty days  (recursive CTE)
USE healthcare;

-- Demo parameters (change freely)
SET @q_doctor_id  = 1;
SET @q_date       = '2026-11-25';
SET @q_patient_id = 1;

-- -----------------------------------------------------------------------------
-- Q01: bookable gaps inside the shifts of a doctor on a given day (FR-02).
-- booked  = every live appointment of the shift (one row per shift if none)
-- before  = gap before each appointment (from previous end, or shift start)
-- tail    = gap after the last appointment (or the whole shift if empty)
-- -----------------------------------------------------------------------------
WITH booked AS (
    SELECT s.shift_id, s.start_time AS shift_start, s.end_time AS shift_end,
           TIME(a.start_time) AS a_start, TIME(a.end_time) AS a_end
    FROM shift s
    LEFT JOIN appointment a ON a.shift_id = s.shift_id AND a.status <> 'CANCELLED'
    WHERE s.status = 'ACTIVE' AND s.doctor_id = @q_doctor_id AND s.shift_date = @q_date
),
before_gap AS (
    SELECT shift_id,
           COALESCE(LAG(a_end) OVER (PARTITION BY shift_id ORDER BY a_start), shift_start) AS gap_start,
           a_start AS gap_end
    FROM booked
    WHERE a_start IS NOT NULL
),
tail_gap AS (
    SELECT shift_id, MAX(COALESCE(a_end, shift_start)) AS gap_start, shift_end AS gap_end
    FROM booked
    GROUP BY shift_id, shift_end, shift_start
)
SELECT shift_id, gap_start, gap_end, TIME_TO_SEC(TIMEDIFF(gap_end, gap_start)) DIV 60 AS free_minutes
FROM (SELECT * FROM before_gap UNION ALL SELECT * FROM tail_gap) g
WHERE gap_end > gap_start
ORDER BY shift_id, gap_start;

-- -----------------------------------------------------------------------------
-- Q02: integrity detector, must return 0 rows (BR-05 / BR-09).
-- -----------------------------------------------------------------------------
SELECT 'APPOINTMENT_OVERLAP' AS problem, a1.appointment_id AS id_1, a2.appointment_id AS id_2, a1.shift_id AS ref
FROM appointment a1
JOIN appointment a2 ON a1.shift_id = a2.shift_id AND a1.appointment_id < a2.appointment_id
WHERE a1.status <> 'CANCELLED' AND a2.status <> 'CANCELLED'
  AND a1.start_time < a2.end_time AND a2.start_time < a1.end_time
UNION ALL
SELECT 'SHIFT_OVERLAP', s1.shift_id, s2.shift_id, s1.doctor_id
FROM shift s1
JOIN shift s2 ON s1.doctor_id = s2.doctor_id AND s1.shift_date = s2.shift_date
             AND s1.shift_id < s2.shift_id
WHERE s1.status = 'ACTIVE' AND s2.status = 'ACTIVE'
  AND s1.start_time < s2.end_time AND s2.start_time < s1.end_time;

-- -----------------------------------------------------------------------------
-- Q03: full history of one patient with the number of prescribed drugs (FR-04).
-- -----------------------------------------------------------------------------
SELECT a.appointment_id, a.start_time, a.status, a.appointment_type,
       d.full_name AS doctor_name, d.spec_type,
       mr.diagnosis, mr.symptoms,
       pr.prescription_id, COUNT(pi.medication_id) AS drugs
FROM appointment a
JOIN patient p      ON p.patient_id = a.patient_id
JOIN shift s        ON s.shift_id = a.shift_id
JOIN doctor d       ON d.doctor_id = s.doctor_id
LEFT JOIN medical_record mr    ON mr.appointment_id = a.appointment_id
LEFT JOIN prescription pr      ON pr.record_id = mr.record_id
LEFT JOIN prescription_item pi ON pi.prescription_id = pr.prescription_id
WHERE p.patient_id = @q_patient_id
GROUP BY a.appointment_id, a.start_time, a.status, a.appointment_type,
         d.full_name, d.spec_type, mr.diagnosis, mr.symptoms, pr.prescription_id
ORDER BY a.start_time DESC;

-- -----------------------------------------------------------------------------
-- Q10: who read medical records recently (NFR-04). The actor is one of three FKs.
-- -----------------------------------------------------------------------------
SELECT al.audit_id, al.record_id, al.action, al.action_at,
       CASE WHEN al.patient_id IS NOT NULL THEN 'PATIENT'
            WHEN al.doctor_id  IS NOT NULL THEN 'DOCTOR'
            ELSE 'ADMIN' END                                   AS actor_type,
       COALESCE(p.full_name, d.full_name, ad.full_name)        AS actor_name
FROM medical_record_audit_log al
LEFT JOIN patient p ON p.patient_id = al.patient_id
LEFT JOIN doctor  d ON d.doctor_id  = al.doctor_id
LEFT JOIN admin  ad ON ad.admin_id  = al.admin_id
WHERE al.action = 'SELECT'
ORDER BY al.action_at DESC, al.audit_id DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- Q12: appointments per day, running total, previous day and 3-day moving average.
-- -----------------------------------------------------------------------------
WITH daily AS (
    SELECT DATE(start_time) AS day,
           COUNT(*) AS booked,
           SUM(status = 'CANCELLED') AS cancelled
    FROM appointment
    GROUP BY DATE(start_time)
)
SELECT day, booked, cancelled,
       SUM(booked) OVER (ORDER BY day)                                   AS running_total,
       LAG(booked) OVER (ORDER BY day)                                   AS prev_day,
       booked - LAG(booked) OVER (ORDER BY day)                          AS change_vs_prev,
       ROUND(AVG(booked) OVER (ORDER BY day ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS moving_avg_3d
FROM daily
ORDER BY day;

-- -----------------------------------------------------------------------------
-- Q14: patients with at least two COMPLETED visits and the gap between them.
-- -----------------------------------------------------------------------------
SELECT patient_id, patient_name, visit_no, start_time,
       DATEDIFF(start_time, prev_visit) AS days_since_previous,
       doctor_name
FROM (
    SELECT p.patient_id, p.full_name AS patient_name, a.start_time, d.full_name AS doctor_name,
           ROW_NUMBER() OVER (PARTITION BY p.patient_id ORDER BY a.start_time) AS visit_no,
           LAG(a.start_time) OVER (PARTITION BY p.patient_id ORDER BY a.start_time) AS prev_visit,
           COUNT(*) OVER (PARTITION BY p.patient_id) AS visits
    FROM appointment a
    JOIN patient p ON p.patient_id = a.patient_id
    JOIN shift s   ON s.shift_id = a.shift_id
    JOIN doctor d  ON d.doctor_id = s.doctor_id
    WHERE a.status = 'COMPLETED'
) t
WHERE visits >= 2
ORDER BY patient_id, visit_no;

-- -----------------------------------------------------------------------------
-- Q15: next 7 days from today with free minutes; days without any shift show 0.
-- Recursive CTE builds the calendar, the LEFT JOIN keeps empty days.
-- -----------------------------------------------------------------------------
WITH RECURSIVE days (day) AS (
    SELECT CURRENT_DATE
    UNION ALL
    SELECT day + INTERVAL 1 DAY FROM days WHERE day < CURRENT_DATE + INTERVAL 6 DAY
)
SELECT days.day, DAYNAME(days.day) AS weekday,
       COUNT(v.shift_id)                  AS open_shifts,
       COALESCE(SUM(v.free_minutes), 0)   AS free_minutes,
       COALESCE(SUM(v.booked_count), 0)   AS booked_appointments
FROM days
LEFT JOIN v_doctor_availability v ON v.shift_date = days.day
GROUP BY days.day
ORDER BY days.day;
