# Hướng dẫn chạy SQL (MySQL 8.0.18+)

## Yêu cầu

- MySQL Server **8.0.18 trở lên** (`SELECT VERSION();` để kiểm tra).
  - Dưới 8.0.16: `CHECK` được parse nhưng **không được kiểm tra**, nhiều test sẽ sai.
  - Dưới 8.0.18: không có `EXPLAIN ANALYZE` (chỉ ảnh hưởng file performance).
- DBeaver 22+ hoặc MySQL client (`mysql`).

## Cấu trúc thư mục

```text
sql/
  run_all.sql                  dựng toàn bộ database một lần (chạy file này là đủ)
  00_init.sql                  DROP + CREATE database healthcare
  ddl/01..10_*.sql             17 bảng
  02_indexes.sql               7 index (NFR-01 / NFR-03)
  triggers/                    25 trigger + procedure kiểm tra dùng chung
  procedures/sp_read_medical_record.sql   fn_can_read_record, sp_read_medical_record,
                                          sp_patient_history, sp_book_appointment,
                                          sp_cancel_appointment, sp_patient_appointments,
                                          sp_list_my_consultations, sp_get_consultation
  views/v_views.sql            7 view
  05_seed_data.sql             dữ liệu mẫu (đi qua toàn bộ trigger)
  07_rbac.sql                  3 role + 3 tài khoản ứng dụng
  99_teardown.sql              xóa database, user, role
  queries/                     16 truy vấn (Q01..Q16)
seed/
  seed_bulk_patients.sql       10.000 bệnh nhân
  seed_bulk_medications.sql    500 thuốc
  seed_bulk_activity.sql       41 bác sĩ, ca trực, ~19.700 lịch hẹn, hồ sơ, đơn thuốc
tests/
  run_all_tests.sql            67 test tự động (TC-01..TC-67)
  performance_explain.sql      kế hoạch thực thi các truy vấn chính
  performance_before_after.sql so sánh có / không có index
docs/
  performance.md               số liệu đo được
  traceability_matrix.md       quy tắc nghiệp vụ -> cài đặt -> test
```

## Cách chạy

### Bằng MySQL client

```bash
cd sql
mysql -u root -p --default-character-set=utf8mb4 -e "source run_all.sql"
cd ..
mysql -u root -p --default-character-set=utf8mb4 healthcare < tests/run_all_tests.sql
```

Kết quả mong đợi của bộ test: `total_tests = 67, passed = 67, failed = 0`.

> **Cảnh báo:** `00_init.sql` xóa và tạo lại database `healthcare`.

### Bằng DBeaver

DBeaver không hỗ trợ `SOURCE`. Mở từng file và chạy bằng **Alt+X** (Execute SQL Script) theo thứ tự:

1. `sql/00_init.sql`
2. `sql/ddl/01_admin.sql` ... `sql/ddl/10_consultation.sql` (theo số thứ tự)
3. `sql/02_indexes.sql`
4. `sql/triggers/trg_doctor_module.sql`, `trg_appointment_audit.sql`, `trg_medication_consultation.sql`
5. `sql/procedures/sp_read_medical_record.sql`
6. `sql/views/v_views.sql`
7. `sql/05_seed_data.sql`
8. `sql/07_rbac.sql`

File có `DELIMITER` (trigger, procedure, test) cần chạy bằng **Execute SQL Script**, không dùng Ctrl+Enter.

### Dữ liệu lớn và đo hiệu năng (tùy chọn)

Chạy **sau** `run_all.sql`, theo thứ tự (khoảng 5 giây):

```bash
mysql -u root -p --default-character-set=utf8mb4 healthcare < seed/seed_bulk_patients.sql
mysql -u root -p --default-character-set=utf8mb4 healthcare < seed/seed_bulk_medications.sql
mysql -u root -p --default-character-set=utf8mb4 healthcare < seed/seed_bulk_activity.sql
mysql -u root -p --default-character-set=utf8mb4 healthcare < tests/performance_explain.sql
mysql -u root -p --default-character-set=utf8mb4 healthcare < tests/performance_before_after.sql
```

Các file seed chạy lại nhiều lần không tạo trùng. Hồ sơ bệnh án và audit log là append-only nên không xóa riêng được;
để về trạng thái ban đầu hãy chạy lại `run_all.sql`.

## Mô hình truy cập (đọc trước khi demo)

- Ứng dụng **không có quyền `SELECT`** trên `medical_record`, `prescription`, `prescription_item`.
  Mọi lần đọc đi qua `sp_read_medical_record(record_id, actor_type, actor_id)` hoặc `sp_patient_history(patient_id)`;
  hai thủ tục này kiểm tra quyền (BR-20/21/22, NFR-02) rồi ghi audit (NFR-04).
- Trước khi ghi, ứng dụng đặt ngữ cảnh audit: `SET @app_actor_type = 'DOCTOR'; SET @app_actor_id = <id>;`
  (với danh mục thuốc: `SET @app_actor_id = <admin_id>;`).
- MySQL không biết người dùng cuối đứng sau một kết nối chung, nên backend (Phase 4) phải truyền đúng id của người
  đã đăng nhập vào các thủ tục. Đây là giới hạn đã biết, ghi trong `docs/traceability_matrix.md`.
- Mật khẩu trong `07_rbac.sql` chỉ để demo, phải đổi trước khi dùng thật.

## Lỗi thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| `Error 3823` khi tạo bảng | Cột nằm trong `CHECK` và trong FK có `ON UPDATE CASCADE`. Schema này dùng `ON UPDATE RESTRICT` ở các FK đó. |
| Các test CHECK (TC-09, TC-21, TC-28, TC-40, TC-60) không bắt được lỗi | MySQL dưới 8.0.16 không enforce `CHECK`. |
| `BR-25: set @app_actor_id ...` | Chưa đặt `@app_actor_id` (một admin đang hoạt động) trước khi sửa bảng `medication`. |
| `NFR-04: actor must be ...` | `@app_actor_type` đặt khác `PATIENT` / `DOCTOR` / `ADMIN`, hoặc thiếu `@app_actor_id`. Để trống cả hai thì audit ghi nhận bác sĩ điều trị. |
