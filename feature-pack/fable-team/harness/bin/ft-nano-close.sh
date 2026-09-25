#!/usr/bin/env bash
# ft-nano-close.sh <좌석> --result <산출경로> --recv <master seq> [--kill]
#   Seatbelt 0.3 · 나노 좌석을 «값으로» 닫는다 (SEATBELT-README §3 닫기 · NANO-LEDGER 종료조건 3).
#   exit 0 = 닫힘(명부 삭제·원장 append[·kill]) · 1 = REJECT(조건 미충족, 사유 stdout) · 2 = usage · 3 = kill 은 사람 승인 필요
# 종료조건 3 (전부 «값»): ①--result 경로 실재 ②--recv master 회수 seq 가 우편함/bodies 에 실재 ③jsonl 마지막 활동 ≥ IDLE_MIN 분 전
# kill 은 --kill 일 때만, 그것도 lineage keep-last-2 안이면 exit 3 (글로벌 HIL 하한). 기본은 «정지 레디 + 명부 삭제».
# 하네스 0.5 행 2 r2 (표준승인 2026-09-25 · ~/.claude/CLAUDE.md HIL 절 · DA-harness-0.5-row2-r1 조건 1~5):
#   close 는 워크트리 정리 계획을 «생성만» 한다(.fable-team/state/wt-clean/<seat>.sh · 원장 행 wt=planned). 조건 ③이 세션 실재를 요구하므로
#   close 시점엔 좌석이 살아 있다 — 실행은 «세션이 사라진 뒤»: --kill 이 KILLED 를 낸 직후, 또는 ft-wt-sweep.sh(master 가 주기 호출).
#   계획 스크립트가 가드 6(계보 세션 자기 포함 0 · 워크트리 cwd 보유 프로세스 0 · info branch nano/* · HEAD=branch+도달성 · 실작업물 0 · ignored 보관)과
#   좌석명 기준 원장 표식(wt=cleaned|skipped:<사유>)을 맡는다. 브랜치는 절대 지우지 않는다. FT_WT_AUTOCLEAN=0 = 실행 경로 전부 끔(계획만 남김).
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

# 계획 «생성» — 좌석의 워크트리 = $ROOT/.worktrees/v65-<seat 에서 접두·#N 제거>. 없으면 PLAN="" · WT_MARK=none.
_wt_clean_plan() {
  local key="${SEAT#"$NANO_PREFIX"}"; key="${key%#*}"
  local wt="$ROOT/.worktrees/v65-$key"
  PLAN=""; WT_MARK=none
  [ -d "$wt" ] || return 0
  mkdir -p "$WT_CLEAN_DIR"; PLAN="$WT_CLEAN_DIR/$SEAT.sh"; WT_MARK=planned
  [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] || WT_MARK="planned(autoclean=0)"
  {
    printf '#!/bin/bash\n# wt-clean 계획 — ft-nano-close.sh 가 %s 에 생성. 가드 6 → ignored 보관 → WIP 커밋 → baton wt-clean → 원장 표식. 브랜치는 지우지 않는다.\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '# baton 부작용(승인 범위에 명시): 아카이브 30일 초과분 prune · 분기 원장(.baton/branches.json) 의 같은 child_branch 행 status=abandoned.\n'
    printf 'SEAT=%q; KEY=%q; WT=%q; PREFIX=%q; LEDGER=%q; PLAN=%q\n' "$SEAT" "$key" "$wt" "$NANO_PREFIX" "$LEDGER" "$PLAN"
    cat <<'SH'
set -uo pipefail
BATON="${BATON_BIN:-$HOME/.baton/current/bin/baton}"
# 원장 표식 — 좌석명으로 행을 지정(마지막 줄 금지 · 그 좌석의 «마지막» 닫힘 행) · 기존 wt= 필드 교체
mark() { python3 - "$LEDGER" "$SEAT" "$1" <<'PY'
import re, sys
p, seat, val = sys.argv[1:4]
lines = open(p, encoding="utf-8").read().split("\n")
key = "`%s` 닫힘(ft-nano-close)" % seat
idx = [i for i, l in enumerate(lines) if key in l]
if idx:
    i = idx[-1]; lines[i] = re.sub(r"( · wt=.*)?$", " · wt=" + val, lines[i], count=1)
    open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
}
fail() { mark "skipped:$1"; echo "skipped:$1"; exit 1; }
[ -d "$WT" ] || { mark none; echo none; exit 0; }
# ① 계보(<PREFIX><KEY>#N) 세션 — «자기 포함» 0 (승인 조건 ① 원문 · DA r1 R1①)
live="$(tmux ls -F '#{session_name}' 2>/dev/null | grep -x "${PREFIX}${KEY}#[0-9]*" | tr '\n' ' ')"
[ -z "$live" ] || fail "좌석 ${live% }"
# ② 워크트리를 cwd 로 쥔 프로세스 0 (tmux 밖 node·mcp·zsh 포함 · DA r1 R4·R8)
holders="$(lsof -Fn -d cwd 2>/dev/null | grep -cE "^n${WT}(/|$)")"
[ "$holders" -eq 0 ] || fail "cwd 보유 프로세스 ${holders}개"
# ③ .worktree-info.json 의 branch 가 nano/*
br="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("branch",""))' "$WT/.worktree-info.json" 2>/dev/null)"
case "$br" in nano/*) ;; *) fail "branch=${br:-?} (nano/* 아님)";; esac
# ④ 도달성 — HEAD 브랜치 = info branch(detached 금지) 이고 HEAD 가 refs/heads/<br> 에 포함 (DA r1 R1②)
hb="$(git -C "$WT" symbolic-ref --short -q HEAD)"
[ "$hb" = "$br" ] || fail "HEAD=${hb:-detached} ≠ info $br"
git -C "$WT" merge-base --is-ancestor HEAD "refs/heads/$br" || fail "HEAD 가 $br 에 미포함"
# ⑤ 미커밋 실작업물(.serena/project.yml 제외) 0 — untracked 포함
dirty="$(git -C "$WT" status --porcelain)"
real="$(printf '%s\n' "$dirty" | grep -v '\.serena/project\.yml$' | grep -c .)"
[ "$real" -eq 0 ] || fail "실작업물 미커밋 ${real}파일"
# ⑥ ignored — 재생성 허용 목록(심링크·캐시)을 뺀 나머지는 <PLAN>.ignored.tar.gz 로 보관한 뒤 진행 (DA r1 R1③')
allow="${FT_WT_IGNORED_ALLOW:-.env .venv venv .worktree-info.json .serena node_modules .next __pycache__ .pytest_cache .ruff_cache .mypy_cache}"
keep=()
while IFS= read -r p; do
  [ -n "$p" ] || continue; top="${p%%/*}"
  case " $allow " in *" $top "*) ;; *) keep+=("$p");; esac
done < <(git -C "$WT" status --porcelain --ignored | sed -n 's/^!! //p')
if [ "${#keep[@]}" -gt 0 ]; then
  tar -C "$WT" -czf "$PLAN.ignored.tar.gz" -- "${keep[@]}" || fail "ignored 보관 실패(${#keep[@]}항목)"
fi
# 미커밋(serena yml)은 WIP 커밋 성공 뒤에만
if [ -n "$dirty" ]; then git -C "$WT" add -A && git -C "$WT" commit -q -m "[wip] nano close $SEAT" || fail "wip commit 실패"; fi
BATON_TMUX_DISABLE=true "$BATON" wt-clean "$WT" || fail "baton wt-clean 실패"
[ -d "$WT" ] && fail "baton 뒤에도 워크트리 남음"
res=cleaned; [ -f "$PLAN.ignored.tar.gz" ] && res="cleaned(ignored ${#keep[@]}항목 보관)"
mark "$res"; echo "$res"
SH
  } > "$PLAN"
  chmod 755 "$PLAN"
}
# 세션이 사라진 뒤(--kill KILLED 직후)의 실행 — 결과는 계획이 원장에 직접 표식. skipped 는 사람 판정 분기 → stdout [HIL](호출자가 mbox 로 올린다).
_wt_clean_run() {
  local res
  res="$(/bin/bash "$PLAN" 2>&1 | tee "$PLAN.log" | tail -1)"
  case "$res" in cleaned*|none) mv "$PLAN" "$PLAN.done";; skipped:좌석*|skipped:cwd*) ;; *) echo "[HIL] ${res#skipped:} · 스크립트 $PLAN";; esac
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
_wt_clean_plan
printf -- '- **[%s KST, `date` 실측] `%s` 닫힘(ft-nano-close)**: ①결과 `%s` ②회수 seq %s ③유휴 jsonl/mtime ≥%s분. kill=%s · wt=%s\n' \
  "$(date '+%Y-%m-%d %H:%M')" "$SEAT" "$RESULT" "$RECV" "$IDLE_MIN" "$KILL" "$WT_MARK" >> "$LEDGER"
[ -z "$PLAN" ] || echo "워크트리 정리 계획: $PLAN (실행은 세션 종료 뒤 — --kill 직후 또는 ft-wt-sweep.sh)"
echo "CLOSED $SEAT (명부 삭제 · 원장 append) — 좌석은 정지 레디"

[ "$KILL" = 1 ] || exit 0
# keep-last-2: 같은 베이스명(#N 떼고)의 최근 2개 안이면 사람 승인
base="${SEAT%#*}"; me="${SEAT##*#}"
top2="$(tmux ls -F '#{session_name}' | awk -v b="$base" 'index($0,b"#")==1{print substr($0,length(b)+2)}' | sort -rn | head -2 | tr '\n' ' ')"
case " $top2 " in *" $me "*) echo "HIL keep-last-2 안($base top2: $top2) — kill 은 사람 승인"; exit 3;; esac
tmux kill-session -t "$PANE" && echo "KILLED $SEAT" || exit 0
# 세션이 사라졌다 — 이제 계획을 실행한다(계보의 다른 세션·cwd 보유가 남아 있으면 계획이 skipped:좌석/cwd 로 대기시킨다)
[ -n "$PLAN" ] && [ "${FT_WT_AUTOCLEAN:-1}" != 0 ] && _wt_clean_run
exit 0
