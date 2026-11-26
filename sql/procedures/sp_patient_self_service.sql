-- Module: Patient self-service (FR-01) - register and maintain one's own profile
--
-- r_patient has no table privilege on `patient`. These three routines run with DEFINER rights
-- (default SQL SECURITY), so the least-privilege account app_patient only needs EXECUTE.
--
-- Trust model (same as sp_read_medical_record): the backend passes the id of the AUTHENTICATED
-- patient (session) as p_patient_id. sp_register_patient is also called before login, with the
-- app_patient connection, to create the profile of a new patient.
USE healthcare;

DROP PROCEDURE IF EXISTS sp_register_patient;
DROP PROCEDURE IF EXISTS sp_get_my_profile;
DROP PROCEDURE IF EXISTS sp_update_my_profile;
DELIMITER $$

-- FR-01: create a patient profile. BR-00 (phone OR email) is enforced by ck_patient_contact.
CREATE PROCEDURE sp_register_patient(
    IN p_full_name VARCHAR(100), IN p_dob DATE, IN p_phone VARCHAR(20),
    IN p_email VARCHAR(120),     IN p_address TEXT)
BEGIN
    INSERT INTO patient (full_name, dob, phone, email, address)
    VALUES (TRIM(p_full_name), p_dob, NULLIF(TRIM(p_phone), ''), NULLIF(TRIM(p_email), ''),
            NULLIF(TRIM(p_address), ''));
    SELECT LAST_INSERT_ID() AS patient_id;
END$$

-- FR-01: a patient reads only his / her own profile
CREATE PROCEDURE sp_get_my_profile(IN p_patient_id INT)
BEGIN
    SELECT patient_id, full_name, dob, phone, email, address, created_at
      FROM patient
     WHERE patient_id = p_patient_id;
END$$

-- FR-01: a patient updates only his / her own profile
CREATE PROCEDURE sp_update_my_profile(
    IN p_patient_id INT,
    IN p_full_name VARCHAR(100), IN p_dob DATE, IN p_phone VARCHAR(20),
    IN p_email VARCHAR(120),     IN p_address TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patient WHERE patient_id = p_patient_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-01: patient not found';
    END IF;

    UPDATE patient
       SET full_name = TRIM(p_full_name),
           dob       = p_dob,
           phone     = NULLIF(TRIM(p_phone), ''),
           email     = NULLIF(TRIM(p_email), ''),
           address   = NULLIF(TRIM(p_address), '')
     WHERE patient_id = p_patient_id;
END$$

DELIMITER ;
