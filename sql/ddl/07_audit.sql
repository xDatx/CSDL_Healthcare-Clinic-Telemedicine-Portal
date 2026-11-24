USE healthcare;

-- NFR-04: append-only trail of every INSERT / UPDATE / SELECT on a medical record.
-- Exactly one actor per row ("exclusive arc"): patient_id XOR doctor_id XOR admin_id.
CREATE TABLE medical_record_audit_log (
    audit_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    record_id  INT NOT NULL,
    patient_id INT NULL,
    doctor_id  INT NULL,
    admin_id   INT NULL,
    action     VARCHAR(10) NOT NULL,
    action_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    details    JSON,
    CONSTRAINT ck_mr_audit_action CHECK (action IN ('INSERT','UPDATE','SELECT')),
    CONSTRAINT ck_mr_audit_one_actor CHECK
        ((patient_id IS NOT NULL) + (doctor_id IS NOT NULL) + (admin_id IS NOT NULL) = 1),
    CONSTRAINT fk_mr_audit_record  FOREIGN KEY (record_id)  REFERENCES medical_record (record_id),
    CONSTRAINT fk_mr_audit_patient FOREIGN KEY (patient_id) REFERENCES patient (patient_id),
    CONSTRAINT fk_mr_audit_doctor  FOREIGN KEY (doctor_id)  REFERENCES doctor (doctor_id),
    CONSTRAINT fk_mr_audit_admin   FOREIGN KEY (admin_id)   REFERENCES admin (admin_id)
);
