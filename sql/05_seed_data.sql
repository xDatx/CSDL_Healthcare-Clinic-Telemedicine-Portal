USE healthcare;
SET NAMES utf8mb4;
-- Reference date of the sample data: 2026-11-24 ("today"). Fixed dates keep every test and
-- every query result reproducible. All rows pass the business-rule triggers, and the appointment
-- lifecycle is driven through the real transitions, so this script is also a positive test.

-- ===== Author: Nguyễn Hoàng Dũng (admins, permissions, catalogs, doctors, shifts) =====
INSERT INTO admin (admin_id, full_name, email, role) VALUES
  (1, 'Nguyễn Thị Lan', 'lan.nguyen@clinic.local',  'SYSTEM_ADMIN'),
  (2, 'Trần Văn Hùng',  'hung.tran@clinic.local',   'SYSTEM_ADMIN'),
  (3, 'Lê Thu Trang',   'trang.le@clinic.local',    'RECEPTIONIST');

-- BR-20 bootstrap: admin 1 self-grants each code once, then delegates what it holds
INSERT INTO staff_permission (admin_id, permission_code, granted_by) VALUES
  (1, 'CREATE_DOCTOR',      1),
  (1, 'MANAGE_MEDICATION',  1),
  (1, 'VIEW_ALL_RECORDS',   1),
  (1, 'ASSIGN_PERMISSION',  1),
  (2, 'CREATE_DOCTOR',      1),
  (2, 'MANAGE_MEDICATION',  1),
  (2, 'VIEW_ALL_RECORDS',   1),
  (2, 'ASSIGN_PERMISSION',  1);

INSERT INTO specialty (specialty_id, name) VALUES
  (1, 'Cardiology'), (2, 'Dermatology'), (3, 'Pediatrics'),
  (4, 'Otolaryngology'), (5, 'Neurology'), (6, 'Orthopedics');

INSERT INTO room (room_id, room_code, floor) VALUES
  (1, 'A101', 1), (2, 'A102', 1), (3, 'A103', 1), (4, 'B201', 2), (5, 'B202', 2);

-- doctors start inactive (BR-01); doctor 10 stays without a subtype row on purpose
INSERT INTO doctor (doctor_id, full_name, email, license_no, employment_type, spec_type, created_by) VALUES
  (1,  'Trần Minh Khoa',     'khoa.tran@clinic.local',   'VN-BYT-001101', 'FULL_TIME', 'GP',         1),
  (2,  'Lê Thị Hồng Nhung',  'nhung.le@clinic.local',    'VN-BYT-001102', 'PART_TIME', 'GP',         1),
  (3,  'Phạm Quốc Bảo',      'bao.pham@clinic.local',    'VN-BYT-001103', 'PART_TIME', 'GP',         1),
  (4,  'Võ Thanh Tùng',      'tung.vo@clinic.local',     'VN-BYT-002201', 'FULL_TIME', 'SPECIALIST', 1),
  (5,  'Đặng Ngọc Mai',      'mai.dang@clinic.local',    'VN-BYT-002202', 'PART_TIME', 'SPECIALIST', 1),
  (6,  'Bùi Anh Thư',        'thu.bui@clinic.local',     'VN-BYT-002203', 'FULL_TIME', 'SPECIALIST', 2),
  (7,  'Hoàng Gia Huy',      'huy.hoang@clinic.local',   'VN-BYT-002204', 'PART_TIME', 'SPECIALIST', 2),
  (8,  'Ngô Đức Long',       'long.ngo@clinic.local',    'VN-BYT-002205', 'FULL_TIME', 'SPECIALIST', 2),
  (9,  'Phan Thị Kim Ngân',  'ngan.phan@clinic.local',   'VN-BYT-002206', 'PART_TIME', 'SPECIALIST', 2),
  (10, 'Đỗ Quang Vinh',      'vinh.do@clinic.local',     'VN-BYT-001104', 'FULL_TIME', 'GP',         2);

INSERT INTO gp (doctor_id) VALUES (1), (2), (3);
INSERT INTO specialist (doctor_id, specialty_id, years_practice) VALUES
  (4, 1, 15), (5, 2, 8), (6, 3, 12), (7, 4, 10), (8, 5, 18), (9, 1, 6);

UPDATE doctor SET is_active = TRUE WHERE doctor_id BETWEEN 1 AND 9;   -- trigger checks the subtype

-- shifts: GP -> room, Specialist -> no room (BR-03/26); PART_TIME -> rate, FULL_TIME -> none (BR-24)
INSERT INTO shift (shift_id, doctor_id, shift_date, start_time, end_time, status, room_id, rate_per_hour) VALUES
  (1,  1, '2026-11-16', '08:00', '12:00', 'ACTIVE', 1,    NULL),
  (2,  2, '2026-11-16', '13:00', '17:00', 'ACTIVE', 2,    250000),
  (3,  3, '2026-11-17', '08:00', '12:00', 'ACTIVE', 1,    240000),
  (4,  1, '2026-11-18', '13:00', '17:00', 'ACTIVE', 1,    NULL),
  (5,  2, '2026-11-19', '08:00', '12:00', 'ACTIVE', 2,    250000),
  (6,  3, '2026-11-20', '13:00', '17:00', 'ACTIVE', 3,    260000),
  (7,  4, '2026-11-16', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (8,  4, '2026-11-18', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (9,  5, '2026-11-17', '13:00', '17:00', 'ACTIVE', NULL, 300000),
  (10, 6, '2026-11-17', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (11, 6, '2026-11-19', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (12, 7, '2026-11-18', '13:00', '17:00', 'ACTIVE', NULL, 280000),
  (13, 8, '2026-11-19', '13:00', '17:00', 'ACTIVE', NULL, NULL),
  (14, 9, '2026-11-20', '08:00', '12:00', 'ACTIVE', NULL, 320000),
  (15, 1, '2026-11-23', '08:00', '12:00', 'ACTIVE', 1,    NULL),
  (16, 2, '2026-11-23', '13:00', '17:00', 'ACTIVE', 2,    250000),
  (17, 4, '2026-11-23', '13:00', '17:00', 'ACTIVE', NULL, NULL),
  (18, 6, '2026-11-24', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (19, 1, '2026-11-25', '08:00', '12:00', 'ACTIVE', 1,    NULL),
  (20, 3, '2026-11-25', '13:00', '17:00', 'ACTIVE', 3,    260000),
  (21, 4, '2026-11-26', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (22, 5, '2026-11-26', '13:00', '17:00', 'ACTIVE', NULL, 300000),
  (23, 8, '2026-11-27', '08:00', '12:00', 'ACTIVE', NULL, NULL),
  (24, 2, '2026-11-27', '13:00', '17:00', 'ACTIVE', 2,    250000);   -- cancelled below

-- ===== Author: Lý Thành Đạt (patients, appointments, medical records) =====
INSERT INTO patient (patient_id, full_name, dob, phone, email, address) VALUES
  (1,  'Nguyễn Văn An',      '1978-03-12', '0903111001', 'an.nguyen@example.com',   '12 Lê Lợi, Quận 1, TP.HCM'),
  (2,  'Trần Thị Bích',      '1985-07-22', '0903111002', NULL,                      '45 Nguyễn Trãi, Quận 5, TP.HCM'),
  (3,  'Lê Hoàng Cường',     '1992-11-05', '0903111003', 'cuong.le@example.com',    '8 Pasteur, Quận 3, TP.HCM'),
  (4,  'Phạm Thu Dung',      '1969-01-30', NULL,         'dung.pham@example.com',   '77 Hai Bà Trưng, Quận 1, TP.HCM'),
  (5,  'Võ Thanh Hải',       '1988-09-17', '0903111005', NULL,                      '21 Cách Mạng Tháng 8, Quận 10, TP.HCM'),
  (6,  'Đặng Thị Hạnh',      '1995-04-08', '0903111006', 'hanh.dang@example.com',   '5 Võ Văn Tần, Quận 3, TP.HCM'),
  (7,  'Bùi Quốc Hưng',      '1960-12-25', '0903111007', NULL,                      '90 Điện Biên Phủ, Bình Thạnh, TP.HCM'),
  (8,  'Hoàng Thị Lan Anh',  '1990-06-14', '0903111008', 'lananh.h@example.com',    '33 Nguyễn Huệ, Quận 1, TP.HCM'),
  (9,  'Ngô Văn Khánh',      '1975-02-19', '0903111009', NULL,                      '14 Phan Xích Long, Phú Nhuận, TP.HCM'),
  (10, 'Phan Thị Mỹ Linh',   '2001-08-03', '0903111010', 'mylinh.p@example.com',    '102 Lý Thường Kiệt, Quận 10, TP.HCM'),
  (11, 'Đỗ Hữu Nghĩa',       '1983-10-27', '0903111011', NULL,                      '56 Trần Hưng Đạo, Quận 5, TP.HCM'),
  (12, 'Vũ Thị Oanh',        '1998-05-21', NULL,         'oanh.vu@example.com',     '3 Nguyễn Đình Chiểu, Quận 3, TP.HCM'),
  (13, 'Trịnh Công Phúc',    '1972-09-09', '0903111013', 'phuc.trinh@example.com',  '28 Hoàng Văn Thụ, Tân Bình, TP.HCM'),
  (14, 'Lý Thanh Quang',     '1966-03-03', '0903111014', NULL,                      '19 Cộng Hòa, Tân Bình, TP.HCM'),
  (15, 'Huỳnh Văn Sơn',      '1958-11-11', '0903111015', NULL,                      '67 Nguyễn Văn Cừ, Quận 5, TP.HCM'),
  (16, 'Dương Thị Thảo',     '1963-07-07', '0903111016', 'thao.duong@example.com',  '41 Lạc Long Quân, Quận 11, TP.HCM'),
  (17, 'Mai Văn Thắng',      '1980-01-15', '0903111017', NULL,                      '9 Trường Chinh, Tân Bình, TP.HCM'),
  (18, 'Đinh Thị Uyên',      '1994-12-02', '0903111018', 'uyen.dinh@example.com',   '84 Nguyễn Thị Minh Khai, Quận 3, TP.HCM'),
  (19, 'Tạ Minh Vũ',         '1987-04-26', '0903111019', NULL,                      '15 Bạch Đằng, Bình Thạnh, TP.HCM'),
  (20, 'Lương Bảo Châu',     '2018-06-18', '0903111020', 'parent.luong@example.com','27 Phạm Ngọc Thạch, Quận 3, TP.HCM'),
  (21, 'Lương Gia Hân',      '2016-02-14', '0903111020', 'parent.luong@example.com','27 Phạm Ngọc Thạch, Quận 3, TP.HCM');

-- every appointment is created PENDING (BR-11) and moved through the lifecycle below
INSERT INTO appointment (appointment_id, patient_id, shift_id, start_time, end_time, appointment_type) VALUES
  (1,  1,  1,  '2026-11-16 08:00:00', '2026-11-16 08:30:00', 'IN_PERSON'),
  (2,  2,  1,  '2026-11-16 08:30:00', '2026-11-16 09:00:00', 'IN_PERSON'),
  (3,  3,  1,  '2026-11-16 09:00:00', '2026-11-16 09:30:00', 'TELEMEDICINE'),
  (4,  4,  1,  '2026-11-16 09:30:00', '2026-11-16 10:00:00', 'IN_PERSON'),
  (5,  5,  2,  '2026-11-16 13:00:00', '2026-11-16 13:30:00', 'IN_PERSON'),
  (6,  6,  2,  '2026-11-16 13:30:00', '2026-11-16 14:00:00', 'TELEMEDICINE'),
  (7,  1,  2,  '2026-11-16 14:00:00', '2026-11-16 14:30:00', 'IN_PERSON'),
  (8,  7,  3,  '2026-11-17 08:00:00', '2026-11-17 08:45:00', 'IN_PERSON'),
  (9,  8,  3,  '2026-11-17 08:45:00', '2026-11-17 09:15:00', 'TELEMEDICINE'),
  (10, 9,  4,  '2026-11-18 13:00:00', '2026-11-18 13:30:00', 'IN_PERSON'),
  (11, 10, 4,  '2026-11-18 13:30:00', '2026-11-18 14:00:00', 'IN_PERSON'),
  (12, 2,  4,  '2026-11-18 14:00:00', '2026-11-18 14:30:00', 'TELEMEDICINE'),
  (13, 11, 5,  '2026-11-19 08:00:00', '2026-11-19 08:30:00', 'IN_PERSON'),
  (14, 12, 5,  '2026-11-19 08:30:00', '2026-11-19 09:00:00', 'IN_PERSON'),
  (15, 13, 5,  '2026-11-19 09:00:00', '2026-11-19 09:30:00', 'TELEMEDICINE'),
  (16, 14, 6,  '2026-11-20 13:00:00', '2026-11-20 13:30:00', 'IN_PERSON'),
  (17, 15, 7,  '2026-11-16 08:00:00', '2026-11-16 08:45:00', 'IN_PERSON'),
  (18, 16, 7,  '2026-11-16 08:45:00', '2026-11-16 09:30:00', 'IN_PERSON'),
  (19, 1,  7,  '2026-11-16 09:30:00', '2026-11-16 10:15:00', 'TELEMEDICINE'),
  (20, 17, 8,  '2026-11-18 08:00:00', '2026-11-18 08:45:00', 'IN_PERSON'),
  (21, 15, 8,  '2026-11-18 08:45:00', '2026-11-18 09:30:00', 'TELEMEDICINE'),
  (22, 18, 9,  '2026-11-17 13:00:00', '2026-11-17 13:30:00', 'IN_PERSON'),
  (23, 19, 9,  '2026-11-17 13:30:00', '2026-11-17 14:00:00', 'IN_PERSON'),
  (24, 3,  9,  '2026-11-17 14:00:00', '2026-11-17 14:30:00', 'TELEMEDICINE'),
  (25, 20, 10, '2026-11-17 08:00:00', '2026-11-17 08:30:00', 'IN_PERSON'),
  (26, 21, 10, '2026-11-17 08:30:00', '2026-11-17 09:00:00', 'IN_PERSON'),
  (27, 20, 11, '2026-11-19 08:00:00', '2026-11-19 08:30:00', 'TELEMEDICINE'),
  (28, 5,  12, '2026-11-18 13:00:00', '2026-11-18 13:30:00', 'IN_PERSON'),
  (29, 6,  12, '2026-11-18 13:30:00', '2026-11-18 14:00:00', 'IN_PERSON'),
  (30, 7,  13, '2026-11-19 13:00:00', '2026-11-19 13:45:00', 'IN_PERSON'),
  (31, 9,  13, '2026-11-19 13:45:00', '2026-11-19 14:30:00', 'TELEMEDICINE'),
  (32, 16, 14, '2026-11-20 08:00:00', '2026-11-20 08:45:00', 'IN_PERSON'),
  (33, 11, 14, '2026-11-20 08:45:00', '2026-11-20 09:30:00', 'IN_PERSON'),
  (34, 13, 15, '2026-11-23 08:00:00', '2026-11-23 08:30:00', 'IN_PERSON'),
  (36, 8,  16, '2026-11-23 13:00:00', '2026-11-23 13:30:00', 'IN_PERSON'),
  (37, 2,  17, '2026-11-23 13:00:00', '2026-11-23 13:45:00', 'IN_PERSON'),
  (38, 20, 18, '2026-11-24 08:00:00', '2026-11-24 08:30:00', 'IN_PERSON'),
  (39, 21, 18, '2026-11-24 08:30:00', '2026-11-24 09:00:00', 'TELEMEDICINE'),
  (40, 3,  19, '2026-11-25 08:00:00', '2026-11-25 08:30:00', 'IN_PERSON'),
  (41, 4,  19, '2026-11-25 08:30:00', '2026-11-25 09:00:00', 'TELEMEDICINE'),
  (42, 17, 20, '2026-11-25 13:00:00', '2026-11-25 13:30:00', 'IN_PERSON'),
  (43, 15, 21, '2026-11-26 08:00:00', '2026-11-26 08:45:00', 'IN_PERSON'),
  (44, 1,  21, '2026-11-26 08:45:00', '2026-11-26 09:30:00', 'TELEMEDICINE'),
  (45, 18, 22, '2026-11-26 13:00:00', '2026-11-26 13:30:00', 'TELEMEDICINE'),
  (46, 7,  23, '2026-11-27 08:00:00', '2026-11-27 08:45:00', 'IN_PERSON'),
  (47, 19, 24, '2026-11-27 13:00:00', '2026-11-27 13:30:00', 'IN_PERSON');

-- Lifecycle (BR-11). Final: 33 COMPLETED, 1 IN_PROGRESS, 3 CONFIRMED, 5 PENDING, 4 CANCELLED
UPDATE appointment SET status = 'CANCELLED' WHERE appointment_id IN (4, 14, 24, 47);
UPDATE appointment SET status = 'CONFIRMED'
 WHERE status = 'PENDING' AND appointment_id NOT IN (41, 42, 44, 45, 46);
UPDATE appointment SET status = 'IN_PROGRESS'
 WHERE status = 'CONFIRMED' AND appointment_id NOT IN (39, 40, 43);
UPDATE appointment SET status = 'COMPLETED'
 WHERE status = 'IN_PROGRESS' AND appointment_id <> 38;

-- shift 24 withdrawn after its only booking was cancelled (history is kept)
UPDATE shift SET status = 'CANCELLED' WHERE shift_id = 24;

-- Medical records (BR-12; audited by trigger as the treating doctor). record_id = appointment_id.
-- Appointments 3, 12, 29, 37 are COMPLETED without a record on purpose (query Q14).
INSERT INTO medical_record
  (record_id, appointment_id, systolic_bp, diastolic_bp, heart_rate, temperature_c, oxygen_saturation, symptoms, diagnosis, notes) VALUES
  (1,  1,  120, 78,  82,  37.8, 98, 'Sore throat, cough and runny nose for 3 days',   'Acute upper respiratory infection', 'Rest and fluids; return if fever lasts beyond 3 days'),
  (2,  2,  118, 76,  76,  36.8, 99, 'Epigastric pain after meals, nausea',            'Gastritis',                         'Avoid spicy food and coffee'),
  (5,  5,  148, 94,  84,  36.7, 98, 'Morning headache and dizziness',                 'Essential hypertension',            'Start low-dose amlodipine; keep a home BP log'),
  (6,  6,  NULL,NULL,NULL,NULL,NULL,'Productive cough for 5 days',                    'Acute bronchitis',                  'Remote consultation, no vitals captured'),
  (7,  7,  130, 84,  78,  36.6, 98, 'Lower back pain after lifting',                  'Lower back pain',                   'Physiotherapy exercises advised'),
  (8,  8,  142, 88,  80,  36.6, 97, 'Increased thirst and fatigue',                   'Type 2 diabetes mellitus',          'HbA1c due at next visit'),
  (9,  9,  NULL,NULL,NULL,NULL,NULL,'Sneezing and itchy eyes',                        'Seasonal allergic rhinitis',        'Avoid known allergens'),
  (10, 10, 110, 70,  92,  37.4, 98, 'Diarrhea and vomiting for 2 days',               'Acute gastroenteritis',             'Oral rehydration; light diet'),
  (11, 11, 116, 74,  80,  37.2, 99, 'Mild cough and nasal congestion',                'Acute upper respiratory infection', 'Symptomatic care only'),
  (13, 13, 126, 82,  74,  36.7, 99, 'Persistent lower back pain',                     'Lower back pain',                   'Review in two weeks'),
  (15, 15, NULL,NULL,NULL,NULL,NULL,'Pressure headache in the afternoon',             'Tension headache',                  'Stress management advised'),
  (16, 16, 152, 96,  88,  36.6, 96, 'Headache, blurred vision',                       'Essential hypertension',            'Refer to cardiology if no improvement'),
  (17, 17, 138, 86,  90,  36.7, 96, 'Chest tightness on exertion',                    'Stable angina',                     'ECG and stress test ordered'),
  (18, 18, 132, 84,  118, 36.8, 95, 'Palpitations and shortness of breath',           'Atrial fibrillation (suspected)',   'Holter monitoring scheduled'),
  (19, 19, NULL,NULL,NULL,NULL,NULL,'Follow-up of blood pressure control',            'Hypertension follow-up',            'Telemedicine follow-up; readings reported by patient'),
  (20, 20, 160, 100, 80,  36.6, 98, 'Headache and tinnitus',                          'Essential hypertension',            'Combination therapy discussed'),
  (21, 21, NULL,NULL,NULL,NULL,NULL,'Follow-up of exertional chest tightness',        'Stable angina',                     'Symptoms improved on treatment'),
  (22, 22, NULL,NULL,NULL,NULL,NULL,'Itchy dry patches on both elbows',               'Atopic dermatitis',                 'Moisturiser twice daily'),
  (23, 23, NULL,NULL,NULL,NULL,NULL,'Red rash after new detergent',                   'Contact dermatitis',                'Avoid the trigger product'),
  (25, 25, NULL,NULL,110, 38.5, 98, 'Ear pain and fever for 2 days',                  'Acute otitis media',                'Weight-based antibiotic dosing'),
  (26, 26, NULL,NULL,96,  38.6, 98, 'Fever and fatigue',                              'Viral fever',                       'Monitor temperature; fluids'),
  (27, 27, NULL,NULL,NULL,NULL,NULL,'Follow-up of ear pain',                          'Acute otitis media',                'Improving; complete antibiotic course'),
  (28, 28, 124, 80,  78,  36.8, 98, 'Nasal blockage and facial pressure for 3 weeks', 'Chronic sinusitis',                 'Saline irrigation advised'),
  (30, 30, 136, 86,  76,  36.7, 98, 'Spinning sensation when turning in bed',         'Vertigo (BPPV)',                    'Epley manoeuvre performed'),
  (31, 31, NULL,NULL,NULL,NULL,NULL,'Throbbing headache with light sensitivity',      'Migraine',                          'Keep a headache diary'),
  (32, 32, 146, 92,  86,  36.7, 97, 'Hypertension review, second cardiologist',       'Essential hypertension',            'Dose adjusted'),
  (33, 33, 128, 82,  72,  36.6, 99, 'Routine blood pressure follow-up',               'Hypertension follow-up',            'Continue current therapy'),
  (34, 34, 122, 78,  80,  37.9, 97, 'Cough with sputum for 4 days',                   'Acute bronchitis',                  'Return if breathless'),
  (36, 36, 118, 76,  74,  37.5, 99, 'Sore throat and painful swallowing',             'Acute pharyngitis',                 'Throat lozenges and rest');

-- ===== Author: Phạm Trần Quốc Việt (medications, prescriptions, consultations) =====
-- BR-25: the catalog trigger needs the acting admin
SET @app_actor_id = 2;
INSERT INTO medication (medication_id, name, unit, description) VALUES
  (1,  'Paracetamol 500 mg',               'tablet',  'Analgesic and antipyretic'),
  (2,  'Amoxicillin 500 mg',               'capsule', 'Broad-spectrum penicillin antibiotic'),
  (3,  'Ibuprofen 400 mg',                 'tablet',  'NSAID for pain and inflammation'),
  (4,  'Cetirizine 10 mg',                 'tablet',  'Second-generation antihistamine'),
  (5,  'Omeprazole 20 mg',                 'capsule', 'Proton pump inhibitor'),
  (6,  'Amlodipine 5 mg',                  'tablet',  'Calcium channel blocker for hypertension'),
  (7,  'Atorvastatin 20 mg',               'tablet',  'Statin for cholesterol control'),
  (8,  'Metformin 500 mg',                 'tablet',  'First-line oral antidiabetic'),
  (9,  'Salbutamol inhaler 100 mcg',       'inhaler', 'Short-acting bronchodilator'),
  (10, 'Loratadine 10 mg',                 'tablet',  'Non-sedating antihistamine'),
  (11, 'Hydrocortisone cream 1%',          'tube',    'Topical corticosteroid'),
  (12, 'Azithromycin 250 mg',              'tablet',  'Macrolide antibiotic'),
  (13, 'Oral rehydration salts',           'sachet',  'Fluid and electrolyte replacement'),
  (14, 'Vitamin D3 1000 IU',               'tablet',  'Vitamin D supplement'),
  (15, 'Ranitidine 150 mg',                'tablet',  'H2 blocker (withdrawn from the market)'),
  (16, 'Bisoprolol 5 mg',                  'tablet',  'Beta blocker'),
  (17, 'Betahistine 16 mg',                'tablet',  'Vestibular disorder treatment'),
  (18, 'Aspirin 81 mg',                    'tablet',  'Antiplatelet'),
  (19, 'Cetirizine syrup 5 mg/5 ml',       'bottle',  'Paediatric antihistamine'),
  (20, 'Amoxicillin suspension 250 mg/5 ml','bottle', 'Paediatric antibiotic');
UPDATE medication SET is_active = FALSE WHERE medication_id = 15;    -- logged as DEACTIVATE
SET @app_actor_id = NULL;

-- one prescription per record except record 11 (symptomatic care only); prescription_id = record_id
INSERT INTO prescription (prescription_id, record_id, issued_at)
SELECT mr.record_id, mr.record_id, TIMESTAMP(DATE(a.start_time), '17:00:00')
  FROM medical_record mr JOIN appointment a ON a.appointment_id = mr.appointment_id
 WHERE mr.record_id <> 11;

INSERT INTO prescription_item (prescription_id, medication_id, quantity, dosage, frequency, duration_days) VALUES
  (1, 1, 10, '500 mg',        'Every 6 hours when needed',   5),
  (1, 4, 5,  '10 mg',         'Once daily at night',         5),
  (2, 15, 28, '150 mg',       'Twice daily',                 14),
  (5, 6, 30, '5 mg',          'Once daily in the morning',   30),
  (6, 2, 21, '500 mg',        'Three times daily',           7),
  (6, 1, 10, '500 mg',        'Every 6 hours when needed',   5),
  (7, 3, 14, '400 mg',        'Twice daily after meals',     7),
  (7, 5, 7,  '20 mg',         'Once daily before breakfast', 7),
  (8, 8, 60, '500 mg',        'Twice daily with meals',      30),
  (9, 10, 10, '10 mg',        'Once daily',                  10),
  (10, 13, 10, '1 sachet in 200 ml water', 'After each loose stool', 3),
  (13, 3, 10, '400 mg',       'Twice daily after meals',     5),
  (15, 1, 10, '500 mg',       'Every 6 hours when needed',   5),
  (16, 6, 30, '5 mg',         'Once daily in the morning',   30),
  (16, 7, 30, '20 mg',        'Once daily at night',         30),
  (17, 18, 30, '81 mg',       'Once daily after lunch',      30),
  (17, 7, 30, '20 mg',        'Once daily at night',         30),
  (17, 16, 30, '5 mg',        'Once daily in the morning',   30),
  (18, 16, 30, '5 mg',        'Once daily in the morning',   30),
  (19, 6, 30, '5 mg',         'Once daily in the morning',   30),
  (20, 6, 30, '5 mg',         'Once daily in the morning',   30),
  (21, 18, 30, '81 mg',       'Once daily after lunch',      30),
  (21, 7, 30, '20 mg',        'Once daily at night',         30),
  (22, 11, 1, 'Thin layer',   'Twice daily',                 14),
  (22, 4, 14, '10 mg',        'Once daily at night',         14),
  (23, 11, 1, 'Thin layer',   'Twice daily',                 7),
  (25, 20, 1, '5 ml',         'Three times daily',           7),
  (25, 1, 10, '250 mg',       'Every 6 hours when needed',   3),
  (26, 1, 10, '250 mg',       'Every 6 hours when needed',   3),
  (27, 20, 1, '5 ml',         'Three times daily',           5),
  (28, 12, 6, '250 mg',       'Once daily',                  6),
  (28, 10, 10, '10 mg',       'Once daily',                  10),
  (30, 17, 60, '16 mg',       'Three times daily',           20),
  (31, 1, 10, '500 mg',       'Every 6 hours when needed',   5),
  (31, 3, 10, '400 mg',       'Twice daily after meals',     5),
  (32, 6, 30, '10 mg',        'Once daily in the morning',   30),
  (32, 16, 30, '5 mg',        'Once daily in the morning',   30),
  (33, 6, 30, '5 mg',         'Once daily in the morning',   30),
  (34, 2, 21, '500 mg',       'Three times daily',           7),
  (34, 9, 1, '2 puffs',       'When breathless, max 4 times daily', 7),
  (36, 12, 6, '250 mg',       'Once daily',                  6),
  (36, 1, 10, '500 mg',       'Every 6 hours when needed',   5);

-- BR-22 / BR-23: second-opinion requests (every request is created PENDING, then answered)
INSERT INTO consultation_request
  (request_id, record_id, requesting_doctor_id, consulting_doctor_id, reason, requested_at, expires_at) VALUES
  (1, 17, 4, 9, 'Second opinion on exertional chest pain and ECG',   '2026-11-17 09:00:00', '2026-12-31 23:59:00'),
  (2, 19, 4, 1, 'GP input on long-term blood pressure management',   '2026-11-20 08:30:00', '2026-12-31 23:59:00'),
  (3, 30, 8, 4, 'Cardiac cause of dizziness to be excluded',         '2026-11-23 16:00:00', NULL),
  (4, 22, 5, 2, 'General health review before long steroid course',  '2026-11-18 09:00:00', NULL),
  (5, 32, 9, 4, 'Second cardiologist opinion on dose adjustment',    '2026-11-20 10:00:00', '2026-11-22 18:00:00');

UPDATE consultation_request SET status = 'APPROVED',  responded_at = '2026-11-17 14:00:00' WHERE request_id = 1;
UPDATE consultation_request SET status = 'COMPLETED', opinion = 'Agree with the plan; add a treadmill stress test.' WHERE request_id = 1;
UPDATE consultation_request SET status = 'APPROVED',  responded_at = '2026-11-20 09:30:00' WHERE request_id = 2;
UPDATE consultation_request SET status = 'DECLINED',  responded_at = '2026-11-19 10:00:00' WHERE request_id = 4;
UPDATE consultation_request SET status = 'APPROVED',  responded_at = '2026-11-20 11:00:00' WHERE request_id = 5;  -- expired window

-- sample read-audit rows (what sp_read_medical_record writes), one per actor type
CALL sp_insert_record_audit(1,  'PATIENT', 1, 'SELECT', JSON_OBJECT('via', 'seed'));
CALL sp_insert_record_audit(17, 'DOCTOR',  9, 'SELECT', JSON_OBJECT('via', 'seed'));
CALL sp_insert_record_audit(19, 'DOCTOR',  1, 'SELECT', JSON_OBJECT('via', 'seed'));
CALL sp_insert_record_audit(5,  'ADMIN',   2, 'SELECT', JSON_OBJECT('via', 'seed'));
CALL sp_insert_record_audit(5,  'DOCTOR',  2, 'SELECT', JSON_OBJECT('via', 'seed'));
