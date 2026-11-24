USE healthcare;

CREATE TABLE medication (
    medication_id INT AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(120) NOT NULL,
    unit          VARCHAR(20)  NOT NULL,
    description   TEXT,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE medication_audit_log (
    audit_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    medication_id INT NOT NULL,
    admin_id      INT NOT NULL,
    action        VARCHAR(15) NOT NULL,
    action_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values    JSON,
    new_values    JSON,
    CONSTRAINT ck_med_audit_action CHECK (action IN ('INSERT','UPDATE','DEACTIVATE'))
);
