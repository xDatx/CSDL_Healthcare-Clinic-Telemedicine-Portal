-- Author: Lý Thành Đạt
-- Module: Doctor operations queries
--   Q07 pay of PART_TIME doctors (hours x the rate of EACH shift, with grand total)
--   Q08 doctors without any ACTIVE shift in the next 7 days (anti-join)
USE healthcare;

-- -----------------------------------------------------------------------------
-- Q07: BR-24. The rate belongs to the shift, so pay = SUM(hours * rate), never SUM(hours) * rate.
-- Reads the view v_part_time_pay; WITH ROLLUP adds the clinic-wide total row (doctor_id NULL).
-- -----------------------------------------------------------------------------
SELECT doctor_id,
       IF(GROUPING(doctor_id), 'ALL PART-TIME DOCTORS', MAX(doctor_name)) AS doctor_name,
       COUNT(*)           AS shifts,
       SUM(hours_worked)  AS total_hours,
       SUM(shift_pay)     AS total_pay
FROM v_part_time_pay
GROUP BY doctor_id WITH ROLLUP
ORDER BY GROUPING(doctor_id), total_pay DESC;

-- -----------------------------------------------------------------------------
-- Q08: active doctors with nothing scheduled in the coming week (candidates for new shifts).
-- -----------------------------------------------------------------------------
SELECT d.doctor_id, d.full_name, d.spec_type, d.employment_type,
       (SELECT MAX(s2.shift_date) FROM shift s2
         WHERE s2.doctor_id = d.doctor_id AND s2.status = 'ACTIVE') AS last_shift_date
FROM doctor d
WHERE d.is_active = TRUE
  AND NOT EXISTS (SELECT 1 FROM shift s
                   WHERE s.doctor_id = d.doctor_id AND s.status = 'ACTIVE'
                     AND s.shift_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 6 DAY)
ORDER BY last_shift_date, d.doctor_id;
