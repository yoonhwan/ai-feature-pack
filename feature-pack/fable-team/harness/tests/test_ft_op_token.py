"""ft-op-token.sh 시험 (판정 675) — 실 Supabase 호출 0 · 로컬 스텁 서버 + 임시 secrets."""
import base64
import json
import os
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
KIT_BIN = ROOT / "harness/kit/fable-team/bin"
TOOL = KIT_BIN / "ft-op-token.sh"
STAGED = ROOT / "harness/design/harness/staged-675"
EMAIL = "tester@example.test"
PASSWORD = "Pw-fake-12345"
KEY = "fake-publishable-key"


def b64(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()


def fake_jwt(exp):
    return f"{b64({'alg': 'none'})}.{b64({'exp': int(exp)})}.sig"


class Stub(ThreadingHTTPServer):
    daemon_threads = True
    mode = "200"
    calls = 0
    token = ""


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        srv = self.server
        srv.calls += 1
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if srv.mode == "400":
            code, body = 400, json.dumps({"error": "bad", "password": PASSWORD, "hint": fake_jwt(1)})
        elif srv.mode == "nonjson":
            code, body = 200, "<html>not json</html>"
        elif srv.mode == "500":
            code, body = 500, "boom"
        elif srv.mode == "slow":
            time.sleep(8)
            code, body = 200, json.dumps({"access_token": srv.token})
        else:
            code, body = 200, json.dumps({"access_token": srv.token})
        self.send_response(code)
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *a):
        pass


@pytest.fixture
def stub():
    s = Stub(("127.0.0.1", 0), Handler)
    s.token = fake_jwt(time.time() + 3600)
    threading.Thread(target=s.serve_forever, daemon=True).start()
    yield s
    s.shutdown()


@pytest.fixture
def env(tmp_path, stub):
    sdir = tmp_path / "secrets"
    sdir.mkdir(mode=0o700)
    sdir.chmod(0o700)
    files = {
        "op-auth.conf": f"SUPABASE_URL=http://127.0.0.1:{stub.server_address[1]}\nSUPABASE_PUBLISHABLE_KEY={KEY}\n",
        "op-accounts.tsv": f"{EMAIL}\tacct.cred\tacct.token\nother@example.test\tother.cred\tother.token\n",
        "acct.cred": json.dumps({"email": EMAIL, "password": PASSWORD}),
    }
    for name, text in files.items():
        (sdir / name).write_text(text)
        (sdir / name).chmod(0o600)
    bin_dir = tmp_path / "stubbin"
    bin_dir.mkdir()
    clip = tmp_path / "clip.txt"
    clip.write_text(PASSWORD + "\n")
    (bin_dir / "pbpaste").write_text(f'#!/bin/sh\ncat "{clip}"\n')
    (bin_dir / "pbcopy").write_text(f'#!/bin/sh\ncat > "{clip}"\n')
    for n in ("pbpaste", "pbcopy"):
        (bin_dir / n).chmod(0o755)
    e = dict(os.environ, FT_OP_SECRETS_DIR=str(sdir), PATH=f"{bin_dir}:{os.environ['PATH']}", FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK="1")
    return {"env": e, "sdir": sdir, "clip": clip}


def run(env, *args, timeout=60):
    return subprocess.run(["bash", str(TOOL), *args], env=env["env"], capture_output=True, text=True, timeout=timeout)


def mode(p):
    return stat.S_IMODE(p.stat().st_mode)


def assert_no_secret(r, stub):
    out = r.stdout + r.stderr
    assert PASSWORD not in out and stub.token not in out and "eyJ" not in out


def test_t1_success_replaces_token(env, stub):
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 0 and r.stdout.startswith(f"OK {EMAIL} exp=") and "file=acct.token" in r.stdout
    assert tf.read_text() == stub.token and mode(tf) == 0o600
    assert_no_secret(r, stub)


def test_t2_400_no_retry_keeps_old_token(env, stub):
    stub.mode = "400"
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert stub.calls == 1 and tf.read_text() == "old-token"
    assert_no_secret(r, stub)


def test_t3_500_retries_once(env, stub):
    stub.mode = "500"
    r = run(env, EMAIL)
    assert r.returncode == 1 and "http=500" in r.stdout and stub.calls == 2
    assert not (env["sdir"] / "acct.token").exists()


def test_t4_timeout_7s_then_retry_then_net_err(env, stub):
    stub.mode = "slow"
    t0 = time.time()
    r = run(env, EMAIL)
    assert r.returncode == 1 and "http=net" in r.stdout and stub.calls == 2
    assert time.time() - t0 < 16


def test_t5_no_cred_exits_2_with_init_hint(env):
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, EMAIL)
    assert r.returncode == 2 and "--init" in r.stdout and "acct.cred" in r.stdout


def test_t6_init_success_writes_cred_and_clears_clipboard(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init", EMAIL)
    assert r.returncode == 0 and r.stdout.startswith("OK ")
    cred, tok = env["sdir"] / "acct.cred", env["sdir"] / "acct.token"
    assert json.loads(cred.read_text())["password"] == PASSWORD and mode(cred) == 0o600 and mode(tok) == 0o600
    assert env["clip"].read_text() == ""
    assert_no_secret(r, stub)


def test_t6b_init_failure_writes_no_cred(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init", EMAIL)
    assert r.returncode == 1 and not (env["sdir"] / "acct.cred").exists()
    assert not (env["sdir"] / "acct.token").exists() and env["clip"].read_text() == ""  # 실패여도 클립보드 비움(T12)


def test_t6c_init_unknown_email_rejected(env):
    r = run(env, "--init", "nobody@example.test")
    assert r.returncode == 2 and "계정 표에 없음" in r.stdout


def test_t8_loose_secrets_dir_is_err(env):
    env["sdir"].chmod(0o755)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith("ERR") and "0700" in r.stdout
    assert mode(env["sdir"]) == 0o755  # 조용한 수정 0


def test_t9_list_shows_remaining_minutes_without_token(env, stub):
    for name, exp in (("acct.token", time.time() + 1800), ("other.token", time.time() - 60)):
        p = env["sdir"] / name
        p.write_text(fake_jwt(exp))
        p.chmod(0o600)
    r = run(env, "--list")
    rows = [ln.split("\t") for ln in r.stdout.strip().splitlines()]
    assert r.returncode == 0 and rows[0][0] == EMAIL and rows[0][2] in ("29분", "30분") and rows[1][2] == "만료"
    assert "eyJ" not in r.stdout


def test_t10_no_real_values_in_tracked_files():
    needles = ["supabase" + ".co", "sb_publi" + "shable_", "@byo" + "urz.com"]
    targets = [KIT_BIN / "ft-op-token.sh", KIT_BIN / "ft_op_token.py"]
    targets += [STAGED / "op-auth.conf.example", STAGED / "op-accounts.tsv.example"]
    for t in targets:
        assert t.exists(), t
        text = t.read_text()
        assert not [n for n in needles if n in text], t


def test_t11_200_non_json_is_one_err_line(env, stub):
    stub.mode = "nonjson"
    tf = env["sdir"] / "acct.token"
    tf.write_text("old-token")
    tf.chmod(0o600)
    r = run(env, EMAIL)
    assert r.returncode == 1 and r.stdout == f"ERR {EMAIL} http=200 msg=응답 JSON 아님\n"
    assert "Traceback" not in r.stderr and "not json" not in r.stdout + r.stderr
    assert stub.calls == 1 and tf.read_text() == "old-token"


def test_t12_init_failure_clears_clipboard(env, stub):
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init", EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert env["clip"].read_text() == "" and PASSWORD not in r.stdout + r.stderr


def set_url(env, url):
    conf = env["sdir"] / "op-auth.conf"
    conf.write_text(f"SUPABASE_URL={url}\nSUPABASE_PUBLISHABLE_KEY={KEY}\n")
    conf.chmod(0o600)


def test_t13_non_https_url_is_err(env, stub):
    port = stub.server_address[1]
    set_url(env, "http://example.invalid")
    r = run(env, EMAIL)  # 우회 변수 있어도 비루프백 http 는 ERR
    assert r.returncode == 2 and r.stdout.startswith(f"ERR {EMAIL} op-auth.conf SUPABASE_URL 은 https:// 만")
    set_url(env, f"http://127.0.0.1:{port}")
    env["env"].pop("FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK")
    r = run(env, EMAIL)  # 변수 없으면 루프백 http 도 ERR
    assert r.returncode == 2 and "https:// 만" in r.stdout and stub.calls == 0
    env["env"]["FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK"] = "1"
    r = run(env, EMAIL)  # 변수 + 루프백 = 통과
    assert r.returncode == 0 and r.stdout.startswith("OK ") and stub.calls == 1
