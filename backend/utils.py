"""Small helpers: Jinja filters, form parsing, pagination, safe redirects."""
from datetime import date, datetime, time, timedelta
from decimal import Decimal, InvalidOperation

from flask import redirect, request, url_for

from errors import UserError


# ---------------------------------------------------------------- Jinja filters
def hm(v):
    """TIME (timedelta from PyMySQL) / time / datetime -> HH:MM"""
    if v is None:
        return ""
    if isinstance(v, timedelta):
        s = int(v.total_seconds())
        return f"{s // 3600:02d}:{s % 3600 // 60:02d}"
    if isinstance(v, (time, datetime)):
        return v.strftime("%H:%M")
    return str(v)


def dmy(v):
    if v is None:
        return ""
    if isinstance(v, datetime):
        return v.strftime("%d/%m/%Y")
    if isinstance(v, date):
        return v.strftime("%d/%m/%Y")
    return str(v)


def dmyhm(v):
    return v.strftime("%d/%m/%Y %H:%M") if isinstance(v, datetime) else ("" if v is None else str(v))


def money(v):
    if v is None:
        return ""
    return f"{int(Decimal(v)):,}".replace(",", ".") + " ₫"


def register_filters(app):
    app.jinja_env.filters.update(hm=hm, dmy=dmy, dmyhm=dmyhm, money=money)


# ---------------------------------------------------------------- form parsing
def text(form, key, required=False, label=None, max_len=None):
    val = (form.get(key) or "").strip()
    if required and not val:
        raise UserError(f"Vui lòng nhập {label or key}.")
    if max_len and len(val) > max_len:
        raise UserError(f"{label or key} tối đa {max_len} ký tự.")
    return val or None


def integer(form, key, label=None, required=True, lo=None, hi=None):
    raw = (form.get(key) or "").strip()
    if not raw:
        if required:
            raise UserError(f"Vui lòng nhập {label or key}.")
        return None
    try:
        val = int(raw)
    except ValueError:
        raise UserError(f"{label or key} phải là số nguyên.")
    if (lo is not None and val < lo) or (hi is not None and val > hi):
        raise UserError(f"{label or key} phải nằm trong khoảng {lo}–{hi}.")
    return val


def decimal(form, key, label=None, required=True, lo=None, hi=None):
    raw = (form.get(key) or "").strip().replace(",", ".")
    if not raw:
        if required:
            raise UserError(f"Vui lòng nhập {label or key}.")
        return None
    try:
        val = Decimal(raw)
    except InvalidOperation:
        raise UserError(f"{label or key} phải là số.")
    if (lo is not None and val < lo) or (hi is not None and val > hi):
        raise UserError(f"{label or key} phải nằm trong khoảng {lo}–{hi}.")
    return val


def parse_date(raw, label="ngày"):
    try:
        return datetime.strptime((raw or "").strip(), "%Y-%m-%d").date()
    except ValueError:
        raise UserError(f"{label.capitalize()} không hợp lệ.")


def parse_time(raw, label="giờ"):
    raw = (raw or "").strip()
    for fmt in ("%H:%M", "%H:%M:%S"):
        try:
            return datetime.strptime(raw, fmt).time()
        except ValueError:
            continue
    raise UserError(f"{label.capitalize()} không hợp lệ.")


def choice(form, key, allowed, label=None):
    val = (form.get(key) or "").strip()
    if val not in allowed:
        raise UserError(f"{label or key} không hợp lệ.")
    return val


# ---------------------------------------------------------------- navigation
def safe_next(default_endpoint, **values):
    """Redirect to the 'next' form field if it is a local path, otherwise to the default page."""
    nxt = request.form.get("next") or request.args.get("next") or ""
    if nxt.startswith("/") and not nxt.startswith("//"):
        return redirect(nxt)
    return redirect(url_for(default_endpoint, **values))


# ---------------------------------------------------------------- pagination
def paginate(db, select_sql, count_sql, args, page, per_page):
    """select_sql must not contain LIMIT. Returns rows plus paging info."""
    total = db.scalar(count_sql, args) or 0
    pages = max(1, -(-total // per_page))
    page = min(max(page, 1), pages)
    rows = db.all(f"{select_sql} LIMIT %s OFFSET %s", (*args, per_page, (page - 1) * per_page))
    return {"rows": rows, "total": total, "page": page, "pages": pages}


def page_arg():
    try:
        return max(1, int(request.args.get("page", 1)))
    except ValueError:
        return 1
