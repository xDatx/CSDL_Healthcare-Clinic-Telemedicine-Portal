USE healthcare;

-- Q07: part-time doctors ranked by hours & pay
SELECT d.doctor_id, d.full_name,
       COUNT(s.shift_id) AS shift_count,
       SUM(TIMESTAMPDIFF(MINUTE, s.start_time, s.end_time)) / 60 AS total_hours,
       SUM(TIMESTAMPDIFF(MINUTE, s.start_time, s.end_time)) / 60 * s.rate_per_hour AS total_pay
FROM doctor d
JOIN shift s ON s.doctor_id = d.doctor_id AND s.status = 'ACTIVE'
WHERE d.employment_type = 'PART_TIME'
GROUP BY d.doctor_id, d.full_name, s.rate_per_hour
ORDER BY total_hours DESC;

-- Q08: doctors with zero shifts
SELECT d.doctor_id, d.full_name, d.spec_type, d.created_at
FROM doctor d
WHERE NOT EXISTS (SELECT 1 FROM shift s WHERE s.doctor_id = d.doctor_id)
ORDER BY d.created_at DESC;
