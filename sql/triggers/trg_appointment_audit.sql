-- Author: Nguyễn Hoàng Dũng
-- Module: Appointment + Medical record + record-audit triggers
-- Enforces: BR-08, BR-09, BR-11, BR-12, NFR-04
-- MySQL 8.0.16+
--
-- Audit context (set by the application before a write):
--     SET @app_actor_type = 'DOCTOR';   -- PATIENT | DOCTOR | ADMIN
--     SET @app_actor_id   = <id of that actor>;
-- If @app_actor_type is NULL the audit row is attributed to the TREATING doctor of the record.

USE healthcare;
DELIMITER $$

-- ===== BR-08 + BR-09 in one routine =====
CREATE PROCEDURE sp_validate_appointment_slot(
    IN p_appt_id INT, IN p_shift_id INT, IN p_start DATETIME, IN p_end DATETIME,
    IN p_is_insert BOOLEAN)
BEGIN
    DECLARE v_status  VARCHAR(10);
    DECLARE v_date    DATE;
    DECLARE v_s_start TIME;
    DECLARE v_s_end   TIME;
    DECLARE v_active  BOOLEAN;

    SELECT s.status, s.shift_date, s.start_time, s.end_time, d.is_active
      INTO v_status, v_date, v_s_start, v_s_end, v_active
      FROM shift s JOIN doctor d ON d.doctor_id = s.doctor_id
     WHERE s.shift_id = p_shift_id;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-07: appointment must reference an existing shift';
    END IF;
    IF p_is_insert AND NOT v_active THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: appointments cannot be assigned to an inactive doctor';
    END IF;
    IF v_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: shift is not ACTIVE';
    END IF;
    IF DATE(p_start) <> v_date OR DATE(p_end) <> v_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment must be on shift date';
    END IF;
    IF TIME(p_start) < v_s_start OR TIME(p_end) > v_s_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment outside shift hours';
    END IF;
    IF EXISTS (SELECT 1 FROM appointment a
                WHERE a.shift_id = p_shift_id AND a.appointment_id <> p_appt_id
                  AND a.status <> 'CANCELLED'
                  AND p_start < a.end_time AND a.start_time < p_end) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-09: overlapping appointment in shift';
    END IF;
END$$

CREATE TRIGGER trg_appointment_validate_insert
BEFORE INSERT ON appointment
FOR EACH ROW
BEGIN
    -- BR-11: the lifecycle always starts at PENDING
    IF NEW.status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: a new appointment must start as PENDING';
    END IF;
    CALL sp_validate_appointment_slot(0, NEW.shift_id, NEW.start_time, NEW.end_time, TRUE);
END$$

CREATE TRIGGER trg_appointment_validate_update
BEFORE UPDATE ON appointment
FOR EACH ROW
BEGIN
    -- BR-11: allowed transitions only
    IF OLD.status <> NEW.status THEN
        IF NOT (   (OLD.status = 'PENDING'     AND NEW.status IN ('CONFIRMED','CANCELLED'))
                OR (OLD.status = 'CONFIRMED'   AND NEW.status IN ('IN_PROGRESS','CANCELLED'))
                OR (OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED')) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: invalid status transition';
        END IF;
    END IF;
    -- BR-08 / BR-09: re-check only when the slot itself moves (so a status change still works
    -- after the shift was cancelled)
    IF NEW.shift_id <> OLD.shift_id OR NEW.start_time <> OLD.start_time OR NEW.end_time <> OLD.end_time THEN
        IF OLD.status IN ('COMPLETED','CANCELLED') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: a COMPLETED or CANCELLED appointment cannot be moved';
        END IF;
        CALL sp_validate_appointment_slot(OLD.appointment_id, NEW.shift_id, NEW.start_time, NEW.end_time, FALSE);
    END IF;
END$$

-- ===== NFR-04: audit helpers =====
CREATE PROCEDURE sp_insert_record_audit(
    IN p_record_id INT, IN p_actor_type VARCHAR(10), IN p_actor_id INT,
    IN p_action VARCHAR(10), IN p_details JSON)
BEGIN
    IF p_actor_type IS NULL OR p_actor_type NOT IN ('PATIENT','DOCTOR','ADMIN') OR p_actor_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: actor must be PATIENT, DOCTOR or ADMIN with an id';
    END IF;
    INSERT INTO medical_record_audit_log (record_id, patient_id, doctor_id, admin_id, action, details)
    VALUES (p_record_id,
            IF(p_actor_type = 'PATIENT', p_actor_id, NULL),
            IF(p_actor_type = 'DOCTOR',  p_actor_id, NULL),
            IF(p_actor_type = 'ADMIN',   p_actor_id, NULL),
            p_action, p_details);
END$$

CREATE PROCEDURE sp_audit_from_session(
    IN p_record_id INT, IN p_appointment_id INT, IN p_action VARCHAR(10), IN p_details JSON)
BEGIN
    DECLARE v_type VARCHAR(10);
    DECLARE v_id   INT;
    IF @app_actor_type IS NOT NULL THEN
        SET v_type = @app_actor_type, v_id = @app_actor_id;
    ELSE
        SELECT 'DOCTOR', s.doctor_id INTO v_type, v_id
          FROM appointment a JOIN shift s ON s.shift_id = a.shift_id
         WHERE a.appointment_id = p_appointment_id;
    END IF;
    CALL sp_insert_record_audit(p_record_id, v_type, v_id, p_action, p_details);
END$$

-- ===== BR-12: a record needs a COMPLETED appointment and never moves / disappears =====
CREATE TRIGGER trg_mr_requires_completed
BEFORE INSERT ON medical_record
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(15);
    SELECT status INTO v_status FROM appointment WHERE appointment_id = NEW.appointment_id;
    IF v_status IS NULL OR v_status <> 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-12: medical record requires COMPLETED appointment';
    END IF;
END$$

CREATE TRIGGER trg_mr_appointment_immutable
BEFORE UPDATE ON medical_record
FOR EACH ROW
BEGIN
    IF NEW.appointment_id <> OLD.appointment_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-12: a record cannot be moved to another appointment';
    END IF;
END$$

CREATE TRIGGER trg_mr_no_delete
BEFORE DELETE ON medical_record
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: medical records are never deleted';
END$$

-- ===== NFR-04: audit of writes =====
CREATE TRIGGER trg_mr_audit_insert
AFTER INSERT ON medical_record
FOR EACH ROW
BEGIN
    CALL sp_audit_from_session(NEW.record_id, NEW.appointment_id, 'INSERT',
        JSON_OBJECT('new', JSON_OBJECT('appointment_id', NEW.appointment_id,
                                       'diagnosis', NEW.diagnosis)));
END$$

CREATE TRIGGER trg_mr_audit_update
AFTER UPDATE ON medical_record
FOR EACH ROW
BEGIN
    CALL sp_audit_from_session(NEW.record_id, NEW.appointment_id, 'UPDATE',
        JSON_OBJECT('old', JSON_OBJECT('diagnosis', OLD.diagnosis, 'notes', OLD.notes),
                    'new', JSON_OBJECT('diagnosis', NEW.diagnosis, 'notes', NEW.notes)));
END$$

-- ===== NFR-04: audit log is append-only =====
CREATE TRIGGER trg_mr_audit_immutable_update
BEFORE UPDATE ON medical_record_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: audit log is append-only';
END$$

CREATE TRIGGER trg_mr_audit_immutable_delete
BEFORE DELETE ON medical_record_audit_log
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-04: audit log is append-only';
END$$

DELIMITER ;
