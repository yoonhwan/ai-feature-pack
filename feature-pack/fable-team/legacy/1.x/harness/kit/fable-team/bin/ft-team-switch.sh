#!/usr/bin/env bash
# ft-team-switch.sh mark <팀> --h <번호> [--root <데이터루트>] [--by <좌석>]
#                   | unmark <팀> --h <번호> [--root <데이터루트>] [--by <좌석>]
#                   | status [<팀>] [--root <데이터루트>]
#   r1675 — 팀 단위 «2.0 으로 옮겼다» 표식 1파일. 표식이 있으면 1.x 쓰기 입구(ft20-switch-lib.sh 가드)가 쓰기 전에 멈춘다(rc3).
#   표식 = <데이터루트>/.fable-team/state/ft20-switch/<팀>.json (team · switched_at · h · by)
#   mark   : 이미 있으면 rc2 «이미 전환»(덮어쓰기 0) · --h 없으면 rc2 · 쓰기는 임시파일→rename(반쪽 0)
#   unmark : 표식을 «지우지 않는다» — <팀>.json.unmarked-<ts> 로 rename(하드 룰 2 · 되돌림 근거 보존) · 표식 없으면 rc2
#   status : <팀> 있으면 1줄 + rc0, 없으면 NOT-SWITCHED + rc1 · 팀 생략 = 표식 전부 1줄씩 rc0(0건이면 NO-SWITCH rc0)
#   실 팀에 쓰는 것은 전환 h(오빠 D) 뒤 master 만 — 이 도구는 쓰는 문만 만들고 스스로 쓰지 않는다.
#   rc 3 = 표식 파일을 못 읽음(판정 불가 · 하드 룰 20) · rc 2 = usage/이미 전환/표식 없음/데이터 루트 아님
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft20-switch-lib.sh"
USAGE="usage: $0 mark <팀> --h <번호> [--root <데이터루트>] [--by <좌석>] | unmark <팀> --h <번호> [--root <데이터루트>] | status [<팀>] [--root <데이터루트>]"
ACT="${1:-}"; [ -n "$ACT" ] || { echo "$USAGE" >&2; exit 2; }; shift || true
TEAM="${1:-}"; case "$TEAM" in ""|--*) TEAM="";; *) shift || true;; esac
H=""; ROOT_ARG=""; BY="${FT_SEAT_NAME:-${FT_SEAT:-}}"
while [ $# -gt 0 ]; do
  case "$1" in
    --h) H="${2:-}"; shift 2 || { echo "$USAGE" >&2; exit 2; };;
    --root) ROOT_ARG="${2:-}"; shift 2 || { echo "$USAGE" >&2; exit 2; };;
    --by) BY="${2:-}"; shift 2 || { echo "$USAGE" >&2; exit 2; };;
    *) echo "$USAGE" >&2; exit 2;;
  esac
done
case "$ACT" in mark|unmark|status) ;; *) echo "$USAGE" >&2; exit 2;; esac
[ "$ACT" = status ] && [ -z "$TEAM" ] || [ -n "$TEAM" ] || { echo "$USAGE — <팀> 필요" >&2; exit 2; }
[ -z "$TEAM" ] || [[ "$TEAM" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "REJECT 팀 이름 꼴 아님(^[a-z0-9][a-z0-9_-]*$): $TEAM" >&2; exit 2; }
if [ "$ACT" != status ]; then [[ "$H" =~ ^[0-9][0-9A-Za-z._-]*$ ]] || { echo "REJECT --h <번호> 필수(mark·unmark)" >&2; exit 2; }; fi
ROOT="${ROOT_ARG:-$(ft20_root_of . 2>/dev/null)}"
[ -n "$ROOT" ] || { echo "REJECT 데이터 루트 못 풂 — --root <데이터루트> 또는 git 리포 안에서" >&2; exit 2; }
ROOT="${ROOT%/}"; DIR="$(ft20_switch_dir "$ROOT")"
[ "$ACT" = status ] || [ -d "$ROOT/.fable-team" ] || { echo "REJECT 데이터 루트 아님(<데이터루트>/.fable-team 없음): $ROOT" >&2; exit 2; }
marker() { ft20_switch_marker "$ROOT" "$1"; }

case "$ACT" in
  mark)
    M="$(marker "$TEAM")"
    [ ! -e "$M" ] || { echo "REJECT 이미 전환 팀 $TEAM — 표식 있음 $M (덮어쓰기 0 · 되돌리려면 unmark)" >&2; exit 2; }
    mkdir -p "$DIR" || { echo "REJECT 표식 폴더 못 만듦: $DIR" >&2; exit 1; }
    TMP="$M.tmp-$$"
    python3 - "$TMP" "$TEAM" "$H" "${BY:-unknown}" <<'PY' || { rm -f "$TMP"; echo "REJECT 표식 쓰기 실패: $TMP" >&2; exit 1; }
import datetime, json, sys
p, team, h, by = sys.argv[1:5]
d = {"team": team, "switched_at": datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z"),
     "h": h, "by": by, "tool": "ft-team-switch.sh", "card": "r1675"}
open(p, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")
PY
    mv "$TMP" "$M" || { echo "REJECT 표식 rename 실패: $M" >&2; exit 1; }
    echo "MARKED $M team=$TEAM h=$H by=${BY:-unknown}"
    ;;
  unmark)
    M="$(marker "$TEAM")"
    [ -e "$M" ] || { echo "REJECT 표식 없음(전환 안 한 팀): $M" >&2; exit 2; }
    TS="$(date +%Y%m%dT%H%M%S)"; DST="$M.unmarked-$TS"
    mv "$M" "$DST" || { echo "REJECT 표식 rename 실패: $M → $DST" >&2; exit 1; }
    echo "UNMARKED $DST team=$TEAM h=$H by=${BY:-unknown}"
    ;;
  status)
    # 표식 1개를 1줄로 — 못 읽으면 UNREADABLE + rc3(판정 불가)
    show() { python3 - "$1" <<'PYS'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    print("UNREADABLE %s (%s)" % (sys.argv[1], e)); sys.exit(3)
print("SWITCHED team=%s switched_at=%s h=%s by=%s" % (d.get("team") or "?", d.get("switched_at") or "?", d.get("h") or "?", d.get("by") or "?"))
PYS
    }
    if [ -n "$TEAM" ]; then
      M="$(marker "$TEAM")"
      [ -e "$M" ] || { echo "NOT-SWITCHED team=$TEAM marker=$M"; exit 1; }
      show "$M" || exit 3; exit 0
    fi
    set -- "$DIR"/*.json; [ -e "$1" ] || { echo "NO-SWITCH 0 팀 (표식 없음: $DIR)"; exit 0; }
    for M in "$@"; do show "$M" || exit 3; done
    exit 0
    ;;
esac
