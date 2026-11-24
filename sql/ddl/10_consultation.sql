USE healthcare;

CREATE TABLE consultation_request (
    request_id            INT AUTO_INCREMENT PRIMARY KEY,
    record_id             INT NOT NULL,
    requesting_doctor_id  INT NOT NULL,
    consulting_doctor_id  INT NOT NULL,
    reason                TEXT NOT NULL,
    status                VARCHAR(15) NOT NULL DEFAULT 'PENDING',
    requested_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    responded_at          DATETIME,
    expires_at            DATETIME,
    opinion               TEXT,
    CONSTRAINT ck_cr_status CHECK (status IN ('PENDING','APPROVED','DECLINED','COMPLETED')),
    CONSTRAINT ck_cr_diff   CHECK (requesting_doctor_id <> consulting_doctor_id),
    CONSTRAINT ck_cr_expiry CHECK (expires_at IS NULL OR expires_at > requested_at),
    CONSTRAINT ck_cr_state CHECK (
        (status = 'PENDING'   AND responded_at IS NULL     AND opinion IS NULL) OR
        (status IN ('APPROVED','DECLINED') AND responded_at IS NOT NULL) OR
        (status = 'COMPLETED' AND responded_at IS NOT NULL AND opinion IS NOT NULL)
    ),
    CONSTRAINT fk_cr_record     FOREIGN KEY (record_id)            REFERENCES medical_record (record_id),
    CONSTRAINT fk_cr_requesting FOREIGN KEY (requesting_doctor_id) REFERENCES doctor (doctor_id),
    CONSTRAINT fk_cr_consulting FOREIGN KEY (consulting_doctor_id) REFERENCES doctor (doctor_id)
);
