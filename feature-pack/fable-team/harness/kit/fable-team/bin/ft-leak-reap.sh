#!/bin/bash
# ft-leak-reap.sh — 좌석이 뿌린 «유출 부하 프로세스» 안전망 (R347 · BYZ 수입본)
#
# 상류: ai-feature-pack feature-pack/fable-team/skill/scripts/ft-leak-reap.sh @ 819dd4e (콘텐츠 sha256 = 카드 R347 상태 절 · LIVE-MAP 행)
# ★상류와 다른 «4개 안전 변경 항목»★ — 판정(부하 시그니처 ∧ PPID=1 ∧ 누적 CPU ≥ MIN_CPU(30s) ∧ 보호 exe 제외)은 상류 그대로
#   ① 조사 실패 = exit 20 + stderr «ft-leak-reap: ERROR …» 1줄(python3 없음 · ps rc≠0 · ps timeout · 스냅샷 읽기·쓰기·파싱·신선도 · 예외) — 상류는 exit 0 이라 유출 0 과 구분이 안 됐다(#0 RULE). traceback 0
#   ② ps 입력 계약: FT_PS_SNAPSHOT=<파일> 이 있으면 그 파일만(자기 ps 폴백 0), 없으면 자기 ps 1회. 필드 7 = pid ppid pgid lstart time stat command (LC_ALL=C).
#      생산(--snapshot)·소비가 같은 검증 — lstart 5토큰 형식·time·stat·빈 표 · 소비는 신선도(FT_PS_SNAPSHOT_MAX_AGE 120s)까지. 생산 실패 = 기존 출력 파일·임시 파일 삭제 + rc20
#   ③ ps 호출 timeout 7초 — FT_PS_TIMEOUT 은 7 이하만(초과 주입 = 7 로 제한 + stderr WARN 1줄) · 대역 주입 FT_PS_CMD(시험 전용)
#   ④ 사건 지문 fp = 후보 (pid|lstart) 집합 sha1 앞 8자 — 틱 경보 중복 억제 단위 · 신규 --snapshot 발행 동작
# 판정이 좁은 이유: «고아 + 누적 CPU» 만으로 찾으면 launchd 데몬(logd·mds…)이 전부 PPID=1 이라 오탐 사살 — 시그니처 필수.
#
# Usage: ft-leak-reap.sh [--kill] [--dry-run] [--min-cpu=N] [--quiet] [--json] | --snapshot=<파일>
#   기본 = dry-run. --kill 이 있어야 종료(TERM → 1s → KILL) — ★틱은 --kill 을 부르지 않는다(사살 실행자 = 머신 launchd 가드 1)★
#   --snapshot=<파일> = ps 1회를 그 파일에 쓰고 끝(틱이 루프당 1회 만들어 소비자들이 FT_PS_SNAPSHOT 으로 공유 · 실패 시 파일을 남기지 않는다)
# exit: 0 = 유출 0 또는 정리 완료 · 10 = dry-run 발견 · 20 = 조사 실패 · 2 = usage
set -u

MODE=dry; MIN_CPU=30; QUIET=0; JSON=0; SNAP_OUT=""
for a in "$@"; do case "$a" in
  --kill)        MODE=kill ;;
  --dry-run)     MODE=dry ;;
  --quiet)       QUIET=1 ;;
  --json)        JSON=1 ;;
  --min-cpu=*)   MIN_CPU="${a#*=}" ;;
  --snapshot=*)  SNAP_OUT="${a#*=}" ;;
  -h|--help)     sed -n '2,19p' "$0"; exit 0 ;;
  *) echo "usage: $0 [--kill|--dry-run] [--min-cpu=N] [--quiet] [--json] | --snapshot=<파일>" >&2; exit 2 ;;
esac; done

PY="$(command -v python3 2>/dev/null || true)"
[ -n "$PY" ] || { echo "ft-leak-reap: ERROR python3 없음 — 조사 못 함" >&2; exit 20; }

# → stdout: 후보 TSV(pid \t lstart \t cpu초 \t 명령 앞 160자) + 끝줄 «#fp <8자>». 조사 실패 = exit 20(stderr 1줄).
found="$("$PY" - "$MIN_CPU" "$SNAP_OUT" <<'PY'
import hashlib, os, re, shlex, subprocess, sys, time

snap_out = sys.argv[2]
DEFAULT_PS = "ps -axo pid=,ppid=,pgid=,lstart=,time=,stat=,command="
SIGS = ("while :; do :; done", "while true; do :; done", "while [ 1 ]; do :; done", "while :;do :;done", "while true;do :;done")
PROTECT_EXE = {"cli-proxy-api", "headroom", "tmux", "tmux-server", "hermes", "launchd", "WindowServer", "login", "sshd", "python3"}
TIME_RE = re.compile(r"^(\d+-)?\d+:\d+(:\d+)?(\.\d+)?$")
LST_RE = re.compile(r"^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{1,2} \d{2}:\d{2}:\d{2} \d{4}$")
STAT_RE = re.compile(r"^[A-Z?][A-Za-z0-9<>+?]*$")   # '?' = 종료 중 프로세스 «(bash)» 행의 실제 stat(2026-10-18 실측)

def cleanup_out():   # 생산 실패 = 이전 출력·임시 파일을 유효 결과로 남기지 않는다
    for p in ((snap_out, f"{snap_out}.tmp{os.getpid()}") if snap_out else ()):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass
        except OSError as e:
            print(f"ft-leak-reap: ERROR 스냅샷 파일 삭제 실패 {p}: {e.strerror}", file=sys.stderr)

def die(msg):
    cleanup_out()
    print(f"ft-leak-reap: ERROR {msg}", file=sys.stderr)
    sys.exit(20)

def crash(t, v, tb):   # traceback 대신 표준 ERROR 1줄 + rc20
    cleanup_out()
    print(f"ft-leak-reap: ERROR 예외 {t.__name__}: {v}", file=sys.stderr)
    sys.stderr.flush()
    os._exit(20)
sys.excepthook = crash
mincpu = float(sys.argv[1])

def secs(t):
    day = 0.0
    if "-" in t:
        d, _, t = t.partition("-")
        day = float(d) * 86400
    total = 0.0
    for p in t.split(":"):
        total = total * 60 + float(p)
    return day + total

def parse(text):   # 생산·소비 공용 검증 — 못 읽는 행 하나라도 있으면 조사 실패
    rows = []
    for ln in text.splitlines():
        if not ln.strip():
            continue
        f = ln.strip().split(None, 10)
        if len(f) < 11 or not (f[0].isdigit() and f[1].isdigit() and f[2].isdigit() and TIME_RE.match(f[8]) and STAT_RE.match(f[9]) and LST_RE.match(" ".join(f[3:8]))):
            die(f"ps 행 파싱 실패(필드 7 계약 · LC_ALL=C 필요): {ln.strip()[:80]}")
        rows.append((int(f[0]), f[1], " ".join(f[3:8]), secs(f[8]), f[10]))
    if not rows:
        die("ps 표가 비어 있음")
    return rows

def read_ps():
    snap = os.environ.get("FT_PS_SNAPSHOT")
    if snap and not snap_out:
        try:
            age = time.time() - os.stat(snap).st_mtime
            text = open(snap, encoding="utf-8", errors="replace").read()
        except OSError as e:
            die(f"ps 스냅샷 읽기 실패 {snap}: {e.strerror}")
        if age > float(os.environ.get("FT_PS_SNAPSHOT_MAX_AGE", "120")):
            die(f"ps 스냅샷이 오래됨 {int(age)}s — 이전 루프 파일")
        return text
    limit = float(os.environ.get("FT_PS_TIMEOUT", "7"))
    if limit > 7:
        print(f"ft-leak-reap: WARN FT_PS_TIMEOUT={limit:g} 는 7초 상한 초과 → 7 로 제한", file=sys.stderr)
        limit = 7.0
    if limit <= 0:
        die(f"FT_PS_TIMEOUT={limit:g} 는 0 보다 커야 함")
    try:
        r = subprocess.run(shlex.split(os.environ.get("FT_PS_CMD") or DEFAULT_PS), capture_output=True, text=True, timeout=limit, env={**os.environ, "LC_ALL": "C"})
    except subprocess.TimeoutExpired:
        die("ps timeout")
    except Exception as e:
        die(f"ps 실행 실패: {e}")
    if r.returncode != 0:
        die(f"ps rc={r.returncode}")
    return r.stdout

text = read_ps()
table = parse(text)
if snap_out:
    tmp = f"{snap_out}.tmp{os.getpid()}"
    try:
        open(tmp, "w", encoding="utf-8").write(text)
        os.replace(tmp, snap_out)
    except OSError as e:
        die(f"스냅샷 쓰기 실패 {snap_out}: {e.strerror}")
    sys.exit(0)

rows, mine = [], os.getpid()
for pid, ppid, lstart, cpu, cmd in table:
    if pid == mine or ppid != "1":
        continue
    exe = os.path.basename(cmd.split()[0]) if cmd.split() else ""
    if exe in PROTECT_EXE or not any(s in cmd for s in SIGS):
        continue
    if cpu >= mincpu:
        rows.append((pid, lstart, cpu, cmd[:160]))
for pid, lstart, cpu, cmd in rows:
    print(f"{pid}\t{lstart}\t{int(cpu)}\t{cmd}")
if rows:
    print("#fp " + hashlib.sha1("\n".join(sorted(f"{p}|{s}" for p, s, _, _ in rows)).encode()).hexdigest()[:8])
PY
)"; prc=$?
[ "$prc" = 0 ] || exit 20
[ -z "$SNAP_OUT" ] || exit 0

fp="$(printf '%s\n' "$found" | sed -n 's/^#fp //p' | tail -1)"
found="$(printf '%s\n' "$found" | grep -v '^#fp ' || true)"
if [ -z "$found" ]; then
  [ "$JSON" = 1 ] && echo '{"leaked":0,"killed":0,"left":0}' || { [ "$QUIET" = 1 ] || echo "leak-reap: 유출 0"; }
  exit 0
fi
n="$(printf '%s\n' "$found" | grep -c .)"

if [ "$MODE" = dry ]; then
  if [ "$JSON" = 1 ]; then
    printf '%s\n' "$found" | "$PY" -c 'import json,sys
rows=[l.rstrip("\n").split("\t",3) for l in sys.stdin if l.strip()]
print(json.dumps({"leaked":len(rows),"killed":0,"rows":[{"pid":int(r[0]),"lstart":r[1],"cpu_s":int(r[2]),"cmd":r[3]} for r in rows]},ensure_ascii=False))'
  else
    printf '%s\n' "$found" | while IFS=$'\t' read -r pid lstart cpu cmd; do
      echo "leak-reap: [dry] 유출 후보 pid=$pid start=\"$lstart\" cpu=${cpu}s cmd=${cmd}"
    done
    echo "leak-reap: 유출 ${n}건 fp=${fp} — 정리하려면 --kill(머신 가드 소관)"
  fi
  exit 10
fi

# ── 실제 정리(머신 launchd 가드 전용): TERM → 1s → KILL, 신호 뒤 생존으로 killed/left 를 센다 ──
pids=""
while IFS=$'\t' read -r pid lstart cpu cmd; do
  [ -n "${pid:-}" ] || continue
  kill -TERM "$pid" 2>/dev/null && echo "leak-reap: TERM pid=$pid cpu=${cpu}s cmd=${cmd}"
  pids="$pids $pid"
done <<< "$found"
sleep 1
for pid in $pids; do
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null && echo "leak-reap: KILL pid=$pid (TERM 무시 — 루프가 시그널을 삼켰다)"
  fi
done

killed=0; left=0
for pid in $pids; do
  if kill -0 "$pid" 2>/dev/null; then left=$((left+1)); else killed=$((killed+1)); fi
done
echo "leak-reap: 정리 ${killed}건 · 잔여 ${left}건 (대상 ${n}건)"

[ "$JSON" = 1 ] && echo "{\"leaked\":$n,\"killed\":$killed,\"left\":$left}" || true
exit 0
