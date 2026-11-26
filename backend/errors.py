"""Turn database errors (triggers, constraints, privileges) into messages a user can read.

Every business-rule trigger rejects with SQLSTATE 45000 and a message that starts with the rule id
(e.g. 'BR-09: overlapping appointment in shift'). We keep that id in the output so a demo audience
(and the SQL defense) can see which rule fired.
"""
import re

import pymysql


class UserError(Exception):
    """A validation problem detected by the backend itself."""


# (substring of the trigger message, Vietnamese explanation) - first match wins
_RULES = [
    ("FR-01: patient not found", "Không tìm thấy hồ sơ bệnh nhân."),
    ("BR-01: a new doctor must start inactive", "Bác sĩ mới phải ở trạng thái chưa kích hoạt cho đến khi có hồ sơ GP/Chuyên khoa."),
    ("BR-01: cannot activate", "Chỉ kích hoạt bác sĩ khi đã có đúng một hồ sơ GP hoặc Chuyên khoa."),
    ("BR-01: appointments cannot be assigned", "Bác sĩ đã ngừng hoạt động nên không nhận lịch hẹn."),
    ("BR-01: only an active doctor", "Chỉ bác sĩ đang hoạt động mới đăng ký được ca."),
    ("BR-01: deactivate the doctor", "Hãy ngừng hoạt động bác sĩ trước khi gỡ hồ sơ GP/Chuyên khoa."),
    ("BR-03: GP shift requires", "Ca của bác sĩ đa khoa (GP) bắt buộc chọn phòng."),
    ("BR-03: GP room double-booked", "Phòng này đã có ca khác trong khung giờ đó."),
    ("BR-04", "Không tìm thấy bác sĩ."),
    ("BR-05", "Bác sĩ đã có một ca khác trùng giờ."),
    ("BR-06", "Không tìm thấy lịch hẹn."),
    ("BR-07", "Lịch hẹn phải thuộc một ca khám hợp lệ."),
    ("BR-08: shift is not ACTIVE", "Ca khám này đã bị hủy."),
    ("BR-08: appointment must be on shift date", "Lịch hẹn phải nằm trong ngày của ca khám."),
    ("BR-08: appointment outside shift hours", "Giờ hẹn nằm ngoài giờ làm việc của ca."),
    ("BR-08: shift change", "Không thể đổi ca vì còn lịch hẹn nằm ngoài khung giờ mới."),
    ("BR-09", "Khung giờ này đã có lịch hẹn khác. Hãy chọn giờ khác."),
    ("BR-11: invalid status transition", "Không thể chuyển lịch hẹn sang trạng thái này."),
    ("BR-11: a new appointment", "Lịch hẹn mới phải bắt đầu ở trạng thái PENDING."),
    ("BR-11: a COMPLETED or CANCELLED", "Lịch hẹn đã hoàn tất hoặc đã hủy thì không thể dời."),
    ("BR-12: medical record requires", "Chỉ tạo hồ sơ khi lịch hẹn đã hoàn tất (COMPLETED)."),
    ("BR-12", "Không được chuyển hồ sơ sang lịch hẹn khác."),
    ("BR-19", "Thuốc không bị xóa; hãy ngừng sử dụng (is_active = 0)."),
    ("BR-20: only SYSTEM_ADMIN", "Chỉ SYSTEM_ADMIN mới được cấp quyền."),
    ("BR-20: the granting admin", "Người cấp phải đang nắm giữ quyền này."),
    ("BR-22: consulting doctor", "Bác sĩ được mời phải đang hoạt động."),
    ("BR-22: invalid consultation", "Không thể chuyển yêu cầu hội chẩn sang trạng thái này."),
    ("BR-22: the access window", "Thời hạn truy cập hồ sơ của yêu cầu này đã hết."),
    ("BR-22: access denied", "Bạn không phải bên tham gia yêu cầu hội chẩn này."),
    ("BR-22: consultation request not found", "Không tìm thấy yêu cầu hội chẩn."),
    ("BR-22: a new consultation", "Yêu cầu hội chẩn mới phải ở trạng thái PENDING."),
    ("BR-23: requesting doctor", "Chỉ bác sĩ điều trị của hồ sơ mới được gửi yêu cầu hội chẩn."),
    ("BR-23", "Không được sửa hồ sơ, bác sĩ hoặc lý do của yêu cầu hội chẩn."),
    ("BR-24: PART_TIME", "Bác sĩ part-time phải có đơn giá theo giờ (rate_per_hour)."),
    ("BR-24: FULL_TIME", "Bác sĩ full-time không được khai đơn giá theo giờ."),
    ("BR-25", "Thiếu thông tin người thao tác với danh mục thuốc."),
    ("BR-26", "Ca của bác sĩ chuyên khoa không được gán phòng."),
    ("NFR-02: access denied", "Bạn không có quyền xem hồ sơ bệnh án này."),
    ("NFR-02: cannot cancel", "Bạn không thể hủy lịch hẹn của người khác."),
    ("NFR-02: medical record not found", "Không tìm thấy hồ sơ bệnh án."),
    ("NFR-04", "Nhật ký và hồ sơ bệnh án không được xóa hoặc sửa theo cách này."),
    ("FR-04", "Không tìm thấy bệnh nhân."),
]

_CHECK = re.compile(r"Check constraint '(\w+)'")


def explain(exc):
    """Human readable text for a UserError or a pymysql error."""
    if isinstance(exc, UserError):
        return str(exc)
    code = exc.args[0] if exc.args and isinstance(exc.args[0], int) else None
    msg = str(exc.args[1]) if len(exc.args) > 1 else str(exc)

    if code == 1644:  # SIGNAL SQLSTATE '45000' from a trigger / procedure
        rule = msg.split(":")[0].strip()
        for needle, vi in _RULES:
            if needle in msg:
                return f"{vi} [{rule}]"
        return msg
    if code in (1142, 1143, 1370, 1044, 1045):
        return "Bạn không có quyền thực hiện thao tác này (bị chặn bởi phân quyền MySQL)."
    if code == 3819:
        m = _CHECK.search(msg)
        return f"Giá trị không thỏa ràng buộc dữ liệu ({m.group(1) if m else 'CHECK'})."
    if code == 1062:
        return "Dữ liệu bị trùng với bản ghi đã có (email, mã giấy phép hoặc khóa duy nhất)."
    if code in (1451, 1452):
        return "Tham chiếu không hợp lệ: bản ghi liên quan không tồn tại hoặc đang được sử dụng."
    if code in (1048, 1364):
        return "Thiếu giá trị bắt buộc."
    if code in (1406, 1264, 1292, 1366):
        return "Giá trị nhập vào không hợp lệ hoặc quá dài."
    if code in (2002, 2003, 2006, 2013):
        return "Không kết nối được tới cơ sở dữ liệu. Hãy kiểm tra MySQL đang chạy."
    return f"Lỗi cơ sở dữ liệu ({code}): {msg}"


def is_permission_error(exc):
    return isinstance(exc, pymysql.MySQLError) and exc.args and exc.args[0] in (1142, 1143, 1370)
