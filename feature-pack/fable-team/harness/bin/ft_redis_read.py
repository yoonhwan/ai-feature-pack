"""ft_redis_read — «읽기 전용 redis 묶음» 실행기 본체 (r623 r4 · 하드 룰 11 유지).

보증 = 서버(ACL 읽기 전용 계정 `ft-readonly`) · 이 파일의 글자 검사 = «빠른 거절 + 원장» 뿐.
진입은 `ft-redis-read.sh`(python3 -I 로 이 파일 실행) 하나 — 환경변수 갈래 0:
실행 파일·읽기 목록·원장·비밀번호 경로는 전부 고정이고, 시험은 main() 에 키워드 인자로 경로를 주입한다.

rc: 0 통과 · 2 REJECT(빠른 거절 · redis-cli 호출 0) · 3 서버 오류 줄(NOPERM·ERR·WRONGTYPE …)
    4 읽기 전용 계정 없음(비밀번호 파일 없음 · WRONGPASS · NOAUTH) — 기본 사용자로 대신 접속하는 갈래 0
"""
import hashlib
import os
import pwd
import re
import subprocess
import sys
import time

USER = "ft-readonly"
HOME = pwd.getpwuid(os.getuid()).pw_dir          # HOME 환경변수가 아니라 계정 정보
HOOK = os.path.join(HOME, ".claude", "hooks", "block-destructive.sh")
LOG = os.path.join(HOME, ".claude", "logs", "redis-read.log")
PASSFILE = os.path.join(HOME, ".config", "ft", "redis-readonly.pass")
CLI_CANDIDATES = ("/opt/homebrew/bin/redis-cli", "/usr/local/bin/redis-cli")
MAX_BYTES = 1024 * 1024
MAX_LINES = 10000
HOST = re.compile(r"^[A-Za-z0-9_.:-]+$")
ERR_LINE = re.compile(r"^(\(error\)|NOPERM|ERR |WRONGTYPE|NOAUTH|WRONGPASS)")
AUTH_FAIL = re.compile(r"WRONGPASS|NOAUTH|AUTH failed")
NO_ACCOUNT = ("읽기 전용 계정 없음(redis 재기동 뒤?) · "
              "준비 h `ft-redis-readonly-user.sh ensure` 실행 필요")


class Reject(Exception):
    def __init__(self, rc, msg):
        super().__init__(msg)
        self.rc, self.msg = rc, msg


def read_verbs(hook):
    """훅 파일의 INJECT_READ_VERBS 한 줄 → (한 낱말 집합, 두 낱말 집합). 복사 0."""
    try:
        with open(hook, encoding="utf-8") as f:
            txt = f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise Reject(2, "읽기 동사 목록을 훅 파일에서 못 읽음: %s" % type(e).__name__)
    m = re.search(r"^INJECT_READ_VERBS='([^']+)'$", txt, re.M)
    if not m:
        raise Reject(2, "읽기 동사 목록을 훅 파일에서 못 읽음: INJECT_READ_VERBS 줄 없음")
    words = [v.split() for v in m.group(1).split("|")]
    one = {w[0] for w in words if len(w) == 1}
    two = {tuple(w) for w in words if len(w) == 2}
    if not one:
        raise Reject(2, "읽기 동사 목록이 비었음")
    return one, two


def acl_rule(hook=HOOK):
    """ACL SETUSER 규칙 낱말(비밀번호 제외) — `-@all` + 훅 읽기 목록과 같은 명령만 · SELECT(-n 용)."""
    one, two = read_verbs(hook)
    allow = sorted("+" + v.lower() for v in one)
    allow += sorted("+%s|%s" % (a.lower(), b.lower()) for a, b in two)
    return ["reset", "on", "~*", "-@all"] + allow + ["+select"]


def parse_args(argv):
    opts, path, i = [], None, 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "-p", "-n"):
            if i + 1 >= len(argv):
                raise Reject(2, "%s 값 없음" % a)
            v = argv[i + 1]
            if a in ("-p", "-n") and not (v.isascii() and v.isdigit()):
                raise Reject(2, "%s 값이 숫자가 아님: %r" % (a, v))
            if a == "-h" and not HOST.match(v):
                raise Reject(2, "-h 값 모양 틀림: %r" % (v,))
            opts += [a, v]
            i += 2
            continue
        if a.startswith("-"):
            raise Reject(2, "허용 밖 옵션: %r (-h/-p/-n 만)" % (a,))
        if path is not None:
            raise Reject(2, "묶음 파일은 1개만: %r" % (a,))
        path, i = a, i + 1
    if path is None:
        raise Reject(2, "사용법: ft-redis-read.sh [-h H] [-p P] [-n N] <묶음 파일>")
    return opts, path


def load(path):
    """파일을 «한 번» 읽는다 — 이후 판정·실행은 이 바이트만 쓴다(다시 열지 않음)."""
    if not os.path.isfile(path) or os.path.islink(path):
        raise Reject(2, "일반 파일이 아님: %s" % path)
    try:
        with open(path, "rb") as f:
            data = f.read(MAX_BYTES + 1)
    except OSError as e:
        raise Reject(2, "파일을 못 읽음: %s" % type(e).__name__)
    if len(data) > MAX_BYTES:
        raise Reject(2, "1 MiB 상한 초과: %s" % path)
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise Reject(2, "UTF-8 이 아님: %s" % path)
    bad = next((c for c in text if c != "\n" and not c.isprintable()), None)
    if bad is not None:
        raise Reject(2, "출력 불가 글자(제어 문자) U+%04X: %s" % (ord(bad), path))
    lines = text.split("\n")
    if len(lines) > MAX_LINES + 1:
        raise Reject(2, "1만 줄 상한 초과: %d 줄" % len(lines))
    return data, lines


def judge(lines, one, two):
    n = 0
    for ln in lines:
        s = ln.strip()
        if not s or s.startswith("#"):
            continue
        up = [x.upper() for x in s.split()[:2]]
        if up[0] in one or (len(up) == 2 and tuple(up) in two):
            n += 1
            continue
        raise Reject(2, "읽기 목록 밖 동사: %s" % s.split()[0][:32])
    if not n:
        raise Reject(2, "읽을 줄이 없음(빈 묶음)")
    return n


def pick_cli(candidates):
    found = [c for c in candidates if os.path.isfile(c) and os.access(c, os.X_OK)]
    if len(found) != 1:
        raise Reject(2, "redis-cli 고정 경로가 정확히 1개가 아님: %d개 %s" % (len(found), list(candidates)))
    return found[0]


def read_pass(passfile):
    try:
        with open(passfile, encoding="utf-8") as f:
            pw = f.read().strip()
    except (OSError, UnicodeDecodeError):
        raise Reject(4, NO_ACCOUNT)
    if not pw or "\n" in pw:
        raise Reject(4, NO_ACCOUNT)
    return pw


def main(argv, hook=HOOK, log=LOG, passfile=PASSFILE, cli_candidates=CLI_CANDIDATES):
    try:
        opts, path = parse_args(argv)
        one, two = read_verbs(hook)
        data, lines = load(path)
        n = judge(lines, one, two)
        cli = pick_cli(cli_candidates)
        pw = read_pass(passfile)
        sha = hashlib.sha256(data).hexdigest()[:16]
        try:                                       # 원장 실패 = 실행 전 REJECT
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "a", encoding="utf-8") as f:
                f.write("%s path=%s lines=%d sha256=%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), path, n, sha))
        except OSError as e:
            raise Reject(2, "원장 기록 실패(실행 0): %s" % type(e).__name__)
        env = {"PATH": "/usr/bin:/bin", "HOME": HOME, "LANG": "C", "REDISCLI_AUTH": pw}
        sys.stderr.write("OK ft-redis-read — %s lines=%d sha256=%s\n" % (path, n, sha))
        try:
            p = subprocess.run([cli, "--user", USER, "--no-raw"] + opts, input=data,
                               env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as e:
            raise Reject(2, "redis-cli 실행 실패: %s" % type(e).__name__)
        sys.stdout.buffer.write(p.stdout)
        sys.stderr.buffer.write(p.stderr)
        out = (p.stdout + b"\n" + p.stderr).decode("utf-8", "replace").splitlines()
        if any(AUTH_FAIL.search(x) for x in out):
            raise Reject(4, NO_ACCOUNT)
        err = next((x for x in out if ERR_LINE.match(x.strip())), None)
        if err is not None:
            raise Reject(3, "서버 오류 줄: %s" % err.strip()[:200])
        return p.returncode
    except Reject as r:
        sys.stderr.write("REJECT ft-redis-read — %s\n" % r.msg)
        return r.rc
    except Exception as e:                         # 판정기 실패 = 차단 · traceback 0
        sys.stderr.write("REJECT ft-redis-read — 내부 오류: %s\n" % type(e).__name__)
        return 2


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--acl-rule":   # 규칙 출력만(실행 0) — 준비 h 가 씀
        try:
            print(" ".join(acl_rule(*sys.argv[2:3])))
        except Reject as r:
            sys.stderr.write("REJECT ft-redis-read — %s\n" % r.msg)
            sys.exit(r.rc)
        sys.exit(0)
    sys.exit(main(sys.argv[1:]))
