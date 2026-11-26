"""Backend configuration. Values come from backend/.env (see .env.example)."""
import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")


class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-only-change-me")
    PERMANENT_SESSION_LIFETIME = timedelta(hours=2)
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "0") == "1"

    DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
    DB_PORT = int(os.getenv("DB_PORT", "3306"))
    DB_NAME = os.getenv("DB_NAME", "healthcare")
    # One MySQL account per application role (least privilege, see sql/07_rbac.sql).
    # The defaults are the demo placeholders of 07_rbac.sql; override them in .env.
    DB_PASSWORDS = {
        "patient": os.getenv("DB_PASS_PATIENT", "Patient#2026"),
        "doctor": os.getenv("DB_PASS_DOCTOR", "Doctor#2026"),
        "admin": os.getenv("DB_PASS_ADMIN", "Admin#2026"),
    }

    # Application accounts (login + password hash) live outside the clinical schema.
    AUTH_DB = os.getenv("AUTH_DB", str(BASE_DIR / "instance" / "auth.db"))
    PAGE_SIZE = 25
