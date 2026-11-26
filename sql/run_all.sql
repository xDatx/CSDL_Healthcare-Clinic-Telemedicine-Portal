-- =============================================================================
-- run_all.sql  |  Build the whole database from scratch (MySQL 8.0.18+)
--
--   cd sql
--   mysql -u root -p --default-character-set=utf8mb4 -e "source run_all.sql"
--
-- DBeaver (no SOURCE support): open each file below and run it with Alt+X, in this order.
-- WARNING: 00_init.sql drops and recreates the database `healthcare`.
-- =============================================================================
SOURCE 00_init.sql;

SOURCE ddl/01_admin.sql;
SOURCE ddl/02_doctor.sql;
SOURCE ddl/03_shift.sql;
SOURCE ddl/04_patient.sql;
SOURCE ddl/05_appointment.sql;
SOURCE ddl/06_medical_record.sql;
SOURCE ddl/07_audit.sql;
SOURCE ddl/08_medication.sql;
SOURCE ddl/09_prescription.sql;
SOURCE ddl/10_consultation.sql;

SOURCE 02_indexes.sql;

SOURCE triggers/trg_doctor_module.sql;
SOURCE triggers/trg_appointment_audit.sql;
SOURCE triggers/trg_medication_consultation.sql;

SOURCE procedures/sp_read_medical_record.sql;
SOURCE procedures/sp_patient_self_service.sql;
SOURCE views/v_views.sql;

SOURCE 05_seed_data.sql;
SOURCE 07_rbac.sql;
