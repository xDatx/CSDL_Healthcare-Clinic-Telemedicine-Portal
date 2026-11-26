-- Author: Lý Thành Đạt
-- Module: Authorised, audited access to clinical data (NFR-02, NFR-04, BR-20, BR-21, BR-22)
--
-- Application roles have NO direct SELECT on medical_record / prescription. Every read goes
-- through sp_read_medical_record (one record) or sp_patient_history (a patient's own history).
-- The routines run with DEFINER rights (default SQL SECURITY), so the roles need no privilege
-- on the audit tables either.
--
-- Trust model: MySQL cannot know the end user behind a pooled application connection, so the
-- backend must pass the id of the AUTHENTICATED user as p_actor_id / p_patient_id.
USE healthcare;

DROP FUNCTION  IF EXISTS fn_can_read_record;
DROP PROCEDURE IF EXISTS sp_read_medical_record;
DROP PROCEDURE IF EXISTS sp_patient_history;
DROP PROCEDURE IF EXISTS sp_book_appointment;
DROP PROCEDURE IF EXISTS sp_cancel_appointment;
DROP PROCEDURE IF EXISTS sp_patient_appointments;
DROP PROCEDURE IF EXISTS sp_list_my_consultations;
DROP PROCEDURE IF EXISTS sp_get_consultation;
DELIMITER $$

-- Access rule in ONE place.
--   PATIENT : only own records
--   DOCTOR  : treating doctor (owner of the appointment's shift, BR-21) or a consulting doctor
--             whose request is APPROVED and not expired (BR-22)
--   ADMIN   : only with VIEW_ALL_RECORDS (BR-20)
CREATE FUNCTION fn_can_read_record(p_record_id INT, p_actor_type VARCHAR(10), p_actor_id INT)
RETURNS BOOLEAN
READS SQL DATA
BEGIN
    DECLARE v_patient  INT;
    DECLARE v_treating INT;

    SELECT a.patient_id, s.doctor_id INTO v_patient, v_treating
      FROM medical_record mr
      JOIN appointment a ON a.appointment_id = mr.appointment_id
      JOIN shift s       ON s.shift_id = a.shift_id
     WHERE mr.record_id = p_record_id;

    IF v_patient IS NULL OR p_actor_id IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_actor_type = 'PATIENT' THEN
        RETURN v_patient = p_actor_id;
    ELSEIF p_actor_type = 'DOCTOR' THEN
        RETURN v_treating = p_actor_id
            OR EXISTS (SELECT 1 FROM consultation_request cr
                        WHERE cr.record_id = p_record_id
                          AND cr.consulting_doctor_id = p_actor_id
                          AND cr.status = 'APPROVED'
                          AND (cr.expires_at IS NULL OR cr.expires_at > NOW()));
    ELSEIF p_actor_type = 'ADMIN' THEN
        RETURN EXISTS (SELECT 1 FROM staff_permission
                        WHERE admin_id = p_actor_id AND permission_code = 'VIEW_ALL_RECORDS');
    END IF;
    RETURN FALSE;
END$$

CREATE PROCEDURE sp_read_medical_record(
    IN p_record_id  INT,
    IN p_actor_type VARCHAR(10),
    IN p_actor_id   INT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM medical_record WHERE record_id = p_record_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-02: medical record not found';
    END IF;
    IF NOT fn_can_read_record(p_record_id, p_actor_type, p_actor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-02: access denied to this medical record';
    END IF;

    -- 1. audit the read (only after authorisation succeeded)
    CALL sp_insert_record_audit(p_record_id, p_actor_type, p_actor_id, 'SELECT',
                                JSON_OBJECT('via', 'sp_read_medical_record'));

    -- 2. the record
    SELECT mr.record_id, mr.appointment_id, mr.diagnosis, mr.symptoms,
           mr.systolic_bp, mr.diastolic_bp, mr.heart_rate,
           mr.temperature_c, mr.oxygen_saturation, mr.notes, mr.created_at
      FROM medical_record mr
     WHERE mr.record_id = p_record_id;

    -- 3. its prescription lines
    SELECT pr.prescription_id, pr.issued_at, m.name AS medication,
           pi.quantity, pi.dosage, pi.frequency, pi.duration_days
      FROM prescription pr
      JOIN prescription_item pi ON pi.prescription_id = pr.prescription_id
      JOIN medication m         ON m.medication_id = pi.medication_id
     WHERE pr.record_id = p_record_id
     ORDER BY m.name;
END$$

-- FR-04: a patient's own history. Each record returned is audited as a read by that patient.
CREATE PROCEDURE sp_patient_history(IN p_patient_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patient WHERE patient_id = p_patient_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-04: unknown patient';
    END IF;

    INSERT INTO medical_record_audit_log (record_id, patient_id, action, details)
    SELECT mr.record_id, p_patient_id, 'SELECT', JSON_OBJECT('via', 'sp_patient_history')
      FROM medical_record mr
      JOIN appointment a ON a.appointment_id = mr.appointment_id
     WHERE a.patient_id = p_patient_id;

    SELECT a.appointment_id, a.start_time, a.appointment_type, a.status,
           d.full_name AS doctor_name, d.spec_type,
           mr.record_id, mr.diagnosis, mr.symptoms
      FROM appointment a
      JOIN shift s  ON s.shift_id = a.shift_id
      JOIN doctor d ON d.doctor_id = s.doctor_id
      LEFT JOIN medical_record mr ON mr.appointment_id = a.appointment_id
     WHERE a.patient_id = p_patient_id
     ORDER BY a.start_time DESC;
END$$

-- FR-03: booking. The triggers enforce BR-08 / BR-09 / BR-11; the booking starts as PENDING.
CREATE PROCEDURE sp_book_appointment(
    IN p_patient_id INT, IN p_shift_id INT,
    IN p_start DATETIME, IN p_end DATETIME, IN p_type VARCHAR(15))
BEGIN
    INSERT INTO appointment (patient_id, shift_id, start_time, end_time, appointment_type)
    VALUES (p_patient_id, p_shift_id, p_start, p_end, p_type);
    SELECT LAST_INSERT_ID() AS appointment_id;
END$$

-- FR-03 / BR-11 / NFR-02: patient self-cancellation without granting direct UPDATE on appointment.
CREATE PROCEDURE sp_cancel_appointment(IN p_patient_id INT, IN p_appointment_id INT)
BEGIN
    DECLARE v_owner INT;

    SELECT patient_id INTO v_owner
      FROM appointment
     WHERE appointment_id = p_appointment_id;

    IF v_owner IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-06: appointment not found';
    END IF;
    IF p_patient_id IS NULL OR v_owner <> p_patient_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NFR-02: cannot cancel another patient''s appointment';
    END IF;

    UPDATE appointment
       SET status = 'CANCELLED'
     WHERE appointment_id = p_appointment_id
       AND patient_id = p_patient_id;

    SELECT appointment_id, status
      FROM appointment
     WHERE appointment_id = p_appointment_id;
END$$

-- FR-03 / NFR-04: list a patient's appointments without reading clinical text or writing SELECT audits.
CREATE PROCEDURE sp_patient_appointments(IN p_patient_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patient WHERE patient_id = p_patient_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-04: unknown patient';
    END IF;

    SELECT a.appointment_id, s.shift_date, a.start_time, a.end_time,
           a.appointment_type, a.status,
           d.doctor_id, d.full_name AS doctor_name, d.spec_type, r.room_code
      FROM appointment a
      JOIN shift s     ON s.shift_id = a.shift_id
      JOIN doctor d    ON d.doctor_id = s.doctor_id
      LEFT JOIN room r ON r.room_id = s.room_id
     WHERE a.patient_id = p_patient_id
     ORDER BY a.start_time DESC;
END$$

-- BR-22 / BR-23: list consultations involving p_doctor_id (with reason & opinion kept hidden from direct SELECT).
CREATE PROCEDURE sp_list_my_consultations(IN p_doctor_id INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM doctor WHERE doctor_id = p_doctor_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-04: unknown doctor';
    END IF;

    SELECT cr.request_id, cr.record_id,
           cr.requesting_doctor_id, rq.full_name AS requesting_doctor_name,
           cr.consulting_doctor_id, cs.full_name AS consulting_doctor_name,
           cr.reason, cr.status, cr.requested_at, cr.responded_at, cr.expires_at, cr.opinion
      FROM consultation_request cr
      JOIN doctor rq ON rq.doctor_id = cr.requesting_doctor_id
      JOIN doctor cs ON cs.doctor_id = cr.consulting_doctor_id
     WHERE cr.requesting_doctor_id = p_doctor_id
        OR cr.consulting_doctor_id = p_doctor_id
     ORDER BY cr.requested_at DESC;
END$$

-- BR-22 / BR-23: read one consultation request only if p_doctor_id is a party to it.
CREATE PROCEDURE sp_get_consultation(IN p_request_id INT, IN p_doctor_id INT)
BEGIN
    DECLARE v_req_doc  INT;
    DECLARE v_cons_doc INT;

    SELECT requesting_doctor_id, consulting_doctor_id
      INTO v_req_doc, v_cons_doc
      FROM consultation_request
     WHERE request_id = p_request_id;

    IF v_req_doc IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: consultation request not found';
    END IF;
    IF p_doctor_id IS NULL OR p_doctor_id NOT IN (v_req_doc, v_cons_doc) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-22: access denied to this consultation request';
    END IF;

    SELECT cr.request_id, cr.record_id,
           cr.requesting_doctor_id, rq.full_name AS requesting_doctor_name,
           cr.consulting_doctor_id, cs.full_name AS consulting_doctor_name,
           cr.reason, cr.status, cr.requested_at, cr.responded_at, cr.expires_at, cr.opinion
      FROM consultation_request cr
      JOIN doctor rq ON rq.doctor_id = cr.requesting_doctor_id
      JOIN doctor cs ON cs.doctor_id = cr.consulting_doctor_id
     WHERE cr.request_id = p_request_id;
END$$

DELIMITER ;
