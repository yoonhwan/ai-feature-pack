#!/bin/bash
# ft-leak-reap.sh — 좌석이 뿌린 «유출 부하 프로세스» 안전망 (Seatbelt 1.0.1)
#
# ★왜 있나 (2026-10-17 실사고)★
#   harness-ops 좌석이 부하 테스트를 이렇게 돌렸다:
#     export LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1
#     PIDS=""; for i in $(seq 1 42); do (while :; do :; done) & PIDS="$PIDS $!"; done
#     trap 'kill $PIDS' EXIT
#     timeout 120 .venv/bin/python -m pytest -q ... test_*_real_redis_worker_kill.py
#   정리를 EXIT trap 에 맡겼는데, 하네스가 셸을 SIGKILL 로 끝내자 trap 이 발화하지 않았다
#   ★SIGKILL 에는 EXIT trap 이 돌지 않는다★ → busy-loop 42개가 PPID=1 로 영구 유출(각 25~42% CPU).
#   결과: load avg 151(14코어) → cliproxy :8317 기아·무응답 · headroom /health 7초 → 전 프로젝트 정지.
#   ⇒ «정리를 trap 에만 의존하지 않는다» 가 규율이고, 이 스크립트가 그 안전망이다.
#
# 판정(좁게 — 오탐 방지): ① 명령줄에 부하 시그니처 ② PPID=1(고아) ③ 누적 CPU ≥ --min-cpu(기본 30s)
#   ★고아가 아니면 건드리지 않는다★ — 부모가 살아 있으면 아직 정리될 수 있는 정상 부하다.
#   실행파일 이름이 보호 목록(cli-proxy-api/headroom/tmux/hermes/…)이면 제외한다.
#
# Usage: ft-leak-reap.sh [--kill] [--dry-run] [--min-cpu=N] [--aggressive] [--quiet] [--json]
#   기본 = dry-run(찾기만). --kill 이 있어야 실제 종료(TERM → 1s → KILL).
#   --quiet 는 «유출 0» 줄을 숨긴다(틱 배선용 — 유출 있을 때만 시끄럽다).
#   --aggressive = 시그니처 없이도 고아 셸이 min-cpu 이상 태우면 포함(실험적 · 기본 off).
# exit: 0 = 유출 0 또는 정리 완료 · 10 = dry-run 에서 유출 발견 · 2 = usage
#
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ft-leak-reap.sh★
#   호출원: ft-tick.sh pass() (매 루프 · --kill). 수동 진단: ft-leak-reap.sh (dry-run 기본).
set -u

MODE=dry; MIN_CPU=30; QUIET=0; JSON=0; AGGR=0
for a in "$@"; do case "$a" in
  --kill)        MODE=kill ;;
  --dry-run)     MODE=dry ;;
  --quiet)       QUIET=1 ;;
  --json)        JSON=1 ;;
  --aggressive)  AGGR=1 ;;
  --min-cpu=*)   MIN_CPU="${a#*=}" ;;
  -h|--help)     sed -n '2,26p' "$0"; exit 0 ;;
  *) echo "usage: $0 [--kill|--dry-run] [--min-cpu=N] [--aggressive] [--quiet] [--json]" >&2; exit 2 ;;
esac; done

PY="$(command -v python3 2>/dev/null || true)"
[ -n "$PY" ] || { echo "ft-leak-reap: python3 없음" >&2; exit 0; }

# → TSV: pid \t cpu초 \t 명령(앞 160자). 유출 0 이면 빈 출력.
found="$("$PY" - "$MIN_CPU" "$AGGR" <<'PY'
import os, subprocess, sys

mincpu = float(sys.argv[1])
aggressive = (sys.argv[2] == "1")

# 부하 시그니처 — 실사고 명령 그대로 + 통상 변형.
SIGS = (
    "while :; do :; done",
    "while true; do :; done",
    "while [ 1 ]; do :; done",
    "while :;do :;done",
    "while true;do :;done",
)
# 실행파일 basename 기준 보호 목록(명령줄 전체가 아니라 exe 로 판정 — 유출 셸의 cmdline 에는
#   pytest/python/claude 경로가 «문자열로» 들어있어 전체 매칭은 오탐/미탐을 만든다).
PROTECT_EXE = {
    "cli-proxy-api", "headroom", "tmux", "tmux-server", "hermes",
    "launchd", "WindowServer", "login", "sshd", "python3",
}

def secs(t: str) -> float:
    """ps -o time 형식([DD-]HH:MM:SS 또는 MM:SS[.ss]) → 초."""
    day = 0.0
    if "-" in t:
        d, _, t = t.partition("-")
        try:
            day = float(d) * 86400
        except ValueError:
            return 0.0
    total = 0.0
    for p in t.split(":"):
        try:
            total = total * 60 + float(p)
        except ValueError:
            return 0.0
    return day + total

try:
    out = subprocess.run(
        ["ps", "-Ao", "pid=,ppid=,time=,command="],
        capture_output=True, text=True, timeout=20,
    ).stdout
except Exception:
    sys.exit(0)

mine = os.getpid()
rows = []
for ln in out.splitlines():
    f = ln.strip().split(None, 3)
    if len(f) < 4:
        continue
    pid_s, ppid_s, time_s, cmd = f
    try:
        pid = int(pid_s)
    except ValueError:
        continue
    if pid == mine:
        continue
    # ② 고아만 — 부모가 살아 있으면 정리될 수 있는 정상 부하다(기본).
    if ppid_s != "1":
        continue
    # exe 보호
    exe = os.path.basename(cmd.split()[0]) if cmd.split() else ""
    if exe in PROTECT_EXE:
        continue
    # ① 시그니처 (--aggressive 면 고아 셸이면 시그니처 없이도 후보)
    if not any(s in cmd for s in SIGS):
        if not aggressive:
            continue
    cpu = secs(time_s)
    # ③ 누적 CPU 하한
    if cpu < mincpu:
        continue
    rows.append((pid, cpu, cmd[:160]))

for pid, cpu, cmd in rows:
    print(f"{pid}\t{int(cpu)}\t{cmd}")
PY
)" || true

if [ -z "$found" ]; then
  [ "$JSON" = 1 ] && echo '{"leaked":0,"killed":0,"left":0}' || { [ "$QUIET" = 1 ] || echo "leak-reap: 유출 0"; }
  exit 0
fi

n="$(printf '%s\n' "$found" | grep -c . )"

if [ "$MODE" = dry ]; then
  if [ "$JSON" = 1 ]; then
    printf '%s\n' "$found" | "$PY" -c 'import json,sys
rows=[l.rstrip("\n").split("\t",2) for l in sys.stdin if l.strip()]
print(json.dumps({"leaked":len(rows),"killed":0,"rows":[{"pid":int(r[0]),"cpu_s":int(r[1]),"cmd":r[2]} for r in rows]},ensure_ascii=False))'
  else
    printf '%s\n' "$found" | while IFS=$'\t' read -r pid cpu cmd; do
      echo "leak-reap: [dry] 유출 후보 pid=$pid cpu=${cpu}s cmd=${cmd}"
    done
    echo "leak-reap: 유출 ${n}건 — 정리하려면 --kill"
  fi
  exit 10
fi

# ── 실제 정리: TERM → 1s → KILL, 그리고 결과를 «정직하게» 보고한다 ──
#   TERM 성공만 보고하면 이미 죽은 것을 못 세고(빈 로그), KILL 성공만 보고하면 TERM 으로 죽은 것을 못 센다.
#   ⇒ 신호 후 실제 생존으로 killed/left 를 센다(틱 로그에 근거가 남아야 한다).
pids=""
while IFS=$'\t' read -r pid cpu cmd; do
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
