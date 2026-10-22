#!/bin/bash
# ft-idle-wake — 유휴 좌석 깨우기 (R241c · DESIGN-r241-desk-never-stall §9) · launchd StartInterval 60 · 판정 876(오빠 입력 절단 0) 유지
# 왜: 받는 쪽이 «스스로 읽는다» 는 전제(틱 좌석 quiet · planner 는 doorbell 0)가 깨지면(Monitor 꺼짐·유휴) 쪽지가 영구 대기한다.
# 매 실행, mbox 큐에서 pending 이 있는 좌석마다 — 넷이 모두 «확인됨» 일 때만 `mbox.sh ring <좌석> <seq>` 1회:
#   ① 가장 오래된 미읽음 ≥ FT_IDLE_WAKE_SEC(180)  ② 좌석 jsonl 턴 상태 = IDLE(ft-seat-status.sh turn · 스피너 0)
#   ③ 그 세션에 붙은 tmux 클라이언트 중 now−client_activity ≤ FT_IDLE_CLIENT_SEC(120) 없음(오빠가 그 화면에서 치는 중이면 깨우지 않는다)
#   ④ 같은 (좌석, 가장 오래된 seq) 로 이미 깨운 적 없음(상태 .fable-team/state/idle-wake.json · 선점 기록 attempt → ring → done|failed|unsure)
# 조회가 하나라도 «모름»(상태 조회 실패·세션 없음·tmux 실패) = 깨우지 않음 + 로그 1줄(좌석·seq 당 1회) — 오입력보다 지연. ring 은 큐에 안 쌓는다.
# ★직렬화(DA⑥ H4)★: 상태 파일 옆 flock -n — 이미 다른 실행이 돌면 이 실행은 조용히 종료 0. 상태 JSON 이 있는데 못 읽으면 ring 0 + stderr ERROR + rc 4(빈 상태로 덮지 않는다).
#   명시 실패(mbox rc≠0)는 다음 실행에 재시도 · 결과 불명(예외·시간 초과)·attempt 로 남은 것은 재전송 0(unsure).
# ★입력 보호의 한계(DA⑥ H3)★: ring 직전에 client_activity 를 «한 번 더» 읽어 최근 키면 보류한다. 그 재확인~mbox 의 send-keys 사이(수 ms)는 «0 보장 아님 · 창을 최소화» 한 것이다.
# 환경: FT_ROOT · FT_MBOX · FT_SEAT_STATUS · FT_TMUX(기본 tmux) · FT_IDLE_WAKE_NOW(시험 시계) · FT_IDLE_WAKE_LOG. 외부 호출 0 · 상주 메모리 0.
set +e
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${FT_ROOT:-}" ]; then
  FT_ROOT="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE")"   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
  [ -n "$FT_ROOT" ] || { echo "ft-idle-wake: 루트를 못 찾음" >&2; exit 1; }
fi
export FT_ROOT HERE
python3 - <<'PYEOF'
import fcntl, json, os, shlex, subprocess, sys, time

ROOT, HERE = os.environ["FT_ROOT"], os.environ["HERE"]
COMM = os.path.join(ROOT, ".fable-team", "comm")
STATE_DIR = os.path.join(ROOT, ".fable-team", "state")
STATE = os.path.join(STATE_DIR, "idle-wake.json")
LOG = os.environ.get("FT_IDLE_WAKE_LOG") or os.path.join(STATE_DIR, "idle-wake.log")
MBOX = os.environ.get("FT_MBOX") or os.path.join(COMM, "mbox.sh")
STATUS = os.environ.get("FT_SEAT_STATUS") or os.path.join(HERE, "ft-seat-status.sh")
TMUX = shlex.split(os.environ.get("FT_TMUX") or "tmux")
WAKE_SEC = int(os.environ.get("FT_IDLE_WAKE_SEC") or 180)
CLIENT_SEC = int(os.environ.get("FT_IDLE_CLIENT_SEC") or 120)
NOW = float(os.environ.get("FT_IDLE_WAKE_NOW") or time.time())


def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(NOW)) + f" ft-idle-wake: {msg}\n")


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True, timeout=30)


def oldest_per_seat():
    """{좌석: (가장 오래된 행의 seq, 대기초)} — 큐(mailbox.jsonl)만 본다. 큐 파일 없음 = 아무것도 안 한다."""
    path = os.path.join(COMM, "mailbox.jsonl")
    if not os.path.exists(path):
        log("mailbox.jsonl 없음 — 깨우기 0")
        return {}
    out = {}
    with open(path, encoding="utf-8") as f:
        for ln in f:
            try:
                r = json.loads(ln)
                age = NOW - time.mktime(time.strptime(r["ts"], "%Y-%m-%dT%H:%M:%S"))
                if r["to"] not in out or age > out[r["to"]][1]:
                    out[r["to"]] = (int(r["seq"]), age)
            except (ValueError, KeyError, TypeError):
                continue
    return out


def typing_recently(seat):
    """(최근 키 있나, 사유) — 조회 실패는 (True, 사유): 모름 = 깨우지 않는다."""
    if run([*TMUX, "has-session", "-t", f"={seat}"]).returncode != 0:
        return True, "tmux 세션 없음"
    c = run([*TMUX, "list-clients", "-t", f"={seat}", "-F", "#{client_activity}"])
    if c.returncode != 0:
        return True, f"tmux list-clients 실패 rc={c.returncode}"
    return any(NOW - int(a) <= CLIENT_SEC for a in c.stdout.split()), None


def idle_and_unwatched(seat):
    """(깨워도 되나, 사유) — 모름은 False + 사유."""
    p = run(["bash", STATUS, "turn", seat])
    state = p.stdout.split()[0] if p.returncode == 0 and p.stdout.split() else ""
    if not state or state == "UNKNOWN":
        return False, f"좌석 상태 조회 실패/UNKNOWN rc={p.returncode}"
    if state != "IDLE":
        return False, None  # 바쁨·대기 중 — 조용히 다음 실행
    typing, why = typing_recently(seat)
    return (not typing), why  # 오빠가 그 화면에서 치는 중이면 why 없이 False — 절단 0


def save(st):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE + ".tmp", "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(STATE + ".tmp", STATE)


os.makedirs(STATE_DIR, exist_ok=True)
lock = open(os.path.join(STATE_DIR, "idle-wake.lock"), "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)  # 다른 실행이 돌고 있다 — 같은 seq 경합 0
try:
    with open(STATE, encoding="utf-8") as f:
        st = json.load(f)
    assert isinstance(st, dict)
except FileNotFoundError:
    st = {}
except (OSError, ValueError, AssertionError) as e:
    log(f"상태 파일 손상/읽기 실패 — ring 0: {type(e).__name__}")
    print(f"ERROR: ft-idle-wake 상태 파일을 읽지 못함({STATE}) — 덮어쓰지 않고 ring 0", file=sys.stderr)
    sys.exit(4)
for seat, (seq, age) in sorted(oldest_per_seat().items()):
    prev = st.get(seat)
    if age < WAKE_SEC or (isinstance(prev, dict) and prev.get("seq") == seq):
        continue
    try:
        ok, why = idle_and_unwatched(seat)
    except (subprocess.SubprocessError, OSError, ValueError) as e:
        ok, why = False, f"조회 예외 {type(e).__name__}"
    if why and st.get(seat + "!") != f"{seq}:{why}":
        log(f"{seat} seq={seq} 깨우지 않음 — {why}")
        st[seat + "!"] = f"{seq}:{why}"
    if not ok:
        continue
    typing, why = typing_recently(seat)  # ring 직전 재확인(H3) — 조회 뒤에 키가 들어왔으면 보류, 다음 실행에 다시 본다
    if typing:
        continue
    st[seat] = {"seq": seq, "result": "attempt"}  # 선점 기록(H4) — ring 도중 죽어도 같은 seq 를 다시 쏘지 않는다
    save(st)
    try:
        r = run(["bash", MBOX, "ring", seat, str(seq)])
        log(f"{seat} seq={seq} ring rc={r.returncode} {r.stdout.strip()[:80]}")
        st[seat]["result"] = "done" if r.returncode == 0 else "failed"
    except (subprocess.SubprocessError, OSError) as e:
        log(f"{seat} seq={seq} ring 결과 불명 {type(e).__name__} — 재전송 0")
        st[seat]["result"] = "unsure"
    if st[seat]["result"] == "failed":
        del st[seat]  # 명시 실패 — 다음 실행에 재시도
    save(st)
PYEOF
_pyrc=$?   # 깨우기(ring) 판정 rc — 아래 빈 석 장치가 이를 바꾸지 않는다(상태 손상 = 4 보존)
# ★빈 석 채우기 (r667)★ — 유휴 팀장에게 «빈 석 쪽지»(1단계) → 그래도 그대로면 자동 spawn(2단계). 별도 도구·별도 상태·별도 로그 — 이 장치의 실패가 깨우기(ring)를 되돌리지 않는다.
SLOT_LOG="${FT_IDLE_SLOT_LOG:-$FT_ROOT/.fable-team/state/idle-slot.log}"
mkdir -p "$(dirname -- "$SLOT_LOG")" 2>/dev/null
if [ -f "$HERE/ft-idle-slot-fill.sh" ]; then
  FT_IDLE_SLOT_LOG="$SLOT_LOG" bash "$HERE/ft-idle-slot-fill.sh" >>"$SLOT_LOG" 2>&1 || echo "ft-idle-wake: ft-idle-slot-fill rc=$? — 깨우기 결과는 그대로" >>"$SLOT_LOG"
else
  echo "ft-idle-wake: ft-idle-slot-fill.sh 없음 — 빈 석 채우기 0" >>"$SLOT_LOG"
fi
exit "$_pyrc"
