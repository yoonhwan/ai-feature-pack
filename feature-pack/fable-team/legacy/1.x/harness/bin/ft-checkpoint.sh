#!/usr/bin/env bash
# ft-checkpoint.sh <증거폴더> [--seat <좌석>] [--prev <앞 회차 표/json>]
#   Seatbelt 1.0.2 · press/시험 한 회차가 끝난 «직후» 프로젝트가 선언한 checkpoint 를 돌려 고정 칸 표를 남긴다.
#   값 해석·VALID 판정은 하지 않는다 — 표와 경보 exit 만 낸다(SEATBELT.md §6-2).
#   설정 = <리포 루트>/.fable-team/checkpoint.json (FT_CHECKPOINT_JSON 로 교체):
#     {"command":"python3 tools/ckpt.py {evid} --prev {prev}", "alarm_exit":3, "table":"{evid}/checkpoint.md",
#      "required_cells":["완료","교정","sealed"]}      ← {evid}·{prev} 는 셸 인용되어 치환된다
#   exit 0 = 경보 없음 · <alarm_exit> = checkpoint 경보(VALID/완료 보고 금지) · 4 = 표 없음/필수 칸 누락/명령 실패
#        2 = usage · 5 = «미설정» (경고 — 무음 통과 금지 · #0 RULE)
#   표준 출력 1줄: CHECKPOINT table=<경로> exit=<n> alarm=<yes|no|unset|broken> seat=<좌석>
#   마지막 결과는 <루트>/.fable-team/checkpoint/<좌석>.last(JSON) — ft-nano-close.sh 가 읽는다.
set -uo pipefail
EVID="${1:-}"; shift || { echo "usage: $0 <증거폴더> [--seat <좌석>] [--prev <경로>]" >&2; exit 2; }
SEAT="${FT_SEAT:-}"; PREV=""
while [ $# -gt 0 ]; do case "$1" in --seat) SEAT="$2"; shift 2;; --prev) PREV="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
[ -d "$EVID" ] || { echo "usage: 증거폴더 없음: $EVID" >&2; exit 2; }
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
CFG="${FT_CHECKPOINT_JSON:-$ROOT/.fable-team/checkpoint.json}"
[ -n "$SEAT" ] || SEAT="$([ -n "${TMUX_PANE:-}" ] && tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)"
SEAT="${SEAT:-unknown}"
STATE="$ROOT/.fable-team/checkpoint"; mkdir -p "$STATE"
export FT_CP_EVID="$(cd "$EVID" && pwd)" FT_CP_PREV="$PREV" FT_CP_SEAT="$SEAT" FT_CP_CFG="$CFG" FT_CP_WT="$WT" FT_CP_STATE="$STATE/${SEAT//\//_}.last"
python3 - <<'PY'
import json, os, shlex, subprocess, sys, time
e = os.environ
evid, prev, seat, cfg, wt, state = (e[k] for k in ("FT_CP_EVID", "FT_CP_PREV", "FT_CP_SEAT", "FT_CP_CFG", "FT_CP_WT", "FT_CP_STATE"))

def finish(code, alarm, table="", note=""):
    print(f"CHECKPOINT table={table or '-'} exit={code} alarm={alarm} seat={seat}" + (f" note={note}" if note else ""))
    json.dump({"seat": seat, "evid": evid, "table": table, "exit": code, "alarm": alarm, "note": note,
               "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z")}, open(state, "w", encoding="utf-8"), ensure_ascii=False)
    sys.exit(code)

if not os.path.isfile(cfg):
    print(f"WARN checkpoint 미설정: {cfg} 없음 — 이 프로젝트는 회차 고정 칸을 안 돌린다(SEATBELT.md §6-2 · update.md 적용 3줄)", file=sys.stderr)
    finish(5, "unset", note="no_config")
c = json.load(open(cfg, encoding="utf-8"))
sub = {"evid": shlex.quote(evid), "prev": shlex.quote(prev) if prev else "''"}
def fill(s, vals):        # str.format 은 셸의 ${VAR:-x} 중괄호를 깨므로 두 토큰만 치환한다
    return s.replace("{evid}", vals["evid"]).replace("{prev}", vals["prev"])
cmd = fill(c["command"], sub)
alarm_exit = int(c.get("alarm_exit", 3))
table = fill(c.get("table", "{evid}/checkpoint.md"), {"evid": evid, "prev": prev})
r = subprocess.run(["bash", "-c", cmd], cwd=wt, capture_output=True, text=True)
sys.stderr.write(r.stderr)
sys.stdout.write(r.stdout)
if r.returncode not in (0, alarm_exit):
    finish(4, "broken", table, f"command_exit_{r.returncode}")
if not os.path.isfile(table):
    finish(4, "broken", table, "table_missing")
text = open(table, encoding="utf-8").read()
missing = [k for k in c.get("required_cells", []) if k not in text]
if missing:
    finish(4, "broken", table, "cells_missing:" + ",".join(missing))
finish(r.returncode, "yes" if r.returncode == alarm_exit else "no", table)
PY
