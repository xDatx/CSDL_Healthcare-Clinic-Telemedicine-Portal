USE healthcare;

CREATE TABLE shift (
    shift_id      INT AUTO_INCREMENT PRIMARY KEY,
    doctor_id     INT NOT NULL,
    shift_date    DATE NOT NULL,
    start_time    TIME NOT NULL,
    end_time      TIME NOT NULL,
    status        VARCHAR(10) NOT NULL DEFAULT 'ACTIVE',
    room_id       INT,
    rate_per_hour DECIMAL(10,2),
    CONSTRAINT ck_shift_status CHECK (status IN ('ACTIVE','CANCELLED')),
    CONSTRAINT ck_shift_time   CHECK (end_time > start_time),
    CONSTRAINT ck_shift_rate   CHECK (rate_per_hour IS NULL OR rate_per_hour > 0),
    CONSTRAINT fk_shift_doctor FOREIGN KEY (doctor_id) REFERENCES doctor (doctor_id),
    CONSTRAINT fk_shift_room   FOREIGN KEY (room_id)   REFERENCES room (room_id)
);

CREATE INDEX idx_shift_doctor_date ON shift (doctor_id, shift_date);