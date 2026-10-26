#!/bin/bash
# ft-leak-reap.sh — 좌석이 뿌린 «유출 부하 프로세스» 안전망 (R347 · BYZ 수입본)
#
# 상류: ai-feature-pack feature-pack/fable-team/skill/scripts/ft-leak-reap.sh @ 819dd4e (콘텐츠 sha256 = 카드 R347 상태 절 · LIVE-MAP 행)
# ★상류와 다른 «4개 안전 변경 항목»★ — 판정(부하 시그니처 ∧ PPID=1 ∧ 누적 CPU ≥ MIN_CPU(30s) ∧ 보호 exe 제외)은 상류 그대로
#   ① 조사 실패 = exit 20 + stderr «ft-leak-reap: ERROR …» 1줄(python3 없음 · ps rc≠0 · ps timeout · 스냅샷 읽기·쓰기·파싱·신선도 · 예외) — 상류는 exit 0 이라 유출 0 과 구분이 안 됐다(#0 RULE). traceback 0
#   ② ps 입력 계약: FT_PS_SNAPSHOT=<파일> 이 있으면 그 파일만(자기 ps 폴백 0), 없으면 자기 ps 1회. ★필드 5 = pid ppid lstart time command (LC_ALL=C · r670 — 판정에 쓰는 필드만: pgid·stat 은 판정에 안 쓴다)★
#      소비는 옛 판·ft-agent-alive 의 필드 7(pid ppid pgid lstart time stat command)도 읽는다(설치 직후 120s 안에 남은 옛 스냅샷이 «조사 실패»로 오판되지 않게). 긴 명령 줄은 앞 512자만 판정·출력에 쓴다.
#      생산(--snapshot)·소비가 같은 검증 — lstart 5토큰 형식·time·빈 표 · 소비는 신선도(FT_PS_SNAPSHOT_MAX_AGE 120s)까지. 생산 실패 = 기존 출력 파일·임시 파일 삭제 + rc20
#   ③ ps 호출 timeout 7초 — FT_PS_TIMEOUT 은 7 이하만(초과 주입 = 7 로 제한 + stderr WARN 1줄) · 대역 주입 FT_PS_CMD(시험 전용)
#      ★r670: 부하 꼭대기(load 98~122)에서 ps 1회가 7초를 넘겨 «조사 못 함»이 두 번 났다 — «첫 출력 전» 실패(timeout·출력 없는 rc≠0·실행 실패)만 1회 재시도한다(총 마감 2×7=14초 · 출력이 나온 뒤 실패는 재시도 0 — 같은 표를 두 번 읽는 것은 부하만 늘린다)★
#   ④ 사건 지문 fp = 후보 (pid|lstart) 집합 sha1 앞 8자 — 틱 경보 중복 억제 단위 · 신규 --snapshot 발행 동작
#   ⑤ r939 ⓔ — 승계(retire)가 «넘긴 작업»(ft-seat-reap --handover)이 영원히 남는 길을 본다: 재개 기록(ZC_RESUME_DIR · 기본 ~/.claude/state/seat-resume)/*.json 의
#      "handed" 칸에서 `at`(retire 시각) + FT_HANDOVER_REPORT_MIN(기본 70)분 초과 ∧ 그 pid 가 아직 살아 있으면 `handover-stale …` 1줄 보고.
#      ★죽이지 않는다(넘김은 머리 나쁜 게 아니다 — 사람·후계 판단) · 유출 수·killed·left·종료코드에 안 섬김(보고만)★
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
  -h|--help)     sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "usage: $0 [--kill|--dry-run] [--min-cpu=N] [--quiet] [--json] | --snapshot=<파일>" >&2; exit 2 ;;
esac; done

PY="$(command -v python3 2>/dev/null || true)"
[ -n "$PY" ] || { echo "ft-leak-reap: ERROR python3 없음 — 조사 못 함" >&2; exit 20; }
HERE0="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BGF0="$HERE0/ft-bg-finite.sh"
LDG0="${FT_BG_FINITE_LEDGER:-}"
if [ -z "$LDG0" ] && [ -f "$HERE0/ft-harness-root.sh" ]; then DR="$(. "$HERE0/ft-harness-root.sh" && ft_data_root "$HERE0" 2>/dev/null)" || DR=""; LDG0="${DR:+$DR/.fable-team/state/bg-finite.tsv}"; fi

# → stdout: 후보 TSV(pid \t lstart \t cpu초 \t 명령 앞 160자) + 끝줄 «#fp <8자>». 조사 실패 = exit 20(stderr 1줄).
found="$("$PY" - "$MIN_CPU" "$SNAP_OUT" "$LDG0" "$BGF0" <<'PY'
import datetime, glob, hashlib, json, os, re, shlex, subprocess, sys, time

snap_out, LEDGER, BGF = sys.argv[2], sys.argv[3], sys.argv[4]
DEFAULT_PS = "ps -axo pid=,ppid=,lstart=,time=,command="   # r670: 판정에 쓰는 필드만(pgid·stat 제거) — 부하 꼭대기의 ps 비용을 줄인다
CMD_MAX = 512        # 긴 명령 줄은 앞 512자만 판정·출력(스냅샷 파일은 ps 출력 그대로 쓴다)
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
        s = ln.strip()
        head = s.split(None, 3)
        if len(head) >= 3 and head[2].isdigit():     # 필드 7(옛 판·ft-agent-alive 계약) — pid ppid pgid lstart time stat command
            f = s.split(None, 10)
            if len(f) < 11 or not STAT_RE.match(f[9]):
                die(f"ps 행 파싱 실패(필드 7 · stat 열 · LC_ALL=C 필요): {s[:80]}")
            pid, ppid, lstart, t, cmd = f[0], f[1], " ".join(f[3:8]), f[8], f[10]
        else:                                        # 필드 5(r670 경량) — pid ppid lstart time command
            f = s.split(None, 8)
            if len(f) < 9:
                die(f"ps 행 파싱 실패(필드 5 계약 · LC_ALL=C 필요): {s[:80]}")
            pid, ppid, lstart, t, cmd = f[0], f[1], " ".join(f[2:7]), f[7], f[8]
        if not (pid.isdigit() and ppid.isdigit() and TIME_RE.match(t) and LST_RE.match(lstart)):
            die(f"ps 행 파싱 실패(필드 5 계약 · LC_ALL=C 필요): {s[:80]}")
        rows.append((int(pid), ppid, lstart, secs(t), cmd[:CMD_MAX]))
    if not rows:
        die("ps 표가 비어 있음")
    return rows

def read_ps():
    snap = os.environ.get("FT_PS_SNAPSHOT")
    if snap and not snap_out:   # 파일 읽기 = 재시도 0(r670)
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
    cmd = shlex.split(os.environ.get("FT_PS_CMD") or DEFAULT_PS)
    deadline, err = time.time() + 2 * limit, ""
    for attempt in (1, 2):   # 첫 출력 전 실패만 1회 더 본다(총 14초) — 두 번째도 실패하면 그대로 rc 20
        budget = max(min(limit, deadline - time.time()), 0.1)
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=budget, env={**os.environ, "LC_ALL": "C"})
        except subprocess.TimeoutExpired:
            err = "ps timeout"
            continue
        except Exception as e:
            err = f"ps 실행 실패: {e}"
            continue
        if r.returncode != 0:
            err = f"ps rc={r.returncode}"
            if (r.stdout or "").strip():
                die(err)   # 출력이 나왔다 = «첫 출력 전» 실패가 아니다(재시도 0)
            continue
        return r.stdout
    die(f"{err} — 재시도 1회 포함 2회 실패")

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

def stale_handed():   # r939 H3 — 장부의 «상한 지난 등록 줄» 보고(죽이지 않음) · 죽은 pid 줄은 지운다 · 줄 stale 표시
    if not LEDGER: return 0
    try: lines = open(LEDGER, encoding="utf-8").read().splitlines() if os.path.exists(LEDGER) else []
    except OSError as e:
        print(f"ft-leak-reap: WARN 장부 못 읽음 {LEDGER}: {e}", file=sys.stderr); return 0
    now, n, live, dead = time.time(), 0, {r[0] for r in table}, []
    stale = []
    for ln in lines:
        f = ln.split("\t")
        try: pid, until = int(f[1]), int(f[4])
        except (IndexError, ValueError): continue
        if pid not in live: dead.append(pid); continue      # 끝난 작업 — 줄을 지운다(영원히 남기지 않음)
        if until > now: continue                            # 상한 전 — 보고 0
        stale.append(pid)
        print(f"#handover-stale pid={pid} until={until} age={int((now - until) / 60)}m cmd={(f[6] if len(f) > 6 else '')[:100]}"); n += 1
    if dead or stale:
        if dead: bgf("prune", [str(p) for p in dead])
        if stale: bgf("stale", [str(p) for p in stale])
    return n
def bgf(mode, args):   # 장부 쓰기는 ft-bg-finite.sh 하나 — prune(죽은 줄) · stale(상한 지난 줄 표시)
    env = {**os.environ, "FT_BG_FINITE_LEDGER": LEDGER}
    try: r = subprocess.run(["bash", BGF, mode, *args], capture_output=True, text=True, timeout=7, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        print(f"ft-leak-reap: WARN 장부 {mode} 실패: {e}", file=sys.stderr); return
    if r.returncode != 0: print(f"ft-leak-reap: WARN 장부 {mode} rc={r.returncode}: {r.stderr.strip()[:160]}", file=sys.stderr)
stale_handed()
PY
)"; prc=$?
[ "$prc" = 0 ] || exit 20
[ -z "$SNAP_OUT" ] || exit 0

fp="$(printf '%s\n' "$found" | sed -n 's/^#fp //p' | tail -1)"
hst="$(printf '%s\n' "$found" | sed -n 's/^#handover-stale //p')"; hst="$(printf '%s\n' "$hst" | grep -v '^$' || true)"
found="$(printf '%s\n' "$found" | grep -v '^#' || true)"
hn=0; [ -z "$hst" ] || hn="$(printf '%s\n' "$hst" | grep -c .)"
if [ -n "$hst" ]; then   # r939 ⓔ — 보고만(신호 0) · 유출 수·killed·left·rc 에 안 섬김
  printf '%s\n' "$hst" | while IFS= read -r l; do echo "leak-reap: handover-stale $l — 죽이지 않음(넘긴 작업 · 사람·후계 판단)"; done
fi
if [ -z "$found" ]; then
  [ "$JSON" = 1 ] && echo "{\"leaked\":0,\"killed\":0,\"left\":0,\"handover_stale\":$hn}" || { [ "$QUIET" = 1 ] || echo "leak-reap: 유출 0"; }
  exit 0
fi
n="$(printf '%s\n' "$found" | grep -c .)"

if [ "$MODE" = dry ]; then
  if [ "$JSON" = 1 ]; then
    printf '%s\n' "$found" | "$PY" -c 'import json,sys
rows=[l.rstrip("\n").split("\t",3) for l in sys.stdin if l.strip()]
print(json.dumps({"leaked":len(rows),"killed":0,"rows":[{"pid":int(r[0]),"lstart":r[1],"cpu_s":int(r[2]),"cmd":r[3]} for r in rows],"handover_stale":int(sys.argv[1])},ensure_ascii=False))' "$hn"
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

[ "$JSON" = 1 ] && echo "{\"leaked\":$n,\"killed\":$killed,\"left\":$left,\"handover_stale\":$hn}" || true
exit 0
