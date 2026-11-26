"""Application accounts (who may log in) kept in a small SQLite file, separate from the clinic schema.

The MySQL schema has no credentials, and the 17-table design stays untouched. This store maps
a login to (role, actor_id); the actor_id is then passed to the stored procedures as the
AUTHENTICATED user (see 07_rbac.sql, "Trust model").
"""
import json
import secrets
import sqlite3
from pathlib import Path

from flask import current_app
from werkzeug.security import check_password_hash, generate_password_hash

ROLES = ("patient", "doctor", "admin")
_SCHEMA = """
CREATE TABLE IF NOT EXISTS account (
    account_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    role          TEXT    NOT NULL CHECK (role IN ('patient','doctor','admin')),
    actor_id      INTEGER NOT NULL,
    login         TEXT    NOT NULL,
    password_hash TEXT    NOT NULL,
    display_name  TEXT    NOT NULL,
    meta          TEXT    NOT NULL DEFAULT '{}',
    is_active     INTEGER NOT NULL DEFAULT 1,
    UNIQUE (role, login),
    UNIQUE (role, actor_id)
);
"""
_DUMMY_HASH = generate_password_hash("not-a-real-password", method="pbkdf2:sha256")


def _connect(path=None):
    path = Path(path or current_app.config["AUTH_DB"])
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.executescript(_SCHEMA)
    return conn


def random_password():
    return secrets.token_urlsafe(8)


def upsert_account(role, actor_id, login, password, display_name, meta=None, path=None):
    """Create the account, or reset login/password/name if (role, actor_id) already exists.
    If the login is already taken by someone else (e.g. a parent and child sharing one email),
    fall back to '<role><id>'. Returns the login that was stored."""
    assert role in ROLES
    login = login.strip().lower()
    h = generate_password_hash(password, method="pbkdf2:sha256")
    with _connect(path) as c:
        taken = c.execute("SELECT actor_id FROM account WHERE role = ? AND login = ?", (role, login)).fetchone()
        if taken and taken["actor_id"] != actor_id:
            login = f"{role}{actor_id}"
        c.execute(
            """INSERT INTO account (role, actor_id, login, password_hash, display_name, meta)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT (role, actor_id) DO UPDATE SET
                 login = excluded.login, password_hash = excluded.password_hash,
                 display_name = excluded.display_name, meta = excluded.meta, is_active = 1""",
            (role, actor_id, login, h, display_name, json.dumps(meta or {})),
        )
    return login


def verify(role, login, password):
    """Return the account row if the credentials are valid, else None (constant-ish time)."""
    with _connect() as c:
        row = c.execute(
            "SELECT * FROM account WHERE role = ? AND login = ? AND is_active = 1",
            (role, (login or "").strip().lower()),
        ).fetchone()
    ok = check_password_hash(row["password_hash"] if row else _DUMMY_HASH, password or "")
    return row if (row and ok) else None


def set_active(role, actor_id, active):
    with _connect() as c:
        c.execute("UPDATE account SET is_active = ? WHERE role = ? AND actor_id = ?",
                  (1 if active else 0, role, actor_id))


def login_exists(role, login):
    """True if this login is already used by an account of the role (any state)."""
    with _connect() as c:
        return c.execute("SELECT 1 FROM account WHERE role = ? AND login = ?",
                         (role, (login or "").strip().lower())).fetchone() is not None


def set_display_name(role, actor_id, name):
    with _connect() as c:
        c.execute("UPDATE account SET display_name = ? WHERE role = ? AND actor_id = ?",
                  (name, role, actor_id))


def update_meta(role, actor_id, **fields):
    with _connect() as c:
        row = c.execute("SELECT meta FROM account WHERE role = ? AND actor_id = ?",
                        (role, actor_id)).fetchone()
        if row:
            meta = json.loads(row["meta"])
            meta.update(fields)
            c.execute("UPDATE account SET meta = ? WHERE role = ? AND actor_id = ?",
                      (json.dumps(meta), role, actor_id))


def meta_of(row):
    return json.loads(row["meta"]) if row else {}


def count():
    with _connect() as c:
        return c.execute("SELECT COUNT(*) FROM account").fetchone()[0]
