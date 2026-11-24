-- Author: Lý Thành Đạt
-- Module: Doctor + Shift + Staff-permission triggers
-- Enforces: BR-01, BR-03, BR-05, BR-08 (shift side), BR-20, BR-24, BR-26
-- MySQL 8.0.16+
-- Convention: every rejection is SQLSTATE '45000' and the message starts with the rule id.

USE healthcare;
DELIMITER $$

-- ===== BR-01: total specialization =====
-- A doctor starts inactive and may be activated only when exactly one GP/SPECIALIST row exists.
CREATE TRIGGER trg_doctor_activation_insert
BEFORE INSERT ON doctor
FOR EACH ROW
BEGIN
    IF NEW.is_active THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-01: a new doctor must start inactive until a subtype row exists';
    END IF;
END$$

CREATE TRIGGER trg_doctor_activation_update
BEFORE UPDATE ON doctor
FOR EACH ROW
BEGIN
    DECLARE v_subtypes INT;
    IF NEW.is_active AND NOT OLD.is_active THEN
        SELECT (SELECT COUNT(*) FROM gp WHERE doctor_id = NEW.doctor_id)
             + (SELECT COUNT(*) FROM specialist WHERE doctor_id = NEW.doctor_id)
          INTO v_subtypes;
        IF v_subtypes <> 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-01: cannot activate a doctor without exactly one GP/SPECIALIST row';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_gp_no_orphan_active
BEFORE DELETE ON gp
FOR EACH ROW
BEGIN
    IF (SELECT is_active FROM doctor WHERE doctor_id = OLD.doctor_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-01: deactivate the doctor before removing the GP row';
    END IF;
END$$

CREATE TRIGGER trg_specialist_no_orphan_active
BEFORE DELETE ON specialist
FOR EACH ROW
BEGIN
    IF (SELECT is_active FROM doctor WHERE doctor_id = OLD.doctor_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-01: deactivate the doctor before removing the SPECIALIST row';
    END IF;
END$$

-- ===== SHIFT rules in one routine (p_shift_id = 0 means a new row) =====
-- BR-03 room rule, BR-26, BR-24 rate rule, BR-05 no overlap, BR-03 room clash,
-- BR-08 (a shift change must not leave live appointments outside the shift).
CREATE PROCEDURE sp_validate_shift(
    IN p_shift_id INT, IN p_doctor_id INT, IN p_room_id INT, IN p_date DATE,
    IN p_start TIME, IN p_end TIME, IN p_rate DECIMAL(10,2), IN p_status VARCHAR(10))
BEGIN
    DECLARE v_spec   VARCHAR(10);
    DECLARE v_emp    VARCHAR(10);
    DECLARE v_active BOOLEAN;

    SELECT spec_type, employment_type, is_active INTO v_spec, v_emp, v_active
      FROM doctor WHERE doctor_id = p_doctor_id;
    IF v_spec IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-04: unknown doctor for this shift';
    END IF;
    IF p_shift_id = 0 AND NOT v_active THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: only an active doctor can register shifts';
    END IF;

    IF v_spec = 'GP' AND p_room_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP shift requires room_id';
    END IF;
    IF v_spec = 'SPECIALIST' AND p_room_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-26: Specialist shift must not have room_id';
    END IF;

    IF v_emp = 'PART_TIME' AND p_rate IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: PART_TIME shift requires rate_per_hour';
    END IF;
    IF v_emp = 'FULL_TIME' AND p_rate IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: FULL_TIME shift must not carry rate_per_hour';
    END IF;

    IF p_status = 'ACTIVE' THEN
        IF EXISTS (SELECT 1 FROM shift s
                    WHERE s.doctor_id = p_doctor_id AND s.shift_date = p_date
                      AND s.status = 'ACTIVE' AND s.shift_id <> p_shift_id
                      AND p_start < s.end_time AND s.start_time < p_end) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-05: overlapping shift for doctor';
        END IF;
        IF p_room_id IS NOT NULL AND EXISTS (SELECT 1 FROM shift s
                    WHERE s.room_id = p_room_id AND s.shift_date = p_date
                      AND s.status = 'ACTIVE' AND s.shift_id <> p_shift_id
                      AND p_start < s.end_time AND s.start_time < p_end) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP room double-booked';
        END IF;
        IF p_shift_id <> 0 AND EXISTS (SELECT 1 FROM appointment a
                    WHERE a.shift_id = p_shift_id AND a.status <> 'CANCELLED'
                      AND (TIME(a.start_time) < p_start OR TIME(a.end_time) > p_end
                           OR DATE(a.start_time) <> p_date)) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-08: shift change would leave appointments outside the shift';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_shift_validate_insert
BEFORE INSERT ON shift
FOR EACH ROW
BEGIN
    CALL sp_validate_shift(0, NEW.doctor_id, NEW.room_id, NEW.shift_date,
                           NEW.start_time, NEW.end_time, NEW.rate_per_hour, NEW.status);
END$$

CREATE TRIGGER trg_shift_validate_update
BEFORE UPDATE ON shift
FOR EACH ROW
BEGIN
    CALL sp_validate_shift(OLD.shift_id, NEW.doctor_id, NEW.room_id, NEW.shift_date,
                           NEW.start_time, NEW.end_time, NEW.rate_per_hour, NEW.status);
END$$

-- ===== BR-20: granting rule =====
--   * only a SYSTEM_ADMIN may grant;
--   * the granter must already hold the permission;
--   * bootstrap: the first grant of a code may be a self-grant by a SYSTEM_ADMIN.
CREATE TRIGGER trg_staff_permission_grant_insert
BEFORE INSERT ON staff_permission
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20);
    SELECT role INTO v_role FROM admin WHERE admin_id = NEW.granted_by;
    IF v_role IS NULL OR v_role <> 'SYSTEM_ADMIN' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-20: only SYSTEM_ADMIN can grant permissions';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM staff_permission
                    WHERE admin_id = NEW.granted_by AND permission_code = NEW.permission_code) THEN
        IF NOT (NEW.granted_by = NEW.admin_id
                AND NOT EXISTS (SELECT 1 FROM staff_permission
                                 WHERE permission_code = NEW.permission_code)) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'BR-20: the granting admin does not hold this permission';
        END IF;
    END IF;
END$$

DELIMITER ;
