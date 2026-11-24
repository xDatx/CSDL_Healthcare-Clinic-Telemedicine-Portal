USE healthcare;

-- ===== Author: Nguyễn Hoàng Dũng =====
SET @app_actor_id = 1;

INSERT INTO admin (full_name, email, role) VALUES
  ('Alice System',  'alice@clinic.local', 'SYSTEM_ADMIN'),
  ('Bob Reception', 'bob@clinic.local',   'RECEPTIONIST');

INSERT INTO staff_permission (admin_id, permission_code, granted_by) VALUES
  (1, 'CREATE_DOCTOR', 1),
  (1, 'MANAGE_MEDICATION', 1),
  (1, 'VIEW_ALL_RECORDS', 1),
  (1, 'ASSIGN_PERMISSION', 1);

INSERT INTO specialty (name) VALUES ('Cardiology'), ('Dermatology'), ('Pediatrics');
INSERT INTO room (room_code, floor) VALUES ('GP-101', 1), ('GP-102', 1);

INSERT INTO doctor (full_name, email, employment_type, spec_type, is_active, created_by) VALUES
  ('Dr. GP One',     'gp1@clinic.local',  'FULL_TIME', 'GP',         FALSE, 1),
  ('Dr. GP PartTime','gp2@clinic.local',  'PART_TIME', 'GP',         FALSE, 1),
  ('Dr. Cardio',     'card@clinic.local', 'FULL_TIME', 'SPECIALIST', FALSE, 1);

INSERT INTO gp (doctor_id, room_id) VALUES (1, 1), (2, 2);
INSERT INTO specialist (doctor_id, specialty_id, years_practice) VALUES (3, 1, 10);

UPDATE doctor SET is_active = TRUE WHERE doctor_id IN (1, 2, 3);

INSERT INTO shift (doctor_id, shift_date, start_time, end_time, status, room_id, rate_per_hour) VALUES
  (1, CURRENT_DATE,                    '08:00', '12:00', 'ACTIVE', 1,    NULL),
  (2, CURRENT_DATE,                    '13:00', '17:00', 'ACTIVE', 2,    250000),
  (3, CURRENT_DATE + INTERVAL 1 DAY,   '09:00', '12:00', 'ACTIVE', NULL, NULL);

-- ===== Author: Lý Thành Đạt =====
SET @app_actor_id = 1;

INSERT INTO patient (full_name, dob, phone, email) VALUES
  ('Patient A', '1990-01-01', '0901000001', NULL),
  ('Patient B', '1985-05-05', NULL, 'b@x.local');

INSERT INTO appointment (patient_id, shift_id, start_time, end_time, appointment_type, status) VALUES
  (1, 1, TIMESTAMP(CURRENT_DATE, '08:00:00'), TIMESTAMP(CURRENT_DATE, '08:30:00'), 'IN_PERSON', 'COMPLETED'),
  (2, 1, TIMESTAMP(CURRENT_DATE, '08:30:00'), TIMESTAMP(CURRENT_DATE, '09:00:00'), 'TELEMEDICINE', 'CONFIRMED');

INSERT INTO medical_record (appointment_id, systolic_bp, diastolic_bp, heart_rate, temperature_c, diagnosis)
VALUES (1, 120, 80, 72, 36.8, 'Mild hypertension');

-- Manual audit row for testing (audit trigger already wrote one on INSERT)
INSERT INTO medical_record_audit_log (record_id, actor_type, actor_id, action)
VALUES (1, 'PATIENT', 1, 'SELECT');

-- ===== Author: Phạm Trần Quốc Việt =====
SET @app_actor_id = 1;

INSERT INTO medication (name, unit, description) VALUES
  ('Paracetamol 500mg', 'tablet',  'Painkiller'),
  ('Amoxicillin 250mg', 'capsule', 'Antibiotic');

INSERT INTO prescription (record_id) VALUES (1);
INSERT INTO prescription_item (prescription_id, medication_id, quantity, dosage, frequency, duration_days) VALUES
  (1, 1, 10, '1 tablet',  '3 times/day', 5),
  (1, 2, 14, '1 capsule', '2 times/day', 7);