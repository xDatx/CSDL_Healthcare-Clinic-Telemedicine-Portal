-- Author: Phạm Trần Quốc Việt
-- Q06: Doctor utilization — appointments per active shift
SELECT d.doctor_id, d.full_name, d.spec_type,
       COUNT(DISTINCT s.shift_id) AS total_active_shifts,
       COUNT(DISTINCT a.appointment_id) AS completed_appointments,
       ROUND(
           COUNT(DISTINCT a.appointment_id) /
           NULLIF(COUNT(DISTINCT s.shift_id), 0),
           2
       ) AS appts_per_shift
FROM doctor d
LEFT JOIN shift s
       ON s.doctor_id = d.doctor_id AND s.status = 'ACTIVE'
LEFT JOIN appointment a
       ON a.shift_id = s.shift_id AND a.status = 'COMPLETED'
WHERE d.is_active = TRUE
GROUP BY d.doctor_id, d.full_name, d.spec_type
ORDER BY appts_per_shift DESC, completed_appointments DESC;
