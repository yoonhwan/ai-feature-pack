#!/usr/bin/env bash
# ft-index-gate.sh — ★동시에 열린 인덱스는 1개★ + ★오빠 확정 없이는 안 닫힌다★
#
# 왜 (오빠 확정 2026-09-22):
#   「멈추고 인터뷰하고 결론내고 넘어가야하는데 계속 뒤로 미루고 랜딩하면 다른이슈나오고
#    수정했는데 나랑 확정안하니 이게 빙글빙글 돌아가는것」
#
#   ★기전★: 확정 없이 다음으로 넘어가면, 랜딩마다 새 이슈가 나온다 — 앞 건이 «닫히지 않았기» 때문이다.
#   ★그리고 동시에 여러 개가 열려 있으면 확정이 «구조적으로» 밀린다★ — 확정할 것이 10개면 사람은
#   하나도 확정하지 못한다. 줄을 설 수가 없다.
#
# ★규칙은 이미 여러 번 있었고 지켜지지 않았다★(450k 규율을 호출의 46.4%가 넘겼다).
#   그래서 이번엔 «선언»이 아니라 «거부»로 만든다. 열려 있으면 두 번째 open 이 exit 1 로 떨어진다.
#
# 병렬을 버리는 것이 아니다 — ★나노는 한 인덱스 «안»에서 여러 개 돌아도 된다.★ 열린 «인덱스»가 1개다.
#
# 사용:
#   ft-index-gate.sh status
#   ft-index-gate.sh open <index-id> <seat> [목적 한 줄]
#   ft-index-gate.sh confirm <index-id> <오빠 확정 근거 한 줄>
#   ft-index-gate.sh close <index-id>
#   ft-index-gate.sh log [N]
#
# 상태 파일: <repo>/.fable-team/state/open-index.json  (열린 것 1개 또는 없음)
# 원장      : <repo>/.fable-team/state/index-ledger.jsonl  (append only)

set -uo pipefail

ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || { echo "REJECT git 저장소가 아니다" >&2; exit 2; }
STATE_DIR="${FT_INDEX_STATE_DIR:-$ROOT/.fable-team/state}"
# ★스코프는 «트랙»이다★ — 전역 1개면 CFO 3트랙이 직렬화돼 멈춘다.
#   빙글빙글은 트랙 «안»에서 돈다(랜딩 → 새 이슈 → 확정 없이 다음). 그래서 트랙별로 1개다.
TRACK="${FT_TRACK:-default}"
OPEN="$STATE_DIR/open-index.$TRACK.json"
LEDGER="$STATE_DIR/index-ledger.$TRACK.jsonl"
mkdir -p "$STATE_DIR" 2>/dev/null || true

_now() { date '+%Y-%m-%dT%H:%M:%S%z'; }
_json_get() { python3 -c "
import json,sys
try:
    d=json.load(open('$OPEN'))
except Exception:
    sys.exit(1)
print(d.get('$1',''))
" 2>/dev/null; }

_append() {
  printf '%s\n' "$1" >> "$LEDGER" 2>/dev/null || {
    echo "REJECT 원장에 못 썼다: $LEDGER" >&2; return 1; }
}

CMD="${1:-status}"; shift || true

case "$CMD" in
  status)
    if [ -s "$OPEN" ]; then
      id="$(_json_get id)"; seat="$(_json_get seat)"
      at="$(_json_get opened_at)"; conf="$(_json_get confirmed_at)"
      echo "OPEN  id=$id  seat=$seat  opened=$at"
      if [ -n "$conf" ]; then
        echo "      ★확정됨★ $conf — close 가능"
      else
        echo "      ☐ 미확정 — ★오빠와 확정하기 전에는 close 되지 않는다★"
      fi
    else
      echo "NONE  열린 인덱스 없음 — open 가능"
    fi
    ;;

  open)
    ID="${1:-}"; SEAT="${2:-}"; shift 2 2>/dev/null || true
    PURPOSE="${*:-}"
    [ -n "$ID" ] && [ -n "$SEAT" ] || { echo "usage: $0 open <index-id> <seat> [목적]" >&2; exit 2; }
    if [ -s "$OPEN" ]; then
      cur="$(_json_get id)"; curseat="$(_json_get seat)"; conf="$(_json_get confirmed_at)"
      echo "★REJECT 이미 열린 인덱스가 있다★" >&2
      echo "  열림: $cur (좌석 $curseat)" >&2
      if [ -n "$conf" ]; then
        echo "  확정은 됐다 — 먼저 close 해라: $0 close $cur" >&2
      else
        echo "  ★아직 오빠와 확정 안 됐다★ — 확정부터: $0 confirm $cur <근거>" >&2
      fi
      exit 1
    fi
    python3 - "$OPEN" "$ID" "$SEAT" "$(_now)" "$PURPOSE" << 'PY'
import json,sys
p,i,s,t,pu = sys.argv[1:6]
json.dump({"id":i,"seat":s,"opened_at":t,"purpose":pu,"confirmed_at":""},
          open(p,"w"), ensure_ascii=False, indent=1)
PY
    _append "{\"ts\":\"$(_now)\",\"ev\":\"open\",\"id\":\"$ID\",\"seat\":\"$SEAT\"}"
    echo "OPENED $ID (좌석 $SEAT) — ★이제 다음 인덱스는 열리지 않는다★"
    ;;

  confirm)
    ID="${1:-}"; shift || true
    WHY="${*:-}"
    [ -n "$ID" ] || { echo "usage: $0 confirm <index-id> <오빠 확정 근거>" >&2; exit 2; }
    [ -n "$WHY" ] || { echo "REJECT 근거가 비었다 — ★무엇을 근거로 닫는지 한 줄★이 있어야 한다" >&2; exit 2; }
    [ -s "$OPEN" ] || { echo "REJECT 열린 인덱스가 없다" >&2; exit 1; }
    cur="$(_json_get id)"
    [ "$cur" = "$ID" ] || { echo "REJECT 열린 것은 $cur 이다 (요청: $ID)" >&2; exit 1; }
    python3 - "$OPEN" "$(_now)" "$WHY" << 'PY'
import json,sys
p,t,w = sys.argv[1:4]
d=json.load(open(p)); d["confirmed_at"]=t; d["confirm_why"]=w
json.dump(d, open(p,"w"), ensure_ascii=False, indent=1)
PY
    _append "{\"ts\":\"$(_now)\",\"ev\":\"confirm\",\"id\":\"$ID\",\"why\":\"$WHY\"}"
    echo "CONFIRMED $ID — 이제 close 가능"
    ;;

  close)
    ID="${1:-}"
    [ -n "$ID" ] || { echo "usage: $0 close <index-id>" >&2; exit 2; }
    [ -s "$OPEN" ] || { echo "REJECT 열린 인덱스가 없다" >&2; exit 1; }
    cur="$(_json_get id)"; conf="$(_json_get confirmed_at)"
    [ "$cur" = "$ID" ] || { echo "REJECT 열린 것은 $cur 이다 (요청: $ID)" >&2; exit 1; }
    if [ -z "$conf" ]; then
      echo "★REJECT 확정 없이 닫을 수 없다★" >&2
      echo "  이게 빙글빙글의 엔진이다 — 확정 없이 넘어가면 다음 랜딩에서 같은 게 또 열린다." >&2
      echo "  먼저: $0 confirm $ID <오빠 확정 근거>" >&2
      exit 1
    fi
    _append "{\"ts\":\"$(_now)\",\"ev\":\"close\",\"id\":\"$ID\"}"
    rm -f "$OPEN"
    echo "CLOSED $ID — 다음 인덱스를 열 수 있다"
    ;;

  log)
    N="${1:-10}"
    [ -f "$LEDGER" ] && tail -n "$N" "$LEDGER" || echo "원장 없음"
    ;;

  *)
    echo "unknown: $CMD (status|open|confirm|close|log)" >&2; exit 2;;
esac
