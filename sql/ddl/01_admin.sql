USE healthcare;

CREATE TABLE admin (
    admin_id    INT AUTO_INCREMENT PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE,
    role        VARCHAR(20)  NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_admin_role CHECK (role IN ('RECEPTIONIST','SYSTEM_ADMIN'))
);

CREATE TABLE staff_permission (
    permission_id   INT AUTO_INCREMENT PRIMARY KEY,
    admin_id        INT NOT NULL,
    permission_code VARCHAR(50) NOT NULL,
    granted_by      INT NOT NULL,
    granted_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_staff_perm UNIQUE (admin_id, permission_code),
    CONSTRAINT fk_perm_admin   FOREIGN KEY (admin_id)   REFERENCES admin (admin_id) ON DELETE CASCADE,
    CONSTRAINT fk_perm_grantor FOREIGN KEY (granted_by) REFERENCES admin (admin_id),
    CONSTRAINT ck_perm_code CHECK (permission_code IN
        ('CREATE_DOCTOR','MANAGE_MEDICATION','VIEW_ALL_RECORDS','ASSIGN_PERMISSION'))
);