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


# ── r605 --init-from-op: 비밀번호를 1Password develop 볼트에서 프로세스 안으로만 ──
OP_ITEM = "opitem5r605"
OP_PASSWORD = "Op-Pw-fake-67890"
OP_DEVELOP_TOKEN = "develop-token-value"


@pytest.fixture
def opstub(tmp_path, env):
    """가짜 op 실행 파일 — argv·env·calls 를 파일로 남기고 body/rc/err/sleep 을 흉내낸다."""
    d = tmp_path / "opstub"
    d.mkdir()
    argv, envtok, body, rc, err, calls = (d / n for n in ("argv", "envtoken", "body", "rc", "err", "calls"))
    script = d / "op"
    script.write_text(
        "#!/bin/sh\n"
        f'echo run >> "{calls}"\n'
        f'printf "%s\\n" "$@" > "{argv}"\n'
        f'printf "%s" "${{OP_SERVICE_ACCOUNT_TOKEN:-}}" > "{envtok}"\n'
        f'[ -f "{d}/sleep" ] && sleep 30\n'
        f'case "$*" in *label=username*) cat "{d}/username" 2>/dev/null ;; *) cat "{body}" 2>/dev/null ;; esac\n'
        f'[ -f "{err}" ] && cat "{err}" >&2\n'
        f'[ -f "{rc}" ] && exit $(cat "{rc}")\n'
        "exit 0\n"
    )
    script.chmod(0o755)
    body.write_text(OP_PASSWORD + "\n")
    (d / "username").write_text(EMAIL + "\n")
    env["env"]["FT_OP_BIN"] = str(script)
    env["env"]["OP_SERVICE_ACCOUNT_TOKEN"] = "kskill-default-token"
    env["env"]["OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"] = OP_DEVELOP_TOKEN
    return {"argv": argv, "envtoken": envtok, "body": body, "rc": rc, "err": err, "calls": calls,
            "sleep": d / "sleep", "dir": d, "userbody": d / "username"}


def _texts(path, skip):
    for p in sorted(Path(path).rglob("*")):
        if p.is_file() and p not in skip:
            yield p, p.read_text(errors="replace")


def test_o1_init_from_op_success(env, stub, opstub):
    """ⓐ op argv·env 고정 · 로그인 OK → cred 저장 · stdout 1줄 OK."""
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.startswith(f"OK {EMAIL} exp=") and "file=acct.token" in r.stdout
    assert opstub["argv"].read_text().splitlines() == [
        "item", "get", OP_ITEM, "--vault", "develop", "--fields", "label=password", "--reveal"]
    assert opstub["envtoken"].read_text() == OP_DEVELOP_TOKEN
    cred, tok = env["sdir"] / "acct.cred", env["sdir"] / "acct.token"
    assert json.loads(cred.read_text())["password"] == OP_PASSWORD
    assert mode(cred) == 0o600 and tok.read_text() == stub.token and mode(tok) == 0o600
    assert env["clip"].read_text() == PASSWORD + "\n"  # 클립보드 손 0 — pbpaste/pbcopy 안 부름


def test_o2_missing_develop_token(env, stub, opstub):
    """ⓑ develop 토큰 없음 → rc≠0 · 가짜 op 호출 0 (기본 kskill 토큰 대체 0)."""
    (env["sdir"] / "acct.cred").unlink()
    env["env"].pop("OP_SERVICE_ACCOUNT_TOKEN_DEVELOP")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0 and "develop 토큰 없음" in r.stdout
    assert not opstub["calls"].exists()
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o3_password_never_leaves_process(env, stub, opstub):
    """ⓒ 값이 stdout·stderr·cred 밖 파일 어디에도 0."""
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0
    assert OP_PASSWORD not in r.stdout + r.stderr
    skip = {env["sdir"] / "acct.cred", opstub["body"]}
    leaks = [str(p) for p, t in _texts(env["sdir"].parent, skip) if OP_PASSWORD in t]
    assert leaks == []


def test_o4_op_failure_prints_no_stderr(env, stub, opstub):
    """ⓓ op rc≠0 + stderr 에 bare 비밀번호(패턴 없음)·토큰 꼴 → stdout 은 고정 문구만 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    bare_token = "optok-bare-1234567890"
    opstub["rc"].write_text("3")
    opstub["err"].write_text(f"read failed: {OP_PASSWORD}\nAuthorization: Bearer {bare_token}\n")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0
    nbytes = len(opstub["err"].read_text().encode("utf-8"))
    assert r.stdout == f"ERR op 읽기 실패 rc=3 (stderr {nbytes}바이트 · 원문 숨김)\n"
    assert OP_PASSWORD not in r.stdout + r.stderr and bare_token not in r.stdout + r.stderr
    assert "read failed" not in r.stdout + r.stderr and "Traceback" not in r.stderr
    assert opstub["calls"].read_text().count("run") == 1  # 재시도 0
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o5_op_empty_value(env, stub, opstub):
    """ⓔ op 빈 값 → ERR 빈 값 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    opstub["body"].write_text("\n")
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode != 0 and "빈 값" in r.stdout
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o6_op_timeout_no_retry(env, stub, opstub):
    """ⓕ op 가 10.5s 넘게 멈춤 → 시간 초과 ERR · 재시도 0 · cred 쓰기 0."""
    (env["sdir"] / "acct.cred").unlink()
    opstub["sleep"].write_text("")
    t0 = time.time()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL, timeout=40)
    assert r.returncode != 0 and "시간 초과" in r.stdout and time.time() - t0 < 20
    assert opstub["calls"].read_text().count("run") == 1
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


def test_o7_login_fail_writes_no_cred(env, stub, opstub):
    """ⓖ 로그인 실패 → cred 쓰기 0 (값도 0)."""
    (env["sdir"] / "acct.cred").unlink()
    stub.mode = "400"
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {EMAIL} http=400")
    assert OP_PASSWORD not in r.stdout + r.stderr
    assert not (env["sdir"] / "acct.cred").exists() and not (env["sdir"] / "acct.token").exists()


# ── r611 --init-from-op: 표에 없는 계정이면 도구가 표 줄까지 추가 (사용자 이름 = 이메일일 때만) ──
NEW_EMAIL = "new.user@x"
NEW_CRED = "byz_new_user.cred"
NEW_TOKEN = "byz_new_user_token_dev"


def table_text(env):
    return (env["sdir"] / "op-accounts.tsv").read_text()


def test_r611a_unknown_email_appends_row_after_login(env, stub, opstub):
    """ⓐ 표에 없는 이메일 + op username == 이메일 → 표 끝 1줄 + cred·token 생성 · stdout «(표 줄 추가)»."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0, r.stdout + r.stderr
    assert r.stdout.startswith(f"OK {NEW_EMAIL} exp=") and f"file={NEW_TOKEN}" in r.stdout
    assert r.stdout.rstrip("\n").endswith("(표 줄 추가)")
    assert table_text(env) == before + f"{NEW_EMAIL}\t{NEW_CRED}\t{NEW_TOKEN}\n"
    cred, tok = env["sdir"] / NEW_CRED, env["sdir"] / NEW_TOKEN
    assert json.loads(cred.read_text())["password"] == OP_PASSWORD
    assert tok.read_text() == stub.token and mode(cred) == 0o600 and mode(tok) == 0o600
    calls = opstub["calls"].read_text().count("run")
    assert calls == 2  # 표 줄용 username + 비밀번호, develop 고정 env 고정 argv('--reveal' 은 비밀번호만)
    assert opstub["argv"].read_text().splitlines() == [
        "item", "get", OP_ITEM, "--vault", "develop", "--fields", "label=password", "--reveal"]
    assert stub.calls == 1 and OP_PASSWORD not in r.stdout + r.stderr


def test_r611b_username_not_email_rejects(env, stub, opstub):
    """ⓑ op username ≠ 이메일 → ERR rc2 · 표·cred 쓰기 0."""
    before = table_text(env)
    opstub["userbody"].write_text("someone.else@x\n")
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 2 and r.stdout.startswith(f"ERR 항목 사용자 이름 ≠ {NEW_EMAIL}")
    assert table_text(env) == before and stub.calls == 0
    assert not (env["sdir"] / NEW_CRED).exists() and not (env["sdir"] / NEW_TOKEN).exists()


def test_r611b2_username_read_failure_fixed_line(env, stub, opstub):
    """ⓑ2 username 읽기 실패 → r605 와 같은 고정 문구 · 표 쓰기 0."""
    before = table_text(env)
    opstub["rc"].write_text("3")
    opstub["err"].write_text("denied\n")
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode != 0 and r.stdout.startswith("ERR op 읽기 실패 rc=3 (stderr ")
    assert "denied" not in r.stdout + r.stderr
    assert table_text(env) == before and not (env["sdir"] / NEW_CRED).exists()


def test_r611c_login_failure_writes_no_row(env, stub, opstub):
    """ⓒ 로그인 실패 → 표 줄 추가 0 (표는 로그인 성공 뒤에만)."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    stub.mode = "400"
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 1 and r.stdout.startswith(f"ERR {NEW_EMAIL} http=400")
    assert table_text(env) == before
    assert not (env["sdir"] / NEW_CRED).exists() and not (env["sdir"] / NEW_TOKEN).exists()


def test_r611d_name_collision_rejects(env, stub, opstub):
    """ⓓ 새 이름이 이미 있는 파일·표 줄과 겹침 → ERR · 쓰기 0."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    p = env["sdir"] / NEW_CRED
    p.write_text("{}")
    p.chmod(0o600)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 2 and "이름 겹침" in r.stdout and NEW_CRED in r.stdout
    assert table_text(env) == before and stub.calls == 0
    p.unlink()
    tsv = env["sdir"] / "op-accounts.tsv"
    tsv.write_text(before + f"third@example.test\t{NEW_TOKEN}\tother.token\n")
    tsv.chmod(0o600)
    r2 = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r2.returncode == 2 and "이름 겹침" in r2.stdout and NEW_TOKEN in r2.stdout
    assert table_text(env).endswith(f"third@example.test\t{NEW_TOKEN}\tother.token\n")


def test_r611e_table_write_is_atomic_and_keeps_bytes(env, stub, opstub):
    """ⓔ 표 = 원자 쓰기(임시 파일 잔여 0) · 권한 600 유지 · 기존 줄 바이트 불변."""
    opstub["userbody"].write_text(NEW_EMAIL + "\n")
    before = table_text(env)
    r = run(env, "--init-from-op", OP_ITEM, NEW_EMAIL)
    assert r.returncode == 0
    tsv = env["sdir"] / "op-accounts.tsv"
    assert mode(tsv) == 0o600
    assert table_text(env).startswith(before) and table_text(env).count("\n") == before.count("\n") + 1
    assert not [p for p in env["sdir"].iterdir() if p.name.startswith(".tmp-")]


def test_r611f_known_account_unchanged(env, stub, opstub):
    """ⓕ 이미 표에 있는 계정 → r605 동작 그대로(표 바이트 불변 · username 호출 0 · 꼬리 없음)."""
    before = table_text(env)
    (env["sdir"] / "acct.cred").unlink()
    r = run(env, "--init-from-op", OP_ITEM, EMAIL)
    assert r.returncode == 0 and "(표 줄 추가)" not in r.stdout
    assert table_text(env) == before
    assert opstub["argv"].read_text().splitlines()[-1] == "--reveal"
    assert opstub["calls"].read_text().count("run") == 1
