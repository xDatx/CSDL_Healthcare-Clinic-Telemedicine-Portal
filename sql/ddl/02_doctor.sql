USE healthcare;

CREATE TABLE specialty (
    specialty_id INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE room (
    room_id   INT AUTO_INCREMENT PRIMARY KEY,
    room_code VARCHAR(20) NOT NULL UNIQUE,
    floor     INT NOT NULL,
    CONSTRAINT ck_room_floor CHECK (floor BETWEEN 1 AND 20)
);

-- DOCTOR = superclass of the disjoint/total specialization (Elmasri option 8A)
CREATE TABLE doctor (
    doctor_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(120) NOT NULL UNIQUE,
    license_no      VARCHAR(50)  NOT NULL UNIQUE,
    employment_type VARCHAR(10)  NOT NULL,
    spec_type       VARCHAR(10)  NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT FALSE,
    created_by      INT NOT NULL,
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_doctor_emp  CHECK (employment_type IN ('FULL_TIME','PART_TIME')),
    CONSTRAINT ck_doctor_spec CHECK (spec_type IN ('GP','SPECIALIST')),
    CONSTRAINT fk_doctor_admin FOREIGN KEY (created_by) REFERENCES admin (admin_id),
    CONSTRAINT uq_doctor_spec  UNIQUE (doctor_id, spec_type)   -- target of the subtype composite FKs
);

-- GP: the room is assigned per SHIFT (BR-03), so no room column here.
-- ON UPDATE stays RESTRICT on purpose: MySQL rejects CHECK on a column that is
-- part of a FK with ON UPDATE CASCADE (error 3823).
CREATE TABLE gp (
    doctor_id INT PRIMARY KEY,
    spec_type VARCHAR(10) NOT NULL DEFAULT 'GP',
    CONSTRAINT ck_gp_spec CHECK (spec_type = 'GP'),
    CONSTRAINT fk_gp_doctor FOREIGN KEY (doctor_id, spec_type)
        REFERENCES doctor (doctor_id, spec_type) ON DELETE CASCADE
);

CREATE TABLE specialist (
    doctor_id      INT PRIMARY KEY,
    spec_type      VARCHAR(10) NOT NULL DEFAULT 'SPECIALIST',
    specialty_id   INT NOT NULL,
    years_practice INT NOT NULL,
    CONSTRAINT ck_spec_spec  CHECK (spec_type = 'SPECIALIST'),
    CONSTRAINT ck_spec_years CHECK (years_practice >= 0),
    CONSTRAINT fk_spec_doctor FOREIGN KEY (doctor_id, spec_type)
        REFERENCES doctor (doctor_id, spec_type) ON DELETE CASCADE,
    CONSTRAINT fk_spec_specialty FOREIGN KEY (specialty_id) REFERENCES specialty (specialty_id)
);
