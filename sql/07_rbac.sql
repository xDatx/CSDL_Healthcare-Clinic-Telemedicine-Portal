-- Author: Nguyễn Hoàng Dũng
-- RBAC cho MySQL 8.0
-- Lưu ý: chạy bằng root. Đổi password trước khi nộp bài.

USE healthcare;

DROP USER IF EXISTS 'app_patient'@'%';
DROP USER IF EXISTS 'app_doctor'@'%';
DROP USER IF EXISTS 'app_admin'@'%';

CREATE USER 'app_patient'@'%' IDENTIFIED BY 'Patient#2026';
CREATE USER 'app_doctor'@'%'  IDENTIFIED BY 'Doctor#2026';
CREATE USER 'app_admin'@'%'   IDENTIFIED BY 'Admin#2026';

-- Patient
GRANT SELECT ON healthcare.v_patient_medical_history TO 'app_patient'@'%';
GRANT SELECT ON healthcare.patient                    TO 'app_patient'@'%';
GRANT SELECT ON healthcare.appointment                TO 'app_patient'@'%';

-- Doctor
GRANT SELECT ON healthcare.doctor                      TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.shift                       TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.appointment                 TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.patient                     TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.medication                  TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.v_doctor_availability       TO 'app_doctor'@'%';
GRANT SELECT ON healthcare.v_active_consultation_access TO 'app_doctor'@'%';
GRANT EXECUTE ON PROCEDURE healthcare.sp_read_medical_record TO 'app_doctor'@'%';

-- Admin
GRANT SELECT, INSERT, UPDATE ON healthcare.admin            TO 'app_admin'@'%';
GRANT SELECT, INSERT, UPDATE ON healthcare.staff_permission TO 'app_admin'@'%';
GRANT SELECT, INSERT, UPDATE ON healthcare.specialty        TO 'app_admin'@'%';
GRANT SELECT, INSERT, UPDATE ON healthcare.room             TO 'app_admin'@'%';
GRANT SELECT, INSERT, UPDATE ON healthcare.medication       TO 'app_admin'@'%';
GRANT SELECT                 ON healthcare.doctor           TO 'app_admin'@'%';

FLUSH PRIVILEGES;