-- Author: Phạm Trần Quốc Việt
-- Enforces: BR-19, BR-23, BR-25
-- MySQL 8.0.16+

USE healthcare;
DELIMITER $$

-- ===== BR-25: medication audit =====
CREATE TRIGGER trg_med_audit_insert
AFTER INSERT ON medication
FOR EACH ROW
BEGIN
    INSERT INTO medication_audit_log (medication_id, admin_id, action, new_values)
    VALUES (NEW.medication_id, COALESCE(@app_actor_id, 0), 'INSERT',
            JSON_OBJECT('name', NEW.name, 'unit', NEW.unit, 'is_active', NEW.is_active));
END$$

CREATE TRIGGER trg_med_audit_update
AFTER UPDATE ON medication
FOR EACH ROW
BEGIN
    DECLARE v_action VARCHAR(15);
    IF OLD.is_active = TRUE AND NEW.is_active = FALSE THEN
        SET v_action = 'DEACTIVATE';
    ELSE
        SET v_action = 'UPDATE';
    END IF;
    INSERT INTO medication_audit_log (medication_id, admin_id, action, old_values, new_values)
    VALUES (NEW.medication_id, COALESCE(@app_actor_id, 0), v_action,
            JSON_OBJECT('name', OLD.name, 'is_active', OLD.is_active),
            JSON_OBJECT('name', NEW.name, 'is_active', NEW.is_active));
END$$

-- ===== NFR-04: medication audit immutable =====
CREATE TRIGGER trg_med_audit_immutable_update
BEFORE UPDATE ON medication_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: medication audit log is append-only';
END$$

CREATE TRIGGER trg_med_audit_immutable_delete
BEFORE DELETE ON medication_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: medication audit log is append-only';
END$$

-- ===== BR-19: block hard delete =====
CREATE TRIGGER trg_med_no_hard_delete
BEFORE DELETE ON medication
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM prescription_item WHERE medication_id = OLD.medication_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-19: cannot hard-delete medication referenced by prescriptions';
    END IF;
END$$

-- ===== BR-23: requesting doctor must be treating doctor =====
CREATE TRIGGER trg_consultation_validate
BEFORE INSERT ON consultation_request
FOR EACH ROW
BEGIN
    DECLARE v_treating INT;
    SELECT s.doctor_id INTO v_treating
    FROM medical_record mr
    JOIN appointment a ON a.appointment_id = mr.appointment_id
    JOIN shift s      ON s.shift_id = a.shift_id
    WHERE mr.record_id = NEW.record_id;
    IF v_treating IS NULL OR v_treating <> NEW.requesting_doctor_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-23: requesting doctor is not treating doctor';
    END IF;
END$$

DELIMITER ;
