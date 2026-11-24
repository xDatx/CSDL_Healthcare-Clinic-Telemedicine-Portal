USE healthcare;

CREATE TABLE prescription (
    prescription_id INT AUTO_INCREMENT PRIMARY KEY,
    record_id       INT NOT NULL UNIQUE,
    issued_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pres_record FOREIGN KEY (record_id)
        REFERENCES medical_record (record_id) ON DELETE CASCADE
);

CREATE TABLE prescription_item (
    item_id         INT AUTO_INCREMENT PRIMARY KEY,
    prescription_id INT NOT NULL,
    medication_id   INT NOT NULL,
    quantity        INT NOT NULL,
    dosage          VARCHAR(120) NOT NULL,
    frequency       VARCHAR(120) NOT NULL,
    duration_days   INT NOT NULL,
    CONSTRAINT ck_item_qty  CHECK (quantity > 0),
    CONSTRAINT ck_item_days CHECK (duration_days > 0),
    CONSTRAINT fk_item_presc FOREIGN KEY (prescription_id)
        REFERENCES prescription (prescription_id) ON DELETE CASCADE,
    CONSTRAINT fk_item_med FOREIGN KEY (medication_id)
        REFERENCES medication (medication_id)
);
