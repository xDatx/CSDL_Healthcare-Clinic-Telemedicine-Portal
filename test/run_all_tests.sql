USE healthcare;
DELIMITER $$

-- ===== Author: Nguyễn Hoàng Dũng =====
DROP PROCEDURE IF EXISTS run_test_tc01$$
CREATE PROCEDURE run_test_tc01()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    INSERT INTO shift (doctor_id, shift_date, start_time, end_time, status, room_id)
    VALUES (1, CURRENT_DATE, '09:00', '13:00', 'ACTIVE', 1);
    IF v_msg LIKE '%BR-05%' THEN SELECT 'TC-01 PASSED (BR-05)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-01 FAILED: BR-05 did not fire' AS result;
    ELSE SELECT CONCAT('TC-01 FAILED: ', v_msg) AS result; END IF;
END$$

DROP PROCEDURE IF EXISTS run_test_tc02$$
CREATE PROCEDURE run_test_tc02()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    INSERT INTO shift (doctor_id, shift_date, start_time, end_time, status, room_id)
    VALUES (2, CURRENT_DATE + INTERVAL 2 DAY, '08:00', '10:00', 'ACTIVE', 2);
    IF v_msg LIKE '%BR-24%' THEN SELECT 'TC-02 PASSED (BR-24)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-02 FAILED: BR-24 did not fire' AS result;
    ELSE SELECT CONCAT('TC-02 FAILED: ', v_msg) AS result; END IF;
END$$

-- ===== Author: Lý Thành Đạt =====
DROP PROCEDURE IF EXISTS run_test_tc03$$
CREATE PROCEDURE run_test_tc03()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    INSERT INTO appointment (patient_id, shift_id, start_time, end_time, appointment_type, status)
    VALUES (2, 1, TIMESTAMP(CURRENT_DATE,'08:15:00'), TIMESTAMP(CURRENT_DATE,'08:45:00'), 'IN_PERSON', 'CONFIRMED');
    IF v_msg LIKE '%BR-09%' THEN SELECT 'TC-03 PASSED (BR-09)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-03 FAILED: BR-09 did not fire' AS result;
    ELSE SELECT CONCAT('TC-03 FAILED: ', v_msg) AS result; END IF;
END$$

DROP PROCEDURE IF EXISTS run_test_tc04$$
CREATE PROCEDURE run_test_tc04()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    UPDATE appointment SET status = 'COMPLETED' WHERE appointment_id = 2;
    IF v_msg LIKE '%BR-11%' THEN SELECT 'TC-04 PASSED (BR-11)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-04 FAILED: BR-11 did not fire' AS result;
    ELSE SELECT CONCAT('TC-04 FAILED: ', v_msg) AS result; END IF;
END$$

DROP PROCEDURE IF EXISTS run_test_tc05$$
CREATE PROCEDURE run_test_tc05()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    UPDATE medical_record_audit_log SET actor_id = 999 WHERE audit_id = 1;
    IF v_msg LIKE '%NFR-04%' THEN SELECT 'TC-05 PASSED (NFR-04)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-05 FAILED: NFR-04 did not fire' AS result;
    ELSE SELECT CONCAT('TC-05 FAILED: ', v_msg) AS result; END IF;
END$$

-- ===== Author: Phạm Trần Quốc Việt =====
DROP PROCEDURE IF EXISTS run_test_tc06$$
CREATE PROCEDURE run_test_tc06()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    INSERT INTO prescription_item (prescription_id, medication_id, quantity, dosage, frequency, duration_days)
    VALUES (1, 1, 0, 'x', 'y', 1);
    IF v_msg LIKE '%ck_item_qty%' THEN SELECT 'TC-06 PASSED (BR-17)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-06 FAILED: BR-17 did not fire' AS result;
    ELSE SELECT CONCAT('TC-06 FAILED: ', v_msg) AS result; END IF;
END$$

DROP PROCEDURE IF EXISTS run_test_tc07$$
CREATE PROCEDURE run_test_tc07()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    DELETE FROM medication WHERE medication_id = 1;
    IF v_msg LIKE '%BR-19%' THEN SELECT 'TC-07 PASSED (BR-19)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-07 FAILED: BR-19 did not fire' AS result;
    ELSE SELECT CONCAT('TC-07 FAILED: ', v_msg) AS result; END IF;
END$$

DROP PROCEDURE IF EXISTS run_test_tc08$$
CREATE PROCEDURE run_test_tc08()
BEGIN
    DECLARE v_msg TEXT DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    INSERT INTO consultation_request (record_id, requesting_doctor_id, consulting_doctor_id, reason)
    VALUES (1, 3, 1, 'Test');
    IF v_msg LIKE '%BR-23%' THEN SELECT 'TC-08 PASSED (BR-23)' AS result;
    ELSEIF v_msg IS NULL THEN SELECT 'TC-08 FAILED: BR-23 did not fire' AS result;
    ELSE SELECT CONCAT('TC-08 FAILED: ', v_msg) AS result; END IF;
END$$

DELIMITER ;

CALL run_test_tc01();
CALL run_test_tc02();
CALL run_test_tc03();
CALL run_test_tc04();
CALL run_test_tc05();
CALL run_test_tc06();
CALL run_test_tc07();
CALL run_test_tc08();