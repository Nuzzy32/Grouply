#!/usr/bin/env python3
"""Set up and exercise only this project's local Supabase, without logging credentials."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT_FILE = Path.home() / "Library/Application Support/GrouplyDevelopment/accounts.json"


def local_status():
    result = subprocess.run(["supabase", "status", "-o", "json"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Supabase Grouply lokal belum berjalan. Jalankan perintah start pada docs/BACKEND_SETUP.md.")
    status = json.loads(result.stdout)
    parsed = urllib.parse.urlparse(status["API_URL"])
    if parsed.hostname not in ("localhost", "127.0.0.1") or parsed.port != 55321:
        raise RuntimeError("Ditolak: skrip ini hanya boleh mengakses backend Grouply lokal pada port 55321.")
    return status


def request(url, key, path, body=None, token=None, method="POST"):
    headers = {"apikey": key, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url + "/" + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def setup():
    status = local_status()
    key = status.get("PUBLISHABLE_KEY") or status["ANON_KEY"]
    url = status["API_URL"]
    existing = json.loads(ACCOUNT_FILE.read_text()) if ACCOUNT_FILE.exists() else {"accounts": {}}
    accounts = {}
    _, listed = request(url, status["SERVICE_ROLE_KEY"], "auth/v1/admin/users", token=status["SERVICE_ROLE_KEY"], method="GET")
    if not isinstance(listed, dict) or "users" not in listed:
        raise RuntimeError("Admin API lokal tidak tersedia; tidak ada akun yang diubah.")
    users = {user["email"]: user for user in listed["users"]}
    for persona in ("alex", "raka", "nadia"):
        email = persona + "@grouply.local"
        old = existing.get("accounts", {}).get(persona)
        password = old["password"] if old else secrets.token_urlsafe(24)
        payload = {"email": email, "password": password, "email_confirm": True, "user_metadata": {"name": persona.title()}}
        path = "auth/v1/admin/users"
        method = "POST"
        if email in users:
            path += "/" + users[email]["id"]
            method = "PUT"
        code, user = request(url, status["SERVICE_ROLE_KEY"], path, payload, status["SERVICE_ROLE_KEY"], method)
        if code not in (200, 201):
            raise RuntimeError("Pembuatan akun pengujian lokal gagal; detail kredensial tidak dicetak.")
        accounts[persona] = {"email": email, "password": password, "id": user["id"]}
    account_data = {"url": url.replace("127.0.0.1", "localhost"), "publishableKey": key, "accounts": accounts}
    ACCOUNT_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(ACCOUNT_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(account_data, stream, indent=2)
    os.chmod(ACCOUNT_FILE, 0o600)
    config = ROOT / "Config/Local.xcconfig"
    if config.exists() and "supabase.co" in config.read_text():
        raise RuntimeError("Akun lokal tersedia, tetapi konfigurasi cloud yang ada tidak ditimpa.")
    config.write_text(
        "// Generated public local connection values. No service-role or refresh credentials.\n"
        + "SUPABASE_URL = http:/$()/localhost:55321\n"
        + "SUPABASE_PUBLISHABLE_KEY = " + key + "\n"
        + "GROUPLY_LOCAL_ACCOUNTS_PATH = " + str(ACCOUNT_FILE) + "\n"
    )
    print("PASS: 3 akun lokal tersedia; konfigurasi publik ditulis ke Config/Local.xcconfig.")
    print("Kredensial pengujian disimpan privat di " + str(ACCOUNT_FILE))


def smoke():
    local_status()
    fixture = json.loads(ACCOUNT_FILE.read_text())
    url, key = fixture["url"], fixture["publishableKey"]
    tokens = {}
    for name, account in fixture["accounts"].items():
        code, result = request(url, key, "auth/v1/token?grant_type=password", {"email": account["email"], "password": account["password"]})
        assert code == 200, "Supabase Auth password sign-in failed"
        tokens[name] = result["access_token"]

    def rpc(name, action, payload, expected=200):
        code, result = request(url, key, "rest/v1/rpc/grouply_mutate", {"action": action, "payload": payload}, tokens[name])
        assert code == expected, "RPC " + action + " returned unexpected status " + str(code)
        return result

    def snapshot(name):
        code, result = request(url, key, "rest/v1/rpc/grouply_snapshot", {}, tokens[name])
        assert code == 200, "Snapshot failed"
        return result

    group = rpc("alex", "createGroup", {"name": "HTTP verification " + str(uuid.uuid4())[:8]})["id"]
    for name in ("raka", "nadia"):
        invite = rpc("alex", "generateInvite", {"groupID": group})["invite"]
        rpc(name, "joinGroup", {"code": invite["code"]})
    date = (datetime.now(timezone.utc) + timedelta(days=7)).isoformat()
    project = rpc("alex", "createProject", {"groupID": group, "title": "Server verification", "dueAt": date})["id"]
    task = rpc("alex", "createTask", {"projectID": project, "title": "Submit and review", "assigneeID": fixture["accounts"]["raka"]["id"], "reviewerID": fixture["accounts"]["nadia"]["id"], "dueAt": date})["id"]
    rpc("raka", "startTask", {"id": task, "expectedVersion": 1})
    rpc("raka", "submitWork", {"taskID": task, "note": "Verified over actual Auth and HTTP", "links": ["https://example.org/result"], "expectedVersion": 2})
    # Two independent HTTP requests race for the same pending revision.
    payload = {"taskID": task, "approve": True, "feedback": "Approved", "expectedVersion": 3}
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(request, url, key, "rest/v1/rpc/grouply_mutate", {"action": "review", "payload": payload}, tokens["nadia"]) for _ in range(2)]
        outcomes = [future.result() for future in futures]
    assert sorted(code for code, _ in outcomes) == [200, 400], "Exactly one concurrent review must succeed"
    assert "stale_version" in str(next(result for code, result in outcomes if code != 200)), "Losing review must be stale"
    final = next(value for value in snapshot("raka")["tasks"] if value["id"] == task)
    assert final["status"] == "done" and len(final["submissions"]) == 1, "Server task did not finish consistently"
    assert final["submissions"][0]["decision"] == "approved", "Review was not persisted"
    isolated = rpc("alex", "createGroup", {"name": "Private group " + str(uuid.uuid4())[:8]})["id"]
    code, rows = request(url, key, "rest/v1/groups?id=eq." + isolated, token=tokens["raka"], method="GET")
    assert code == 200 and rows == [], "RLS leaked another group's row"
    code, _ = request(url, key, "rest/v1/rpc/grouply_mutate", {"action": "updateGroup", "payload": {"id": isolated, "name": "Forbidden"}}, tokens["raka"])
    assert code == 400, "Cross-group mutation accepted"
    code, _ = request(url, key, "rest/v1/groups", {"name": "Direct DML forbidden"}, tokens["raka"])
    assert code in (401, 403), "Direct DML accepted"
    code, _ = request(url, key, "rest/v1/rpc/grouply_snapshot", {})
    assert code in (401, 403), "Unauthenticated snapshot accepted"
    output = ROOT / "artifacts/backend-http-verification.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps({"result": "PASS", "authenticated_accounts": 3, "groupID": group, "projectID": project, "taskID": task, "concurrent_review_statuses": sorted(code for code, _ in outcomes), "task_status": final["status"], "rls_isolation": "PASS", "direct_dml_denied": True}, indent=2))
    print("PASS: Auth 3 akun, create/join/project/task/submit/review, concurrent review, RLS dan direct-DML denial.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "smoke"))
    args = parser.parse_args()
    try:
        setup() if args.action == "setup" else smoke()
    except (RuntimeError, AssertionError, OSError, KeyError, ValueError) as error:
        raise SystemExit("FAIL: " + str(error))
