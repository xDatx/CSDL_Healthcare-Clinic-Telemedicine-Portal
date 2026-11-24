USE healthcare;

CREATE TABLE medical_record (
    record_id         INT AUTO_INCREMENT PRIMARY KEY,
    appointment_id    INT NOT NULL UNIQUE,
    systolic_bp       INT,
    diastolic_bp      INT,
    heart_rate        INT,
    temperature_c     DECIMAL(4,1),
    oxygen_saturation INT,
    symptoms          TEXT,
    diagnosis         TEXT NOT NULL,
    notes             TEXT,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_mr_sysbp CHECK (systolic_bp IS NULL OR systolic_bp BETWEEN 60 AND 250),
    CONSTRAINT ck_mr_diabp CHECK (diastolic_bp IS NULL OR diastolic_bp BETWEEN 30 AND 150),
    CONSTRAINT ck_mr_hr    CHECK (heart_rate IS NULL OR heart_rate BETWEEN 20 AND 250),
    CONSTRAINT ck_mr_temp  CHECK (temperature_c IS NULL OR temperature_c BETWEEN 30 AND 45),
    CONSTRAINT ck_mr_o2    CHECK (oxygen_saturation IS NULL OR oxygen_saturation BETWEEN 50 AND 100),
    CONSTRAINT fk_mr_appointment FOREIGN KEY (appointment_id)
        REFERENCES appointment (appointment_id)
);