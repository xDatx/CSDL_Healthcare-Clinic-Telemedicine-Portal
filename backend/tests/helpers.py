PASSWORD = "Demo#2026"  # set by `python manage.py seed-accounts`


def make_client(app, role, login):
    client = app.test_client()
    resp = client.post("/login", data={"role": role, "login": login, "password": PASSWORD})
    assert resp.status_code == 302, f"login failed for {role}/{login}"
    return client


def text(resp):
    return resp.get_data(as_text=True)
