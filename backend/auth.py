"""Login / logout, session handling and the access decorators used by every portal."""
import time
from functools import wraps

from flask import (Blueprint, abort, flash, g, redirect, render_template, request,
                   session, url_for)

import auth_store
from datetime import date

from flask import current_app

from db import Db, get_db
from errors import UserError
from utils import parse_date, text

bp = Blueprint("auth", __name__)

HOME = {"patient": "patient.home", "doctor": "doctor.home", "admin": "admin.home"}

# naive in-memory brute-force guard: 5 failures per (ip, role, login) -> 5 minute lock
_FAILS = {}
_MAX_FAILS, _LOCK_SECONDS = 5, 300


def _locked(key):
    fails, since = _FAILS.get(key, (0, 0))
    if fails >= _MAX_FAILS and time.time() - since < _LOCK_SECONDS:
        return True
    if fails >= _MAX_FAILS:
        _FAILS.pop(key, None)
    return False


@bp.route("/login", methods=["GET", "POST"])
def login():
    if session.get("uid"):
        return redirect(url_for(HOME[session["role"]]))
    if request.method == "POST":
        role = request.form.get("role", "")
        login_id = request.form.get("login", "")
        key = (request.remote_addr, role, login_id.strip().lower())
        if role not in auth_store.ROLES:
            flash("Vai trò không hợp lệ.", "danger")
        elif _locked(key):
            flash("Đăng nhập sai quá nhiều lần. Vui lòng thử lại sau 5 phút.", "danger")
        else:
            acc = auth_store.verify(role, login_id, request.form.get("password", ""))
            if acc:
                _FAILS.pop(key, None)
                session.clear()
                session.permanent = True
                session.update(uid=acc["actor_id"], role=acc["role"], name=acc["display_name"],
                               meta=auth_store.meta_of(acc))
                return redirect(url_for(HOME[acc["role"]]))
            fails, _ = _FAILS.get(key, (0, 0))
            _FAILS[key] = (fails + 1, time.time())
            flash("Sai tên đăng nhập hoặc mật khẩu.", "danger")
    return render_template("login.html")


@bp.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))


# ---------------------------------------------------------------- FR-01: patient self-registration
# in-memory throttle: at most REGISTER_MAX_PER_HOUR sign-ups per IP address per hour
_REGISTRATIONS = {}


def _register_throttled():
    now = time.time()
    hits = [t for t in _REGISTRATIONS.get(request.remote_addr, []) if now - t < 3600]
    _REGISTRATIONS[request.remote_addr] = hits
    return len(hits) >= current_app.config.get("REGISTER_MAX_PER_HOUR", 10)


def parse_registration(form):
    """Validate the sign-up form. Returns (profile values, email, password) or raises UserError."""
    full_name = text(form, "full_name", True, "họ tên", 100)
    dob = parse_date(form.get("dob"), "ngày sinh")
    if dob > date.today():
        raise UserError("Ngày sinh không được ở tương lai.")
    email = (text(form, "email", True, "email", 120) or "").lower()
    if "@" not in email or "." not in email.rsplit("@", 1)[-1]:
        raise UserError("Email không hợp lệ.")
    password = form.get("password") or ""
    if len(password) < 8:
        raise UserError("Mật khẩu phải có ít nhất 8 ký tự.")
    if password != (form.get("password2") or ""):
        raise UserError("Mật khẩu nhập lại không khớp.")
    phone, address = text(form, "phone", max_len=20, label="số điện thoại"), text(form, "address")
    return (full_name, dob, phone, email, address), email, password


@bp.route("/register", methods=["GET", "POST"])
def register():
    """Patients create their own profile (FR-01). The e-mail becomes the login name."""
    if session.get("uid"):
        return redirect(url_for(HOME[session["role"]]))
    if request.method == "POST":
        try:
            if _register_throttled():
                raise UserError("Quá nhiều lượt đăng ký từ địa chỉ này. Vui lòng thử lại sau.")
            values, email, password = parse_registration(request.form)
            if auth_store.login_exists("patient", email):
                raise UserError("Email này đã có tài khoản. Hãy đăng nhập hoặc dùng email khác.")
            db = Db("patient", config=current_app.config)      # app_patient: EXECUTE on the routines only
            try:
                pid = db.call("sp_register_patient", *values)[0][0]["patient_id"]
                db.commit()
            finally:
                db.close()
            auth_store.upsert_account("patient", pid, email, password, values[0])
            _REGISTRATIONS.setdefault(request.remote_addr, []).append(time.time())
            flash("Đăng ký thành công. Bạn có thể đăng nhập bằng email vừa dùng.", "success")
            return redirect(url_for("auth.login"))
        except UserError as exc:
            flash(str(exc), "danger")
    return render_template("register.html")


def role_required(role, perm=None):
    """Only a logged-in user with this role (and, for admins, this permission) gets in."""
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not session.get("uid"):
                return redirect(url_for("auth.login"))
            if session.get("role") != role:
                abort(403)
            if role == "admin" and not admin_profile()["active"]:
                session.clear()
                flash("Tài khoản quản trị đã bị vô hiệu hóa.", "danger")
                return redirect(url_for("auth.login"))
            if perm and not has_perm(perm):
                abort(403)
            return view(*args, **kwargs)
        return wrapped
    return decorator


def admin_profile():
    """Admin role (RECEPTIONIST / SYSTEM_ADMIN) and permission codes, read fresh from the DB."""
    if "admin_profile" not in g:
        db = get_db()
        row = db.one("SELECT role, is_active FROM admin WHERE admin_id = %s", (session["uid"],))
        perms = {r["permission_code"] for r in db.all(
            "SELECT permission_code FROM staff_permission WHERE admin_id = %s", (session["uid"],))}
        g.admin_profile = {"role": row["role"] if row else None,
                           "active": bool(row and row["is_active"]), "perms": perms}
    return g.admin_profile


def has_perm(code):
    return session.get("role") == "admin" and code in admin_profile()["perms"]


def is_system_admin():
    return session.get("role") == "admin" and admin_profile()["role"] == "SYSTEM_ADMIN"


def init_app(app):
    @app.context_processor
    def inject_user():
        ctx = {"user": {"name": session.get("name"), "role": session.get("role"),
                        "id": session.get("uid")} if session.get("uid") else None}
        if session.get("role") == "admin":
            prof = admin_profile()
            ctx.update(perms=prof["perms"], admin_role=prof["role"])
        return ctx
