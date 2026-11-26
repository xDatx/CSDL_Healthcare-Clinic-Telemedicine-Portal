"""Telemedicine Portal & Clinical Management - Flask backend (Phase 4).

Run:   python app.py          (or: flask --app app run)
Setup: see backend/README.md
"""
import pymysql
from flask import Flask, flash, redirect, render_template, request, session, url_for
from flask_wtf.csrf import CSRFError, CSRFProtect

import auth
import db
from config import Config
from errors import UserError, explain, is_permission_error
from utils import register_filters

csrf = CSRFProtect()


def create_app(test_config=None):
    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config:
        app.config.update(test_config)

    csrf.init_app(app)
    register_filters(app)
    db.init_app(app)
    auth.init_app(app)

    from blueprints import admin, doctor, patient
    app.register_blueprint(auth.bp)
    app.register_blueprint(patient.bp)
    app.register_blueprint(doctor.bp)
    app.register_blueprint(admin.bp)

    @app.route("/")
    def index():
        if session.get("uid"):
            return redirect(url_for(auth.HOME[session["role"]]))
        return redirect(url_for("auth.login"))

    # ---- one place that turns rule violations into readable messages
    def back_with_error(message):
        flash(message, "danger")
        if request.method == "POST":
            target = request.referrer or url_for("index")
            return redirect(target)
        return render_template("error.html", code=400, message=message), 400

    @app.errorhandler(UserError)
    def handle_user_error(exc):
        return back_with_error(str(exc))

    @app.errorhandler(pymysql.MySQLError)
    def handle_db_error(exc):
        app.logger.warning("database error: %s", exc)
        if is_permission_error(exc) and request.method == "GET":
            return render_template("error.html", code=403, message=explain(exc)), 403
        return back_with_error(explain(exc))

    @app.errorhandler(CSRFError)
    def handle_csrf(_exc):
        flash("Phiên làm việc của biểu mẫu đã hết hạn. Vui lòng thử lại.", "warning")
        return redirect(request.referrer or url_for("index"))

    @app.errorhandler(403)
    def forbidden(_e):
        return render_template("error.html", code=403,
                               message="Bạn không có quyền truy cập trang này."), 403

    @app.errorhandler(404)
    def not_found(_e):
        return render_template("error.html", code=404, message="Không tìm thấy trang yêu cầu."), 404

    @app.errorhandler(500)
    def server_error(_e):
        return render_template("error.html", code=500, message="Đã xảy ra lỗi hệ thống."), 500

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)
