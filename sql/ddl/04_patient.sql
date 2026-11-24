USE healthcare;

CREATE TABLE patient (
    patient_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL,
    dob        DATE NOT NULL,
    phone      VARCHAR(20),
    email      VARCHAR(120),
    address    TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_patient_contact CHECK (phone IS NOT NULL OR email IS NOT NULL)
);