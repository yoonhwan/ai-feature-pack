#!/bin/bash
# ft-seats-lint.sh — tmux 세션 ↔ 명부(seats*.json) 대조 (PLAN-harness-networking D9 · N1 r-net-tick-line). 읽기만 · 쓰기 0 · 외부 호출 0.
# 추적 사본: scripts/fable-team-bin/ft-seats-lint.sh · 런타임 자리: <워크트리>/.fable-team/bin/ (gitignore)
#
# usage: ft-seats-lint.sh [--team <명부 파일>]
# 출력: 첫 줄 `불일치 N (UNKNOWN M)` + 행(ⓐ~ⓔ 불일치 · UNKNOWN 행 · OPENING 안내). rc 0 = N 도 M 도 0 · rc 1 = 아니면 · rc 2 = usage.
#   ⓐ 세션이 살아 있는데 활성 행이 없다 — 행 자체가 없거나, `_closed` 팀의 closed/stopped 행인데 `_kept` 가 아니다 (`_kept=true` 보존 좌석은 제외)
#   ⓑ `_master`/`_hil_route` 가 명부에 없음·은퇴(_replaced_by)·closed/stopped/stop-ready·세션 죽음 (`_closed` 팀은 건너뜀 ·
#      개설 중 빈 `_master` 는 `OPENING` 안내만, `_opened` 없이 명부 mtime 30분 넘으면 불일치)
#   ⓒ 활성 행(_replaced_by 없음 · role ∉ closed/stopped/stop-ready)인데 세션이 없다
#   ⓓ 계보(`#N` 앞)당 살아 있는 세션 > 2 — keep-last-2 초과, 가장 오래된 번호가 kill 후보(행에만 적는다 · 계획 파일·kill 0 — 좌석 kill 은 HIL)
#   ⓔ 같은 좌석 키가 명부 2개 이상 또는 한 파일 안 중복
#   ⓕ 명부 파싱 실패 = `UNKNOWN <파일>` (0 이 아니다)
# --team <파일>: ⓑⓒⓓ·ⓔ·ⓕ 는 그 명부만, ⓐ 는 `^(byz|ft)-<팀키>-` 세션만 (팀키 = 파일명의 seats- 뒤 · seats.json = v65).
#   tmux ls 를 못 읽으면(서버 없음 제외) 판정 불가 → `UNKNOWN tmux` 로 드러낸다 (빈 목록으로 접지 않는다).
# env: FT_ROOT · FT_SEATS_GLOB(기본 <루트>/.fable-team/seats*.json) · FT_TMUX_LS_CMD(기본 `tmux ls -F #{session_name}`) · FT_BOARD_NOW(ISO · 시험용)

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEAM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="${2:-}"; [ -n "$TEAM" ] || { echo "usage: $0 [--team <명부 파일>]" >&2; exit 2; }; shift 2 ;;
    *) echo "usage: $0 [--team <명부 파일>]" >&2; exit 2 ;;
  esac
done
if [ -z "${FT_ROOT:-}" ]; then
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && FT_ROOT="$(dirname "$common")"
fi
export FT_ROOT TEAM
export FT_SEATS_GLOB="${FT_SEATS_GLOB:-$FT_ROOT/.fable-team/seats*.json}"

python3 - <<'PY'
import datetime as dt
import glob
import json
import os
import re
import shlex
import subprocess
import sys
from collections import defaultdict

INACTIVE = {"closed", "stopped"}
PARKED = INACTIVE | {"stop-ready"}
OPENING_MAX_MIN = 30
team = os.environ.get("TEAM", "")
now = dt.datetime.fromisoformat(os.environ["FT_BOARD_NOW"]) if os.environ.get("FT_BOARD_NOW") else dt.datetime.now()
files = sorted(glob.glob(os.environ["FT_SEATS_GLOB"]))
scope = os.path.abspath(team) if team else None
rows, unknown = [], []


def load(path):
    dups = []

    def hook(pairs):
        seen = {}
        for k, v in pairs:
            if "#" in k and k in seen:
                dups.append(k)
            seen[k] = v
        return seen
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f, object_pairs_hook=hook)
    except (OSError, ValueError) as e:
        return None, dups, str(e)[:60]
    return (d, dups, "") if isinstance(d, dict) else (None, dups, "최상위가 객체가 아님")


def seat_rows(d):
    return {k: v for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)}


def tmux_alive():
    r = subprocess.run(shlex.split(os.environ.get("FT_TMUX_LS_CMD", "tmux ls -F #{session_name}")), capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        if "no server running" in r.stderr or "no sessions" in r.stderr:
            return set()
        raise RuntimeError(f"rc={r.returncode} {r.stderr.strip()[:60]}")
    return {s.strip() for s in r.stdout.splitlines() if s.strip()}


rosters = {}  # 파일 경로 → (dict, dups)
for p in files:
    d, dups, err = load(p)
    if d is None:
        if scope is None or os.path.abspath(p) == scope:
            unknown.append(f"UNKNOWN {os.path.basename(p)} ({err})")
        continue
    rosters[p] = (d, dups)
if scope and scope not in {os.path.abspath(p) for p in rosters} and not unknown:
    unknown.append(f"UNKNOWN {os.path.basename(scope)} (명부 파일을 찾을 수 없음)")
scoped = [p for p in rosters if scope is None or os.path.abspath(p) == scope]
key = ""
if scope:
    stem = os.path.basename(scope)[:-5]
    key = "v65" if stem == "seats" else stem.removeprefix("seats-")
prefix = re.compile(rf"^(byz|ft)-{re.escape(key)}-") if key else None

try:
    alive = tmux_alive()
except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
    print("불일치 0 (UNKNOWN %d)" % (len(unknown) + 1))
    print("  UNKNOWN tmux (%s)" % e)
    sys.exit(1)

rowed = defaultdict(list)  # 좌석 키 → [(파일, row, 명부 dict)]
for p, (d, dups) in rosters.items():
    for name, row in seat_rows(d).items():
        rowed[name].append((p, row, d))
    for name in set(dups):
        rows.append(("ⓔ", p, f"ⓔ {name} {os.path.basename(p)} 안에서 중복"))


def is_active(row):
    return not row.get("_replaced_by") and row.get("role") not in PARKED


for s in sorted(alive):
    if prefix and not prefix.match(s):
        continue
    hits = rowed.get(s)
    if not hits:
        rows.append(("ⓐ", None, f"ⓐ {s} 세션은 있는데 명부 행 없음"))
    elif all(d.get("_closed") and r.get("role") in INACTIVE and not r.get("_kept") for _, r, d in hits):
        rows.append(("ⓐ", None, f"ⓐ {s} 닫힌 팀의 행인데 보존(_kept) 표시 없이 세션이 살아 있음"))

for name, hits in sorted(rowed.items()):
    paths = sorted({h[0] for h in hits})
    if len(paths) > 1 and (scope is None or scope in {os.path.abspath(x) for x in paths}):
        rows.append(("ⓔ", None, f"ⓔ {name} " + ",".join(os.path.basename(x) for x in paths)))

for p in scoped:
    d, _ = rosters[p]
    for name, row in seat_rows(d).items():
        if is_active(row) and name not in alive:
            rows.append(("ⓒ", p, f"ⓒ {name} 활성 행(role={row.get('role')})인데 세션 없음"))
    if d.get("_closed"):
        continue
    for k in ("_master", "_hil_route"):
        if k not in d:
            continue
        v = d[k]
        if not v:
            if k == "_master" and not d.get("_opened"):
                age = int((now - dt.datetime.fromtimestamp(os.path.getmtime(p))).total_seconds() // 60)
                if age > OPENING_MAX_MIN:
                    rows.append(("ⓑ", p, f"ⓑ _master 비어 있음 · _opened 없이 {age}분 ({os.path.basename(p)})"))
                else:
                    rows.append(("OPENING", p, f"OPENING {os.path.basename(p)} _master 개설 중 ({age}분)"))
            continue
        target = [(r, dd) for pp, r, dd in rowed.get(v, [])]
        why = ""
        if not target:
            why = "명부에 행 없음"
        elif any(r.get("_replaced_by") for r, _ in target):
            why = "은퇴(_replaced_by)"
        elif any(r.get("role") in PARKED for r, _ in target):
            why = "role=" + target[0][0].get("role", "?")
        elif v not in alive:
            why = "세션 없음"
        if why:
            rows.append(("ⓑ", p, f"ⓑ {k} {v} {why}"))

lineage = defaultdict(list)
for s in alive:
    m = re.match(r"^(.*)#(\d+)$", s)
    if m and (not prefix or prefix.match(s)):
        lineage[m.group(1)].append((int(m.group(2)), s))
for lin, items in sorted(lineage.items()):
    if len(items) > 2:
        old = [s for _, s in sorted(items)[:-2]]
        rows.append(("ⓓ", None, f"ⓓ {lin} {len(items)} > 2 · keep-last-2 초과 · kill 후보 " + " ".join(old)))

n = sum(1 for r in rows if r[0] in "ⓐⓑⓒⓓⓔ")
print(f"불일치 {n} (UNKNOWN {len(unknown)})")
for r in rows:
    print("  " + r[2])
for u in unknown:
    print("  " + u)
sys.exit(0 if n == 0 and not unknown else 1)
PY
