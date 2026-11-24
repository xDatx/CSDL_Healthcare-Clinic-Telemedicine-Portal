
---

## 2. `README_SQL.md` — 

```markdown
# Hướng dẫn chạy SQL trong DBeaver (MySQL 8.0.16+)

## Yêu cầu

- MySQL Server 8.0.16 trở lên (`SELECT VERSION();` để kiểm tra)
- DBeaver Community 22+ (khuyến nghị 23+)

**Quan trọng:** MySQL < 8.0.16 parse `CHECK` constraint nhưng **không enforce**. Các test TC-06 (BR-17) sẽ fail nếu version thấp hơn.

## Cấu trúc thư mục

```text
sql/
  00_init.sql
  02_indexes.sql
  05_seed_data.sql
  07_rbac.sql
  99_teardown.sql
  ddl/          10 file tạo bảng
  triggers/     3 file trigger (12+ trigger)
  procedures/   sp_read_medical_record
  views/        3 view
  queries/      10 query phức tạp
seed/
  seed_bulk_patients.sql
tests/
  run_all_tests.sql
  performance_explain.sql
  performance_before_after.sql