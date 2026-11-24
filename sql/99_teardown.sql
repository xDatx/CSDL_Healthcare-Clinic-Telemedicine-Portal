USE healthcare;

DROP VIEW IF EXISTS v_active_consultation_access;
DROP VIEW IF EXISTS v_doctor_availability;
DROP VIEW IF EXISTS v_patient_medical_history;

DROP TABLE IF EXISTS consultation_request;
DROP TABLE IF EXISTS prescription_item;
DROP TABLE IF EXISTS prescription;
DROP TABLE IF EXISTS medication_audit_log;
DROP TABLE IF EXISTS medication;
DROP TABLE IF EXISTS medical_record_audit_log;
DROP TABLE IF EXISTS medical_record;
DROP TABLE IF EXISTS appointment;
DROP TABLE IF EXISTS patient;
DROP TABLE IF EXISTS shift;
DROP TABLE IF EXISTS gp;
DROP TABLE IF EXISTS specialist;
DROP TABLE IF EXISTS doctor;
DROP TABLE IF EXISTS specialty;
DROP TABLE IF EXISTS room;
DROP TABLE IF EXISTS staff_permission;
DROP TABLE IF EXISTS admin;

DROP PROCEDURE IF EXISTS sp_read_medical_record;
