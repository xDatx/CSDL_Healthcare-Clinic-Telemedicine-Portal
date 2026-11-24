-- Author: Lý Thành Đạt
-- Module: Secure read of medical record with audit (NFR-02, NFR-04)
USE healthcare;

DROP PROCEDURE IF EXISTS sp_read_medical_record;
DELIMITER $$

CREATE PROCEDURE sp_read_medical_record(
    IN p_record_id  INT,
    IN p_actor_type VARCHAR(10),
    IN p_actor_id   INT
)
BEGIN
    -- 1. Audit the read
    INSERT INTO medical_record_audit_log (record_id, actor_type, actor_id, action)
    VALUES (p_record_id, p_actor_type, p_actor_id, 'SELECT');

    -- 2. Return the record
    SELECT mr.record_id, mr.appointment_id, mr.diagnosis, mr.symptoms,
           mr.systolic_bp, mr.diastolic_bp, mr.heart_rate,
           mr.temperature_c, mr.oxygen_saturation, mr.notes, mr.created_at
    FROM medical_record mr
    WHERE mr.record_id = p_record_id;
END$$

DELIMITER ;
