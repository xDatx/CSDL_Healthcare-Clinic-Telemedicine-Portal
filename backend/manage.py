"""Management commands.

  python manage.py seed-accounts [--patients N] [--password PW]
      Create login accounts for the people already in the database (demo / first setup):
      every admin, every active doctor and the first N patients. Re-running resets their password.

  python manage.py list-accounts
"""
import argparse
import getpass
import sqlite3
from pathlib import Path

import pymysql

import auth_store
from config import Config
from db import Db

DEFAULT_PASSWORD = "Demo#2026"


def seed_accounts(patients, password):
    cfg = {"DB_HOST": Config.DB_HOST, "DB_PORT": Config.DB_PORT, "DB_NAME": Config.DB_NAME,
           "DB_PASSWORDS": Config.DB_PASSWORDS}
    db = Db("admin", config=cfg)
    try:
        rows = []
        for a in db.all("SELECT admin_id, full_name, email, role FROM admin WHERE is_active = TRUE"):
            rows.append(("admin", a["admin_id"], a["email"], a["full_name"], {"role": a["role"]}))
        for d in db.all("SELECT doctor_id, full_name, email, spec_type, employment_type FROM doctor "
                        "WHERE is_active = TRUE"):
            rows.append(("doctor", d["doctor_id"], d["email"], d["full_name"],
                         {"spec_type": d["spec_type"], "employment_type": d["employment_type"]}))
        for p in db.all("SELECT patient_id, full_name, email FROM patient ORDER BY patient_id LIMIT %s", (patients,)):
            rows.append(("patient", p["patient_id"], p["email"] or f"patient{p['patient_id']}", p["full_name"], {}))
    finally:
        db.close()

    for role, actor_id, login, name, meta in rows:
        auth_store.upsert_account(role, actor_id, login, password, name, meta, path=Config.AUTH_DB)
    print(f"Created/updated {len(rows)} accounts in {Config.AUTH_DB}")
    print(f"Password for all of them: {password}")


def split_statements(script):
    """Split a mysql-client style script (with DELIMITER lines) into single statements."""
    delim, buf, out = ";", [], []
    for line in script.splitlines():
        stripped = line.strip()
        if stripped.upper().startswith("DELIMITER "):
            delim = stripped.split(None, 1)[1]
            continue
        if not buf and (not stripped or stripped.startswith("--")):
            continue
        buf.append(line)
        if stripped.endswith(delim):
            stmt = "\n".join(buf).rstrip()
            out.append(stmt[: -len(delim)].rstrip())
            buf = []
    if buf and "\n".join(buf).strip():
        out.append("\n".join(buf).strip())
    return [s for s in out if s]


PATCH_GRANTS = [
    "GRANT EXECUTE ON PROCEDURE healthcare.sp_register_patient  TO 'r_patient'",
    "GRANT EXECUTE ON PROCEDURE healthcare.sp_get_my_profile    TO 'r_patient'",
    "GRANT EXECUTE ON PROCEDURE healthcare.sp_update_my_profile TO 'r_patient'",
    "GRANT SELECT ON healthcare.room TO 'r_doctor'",
    "FLUSH PRIVILEGES",
]


def apply_patch(user):
    """Apply sql/08_phase4_patch.sql to the existing database (needs an account that may CREATE ROUTINE / GRANT)."""
    sql_file = Path(__file__).resolve().parent.parent / "sql" / "procedures" / "sp_patient_self_service.sql"
    statements = split_statements(sql_file.read_text(encoding="utf-8")) + PATCH_GRANTS
    password = getpass.getpass(f"MySQL password for {user}@{Config.DB_HOST}: ")
    conn = pymysql.connect(host=Config.DB_HOST, port=Config.DB_PORT, user=user, password=password,
                           charset="utf8mb4", autocommit=True)
    try:
        with conn.cursor() as cur:
            for stmt in statements:
                cur.execute(stmt)
    finally:
        conn.close()
    print(f"Applied {len(statements)} statements (procedures + grants). Now run: python -m pytest -q")


def list_accounts():
    conn = sqlite3.connect(Config.AUTH_DB)
    for role, actor_id, login, name, active in conn.execute(
            "SELECT role, actor_id, login, display_name, is_active FROM account ORDER BY role, actor_id"):
        print(f"{role:8} #{actor_id:<6} {login:32} {name}{'' if active else '  [disabled]'}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seed-accounts")
    s.add_argument("--patients", type=int, default=30, help="how many patients get an account (default 30)")
    s.add_argument("--password", default=DEFAULT_PASSWORD)
    sub.add_parser("list-accounts")
    p = sub.add_parser("apply-patch", help="apply the Phase 4 SQL changes (self-service procedures + grants)")
    p.add_argument("--user", default="root", help="MySQL account allowed to CREATE ROUTINE / GRANT (default root)")
    args = ap.parse_args()
    if args.cmd == "seed-accounts":
        seed_accounts(args.patients, args.password)
    elif args.cmd == "apply-patch":
        apply_patch(args.user)
    else:
        list_accounts()
