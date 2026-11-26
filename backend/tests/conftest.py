"""Shared fixtures for the integration tests (real MySQL + `python manage.py seed-accounts`)."""
import pytest

from app import create_app
from helpers import make_client


@pytest.fixture(scope="session")
def app():
    return create_app({"TESTING": True, "WTF_CSRF_ENABLED": False})


@pytest.fixture()
def anon(app):
    return app.test_client()


@pytest.fixture()
def patient1(app):
    return make_client(app, "patient", "an.nguyen@example.com")


@pytest.fixture()
def patient2(app):
    return make_client(app, "patient", "patient2")


@pytest.fixture()
def doctor1(app):
    return make_client(app, "doctor", "khoa.tran@clinic.local")


@pytest.fixture()
def doctor4(app):
    return make_client(app, "doctor", "tung.vo@clinic.local")


@pytest.fixture()
def sysadmin(app):
    return make_client(app, "admin", "lan.nguyen@clinic.local")


@pytest.fixture()
def receptionist(app):
    return make_client(app, "admin", "trang.le@clinic.local")
