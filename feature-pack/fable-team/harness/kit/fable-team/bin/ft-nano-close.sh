#!/usr/bin/env bash
# ft-nano-close.sh <좌석> --result <산출경로> --recv <master seq> [--kill] [--cherry-override "<사유>" | --superseded-by <대체 카드 경로> | --suspended "<사유>"] [--shared-wt | --wt <경로> --branch <이름>]
#   --suspended "<사유>" = 팀 정지 등으로 «미완» 인 채 멈춘 나노(⑥ 증거 줄 rc≠0 · 대체 카드 없음)를 닫는다(r450). ⑥ 만 면제하고 그 자리에서 ft-nano-suspended-check.sh 가
#     HEAD(브랜치 위)·미커밋 0 을 보고(실작업물 미커밋은 먼저 [wip] 커밋 · 실패 = REJECT), 닫기 직전 카드 «## 상태» 끝에 `중단: <사유> · 세트 <HEAD> · …` 1줄(멱등)을 남긴다.
#     ⑤ cherry 게이트엔 --override "suspended: <사유>" 자동 전달 · 원장 행 suspended=1 reason=… set=… · 출력 `CLOSED <좌석> suspended=1 reason=<사유> set=<HEAD>` · 브랜치 삭제 0.
#     빈 사유·--superseded-by·--cherry-override 와 동시 = usage 2 · 인자 없으면 동작 불변.
#   --wt <경로> --branch <이름> = 전용 워크트리는 있는데 «이름이 표준(.worktrees/<접두><키> · nano/<키>)이 아닌» 좌석 닫기(원장 R8 보강) — 둘 «모두» 명시해야만 이 모드(하나만 · --shared-wt 와 동시 = usage 2 · 자동 판별 0).
#     확인 ⓐ등록된 .worktrees/ 아래 워크트리 ⓑ그 워크트리 체크아웃 브랜치 == --branch ⓒ세션이 살아 있으면 pane cwd toplevel == --wt ⓓ다른 pane 이 --wt 안 cwd 0 ⓔ미커밋 0 ⓕ기존 종료조건 3·증거 줄 ⓖcherry 는 --branch 기준(우회는 기존 --cherry-override 뿐).
#     통과해도 WIP 자동 커밋·wt-clean 실행·브랜치 삭제 0 — 정리 계획만 <wt-clean>/<seat>.sh.hil 로 생성(sweep 순회 밖 · 사람 ! 실행).
#   --shared-wt = 전용 워크트리가 없는 «공유 워크트리 좌석»(예: pane cwd = 공유 c-level-planning) 닫기 — 명시 인자로만(자동 판별 0). 확인 ⓐ~ⓔ 전부 통과해야 하고, 통과해도 cherry·wt-clean 은 건너뛰고 세션 kill·명부·원장만(워크트리·파일·브랜치 손대지 않음).
#   --cherry-override = ⑤ cherry 게이트의 코드 «+» 내용 REJECT 만 사람 사유로 우회(산출물이 의도적으로 대체된 석 · 원장 cherry-gate-override.log 1행 · 사유 빈 값은 exit 2).
#   --superseded-by <카드> = 다른 카드로 «대체된» 나노(세트를 랜딩하지 않아 ⑥ rc=0 증거 줄이 영원히 없다)를 닫는다(R171). 이 인자가 있으면 ⑥ 의 rc=0 증거 줄 대신 ft-nano-superseded-check.sh 가
#     «카드 ## 상태 맨 끝 줄 = 대체됨: <카드> · 사유: <글>» + 대체 카드(design/<팀>/indices/{대기,진행,완료}/*.md) 실재 + 자기 자신 아님을 요구하고, ⑤ cherry 게이트엔 --override "superseded-by <카드>"(원장 1행)를 넘긴다.
#     --cherry-override 와 동시 = usage 2 · 인자 없으면 동작 불변 · 브랜치 삭제 0 · 명부는 기존 CLOSED 경로가 갱신(손 편집 불필요) · 출력 `CLOSED <좌석> superseded-by=<카드> …`.
#   --plan-only <워크트리 경로> = 이미 좌석이 사라졌는데 정리 계획이 없는 나노 워크트리의 «계획만» 만든다(r-disk-drop-worktree-scratch-census · ft-disk-census.sh --plan 이 부른다). ①②③ 종료조건·cherry 게이트·명부·원장 행·kill 전부 건너뛰고
#     확인: 좌석 세션 0(tmux 조회 성공) · 그 경로가 이 리포 .worktrees/ 아래 등록 워크트리 · 가지가 nano/<좌석 키>[-rN]. 통과하면 <wt-clean>/<seat>.sh 생성 + `PLANNED <경로>` + exit 0 — 실행은 기존 ft-wt-sweep.sh. 착지 판정은 호출자(census) 몫이고, 원장에 닫힘 행이 없어도 계획은 표식 실패로 멈추지 않는다.
#   Seatbelt 0.3 · 나노 좌석을 «값으로» 닫는다 (SEATBELT-README §3 닫기 · NANO-LEDGER 종료조건 3).
#   exit 0 = 닫힘(명부 삭제·원장 append·@zc_v65_active 해제·세션 kill) · 1 = REJECT(조건 미충족) 또는 FAIL(해제/kill 실패, 사유 stdout) · 2 = usage
#   --kill 은 호환용 — 닫으면 항상 태그 해제 + kill-session(2026-10-02 · keep-last-2 검사 삭제, nano 계보는 대상 아님).
# 종료조건 3 (전부 «값»): ①--result 경로 실재 ②--recv master 회수 seq 가 우편함/bodies 에 실재 ③jsonl 마지막 활동 ≥ IDLE_MIN 분 전
# 종료조건 ④ (팩 1.0.2): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no (checkpoint.json 미설정 프로젝트는 경고만).
# 하네스 0.5 행 2 r3 (표준승인 2026-09-25 · ~/.claude/CLAUDE.md HIL 절 · DA r1 조건 1~7 · DA r2 조건 1~5):
#   close 는 워크트리 정리 계획을 «생성만» 한다(.fable-team/state/wt-clean/<seat>.sh · 원장 행 wt=planned). 조건 ③이 세션 실재를 요구하므로
#   close 시점엔 좌석이 살아 있다 — 실행은 «세션이 사라진 뒤»: --kill 이 KILLED 를 낸 직후, 또는 ft-wt-sweep.sh(ft-tick.sh 가 매 루프 호출 · r3 배선).
#   계획 스크립트가 가드 6(계보 세션 자기 포함 0 · 워크트리 cwd 보유 프로세스 0 · info branch nano/* · HEAD=branch+도달성 · 실작업물은 WIP 커밋(r7) · ignored 보관)과
#   원장 표식(wt=… · 좌석명 행 · mkdir 락)을 맡는다. ★가드 도구(lsof·tmux) 실패 = skipped(fail-closed · DA r2 R12)★. 브랜치는 절대 지우지 않는다.
#   FT_WT_AUTOCLEAN=0 = 실행 경로 전부 끔(계획만 남김). 원장 경로는 리포 고정(ROOT 기준 · DA r2 MINOR C) — FT_NANO_LEDGER 로 override.
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec
SEAT="${1:-}"; shift || { echo "usage: $0 <seat> --result <path> --recv <seq> [--kill]" >&2; exit 2; }
RESULT=""; RECV=""; PLAN_ONLY=0; PO_WT=""; KILL=1; IDLE_MIN="${FT_NANO_IDLE_MIN:-3}"; CHERRY_OVERRIDE=""; HAVE_CHERRY_OVERRIDE=0; SUPER=0; SUPERSEDED=""; SHARED=0; HAVE_NWT=0; HAVE_NBR=0; NWT=""; NBR=""; SUSP=0; SUSP_REASON=""; SUSP_SET=""
while [ $# -gt 0 ]; do case "$1" in --result) RESULT="$2"; shift 2;; --recv) RECV="$2"; shift 2;; --kill) KILL=1; shift;; --plan-only) [ $# -ge 2 ] || { echo "usage: --plan-only <워크트리 경로> (경로 인자 누락)" >&2; exit 2; }; PLAN_ONLY=1; PO_WT="$2"; shift 2;; --shared-wt) SHARED=1; shift;;
  --wt) [ $# -ge 2 ] || { echo "usage: --wt <경로> (경로 인자 누락)" >&2; exit 2; }; HAVE_NWT=1; NWT="$2"; shift 2;;
  --branch) [ $# -ge 2 ] || { echo "usage: --branch <이름> (이름 인자 누락)" >&2; exit 2; }; HAVE_NBR=1; NBR="$2"; shift 2;;
  --cherry-override) [ $# -ge 2 ] || { echo "usage: --cherry-override <사유> (사유 인자 누락)" >&2; exit 2; }; HAVE_CHERRY_OVERRIDE=1; CHERRY_OVERRIDE="$2"; shift 2;;
  --superseded-by) [ $# -ge 2 ] || { echo "usage: --superseded-by <대체 카드 경로> (경로 인자 누락)" >&2; exit 2; }; SUPER=1; SUPERSEDED="$2"; shift 2;;
  --suspended) [ $# -ge 2 ] || { echo "usage: --suspended <사유> (사유 인자 누락)" >&2; exit 2; }; SUSP=1; SUSP_REASON="$2"; shift 2;;
  *) echo "unknown $1" >&2; exit 2;; esac; done
# --suspended(r450): 빈 사유·다른 우회 인자와 동시 = usage(2) — ⑤·⑥ 우회 사유가 둘이 되면 원장 사유가 갈린다(--superseded-by 와 같은 꼴)
if [ "$SUSP" -eq 1 ] && [ -z "${SUSP_REASON//[[:space:]]/}" ]; then echo "usage: --suspended 사유가 비어 있음(사유 없는 면제 거부)" >&2; exit 2; fi
case "$SUSP_REASON" in *$'\n'*|*$'\r'*) echo "usage: --suspended 사유는 한 줄이어야 한다" >&2; exit 2;; esac
if [ "$SUSP" -eq 1 ] && [ "$SUPER" -eq 1 ]; then echo "usage: --suspended 와 --superseded-by 는 동시에 못 쓴다(⑥ 면제 사유가 둘이 된다)" >&2; exit 2; fi
if [ "$SUSP" -eq 1 ] && [ "$HAVE_CHERRY_OVERRIDE" -eq 1 ]; then echo "usage: --suspended 와 --cherry-override 는 동시에 못 쓴다(⑤ 우회 사유가 둘이 된다 · --suspended 가 ⑤ 에 사유를 넘긴다)" >&2; exit 2; fi
# --superseded-by: 빈 값·--cherry-override 와 동시 지정은 close 입구에서 usage(2) — ⑤ 우회 길이 둘이 되면 원장 사유가 갈린다(R171)
if [ "$SUPER" -eq 1 ] && [ -z "${SUPERSEDED//[[:space:]]/}" ]; then echo "usage: --superseded-by 경로가 비어 있음" >&2; exit 2; fi
if [ "$SUPER" -eq 1 ] && [ "$HAVE_CHERRY_OVERRIDE" -eq 1 ]; then echo "usage: --superseded-by 와 --cherry-override 는 동시에 못 쓴다(⑤ 우회 사유가 둘이 된다)" >&2; exit 2; fi
# ⑤ cherry 게이트 사람 우회 — 사유 빈 문자열은 cherry-gate 의 REJECT 에 기대지 않고 close 입구에서 usage(2) (M7 · arch#141 #53675)
if [ "$HAVE_CHERRY_OVERRIDE" -eq 1 ] && [ -z "${CHERRY_OVERRIDE//[[:space:]]/}" ]; then echo "usage: --cherry-override 사유가 비어 있음(사유 없는 우회 거부)" >&2; exit 2; fi
# --wt/--branch(명시 모드) — «둘 다» 있어야 하고(자동 판별 0) --shared-wt 와 같이 쓰지 못한다. 빈 값도 usage.
NAMED=0
if [ "$HAVE_NWT" -ne "$HAVE_NBR" ]; then echo "usage: --wt 와 --branch 는 둘 다 명시해야 한다(하나만 = 거부)" >&2; exit 2; fi
if [ "$HAVE_NWT" -eq 1 ]; then
  { [ -n "$NWT" ] && [ -n "$NBR" ]; } || { echo "usage: --wt/--branch 값이 비어 있음" >&2; exit 2; }
  [ "$SHARED" -eq 0 ] || { echo "usage: --shared-wt 와 --wt/--branch 는 같이 쓰지 못한다" >&2; exit 2; }
  NAMED=1
fi
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$HERE/ft-team-lib.sh" ]; then . "$HERE/ft-team-lib.sh"; else echo "WARN ft-team-lib.sh 없음($HERE) — 카드 쌍둥이 경로 후보 0(R382 전환 기간 역호환 꺼짐)" >&2; fi
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
# ★팀 env 자동 로드 (카드 nano-spawn-close-team-env §1)★: FT_NANO_PREFIX 가 이미 있으면 «명시가 이긴다» — 아무것도 안 한다.
#   없으면 좌석명 byz-<팀>-nano-… 의 팀으로 $ROOT/.fable-team/bin-<팀>/<팀>-env.sh 를 source(파일 없으면 추측 없이 REJECT). 옛 이름(ft-v65-temp-*)은 기본값 그대로.
if [ -z "${FT_NANO_PREFIX:-}" ]; then
  _team=""; [[ "$SEAT" =~ ^byz-([a-z0-9]+)-nano- ]] && _team="${BASH_REMATCH[1]}"
  if [ -n "$_team" ]; then
    _tenv="$ROOT/.fable-team/bin-$_team/$_team-env.sh"
    [ -f "$_tenv" ] || { echo "REJECT 팀 env 없음: $_tenv"; exit 1; }
    . "$_tenv"
  fi
  echo "ENV team=${_team:-default} prefix=${FT_NANO_PREFIX:-ft-v65-temp-} seats=${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
fi
# ★라이브 bin 드리프트 입구 검사 (카드 live-bin-drift-check · Issue 816 ③)★: 설치 꼴(*/.fable-team/bin)에서 돌 때만 — 라이브 도구가 origin/main 키트와 다르면 닫지 않는다(bad=() 에 안 넣고 입구에서 종료).
#   검사 스크립트가 없는 것도 드리프트(설치 누락). 우회 스위치 없음 — 해결은 master 라이브 cp.
case "$HERE" in
  */.fable-team/bin|*/.fable-team/*/bin|*/fable-team/live/*/bin)   # r385: 버전 폴더 설치 꼴 포함 · 키트 리포 = 하네스 코드 루트(--repo 생략)
    if [ ! -f "$HERE/ft-live-bin-drift-check.sh" ]; then echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시 (ft-live-bin-drift-check.sh 설치 누락)"; exit 1; fi
    _dout="$(bash "$HERE/ft-live-bin-drift-check.sh" --bin "$HERE")" || { printf '%s\n' "$_dout"; echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시"; exit 1; }
    printf '%s\n' "$_dout";;
  *) echo "INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $HERE";;
esac
NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"
# 좌석 워크트리 접두(spawn 123행과 같은 env) — 정규식에 들어가므로 소문자·숫자·'-' 만 허용(그 밖은 추측 없이 REJECT).
WT_PREFIX="${FT_NANO_WT_PREFIX:-v65-}"
[[ "$WT_PREFIX" =~ ^[a-z0-9-]+$ ]] || { echo "REJECT FT_NANO_WT_PREFIX(${WT_PREFIX}) 는 소문자·숫자·'-' 만 허용"; exit 1; }
case "$SEAT" in "$NANO_PREFIX"*) ;; *) echo "REJECT 나노(${NANO_PREFIX}*)만 닫는다: $SEAT"; exit 1;; esac   # role 무관(nano·impl·checker·tester 전부 temp- 접두)
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"; COMM="${FT_INBOX_ROOT:-$ROOT/.fable-team/comm}"
# 원장 = 리포 고정(운영 정본 = v6-realtime-live 워크트리 · FT_NANO_LEDGER_WT 로 override). $WT 에 묶지 않는다 — 나노가 자기 워크트리에서 부르면 원장이 삭제 대상 안에 놓인다(DA r2 C).
LEDGER_WT="${FT_NANO_LEDGER_WT:-$ROOT/.worktrees/v6-realtime-live}"; [ -d "$LEDGER_WT" ] || LEDGER_WT="$WT"
# R383 → R400 r3(판정 2307 ①): 기본 원장 = «명단은 ref · 폴더는 원장 워크트리» — 팀 명단은 FT_TEAMS_REF(기본 origin/main)의 design/TEAMS.md 에서 읽고(원장 워크트리 사본이 옛 명단이어도 무관),
#   그 명단 꼴·쌍둥이 후보 중 원장 파일이 실재하는 «정확히 1개» 만 쓴다. 0·2+·명단 못 읽음 = REJECT(#0 RULE — 옛 경로 후퇴·추측 0). FT_NANO_LEDGER 명시가 이긴다.
if [ -n "${FT_NANO_LEDGER:-}" ]; then LEDGER="$FT_NANO_LEDGER"
else
  _ref="${FT_TEAMS_REF:-origin/main}"; _lrel="20260912/NANO-LEDGER-pm1-temp-sessions.md"
  _cands="$(ft_team_cands_ref "$LEDGER_WT" v65 "$_ref" 2>&1)" || { case "$_cands" in *"못 읽음"*) echo "REJECT 팀 명단($_ref)을 못 읽음 — FT_NANO_LEDGER 로 지정 ($LEDGER_WT)";; *) echo "REJECT v65 팀 폴더를 못 풀었다(명단 $_ref) — ${_cands:-사유 없음} · FT_NANO_LEDGER 로 지정";; esac; exit 1; }
  _ln=0; _lf=""; _lall=""
  while IFS= read -r _c; do [ -n "$_c" ] || continue; _lall+=" $_c/$_lrel"; [ -f "$_c/$_lrel" ] && { _ln=$((_ln+1)); _lf+="${_lf:+ · }$_c/$_lrel"; }; done <<< "$_cands"
  case "$_ln" in
    1) LEDGER="$_lf"; echo "INFO 원장 ← $LEDGER (명단 $_ref)";;
    0) echo "REJECT v65 원장을 못 찾았다 — 후보:$_lall (FT_NANO_LEDGER 로 지정)"; exit 1;;
    *) echo "REJECT v65 원장 후보 ${_ln}개: $_lf (FT_NANO_LEDGER 로 지정)"; exit 1;;
  esac
fi
case "$LEDGER" in /*) ;; *) LEDGER="$LEDGER_WT/$LEDGER";; esac
# R400 r3(판정 2307 ②) fail-closed 입구: 명부·원장이 없으면 닫지 않는다 — 아래 명부 pop·원장 append 가 «없는 파일» 위에서 실패하고도 CLOSED 를 찍던 자리(airag 1.0.1 실사건 · 1.1.4 도 같은 꼴). tmux 조회·변경 전.
[ -f "$SEATS" ] || { echo "REJECT 명부 없음: $SEATS — FT_SEATS_JSON 으로 지정(워크트리 .fable-team/seats.json 이면 그 절대경로)"; exit 1; }
{ [ -f "$LEDGER" ] && [ -w "$LEDGER" ]; } || { echo "REJECT 원장 없음/쓰기 불가: $LEDGER"; exit 1; }
WT_CLEAN_DIR="${FT_WT_CLEAN_DIR:-$ROOT/.fable-team/state/wt-clean}"

# 계획 «생성» — 좌석의 워크트리 = $ROOT/.worktrees/<WT 접두(기본 v65-)><seat 에서 접두·#N 제거>. 없으면 PLAN="" · WT_MARK=none.
# key 는 $_KEY(하단 ③ 에서 1회 계산) 를 그대로 쓴다 — 두 곳에서 따로 계산하면 한쪽만 바뀔 때 ABSENT 판정과 계획 워크트리가 어긋난다(DA r5 MINOR 3).
_wt_clean_plan() {
  local key="$_KEY"
  local wt="$SEAT_WT"   # _resolve_seat_wt 의 값(-rN 포함) — 여기서 다시 조립하지 않는다
  PLAN=""; WT_MARK=none
  [ -n "$wt" ] && [ -d "$wt" ] || return 0
  mkdir -p "$WT_CLEAN_DIR"; PLAN="$WT_CLEAN_DIR/$SEAT.sh"; WT_MARK=planned
  # --wt/--branch: 자율 정리 범위 밖(브랜치 nano/* 아님) — sweep(*.sh 순회) 밖인 .sh.hil 로만 생성한다. 실행은 사람(! bash <계획>).
  [ "$NAMED" != 1 ] || PLAN="$WT_CLEAN_DIR/$SEAT.sh.hil"
  [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || WT_MARK="planned(autoclean=0)"
  # r166 계획 버전 표식 — 이 생성기 파일의 blob sha. ft-wt-sweep.sh 가 «옆의 라이브 생성기» 와 대조해 다르면 실행을 거부한다(옛 생성기 계획 = 옛 가드).
  local planver; planver="$(git hash-object -- "$HERE/ft-nano-close.sh" 2>/dev/null)"
  {
    printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 %s 에 생성. 가드 6 → ignored 보관 → WIP 커밋 → 이름 바꾸기(worktree move) → 분리 정리(baton wt-clean). 브랜치는 지우지 않는다.\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '# plan-ver: %s\n' "$planver"
    printf '# baton 부작용(승인 범위에 명시): 아카이브 30일 초과분 prune · 분기 원장(.baton/branches.json) 의 같은 child_branch 행 status=abandoned.\n'
    # FT_NANO_WIP 는 close 실행 시점 값을 계획에 «굽는다» — sweep 은 나중 다른 프로세스/환경에서 돌아 close 의 env 를 못 물려받는다.
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q; LEDGER=%q; PLAN=%q; FT_NANO_WIP=%q; NAMED_BR=%q; SWEEPER=%q; GEN=%q; PLANVER=%q; PLAN_ONLY=%q; LANDCHK=%q; MAINREF=%q; ROOTR=%q\n' "$SEAT" "$key" "$wt" "$NANO_PREFIX" "$LEDGER" "$PLAN" "${FT_NANO_WIP:-0}" "$([ "$NAMED" = 1 ] && echo "$NBR")" "$HERE/ft-wt-sweep.sh" "$HERE/ft-nano-close.sh" "$planver" "$PLAN_ONLY" "$HERE/ft-landed-check.sh" "${PO_MAINREF:-}" "$ROOT"
    cat <<'SH'
# r173 자기검사 — 어떤 동작보다 먼저: 생성기의 «지금» blob sha 가 굽힌 plan-ver 와 같을 때만 계속한다(사람이 bash 로 직접 실행하는 .sh.hil 도 sweep 을 거치지 않고 여기서 멈춘다). 비교 불능(생성기 없음·hash 실패·빈 plan-ver)도 STALE.
_lv="$(git hash-object -- "$GEN" 2>/dev/null)" || _lv=""
[ -n "$_lv" ] && [ "$_lv" = "$PLANVER" ] || { echo "STALE $SEAT — 옛 생성기 계획 실행 거부(plan-ver=${PLANVER:-없음} ≠ 라이브 생성기=${_lv:-없음}) · 재생성: ft-nano-close.sh $SEAT 를 다시 돌려 새 계획을 만든다"; exit 3; }
set -uo pipefail
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"
# ★변수명 TMUX 금지★ — tmux 가 $TMUX 를 소켓 경로로 읽는다(r3 시험에서 «error connecting to /opt/homebrew/bin/tmux» 실측). 바이너리는 TMUX_BIN.
LSOF="${FT_LSOF_BIN:-/usr/sbin/lsof}"; TMUX_BIN="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)}"
# 원장 표식 — 좌석명 행(그 좌석의 «마지막» 닫힘 행)의 wt= 필드 교체. mkdir 락(<원장>.lock · 최대 10s) 아래 read→write · 실패는 stdout+exit 1 (#0 RULE · DA r2 B)
mark() {
  local lock="$LEDGER.lock" i=0 rc
  until mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ "$i" -lt 100 ] || { echo "skipped:원장 락 실패($lock)"; exit 1; }; sleep 0.1; done
  python3 - "$LEDGER" "$SEAT" "$1" <<'PY'
import os, re, sys
p, seat, val = sys.argv[1:4]
s = open(p, encoding="utf-8").read(); lines = s.split("\n")
key = "`%s` 닫힘(ft-nano-close)" % seat
idx = [i for i, l in enumerate(lines) if key in l]
if not idx: sys.exit(3)
i = idx[-1]; lines[i] = re.sub(r"( · wt=.*)?$", " · wt=" + val, lines[i], count=1)
tmp = p + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f: f.write("\n".join(lines)); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)
PY
  rc=$?; rmdir "$lock"
  { [ "$rc" -eq 3 ] && [ "${PLAN_ONLY:-0}" = 1 ]; } && return 0   # --plan-only 계획: close 를 거친 적 없는 좌석 = 원장에 닫힘 행이 없다(표식할 곳 없음 · 실패 아님)
  [ "$rc" -eq 0 ] || { echo "skipped:원장 표식 실패(rc=$rc · $SEAT 행 없음=3)"; exit 1; }
}
fail() { mark "skipped:$1"; echo "skipped:$1"; exit 1; }
[ -d "$WT" ] || { mark none; echo none; exit 0; }
# ① 계보(<PREFIX><KEY>#N) 세션 — «자기 포함» 0. tmux 실패는 「no server running」만 0세션으로 인정, 그 외(바이너리 없음·소켓 오류)는 skipped (DA r2 R12)
# r8(DA r7 조건1): rc=1 요건 추가 — 「소켓 없음」 문구만 0세션(그 외 rc1 연결 장애는 skipped, close 쪽과 같은 좁힘).
[ -x "$TMUX_BIN" ] || fail "tmux 실행 불가($TMUX_BIN)"
out="$("$TMUX_BIN" ls -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$rc:$out" in
    1:*"no server running"*) out="";;
    1:*"error connecting to "*"(No such file or directory)"*)
      # r9(오빠 판정 ㉙ Q5)+r10(DA r9 M1·M2): 소켓 파일만 없고 서버 프로세스가 살아있으면 고아 서버 — 0세션이 아니라 REJECT.
      # M2: -a 로 호출자 조상(서버 자신) 도 포함(pgrep 기본은 조상 제외). M1: -U "$(id -u)" 로 fail-open 제거 · rc 를 |wc -l 로 삼키지 않고 분리.
      n=0
      op="$(pgrep -a -U "$(id -u)" -x tmux 2>&1)"; prc=$?
      case "$prc" in 0) n="$(printf '%s\n' "$op" | grep -c .)";; 1) n=0;; *) fail "pgrep 실패(rc=$prc: ${op:0:60})";; esac
      if [ -n "${FT_TMUX_BIN:-}" ]; then
        op2="$(pgrep -a -U "$(id -u)" -f "$TMUX_BIN" 2>&1)"; prc2=$?
        case "$prc2" in 0) n=$((n + $(printf '%s\n' "$op2" | grep -c .)));; 1) ;; *) fail "pgrep 실패(rc=$prc2: ${op2:0:60})";; esac
      fi
      [ "$n" -eq 0 ] || fail "③고아 tmux 서버(pgrep ${n} · 소켓 부재)"
      out="";;
    *) fail "tmux 조회 실패(rc=$rc: ${out:0:60})";;
  esac
fi
live="$(printf '%s\n' "$out" | grep -x "${PREFIX}${KEY}#[0-9]*" | tr '\n' ' ')"
[ -z "$live" ] || fail "좌석 ${live% }"
# ② 워크트리를 cwd 로 쥔 프로세스 0 (tmux 밖 node·mcp·zsh 포함). lsof 절대경로 + 실행 가능 + 종료코드를 grep 과 분리(fail-closed · DA r2 R12)
[ -x "$LSOF" ] || fail "lsof 실행 불가($LSOF)"
lsout="$("$LSOF" -Fn -d cwd 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || fail "lsof 실패(rc=$rc)"
holders="$(printf '%s\n' "$lsout" | grep -cE "^n${WT}(/|$)")"
[ "$holders" -eq 0 ] || fail "cwd 보유 프로세스 ${holders}개"
# ③ .worktree-info.json 의 branch 가 nano/*  (--wt/--branch 계획: 브랜치는 close 가 확인해 구워 둔 값 — 사람이 실행하는 계획이라 nano/* 를 요구하지 않는다)
#   r166 껍데기 인식: 상한 TERM 으로 «지우다 만» 워크트리는 .worktree-info.json 도 이미 사라졌을 수 있다. tracked 가 전부 ' D'(작업 트리에서만 지워짐)뿐이면 info 대신 HEAD 브랜치로 판정(그 외 미커밋이 한 줄이라도 있으면 기존 그대로).
if [ -n "$NAMED_BR" ]; then br="$NAMED_BR"
else
br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$WT/.worktree-info.json" 2>/dev/null)"
if [ -z "$br" ]; then
  _st="$(git -C "$WT" status --porcelain 2>/dev/null)"
  if [ "$(printf '%s\n' "$_st" | grep -v '\.serena/project\.yml$' | grep -v '^ D ' | grep -c .)" -eq 0 ] && [ "$(printf '%s\n' "$_st" | grep -c '^ D ')" -gt 0 ]; then
    br="$(git -C "$WT" symbolic-ref --short -q HEAD)"
  fi
fi
case "$br" in nano/*) ;; *) fail "branch=${br:-?} (nano/* 아님)";; esac
fi
# ④ 도달성 — HEAD 브랜치 = info branch(detached 금지) 이고 HEAD 가 refs/heads/<br> 에 포함 (DA r1 R1②)
hb="$(git -C "$WT" symbolic-ref --short -q HEAD)"
[ "$hb" = "$br" ] || fail "HEAD=${hb:-detached} ≠ info $br"
git -C "$WT" merge-base --is-ancestor HEAD "refs/heads/$br" || fail "HEAD 가 $br 에 미포함"
# ④b 착지 재검증(--plan-only 계획 한정 · r-disk-drop-worktree-scratch-census DA⑥ HOLD 2) — 계획 «실행 시점» 에도 가지가 main 에 착지했는가(생성 뒤 커밋이 붙었으면 거부). 일반 close 계획은 ⑤ cherry 게이트가 이미 닫았다(동작 불변).
if [ "${PLAN_ONLY:-0}" = 1 ]; then
  _lw="$(bash "$LANDCHK" "$ROOTR" "$MAINREF" "$br" "$(printf '%s' "$br" | sed 's|^nano/||; s|-r[0-9][0-9]*$||')" 2>/dev/null)" || fail "착지 재검증 실패(${_lw:-no}) — $br 가 $MAINREF 에 착지하지 않았다"
fi
# ⑤ 미커밋 상태 확인.
#   r8(DA r7 잔여 질문1): #30467 「dirty 는 [wip] 커밋」은 20건 백필 맥락이었다 — 답 전까지 «백필 한정 플래그»로 분리해
#   어느 판정이든(영구 적용/백필 한정) 수용한다. FT_NANO_WIP=1 일 때만 아래 새 경로, 미설정(기본)은 r6 이전 기존 REJECT.
if [ "${FT_NANO_WIP:-0}" = 1 ]; then
  # r7 · 하네스 0.5 행 2 · 오빠 판정 #30467 「dirty 는 [wip] 커밋 경로」 · DA r6 잔여 질문 2 정리.
  # 브랜치는 지우지 않으므로 커밋해 두면 baton wt-clean 뒤에도 git 이력으로 복원 가능 — REJECT 로 워크트리를 잔존시키는 쪽이 더 나쁘다(#0 RULE).
  # r8(DA r7 MAJOR 2): baton 자신이 만드는 임시 재생성물 .unmerged-changes.patch 는 커밋 대상이 아니다 — add -A 전에 지운다(언제든 재생성됨).
  rm -f "$WT/.unmerged-changes.patch"
  dirty="$(git -C "$WT" status --porcelain)"
  # r8(DA r7 MAJOR 2): untracked 합계 상한 — baton 산출물이 중단돼 수 GB 로 남으면 커밋이 눈덩이가 된다(k6/k7 실측). 상한 초과는 REJECT(사람 판정).
  cap="${FT_WT_DIRTY_CAP_BYTES:-52428800}"
  usum=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    sz="$(stat -f '%z' "$WT/$p" 2>/dev/null || echo 0)"
    usum=$((usum + sz))
  done < <(git -C "$WT" ls-files -o --exclude-standard)
  [ "$usum" -le "$cap" ] || fail "dirty 대용량(${usum}B > ${cap}B)"
else
  # 기존(r6 이전) 동작 — 실작업물(.serena/project.yml 제외) 있으면 REJECT, .serena 만 있으면 그 아래 WIP 커밋으로.
  # r-wt-clean-deletion-only: 작업 트리에서만 지워진 줄(' D' = 인덱스 칸 공백 · 작업 트리 칸 D)은 «지우다 만 흔적» — 내용은 브랜치에 그대로 있다. 실작업물로 세지 않고 [wip] 에도 담지 않는다(삭제 커밋은 브랜치를 망가뜨린다).
  dirty="$(git -C "$WT" status --porcelain)"
  ndel="$(printf '%s\n' "$dirty" | grep -v '\.serena/project\.yml$' | grep -c '^ D ')"
  real="$(printf '%s\n' "$dirty" | grep -v '\.serena/project\.yml$' | grep -v '^ D ' | grep -c .)"
  [ "$real" -eq 0 ] || fail "실작업물 미커밋 ${real}파일"
fi
# ⑥ ignored — 재생성 허용 목록(이름 · «임의 깊이»의 경로 요소에 적용 · DA r2 A)을 뺀 나머지를 <PLAN>.ignored.tar.gz 로 보관한 뒤 진행 (DA r1 R1③')
#   ★파일 단위로 센다(`ls-files -o -i`)★ — `status --ignored` 는 «내용이 전부 ignored 인 디렉터리»를 `clients/` 한 줄로 접어 그 안의 node_modules 가 안 보인다(r3 실측).
allow="${FT_WT_IGNORED_ALLOW:-.env .venv venv .worktree-info.json .serena node_modules .next __pycache__ .pytest_cache .ruff_cache .mypy_cache .turbo dist build coverage}"
list="$PLAN.ignored.list"; : > "$list"
while IFS= read -r p; do
  [ -n "$p" ] || continue; skip=0
  IFS=/ read -ra segs <<< "$p"
  for seg in "${segs[@]}"; do case " $allow " in *" $seg "*) skip=1; break;; esac; done
  [ "$skip" = 1 ] || printf '%s\n' "$p" >> "$list"
done < <(git -C "$WT" ls-files -o -i --exclude-standard)
nkeep="$(grep -c . "$list")"
if [ "$nkeep" -gt 0 ]; then
  tar -C "$WT" -czf "$PLAN.ignored.tar.gz" -T "$list" || fail "ignored 보관 실패(${nkeep}파일)"
else rm -f "$list"; fi
# 미커밋(실작업물 포함, r7)은 WIP 커밋 성공 뒤에만 진행 — 실패하면 정리 자체를 REJECT(#0 RULE, 조용히 버리지 않는다)
# r9(오빠 판정 ㉙ Q4): .serena/project.yml 은 activate_project 가 매번 갱신하는 노이즈 — WIP 커밋 전에 되돌린다(tracked 인 경우만 · untracked 는 대상 아님).
if git -C "$WT" ls-files --error-unmatch .serena/project.yml >/dev/null 2>&1; then
  # r10(DA r9 MINOR b 채택): staged(M ) 상태에서도 「.serena-only = [wip] 0」 이 되도록 index 가 아니라 HEAD 기준으로 되돌린다.
  git -C "$WT" checkout HEAD -- .serena/project.yml || fail ".serena/project.yml checkout 실패"
  dirty="$(git -C "$WT" status --porcelain)"
fi
[ "${FT_NANO_WIP:-0}" = 1 ] || dirty="$(printf '%s\n' "$dirty" | grep -v '^ D ')"   # 기본 경로: 여기까지 왔으면 실작업물 0 — 남은 ' D' 는 [wip] 대상이 아니다
if [ -n "$dirty" ]; then
  # 기본 경로: add -A 가 ' D' 삭제도 올리므로 «add 전에» 삭제 목록을 떠 두고 add 뒤 index 에서 되돌린다(브랜치 보존 · 추적 안 된 .serena 가 남아 dirty 가 비지 않는 경우 포함).
  delf="$(mktemp)"; [ "${FT_NANO_WIP:-0}" = 1 ] || git -C "$WT" diff --name-only --diff-filter=D -z > "$delf"
  git -C "$WT" add -A || { rm -f "$delf"; fail "wip add 실패"; }
  if [ -s "$delf" ]; then xargs -0 git -C "$WT" reset -q -- < "$delf" || { rm -f "$delf"; fail "wip 삭제 제외(reset) 실패"; }; fi
  rm -f "$delf"
  git -C "$WT" commit -q -m "[wip] nano close $SEAT" || fail "wip commit 실패"
fi
# ★r166 2단 정리★ ①이름 바꾸기(worktree move · 즉시) → ②분리 프로세스에서 baton 정리 + prune(상한 밖).
#   120초 상한 TERM 이 삭제 도중 걸려도 원래 경로엔 껍데기가 남지 않는다(이름 바뀐 .deleting-<ts> 만 · sweep 이 이어서 정리).
#   보관(baton archive)은 ②의 첫 단계 — 실패하면 삭제를 하지 않고 .deleting-<ts> 가 남아 sweep 이 재시도한다.
ROOTD="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOTD" ] || fail "리포 루트 판별 실패"
[ -f "$SWEEPER" ] || fail "ft-wt-sweep.sh 없음($SWEEPER) — 분리 정리를 걸 수 없다"
DEL="$WT.deleting-$(date +%s)"
git -C "$ROOTD" worktree move "$WT" "$DEL" || fail "worktree move 실패"
[ ! -e "$WT" ] || fail "move 뒤에도 원래 경로 남음"
printf '%s\n%s\n' "$DEL" "$ROOTD" > "$PLAN.deleting"
( cd "$ROOTD" && perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' /bin/bash "$SWEEPER" --finish "$PLAN.deleting" >> "$PLAN.finish.log" 2>&1 < /dev/null & )
res=cleaned; [ -f "$PLAN.ignored.tar.gz" ] && res="cleaned(ignored ${nkeep}파일 보관)"
if [ "${ndel:-0}" -gt 0 ]; then
  res="cleaned(삭제만 ${ndel}파일 · 복원 = git worktree add $WT $br)"
  [ ! -f "$PLAN.ignored.tar.gz" ] || res="cleaned(삭제만 ${ndel}파일 · ignored ${nkeep}파일 보관 · 복원 = git worktree add $WT $br)"
fi
res="$res · 이름 바꿈 → ${DEL##*/} (파일 정리는 분리 진행)"
mark "$res"; echo "$res"
SH
  } > "$PLAN"
  chmod 755 "$PLAN"
}
# 세션이 사라진 뒤(--kill KILLED 직후)의 실행 — 결과는 계획이 원장에 직접 표식. skipped 는 사람 판정 분기 → stdout [HIL](호출자가 mbox 로 올린다).
_wt_clean_run() {
  local res
  res="$(/bin/bash "$PLAN" 2>&1 | tee "$PLAN.log" | tail -1)"
  # [HIL] 은 1회만 — 계획을 <seat>.sh.hil 로 옮겨 sweep 순회에서 뺀다(사람이 .sh 로 되돌리면 재시도 · DA r3 MAJOR N1)
  case "$res" in cleaned*|none) mv "$PLAN" "$PLAN.done";; skipped:좌석*|skipped:cwd*) ;; *) mv "$PLAN" "$PLAN.hil"; echo "[HIL] ${res#skipped:} · 스크립트 $PLAN.hil";; esac
  echo "워크트리 정리: $res (로그 $PLAN.log)"
}
bad=()
# ① 결과 보존
[ -n "$RESULT" ] && [ -e "$RESULT" ] || bad+=("①결과 경로 없음: ${RESULT:-<미지정>}")
# ② master 회수 — 그 seq 가 실제로 존재했는가 (행이 소비돼도 bodies/<seq>.txt 또는 카운터 이하)
if [ -z "$RECV" ]; then bad+=("②--recv <seq> 미지정")
elif ! { [ -f "$COMM/bodies/$RECV.txt" ] || grep -q "\"seq\": *$RECV," "$COMM/mailbox.jsonl" 2>/dev/null || [ "$RECV" -le "$(cat "$COMM/.mbox-seq" 2>/dev/null || echo 0)" ]; }; then
  bad+=("②seq $RECV 가 우편함 기록에 없다")
fi
# ③ 실제 유휴 — pane 이 아니라 jsonl 마지막 레코드 시각 (pane ❯ 는 ghost 를 못 가른다)
# pane_id 경유 — `-t "=$SEAT"` 는 `#` 든 이름에 display-message 가 빈 값을 돌려준다(실측 2026-09-14)
# 하네스 0.5 행 2 r6(DA r5 MAJOR 1): tmux 조회 자체의 성공을 먼저 본다 — 계획 본문 가드 ①(:71-77)과 같은 규칙.
# r7(DA r6 MAJOR 2ⓐ): no-server 판정을 좁힌다 — rc=1 «이고» 메시지에 no server running|error connecting to 가 있을 때만 0세션.
# r8(DA r7 MAJOR 1 — 회귀): r7 의 "error connecting to" 단독 매칭이 «모든» 소켓 연결 장애(Operation not permitted 등, 전부 rc1)를
# 서버없음으로 삼켰다 — 생존 좌석까지 ABSENT 로 넘겼다(재현 C1). 「소켓 파일 자체가 없다」는 문구까지 요구해 좁힌다.
tmux_out="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>&1)"; tmux_rc=$?; tmux_ok=1
if [ "$tmux_rc" -ne 0 ]; then
  case "$tmux_rc:$tmux_out" in
    1:*"no server running"*) tmux_out="";;
    1:*"error connecting to "*"(No such file or directory)"*)
      # r9(오빠 판정 ㉙ Q5)+r10(DA r9 M1·M2): 소켓 파일만 없고 서버 프로세스가 살아있으면 고아 서버 — 0세션이 아니라 REJECT(같은 화이트리스트, 계획 본문 guard①과 동일).
      n=0
      op="$(pgrep -a -U "$(id -u)" -x tmux 2>&1)"; prc=$?
      case "$prc" in 0) n="$(printf '%s\n' "$op" | grep -c .)";; 1) n=0;; *) tmux_ok=0; bad+=("③pgrep 실패(rc=$prc: ${op:0:60})");; esac
      if [ "$tmux_ok" = 1 ] && [ -n "${FT_TMUX_BIN:-}" ]; then
        op2="$(pgrep -a -U "$(id -u)" -f "$FT_TMUX_BIN" 2>&1)"; prc2=$?
        case "$prc2" in 0) n=$((n + $(printf '%s\n' "$op2" | grep -c .)));; 1) ;; *) tmux_ok=0; bad+=("③pgrep 실패(rc=$prc2: ${op2:0:60})");; esac
      fi
      if [ "$tmux_ok" = 1 ]; then
        if [ "$n" -gt 0 ]; then tmux_ok=0; bad+=("③고아 tmux 서버(pgrep ${n} · 소켓 부재)")
        else tmux_out=""; fi
      fi
      ;;
    *) tmux_ok=0; bad+=("③tmux 조회 실패(rc=$tmux_rc: ${tmux_out:0:60})");;
  esac
fi
PANE="$(printf '%s\n' "$tmux_out" | awk -F'|' -v s="$SEAT" '$1==s{print $2; exit}')"
# r7(DA r6 MAJOR 2ⓑ): PANE 은 있는데 display-message 가 실패하거나 빈 경로를 주면 ABSENT 가 아니라 REJECT — ABSENT 는 «PANE 자체가 없을 때」만.
cwd=""
if [ -n "$PANE" ]; then
  cwd="$(tmux display-message -p -t "$PANE" '#{pane_current_path}' 2>&1)"; dm_rc=$?
  if [ "$dm_rc" -ne 0 ] || [ -z "$cwd" ]; then bad+=("③pane 경로 조회 실패(rc=$dm_rc)"); tmux_ok=0; cwd=""; fi
fi
# 하네스 0.5 행 2 r5(오빠 판정 #30467): 세션이 먼저 죽은 좌석 — 세션 없음 + 워크트리 실재는 REJECT 대신 「세션 없음 자체가 충족」(유휴 검사 불요).
# 워크트리 부재(닫을 것 없음)는 기존 REJECT 유지. ABSENT 는 아래 명부/원장 처리 분기에서만 쓴다. tmux_ok=0 이면 이 블록 전체를 건너뛴다(위에서 이미 REJECT 사유 기록).
_KEY="${SEAT#"$NANO_PREFIX"}"; _KEY="${_KEY%#*}"
# 좌석 워크트리 해석 «한 곳» (M7 · 재착수 -rN) — spawn 은 옛 브랜치가 있으면 <접두><key>-r2·-r3… 로 만든다. 아래 ③·⑥·⑤ 와 wt-clean 계획이 전부 이 값(SEAT_WT·SEAT_BR)만 쓴다.
#   «등록된 후보» = 현재 리포 `git worktree list --porcelain` 에 있고 ∧ $ROOT/.worktrees/ 아래 ∧ 좌석 브랜치(nano/<key>[-rN])를 체크아웃한 워크트리 (DA607 H2 — 외부 리포·경계 밖 경로는 후보가 아니다).
#   ①살아 있는 pane cwd 의 toplevel 이 등록된 후보면 그것(아니면 ②로 후퇴) ②후보 중 이름이 <접두><key>[-rN] (접두 = FT_NANO_WT_PREFIX, 기본 v65-) 인 것이 «정확히 1개»일 때만.
#   SEAT_WT_ERR(후보 2개 이상 · pane 살아 있는데 후보 0) = cwd 유무·역할과 무관하게 아래에서 REJECT(DA607 H1 · 추측 금지 · fail-closed) · 세션 없음 ∧ 후보 0 = 빈 값(기존 «워크트리 없음» 판정).
_is_seat_branch() { [[ "$1" =~ ^nano/${_KEY}(-r[0-9]+)?$ ]]; }
_resolve_seat_wt() {
  SEAT_WT=""; SEAT_BR=""; SEAT_WT_ERR=""; SEAT_WT_NOCAND=0
  local top="" p br rel i hits=() brs=() lp=() lb=() base="$ROOT/.worktrees/"
  while IFS=$'\t' read -r p br; do
    rel="${p#"$base"}"; [ "$rel" != "$p" ] || continue
    _is_seat_branch "$br" || continue
    lp+=("$p"); lb+=("$br")
  done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk '/^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8); sub("^refs/heads/","",b); print p "\t" b}')
  if [ -n "$cwd" ]; then
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    for ((i=0; i<${#lp[@]}; i++)); do
      if [ -n "$top" ] && [ "${lp[$i]}" = "$top" ]; then SEAT_WT="$top"; SEAT_BR="${lb[$i]}"; return 0; fi
    done
  fi
  for ((i=0; i<${#lp[@]}; i++)); do
    rel="${lp[$i]#"$base"}"
    [[ "$rel" =~ ^${WT_PREFIX}${_KEY}(-r[0-9]+)?$ ]] || continue
    hits+=("${lp[$i]}"); brs+=("${lb[$i]}")
  done
  if [ "${#hits[@]}" -eq 1 ]; then SEAT_WT="${hits[0]}"; SEAT_BR="${brs[0]}"
  elif [ "${#hits[@]}" -gt 1 ]; then SEAT_WT_ERR="좌석 워크트리 후보 ${#hits[@]}개(${hits[*]}) — 추측 금지, 어느 것인지 사람 판정"
  elif [ -n "$cwd" ]; then SEAT_WT_ERR="pane cwd($cwd)가 등록된 좌석 워크트리가 아니고 ${WT_PREFIX}<key>[-rN] 후보도 0개 — 추측 금지"; SEAT_WT_NOCAND=1; fi
}
_resolve_seat_wt
# ★--plan-only (r-disk-drop-worktree-scratch-census)★ 좌석 세션 0 · 등록 워크트리 · 가지=nano/<키> 를 확인하고 «계획 생성만». 아래 종료조건·원장·명부·kill 경로는 타지 않는다.
if [ "$PLAN_ONLY" = 1 ]; then
  [ "$tmux_ok" = 1 ] || { printf 'REJECT --plan-only: tmux 조회 실패 — 좌석 생존 불명(fail-closed)\n'; printf '%s\n' "${bad[@]}"; exit 1; }
  [ -z "$PANE" ] || { echo "REJECT --plan-only: 좌석 세션이 살아 있다($SEAT)"; exit 1; }
  _po="$(cd "$PO_WT" 2>/dev/null && pwd -P)"
  [ -n "$_po" ] && [[ "$_po" == "$ROOT/.worktrees/"?* ]] && git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $_po" || { echo "REJECT --plan-only: 이 리포 .worktrees/ 아래 등록 워크트리가 아니다: $PO_WT"; exit 1; }
  _pb="$(git -C "$_po" symbolic-ref --short -q HEAD)"
  _is_seat_branch "$_pb" || { echo "REJECT --plan-only: 가지(${_pb:-detached})가 좌석 키(nano/${_KEY}[-rN])와 맞지 않는다"; exit 1; }
  SEAT_WT="$_po"; SEAT_BR="$_pb"
  # 착지 판정(생성 시점) — 공용 ft-landed-check.sh · 기준 ref = FT_CENSUS_MAIN > origin/main > main. 같은 판정을 계획 본문이 실행 시점에 한 번 더 건다(④b).
  PO_MAINREF="${FT_CENSUS_MAIN:-}"; [ -n "$PO_MAINREF" ] || { git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && PO_MAINREF=origin/main || PO_MAINREF=main; }
  _lw="$(bash "$HERE/ft-landed-check.sh" "$ROOT" "$PO_MAINREF" "$_pb" "$(printf '%s' "$_pb" | sed 's|^nano/||; s|-r[0-9][0-9]*$||')" 2>&1)" || { echo "REJECT --plan-only: 착지하지 않은 가지($_pb · 판정 ${_lw##*$'\n'}) — 계획을 만들지 않는다"; exit 1; }
  _wt_clean_plan; [ -n "$PLAN" ] || { echo "REJECT --plan-only: 계획 생성 실패"; exit 1; }
  echo "PLANNED $PLAN"; exit 0
fi
# ★--shared-wt (오빠 10-07 · 원장 R8)★ ⓐ전용 워크트리가 «없다» ⓑpane cwd toplevel 이 등록된 워크트리이고 브랜치가 nano/* 가 «아니다». 하나라도 아니면 REJECT.
#   ⓐ 의 0-후보 «추측 금지» 에러는 이 모드의 정상 상태라 걸러내고, 후보가 있거나 2개 이상이면 «전용 경로로 닫아라» 로 바꾼다.
SH_TOP=""
if [ "$SHARED" = 1 ]; then
  if [ -n "$SEAT_WT" ] || { [ -n "$SEAT_WT_ERR" ] && [ "$SEAT_WT_NOCAND" = 0 ]; }; then
    bad+=("ⓐ좌석 전용 워크트리가 있다(${SEAT_WT:-$SEAT_WT_ERR}) — --shared-wt 없이 전용 경로로 닫아라"); SEAT_WT_ERR=""
  elif [ -z "$cwd" ]; then bad+=("ⓑpane cwd 를 알 수 없다 — 공유 워크트리 확인 불가(세션이 살아 있어야 한다)")
  else
    SEAT_WT_ERR=""
    SH_TOP="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    SH_BR="$(git -C "$ROOT" worktree list --porcelain 2>/dev/null | awk -v t="$SH_TOP" '/^worktree /{p=substr($0,10)} /^branch /{if(p==t){b=substr($0,8); sub("^refs/heads/","",b); print b}}')"
    if [ -z "$SH_TOP" ] || ! git -C "$ROOT" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $SH_TOP"; then bad+=("ⓑpane cwd($cwd)의 toplevel 이 등록된 워크트리가 아니다")
    elif [ -z "$SH_BR" ]; then bad+=("ⓑ공유 워크트리 $SH_TOP 의 브랜치를 알 수 없다(detached) — 추측 금지")
    else case "$SH_BR" in nano/*) bad+=("ⓑ공유 워크트리 $SH_TOP 가 나노 브랜치($SH_BR) — 공유 좌석이 아니라 전용 경로로 닫아라");; esac; fi
  fi
fi
# ★--wt/--branch (오빠 10-07 · 원장 R8 보강)★ 이름이 표준이 아닌 «전용» 워크트리 좌석. 표준 해석(_resolve_seat_wt)이 못 찾는 것을 «명시 인자»로 대신하되 전부 확인한다 — 하나라도 아니면 REJECT.
#   통과하면 SEAT_WT·SEAT_BR 만 이 값으로 정한다(⑥ 증거 줄·⑤ cherry·계획 생성이 그 «한 곳» 값을 쓴다). 자동 판별 0 · WIP 자동 커밋 0 · wt-clean 실행 0.
if [ "$NAMED" = 1 ]; then
  _std_wt="$SEAT_WT"; SEAT_WT=""; SEAT_BR=""; SEAT_WT_ERR=""   # 표준 해석 결과·«추측 금지» 에러는 이 모드에서 명시 인자가 대신한다(표준 후보가 따로 있으면 아래서 REJECT)
  _nw="$(cd "$NWT" 2>/dev/null && pwd -P)"
  _porc="$(git -C "$ROOT" worktree list --porcelain 2>/dev/null)"
  if [ -z "$_nw" ]; then bad+=("ⓐ--wt 경로가 없다: $NWT")
  elif [[ "$_nw" != "$ROOT/.worktrees/"?* ]] || ! printf '%s\n' "$_porc" | grep -qxF "worktree $_nw"; then
    bad+=("ⓐ--wt($_nw)가 이 리포($ROOT)에 등록된 .worktrees/ 아래 워크트리가 아니다")
  else
    _nb="$(printf '%s\n' "$_porc" | awk -v t="$_nw" '/^worktree /{p=substr($0,10)} /^branch /{if(p==t){b=substr($0,8); sub("^refs/heads/","",b); print b}}')"
    if [ "$_nb" != "$NBR" ]; then bad+=("ⓑ--wt($_nw)에 체크아웃된 브랜치(${_nb:-detached})가 --branch($NBR)와 다르다")
    else
      SEAT_WT="$_nw"; SEAT_BR="$NBR"
      case "$NBR" in main|master|"${FT_NANO_FEAT:-feat/v6-realtime-live}") bad+=("ⓑ--branch($NBR)는 정본 줄기(base)다 — 좌석 브랜치가 아니라 닫지 않는다");; esac
      if [ -n "$_std_wt" ] && [ "$_std_wt" != "$_nw" ]; then bad+=("ⓐ표준 전용 워크트리($_std_wt)가 따로 있다 — --wt($_nw)와 다르다, 추측 금지(인자 없이 닫거나 인자를 고쳐라)"); fi
    fi
  fi
  # ⓒ 세션이 살아 있으면 pane cwd 의 toplevel == --wt (죽었으면 «세션 없음 자체가 충족» — 아래 ABSENT 경로)
  if [ -n "$cwd" ] && [ -n "$_nw" ]; then
    _ctop="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    [ "$_ctop" = "$_nw" ] || bad+=("ⓒpane cwd($cwd)의 toplevel(${_ctop:-없음})이 --wt($_nw)와 다르다")
  fi
  # ⓓ 다른 tmux pane 중 cwd 가 --wt 안인 것 0 — 있으면 공유 워크트리다
  if [ "$tmux_ok" = 1 ] && [ -n "$_nw" ]; then
    _pp="$(tmux list-panes -a -F '#{session_name}|#{pane_current_path}' 2>&1)"; _prc=$?
    if [ "$_prc" -ne 0 ]; then
      case "$_prc:$_pp" in 1:*"no server running"*|1:*"error connecting to "*"(No such file or directory)"*) _pp="";; *) bad+=("ⓓtmux pane 조회 실패(rc=$_prc: ${_pp:0:60})"); _pp="";; esac
    fi
    _oth=""
    while IFS='|' read -r _ps _pc; do
      [ -n "$_ps" ] && [ "$_ps" != "$SEAT" ] || continue
      case "$_pc" in "$_nw"|"$_nw"/*) _oth="$_oth $_ps";; esac
    done <<< "$_pp"
    [ -z "$_oth" ] || bad+=("ⓓ다른 pane(${_oth# })의 cwd 가 --wt($_nw) 안이다 — 공유 워크트리다. --shared-wt 로 닫아라")
  fi
  # ⓔ 미커밋 0 — 이 모드는 WIP 자동 커밋을 하지 않는다(표준 브랜치가 아니라서). .serena/project.yml 만이면 git checkout 으로 되돌린 뒤 다시 닫는다.
  if [ -n "$_nw" ] && [ -n "$SEAT_WT" ]; then
    _dirty="$(git -C "$_nw" status --porcelain 2>&1)"; _drc=$?
    if [ "$_drc" -ne 0 ]; then bad+=("ⓔgit status 실패(rc=$_drc: ${_dirty:0:60})")
    elif [ -n "$_dirty" ]; then bad+=("ⓔ--wt 미커밋 변경 $(printf '%s\n' "$_dirty" | grep -c .)건 — 커밋하거나 되돌린 뒤 닫는다(WIP 자동 커밋 0 · .serena/project.yml 만이면 git checkout 으로 되돌려라)"); fi
  fi
fi
[ -z "$SEAT_WT_ERR" ] || bad+=("③$SEAT_WT_ERR")
# base 정합 (카드 §3): FT_NANO_FEAT «명시» → 그 값 · 아니면 좌석 워크트리 .worktree-info.json 의 base · 그것도 없으면 지금 기본값.
_FEAT="${FT_NANO_FEAT:-}"
[ -n "$_FEAT" ] || [ -z "$SEAT_WT" ] || _FEAT="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("base",""))' "$SEAT_WT/.worktree-info.json" 2>/dev/null)"
# R42: info.base 가 ref 가 아니고 commit(sha)이면 «랜딩 브랜치 정보 없음» — 기본 사슬로 랜딩 브랜치를 정한다(FT_NANO_FEAT 명시값은 그대로 우선). 조상 확인은 fetch 뒤.
_BASE_SHA=""
if [ -z "${FT_NANO_FEAT:-}" ] && [ -n "$_FEAT" ] \
   && ! git -C "$ROOT" rev-parse --verify -q "refs/heads/$_FEAT" >/dev/null \
   && ! git -C "$ROOT" rev-parse --verify -q "refs/remotes/$_FEAT" >/dev/null \
   && git -C "$ROOT" rev-parse --verify -q "$_FEAT^{commit}" >/dev/null; then
  _BASE_SHA="$_FEAT"; _FEAT=""
fi
_FEAT="${_FEAT:-feat/v6-realtime-live}"
# R22: base 가 원격 추적 ref(origin/<b>)면 닫기 직전 그 ref 하나만 fetch — 옛 ref 로 대조하지 않는다(#0 RULE). 로컬 브랜치 값이면 fetch 0.
_fetch_remote_feat() {
  local feat="$1" remote br
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$feat" >/dev/null && return 0
  git -C "$ROOT" rev-parse --verify -q "refs/remotes/$feat" >/dev/null || return 0
  remote="${feat%%/*}"; br="${feat#*/}"
  if git -C "$ROOT" fetch -q "$remote" "$br" >/dev/null 2>&1; then
    echo "INFO feat=$feat @ $(git -C "$ROOT" rev-parse --short "refs/remotes/$feat") (fetch 완료)"
  else
    bad+=("⑤ feat 원격 ref fetch 실패: $feat — 옛값으로 대조하지 않는다")
  fi
}
_fetch_remote_feat "$_FEAT"
if [ -n "$_BASE_SHA" ]; then
  if git -C "$ROOT" merge-base --is-ancestor "$_BASE_SHA" "$_FEAT" 2>/dev/null; then
    echo "INFO base sha ${_BASE_SHA:0:9} → 랜딩 브랜치 $_FEAT"
  else
    bad+=("base 가 sha ${_BASE_SHA:0:9} 이고 $_FEAT 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시")
  fi
fi
ABSENT=0
if [ "$tmux_ok" = 1 ]; then
  if [ -z "$cwd" ]; then
    if [ -n "$SEAT_WT" ]; then ABSENT=1; elif [ -z "$SEAT_WT_ERR" ]; then bad+=("③세션 없음: $SEAT"); fi
  else
    enc="$(printf '%s' "$cwd" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; dir="$HOME/.claude/projects/$enc"
    # r7(DA r6 MAJOR 1): 같은 좌석명 jsonl 이 여러 개(재기동)일 수 있다 — 「이름순 첫 파일」(head -1) 대신 «매칭 전부 중 mtime 최대».
    f="$(grep -lE "\"(agentName|customTitle)\":\"$(printf '%s' "$SEAT" | sed 's/[][\.*^$/]/\\&/g')\"" "$dir"/*.jsonl 2>/dev/null \
        | while IFS= read -r mf; do stat -f '%m %N' "$mf"; done | sort -rn | head -1 | cut -d' ' -f2-)"
    if [ -z "$f" ]; then
      # codex/cmd/opencode 는 claude jsonl 이 없다 — 파일 mtime 으로 대신(에이전트 무관 하한)
      last="$(find "$cwd" -type f -newer "$SEATS" -not -path '*/.git/*' -mmin -"$IDLE_MIN" 2>/dev/null | head -1)"
      [ -z "$last" ] || bad+=("③워크트리에 ${IDLE_MIN}분 내 편집: $last")
    else
      _lt="$("${FT_JSONL_LAST_TS:-$HERE/ft-jsonl-last-ts.py}" "$f" 2>&1)"; _lt_rc=$?  # R53: 파일 mtime 이 아니라 timestamp 있는 마지막 기록
      if [ "$_lt_rc" -ne 0 ]; then bad+=("③jsonl 기록 시각 없음: ${_lt%%$'\n'*}")
      else age=$(( ( $(date +%s) - ${_lt%% *} ) / 60 ))
        [ "$age" -ge "$IDLE_MIN" ] || bad+=("③jsonl 마지막 기록(${_lt#* }) ${age}분 전 < ${IDLE_MIN}분"); fi
    fi
  fi
fi
# ④ 카드가 checkpoint 를 요구하면(`ft-checkpoint.sh` 줄) 마지막 checkpoint 표 실재 + 경보 아님 (팩 SEATBELT.md §6-2 · 설정 없는 프로젝트는 경고만)
IDX="$(jq -r --arg s "$SEAT" '.[$s].index // empty' "$SEATS" 2>/dev/null)"; CARD=""
# R370: index 가 비면 _replaces 사슬을 거슬러 첫 index 로 후퇴(방문 집합으로 순환 차단 · 최대 10단 · 끝까지 없으면 아래 기존 REJECT 그대로)
_ic="$SEAT"; _iseen="|$SEAT|"; _in=0
while [ -z "$IDX" ] && [ "$_in" -lt 10 ]; do _ic="$(jq -r --arg s "$_ic" '.[$s]._replaces[0]? // empty' "$SEATS" 2>/dev/null)"; { [ -n "$_ic" ] && [[ "$_iseen" != *"|$_ic|"* ]]; } || break
  _iseen+="$_ic|"; _in=$((_in+1)); IDX="$(jq -r --arg s "$_ic" '.[$s].index // empty' "$SEATS" 2>/dev/null)"; [ -z "$IDX" ] || echo "INFO index 상속 ← $_ic"; done
_tw=""; [ -z "$IDX" ] || { declare -F ft_index_twin >/dev/null && _tw="$(ft_index_twin "$IDX")"; }   # R382: design/teams/<팀>/ ↔ design/<팀>/ 쌍둥이 후보(미전환·전환 워크트리가 섞인 기간)
# r444 ⑥(planner #111324 · L6b): 카드 = 팀 폴더 리졸버(ft_team_cands_ref · 명단 = ref · 폴더 = 각 루트)의 indices/<단계>/<파일> 먼저 — 단계 진행→완성→대기 순 · 루트 WT→ROOT→LEDGER_WT 순.
#   옛 글자 경로(design/<팀>/indices/대기)에 남은 사본이 실제 카드(design/teams/<팀>/indices/진행 · 미커밋)를 가리지 않게. 못 찾으면 아래 기존 후보 그대로.
if [ -n "$IDX" ] && [[ "$IDX" =~ design/(teams/)?([a-z0-9][a-z0-9_-]*)/indices/[^/]+/([^/]+)$ ]] && declare -F ft_team_cands_ref >/dev/null; then
  _ct="${BASH_REMATCH[2]}"; _cf="${BASH_REMATCH[3]}"
  for _d in 진행 완성 대기; do [ -z "$CARD" ] || break
    for _b in "$WT" "$ROOT" "$LEDGER_WT"; do [ -z "$CARD" ] || break
      while IFS= read -r _c; do [ -n "$_c" ] && [ -z "$CARD" ] && [ -f "$_c/indices/$_d/$_cf" ] && CARD="$_c/indices/$_d/$_cf"
      done < <(ft_team_cands_ref "$_b" "$_ct" "${FT_TEAMS_REF:-origin/main}" 2>/dev/null); done; done
  [ -z "$CARD" ] || echo "INFO 카드 위치(팀 폴더) ← $CARD"
fi
for c in "$WT/$IDX" "$ROOT/$IDX" "$LEDGER_WT/$IDX" ${_tw:+"$WT/$_tw" "$ROOT/$_tw" "$LEDGER_WT/$_tw"}; do [ -n "$IDX" ] && [ -z "$CARD" ] && [ -f "$c" ] && { CARD="$c"; break; }; done
# R400 r2: 카드 생애 이동(대기→진행→완성) 뒤 명부 index 는 옛 폴더 그대로 — 같은 indices 뿌리의 형제 폴더에서 같은 파일명이 «정확히 1개» 일 때만 그 카드(쌍둥이도 같은 규칙 · 0·2+ = 아래 REJECT 그대로 · 명부 쓰기 0)
_sibn=""
if [ -z "$CARD" ] && [[ "$IDX" =~ ^(.*/indices)/[^/]+/[^/]+$ ]]; then
  _sibn=0; _sib1=""
  for _d in 대기 진행 완성; do _hit=""
    for _rel in "$IDX" ${_tw:+"$_tw"}; do [[ "$_rel" =~ ^(.*/indices)/[^/]+/([^/]+)$ ]] || continue
      for _b in "$WT" "$ROOT" "$LEDGER_WT"; do [ -z "$_hit" ] && [ -f "$_b/${BASH_REMATCH[1]}/$_d/${BASH_REMATCH[2]}" ] && _hit="$_b/${BASH_REMATCH[1]}/$_d/${BASH_REMATCH[2]}"; done; done
    [ -z "$_hit" ] || { _sibn=$((_sibn+1)); _sib1="$_hit"; }; done
  [ "$_sibn" = 1 ] && { CARD="$_sib1"; echo "INFO 카드 위치 ← $CARD"; }
fi
# ④ 면제: 나노는 press 금지(single_set_testing) — 이 좌석 브랜치에 press 산출(poller_dom.jsonl)이 없으면 checkpoint 를 요구하지 않는다(10-03 문서·유닛 나노 4석 막힘 · master-claude#131).
_cp_pressed=1
if [ "$(jq -r --arg s "$SEAT" '.[$s].role // empty' "$SEATS" 2>/dev/null)" = nano ] && [ -n "$SEAT_WT" ]; then
  _cp_mb="$(git -C "$SEAT_WT" merge-base HEAD "$_FEAT" 2>/dev/null)"
  git -C "$SEAT_WT" diff --name-only "${_cp_mb:-HEAD}" HEAD 2>/dev/null | grep -q 'poller_dom\.jsonl' || { _cp_pressed=0; echo "WARN ④checkpoint 면제 — 나노 브랜치에 press 산출 0(poller_dom.jsonl 없음)"; }
fi
if [ -n "$CARD" ] && [ "$_cp_pressed" = 1 ] && grep -qF 'ft-checkpoint.sh' "$CARD"; then
  CPCFG="${FT_CHECKPOINT_JSON:-$ROOT/.fable-team/checkpoint.json}"; CPST="$ROOT/.fable-team/checkpoint/${SEAT//\//_}.last"
  if [ ! -f "$CPCFG" ]; then echo "WARN ④press/시험 카드인데 checkpoint 미설정($CPCFG) — 경고만(§6-2)"
  elif [ ! -f "$CPST" ]; then bad+=("④press/시험 카드인데 checkpoint 실행 기록 없음: ft-checkpoint.sh <증거폴더> --seat $SEAT")
  else
    cp_tab="$(jq -r '.table // empty' "$CPST")"; cp_al="$(jq -r '.alarm // empty' "$CPST")"; cp_ex="$(jq -r '.exit // empty' "$CPST")"
    [ -n "$cp_tab" ] && [ -f "$cp_tab" ] || bad+=("④checkpoint 표 없음: ${cp_tab:-<빈 경로>}")
    [ "$cp_al" = "no" ] || bad+=("④마지막 checkpoint alarm=$cp_al exit=$cp_ex — 경보면 4축 정리 → arch(+DA) 처방 → 수정 → 재실행 후 닫는다")
  fi
fi
# ⑥ 나노 생애 ③④ 증거 줄 (M7 · REVIEW arch141 §2-2) — role=nano 좌석만: 카드 «## 상태» 의 `세트: <HEAD> · 시험: … rc=0 · 이슈: …` 가 현재 나노 HEAD 와 맞아야 닫힌다.
#   impl·tester·checker 등 tier 좌석은 대상 아님(role 이 nano 가 아님). 루트 포함은 cherry-gate --mode land 가 랜딩 요청 시점에 맡는다(close 에는 걸지 않는다).
_role="$(jq -r --arg s "$SEAT" '.[$s].role // empty' "$SEATS" 2>/dev/null)"
# r450 --suspended: 실작업물 미커밋 → [wip] 커밋(계획 본문 [wip] 과 같은 규칙: .serena/project.yml 은 HEAD 로 되돌림 · ' D' 지우다 만 흔적은 담지 않음 · 브랜치 보존)
_susp_wip() {
  local st del=() p
  st="$(git -C "$SEAT_WT" status --porcelain)" || return 1
  [ "$(printf '%s\n' "$st" | grep -v '\.serena/project\.yml$' | grep -v '^ D ' | grep -c .)" -gt 0 ] || return 0
  if git -C "$SEAT_WT" ls-files --error-unmatch .serena/project.yml >/dev/null 2>&1; then git -C "$SEAT_WT" checkout HEAD -- .serena/project.yml || return 1; fi
  while IFS= read -r p; do [ -n "$p" ] && del+=("$p"); done < <(git -C "$SEAT_WT" diff --name-only --diff-filter=D)
  git -C "$SEAT_WT" add -A || return 1
  [ "${#del[@]}" -eq 0 ] || git -C "$SEAT_WT" reset -q -- "${del[@]}" || return 1
  git -C "$SEAT_WT" commit -q -m "[wip] nano close $SEAT" || return 1
  echo "INFO [wip] 커밋 $(git -C "$SEAT_WT" rev-parse --short HEAD) — 중단 전 미커밋 보존"
}
if [ "$SUPER" = 1 ]; then
  # R171 대체됨: rc=0 세트 증거 줄 대신 «카드 ## 상태 맨 끝 줄 = 대체됨: <카드> · 사유: <글>» + 대체 카드 실재(대기/진행/완료) + 자기 자신 아님. 역할 무관(카드를 못 찾으면 REJECT).
  if [ -z "$CARD" ]; then bad+=("⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} — 대체됨 줄을 대조할 카드가 없다${_sibn:+ · 형제 ${_sibn}개}")
  elif [ ! -x "$HERE/ft-nano-superseded-check.sh" ]; then bad+=("⑥대체됨 검사 스크립트 없음: $HERE/ft-nano-superseded-check.sh (런타임 bin 에 같이 복사)")
  else
    _sp_out="$("$HERE/ft-nano-superseded-check.sh" "$CARD" --superseded-by "$SUPERSEDED" --base "$WT" --base "$ROOT" --base "$LEDGER_WT" --team-root "$ROOT" 2>&1)"; _sp_rc=$?
    if [ "$_sp_rc" -eq 0 ]; then echo "$_sp_out"; else bad+=("⑥$(printf '%s' "$_sp_out" | sed -e 's/^REJECT //' -e '2,$s/^/    /')"); fi
  fi
elif [ "$SUSP" = 1 ]; then
  # r450 중단: rc=0 세트 증거 줄 대신 ft-nano-suspended-check.sh(HEAD·미커밋 0) — 카드 기록(--apply)은 모든 조건 통과 뒤(아래 bad 판정 직후). 역할 무관.
  if [ -z "$CARD" ]; then bad+=("⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} — 중단 줄을 남길 카드가 없다${_sibn:+ · 형제 ${_sibn}개}")
  elif [ -z "$SEAT_WT" ]; then bad+=("⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — 중단 세트(HEAD)를 정할 수 없다")
  elif [ ! -x "$HERE/ft-nano-suspended-check.sh" ]; then bad+=("⑥중단 검사 스크립트 없음: $HERE/ft-nano-suspended-check.sh (런타임 bin 에 같이 복사)")
  else
    # 실작업물 미커밋은 먼저 [wip] 커밋(앞 조건이 다 통과했을 때만 · --wt/--branch 모드는 WIP 자동 커밋 0 이라 ⓔ 가 이미 REJECT) — 실패 = REJECT · 닫힘 0
    if [ "${#bad[@]}" -eq 0 ] && [ "$NAMED" != 1 ]; then _susp_wip || bad+=("⑥[wip] 커밋 실패 — 미커밋을 보존하지 못해 닫지 않는다: $SEAT_WT"); fi
    _su_out="$("$HERE/ft-nano-suspended-check.sh" "$CARD" --wt "$SEAT_WT" --reason "$SUSP_REASON" 2>&1)"; _su_rc=$?
    if [ "$_su_rc" -eq 0 ]; then echo "$_su_out"; SUSP_SET="$(git -C "$SEAT_WT" rev-parse HEAD)"; else bad+=("⑥$(printf '%s' "$_su_out" | sed -e 's/^REJECT //' -e '2,$s/^/    /')"); fi
  fi
elif [ "$_role" = nano ] && [ -z "$CARD" ]; then
  # 카드를 못 찾으면 증거를 대조할 수 없다 — 건너뛰고 CLOSED 하면 무음 통과(#0 RULE · DA⑥ 관측 A3). grandfather 와 무관하게 REJECT.
  bad+=("⑥카드 못 찾음: seats.json index=${IDX:-<빈 값>} (후보 $WT/·$ROOT/·$LEDGER_WT/ 아래 어디에도 없음) — 증거 줄을 대조할 카드가 없다${_sibn:+ · 형제 ${_sibn}개}")
elif [ "$_role" = nano ] && [ -n "$CARD" ]; then
  if [ ! -x "$HERE/ft-nano-evidence-check.sh" ]; then bad+=("⑥증거 검사 스크립트 없음: $HERE/ft-nano-evidence-check.sh (런타임 bin 에 같이 복사)")
  elif [ "$SHARED" = 1 ]; then
    # ⓔ 공유 워크트리: 증거 sha 는 «공유 HEAD 의 조상»(HEAD 는 다른 세션이 계속 옮긴다). SH_TOP 이 없으면 ⓑ 에서 이미 REJECT 사유가 있다.
    if [ -n "$SH_TOP" ]; then
      _ev_out="$("$HERE/ft-nano-evidence-check.sh" "$CARD" --repo "$SH_TOP" --feat "$_FEAT" --ancestor-of HEAD 2>&1)"; _ev_rc=$?
      if [ "$_ev_rc" -eq 0 ]; then echo "$_ev_out"; else bad+=("ⓔ$(printf '%s' "$_ev_out" | sed -e 's/^REJECT //' -e '2,$s/^/    /')"); fi
    fi
  elif [ -z "$SEAT_WT" ]; then bad+=("⑥나노 워크트리 ${SEAT_WT_ERR:-없음: $ROOT/.worktrees/${WT_PREFIX}<key>[-rN]} — 증거 줄의 HEAD 를 대조할 수 없다")
  else
    # 언제부터 요구하나: 워크트리 .worktree-info.json created_at 날짜 >= FT_EVIDENCE_SINCE(기본 2026-10-03)인 나노만 REJECT — 그 전에 열린 진행 나노는 WARN 만(한 번에 막히지 않게).
    #   created_at 을 못 읽으면 요구한다(fail-closed · 값 추론 금지).
    _ev_created="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("created_at","")[:10])' "$SEAT_WT/.worktree-info.json" 2>/dev/null)"
    _ev_since="${FT_EVIDENCE_SINCE:-2026-10-03}"
    _ev_out="$("$HERE/ft-nano-evidence-check.sh" "$CARD" --repo "$SEAT_WT" --feat "$_FEAT" 2>&1)"; _ev_rc=$?
    if [ "$_ev_rc" -eq 0 ]; then echo "$_ev_out"
    elif [ -n "$_ev_created" ] && [[ "$_ev_created" < "$_ev_since" ]]; then echo "WARN ⑥증거 줄 미충족(grandfather — 워크트리 created_at $_ev_created < $_ev_since): $(printf '%s' "$_ev_out" | head -1)"
    else bad+=("⑥$(printf '%s' "$_ev_out" | sed -e 's/^REJECT //' -e '2,$s/^/    /')"); fi
  fi
fi
# ⑤ 산출물 회수 — 그 좌석 브랜치의 «+» 커밋(git cherry <feat> <branch>)이 0 (G4 · 골좌표 M7). 좌석이 닫혔다 ≠ 산출물이 들어왔다.
#   feat = FT_NANO_FEAT(기본 feat/v6-realtime-live) · 브랜치 = 워크트리 .worktree-info.json 의 branch, 워크트리가 없으면 nano/<key>. 못 찾으면 REJECT(침묵 통과 0).
# --shared-wt: cherry 게이트·wt-clean 계획은 건너뛴다(좌석 브랜치·전용 워크트리가 없다 — 공유 워크트리·브랜치는 손대지 않는다). 대신 ⓓ 가 산출물 커밋 여부를 본다.
_gate_br=""; [ -z "$SEAT_WT" ] || _gate_br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$SEAT_WT/.worktree-info.json" 2>/dev/null)"
[ -n "$_gate_br" ] || _gate_br="${SEAT_BR:-nano/$_KEY}"
[ "$NAMED" != 1 ] || _gate_br="$NBR"   # --wt/--branch: cherry 게이트는 «--branch 기준»(ⓖ) — info 파일 값이 아니다. 우회는 기존 --cherry-override 뿐.
if [ "$SHARED" = 1 ]; then
  # ⓓ --result 가 공유 워크트리에서 «추적 중» 이고 그 경로에 미커밋 변경 0 (워크트리 «전체» 미커밋은 다른 세션 것이라 보지 않는다)
  if [ -n "$SH_TOP" ] && [ -e "$RESULT" ]; then
    _rel="$(python3 -c 'import os,sys;print(os.path.relpath(os.path.realpath(sys.argv[1]),os.path.realpath(sys.argv[2])))' "$RESULT" "$SH_TOP")"
    case "$_rel" in ../*|..) bad+=("ⓓ--result($RESULT)가 공유 워크트리($SH_TOP) 밖이다");;
      *) git -C "$SH_TOP" ls-files --error-unmatch -- "$_rel" >/dev/null 2>&1 || bad+=("ⓓ--result($_rel)가 공유 워크트리에서 추적 중이 아니다(미추적)")
         [ -z "$(git -C "$SH_TOP" status --porcelain -- "$_rel" 2>/dev/null)" ] || bad+=("ⓓ--result($_rel)에 미커밋 변경이 있다 — 커밋한 뒤 닫는다");;
    esac
  fi
elif [ -x "$HERE/ft-nano-cherry-gate.sh" ]; then
  # --cherry-override 는 ⑤ 에만 전달한다(①~④·⑥ 영향 0). FT_SEAT 로 원장 행 seat 칸이 좌석명이 된다.
  _gate_args=(--repo "$ROOT" --mode close); [ "$HAVE_CHERRY_OVERRIDE" -eq 0 ] || _gate_args+=(--override "$CHERRY_OVERRIDE")
  [ "$SUPER" -eq 0 ] || _gate_args+=(--override "superseded-by $SUPERSEDED")   # R171: 대체 나노는 산출을 랜딩하지 않는다 — cherry REJECT 일 때만 원장 1행(사유 = 대체 카드)
  [ "$SUSP" -eq 0 ] || _gate_args+=(--override "suspended: $SUSP_REASON")   # r450: 중단 나노도 미완 산출을 랜딩하지 않는다(브랜치 보존) — 같은 자리 · 같은 원장
  _gate_out="$(FT_SEAT="$SEAT" "$HERE/ft-nano-cherry-gate.sh" "$_FEAT" "$_gate_br" "${_gate_args[@]}" 2>&1)"; _gate_rc=$?
  # 판정 1280: 팀 base 기준 REJECT «일 때만» origin/main 기준으로 같은 게이트를 한 번 더(--override 전달 0) — 뒤처진 팀 base 에서 main 에 squash 된 나노를 막지 않는다.
  #   fetch 실패면 옛 ref 로 대조하지 않는다(R22 · #0 RULE). 팀 base 가 이미 main·origin/main 이면 두 번째 실행 0.
  if [ "$_gate_rc" -ne 0 ] && [ "$_FEAT" != origin/main ] && [ "$_FEAT" != main ]; then
    if git -C "$ROOT" fetch -q origin main >/dev/null 2>&1; then
      _om_out="$(FT_SEAT="$SEAT" "$HERE/ft-nano-cherry-gate.sh" origin/main "$_gate_br" --repo "$ROOT" --mode close 2>&1)"; _om_rc=$?
      if [ "$_om_rc" -eq 0 ]; then _gate_rc=0; _gate_out="INFO cherry 게이트 — $_FEAT 기준 REJECT(${_gate_out%%$'\n'*}) · origin/main 기준 통과(${_om_out%%$'\n'*}) (사유 content_on_origin_main)"
      else _gate_out="$_gate_out"$'\n'"origin/main 기준: ${_om_out%%$'\n'*}"; fi
    else _gate_out="$_gate_out"$'\n'"origin/main fetch 실패 — 옛 ref 로 대조하지 않는다(R22)"; fi
  fi
  [ "$_gate_rc" -eq 0 ] || bad+=("⑤$(printf '%s' "$_gate_out" | sed '2,$s/^/    /')")
  # 나노 생애(오빠 ORDERS 103 · docs/rules/single_set_testing.md §3): 미랜딩이면 «루트부터» 판정과 다음 수(최신 루트 병합→시험→squash 랜딩)를 같이 낸다.
  if [ "$_gate_rc" -ne 0 ] && [ -x "$HERE/ft-nano-freshness.sh" ]; then
    _fresh_out="$(cd "$ROOT" && "$HERE/ft-nano-freshness.sh" "$_gate_br" --root "$_FEAT" 2>&1 | grep -E '^(base|branch|overlap|다음|VERDICT|  )')"
    bad+=("⑤-생애 $(printf '%s' "$_fresh_out" | sed '2,$s/^/    /')")
  fi
  [ "$_gate_rc" -ne 0 ] || echo "$_gate_out"
else
  bad+=("⑤cherry 게이트 스크립트 없음: $HERE/ft-nano-cherry-gate.sh (런타임 bin 에 같이 복사)")
fi
if [ "${#bad[@]}" -gt 0 ]; then echo "REJECT $SEAT"; printf '  - %s\n' "${bad[@]}"; exit 1; fi
# r450 중단: 조건이 전부 통과한 뒤에만 카드 «## 상태» 끝에 중단 줄(멱등) — 못 쓰면 명부·원장·세션 변경 전에 REJECT
if [ "$SUSP" = 1 ]; then
  _su_out="$("$HERE/ft-nano-suspended-check.sh" "$CARD" --wt "$SEAT_WT" --reason "$SUSP_REASON" --apply 2>&1)" || { echo "REJECT $SEAT"; printf '  - ⑥%s\n' "${_su_out#REJECT }"; exit 1; }
  echo "$_su_out"
fi
_su_tag=""; [ "$SUSP" -eq 0 ] || _su_tag=" suspended=1 reason=$SUSP_REASON set=$SUSP_SET"
# R387 판정 2282 §7-2 — 리서치 좌석(카드 `- 리서치: <좌석> base=<sha> 허용=<경로 패턴>`): 허용 밖 변경(base..HEAD + 작업트리)이 있으면 카드에 `- 리서치 위반:` 1줄 — 기록만(닫기·WIP 보존·회수는 막지 않는다 · 새 sandbox 0)
RS_LINE=""; RS_AGENT=""
if [ -n "${CARD:-}" ] && [ -f "$CARD" ]; then RS_LINE="$(grep -m1 -F -- "- 리서치: $SEAT base=" "$CARD" 2>/dev/null)"; RS_AGENT="$(jq -r --arg s "$SEAT" '.[$s].agent // empty' "$SEATS" 2>/dev/null)"; fi
if [ -n "$RS_LINE" ] && [ -n "${SEAT_WT:-}" ]; then
  python3 - "$CARD" "$SEAT" "$SEAT_WT" "$RS_LINE" <<'PY' || echo "WARN 리서치 위반 검사 실패 — 기록 못 함(닫기는 계속)"
import re, subprocess, sys
card, seat, wt, line = sys.argv[1:5]
m = re.search(r"base=([0-9a-f]{7,40}) 허용=(\S+)", line)
if not m:
    sys.exit(0)
base, allow = m.groups()
pat = re.compile("^" + re.escape(allow).replace(r"\*", "[^/]*") + "$")
files = set(subprocess.run(["git", "-C", wt, "diff", "--name-only", f"{base}..HEAD"], capture_output=True, text=True).stdout.split())
for ln in subprocess.run(["git", "-C", wt, "status", "--porcelain", "-uall"], capture_output=True, text=True).stdout.splitlines():
    files.add(ln[3:].split(" -> ")[-1].strip('"'))
files = {f for f in files if f and f != ".serena/project.yml" and not pat.match(f)}
if files:
    open(card, "a", encoding="utf-8").write(f"- 리서치 위반: {seat} {' '.join(sorted(files))[:300]}\n")
    print("WARN 리서치 위반 기록 — 허용(" + allow + ") 밖 변경 " + str(len(files)) + "건 (회수는 계속)")
PY
fi

# 재실행 감지 — 명부에 좌석이 이미 없으면(해제/kill 실패 뒤 같은 close 재호출) 원장 닫힘 행이 이미 있는 한 append 하지 않는다(멱등).
# jq 종료코드 1(has=false) 만 «없음» — 파일 오류(2·5)는 RERUN=0 으로 두어 기존 동작(append) 유지.
RERUN=0; jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null 2>&1; [ "$?" -ne 1 ] || RERUN=1
# 사건 원장 훅(PLAN-status-sheet §3-1): 명부 삭제 «전» prepared — 못 쓰면 닫기 거절 · 원장 append 직후 committed · 그 밖의 종료는 abort(trap)
_SK="$(bash "$HERE/ft-sheet-events.sh" key nano-close "$SEAT" "${RESULT:-none}")"
bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' nano-close "" "$SEAT" "$SEAT" "세트 ${RESULT:0:60}" nano-close)" >/dev/null || { echo "REJECT $SEAT"; echo "  - 사건 원장 prepared 실패 — 닫기 거절(PLAN §3-1)"; exit 1; }
trap 'bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null' EXIT
# 명부 삭제 + 원장 append (pm 만 원장을 쓴다는 §2-7 의 예외 = 이 스크립트의 append 1줄)
python3 - "$SEATS" "$SEAT" <<'PY'
import json, sys, collections
p, s = sys.argv[1:3]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d.pop(s, None)
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
_prc=$?; [ "$_prc" -eq 0 ] || { echo "REJECT $SEAT"; echo "  - 명부 쓰기 실패(rc=$_prc): $SEATS"; exit 1; }   # R400 r3 ③ — 사건 원장은 trap abort · CLOSED 0
_wt_clean_plan
[ "$SHARED" != 1 ] || WT_MARK="mode=shared-wt wt=$SH_TOP (정리 0 · 브랜치 0)"   # 계획·정리 0 — 원장 행에 모드를 남긴다
[ "$NAMED" != 1 ] || WT_MARK="mode=named-wt wt=$SEAT_WT branch=$NBR (계획만 · 정리 0 · 브랜치 0)"
# 원장 append 도 계획의 mark() 와 «같은» mkdir 락(<원장>.lock) 아래 — 락 밖 >> 와 mark 의 read→replace 가 겹치면 행이 소실된다(DA r3 실측 204/8000). 락 실패는 REJECT 가 아니라 append 강행(닫힘 행이 없는 것이 더 나쁘다) + 경고.
_lock="$LEDGER.lock"; _i=0
until mkdir "$_lock" 2>/dev/null; do _i=$((_i+1)); [ "$_i" -lt 100 ] || { echo "WARN 원장 락 10s 초과($_lock) — 락 없이 처리" >&2; _lock=""; break; }; sleep 0.1; done
_rowexists=0; grep -qF "\`$SEAT\` 닫힘(ft-nano-close)" "$LEDGER" 2>/dev/null && _rowexists=1
if [ "$ABSENT" = 1 ] && [ "$_rowexists" = 1 ]; then
  # r5(오빠 판정 #30467): 세션이 먼저 죽어 이미 닫힘 행이 있는 좌석(백필) — 새 행을 만들지 않고 마지막 행의 wt= 만 표식(mark() 와 같은 방식).
  # r6(DA r5 MINOR c): 이 경로는 닫힘 행이 이미 있어 「잃을 것」이 append 와 다르다 — 락 실패는 강행이 아니라 REJECT(재시도).
  [ -n "$_lock" ] || { echo "REJECT $SEAT"; echo "  - 원장 락 10s 초과(재시도) — 닫힘 행 이미 있음, 표식은 락 아래서만"; exit 1; }
  python3 - "$LEDGER" "$SEAT" "$WT_MARK" <<'PY'
import os, re, sys
p, seat, val = sys.argv[1:4]
s = open(p, encoding="utf-8").read(); lines = s.split("\n")
key = "`%s` 닫힘(ft-nano-close)" % seat
idx = [i for i, l in enumerate(lines) if key in l]
i = idx[-1]; lines[i] = re.sub(r"( · wt=.*)?$", " · wt=" + val, lines[i], count=1)
tmp = p + ".tmp.%d" % os.getpid()
with open(tmp, "w", encoding="utf-8") as f: f.write("\n".join(lines)); f.flush(); os.fsync(f.fileno())
os.replace(tmp, p)
PY
  # r6(DA r5 MINOR b): mark-only 도 종료코드를 본다(#0 RULE — 실패를 삼키지 않는다).
  _mrc=$?; [ -z "$_lock" ] || rmdir "$_lock"
  [ "$_mrc" -eq 0 ] || { echo "REJECT $SEAT"; echo "  - 원장 표식 실패(rc=$_mrc)"; exit 1; }
elif [ "$RERUN" = 1 ] && [ "$_rowexists" = 1 ]; then
  echo "재실행 — 명부에 없고 원장 닫힘 행이 이미 있다: append 생략, 남은 세션 정리만 이어간다"
  [ -z "$_lock" ] || rmdir "$_lock"
else
  printf -- '- **[%s KST, `date` 실측] `%s` 닫힘(ft-nano-close)**: ①결과 `%s` ②회수 seq %s ③%s. kill=%s%s · %s\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$SEAT" "$RESULT" "$RECV" "$([ "$ABSENT" = 1 ] && echo "세션 없음(백필)" || echo "유휴 jsonl 기록/mtime(codex) ≥${IDLE_MIN}분")" "$KILL" "$([ "$SUPER" = 1 ] && echo " · superseded-by=$SUPERSEDED")${_su_tag:+ ·$_su_tag}" "$([ "$SHARED" = 1 ] || [ "$NAMED" = 1 ] && echo "$WT_MARK" || echo "wt=$WT_MARK")" >> "$LEDGER"
  _arc=$?; [ -z "$_lock" ] || rmdir "$_lock"
  [ "$_arc" -eq 0 ] || { echo "FAIL $SEAT — 원장 append 실패(rc=$_arc · 명부는 삭제됨 · 같은 close 재실행이 RERUN 으로 이어간다): $LEDGER"; exit 1; }   # R400 r3 ④ — CLOSED 0
fi
if [ "$NAMED" = 1 ]; then
  case "$NBR" in nano/*) _why="이름이 표준 좌석 경로가 아니라(--wt/--branch 명시 모드)";; *) _why="브랜치가 nano/* 가 아니라";; esac
  _hb="$(dirname "$0")/ft-hil.sh"; _hm=""  # R83: 사람 ! 실행 안내 = 짧은 링크 · ft-hil.sh 없거나 실패면 지금 문구 + WARN
  [ -z "$PLAN" ] || { command -v "$_hb" >/dev/null 2>&1 && _hm="$("$_hb" --add "$PLAN" 2>/dev/null | tail -1)"; [ -n "$_hm" ] || echo "WARN ft-hil 실패 — 경로 안내로 후퇴" >&2; }
  [ -z "$PLAN" ] || echo "워크트리 정리 계획: $PLAN — $_why 자율 정리 범위 밖 — 사람 ! 실행: ${_hm:-! bash $PLAN} (자동 wt-clean 0 · 브랜치 삭제 0)"
elif [ -n "$PLAN" ]; then echo "워크트리 정리 계획: $PLAN (실행은 세션 kill 직후 — 미완이면 ft-wt-sweep.sh)"; fi
# r6(DA r5 MINOR e): 명부 pop 은 ABSENT 여부와 무관하게 위에서 항상 실행된다 — 「명부 확인」은 사실과 달랐다.
bash "$HERE/ft-sheet-events.sh" commit "$_SK" >/dev/null || true   # 원장 append 직후 = 닫힘 사건 성공(append 실패는 stderr SHEET-EVENT-PENDING)
_sp_tag=""; [ "$SUPER" -eq 0 ] || _sp_tag=" superseded-by=$SUPERSEDED"   # R171
_sp_tag+="$_su_tag"   # r450
if [ "$ABSENT" = 1 ]; then echo "CLOSED-ABSENT $SEAT$_sp_tag (명부 삭제 · 원장 표식) — 워크트리 정리 계획만"; exit 0; fi
echo "CLOSED $SEAT$_sp_tag (명부 삭제 · 원장 append) — 좌석은 정지 레디"
# 슬롯 채움(오빠 2026-10-02): 닫은 같은 턴에 빈 석·후보를 보인다 — 출력만, 실패해도 close 결과는 그대로.
bash "$(dirname "$0")/ft-nano-slots.sh" || echo "WARN ft-nano-slots 실패(rc=$?) — 빈 석을 손으로 세라"

# 닫힌 나노는 «항상» 태그 해제 + 세션 kill — 근거: 글로벌 ~/.claude/CLAUDE.md 「나노 세션 정리 표준승인 (2026-10-02 · 오빠 AskUserQuestion master-claude#120)」
# (nano-close 경로 하나 · 나노 계보 keep-last-2 면제 · ★브랜치 삭제 0★ · 역할 좌석은 keep-last-2 그대로).
# 둘 중 하나라도 실패하면 조용히 넘기지 않는다(#0 RULE) — 명부는 이미 지워졌으므로 같은 close 를 다시 부르면 남은 정리만 이어진다(RERUN).
tmux set-option -t "$PANE" -u @zc_v65_active || { echo "FAIL $SEAT — @zc_v65_active 해제 실패(세션 잔존 · 명부는 삭제됨)"; exit 1; }
tmux kill-session -t "$PANE" || { echo "FAIL $SEAT — kill-session 실패(세션 잔존 · 태그는 해제됨)"; exit 1; }
echo "KILLED $SEAT (@zc_v65_active 해제 · 세션 kill · 브랜치 보존)"
# R387 §7-3·§9-3 — 리서치 좌석이었다면 카드에 `- 리서치 닫힘:` 1줄 — opencode = ft-opencode-reap.sh 의 rc·left=<n> 각각 보존(left≠0 또는 rc≠0 = `CLOSE-FAIL reap left=<n> rc=<n>` 줄 + exit 1 · 미설치만 «도구 없음») · 그 밖 = kill rc=0. 부모 완성 게이트(ft-index-move)가 읽는다. 카드 쓰기 실패는 경고.
if [ -n "$RS_LINE" ]; then
  _rs_tail="kill rc=0"; _rs_fail=0
  if [ "$RS_AGENT" = opencode ]; then
    if [ -f "$HERE/ft-opencode-reap.sh" ]; then
      _rs_out="$(bash "$HERE/ft-opencode-reap.sh" "$SEAT" 2>&1)"; _rs_rc=$?; _rs_left="$(printf '%s' "$_rs_out" | grep -oE 'left=[0-9]+' | tail -1)"
      if [ "$_rs_rc" -eq 0 ] && [ "$_rs_left" = "left=0" ]; then _rs_tail="reap left=0 rc=0"
      else _rs_tail="CLOSE-FAIL reap ${_rs_left:-left=?} rc=$_rs_rc"; _rs_fail=1; fi
    else _rs_tail="reap 도구 없음(r286 미설치)"; fi
  fi
  printf -- '- 리서치 닫힘: %s %s %s\n' "$SEAT" "$(date '+%F %T')" "$_rs_tail" >> "$CARD" || echo "WARN 리서치 닫힘 줄 쓰기 실패($CARD)"
  [ "$_rs_fail" -eq 0 ] || { echo "$_rs_tail"; exit 1; }
fi
# 세션이 사라졌다 — 이제 계획을 실행한다(계보의 다른 세션·cwd 보유가 남아 있으면 계획이 skipped:좌석/cwd 로 대기시킨다)
[ "$NAMED" != 1 ] && [ -n "$PLAN" ] && [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] && _wt_clean_run   # --wt/--branch 는 자동 실행 0(계획만 · 사람 ! 실행)
exit 0
