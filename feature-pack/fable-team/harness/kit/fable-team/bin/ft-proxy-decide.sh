#!/usr/bin/env bash
# ft-proxy-decide.sh — 자율 대리 결정 도구 (DESIGN-autonomy-proxy-decision r3 §4(b) · 판정 1322)
#   ft-proxy-decide.sh --kind <card-start|press-order|nano-reopen|docs-push|wt-clean> --q "<질문>" --choice "<추천안>" --why "<근거>" --undo "<되돌림 1줄>"
#       [--card <카드.md> --verdict <판정 번호>]       card-start 근거: 판정 줄에 카드 이름 + 착수 낱말 · 카드 본문 제외 어휘 검사
#       [--card <진행/카드.md> --seat <좌석>]          nano-reopen 근거(설계 r1-1 ①~④ + r1-9 H2 ⑤): 진행 폴더 카드 · nano/* 브랜치 · 재개 기록 · 자원 문지기 rc 0 · spawn 기준선과 같음
#       [--branch <가지> --sha <40hex>]               docs-push 근거: diff 전부 *.md|design/** · 가지 ∉ {main}∪FT_DEPLOY_BRANCHES(미설정=QUEUE) · fast-forward
#       [--plan <상태>/wt-clean/<좌석>.sh.hil]        wt-clean 근거(R410 · 판정 2326): ft-nano-close 계획 · plan-ver = 라이브 생성기 blob · «브랜치는 지우지 않는다» · 좌석 tmux 세션 0 · 실행 줄 제외 어휘(계획 실행은 PROXY 뒤 호출자 몫)
#       [--team <팀>]                               r529 큐 줄 팀 칸(없으면 --card 경로의 팀 · 둘 다 없으면 -)
#   push-merge(main 병합·main push)는 오빠 값(판정 1675) — 항상 QUEUE, ok 파일 쓰기 0. 병합 승인 = ft-autonomy.sh approve-merge(오빠 `!`)뿐.
# rc 0 = 대리(PROXY): 판정 원장에 «대리» 1줄 · rc 2 = 대리 불가(QUEUE): 오빠 큐 1행 · rc 3 = 모드 OFF/위변조(인터뷰로) · rc 4 = 인자 오류
# 환경: FT_ROOT · FT_AUTONOMY_STATE_DIR · FT_PLANNER_DIR(원장 VERDICTS-*.md · 큐 AUTONOMY-QUEUE.md) · FT_PROXY_LEDGER(쓸 원장, 기본 최신 planner 번호) · FT_TEAMS_REF(큐 자리 명단·카드 읽기 ref, 기본 origin/main · r515)
#       FT_SEAT_RESUME_DIR(재개 기록, 기본 ~/.claude/state/seat-resume) · FT_RESOURCE_GATE(자원 문지기, 기본 같은 폴더 ft-resource-gate.sh) · FT_DEPLOY_BRANCHES(공백·쉼표 구분, glob 허용 · 없으면 <상태>/deploy-branches.txt 한 줄 한 패턴) · FT_PUSH_REMOTE(기본 origin) · FT_TMUX_BIN(기본 PATH 의 tmux)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-}"   # r385: 라이브 루트 = FT_ROOT → ft_data_root(cwd LIVE_ROOT · 옛 설치 꼴) → ERROR rc3(=모드 못 읽음 → 인터뷰로)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_data_root "$HERE")"; } || exit 3
STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
# R383: planner 팀 폴더(판정 원장)는 ROOT 의 design/TEAMS.md 로(팀 이름 글자 0) — 못 풀면 후퇴 없이 ERROR 종료(#0 RULE)
. "$HERE/ft-team-lib.sh" || { echo "ERROR 팀 경로 공용 함수(ft-team-lib.sh)를 못 읽음" >&2; exit 4; }
if [ -n "${FT_PLANNER_DIR:-}" ]; then PLANNER="$FT_PLANNER_DIR"
else PLANNER="$(ft_team_in "$ROOT" planner)" || { echo "ERROR planner 팀 폴더를 못 풀었다(design/TEAMS.md · FT_ROOT=$ROOT) — FT_PLANNER_DIR 로 지정하거나 명단을 고친다" >&2; exit 4; }; fi
# r515: 오빠 큐 자리는 ft_planner_queue 하나(ft-autonomy·ft_decision_count 와 같은 리졸버 · 이동 전 가지의 옛 자리 후퇴 0)
QUEUE="$(ft_planner_queue "$ROOT")" || { echo "ERROR 오빠 큐 자리를 못 풀었다(ft_planner_queue · FT_ROOT=$ROOT) — FT_PLANNER_DIR 로 지정하거나 ref 명단을 고친다" >&2; exit 4; }
CARD_REF="${FT_TEAMS_REF:-origin/main}"   # r515: card-start 카드 상대경로 = cwd → 이 ref 순
AUT="$HERE/ft-autonomy.sh"; CLS="$HERE/autonomy_classify.py"
. "$HERE/ft-verdict-row.sh" || { echo "REJECT 판정 줄 공용 함수(ft-verdict-row.sh)를 못 읽음 — 같은 폴더에 있어야 한다" >&2; exit 4; }   # 원장 두 꼴(글머리·표 행) 읽기 정본
CALL_TIMEOUT_S=7   # 외부 호출 한 시도 상한 + 재시도 1회 = shared/config/external_call.py 값 (판정 666)
CALL_RETRIES=1

usage() { echo "REJECT $*" >&2; echo "usage: ft-proxy-decide.sh --kind K --q Q --choice C --why W --undo U [--card F --verdict N | --card F --seat S | --branch B --sha S | --plan P]" >&2; exit 4; }
san() { printf '%s' "$1" | tr '\n|' ' /'; }

kind=""; q=""; choice=""; why=""; undo=""; sha=""; card=""; verdict=""; seat=""; branch=""; plan=""; team=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage "값 없는 인자: $1"
  case "$1" in
    --kind) kind="$2" ;; --q) q="$2" ;; --choice) choice="$2" ;; --why) why="$2" ;; --undo) undo="$2" ;;
    --sha) sha="$2" ;; --card) card="$2" ;; --verdict) verdict="$2" ;; --seat) seat="$2" ;; --branch) branch="$2" ;; --plan) plan="$2" ;; --team) team="$2" ;;
    --da|--pr) ;;   # push-merge 옛 인자 — 이제 QUEUE 고정이라 읽지 않는다(호출 습관이 rc 4 로 깨지지 않게 받기만)
    *) usage "알 수 없는 인자: $1" ;;
  esac
  shift 2
done
for v in kind q choice why undo; do [ -n "${!v}" ] || usage "--$v 필수"; done
# r529: 큐 줄 팀 칸 = --team → --card 경로의 design/[teams/]<팀>/indices/ → -
qteam="${team:--}"; case "$qteam" in *[!a-z0-9_-]*) usage "--team 형식 틀림: $team" ;; esac
if [ -z "$team" ] && [[ "$card" =~ (^|/)design/(teams/)?([a-z0-9][a-z0-9_-]*)/indices/ ]]; then qteam="${BASH_REMATCH[3]}"; fi

mode="$("$AUT" mode)"
[ "$mode" = on ] || { echo "REJECT 자율 모드 $mode — 대리 불가, 인터뷰로"; exit 3; }
EV="$("$AUT" event)"
qhash="$(printf '%s\n%s' "$kind" "$q" | shasum -a 256 | cut -c1-16)"
SEEN="$STATE/autonomy.queued"

lock() { local i=0; until mkdir "$STATE/.proxy.lock" 2>/dev/null; do i=$((i+1)); [ "$i" -le 50 ] || usage "락 선점 중: $STATE/.proxy.lock"; sleep 0.1; done; trap 'rmdir "$STATE/.proxy.lock" 2>/dev/null' EXIT; }
unlock() { rmdir "$STATE/.proxy.lock" 2>/dev/null; trap - EXIT; }

fail() { echo "ERROR $* — 기록 실패, 결정 아님" >&2; exit 5; }  # #0 RULE: 기록 실패에 PROXY·QUEUE 성공을 말하지 않는다

queue_exit() {  # <사유> — 큐 1행 + 같은 질문 기록, rc 2 (쓰기 실패 = rc 5 + stderr)
  local why_q="$1" added
  # r528: 상태 칸(어휘 정본 queue-states.tsv · 새 줄 «대기») · r529: 상태 뒤 번호·팀·보여준 시각 — 줄 쓰기 = ft-queue.sh add 하나(락 · 옛 머리 칸 셋 붙임)
  added="$(FT_QUEUE_FILE="$QUEUE" FT_AUTONOMY_STATE_DIR="$STATE" bash "$HERE/ft-queue.sh" add --ev "$EV" --kind "$kind" --q "$q" --choice "$choice" --why "$why_q" --team "$qteam" 2>&1)" \
    || fail "큐 행 쓰기 실패: $QUEUE (${added//$'\n'/ })"
  lock
  printf '%s %s\n' "$EV" "$qhash" >> "$SEEN" || fail "재시도 기록 쓰기 실패: $SEEN"
  unlock
  echo "QUEUE $why_q · 큐 줄 ${added#ADD } · 큐 파일 $QUEUE"
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
  local slug line body
  [ -n "$card" ] && [ -n "$verdict" ] || queue_exit "card-start 에는 --card·--verdict 필요 — 예) ft-proxy-decide.sh --kind card-start --card design/<팀>/indices/대기/<카드>.md --verdict <판정 번호> --q <질문> --choice <추천안> --why <근거> --undo <되돌림>"
  case "$verdict" in *[!0-9]*) queue_exit "판정 번호가 숫자 아님" ;; esac
  if [ -r "$card" ]; then body="$(cat "$card")"   # 절대경로 = 그 파일만 · 상대경로 = cwd 다음 ref(r515)
  else case "$card" in /*) queue_exit "카드를 못 읽음: $card" ;; esac
    body="$(git -C "$ROOT" show "$CARD_REF:$card" 2>/dev/null)" && [ -n "$body" ] || queue_exit "카드를 못 읽음: $PWD/$card · $CARD_REF:$card"; fi
  slug="$(basename "$card" .md)"
  line="$(cat "$PLANNER"/VERDICTS-*.md 2>/dev/null | grep -E "$(fv_row_re "$verdict")" | head -1)"   # 글머리 `- **N**` 꼴 · 표 행 `| N |` 꼴 둘 다(번호 경계 엄격 — ft-verdict-row.sh)
  [ -n "$line" ] || queue_exit "원장에 판정 $verdict 줄 없음"
  # 이름 경계: 앞뒤가 [A-Za-z0-9_-] 가 아니어야 한다 (r-wait-events ⊄ r-wait-events-rotate)
  grep -qE "(^|[^A-Za-z0-9_-])$(printf '%s' "$slug" | sed 's/[][\.*^$()+?{|]/\\&/g')([^A-Za-z0-9_-]|$)" <<<"$line" || queue_exit "판정 $verdict 줄이 카드 이름($slug)을 말하지 않음"
  ! grep -qE '설계만|제안서만' <<<"$line" || queue_exit "판정 $verdict 은 설계·제안서까지만 승인"
  ! grep -qE '보류|금지|중단|취소|대기|철회|불가|않|(^|[[:space:]])안([[:space:]]|$)|하지[[:space:]]*마|말[것고]' <<<"$line" || queue_exit "판정 $verdict 줄에 부정·보류 낱말 — 허락을 확인 못 함"
  grep -qE '착수|발주|구현|진행' <<<"$line" || queue_exit "판정 $verdict 줄에 착수 낱말 없음"
  CARD_TEXT="$(awk '/^## /{p=($0 ~ /^## (배경|구현 범위|쓰기 허용|금지)/)} p' <<<"$body")"
}

jget() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2" 2>/dev/null; }  # <json 파일> <키> — 못 읽으면 빈 값

nano_reopen_check() {  # 설계 r1-1 ①~④ + r1-9 H2 ⑤ — 하나라도 못 읽으면 QUEUE (기준선 파일 쓰기는 ft-nano-spawn 몫, 없으면 QUEUE)
  local base="$STATE/nano-card-base/$seat.json" rec="${FT_SEAT_RESUME_DIR:-$HOME/.claude/state/seat-resume}/$seat.json"
  local gate="${FT_RESOURCE_GATE:-$HERE/ft-resource-gate.sh}" bb bw cb
  [ -n "$card" ] && [ -n "$seat" ] || queue_exit "nano-reopen 에는 --card·--seat 필요 — 예) ft-proxy-decide.sh --kind nano-reopen --card design/<팀>/indices/진행/<카드>.md --seat <좌석> --q <질문> --choice <추천안> --why <근거> --undo <되돌림>"
  case "$seat" in */*|*..*) queue_exit "--seat 형식 틀림" ;; esac
  case "$card" in */indices/진행/*.md) [ -r "$card" ] || queue_exit "① 카드를 못 읽음" ;; *) queue_exit "① 카드가 indices/진행/ 폴더에 없음" ;; esac
  [ -r "$base" ] || queue_exit "⑤ spawn 기준선($base) 없음"
  bb="$(jget "$base" branch)"; bw="$(jget "$base" worktree)"; cb="$(jget "$base" card_blob)"
  [ -n "$bb" ] && [ -n "$bw" ] && [ -n "$cb" ] || queue_exit "⑤ 기준선 필드(branch·worktree·card_blob)를 못 읽음"
  case "$bb" in nano/*) ;; *) queue_exit "② 기준선 가지가 nano/* 아님: $bb" ;; esac
  git -C "$bw" rev-parse --verify -q "refs/heads/$bb" >/dev/null 2>&1 || queue_exit "② 가지 $bb 없음"
  [ "$(git -C "$bw" symbolic-ref --short -q HEAD 2>/dev/null)" = "$bb" ] || queue_exit "③⑤ 워크트리 HEAD 가 기준선 가지($bb)가 아님"
  [ -r "$rec" ] || queue_exit "③ 재개 기록($rec) 없음"
  [ "$(jget "$rec" name)" = "$seat" ] && [ "$(jget "$rec" cwd)" = "$bw" ] || queue_exit "③⑤ 재개 기록의 name·cwd 가 기준선과 다름"
  [ "$(git hash-object "$card" 2>/dev/null)" = "$cb" ] || queue_exit "⑤ 카드 내용이 spawn 기준선과 다름(새 범위)"
  bash "$gate" check >/dev/null 2>&1 || queue_exit "④ 자원 문지기 check rc≠0"
}

docs_push_check() {  # 설계 r1-1 — 원격 비교는 ls-remote 1회(7초 + 재시도 1회 · 실패 = QUEUE)
  local remote="${FT_PUSH_REMOTE:-origin}" pat rsha files f list deploy_file="$STATE/deploy-branches.txt"
  [ -n "$branch" ] && grep -qE '^[0-9a-f]{40}$' <<<"$sha" || queue_exit "docs-push 에는 --branch·--sha(40hex) 필요"
  case "$branch" in -*|*..*|main) queue_exit "② 대상 가지가 main 이거나 형식 틀림: $branch" ;; esac
  list="${FT_DEPLOY_BRANCHES:-}"   # env 우선 · 없으면 목록 파일(한 줄 한 패턴 · # 주석)
  [ -n "$list" ] || { [ -r "$deploy_file" ] && list="$(sed 's/#.*//' "$deploy_file" | tr -s ' \t\r\n,' ' ')"; }
  [ -n "${list//[[:space:]]/}" ] || queue_exit "② 배포 가지 목록 없음 — FT_DEPLOY_BRANCHES 또는 $deploy_file"
  set -f; for pat in ${list//,/ }; do case "$branch" in $pat) set +f; queue_exit "② 대상 가지($branch)가 배포 가지($pat)" ;; esac; done; set +f
  rsha="$(bounded git ls-remote --heads "$remote" "refs/heads/$branch")" || queue_exit "git ls-remote 실패·${CALL_TIMEOUT_S}초 초과"
  rsha="${rsha%%[[:space:]]*}"; grep -qE '^[0-9a-f]{40}$' <<<"$rsha" || queue_exit "원격에 가지($branch) 없음"
  git merge-base --is-ancestor "$rsha" "$sha" 2>/dev/null || queue_exit "③ fast-forward 아님(원격 $rsha ⊄ --sha)"
  files="$(git diff --name-only "$rsha" "$sha" 2>/dev/null)" && [ -n "$files" ] || queue_exit "① diff 를 못 읽음·비어 있음"
  while IFS= read -r f; do case "$f" in *.md|design/*) ;; *) queue_exit "① 문서 아닌 파일: $f" ;; esac; done <<<"$files"
}

wt_clean_check() {  # R410 · 판정 2326 — 근거 = ft-nano-close 가 만든 계획 파일 하나 · 하나라도 못 읽으면 QUEUE(계획 실행은 여기서 하지 않는다)
  local gen="$HERE/ft-nano-close.sh" sd pd pv lv s tm="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
  [ -n "$plan" ] || queue_exit "wt-clean 에는 --plan 필요 — 예) ft-proxy-decide.sh --kind wt-clean --plan $STATE/wt-clean/<좌석>.sh.hil --q <질문> --choice <추천안> --why <근거> --undo <되돌림>"
  sd="$(cd "$STATE/wt-clean" 2>/dev/null && pwd -P)"; pd="$(cd "$(dirname "$plan")" 2>/dev/null && pwd -P)"
  [ -n "$sd" ] && [ "$pd" = "$sd" ] && case "$plan" in *.sh.hil) true ;; *) false ;; esac || queue_exit "① 계획이 $STATE/wt-clean/*.sh.hil 이 아님: $plan"
  [ -f "$plan" ] && [ -r "$plan" ] || queue_exit "① 계획을 못 읽음: $plan"
  pv="$(sed -n 's/^# plan-ver: \([0-9a-f]\{40\}\)$/\1/p' "$plan" | head -1)"; lv="$(git hash-object -- "$gen" 2>/dev/null)" || lv=""
  [ -n "$pv" ] && [ "$pv" = "$lv" ] || queue_exit "② STALE 계획(plan-ver=${pv:-없음} ≠ 생성기 ${lv:-없음}) — ft-nano-close.sh 로 다시 만든다"
  grep -qF '브랜치는 지우지 않는다' "$plan" || queue_exit "③ 계획에 «브랜치는 지우지 않는다» 없음"
  s="$(sed -n 's/^SEAT=\([^;]*\);.*/\1/p' "$plan" | head -1)"; [ -n "$s" ] || queue_exit "④ 계획에 SEAT= 없음"
  [ -n "$tm" ] && [ -x "$tm" ] || queue_exit "④ tmux 실행 불가(${tm:-없음}) — 좌석 세션 0 을 확인 못 함"
  ! "$tm" has-session -t "=$s" 2>/dev/null || queue_exit "④ 좌석 세션 실재: $s"
  PLAN_TEXT="$(cat "$plan")" || queue_exit "⑤ 계획 본문을 못 읽음"
}

if [ -f "$SEEN" ] && grep -qxF "$EV $qhash" "$SEEN"; then
  echo "QUEUE 같은 질문 재시도 — 이미 큐에 있음 · 큐 파일 $QUEUE"; exit 2
fi

CARD_TEXT=""; PLAN_TEXT=""
[ "$kind" != card-start ] || card_check
[ "$kind" != wt-clean ] || wt_clean_check
out="$(python3 "$CLS" --kind "$kind" --text "$q" --text "$choice" --text "$why" --text "$undo" --text "$CARD_TEXT" --plan-text "$PLAN_TEXT")" || queue_exit "${out#QUEUE }"
case "$kind" in nano-reopen) nano_reopen_check ;; docs-push) docs_push_check ;; esac

# PROXY — 판정 원장 1줄 (번호 = 원장 폴더 최대 번호 + 1)
LEDGER="${FT_PROXY_LEDGER:-$(ls "$PLANNER"/VERDICTS-*.md 2>/dev/null | sed 's/.*planner-\([0-9]*\)-.*/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)}"
[ -n "$LEDGER" ] || usage "판정 원장 파일 없음: $PLANNER/VERDICTS-*.md"
lock
max="$(cat "$PLANNER"/VERDICTS-*.md "$LEDGER" 2>/dev/null | fv_max)" || fail "판정 원장에서 번호를 하나도 못 읽음(글머리·표 행 둘 다) — 번호 발급 0"
num=$((max + 1))
[ -f "$LEDGER" ] && [ -w "$LEDGER" ] || fail "판정 원장이 쓰기 가능한 파일이 아님: $LEDGER"
line="$(printf -- '- **%s** [대리 · 자율 ON %s] %s → %s · 근거 %s · 되돌림 %s' "$num" "$EV" "$(san "$q")" "$(san "$choice")" "$(san "$why")" "$(san "$undo")")"
printf '%s\n' "$line" >> "$LEDGER" || fail "판정 원장 쓰기 실패: $LEDGER"
[ "$(tail -n 1 "$LEDGER")" = "$line" ] || fail "판정 원장 쓰기 확인 실패: $LEDGER"
unlock
echo "PROXY 판정 $num · $("$AUT" status) → $choice"
