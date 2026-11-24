-- Author: Phạm Trần Quốc Việt
-- Module: Doctor performance queries
--   Q06 utilisation: completed appointments per active shift
--   Q11 ranking inside each clinical role (GP / SPECIALIST) with DENSE_RANK
USE healthcare;

-- -----------------------------------------------------------------------------
-- Q06: doctor utilisation. DISTINCT on both counters because the two LEFT JOINs fan out.
-- -----------------------------------------------------------------------------
SELECT d.doctor_id, d.full_name, d.spec_type, d.employment_type,
       COUNT(DISTINCT s.shift_id)       AS active_shifts,
       COUNT(DISTINCT a.appointment_id) AS completed_appointments,
       ROUND(COUNT(DISTINCT a.appointment_id) / NULLIF(COUNT(DISTINCT s.shift_id), 0), 2) AS appts_per_shift
FROM doctor d
LEFT JOIN shift s       ON s.doctor_id = d.doctor_id AND s.status = 'ACTIVE'
LEFT JOIN appointment a ON a.shift_id = s.shift_id AND a.status = 'COMPLETED'
WHERE d.is_active = TRUE
GROUP BY d.doctor_id, d.full_name, d.spec_type, d.employment_type
ORDER BY appts_per_shift DESC, completed_appointments DESC, d.doctor_id;

-- -----------------------------------------------------------------------------
-- Q11: who handles the most completed visits within the same role. Ties get the same rank and
-- the next rank is not skipped (DENSE_RANK). Also shows the gap to the leader of the role.
-- -----------------------------------------------------------------------------
WITH per_doctor AS (
    SELECT d.doctor_id, d.full_name, d.spec_type,
           COUNT(a.appointment_id) AS completed
    FROM doctor d
    LEFT JOIN shift s       ON s.doctor_id = d.doctor_id
    LEFT JOIN appointment a ON a.shift_id = s.shift_id AND a.status = 'COMPLETED'
    WHERE d.is_active = TRUE
    GROUP BY d.doctor_id, d.full_name, d.spec_type
)
SELECT spec_type, doctor_id, full_name, completed,
       DENSE_RANK() OVER (PARTITION BY spec_type ORDER BY completed DESC) AS rank_in_role,
       MAX(completed) OVER (PARTITION BY spec_type) - completed           AS behind_leader
FROM per_doctor
ORDER BY spec_type, rank_in_role, full_name;
