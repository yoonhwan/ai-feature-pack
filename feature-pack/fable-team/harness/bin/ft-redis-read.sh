#!/bin/bash
# ft-redis-read.sh — «읽기 전용 redis 묶음» 실행 도구 (r623 · 하드 룰 11 유지)
#
# 왜 있나: 측정 조작 차단 훅(block-destructive.sh)은 `redis-cli … < <파일>` 을 막는다 — bash 가 «나중에» 여는
# 파일을 훅이 미리 맞히려 하면 중괄호 확장·경합 같은 틈이 계속 생긴다(DA⑥ r1·r2). 그래서 훅은 넓히지 않고(팩 main 판 그대로),
# 이 도구가 «한 번 읽어 판정한 그 바이트» 를 그대로 redis-cli 표준입력으로 보낸다 = 검사한 내용과 실행한 내용이 같다.
#
# 쓰는 법: ft-redis-read.sh [-h H] [-p P] [-n N] <묶음 파일>
#   1) 파일을 «한 번» 읽어 메모리에 올리고(1 MiB · 1만 줄 상한 · UTF-8) 빈 줄·`#` 주석을 뺀 모든 줄의 첫 동사
#      (두 낱말 동사 포함)가 훅의 INJECT_READ_VERBS 안인지 본다 — 목록은 훅 파일에서 읽는다(복사 0 · 못 읽으면 REJECT).
#   2) redis-cli 인자는 이 도구가 만든 고정 꼴(-h/-p/-n 값만 · 숫자·호스트 글자 검사)뿐 — -x·--eval·--pipe·URL·추가 인자 0.
#   3) 실행마다 원장 1줄(시각·경로·줄 수·sha256 앞16 · 내용 0).
# 하나라도 어긋나면 REJECT rc2 + 사유 1줄 · redis-cli 호출 0 (폴백 없음). 쓰기 동사 1줄이라도 있으면 차단 — 하드 룰 11 약화 0.
set -uo pipefail
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename -- "${BASH_SOURCE[0]:-$0}")"
exec python3 - "$SELF" "$@" <<'PY'
import hashlib, os, re, subprocess, sys, time

def reject(msg):
    sys.stderr.write("REJECT ft-redis-read — %s\n" % msg)
    sys.exit(2)

self, argv = sys.argv[1], sys.argv[2:]
host = re.compile(r"^[A-Za-z0-9_.:@/+-]+$")
opts, path = [], None
i = 0
while i < len(argv):
    a = argv[i]
    if a in ("-h", "-p", "-n"):
        if i + 1 >= len(argv):
            reject("%s 값 없음" % a)
        v = argv[i + 1]
        if a in ("-p", "-n") and not v.isdigit():
            reject("%s 값이 숫자가 아님: %r" % (a, v))
        if a == "-h" and not host.match(v):
            reject("-h 값 모양 틀림: %r" % (v,))
        opts += [a, v]; i += 2; continue
    if a.startswith("-"):
        reject("허용 밖 옵션: %r (-h/-p/-n 만)" % (a,))
    if path is not None:
        reject("묶음 파일은 1개만: %r" % (a,))
    path = a; i += 1
if path is None:
    reject("사용법: ft-redis-read.sh [-h H] [-p P] [-n N] <묶음 파일>")

# 읽기 동사 목록 = 훅 파일에서 읽는다(복사 0)
hook = os.environ.get("FT_REDIS_READ_HOOK") or os.path.join(os.path.dirname(self), "..", "templates", "hooks", "block-destructive.sh")
try:
    txt = open(hook, encoding="utf-8").read()
    m = re.search(r"^INJECT_READ_VERBS='([^']+)'$", txt, re.M)
    if not m:
        reject("읽기 동사 목록을 훅 파일에서 못 읽음")
    verbs = m.group(1)
except OSError as e:
    reject("훅 파일을 못 읽음: %s" % e)
one = set(v for v in verbs.split("|") if " " not in v)
two = set(tuple(v.split()) for v in verbs.split("|") if len(v.split()) == 2)
if not one:
    reject("읽기 동사 목록이 비었음")

# 파일을 «한 번» 읽는다 — 이후 판정도 실행도 이 바이트만 쓴다(다시 열지 않는다)
try:
    if not os.path.isfile(path) or os.path.islink(path):
        reject("일반 파일이 아님: %s" % path)
    if os.path.getsize(path) > 1024 * 1024:
        reject("1 MiB 상한 초과: %s" % path)
    data = open(path, "rb").read()
    text = data.decode("utf-8")
except OSError as e:
    reject("파일을 못 읽음: %s" % e)
except UnicodeDecodeError:
    reject("UTF-8 이 아님: %s" % path)
lines = text.splitlines()
if len(lines) > 10000:
    reject("1만 줄 상한 초과: %d 줄" % len(lines))
n = 0
for ln in lines:
    s = ln.strip()
    if not s or s.startswith("#"):
        continue
    up = [x.upper() for x in s.split()[:2]]
    if up[0] in one or (len(up) == 2 and tuple(up) in two):
        n += 1; continue
    reject("읽기 목록 밖 동사: %s" % s.split()[0][:32])
if not n:
    reject("읽을 줄이 없음(빈 묶음): %s" % path)

# 원장 1줄 — 내용 0 · 사후 대조용(경로·줄수·sha256 앞16)
log = os.environ.get("FT_REDIS_READ_LOG") or os.path.join(os.path.expanduser("~"), ".claude", "logs", "redis-read.log")
try:
    os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "a", encoding="utf-8") as f:
        f.write("%s path=%s lines=%d sha256=%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), path, n, hashlib.sha256(data).hexdigest()[:16]))
except OSError as e:
    sys.stderr.write("WARN ft-redis-read — 원장 기록 실패: %s\n" % e)

cli = os.environ.get("FT_REDIS_CLI") or "redis-cli"
sys.stderr.write("OK ft-redis-read — %s lines=%d sha256=%s\n" % (path, n, hashlib.sha256(data).hexdigest()[:16]))
try:
    p = subprocess.run([cli] + opts, input=data)   # 판정한 그 바이트를 그대로 표준입력으로
except OSError as e:
    reject("redis-cli 실행 실패: %s" % e)
sys.exit(p.returncode)
PY
