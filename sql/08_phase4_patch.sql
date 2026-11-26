-- =============================================================================
-- 08_phase4_patch.sql  |  Apply the Phase 4 database changes to an EXISTING `healthcare` database
--                         (does NOT drop anything; run_all.sql already contains the same changes
--                          for a from-scratch build)
--
--   cd sql
--   mysql -u root -p --default-character-set=utf8mb4 healthcare < 08_phase4_patch.sql
--
-- What it adds
--   * FR-01 patient self-service: sp_register_patient, sp_get_my_profile, sp_update_my_profile
--   * doctor: read-only SELECT on `room` (room dropdown in the shift form, BR-03)
-- =============================================================================
USE healthcare;

SOURCE procedures/sp_patient_self_service.sql;

GRANT EXECUTE ON PROCEDURE healthcare.sp_register_patient  TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_get_my_profile    TO 'r_patient';
GRANT EXECUTE ON PROCEDURE healthcare.sp_update_my_profile TO 'r_patient';
GRANT SELECT ON healthcare.room TO 'r_doctor';

FLUSH PRIVILEGES;
