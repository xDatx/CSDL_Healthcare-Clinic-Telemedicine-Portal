-- Author: Lý Thành Đạt
-- Module: Bulk seed for performance testing (NFR-03)
-- Chạy SAU 05_seed_data.sql, TRƯỚC tests/performance_explain.sql
-- Idempotent: chạy lại nhiều lần không lỗi

USE healthcare;

DROP PROCEDURE IF EXISTS seed_bulk_patients;
DROP PROCEDURE IF EXISTS seed_bulk_appointments_for_patient;
DROP PROCEDURE IF EXISTS seed_bulk_medications;
DROP PROCEDURE IF EXISTS seed_bulk_prescription_items;

DELIMITER $$

CREATE PROCEDURE seed_bulk_patients(IN p_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_existing INT;

    SELECT COUNT(*) INTO v_existing FROM patient WHERE full_name LIKE 'Bulk Patient %';
    SET i = v_existing;  -- bỏ qua nếu đã seed 1 phần

    WHILE i < p_count DO
        INSERT INTO patient (full_name, dob, phone)
        VALUES (CONCAT('Bulk Patient ', i),
                DATE_SUB('1990-01-01', INTERVAL (i % 3650) DAY),
                CONCAT('090', LPAD(i, 7, '0')));
        SET i = i + 1;
    END WHILE;
END$$

CREATE PROCEDURE seed_bulk_appointments_for_patient(IN p_patient_id INT, IN p_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_shift_id INT;
    DECLARE v_date DATE;

    WHILE i < p_count DO
        SET v_date = DATE_ADD('2030-01-01', INTERVAL i DAY);  -- base date xa CURRENT_DATE

        -- Tạo shift nếu chưa có
        IF NOT EXISTS (
            SELECT 1 FROM shift
            WHERE doctor_id = 1
              AND shift_date = v_date
              AND status = 'ACTIVE'
        ) THEN
            INSERT INTO shift (doctor_id, shift_date, start_time, end_time, status, room_id)
            VALUES (1, v_date, '08:00', '12:00', 'ACTIVE', 1);
            SET v_shift_id = LAST_INSERT_ID();
        ELSE
            SELECT shift_id INTO v_shift_id FROM shift
            WHERE doctor_id = 1 AND shift_date = v_date AND status = 'ACTIVE'
            LIMIT 1;
        END IF;

        -- Tạo appointment nếu chưa có
        IF NOT EXISTS (
            SELECT 1 FROM appointment
            WHERE shift_id = v_shift_id AND patient_id = p_patient_id
        ) THEN
            INSERT INTO appointment (patient_id, shift_id, start_time, end_time, appointment_type, status)
            VALUES (p_patient_id, v_shift_id,
                    TIMESTAMP(v_date, '08:00:00'),
                    TIMESTAMP(v_date, '08:30:00'),
                    'IN_PERSON', 'COMPLETED');
        END IF;

        SET i = i + 1;
    END WHILE;
END$$

CREATE PROCEDURE seed_bulk_medications(IN p_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_existing INT;

    SELECT COUNT(*) INTO v_existing FROM medication WHERE name LIKE 'Medication %';
    SET i = v_existing;

    WHILE i < p_count DO
        INSERT INTO medication (name, unit, description, is_active)
        VALUES (CONCAT('Medication ', LPAD(i, 5, '0')),
                'tablet',
                CONCAT('Bulk seeded #', i),
                IF(i % 10 = 0, FALSE, TRUE));
        SET i = i + 1;
    END WHILE;
END$$

CREATE PROCEDURE seed_bulk_prescription_items(IN p_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_presc_id INT;
    DECLARE v_med_id   INT;
    DECLARE v_existing INT;

    SELECT prescription_id INTO v_presc_id FROM prescription LIMIT 1;

    SELECT COUNT(*) INTO v_existing FROM prescription_item WHERE prescription_id = v_presc_id;
    SET i = v_existing;

    WHILE i < p_count DO
        SET v_med_id = 1 + (i % 2);
        INSERT INTO prescription_item
            (prescription_id, medication_id, quantity, dosage, frequency, duration_days)
        VALUES (v_presc_id, v_med_id, 5 + (i % 10), '1 tablet', '3 times/day', 3 + (i % 7));
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

-- ============================================================
-- EXECUTION
-- ============================================================
SET @start = NOW(6);
CALL seed_bulk_patients(10000);
SELECT CONCAT('bulk_patients: ', TIMESTAMPDIFF(MICROSECOND, @start, NOW(6)) / 1000, ' ms') AS timing;

SET @start = NOW(6);
CALL seed_bulk_appointments_for_patient(1, 300);
SELECT CONCAT('bulk_appointments: ', TIMESTAMPDIFF(MICROSECOND, @start, NOW(6)) / 1000, ' ms') AS timing;

SET @start = NOW(6);
CALL seed_bulk_medications(500);
SELECT CONCAT('bulk_medications: ', TIMESTAMPDIFF(MICROSECOND, @start, NOW(6)) / 1000, ' ms') AS timing;

SET @start = NOW(6);
CALL seed_bulk_prescription_items(5000);
SELECT CONCAT('bulk_prescription_items: ', TIMESTAMPDIFF(MICROSECOND, @start, NOW(6)) / 1000, ' ms') AS timing;

-- ============================================================
-- VERIFICATION
-- ============================================================
SELECT 'patients'          AS entity, COUNT(*) AS cnt FROM patient
UNION ALL SELECT 'appointments',        COUNT(*) FROM appointment
UNION ALL SELECT 'shifts',              COUNT(*) FROM shift
UNION ALL SELECT 'medications',         COUNT(*) FROM medication
UNION ALL SELECT 'prescription_items',  COUNT(*) FROM prescription_item
UNION ALL SELECT 'appts_for_patient_1', COUNT(*) FROM appointment WHERE patient_id = 1;
