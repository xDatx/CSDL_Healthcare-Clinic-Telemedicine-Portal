USE healthcare;

CREATE TABLE medication (
    medication_id INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(120) NOT NULL,
    unit          VARCHAR(20)  NOT NULL,
    description   TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- BR-25: every create / update / deactivate of a catalog entry is logged (append-only).
CREATE TABLE medication_audit_log (
    audit_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    medication_id INT NOT NULL,
    admin_id      INT NOT NULL,
    action        VARCHAR(15) NOT NULL,
    action_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values    JSON,
    new_values    JSON,
    CONSTRAINT ck_med_audit_action CHECK (action IN ('INSERT','UPDATE','DEACTIVATE')),
    CONSTRAINT fk_med_audit_med   FOREIGN KEY (medication_id) REFERENCES medication (medication_id),
    CONSTRAINT fk_med_audit_admin FOREIGN KEY (admin_id)      REFERENCES admin (admin_id)
);
