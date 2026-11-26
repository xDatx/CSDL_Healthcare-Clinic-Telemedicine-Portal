# Chuẩn bị bảo vệ (Phase 4)

Tài liệu này gom những gì cần nói và các câu hỏi dễ gặp. Mỗi câu trả lời trỏ tới file / đối tượng CSDL cụ thể để có thể mở ra chứng minh ngay.

## 1. Cấu trúc bài trình bày gợi ý (≈ 10 phút) + demo

| Phút | Nội dung | Mở file |
|---|---|---|
| 0–1 | Bài toán: phòng khám nhỏ dùng giấy và điện thoại → trùng lịch, hồ sơ rải rác, khó theo dõi đơn thuốc | `README.md` |
| 1–3 | Thiết kế: EER (specialization GP/Specialist, quan hệ hội chẩn), ánh xạ Elmasri, chuẩn hóa 3NF/BCNF | `docs/EER/`, báo cáo mục 2 |
| 3–5 | Cài đặt: 17 bảng, 25 trigger, thủ tục truy cập có kiểm soát, 7 view, 16 truy vấn, RBAC | `sql/`, `docs/traceability_matrix.md` |
| 5–6 | Hiệu năng: chỉ mục + EXPLAIN trước/sau | `docs/performance.md` |
| 6–15 | Demo trực tiếp (7 kịch bản) | `docs/demo_scenarios.md` |
| cuối | Giới hạn đã biết + hướng phát triển | mục 4 dưới đây |

## 2. Con số có thể nói (đều có bằng chứng trong repo)
- 17 bảng, 25 trigger, 7 view, 16 truy vấn mẫu, 7 chỉ mục.
- Dữ liệu lớn: 50 bác sĩ hoạt động, 10.021 bệnh nhân, 19.726 lịch hẹn.
- 67 ca kiểm thử SQL (`tests/run_all_tests.sql`) + 76 ca kiểm thử backend (`python -m pytest -q`, chạy trên CSDL thật; phần ghi chạy trong giao dịch rồi rollback).

## 3. Câu hỏi thường gặp và cách trả lời

### Thiết kế
**Vì sao `appointment` không có `doctor_id`?**
Vì `appointment_id → shift_id → doctor_id` là phụ thuộc bắc cầu, vi phạm 3NF. Bác sĩ của lịch hẹn lấy qua `shift`; view `v_appointment_detail` đưa thông tin này ra cho ứng dụng (báo cáo 2.3, BR-07).

**Phân cấp DOCTOR → GP / SPECIALIST làm thế nào? Vì sao chọn Option 8A?**
Mỗi bảng con có khóa chính = khóa ngoại tới `doctor`. 8A tránh cột NULL và cho phép cấp quyền riêng cho từng loại. Điều kiện *disjoint* được bảo đảm khai báo bằng khóa ngoại ghép `(doctor_id, spec_type)` + `CHECK spec_type = 'GP'/'SPECIALIST'`; điều kiện *total* không khai báo được nên dùng trigger (không cho `is_active = TRUE` nếu chưa có đúng một dòng ở GP hoặc SPECIALIST — BR-01).

**Vì sao `rate_per_hour` nằm ở `shift` mà không ở `doctor`?**
Đơn giá thỏa thuận theo từng ca (thâm niên, ca tối, cuối tuần) và phải giữ nguyên lịch sử lương của ca đã làm (BR-24). Đặt ở `doctor` sẽ mất lịch sử và gây phụ thuộc sai.

**`CONSULTATION_REQUEST` sao không phải quan hệ ba ngôi (ternary)?**
Nó nối một hồ sơ với hai bác sĩ ở hai vai khác nhau; mô hình hóa thành thực thể có ba quan hệ 1:N nhị phân nên không cần bước 7 của thuật toán ánh xạ và vẫn có thể gắn trạng thái, thời hạn, ý kiến.

**Vì sao khóa chính ghép ở `prescription_item`?**
Là thực thể kết hợp giải quyết M:N giữa đơn thuốc và thuốc (BR-16); cặp `(prescription_id, medication_id)` chặn kê trùng một thuốc trong cùng đơn, và các thuộc tính liều dùng phụ thuộc cả cặp (đạt 2NF).

### Ràng buộc và trigger
**Vì sao chống đặt trùng lịch phải dùng trigger mà không dùng UNIQUE/CHECK?**
Đó là kiểm tra chồng lấn khoảng thời gian giữa nhiều dòng, loại trừ lịch `CANCELLED` → UNIQUE/CHECK (chỉ nhìn một dòng) không biểu diễn được. Trigger BR-09 kiểm tra trong phạm vi một ca; vì BR-05 cấm hai ca của cùng bác sĩ chồng nhau nên kiểm tra theo ca là đủ. Chỉ mục `(shift_id, start_time)` làm cho phép kiểm tra nhanh.

**Làm sao bảo đảm trạng thái lịch hẹn đi đúng vòng đời?**
CHECK giới hạn tập giá trị; trigger BR-11 kiểm tra chuyển trạng thái hợp lệ (`PENDING → CONFIRMED → IN_PROGRESS → COMPLETED`, và `PENDING/CONFIRMED → CANCELLED`). Demo: kịch bản 4, bước 2.

**Ràng buộc "đúng một trong ba actor" của nhật ký bệnh án?**
Ba khóa ngoại cho phép NULL (`patient_id`, `doctor_id`, `admin_id`) + `CHECK` đúng một cột khác NULL (exclusive arc).

### Bảo mật
**Bệnh án được bảo vệ như thế nào?**
Ba lớp: (1) vai trò MySQL ứng dụng không có `SELECT` trên `medical_record`, `prescription`, `prescription_item`; (2) đọc qua `sp_read_medical_record` kiểm tra quyền trong một chỗ duy nhất (`fn_can_read_record`) rồi **ghi nhật ký trước khi trả dữ liệu**; (3) bảng chứa dữ liệu lâm sàng thuộc tablespace mã hóa AES-256 ở mức lưu trữ (TDE): lệnh `ALTER TABLE ... ENCRYPTION = 'Y'` được thực hiện khi triển khai và ghi trong `docs/traceability_matrix.md`; nói rõ đây là cấu hình triển khai, không phải logic ứng dụng.

**MySQL không biết "người dùng cuối", vậy ai chặn bệnh nhân A gọi thủ tục với id của B?**
Đây là giới hạn đã ghi trong `07_rbac.sql`. Backend xác thực người dùng và **luôn lấy id từ session**, không bao giờ từ request; tầng cơ sở dữ liệu là lớp bảo vệ thứ hai (quyền theo cột, trigger, thủ tục kiểm tra chủ sở hữu). Demo: kịch bản 3. Nói rõ: nếu muốn chặn cả khi backend bị chiếm quyền thì cần mỗi người dùng một tài khoản CSDL hoặc bảng định danh phiên ở phía CSDL.

**Vì sao tài khoản đăng nhập lưu ở SQLite mà không trong schema 17 bảng?**
Để giữ nguyên schema đã thiết kế và đã chuẩn hóa (báo cáo không có bảng thông tin đăng nhập); `auth_store.py` ánh xạ `(role, login) → actor_id`, mật khẩu băm PBKDF2.

**Bệnh nhân đăng ký thế nào mà không có quyền ghi bảng `patient`?**
Qua `sp_register_patient` chạy với quyền DEFINER; `app_patient` chỉ có `EXECUTE`. Có giới hạn tần suất theo IP (10 lượt/giờ).

**Nhật ký có sửa/xóa được không?**
Không: trigger `BEFORE UPDATE/DELETE` trên hai bảng nhật ký báo lỗi; vai trò ứng dụng chỉ có quyền ghi thêm (NFR-04).

### Hiệu năng
**Chứng minh yêu cầu < 200 ms (NFR-03) thế nào?**
Chạy `tests/performance_before_after.sql` và `tests/performance_explain.sql` trên bộ dữ liệu lớn, so sánh kế hoạch `EXPLAIN ANALYZE` trước/sau khi có chỉ mục (kết quả trong `docs/performance.md`).

### Ứng dụng
**Quy tắc nghiệp vụ nằm ở đâu: backend hay CSDL?**
Ở CSDL (trigger là "lời cuối"); backend chỉ dịch thông báo `SQLSTATE 45000` thành tiếng Việt kèm mã quy tắc (`errors.py`), nên lỗi vẫn truy ngược được đến BR/NFR.

## 4. Giới hạn đã biết (nên nói trước khi bị hỏi)
- Đơn thuốc không sửa được sau khi lưu (bác sĩ không có quyền `UPDATE` trên `prescription_item`).
- Chưa có đổi mật khẩu / quên mật khẩu; đăng ký chưa xác minh email.
- Bộ đếm đăng nhập sai và giới hạn đăng ký nằm trong bộ nhớ, mất khi khởi động lại (production nên dùng kho ngoài).
- Chưa có CI; thử nghiệm chạy thủ công trên MySQL thật.
- Hạn chế truy cập theo hàng (row-level) cho bác sĩ do MySQL chỉ có quyền theo cột, nên được kiểm tra thêm ở route (`_own_appointment`, `_my_incoming`).

## 5. Danh sách việc phải làm ngay trước giờ bảo vệ
- [ ] Dựng lại CSDL: `run_all.sql` → `python manage.py seed-accounts` → `python -m pytest -q` (76 passed).
- [ ] Mở sẵn: sơ đồ EER, sơ đồ Crow's Foot, `docs/traceability_matrix.md`, `docs/performance.md`.
- [ ] Mở sẵn 3 profile trình duyệt cho 3 vai trò, đăng nhập sẵn.
- [ ] Mỗi thành viên tự chạy được `sql/run_all.sql` và 2–3 truy vấn trong `sql/queries/` (theo kế hoạch milestone, phần SQL defense chấm cá nhân; kiểm tra lại với đề).
