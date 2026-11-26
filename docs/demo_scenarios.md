# Kịch bản demo trực tiếp (Phase 4)

Thời lượng gợi ý: 12–15 phút. Mỗi kịch bản nêu rõ **thao tác**, **kết quả mong đợi** và **quy tắc / đối tượng CSDL** đứng sau để giải thích khi bị hỏi.

## 0. Chuẩn bị trước giờ demo

```bash
# 1. Dựng CSDL từ đầu (xóa và tạo lại `healthcare`, đã gồm RBAC và thủ tục tự phục vụ FR-01)
cd sql
mysql -u root -p --default-character-set=utf8mb4 -e "source run_all.sql"

# (Nếu CSDL đã có sẵn từ trước: chỉ cần áp bản vá Phase 4)
cd ../backend
python manage.py apply-patch            # hỏi mật khẩu MySQL root, không lưu lại

# 2. Dữ liệu lớn để minh họa hiệu năng (tùy chọn): xem README_SQL.md

# 3. Tài khoản đăng nhập + chạy web
python manage.py seed-accounts
python app.py                           # http://127.0.0.1:5000  (không cần internet: Bootstrap nằm trong static/vendor)

# 4. Kiểm tra nhanh: kỳ vọng 76 passed
python -m pytest -q
```

Mật khẩu mọi tài khoản demo: `Demo#2026`. Mở sẵn **3 cửa sổ trình duyệt (hoặc 3 profile ẩn danh)** cho 3 vai trò để chuyển nhanh.

| Vai trò | Đăng nhập |
|---|---|
| Bệnh nhân A | `an.nguyen@example.com` |
| Bệnh nhân B | `patient2` |
| Bác sĩ đa khoa (GP) | `khoa.tran@clinic.local` |
| Bác sĩ chuyên khoa | `tung.vo@clinic.local` |
| Quản trị hệ thống | `lan.nguyen@clinic.local` |
| Lễ tân (không có quyền đặc biệt) | `trang.le@clinic.local` |

> Dữ liệu seed có thể đã bị thay đổi nếu bạn thử tay trước đó. Trước buổi demo nên dựng lại CSDL và chạy lại `seed-accounts` để các mã số lịch hẹn / yêu cầu hội chẩn dưới đây đúng như mô tả.

---

## Kịch bản 1 — Bệnh nhân tự đăng ký và cập nhật hồ sơ (FR-01)
1. Ở trang đăng nhập bấm **Đăng ký**. Nhập họ tên, ngày sinh, email, mật khẩu ≥ 8 ký tự → **Đăng ký**.
2. Đăng nhập bằng email vừa tạo → menu **Hồ sơ cá nhân** → đổi số điện thoại → **Lưu thay đổi**.
3. Thử xóa cả số điện thoại lẫn email rồi lưu → bị từ chối (cần ít nhất một liên lạc).
4. Thử đăng ký lại bằng chính email đó → báo "đã có tài khoản".

**Giải thích:** thủ tục `sp_register_patient`, `sp_get_my_profile`, `sp_update_my_profile` chạy với quyền DEFINER; tài khoản MySQL `app_patient` chỉ có `EXECUTE`, **không có quyền ghi bảng `patient`**. `patient_id` lấy từ session nên không thể sửa hồ sơ người khác. BR-00 do ràng buộc `ck_patient_contact` bảo đảm.

## Kịch bản 2 — Đặt lịch, chống đặt trùng, hủy lịch (FR-02, FR-03, BR-08, BR-09)
1. Đăng nhập **Bệnh nhân A** → **Đặt lịch khám**: chỉ hiện các ca còn thời gian trống (`v_doctor_availability`).
2. Chọn một ca, giờ trong ca, 30 phút → **Đặt**. Lịch xuất hiện ở **Lịch hẹn** với trạng thái `PENDING`.
3. Đặt lại **đúng khung giờ đó** → bị chặn, thông báo kèm mã **BR-09**.
4. Thử giờ nằm ngoài ca → bị chặn bởi **BR-08**.
5. Hủy lịch vừa đặt.

**Giải thích:** `sp_book_appointment` + trigger kiểm tra trùng khoảng thời gian (không thể diễn đạt bằng UNIQUE đơn thuần, NFR-01), có chỉ mục `(shift_id, start_time)` hỗ trợ.

## Kịch bản 3 — Cách ly dữ liệu bệnh án (NFR-02, NFR-04, BR-20, BR-21)
1. **Bệnh nhân B**: **Lịch sử khám** → ghi lại số hồ sơ (`/patient/records/<id>`).
2. **Bệnh nhân A** gõ thẳng URL hồ sơ đó → bị từ chối, thông báo mã **NFR-02**.
3. **Lễ tân** mở `/admin/records/<id>` → bị từ chối (chưa có `VIEW_ALL_RECORDS`).
4. **Quản trị hệ thống** mở cùng hồ sơ → xem được → vào **Nhật ký** (`/admin/audit`) → thấy dòng `SELECT` vừa ghi.

**Giải thích:** vai trò ứng dụng không có `SELECT` trên `medical_record`; mọi lần đọc đi qua `sp_read_medical_record` (kiểm tra quyền trong `fn_can_read_record` và ghi nhật ký **trước khi** trả dữ liệu). Id người dùng đến từ session, không đến từ request.

## Kịch bản 4 — Bác sĩ khám bệnh, ghi bệnh án và đơn thuốc (FR-06, FR-07, FR-08)
1. **Bác sĩ GP** → **Lịch hẹn**: chuyển lịch `CONFIRMED` sang `IN_PROGRESS` → thành công.
2. Thử chuyển thẳng `CONFIRMED` → `COMPLETED` → bị chặn, mã **BR-11** (không được nhảy bước).
3. Mở một lịch đã `COMPLETED` → **Tạo hồ sơ**: nhập sinh hiệu, chẩn đoán, thêm 2 dòng thuốc → lưu (một giao dịch: hồ sơ + đơn thuốc + chi tiết đơn).
4. Nhập huyết áp tâm trương lớn hơn tâm thu → bị từ chối; thêm cùng một thuốc hai lần → bị từ chối (**BR-16**).
5. Thử mở `…/record/new` của lịch thuộc bác sĩ khác → 404.

**Giải thích:** trigger BR-11/BR-12 (chỉ tạo hồ sơ khi lịch `COMPLETED`), CHECK sinh hiệu, khóa chính ghép `(prescription_id, medication_id)` của `prescription_item`; bác sĩ chỉ ghi đè được các cột lâm sàng, không `SELECT` nội dung bệnh án.

## Kịch bản 5 — Hội chẩn và truy cập theo từng ca (FR-09 → FR-11, BR-21 → BR-23)
1. **Bác sĩ GP** mở hồ sơ của mình → **Mời hội chẩn** → chọn bác sĩ chuyên khoa + lý do.
2. **Bác sĩ chuyên khoa** → **Hội chẩn**: thấy yêu cầu `PENDING` → **Duyệt** (kèm số giờ hiệu lực) → mở hồ sơ ở chế độ chỉ đọc.
3. Cùng bác sĩ chuyên khoa thử mở hồ sơ **không** thuộc yêu cầu nào → bị từ chối (BR-21).
4. Bác sĩ chuyên khoa gửi **ý kiến** → trạng thái `COMPLETED`, quyền truy cập kết thúc.
5. Bác sĩ không phải bên liên quan mở trang chi tiết yêu cầu → bị từ chối (BR-22).

**Giải thích:** `CONSULTATION_REQUEST` là quan hệ tạm thời theo từng ca; quyền đọc chỉ có khi `status = 'APPROVED'` và chưa hết hạn.

## Kịch bản 6 — Quản trị: phân quyền, tạo bác sĩ, ca làm, lương (FR-12 → FR-14, BR-01, BR-03, BR-20, BR-24)
1. **Lễ tân** thử mở **Phân quyền**, **Nhật ký**, **Thuốc**, **Thêm bác sĩ** → đều bị 403.
2. **Quản trị hệ thống** → **Thêm bác sĩ** (loại GP, toàn thời gian) → hệ thống tạo `doctor` → `gp` → kích hoạt đúng thứ tự (BR-01).
3. **Bác sĩ GP** đăng ký ca **không chọn phòng** → bị chặn **BR-03**; chọn phòng từ danh sách → thành công.
4. **Quản trị** → **Phân quyền**: cấp một quyền cho lễ tân; lễ tân không thể tự cấp quyền (BR-20).
5. **Lương part-time** (`v_part_time_pay`) → xem giờ làm × đơn giá theo ca (BR-24).

## Kịch bản 7 — Danh mục thuốc và nhật ký bất biến (BR-19, BR-25)
1. **Quản trị** → **Thuốc**: thêm thuốc, sửa tên, **ngừng sử dụng** (không xóa được).
2. **Nhật ký** → tab thuốc: thấy các dòng `CREATE`, `UPDATE`, `DEACTIVATE` kèm quản trị viên thực hiện.

**Giải thích:** vai trò quản trị không có `DELETE`; hai bảng nhật ký chặn UPDATE/DELETE bằng trigger.

---

## Phương án dự phòng khi demo gặp sự cố
- **Không vào được web:** chạy `python -m pytest -q` để chứng minh các luồng vẫn đúng, hoặc chạy `tests/run_all_tests.sql` (kỳ vọng 67/67 PASS).
- **Quên mật khẩu / tài khoản khóa 5 phút:** chạy lại `python manage.py seed-accounts` và khởi động lại `app.py` (bộ đếm đăng nhập sai nằm trong bộ nhớ).
- **Sai dữ liệu seed:** dựng lại CSDL bằng `run_all.sql` rồi `seed-accounts`.
