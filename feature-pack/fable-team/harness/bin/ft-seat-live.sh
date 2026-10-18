#!/usr/bin/env bash
# ft-seat-live.sh — 살아 있는 tmux 세션 + 팀 설정 명부(seats-*.json · seats.json)를 합쳐 seats.live.json 을 만든다 (C2).
# 읽기 전용 생성기: tmux 는 list-* 만 · 입력 명부는 열기만 · 산출은 단일 쓰기(임시파일 → mv).
#
# 사용: ft-seat-live.sh [--out <경로>]
#   산출 기본 = <FT_STATE_DIR>/seats.live.json   (FT_STATE_DIR 기본 = <FT_SEATS_DIR>/state)
#   FT_SEATS_DIR 기본 = 메인 체크아웃의 .fable-team · FT_TMUX 기본 = tmux (시험용 대체 가능)
#   성공 stdout 한 줄: LIVE rows=N members=N tmux_total=T excluded=K out=<경로>   exit 0
#   검증 실패(행 수 ≠ 접두 세션 수 · 입력 읽기 실패 · tmux 오류) exit 1 (사유 stderr)
#
# 회원 판정: 세션명이 ①명부 어느 행의 베이스(#N 뗀 것)와 같거나 ②명부 구 문법 행의 팀 접두(ft-<팀>-)로 시작하거나
#   ③P6 문법(ft-name-lint)을 통과하면 회원.
#   그 밖(KakaoBot·tmm 등 동거 세션)은 excluded 로 파일에 이름만 남긴다.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMMON="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)"   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
SEATS_DIR="${FT_SEATS_DIR:-$COMMON/.fable-team}"
STATE_DIR="${FT_STATE_DIR:-$SEATS_DIR/state}"
TMUX_BIN="${FT_TMUX:-tmux}"
OUT="$STATE_DIR/seats.live.json"
ALIVE_BIN="${FT_AGENT_ALIVE_BIN:-$HERE/../comm/ft-agent-alive.sh}"   # R346 판정기 하나(전경 셸·정지 본체 = NOAGENT) — doorbell·틱과 같은 것

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "REJECT --out 값 없음" >&2; exit 2; }; shift 2;;
    *) echo "usage: ft-seat-live.sh [--out <경로>]" >&2; exit 2;;
  esac
done
[ -d "$SEATS_DIR" ] || { echo "REJECT 명부 디렉터리 없음: $SEATS_DIR" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
snap() { # tmux 목록 1회 스냅샷 → $T/$1 (서버 없음 = 세션 0 · 그 밖의 오류는 실패)
  local out="$1"; shift
  "$TMUX_BIN" "$@" >"$T/$out" 2>"$T/err"; local rc=$?
  if [ $rc -ne 0 ]; then
    grep -qi 'no server running\|no sessions' "$T/err" && : >"$T/$out" || { echo "REJECT tmux $* rc=$rc: $(cat "$T/err")" >&2; exit 1; }
  fi
}
snap sessions list-sessions -F '#{session_name}	#{session_created}	#{session_attached}'
snap panes list-panes -a -F '#{session_name}	#{pane_pid}'

mkdir -p "$(dirname "$OUT")" || exit 1
export FT_NAME_LINT="$HERE/ft-name-lint.sh" FT_SEATS_DIR_X="$SEATS_DIR" FT_TMUX_X="$TMUX_BIN" FT_SNAP="$T" FT_OUT="$OUT" FT_ALIVE_BIN_X="$ALIVE_BIN"

python3 - <<'PY'
import glob, json, os, re, subprocess, sys, tempfile, time

seats_dir, snap, out = os.environ["FT_SEATS_DIR_X"], os.environ["FT_SNAP"], os.environ["FT_OUT"]
lint, tmux_bin = os.environ["FT_NAME_LINT"], os.environ["FT_TMUX_X"]
alive_bin, alive_warned = os.environ["FT_ALIVE_BIN_X"], []

def die(msg):
    print(f"REJECT {msg}", file=sys.stderr)
    sys.exit(1)

def base_of(name):
    return name.rsplit("#", 1)[0]

# 입력 명부 — 열기만 한다. 파일 순서: seats-<팀>.json 이름순 → seats.json(v65). 같은 키는 먼저 본 행이 이긴다.
files = sorted(glob.glob(os.path.join(seats_dir, "seats-*.json")))
files = [f for f in files if re.fullmatch(r"seats-[^.]+\.json", os.path.basename(f))]
if os.path.isfile(os.path.join(seats_dir, "seats.json")):
    files.append(os.path.join(seats_dir, "seats.json"))
if not files:
    die(f"명부 파일 없음: {seats_dir}/seats*.json")
rows_cfg, bases, prefixes = {}, set(), set()
for f in files:
    try:
        with open(f, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as e:
        die(f"명부 읽기 실패 {f}: {e}")
    for key, row in doc.items():
        if key.startswith("_") or not isinstance(row, dict):
            continue
        bases.add(base_of(key))
        m = re.match(r"ft-[a-z0-9]+-", key)  # 구 문법 팀 계보 접두 — 명부에 행이 없는 같은 팀 세션도 회원으로 본다
        if m:
            prefixes.add(m.group(0))
        rows_cfg.setdefault(key, (os.path.basename(f), row))

def p6(name):  # P6 문법 통과 여부 + 토큰
    r = subprocess.run(["bash", lint, name], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    toks = base_of(name).split("-", 3)
    project, team, role = toks[0], toks[1], toks[2]
    tail = toks[3] if len(toks) > 3 else None
    return {"project": project, "team": team, "role": role, "agent": None if role == "nano" else tail}

def read_snap():
    ses, pids = {}, {}
    with open(os.path.join(snap, "sessions"), encoding="utf-8") as fh:
        for ln in fh.read().splitlines():
            p = ln.split("\t")
            if p[0]:
                ses[p[0]] = (p[1] if len(p) > 1 else "", p[2] if len(p) > 2 else "")
    with open(os.path.join(snap, "panes"), encoding="utf-8") as fh:
        for ln in fh.read().splitlines():
            p = ln.split("\t")
            if len(p) > 1 and p[0] not in pids:
                pids[p[0]] = p[1]
    return ses, pids

def is_member(name):
    return base_of(name) in bases or name.startswith(tuple(prefixes)) or p6(name) is not None

def agent_state(session):
    """(agent_alive, fg) — 판정기 ft-agent-alive.sh 1회(7초 룰: 좌석당 timeout 7). 판정 불가·판정기 없음·시간 초과 = (None, None) — 거짓 true/false 0."""
    if not os.path.isfile(alive_bin):
        if not alive_warned:
            alive_warned.append(1); print(f"WARN 판정기 없음 {alive_bin} — agent_alive 칸 null", file=sys.stderr)
        return None, None
    try:
        r = subprocess.run(["bash", alive_bin, session], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired):
        return None, None
    m = re.match(r"(ALIVE|NOAGENT) seat=\S+ fg=(\S*) ", r.stdout)
    return ((m.group(1) == "ALIVE"), m.group(2)) if m else (None, None)

sessions, pids = read_snap()
rows, excluded = [], []
for name in sorted(sessions):
    if not is_member(name):
        excluded.append(name)
        continue
    cfg_file, cfg = rows_cfg.get(name, (None, {}))
    parsed = p6(name)
    created, attached = sessions[name]
    alive, fg = agent_state(name) if name in pids else (None, None)
    rows.append({
        "session": name,
        "base": base_of(name),
        "gen": int(name.rsplit("#", 1)[1]) if re.search(r"#\d+$", name) else None,
        "grammar": "p6" if parsed else "legacy",
        "project": parsed["project"] if parsed else None,
        "team": parsed["team"] if parsed else None,
        "role": cfg.get("role") or (parsed["role"] if parsed else None),
        "agent": cfg.get("agent") or (parsed["agent"] if parsed else None),
        "model": cfg.get("model"),
        "state": "replaced" if cfg.get("_replaced_by") else None,
        "config_file": cfg_file,
        "pane_pid": int(pids[name]) if name in pids else None,
        "created": int(created) if created.isdigit() else None,
        "attached": int(attached) if attached.isdigit() else None,
        "agent_alive": alive,
        "fg": fg,
    })

doc = {
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "tmux_total": len(sessions), "members": len(rows), "excluded": excluded, "rows": rows,
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out) or ".", prefix=".seats.live.", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=1)
    fh.write("\n")
os.replace(tmp, out)

# 검증 — 산출을 다시 읽고 tmux 를 다시 떠서 「행 수 == 접두 세션 수」를 대조한다.
with open(out, encoding="utf-8") as fh:
    written = json.load(fh)["rows"]
r = subprocess.run([tmux_bin, "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True)
fresh = [n for n in r.stdout.splitlines() if n and is_member(n)] if r.returncode == 0 else []
names = [w["session"] for w in written]
if len(set(names)) != len(names):
    die("산출에 중복 세션 행")
if sorted(names) != sorted(fresh):
    die(f"행 수 {len(names)} ≠ 접두 세션 수 {len(fresh)} (그 사이 세션이 바뀌었거나 생성 오류) — 다시 실행")
print(f"LIVE rows={len(names)} members={len(fresh)} tmux_total={len(sessions)} excluded={len(excluded)} out={out}")
PY
