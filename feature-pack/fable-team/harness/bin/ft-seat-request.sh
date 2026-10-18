#!/usr/bin/env bash
# ft-seat-request.sh — 열린 Issue 를 team: 라벨로 묶고, 팀 오케 좌석이 없는 팀을 골라 planner 「좌석 필요」 값(본문)을 «출력만» 한다 (C19).
# 읽기 전용: gh 는 `issue list` 만 · tmux 는 list-sessions 만 · 명부는 열기만. 발신(mbox)·좌석 spawn·gh 쓰기 0.
#
# 사용: ft-seat-request.sh [--from-json <파일>]
#   --from-json : gh 대신 Issue JSON(`gh issue list --json number,title,labels` 형식)을 읽는다 (시험·재현용)
#   FT_SEATS_DIR 기본 = 메인 체크아웃의 .fable-team · FT_TMUX 기본 = tmux · FT_GH 기본 = gh
#   FT_SEAT_ROLES 기본 = master,orch,arch,architect  (팀 «오케 좌석»으로 세는 역할)
#
# 좌석 판정(팀 T): tmux 에 살아 있는 세션 중 ①이름 토큰(소문자, [-_#] 분리)에 T(별칭 포함)가 있고
#   ②명부(seats-*.json · seats.json)에 그 세션 행이 있으면 «행의 role» 이, 없으면 «이름 토큰» 이 오케 역할이어야 한다.
#   명부 행에 _replaced_by 가 있거나 role 이 stop-ready·stopped·closed 면 좌석이 아니다.
# 성공 stdout 마지막 줄: SEAT_REQUEST teams=N missing=K issues=M send=0   exit 0 · 실패(gh·tmux·명부 읽기) exit 1 · usage exit 2
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMMON="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)"   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
export FT_SEATS_DIR_X="${FT_SEATS_DIR:-$COMMON/.fable-team}"
export FT_TMUX_X="${FT_TMUX:-tmux}" FT_GH_X="${FT_GH:-gh}" FT_ROLES_X="${FT_SEAT_ROLES:-master,orch,arch,architect}"
export FT_FROM_JSON_X=""

while [ $# -gt 0 ]; do
  case "$1" in
    --from-json) FT_FROM_JSON_X="${2:-}"; [ -n "$FT_FROM_JSON_X" ] || { echo "REJECT --from-json 값 없음" >&2; exit 2; }; shift 2;;
    *) echo "usage: ft-seat-request.sh [--from-json <파일>]" >&2; exit 2;;
  esac
done
export FT_FROM_JSON_X
[ -d "$FT_SEATS_DIR_X" ] || { echo "REJECT 명부 디렉터리 없음: $FT_SEATS_DIR_X" >&2; exit 1; }

python3 - <<'PY'
import glob, json, os, re, subprocess, sys

seats_dir, tmux_bin, gh_bin = os.environ["FT_SEATS_DIR_X"], os.environ["FT_TMUX_X"], os.environ["FT_GH_X"]
roles = {r for r in os.environ["FT_ROLES_X"].split(",") if r}
from_json = os.environ["FT_FROM_JSON_X"]
ALIAS = {"shared-harness": "harness", "harness-ops": "harness"}  # team: 라벨 → 세션명 팀 토큰
DEAD = {"stop-ready", "stopped", "closed"}

def die(msg):
    print(f"REJECT {msg}", file=sys.stderr)
    sys.exit(1)

# 1 Issue — gh 는 읽기(list)만. GH_TOKEN 은 워크트리 gh 실패 함정(git-worktree-pitfalls #4)이라 뺀다.
if from_json:
    try:
        with open(from_json, encoding="utf-8") as fh:
            issues = json.load(fh)
    except (OSError, ValueError) as e:
        die(f"Issue JSON 읽기 실패 {from_json}: {e}")
else:
    env = {k: v for k, v in os.environ.items() if k != "GH_TOKEN"}
    r = subprocess.run([gh_bin, "issue", "list", "--state", "open", "--limit", "1000", "--json", "number,title,labels"],
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        die(f"gh issue list rc={r.returncode}: {r.stderr.strip()}")
    issues = json.loads(r.stdout)

by_team, no_team = {}, []
for it in issues:
    teams = [l["name"][5:] for l in it.get("labels", []) if l["name"].startswith("team:")]
    for t in teams:
        by_team.setdefault(t, []).append(it["number"])
    if not teams:
        no_team.append(it["number"])

# 2 명부 — 열기만. 같은 키는 먼저 본 행이 이긴다(ft-seat-live.sh 와 같은 순서).
files = [f for f in sorted(glob.glob(os.path.join(seats_dir, "seats-*.json"))) if re.fullmatch(r"seats-[^.]+\.json", os.path.basename(f))]
if os.path.isfile(os.path.join(seats_dir, "seats.json")):
    files.append(os.path.join(seats_dir, "seats.json"))
if not files:
    die(f"명부 파일 없음: {seats_dir}/seats*.json")
roster = {}
for f in files:
    try:
        with open(f, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as e:
        die(f"명부 읽기 실패 {f}: {e}")
    for key, row in doc.items():
        if not key.startswith("_") and isinstance(row, dict):
            roster.setdefault(key, row)

# 3 tmux — list-sessions 만. 서버 없음 = 세션 0, 그 밖의 오류는 실패.
r = subprocess.run([tmux_bin, "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True)
if r.returncode != 0 and not re.search(r"no server running|no sessions", r.stderr, re.I):
    die(f"tmux list-sessions rc={r.returncode}: {r.stderr.strip()}")
live = [n for n in r.stdout.splitlines() if n]

def orch_seat(name):
    tokens = set(re.split(r"[-_#]", name.lower()))
    row = roster.get(name)
    if row is not None:
        return not row.get("_replaced_by") and row.get("role") in roles and row.get("role") not in DEAD
    return bool(tokens & roles)

def seats_of(team):
    token = ALIAS.get(team, team)
    return [n for n in live if token in set(re.split(r"[-_#]", n.lower())) and orch_seat(n)]

# 4 표
rows = sorted(((t, nums, seats_of(t)) for t, nums in by_team.items()), key=lambda x: (-len(x[1]), x[0]))
print(f"{'팀':<18}{'열린 Issue':>10}  {'오케 좌석':<8} 좌석(살아 있는 것)")
for t, nums, seats in rows:
    print(f"{'team:'+t:<18}{len(nums):>10}  {'있음' if seats else '없음':<8} {', '.join(seats) if seats else '-'}")
if no_team:
    print(f"{'(team 라벨 없음)':<18}{len(no_team):>10}  -        #{', #'.join(map(str, sorted(no_team)))}")
missing = [(t, sorted(nums)) for t, nums, seats in rows if not seats]
total = sum(len(n) for _, n in missing)

# 5 planner 로 보낼 「좌석 필요」 본문 — 출력만(발신 0)
print("")
if not missing:
    print("좌석 필요 없음 — 열린 Issue 가 걸린 모든 팀에 오케 좌석이 있다.")
else:
    print("--- planner 로 보낼 본문 (출력만 · 발신 0) ---")
    print(f"[좌석 필요] 팀 오케 좌석 0 인 팀 {len(missing)}개 · Issue {total}건 — 개설 집행 = harness-ops")
    for t, nums in missing[:3]:
        shown = ",".join(f"#{n}" for n in nums[:25]) + (f" 외 {len(nums) - 25}건" if len(nums) > 25 else "")
        print(f"team:{t} {len(nums)}건: {shown}")
    if len(missing) > 3:
        rest = missing[3:]
        print(f"외 {len(rest)}팀 {sum(len(n) for _, n in rest)}건: " + ", ".join(f"team:{t}" for t, _ in rest))
    print("요청: harness-ops 가 팀 좌석을 열고 배분 쌍으로 넘긴다 (planner 는 좌석 개설 0 · SPEC-github-issue-driven §6-3 · Q2 A)")
print(f"SEAT_REQUEST teams={len(rows)} missing={len(missing)} issues={total} send=0")
PY
