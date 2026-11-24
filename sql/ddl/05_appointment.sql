USE healthcare;

CREATE TABLE appointment (
    appointment_id   INT AUTO_INCREMENT PRIMARY KEY,
    patient_id       INT NOT NULL,
    shift_id         INT NOT NULL,
    start_time       DATETIME NOT NULL,
    end_time         DATETIME NOT NULL,
    appointment_type VARCHAR(15) NOT NULL,
    status           VARCHAR(15) NOT NULL DEFAULT 'PENDING',
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_appt_type   CHECK (appointment_type IN ('IN_PERSON','TELEMEDICINE')),
    CONSTRAINT ck_appt_status CHECK (status IN
        ('PENDING','CONFIRMED','IN_PROGRESS','COMPLETED','CANCELLED')),
    CONSTRAINT ck_appt_time   CHECK (end_time > start_time),
    CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id) REFERENCES patient (patient_id),
    CONSTRAINT fk_appt_shift   FOREIGN KEY (shift_id)   REFERENCES shift (shift_id)
);

CREATE INDEX idx_appt_shift_time ON appointment (shift_id, start_time);