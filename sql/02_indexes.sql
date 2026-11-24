-- Author: Lý Thành Đạt
-- Module: Performance indexes for NFR-03
-- Run order: sau 10 file DDL, trước triggers
-- Ghi chú: KHÔNG tạo index trùng với FK auto-index hoặc UNIQUE constraint.
--          Kiểm tra trước bằng: SHOW INDEX FROM <table>;

USE healthcare;

-- Q01 / Q07: doctor slot lookup by (doctor_id, shift_date)
-- Composite vượt trội so với fk_shift_doctor (chỉ doctor_id)
CREATE INDEX idx_shift_doctor_date
    ON shift (doctor_id, shift_date);

-- Q02 + trg_appointment_no_overlap: overlap check mỗi INSERT
-- Composite (shift_id, start_time) serve cả WHERE shift_id = ? và range start_time
CREATE INDEX idx_appt_shift_time
    ON appointment (shift_id, start_time);

-- Q03: patient history ORDER BY start_time DESC — index sort sẵn, không filesort
CREATE INDEX idx_appt_patient_date
    ON appointment (patient_id, start_time DESC);

-- Q10 + sp_read_medical_record: audit log query theo record, sort DESC
CREATE INDEX idx_mr_audit_record
    ON medical_record_audit_log (record_id, action_at DESC);

-- BR-22: consultation access check
CREATE INDEX idx_consult_doctor_status
    ON consultation_request (consulting_doctor_id, status);

-- Q09: expiring approvals within 24h
CREATE INDEX idx_consult_expires
    ON consultation_request (expires_at);