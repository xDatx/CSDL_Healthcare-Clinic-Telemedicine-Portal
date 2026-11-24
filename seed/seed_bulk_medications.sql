USE healthcare;

CREATE TABLE medical_record_audit_log (
    audit_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    record_id  INT NOT NULL,
    actor_type VARCHAR(10) NOT NULL,
    actor_id   INT NOT NULL,
    action     VARCHAR(10) NOT NULL,
    action_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details    JSON,
    CONSTRAINT ck_mr_audit_actor  CHECK (actor_type IN ('PATIENT','DOCTOR','ADMIN')),
    CONSTRAINT ck_mr_audit_action CHECK (action IN ('INSERT','UPDATE','SELECT'))
);

