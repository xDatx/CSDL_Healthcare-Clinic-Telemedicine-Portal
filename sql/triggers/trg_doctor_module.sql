-- Author: Lý Thành Đạt
-- Module: Doctor + Shift triggers
-- Enforces: BR-01, BR-03, BR-05, BR-20, BR-24, BR-26
-- MySQL 8.0.16+

USE healthcare;
DELIMITER $$

-- ===== BR-05: no overlapping ACTIVE shifts per doctor =====
CREATE TRIGGER trg_shift_no_overlap_insert
BEFORE INSERT ON shift
FOR EACH ROW
BEGIN
    IF NEW.status = 'ACTIVE' AND EXISTS (
        SELECT 1 FROM shift s
        WHERE s.doctor_id = NEW.doctor_id
          AND s.shift_date = NEW.shift_date
          AND s.status = 'ACTIVE'
          AND NEW.start_time < s.end_time
          AND s.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-05: overlapping shift for doctor';
    END IF;
END$$

CREATE TRIGGER trg_shift_no_overlap_update
BEFORE UPDATE ON shift
FOR EACH ROW
BEGIN
    IF NEW.status = 'ACTIVE' AND EXISTS (
        SELECT 1 FROM shift s
        WHERE s.doctor_id = NEW.doctor_id
          AND s.shift_date = NEW.shift_date
          AND s.status = 'ACTIVE'
          AND s.shift_id <> OLD.shift_id
          AND NEW.start_time < s.end_time
          AND s.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-05: overlapping shift for doctor';
    END IF;
END$$

-- ===== BR-03 + BR-26: room rule =====
CREATE TRIGGER trg_shift_room_insert
BEFORE INSERT ON shift
FOR EACH ROW
BEGIN
    DECLARE v_spec VARCHAR(10);
    SELECT spec_type INTO v_spec FROM doctor WHERE doctor_id = NEW.doctor_id;
    IF v_spec = 'GP' AND NEW.room_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP shift requires room_id';
    END IF;
    IF v_spec = 'SPECIALIST' AND NEW.room_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-26: Specialist shift must not have room_id';
    END IF;
    IF v_spec = 'GP' AND NEW.status = 'ACTIVE' AND EXISTS (
        SELECT 1 FROM shift s
        JOIN doctor d ON d.doctor_id = s.doctor_id
        WHERE s.room_id = NEW.room_id
          AND s.shift_date = NEW.shift_date
          AND s.status = 'ACTIVE'
          AND d.spec_type = 'GP'
          AND NEW.start_time < s.end_time
          AND s.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP room double-booked';
    END IF;
END$$

CREATE TRIGGER trg_shift_room_update
BEFORE UPDATE ON shift
FOR EACH ROW
BEGIN
    DECLARE v_spec VARCHAR(10);
    SELECT spec_type INTO v_spec FROM doctor WHERE doctor_id = NEW.doctor_id;
    IF v_spec = 'GP' AND NEW.room_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP shift requires room_id';
    END IF;
    IF v_spec = 'SPECIALIST' AND NEW.room_id IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-26: Specialist shift must not have room_id';
    END IF;
    IF v_spec = 'GP' AND NEW.status = 'ACTIVE' AND EXISTS (
        SELECT 1 FROM shift s
        JOIN doctor d ON d.doctor_id = s.doctor_id
        WHERE s.room_id = NEW.room_id
          AND s.shift_date = NEW.shift_date
          AND s.status = 'ACTIVE'
          AND d.spec_type = 'GP'
          AND s.shift_id <> OLD.shift_id
          AND NEW.start_time < s.end_time
          AND s.start_time < NEW.end_time
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-03: GP room double-booked';
    END IF;
END$$

-- ===== BR-24: rate rule =====
CREATE TRIGGER trg_shift_rate_insert
BEFORE INSERT ON shift
FOR EACH ROW
BEGIN
    DECLARE v_emp VARCHAR(10);
    SELECT employment_type INTO v_emp FROM doctor WHERE doctor_id = NEW.doctor_id;
    IF v_emp = 'PART_TIME' AND NEW.rate_per_hour IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: PART_TIME shift requires rate_per_hour';
    END IF;
    IF v_emp = 'FULL_TIME' AND NEW.rate_per_hour IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: FULL_TIME shift must not carry rate_per_hour';
    END IF;
END$$

CREATE TRIGGER trg_shift_rate_update
BEFORE UPDATE ON shift
FOR EACH ROW
BEGIN
    DECLARE v_emp VARCHAR(10);
    SELECT employment_type INTO v_emp FROM doctor WHERE doctor_id = NEW.doctor_id;
    IF v_emp = 'PART_TIME' AND NEW.rate_per_hour IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: PART_TIME shift requires rate_per_hour';
    END IF;
    IF v_emp = 'FULL_TIME' AND NEW.rate_per_hour IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-24: FULL_TIME shift must not carry rate_per_hour';
    END IF;
END$$

-- ===== BR-01: activation requires subtype =====
CREATE TRIGGER trg_doctor_activation_insert
BEFORE INSERT ON doctor
FOR EACH ROW
BEGIN
    IF NEW.is_active = TRUE THEN
        IF NEW.spec_type = 'GP'
           AND NOT EXISTS (SELECT 1 FROM gp WHERE doctor_id = NEW.doctor_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: activate GP requires GP subtype row';
        END IF;
        IF NEW.spec_type = 'SPECIALIST'
           AND NOT EXISTS (SELECT 1 FROM specialist WHERE doctor_id = NEW.doctor_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: activate Specialist requires subtype row';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_doctor_activation_update
BEFORE UPDATE ON doctor
FOR EACH ROW
BEGIN
    IF NEW.is_active = TRUE AND OLD.is_active = FALSE THEN
        IF NEW.spec_type = 'GP'
           AND NOT EXISTS (SELECT 1 FROM gp WHERE doctor_id = NEW.doctor_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: activate GP requires GP subtype row';
        END IF;
        IF NEW.spec_type = 'SPECIALIST'
           AND NOT EXISTS (SELECT 1 FROM specialist WHERE doctor_id = NEW.doctor_id) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-01: activate Specialist requires subtype row';
        END IF;
    END IF;
END$$

-- ===== BR-20: only SYSTEM_ADMIN grants permissions =====
CREATE TRIGGER trg_staff_permission_grant_insert
BEFORE INSERT ON staff_permission
FOR EACH ROW
BEGIN
    DECLARE v_role VARCHAR(20);
    SELECT role INTO v_role FROM admin WHERE admin_id = NEW.granted_by;
    IF v_role IS NULL OR v_role <> 'SYSTEM_ADMIN' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-20: only SYSTEM_ADMIN can grant permissions';
    END IF;
END$$

DELIMITER ;
