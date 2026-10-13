#!/usr/bin/env bash
# ft-proxy-decide.sh — 자율 대리 결정 도구 (DESIGN-autonomy-proxy-decision r3 §4(b) · 판정 1322)
#   ft-proxy-decide.sh --kind <push-merge|card-start|press-order> --q "<질문>" --choice "<추천안>" --why "<근거>" --undo "<되돌림 1줄>"
#       [--sha <40hex> --da <판정문> --pr <N>]        push-merge 근거: PR head == --sha == DA⑥ 판정문 sha · checks 전부 pass
#       [--card <카드.md> --verdict <판정 번호>]       card-start 근거: 판정 줄에 카드 이름 + 착수 낱말 · 카드 본문 제외 어휘 검사
# rc 0 = 대리(PROXY): 판정 원장에 «대리» 1줄 · rc 2 = 대리 불가(QUEUE): 오빠 큐 1행 · rc 3 = 모드 OFF/위변조(인터뷰로) · rc 4 = 인자 오류
#   push-merge PROXY 는 원장 줄 뒤에 $STATE/autonomy-merge-ok/<sha> 1줄(`<판정> pr=<N> da=<판정문> ev=<A번호>`)을 쓴다 — 자율 ON 중 pr merge·main push 가드(훅③)의 통과 근거 (판정 1355)
# 환경: FT_ROOT · FT_AUTONOMY_STATE_DIR · FT_PLANNER_DIR(원장 VERDICTS-*.md · 큐 AUTONOMY-QUEUE.md) · FT_PROXY_LEDGER(쓸 원장, 기본 최신 planner 번호)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(cd "$HERE/../.." && pwd)}"
STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
PLANNER="${FT_PLANNER_DIR:-$ROOT/design/planner}"
QUEUE="$PLANNER/AUTONOMY-QUEUE.md"
AUT="$HERE/ft-autonomy.sh"; CLS="$HERE/autonomy_classify.py"
CALL_TIMEOUT_S=7   # 외부 호출 한 시도 상한 + 재시도 1회 = shared/config/external_call.py 값 (판정 666)
CALL_RETRIES=1

usage() { echo "REJECT $*" >&2; echo "usage: ft-proxy-decide.sh --kind K --q Q --choice C --why W --undo U [--sha S --da F --pr N | --card F --verdict N]" >&2; exit 4; }
san() { printf '%s' "$1" | tr '\n|' ' /'; }

kind=""; q=""; choice=""; why=""; undo=""; sha=""; da=""; pr=""; card=""; verdict=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage "값 없는 인자: $1"
  case "$1" in
    --kind) kind="$2" ;; --q) q="$2" ;; --choice) choice="$2" ;; --why) why="$2" ;; --undo) undo="$2" ;;
    --sha) sha="$2" ;; --da) da="$2" ;; --pr) pr="$2" ;; --card) card="$2" ;; --verdict) verdict="$2" ;;
    *) usage "알 수 없는 인자: $1" ;;
  esac
  shift 2
done
for v in kind q choice why undo; do [ -n "${!v}" ] || usage "--$v 필수"; done

mode="$("$AUT" mode)"
[ "$mode" = on ] || { echo "REJECT 자율 모드 $mode — 대리 불가, 인터뷰로"; exit 3; }
EV="$("$AUT" event)"
qhash="$(printf '%s\n%s' "$kind" "$q" | shasum -a 256 | cut -c1-16)"
SEEN="$STATE/autonomy.queued"

lock() { local i=0; until mkdir "$STATE/.proxy.lock" 2>/dev/null; do i=$((i+1)); [ "$i" -le 50 ] || usage "락 선점 중: $STATE/.proxy.lock"; sleep 0.1; done; trap 'rmdir "$STATE/.proxy.lock" 2>/dev/null' EXIT; }
unlock() { rmdir "$STATE/.proxy.lock" 2>/dev/null; trap - EXIT; }

fail() { echo "ERROR $* — 기록 실패, 결정 아님" >&2; exit 5; }  # #0 RULE: 기록 실패에 PROXY·QUEUE 성공을 말하지 않는다

queue_exit() {  # <사유> — 큐 1행 + 같은 질문 기록, rc 2 (쓰기 실패 = rc 5 + stderr)
  local why_q="$1"
  lock
  if [ ! -f "$QUEUE" ]; then
    mkdir -p "$PLANNER" || fail "큐 폴더 생성 실패: $PLANNER"
    printf '%s\n\n%s\n%s\n' '# AUTONOMY-QUEUE — 자율 대리 결정 모드가 대리하지 않은 질문 (오빠 큐)' \
      '| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 |' '|---|---|---|---|---|---|' > "$QUEUE" || fail "큐 파일 생성 실패: $QUEUE"
  fi
  printf '| %s | %s | %s | %s | %s | %s |\n' "$EV" "$(date '+%Y-%m-%d %H:%M')" "$(san "$kind")" "$(san "$q")" "$(san "$choice")" "$(san "$why_q")" >> "$QUEUE" || fail "큐 행 쓰기 실패: $QUEUE"
  printf '%s %s\n' "$EV" "$qhash" >> "$SEEN" || fail "재시도 기록 쓰기 실패: $SEEN"
  unlock
  echo "QUEUE $why_q · 큐 파일 $QUEUE"
  exit 2
}

# <명령…> → stdout · 시도마다 CALL_TIMEOUT_S초 deadline 을 «별도» 판정 — 초과한 시도는 출력·rc 를 버린다(늦은 rc0 채택 0)
# TERM → 1초 유예 → KILL. 실패·초과면 CALL_RETRIES회 재시도, 끝내 안 되면 rc 1 (호출자가 QUEUE)
bounded() {
  local try=0 tmp pid i rc timed
  tmp="$(mktemp)" || return 1
  while [ "$try" -le "$CALL_RETRIES" ]; do
    try=$((try+1)); timed=0
    "$@" >"$tmp" 2>/dev/null & pid=$!
    i=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$i" -ge $((CALL_TIMEOUT_S * 10)) ]; then timed=1; break; fi
      sleep 0.1; i=$((i+1))
    done
    if [ "$timed" = 1 ]; then
      kill -TERM "$pid" 2>/dev/null; i=0
      while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 0.1; i=$((i+1)); done
      kill -KILL "$pid" 2>/dev/null
      { wait "$pid"; } 2>/dev/null
      continue
    fi
    { wait "$pid"; } 2>/dev/null; rc=$?
    if [ "$rc" = 0 ]; then cat "$tmp"; rm -f "$tmp"; return 0; fi
  done
  rm -f "$tmp"; return 1
}

card_check() {  # card-start — 판정 줄 결속 + 카드 본문(배경·구현 범위·쓰기 허용·금지 절)을 CARD_TEXT 로
  local slug line
  [ -n "$card" ] && [ -n "$verdict" ] || queue_exit "card-start 에는 --card·--verdict 필요"
  case "$verdict" in *[!0-9]*) queue_exit "판정 번호가 숫자 아님" ;; esac
  [ -r "$card" ] || queue_exit "카드를 못 읽음: $card"
  slug="$(basename "$card" .md)"
  line="$(cat "$PLANNER"/VERDICTS-*.md 2>/dev/null | grep -E "^- \*\*$verdict\*\*" | head -1)"
  [ -n "$line" ] || queue_exit "원장에 판정 $verdict 줄 없음"
  # 이름 경계: 앞뒤가 [A-Za-z0-9_-] 가 아니어야 한다 (r-wait-events ⊄ r-wait-events-rotate)
  grep -qE "(^|[^A-Za-z0-9_-])$(printf '%s' "$slug" | sed 's/[][\.*^$()+?{|]/\\&/g')([^A-Za-z0-9_-]|$)" <<<"$line" || queue_exit "판정 $verdict 줄이 카드 이름($slug)을 말하지 않음"
  ! grep -qE '설계만|제안서만' <<<"$line" || queue_exit "판정 $verdict 은 설계·제안서까지만 승인"
  ! grep -qE '보류|금지|중단|취소|대기|철회|불가|않|(^|[[:space:]])안([[:space:]]|$)|하지[[:space:]]*마|말[것고]' <<<"$line" || queue_exit "판정 $verdict 줄에 부정·보류 낱말 — 허락을 확인 못 함"
  grep -qE '착수|발주|구현|진행' <<<"$line" || queue_exit "판정 $verdict 줄에 착수 낱말 없음"
  CARD_TEXT="$(awk '/^## /{p=($0 ~ /^## (배경|구현 범위|쓰기 허용|금지)/)} p' "$card")"
}

push_merge_check() {  # PR head == --sha == DA⑥ 판정문 sha · checks 전부 pass — 외부 호출 실패 = QUEUE
  local head checks dv
  grep -qE '^[0-9a-f]{40}$' <<<"$sha" || queue_exit "--sha 가 40hex 아님"
  case "$pr" in ''|*[!0-9]*) queue_exit "--pr 가 숫자 아님" ;; esac
  [ -r "$da" ] || queue_exit "DA 판정문을 못 읽음"
  dv="$(python3 "$CLS" da-check "$da" "$sha")" || queue_exit "${dv#QUEUE }"
  head="$(bounded env -u GH_TOKEN gh pr view "$pr" --json headRefOid -q .headRefOid)" || queue_exit "gh pr view 실패·${CALL_TIMEOUT_S}초 초과"
  [ "$head" = "$sha" ] || queue_exit "PR head($head) ≠ --sha"
  checks="$(bounded env -u GH_TOKEN gh pr checks "$pr" --json bucket -q '.[].bucket')" || queue_exit "gh pr checks 실패·${CALL_TIMEOUT_S}초 초과"
  [ -n "$checks" ] && ! grep -qvx pass <<<"$checks" || queue_exit "checks 가 전부 pass 아님"
}

if [ -f "$SEEN" ] && grep -qxF "$EV $qhash" "$SEEN"; then
  echo "QUEUE 같은 질문 재시도 — 이미 큐에 있음 · 큐 파일 $QUEUE"; exit 2
fi

CARD_TEXT=""
[ "$kind" != card-start ] || card_check
out="$(python3 "$CLS" --kind "$kind" --text "$q" --text "$choice" --text "$why" --text "$undo" --text "$CARD_TEXT")" || queue_exit "${out#QUEUE }"
[ "$kind" != push-merge ] || push_merge_check

# PROXY — 판정 원장 1줄 (번호 = 원장 폴더 최대 번호 + 1)
LEDGER="${FT_PROXY_LEDGER:-$(ls "$PLANNER"/VERDICTS-*.md 2>/dev/null | sed 's/.*planner-\([0-9]*\)-.*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)}"
[ -n "$LEDGER" ] || usage "판정 원장 파일 없음: $PLANNER/VERDICTS-*.md"
lock
num="$(( $(cat "$PLANNER"/VERDICTS-*.md "$LEDGER" 2>/dev/null | sed -n 's/^- \*\*\([0-9][0-9]*\)\*\*.*/\1/p' | sort -n | tail -1) + 1 ))"
[ -f "$LEDGER" ] && [ -w "$LEDGER" ] || fail "판정 원장이 쓰기 가능한 파일이 아님: $LEDGER"
line="$(printf -- '- **%s** [대리 · 자율 ON %s] %s → %s · 근거 %s · 되돌림 %s' "$num" "$EV" "$(san "$q")" "$(san "$choice")" "$(san "$why")" "$(san "$undo")")"
printf '%s\n' "$line" >> "$LEDGER" || fail "판정 원장 쓰기 실패: $LEDGER"
[ "$(tail -n 1 "$LEDGER")" = "$line" ] || fail "판정 원장 쓰기 확인 실패: $LEDGER"
if [ "$kind" = push-merge ]; then  # 병합 가드 훅(autonomy-merge-guard)이 읽는 ok 파일 — 원장 줄을 쓴 «뒤»에만 · 실패 = rc 5 (PROXY 출력 0)
  OKDIR="$STATE/autonomy-merge-ok"
  { mkdir -p "$OKDIR" && printf '%s pr=%s da=%s ev=%s\n' "$num" "$pr" "$(san "$da")" "$EV" > "$OKDIR/$sha.tmp" && mv "$OKDIR/$sha.tmp" "$OKDIR/$sha"; } || fail "병합 ok 파일 쓰기 실패: $OKDIR/$sha"
fi
unlock
echo "PROXY 판정 $num · $("$AUT" status) → $choice"
