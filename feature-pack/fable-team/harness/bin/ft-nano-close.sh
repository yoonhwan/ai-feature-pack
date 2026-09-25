#!/usr/bin/env bash
# ft-nano-close.sh <좌석> --result <산출경로> --recv <master seq> [--kill]
#   Seatbelt 0.3 · 나노 좌석을 «값으로» 닫는다 (SEATBELT-README §3 닫기 · NANO-LEDGER 종료조건 3).
#   exit 0 = 닫힘(명부 삭제·원장 append[·kill]) · 1 = REJECT(조건 미충족, 사유 stdout) · 2 = usage · 3 = kill 은 사람 승인 필요
# 종료조건 3 (전부 «값»): ①--result 경로 실재 ②--recv master 회수 seq 가 우편함/bodies 에 실재 ③jsonl 마지막 활동 ≥ IDLE_MIN 분 전
# kill 은 --kill 일 때만, 그것도 lineage keep-last-2 안이면 exit 3 (글로벌 HIL 하한). 기본은 «정지 레디 + 명부 삭제».
# 하네스 0.5 행 2 (표준승인 2026-09-25 · ~/.claude/CLAUDE.md HIL 절): 원장 append 뒤 워크트리 정리 스크립트를 «생성»(.fable-team/state/wt-clean/<seat>.sh)
#   하고 «기본으로 실행»한다(FT_WT_AUTOCLEAN 기본 1 · 끄기 = FT_WT_AUTOCLEAN=0 → 생성만 + 사람 `!` 경로). 브랜치는 절대 지우지 않는다.
set -uo pipefail
SEAT="${1:-}"; shift || { echo "usage: $0 <seat> --result <path> --recv <seq> [--kill]" >&2; exit 2; }
RESULT=""; RECV=""; KILL=0; IDLE_MIN="${FT_NANO_IDLE_MIN:-3}"
while [ $# -gt 0 ]; do case "$1" in --result) RESULT="$2"; shift 2;; --recv) RECV="$2"; shift 2;; --kill) KILL=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}"
case "$SEAT" in "$NANO_PREFIX"*) ;; *) echo "REJECT 나노(${NANO_PREFIX}*)만 닫는다: $SEAT"; exit 1;; esac   # role 무관(nano·impl·checker·tester 전부 temp- 접두)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"; COMM="${FT_INBOX_ROOT:-$ROOT/.fable-team/comm}"
LEDGER="$WT/${FT_NANO_LEDGER:-design/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md}"
WT_CLEAN_DIR="${FT_WT_CLEAN_DIR:-$ROOT/.fable-team/state/wt-clean}"

# 워크트리 정리 계획 «생성» — 좌석의 워크트리 = $ROOT/.worktrees/v65-<seat 에서 접두·#N 제거>. 없으면 PLAN="" .
# 실행은 사람(`! bash <경로>`) 또는 FT_WT_AUTOCLEAN=1. 브랜치는 절대 지우지 않는다(복원 = git worktree add <경로> <브랜치>).
_wt_clean_plan() {
  local key="${SEAT#"$NANO_PREFIX"}"; key="${key%#*}"
  local wt="$ROOT/.worktrees/v65-$key"
  PLAN=""
  [ -d "$wt" ] || { echo "워크트리 없음: $wt"; return 0; }
  mkdir -p "$WT_CLEAN_DIR"; PLAN="$WT_CLEAN_DIR/$SEAT.sh"
  {
    printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 %s 에 생성. 가드 3 → WIP 커밋 → baton wt-clean. 브랜치는 지우지 않는다.\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q\n' "$SEAT" "$key" "$wt" "$NANO_PREFIX"
    cat <<'SH'
set -uo pipefail
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"
fail() { echo "skipped:$1"; exit 1; }
[ -d "$WT" ] || fail "워크트리 없음"
# ① 좌석 — 같은 계보(<PREFIX><KEY>#N)의 «다른» 세션이 살아 있으면 중단. 닫힌 좌석 자신($SEAT)은 정지 레디라 제외(close 조건 ③이 세션 실재를 요구한다).
live="$(tmux ls -F '#{session_name}' 2>/dev/null | grep -x "${PREFIX}${KEY}#[0-9]*" | grep -vx "$SEAT" | tr '\n' ' ')"
[ -z "$live" ] || fail "좌석 ${live% }"
# ② .worktree-info.json 의 branch 가 nano/*
br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$WT/.worktree-info.json" 2>/dev/null)"
case "$br" in nano/*) ;; *) fail "branch=${br:-?} (nano/* 아님)";; esac
# ③ 미커밋 실작업물(.serena/project.yml 제외) 0 — untracked 포함
dirty="$(git -C "$WT" status --porcelain)"
real="$(printf '%s\n' "$dirty" | grep -v '\.serena/project\.yml$' | grep -c .)"
[ "$real" -eq 0 ] || fail "실작업물 미커밋 ${real}파일"
# 미커밋(serena yml)은 WIP 커밋 뒤에만 진행
if [ -n "$dirty" ]; then git -C "$WT" add -A && git -C "$WT" commit -q -m "[wip] nano close $SEAT" || fail "wip commit 실패"; fi
BATON_TMUX_DISABLE=true "$BATON" wt-clean "$WT" || fail "baton wt-clean 실패"
[ -d "$WT" ] && fail "baton 뒤에도 워크트리 남음"
echo cleaned
SH
  } > "$PLAN"
  chmod 755 "$PLAN"
}
# FT_WT_AUTOCLEAN=1: 계획을 그 자리에서 실행하고 결과 1줄을 원장 닫힘 행 끝에 append. 실패해도 CLOSED 는 유지(닫힘과 정리는 분리).
_wt_clean_run() {
  local res
  res="$(/bin/bash "$PLAN" 2>&1 | tee "$PLAN.log" | tail -1)"
  case "$res" in cleaned|skipped:*) ;; *) res="skipped:${res:-실행 실패}";; esac
  python3 - "$LEDGER" "$res" <<'PY'
import sys
p, r = sys.argv[1:3]
s = open(p, encoding="utf-8").read().rstrip("\n")
open(p, "w", encoding="utf-8").write(s + " · wt=" + r + "\n")
PY
  # skipped = 사람 판정 분기(좌석 생존·비nano 브랜치·실작업물 미커밋…) — 스크립트는 mbox 를 쏘지 않는다. 호출자가 이 줄을 [HIL] 로 CFO 에 올린다(오빠 규칙 2026-09-25).
  case "$res" in skipped:*) echo "[HIL] ${res#skipped:} · 스크립트 $PLAN";; esac
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
PANE="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' | awk -F'|' -v s="$SEAT" '$1==s{print $2; exit}')"
cwd="$([ -n "$PANE" ] && tmux display-message -p -t "$PANE" '#{pane_current_path}' 2>/dev/null)"
if [ -z "$cwd" ]; then bad+=("③세션 없음: $SEAT")
else
  enc="$(printf '%s' "$cwd" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; dir="$HOME/.claude/projects/$enc"
  f="$(grep -lE "\"(agentName|customTitle)\":\"$(printf '%s' "$SEAT" | sed 's/[][\.*^$/]/\\&/g')\"" "$dir"/*.jsonl 2>/dev/null | head -1)"
  if [ -z "$f" ]; then
    # codex/cmd/opencode 는 claude jsonl 이 없다 — 파일 mtime 으로 대신(에이전트 무관 하한)
    last="$(find "$cwd" -type f -newer "$SEATS" -not -path '*/.git/*' -mmin -"$IDLE_MIN" 2>/dev/null | head -1)"
    [ -z "$last" ] || bad+=("③워크트리에 ${IDLE_MIN}분 내 편집: $last")
  else
    age=$(( ( $(date +%s) - $(stat -f %m "$f") ) / 60 ))
    [ "$age" -ge "$IDLE_MIN" ] || bad+=("③jsonl 마지막 활동 ${age}분 전 < ${IDLE_MIN}분")
  fi
fi
if [ "${#bad[@]}" -gt 0 ]; then echo "REJECT $SEAT"; printf '  - %s\n' "${bad[@]}"; exit 1; fi

# 명부 삭제 + 원장 append (pm 만 원장을 쓴다는 §2-7 의 예외 = 이 스크립트의 append 1줄)
python3 - "$SEATS" "$SEAT" <<'PY'
import json, sys, collections
p, s = sys.argv[1:3]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d.pop(s, None)
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
printf -- '- **[%s KST, `date` 실측] `%s` 닫힘(ft-nano-close)**: ①결과 `%s` ②회수 seq %s ③유휴 jsonl/mtime ≥%s분. kill=%s\n' \
  "$(date '+%Y-%m-%d %H:%M')" "$SEAT" "$RESULT" "$RECV" "$IDLE_MIN" "$KILL" >> "$LEDGER"
_wt_clean_plan
if [ -n "$PLAN" ]; then
  if [ "${FT_WT_AUTOCLEAN:-1}" != 0 ]; then _wt_clean_run; else echo "워크트리 정리: ! bash $PLAN"; fi
fi
echo "CLOSED $SEAT (명부 삭제 · 원장 append) — 좌석은 정지 레디"

[ "$KILL" = 1 ] || exit 0
# keep-last-2: 같은 베이스명(#N 떼고)의 최근 2개 안이면 사람 승인
base="${SEAT%#*}"; me="${SEAT##*#}"
top2="$(tmux ls -F '#{session_name}' | awk -v b="$base" 'index($0,b"#")==1{print substr($0,length(b)+2)}' | sort -rn | head -2 | tr '\n' ' ')"
case " $top2 " in *" $me "*) echo "HIL keep-last-2 안($base top2: $top2) — kill 은 사람 승인"; exit 3;; esac
tmux kill-session -t "$PANE" && echo "KILLED $SEAT"
