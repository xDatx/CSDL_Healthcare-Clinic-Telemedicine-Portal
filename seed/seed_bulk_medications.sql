-- Author: Lý Thành Đạt
-- Module: Bulk seed 2/3 - 500 extra medications (BR-25 audit applies, so an admin actor is set)
-- Idempotent: does nothing if the bulk medications already exist.
USE healthcare;

SET SESSION cte_max_recursion_depth = 100000;
SET @app_actor_id = 1;          -- BR-25: the catalog trigger needs an active admin

INSERT INTO medication (name, unit, description, is_active)
WITH RECURSIVE n (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 500
)
SELECT CONCAT('Bulk Medication ', LPAD(i, 3, '0')),
       ELT(1 + i % 4, 'tablet', 'capsule', 'bottle', 'tube'),
       CONCAT('Bulk seeded catalog entry #', i),
       i % 10 <> 0                       -- 10% inactive
FROM n
WHERE NOT EXISTS (SELECT 1 FROM medication WHERE name LIKE 'Bulk Medication %');

SET @app_actor_id = NULL;

SELECT COUNT(*) AS total_medications, SUM(is_active) AS active_medications FROM medication;
