#!/usr/bin/env python3
"""ft_op_token.py — 운영 계정 access_token 을 저장된 cred 로 발급·교체한다 (판정 675).

사용: ft_op_token.py <email> | --init <email> (비밀번호는 stdin 1줄) | --list
설정(추적 밖): <secrets>/op-auth.conf · op-accounts.tsv · <계정>.cred(JSON {"email","password"})
외부 호출 1곳(Supabase password grant) — 7초 룰(판정 666): 1회 7 s(소켓 연산 기준) · 재시도 1(네트워크·5xx 만).
비밀번호·토큰 원문은 stdout·stderr·argv 어디에도 내지 않는다.
"""
import base64
import json
import os
import re
import socket
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

TIMEOUT_S = 7.0
MAX_RETRIES = 1
RETRY_WAIT_S = 0.5
KST = timezone(timedelta(hours=9))
MASKS = [re.compile(p) for p in (r"eyJ[\w.\-]+", r"sb_[\w\-]+", r'"password"\s*:\s*"[^"]*"')]


class Fail(Exception):
    def __init__(self, line, code=1):
        super().__init__(line)
        self.line, self.code = line, code


def secrets_dir():
    """FT_OP_SECRETS_DIR → 옛 설치 꼴(이 파일이 */.fable-team/bin)이면 <bin>/../secrets → cwd git 공용 루트의 .fable-team/secrets(실재)
    → ERROR rc1 (r385 r3 · 설치본(git 밖)의 ../secrets 는 없다 · 조용한 후퇴 0)."""
    d = os.environ.get("FT_OP_SECRETS_DIR")
    if d:
        return os.path.abspath(d)
    here = os.path.dirname(os.path.abspath(__file__))
    if os.path.basename(here) == "bin" and os.path.basename(os.path.dirname(here)) == ".fable-team":
        return os.path.abspath(os.path.join(here, "..", "secrets"))
    try:
        out = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, timeout=7)
        common = os.path.dirname(out.stdout.strip()) if out.returncode == 0 and out.stdout.strip() else ""
    except (OSError, subprocess.SubprocessError):
        common = ""
    if common and os.path.isdir(os.path.join(common, ".fable-team", "secrets")):
        return os.path.join(common, ".fable-team", "secrets")
    sys.exit(f"ERROR 비밀 폴더를 못 풂 — FT_OP_SECRETS_DIR 없음 · 옛 설치 꼴 아님({here}) · cwd({os.getcwd()}) git 공용 루트에 .fable-team/secrets 없음")


def mode_of(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def check_perms(sdir, files, email):
    if not os.path.isdir(sdir):
        raise Fail(f"ERR {email} 설정 없음: secrets 폴더 — ft-op-token.sh --init {email} 1회", 2)
    if mode_of(sdir) != 0o700:
        raise Fail(f"ERR {email} secrets 폴더 권한 {mode_of(sdir):04o} (0700 필요) — 직접 고친 뒤 재시도")
    for f in files:
        if os.path.exists(f) and mode_of(f) != 0o600:
            raise Fail(f"ERR {email} {os.path.basename(f)} 권한 {mode_of(f):04o} (0600 필요) — 직접 고친 뒤 재시도")


def read_conf(sdir, email):
    path = os.path.join(sdir, "op-auth.conf")
    if not os.path.exists(path):
        raise Fail(f"ERR {email} 설정 없음: op-auth.conf — ft-op-token.sh --init {email} 1회", 2)
    kv = {}
    for line in open(path, encoding="utf-8"):
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.rstrip("\n").split("=", 1)
            kv[k.strip()] = v.strip()
    if not kv.get("SUPABASE_URL") or not kv.get("SUPABASE_PUBLISHABLE_KEY"):
        raise Fail(f"ERR {email} op-auth.conf 에 SUPABASE_URL·SUPABASE_PUBLISHABLE_KEY 필요", 2)
    url = kv["SUPABASE_URL"].rstrip("/")
    if not (url.startswith("https://") or loopback_http_allowed(url)):
        raise Fail(f"ERR {email} op-auth.conf SUPABASE_URL 은 https:// 만", 2)
    return url, kv["SUPABASE_PUBLISHABLE_KEY"]


def loopback_http_allowed(url):
    """시험 전용 우회: FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK=1 이고 http 호스트가 127.0.0.1·localhost 일 때만."""
    if os.environ.get("FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK") != "1" or not url.startswith("http://"):
        return False
    return urllib.parse.urlsplit(url).hostname in ("127.0.0.1", "localhost")


def read_table(sdir):
    path = os.path.join(sdir, "op-accounts.tsv")
    rows = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 3 and not p[0].startswith("#"):
                rows[p[0]] = (p[1], p[2])
    return rows


def mask(text, secret=None):
    for rx in MASKS:
        text = rx.sub("***", text)
    if secret:
        text = text.replace(secret, "***")
    return text[:200]


def login(url, key, email, password):
    """password grant. 4xx = 즉시 Fail · 네트워크·5xx = 재시도 1회 뒤 Fail. 성공 시 access_token."""
    body = json.dumps({"email": email, "password": password}).encode()
    req = urllib.request.Request(f"{url}/auth/v1/token?grant_type=password", data=body, method="POST",
                                 headers={"apikey": key, "Content-Type": "application/json"})
    last = None
    for attempt in range(MAX_RETRIES + 1):
        if attempt:
            time.sleep(RETRY_WAIT_S)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
                raw = r.read().decode("utf-8", "replace")
            try:
                tok = json.loads(raw).get("access_token")
            except (ValueError, AttributeError):
                raise Fail(f"ERR {email} http=200 msg=응답 JSON 아님")
            if not tok:
                raise Fail(f"ERR {email} http=200 msg=access_token 없음")
            return tok
        except urllib.error.HTTPError as e:
            msg = mask(e.read().decode("utf-8", "replace"), password)
            last = f"ERR {email} http={e.code} msg={msg}"
            if e.code < 500:
                raise Fail(last)
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, OSError) as e:
            last = f"ERR {email} http=net msg={mask(str(getattr(e, 'reason', e)), password)}"
    raise Fail(last)


def exp_of(token):
    try:
        seg = token.split(".")[1]
        return int(json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))["exp"])
    except (IndexError, KeyError, ValueError):
        return None


def atomic_write(path, text):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def ok_line(email, token, token_name):
    exp = exp_of(token)
    if exp is None:
        return f"OK {email} exp=? file={token_name}"
    mins = int((exp - time.time()) // 60)
    return f"OK {email} exp={datetime.fromtimestamp(exp, KST):%H:%M} ({mins}분) file={token_name}"


def issue(email, init):
    sdir = secrets_dir()
    rows = read_table(sdir) if os.path.isdir(sdir) else {}
    if email not in rows:
        raise Fail(f"ERR {email} 계정 표에 없음 (op-accounts.tsv 에 1줄 추가는 사람이)", 2)
    cred_name, token_name = rows[email]
    cred_path, token_path = (os.path.join(sdir, n) for n in (cred_name, token_name))
    check_perms(sdir, [cred_path, token_path, os.path.join(sdir, "op-auth.conf"), os.path.join(sdir, "op-accounts.tsv")], email)
    url, key = read_conf(sdir, email)
    if init:
        password = sys.stdin.readline().rstrip("\r\n")
        if not password:
            raise Fail(f"ERR {email} 비밀번호 입력 없음 (클립보드가 비었다)")
        cred = {}
    else:
        if not os.path.exists(cred_path):
            raise Fail(f"ERR {email} 설정 없음: {cred_name} — ft-op-token.sh --init {email} 1회", 2)
        cred = json.load(open(cred_path, encoding="utf-8"))
        password = cred.get("password", "")
    token = login(url, key, email, password)
    if init:
        if os.path.exists(cred_path):
            cred = json.load(open(cred_path, encoding="utf-8"))
        cred.update({"email": email, "password": password})
        atomic_write(cred_path, json.dumps(cred, ensure_ascii=False))
    atomic_write(token_path, token)
    return ok_line(email, token, token_name)


def list_accounts():
    sdir = secrets_dir()
    for email, (_, token_name) in read_table(sdir).items():
        tp = os.path.join(sdir, token_name)
        left = "없음"
        if os.path.exists(tp):
            exp = exp_of(open(tp, encoding="utf-8").read().strip())
            left = "?" if exp is None else ("만료" if exp <= time.time() else f"{int((exp - time.time()) // 60)}분")
        print(f"{email}\t{token_name}\t{left}")


def main(argv):
    os.umask(0o077)
    try:
        if argv[:1] == ["--list"]:
            return list_accounts() or 0
        init = argv[:1] == ["--init"]
        args = argv[1:] if init else argv
        if len(args) != 1:
            print("usage: ft-op-token.sh <email> | --init <email> | --list", file=sys.stderr)
            return 2
        print(issue(args[0], init))
        return 0
    except Fail as e:
        print(e.line)
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
