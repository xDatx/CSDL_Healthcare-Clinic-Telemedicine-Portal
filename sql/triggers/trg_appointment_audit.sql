-- Author: Nguyễn Hoàng Dũng
-- Enforces: BR-08, BR-09, BR-11, BR-12, NFR-04
-- MySQL 8.0.16+

USE healthcare;
DELIMITER $$

-- ===== BR-08: appointment must be inside ACTIVE shift =====
CREATE TRIGGER trg_appointment_in_shift_insert
BEFORE INSERT ON appointment
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(10);
    DECLARE v_date DATE;
    DECLARE v_start TIME;
    DECLARE v_end TIME;
    SELECT status, shift_date, start_time, end_time
      INTO v_status, v_date, v_start, v_end
      FROM shift WHERE shift_id = NEW.shift_id;
    IF v_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: shift is not ACTIVE';
    END IF;
    IF DATE(NEW.start_time) <> v_date OR DATE(NEW.end_time) <> v_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment must be on shift date';
    END IF;
    IF TIME(NEW.start_time) < v_start OR TIME(NEW.end_time) > v_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment outside shift hours';
    END IF;
END$$

CREATE TRIGGER trg_appointment_in_shift_update
BEFORE UPDATE ON appointment
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(10);
    DECLARE v_date DATE;
    DECLARE v_start TIME;
    DECLARE v_end TIME;
    SELECT status, shift_date, start_time, end_time
      INTO v_status, v_date, v_start, v_end
      FROM shift WHERE shift_id = NEW.shift_id;
    IF v_status <> 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: shift is not ACTIVE';
    END IF;
    IF DATE(NEW.start_time) <> v_date OR DATE(NEW.end_time) <> v_date THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment must be on shift date';
    END IF;
    IF TIME(NEW.start_time) < v_start OR TIME(NEW.end_time) > v_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08: appointment outside shift hours';
    END IF;
END$$

-- ===== BR-09: strict anti-double-booking =====
CREATE TRIGGER trg_appointment_no_overlap_insert
BEFORE INSERT ON appointment
FOR EACH ROW
BEGIN
    IF NEW.status <> 'CANCELLED' AND EXISTS (
        SELECT 1 FROM appointment a
        WHERE a.shift_id = NEW.shift_id
          AND a.status <> 'CANCELLED'
          AND NEW.start_time < a.end_time
          AND a.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-09: overlapping appointment in shift';
    END IF;
END$$

CREATE TRIGGER trg_appointment_no_overlap_update
BEFORE UPDATE ON appointment
FOR EACH ROW
BEGIN
    IF NEW.status <> 'CANCELLED' AND EXISTS (
        SELECT 1 FROM appointment a
        WHERE a.shift_id = NEW.shift_id
          AND a.appointment_id <> OLD.appointment_id
          AND a.status <> 'CANCELLED'
          AND NEW.start_time < a.end_time
          AND a.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-09: overlapping appointment in shift';
    END IF;
END$$

-- ===== BR-11: status transitions =====
CREATE TRIGGER trg_appointment_transition
BEFORE UPDATE ON appointment
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        IF NOT (
            (OLD.status = 'PENDING'     AND NEW.status IN ('CONFIRMED','CANCELLED')) OR
            (OLD.status = 'CONFIRMED'   AND NEW.status IN ('IN_PROGRESS','CANCELLED')) OR
            (OLD.status = 'IN_PROGRESS' AND NEW.status = 'COMPLETED')
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-11: invalid status transition';
        END IF;
    END IF;
END$$

-- ===== BR-12: record requires COMPLETED appointment =====
CREATE TRIGGER trg_mr_requires_completed
BEFORE INSERT ON medical_record
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(15);
    SELECT status INTO v_status FROM appointment WHERE appointment_id = NEW.appointment_id;
    IF v_status <> 'COMPLETED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-12: medical record requires COMPLETED appointment';
    END IF;
END$$

-- ===== NFR-04: auto-audit writes =====
CREATE TRIGGER trg_mr_audit_insert
AFTER INSERT ON medical_record
FOR EACH ROW
BEGIN
    INSERT INTO medical_record_audit_log (record_id, actor_type, actor_id, action, details)
    VALUES (
        NEW.record_id, 'DOCTOR', COALESCE(@app_actor_id, 0), 'INSERT',
        JSON_OBJECT('new', JSON_OBJECT(
            'record_id', NEW.record_id,
            'appointment_id', NEW.appointment_id,
            'diagnosis', NEW.diagnosis
        ))
    );
END$$

CREATE TRIGGER trg_mr_audit_update
AFTER UPDATE ON medical_record
FOR EACH ROW
BEGIN
    INSERT INTO medical_record_audit_log (record_id, actor_type, actor_id, action, details)
    VALUES (
        NEW.record_id, 'DOCTOR', COALESCE(@app_actor_id, 0), 'UPDATE',
        JSON_OBJECT('old', JSON_OBJECT('diagnosis', OLD.diagnosis),
                    'new', JSON_OBJECT('diagnosis', NEW.diagnosis))
    );
END$$

-- ===== NFR-04: audit log immutable =====
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