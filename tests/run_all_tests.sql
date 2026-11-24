-- Author: Nguyễn Hoàng Dũng (framework, BR-01..12) / Lý Thành Đạt (BR-19..26) / Phạm Trần Quốc Việt (NFR-02, CHECK)
-- Module: Automated test suite (run AFTER run_all.sql on a freshly built database)
--
--   mysql -u root -p --default-character-set=utf8mb4 healthcare < tests/run_all_tests.sql
--
-- Every test is one row in the temporary table tc_results; the last two result sets are the
-- full list and the PASS / FAIL summary. The whole run happens inside a transaction that is
-- rolled back at the end, so the database is left exactly as it was.
-- A negative test PASSES when the statement fails with a message containing the expected text.
-- Note: the few tests that execute sp_read_medical_record successfully print its result sets;
-- ignore them, the verdicts are in the summary.

USE healthcare;

DROP TEMPORARY TABLE IF EXISTS tc_results;
CREATE TEMPORARY TABLE tc_results (
    seq         INT AUTO_INCREMENT PRIMARY KEY,
    tc          VARCHAR(8),
    rule_id     VARCHAR(12),
    description VARCHAR(110),
    expected    VARCHAR(70),
    outcome     VARCHAR(4),
    detail      VARCHAR(300)
) ENGINE = MEMORY;

DROP PROCEDURE IF EXISTS tc_expect_error;
DROP PROCEDURE IF EXISTS tc_expect_ok;
DROP PROCEDURE IF EXISTS tc_assert;

DELIMITER $$

-- the statement must FAIL and the error text must contain p_expect
CREATE PROCEDURE tc_expect_error(IN p_tc VARCHAR(8), IN p_rule VARCHAR(12), IN p_desc VARCHAR(110),
                                 IN p_expect VARCHAR(70), IN p_sql TEXT)
BEGIN
    DECLARE v_msg VARCHAR(300) DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    SET @tc_sql = p_sql;
    PREPARE tc_stmt FROM @tc_sql;
    EXECUTE tc_stmt;
    DEALLOCATE PREPARE tc_stmt;
    INSERT INTO tc_results (tc, rule_id, description, expected, outcome, detail)
    VALUES (p_tc, p_rule, p_desc, p_expect,
            IF(v_msg IS NOT NULL AND v_msg LIKE CONCAT('%', p_expect, '%'), 'PASS', 'FAIL'),
            IF(v_msg IS NULL, 'statement succeeded but should have failed', v_msg));
END$$

-- the statement must SUCCEED
CREATE PROCEDURE tc_expect_ok(IN p_tc VARCHAR(8), IN p_rule VARCHAR(12), IN p_desc VARCHAR(110), IN p_sql TEXT)
BEGIN
    DECLARE v_msg VARCHAR(300) DEFAULT NULL;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT; END;
    SET @tc_sql = p_sql;
    PREPARE tc_stmt FROM @tc_sql;
    EXECUTE tc_stmt;
    DEALLOCATE PREPARE tc_stmt;
    INSERT INTO tc_results (tc, rule_id, description, expected, outcome, detail)
    VALUES (p_tc, p_rule, p_desc, 'no error', IF(v_msg IS NULL, 'PASS', 'FAIL'), v_msg);
END$$

-- a boolean condition must hold
CREATE PROCEDURE tc_assert(IN p_tc VARCHAR(8), IN p_rule VARCHAR(12), IN p_desc VARCHAR(110), IN p_cond BOOLEAN)
BEGIN
    INSERT INTO tc_results (tc, rule_id, description, expected, outcome, detail)
    VALUES (p_tc, p_rule, p_desc, 'condition true', IF(p_cond, 'PASS', 'FAIL'), NULL);
END$$

DELIMITER ;

SET @app_actor_type = NULL;
SET @app_actor_id   = NULL;
START TRANSACTION;

-- ======================= Doctor / shift (BR-01, 03, 05, 24, 26) =======================
CALL tc_expect_error('TC-01','BR-01','A new doctor cannot be created active','BR-01',
  "INSERT INTO doctor (full_name,email,license_no,employment_type,spec_type,is_active,created_by) VALUES ('T','t1@x.vn','L-T1','FULL_TIME','GP',TRUE,1)");
CALL tc_expect_error('TC-02','BR-01','Doctor without GP/SPECIALIST row cannot be activated','BR-01',
  "UPDATE doctor SET is_active = TRUE WHERE doctor_id = 10");
CALL tc_expect_error('TC-03','BR-03','GP shift without a room is rejected','BR-03: GP shift requires',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (1,'2027-01-05','08:00','12:00',NULL,NULL)");
CALL tc_expect_error('TC-04','BR-26','Specialist shift with a room is rejected','BR-26',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (4,'2027-01-05','08:00','12:00',1,NULL)");
CALL tc_expect_error('TC-05','BR-24','PART_TIME shift without rate is rejected','BR-24: PART_TIME',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (2,'2027-01-05','08:00','12:00',4,NULL)");
CALL tc_expect_error('TC-06','BR-24','FULL_TIME shift with a rate is rejected','BR-24: FULL_TIME',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (1,'2027-01-05','08:00','12:00',4,100000)");
CALL tc_expect_error('TC-07','BR-05','Overlapping shifts of one doctor are rejected','BR-05',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (1,'2026-11-16','09:00','11:00',4,NULL)");
CALL tc_expect_error('TC-08','BR-03','Two GPs cannot use the same room at the same time','BR-03: GP room double-booked',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (3,'2026-11-16','08:00','12:00',1,200000)");
CALL tc_expect_error('TC-09','CHECK','Shift must end after it starts','ck_shift_time',
  "INSERT INTO shift (doctor_id,shift_date,start_time,end_time,room_id,rate_per_hour) VALUES (4,'2027-01-06','12:00','08:00',NULL,NULL)");

-- ======================= Appointment (BR-08, 09, 11) =======================
CALL tc_expect_error('TC-10','BR-09','Overlapping appointment in a shift is rejected','BR-09',
  "INSERT INTO appointment (patient_id,shift_id,start_time,end_time,appointment_type,status) VALUES (2,19,'2026-11-25 08:15:00','2026-11-25 08:45:00','IN_PERSON','PENDING')");
CALL tc_expect_error('TC-11','BR-08','Appointment outside the shift hours is rejected','BR-08: appointment outside',
  "INSERT INTO appointment (patient_id,shift_id,start_time,end_time,appointment_type,status) VALUES (2,19,'2026-11-25 13:00:00','2026-11-25 13:30:00','IN_PERSON','PENDING')");
CALL tc_expect_error('TC-12','BR-08','Appointment on another day than the shift is rejected','BR-08: appointment must be on shift date',
  "INSERT INTO appointment (patient_id,shift_id,start_time,end_time,appointment_type,status) VALUES (2,19,'2026-11-26 09:00:00','2026-11-26 09:30:00','IN_PERSON','PENDING')");
CALL tc_expect_error('TC-13','BR-08','Appointment on a CANCELLED shift is rejected','BR-08: shift is not ACTIVE',
  "INSERT INTO appointment (patient_id,shift_id,start_time,end_time,appointment_type,status) VALUES (2,24,'2026-11-27 14:00:00','2026-11-27 14:30:00','IN_PERSON','PENDING')");
CALL tc_expect_error('TC-14','BR-11','A new appointment must start as PENDING','BR-11: a new appointment',
  "INSERT INTO appointment (patient_id,shift_id,start_time,end_time,appointment_type,status) VALUES (2,19,'2026-11-25 09:00:00','2026-11-25 09:30:00','IN_PERSON','COMPLETED')");
CALL tc_expect_error('TC-15','BR-11','PENDING cannot jump to COMPLETED','BR-11: invalid status transition',
  "UPDATE appointment SET status = 'COMPLETED' WHERE appointment_id = 41");
CALL tc_expect_error('TC-16','BR-11','A COMPLETED appointment cannot be re-opened','BR-11: invalid status transition',
  "UPDATE appointment SET status = 'CONFIRMED' WHERE appointment_id = 1");
CALL tc_expect_ok   ('TC-17','BR-11','PENDING -> CONFIRMED is allowed',
  "UPDATE appointment SET status = 'CONFIRMED' WHERE appointment_id = 41");
CALL tc_expect_ok   ('TC-18','BR-09','A free slot can be booked through sp_book_appointment',
  "CALL sp_book_appointment(2,19,'2026-11-25 09:00:00','2026-11-25 09:30:00','TELEMEDICINE')");

-- ======================= Medical record + audit (BR-12, NFR-04) =======================
CALL tc_expect_error('TC-19','BR-12','Record for a non-COMPLETED appointment is rejected','BR-12: medical record requires',
  "INSERT INTO medical_record (appointment_id,diagnosis) VALUES (43,'x')");
CALL tc_expect_error('TC-20','BR-12','Second record for the same appointment is rejected','Duplicate entry',
  "INSERT INTO medical_record (appointment_id,diagnosis) VALUES (1,'x')");
CALL tc_expect_error('TC-21','CHECK','Diastolic pressure must be below systolic','ck_mr_bp_order',
  "INSERT INTO medical_record (appointment_id,diagnosis,systolic_bp,diastolic_bp) VALUES (3,'x',80,90)");
CALL tc_expect_error('TC-22','NFR-04','Medical records can never be deleted','NFR-04',
  "DELETE FROM medical_record WHERE record_id = 1");
CALL tc_expect_error('TC-23','NFR-04','Audit log rows cannot be updated','NFR-04: audit log is append-only',
  "UPDATE medical_record_audit_log SET action = 'SELECT' WHERE audit_id = 1");
CALL tc_expect_error('TC-24','NFR-04','Audit log rows cannot be deleted','NFR-04: audit log is append-only',
  "DELETE FROM medical_record_audit_log WHERE audit_id = 1");
CALL tc_expect_error('TC-25','NFR-04','An audit row must have exactly one actor','ck_mr_audit_one_actor',
  "INSERT INTO medical_record_audit_log (record_id,patient_id,doctor_id,action) VALUES (1,1,1,'SELECT')");

SELECT COUNT(*) INTO @n_before FROM medical_record_audit_log;
SET @app_actor_type = 'DOCTOR'; SET @app_actor_id = 1;
CALL tc_expect_ok('TC-26','NFR-04','Updating a record is allowed and audited',
  "UPDATE medical_record SET notes = 'test note' WHERE record_id = 1");
SET @app_actor_type = NULL; SET @app_actor_id = NULL;
SELECT COUNT(*) INTO @n_after FROM medical_record_audit_log;
CALL tc_assert('TC-27','NFR-04','That update wrote exactly one UPDATE audit row', @n_after = @n_before + 1);

-- ======================= Prescription (BR-14, 16, 17) =======================
CALL tc_expect_error('TC-28','BR-17','Prescription quantity must be positive','ck_item_qty',
  "INSERT INTO prescription_item (prescription_id,medication_id,quantity,dosage,frequency,duration_days) VALUES (1,5,0,'x','y',1)");
CALL tc_expect_error('TC-29','BR-16','The same drug cannot appear twice on one prescription','Duplicate entry',
  "INSERT INTO prescription_item (prescription_id,medication_id,quantity,dosage,frequency,duration_days) SELECT prescription_id,medication_id,1,'x','y',1 FROM prescription_item LIMIT 1");
CALL tc_expect_error('TC-30','BR-14','Second prescription for one record is rejected','Duplicate entry',
  "INSERT INTO prescription (record_id) VALUES (1)");

-- ======================= Medication catalog (BR-19, BR-25) =======================
CALL tc_expect_error('TC-31','BR-19','Medications are never deleted','BR-19',
  "DELETE FROM medication WHERE medication_id = 1");
CALL tc_expect_error('TC-32','BR-25','Catalog change without an admin actor is rejected','BR-25: set @app_actor_id',
  "UPDATE medication SET description = 'x' WHERE medication_id = 1");
SELECT COUNT(*) INTO @m_before FROM medication_audit_log;
SET @app_actor_id = 1;
CALL tc_expect_ok('TC-33','BR-25','Catalog change by an admin is accepted',
  "UPDATE medication SET is_active = FALSE WHERE medication_id = 20");
SET @app_actor_id = NULL;
SELECT COUNT(*) INTO @m_after FROM medication_audit_log;
CALL tc_assert('TC-34','BR-25','That change wrote one DEACTIVATE audit row',
  @m_after = @m_before + 1 AND (SELECT action FROM medication_audit_log ORDER BY audit_id DESC LIMIT 1) = 'DEACTIVATE');

-- ======================= Permissions (BR-20) =======================
CALL tc_expect_error('TC-35','BR-20','A receptionist cannot grant permissions','BR-20: only SYSTEM_ADMIN',
  "INSERT INTO staff_permission (admin_id,permission_code,granted_by) VALUES (3,'CREATE_DOCTOR',3)");
INSERT INTO admin (full_name,email,role) VALUES ('Test Admin','test.admin@clinic.local','SYSTEM_ADMIN');
SET @new_admin = LAST_INSERT_ID();
CALL tc_expect_error('TC-36','BR-20','A SYSTEM_ADMIN cannot grant a permission it does not hold','BR-20: the granting admin',
  CONCAT("INSERT INTO staff_permission (admin_id,permission_code,granted_by) VALUES (3,'MANAGE_MEDICATION',", @new_admin, ")"));
CALL tc_expect_ok('TC-37','BR-20','A SYSTEM_ADMIN holding the permission can grant it',
  "INSERT INTO staff_permission (admin_id,permission_code,granted_by) VALUES (3,'MANAGE_MEDICATION',1)");

-- ======================= Consultation (BR-22, BR-23) =======================
CALL tc_expect_error('TC-38','BR-23','Only the treating doctor can request a consultation','BR-23: requesting doctor is not treating',
  "INSERT INTO consultation_request (record_id,requesting_doctor_id,consulting_doctor_id,reason) VALUES (17,3,1,'t')");
CALL tc_expect_error('TC-39','BR-22','The consulting doctor must be active','BR-22: consulting doctor must be an active',
  "INSERT INTO consultation_request (record_id,requesting_doctor_id,consulting_doctor_id,reason) VALUES (17,4,10,'t')");
CALL tc_expect_error('TC-40','CHECK','A doctor cannot consult himself','ck_cr_diff',
  "INSERT INTO consultation_request (record_id,requesting_doctor_id,consulting_doctor_id,reason) VALUES (17,4,4,'t')");
CALL tc_expect_error('TC-41','BR-22','A COMPLETED request cannot go back to APPROVED','BR-22: invalid consultation status',
  "UPDATE consultation_request SET status = 'APPROVED' WHERE request_id = 1");
CALL tc_expect_error('TC-42','BR-23','Doctors of a request cannot be swapped afterwards','BR-23: record, doctors',
  "UPDATE consultation_request SET consulting_doctor_id = 5 WHERE request_id = 3");
CALL tc_expect_ok('TC-43','BR-22','PENDING -> APPROVED stamps responded_at',
  "UPDATE consultation_request SET status = 'APPROVED', expires_at = NOW() + INTERVAL 1 DAY WHERE request_id = 3");
CALL tc_assert('TC-44','BR-22','The approved doctor can now read record 30',
  fn_can_read_record(30, 'DOCTOR', 4));

-- ======================= Access control (NFR-02, BR-20/21/22) =======================
CALL tc_assert('TC-45','NFR-02','Patient reads own record',                 fn_can_read_record(1,  'PATIENT', 1));
CALL tc_assert('TC-46','NFR-02','Patient cannot read another patient',      NOT fn_can_read_record(1,  'PATIENT', 2));
CALL tc_assert('TC-47','BR-21','Treating doctor reads the record',          fn_can_read_record(1,  'DOCTOR',  1));
CALL tc_assert('TC-48','BR-21','Unrelated doctor cannot read the record',   NOT fn_can_read_record(1,  'DOCTOR',  5));
CALL tc_assert('TC-49','BR-22','Consulting doctor with APPROVED request can read', fn_can_read_record(19, 'DOCTOR', 1));
CALL tc_assert('TC-50','BR-22','Expired APPROVED request gives no access',  NOT fn_can_read_record(32, 'DOCTOR', 4));
CALL tc_assert('TC-51','BR-22','A DECLINED request gives no access',        NOT fn_can_read_record(22, 'DOCTOR', 2));
CALL tc_assert('TC-52','BR-20','Admin with VIEW_ALL_RECORDS can read',      fn_can_read_record(1,  'ADMIN',   1));
CALL tc_assert('TC-53','BR-20','Receptionist without the permission cannot read', NOT fn_can_read_record(1, 'ADMIN', 3));
CALL tc_assert('TC-54','NFR-02','Unknown actor type is denied',             NOT fn_can_read_record(1,  'GUEST',   1));
CALL tc_expect_error('TC-55','NFR-02','sp_read_medical_record refuses an unauthorised actor','NFR-02: access denied',
  "CALL sp_read_medical_record(1,'PATIENT',2)");
CALL tc_expect_error('TC-56','NFR-02','sp_read_medical_record rejects an unknown record','medical record not found',
  "CALL sp_read_medical_record(999999,'DOCTOR',1)");

SELECT COUNT(*) INTO @r_before FROM medical_record_audit_log;
CALL tc_expect_error('TC-57','NFR-04','A refused read leaves no audit row','NFR-02: access denied',
  "CALL sp_read_medical_record(1,'PATIENT',2)");
SELECT COUNT(*) INTO @r_mid FROM medical_record_audit_log;
CALL tc_expect_ok('TC-58','NFR-04','An allowed read through the procedure succeeds',
  "CALL sp_read_medical_record(1,'PATIENT',1)");
SELECT COUNT(*) INTO @r_after FROM medical_record_audit_log;
CALL tc_assert('TC-59','NFR-04','Refused read wrote 0 audit rows, allowed read wrote 1',
  @r_mid = @r_before AND @r_after = @r_mid + 1);

-- ======================= Patient data =======================
CALL tc_expect_error('TC-60','CHECK','A patient needs a phone or an email','ck_patient_contact',
  "INSERT INTO patient (full_name,dob) VALUES ('No Contact','1990-01-01')");

ROLLBACK;

SELECT tc, rule_id, description, outcome, IF(outcome = 'PASS', '', detail) AS detail FROM tc_results ORDER BY seq;
SELECT COUNT(*) AS total_tests, SUM(outcome = 'PASS') AS passed, SUM(outcome = 'FAIL') AS failed FROM tc_results;
