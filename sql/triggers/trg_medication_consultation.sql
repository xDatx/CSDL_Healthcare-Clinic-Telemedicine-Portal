-- Author: Phạm Trần Quốc Việt
-- Module: Medication catalog + Consultation request triggers
-- Enforces: BR-19, BR-22, BR-23, BR-25
-- MySQL 8.0.16+
--
-- Audit context for the catalog (set by the application before a write):
--     SET @app_actor_id = <admin_id>;
-- A change without a valid admin in @app_actor_id is rejected.

USE healthcare;
DELIMITER $$

-- ===== BR-25: who is changing the catalog? =====
CREATE PROCEDURE sp_require_admin_actor()
BEGIN
    IF @app_actor_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM admin WHERE admin_id = @app_actor_id AND is_active = TRUE) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-25: set @app_actor_id to an active admin before changing the medication catalog';
    END IF;
END$$

CREATE TRIGGER trg_med_require_actor_insert
BEFORE INSERT ON medication
FOR EACH ROW
BEGIN
    CALL sp_require_admin_actor();
END$$

CREATE TRIGGER trg_med_require_actor_update
BEFORE UPDATE ON medication
FOR EACH ROW
BEGIN
    CALL sp_require_admin_actor();
END$$

-- ===== BR-19: medications are deactivated, never deleted =====
CREATE TRIGGER trg_med_no_hard_delete
BEFORE DELETE ON medication
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-19: medications are never deleted; set is_active = FALSE instead';
END$$

-- ===== BR-25: audit of every change =====
CREATE TRIGGER trg_med_audit_insert
AFTER INSERT ON medication
FOR EACH ROW
BEGIN
    INSERT INTO medication_audit_log (medication_id, admin_id, action, new_values)
    VALUES (NEW.medication_id, @app_actor_id, 'INSERT',
            JSON_OBJECT('name', NEW.name, 'unit', NEW.unit, 'is_active', NEW.is_active));
END$$

CREATE TRIGGER trg_med_audit_update
AFTER UPDATE ON medication
FOR EACH ROW
BEGIN
    INSERT INTO medication_audit_log (medication_id, admin_id, action, old_values, new_values)
    VALUES (NEW.medication_id, @app_actor_id,
            IF(OLD.is_active AND NOT NEW.is_active, 'DEACTIVATE', 'UPDATE'),
            JSON_OBJECT('name', OLD.name, 'unit', OLD.unit, 'is_active', OLD.is_active),
            JSON_OBJECT('name', NEW.name, 'unit', NEW.unit, 'is_active', NEW.is_active));
END$$

CREATE TRIGGER trg_med_audit_immutable_update
BEFORE UPDATE ON medication_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-25: medication audit log is append-only';
END$$

CREATE TRIGGER trg_med_audit_immutable_delete
BEFORE DELETE ON medication_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-25: medication audit log is append-only';
END$$

-- ===== BR-22 / BR-23: consultation request =====
CREATE TRIGGER trg_consultation_validate
BEFORE INSERT ON consultation_request
FOR EACH ROW
BEGIN
    DECLARE v_treating INT;
    DECLARE v_active   BOOLEAN;
    SELECT s.doctor_id INTO v_treating
      FROM medical_record mr
      JOIN appointment a ON a.appointment_id = mr.appointment_id
      JOIN shift s       ON s.shift_id = a.shift_id
     WHERE mr.record_id = NEW.record_id;
    IF v_treating IS NULL OR v_treating <> NEW.requesting_doctor_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-23: requesting doctor is not treating doctor';
    END IF;
    SELECT is_active INTO v_active FROM doctor WHERE doctor_id = NEW.consulting_doctor_id;
    IF v_active IS NULL OR NOT v_active THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: consulting doctor must be an active doctor';
    END IF;
    IF NEW.status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: a new consultation request must start as PENDING';
    END IF;
END$$

CREATE TRIGGER trg_consultation_transition
BEFORE UPDATE ON consultation_request
FOR EACH ROW
BEGIN
    IF NEW.record_id <> OLD.record_id OR NEW.requesting_doctor_id <> OLD.requesting_doctor_id
       OR NEW.consulting_doctor_id <> OLD.consulting_doctor_id OR NEW.reason <> OLD.reason THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-23: record, doctors and reason of a request are immutable';
    END IF;
    IF NEW.status <> OLD.status THEN
        IF NOT (   (OLD.status = 'PENDING'  AND NEW.status IN ('APPROVED','DECLINED'))
                OR (OLD.status = 'APPROVED' AND NEW.status = 'COMPLETED')) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: invalid consultation status transition';
        END IF;
        IF NEW.status = 'COMPLETED' AND OLD.expires_at IS NOT NULL AND OLD.expires_at < NOW() THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: the access window has expired';
        END IF;
        IF OLD.status = 'PENDING' AND NEW.responded_at IS NULL THEN
            SET NEW.responded_at = NOW();
        END IF;
    END IF;
END$$

DELIMITER ;
