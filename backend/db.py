"""Per-request MySQL access.

One connection per request, opened with the MySQL account that matches the logged-in role
(app_patient / app_doctor / app_admin). The audit context expected by the triggers
(@app_actor_type / @app_actor_id, see trg_appointment_audit.sql and
trg_medication_consultation.sql) is set right after connecting.

Connections run with autocommit OFF: a route must call db.commit() after any write.
Anything left uncommitted is rolled back when the request ends.
"""
import re

import pymysql
from flask import current_app, g, session
from pymysql.cursors import DictCursor

ROLE_USER = {"patient": "app_patient", "doctor": "app_doctor", "admin": "app_admin"}
_PROC_NAME = re.compile(r"^[a-z_][a-z0-9_]*$")


class Db:
    def __init__(self, role, actor_id=None, config=None):
        cfg = config or current_app.config
        self.role = role
        self.rowcount = 0
        self.conn = pymysql.connect(
            host=cfg["DB_HOST"], port=cfg["DB_PORT"], database=cfg["DB_NAME"],
            user=ROLE_USER[role], password=cfg["DB_PASSWORDS"][role],
            charset="utf8mb4", cursorclass=DictCursor, autocommit=False, connect_timeout=5,
        )
        if actor_id is not None:
            self.execute("SET @app_actor_type = %s, @app_actor_id = %s", (role.upper(), actor_id))

    # ---- reads
    def all(self, sql, args=()):
        with self.conn.cursor() as cur:
            cur.execute(sql, args)
            return list(cur.fetchall())

    def one(self, sql, args=()):
        rows = self.all(sql, args)
        return rows[0] if rows else None

    def scalar(self, sql, args=()):
        row = self.one(sql, args)
        return next(iter(row.values())) if row else None

    # ---- writes
    def execute(self, sql, args=()):
        """Run one statement. Returns lastrowid; affected rows are in self.rowcount."""
        with self.conn.cursor() as cur:
            cur.execute(sql, args)
            self.rowcount = cur.rowcount
            return cur.lastrowid

    def call(self, proc, *args):
        """CALL a stored procedure. Returns every result set as a list of dict rows."""
        if not _PROC_NAME.match(proc):
            raise ValueError(f"bad procedure name: {proc!r}")
        marks = ", ".join(["%s"] * len(args))
        sets = []
        with self.conn.cursor() as cur:
            cur.execute(f"CALL {proc}({marks})", args)
            while True:
                if cur.description:
                    sets.append(list(cur.fetchall()))
                if not cur.nextset():
                    break
        return sets

    def commit(self):
        self.conn.commit()

    def rollback(self):
        try:
            self.conn.rollback()
        except pymysql.MySQLError:
            pass

    def close(self):
        self.rollback()
        try:
            self.conn.close()
        except pymysql.MySQLError:
            pass


def get_db():
    """The request-scoped connection of the logged-in user."""
    if "db" not in g:
        g.db = Db(session["role"], session["uid"])
    return g.db


def init_app(app):
    @app.teardown_appcontext
    def _close_db(_exc):
        db = g.pop("db", None)
        if db is not None:
            db.close()
