#!/usr/bin/env bash
# test_team_literal_paths.sh — R382b 팀 이름을 «글자 그대로» 박은 경로 17곳이 ft_team_root / ft_team_lib.team_in 경유로 풀리는지 격리 시험
#   ⓐ 픽스처 리포(TEAMS.md 폴더 칸 꼴1 `design/<팀>/` · 꼴2 `design/teams/<팀>/` 두 벌)에서 각 도구가 «칸이 가리키는» 원장·카드를 읽는다 — 두 꼴의 정규화 출력이 같다
#   ⓑ 린트 ft-team-path-lint.sh 가 «리터럴 팀 이름 경로» 도 0 으로 요구(셸 글자 · 파이썬 쪼갠 꼴 · 주석 제외 · 변이 1줄 → ERR)
#   ⓒ 셸 lib 와 파이썬 lib 의 출력 동치(13팀 × 3꼴 · --alt · 오류) · 키트 사본 cmp0 · FT_TLP_RUN_EXISTING=1 이면 기존 시험(골 표·이동 왕복) rc0
# 임시 폴더·가짜 도구만 쓴다 — 실제 리포·seats·tmux 세션·mbox 는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/fable-team-bin"; KIT="$HERE/../../scripts/harness-install/fable-team/bin"; FIX="$HERE/../fixtures/goal_table"
_T0="$(mktemp -d)"; T="$(cd "$_T0" && pwd -P)"; trap 'rm -rf "$_T0"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
norm() { sed "s|$1|<R>|g; s|design/teams/|design/|g"; }   # 두 꼴 출력을 같은 글자로 — 팀 폴더 꼴만 다르다

echo "== 0 문법 · 키트 사본 cmp0 · 린트(실 bin)"
TOOLS_SH=(ft-harness-info ft-hil-ask ft-hil-answer ft-goal-check ft-goal-tick ft-role-spawn ft-news-tick ft-news-tick-cfo ft-branch-candidates ft-regress-reopen ft-press-baseline-check ft-team-path-lint)
TOOLS_PY=(ft_team_lib ft_board_decide ft_decision_count ft_news_publish ft_weekly_review ft_goal_table ft_goal_ledger)
for f in "${TOOLS_SH[@]}"; do bash -n "$SRC/$f.sh" && ok "bash -n $f" || bad "bash -n $f"; cmp -s "$SRC/$f.sh" "$KIT/$f.sh" && ok "키트 사본 cmp0 $f.sh" || bad "키트 사본 cmp $f.sh"; done
for f in "${TOOLS_PY[@]}"; do python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/$f.py" && ok "ast $f" || bad "ast $f"; cmp -s "$SRC/$f.py" "$KIT/$f.py" && ok "키트 사본 cmp0 $f.py" || bad "키트 사본 cmp $f.py"; done
out="$(bash "$SRC/ft-team-path-lint.sh" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "$out" "OK 하드코딩 0" "ⓑ 실 bin 린트 rc0" || bad "ⓑ 실 bin 린트 rc=$rc $out"

# ── 픽스처 리포 ───────────────────────────────────────────────────────────────
TEAMS13=(harness planner cfo ops graphics issues feature kk v65 loom lecture room concierge)
mkrepo() {  # <경로> <꼴 1|2>
  local R="$1" form="$2" t p H P V C I; mkdir -p "$R/design" "$R/.fable-team/state"
  git -C "$R" init -q -b main
  { printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'
    for t in "${TEAMS13[@]}"; do case "$form" in 1) p="design/$t/";; 2) p="design/teams/$t/";; esac; printf '| %s | `%s` | byz-%s-master-claude | 현역 |\n' "$t" "$p" "$t"; done; } > "$R/design/TEAMS.md"
  case "$form" in 1) base="$R/design";; 2) base="$R/design/teams";; esac
  H="$base/harness"; P="$base/planner"; V="$base/v65"; C="$base/cfo"; I="$base/issues"
  mkdir -p "$H/indices/진행" "$H/issue-improvement" "$P" "$V/20260909" "$V/20260910" "$V/20260911" "$V/indices/inbox/da" "$V/baselines" "$C" "$I"
  printf '# g\n' > "$H/GOAL-harness.md"; printf '# o\n' > "$H/OPS-VERDICTS-20261006.md"; printf '# m\n' > "$H/MACHINES.md"; printf '# s\n' > "$H/issue-improvement/SPEC-session-naming-20261005.md"
  printf '# 요청 원장\n| 번호 | 접수 | 누가 | 요청 | 상태 | 처리 | 닫는 증거 |\n|---|---|---|---|---|---|---|\n| R1 | 10-01 | x | 첫 요청 | 열림 | 대기 |  |\n' > "$H/REQUEST-LEDGER.md"
  printf '| 카드 | 결과 sha | Issue |\n|---|---|---|\n| card-a | %s | #7 |\n' "ffffffffffffffffffffffffffffffffffffffff" > "$H/LANDING-LEDGER.md"   # sha 는 아래에서 실 커밋으로 바꾼다
  printf '# card\n' > "$H/indices/진행/card-a.md"; printf '# g\n' > "$I/GOAL-issues.md"; printf '# guide\n' > "$P/GUIDE-planner.md"
  printf '# L\n' > "$V/GOAL-LEDGER-v65.md"; printf 'a\n' > "$V/20260909/GOAL-archastra-lst-on-off-completion.md"; printf 'b\n' > "$V/20260910/LIST-v65-lst-completion-MERGED.md"; printf 'c\n' > "$V/20260911/PLAN-v65-sm65-experiment-completion-handoff.md"
  printf '# 트리\n' > "$V/NEWS-TREE.md"; printf 'x\n' > "$V/SEATBELT-README.md"; printf '# 트리\n' > "$C/NEWS-TREE.md"; printf 'v\n' > "$C/VERDICT-DATA-SOVEREIGNTY-20260923.md"
  cp "$FIX/AUTONOMY-GOAL-A6-20261018.md" "$P/AUTONOMY-GOAL-A6-20261018.md"
  { printf '# 원장\n## 메인 골 6줄 (마지막 갱신: 2026-10-18 10:00)\n| 골 | 지금 상태 |\n|---|---|\n'; for n in 1 2 3 4 5 6; do printf '| 골%s | 상태%s진행 |\n' "$n" "$n"; done; } > "$P/PLAN-oppa-ledger.md"
  printf '| 번호 | 일시 | 좌석 | seq | 질문 | 선택지 | 추천 | 상태 |\n|---|---|---|---|---|---|---|---|\n| 1 | t | s | 1 | q | a | a | open |\n' > "$H/HIL-LEDGER.md"
  printf '| 항목 | 상태 |\n|---|---|\n| m1 | 대기 |\n' > "$H/MERGE-QUEUE.md"
  printf '| 토글 | 기본값 |\n|---|---|\n| X_FLAG | off |\n' > "$V/baselines/FLAGS.md"
  printf '# q\n| 열 | 값 |\n|---|---|\n| 7 |  |\n' > "$P/DECISIONS-oppa-queue-20261013.md"
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init
  GITC "$R" update-ref refs/remotes/origin/main HEAD
  GITC "$R" remote add origin https://github.com/x/y.git
  local sha; sha="$(GITC "$R" rev-parse HEAD)"; sed -i.bak "s/ffffffffffffffffffffffffffffffffffffffff/$sha/" "$H/LANDING-LEDGER.md"; rm -f "$H/LANDING-LEDGER.md.bak"   # 미커밋 변경 — 원장은 파일로 읽는다
}
R1="$T/r1"; R2="$T/r2"; mkrepo "$R1" 1; mkrepo "$R2" 2

declare -A OUTS
for F in 1 2; do
  R="$T/r$F"; echo "== ⓐ 꼴$F 픽스처에서 각 도구가 칸이 가리키는 경로를 읽는다"
  case "$F" in 1) HT="$R/design/harness"; PT="$R/design/planner"; VT="$R/design/v65"; IT="$R/design/issues";; 2) HT="$R/design/teams/harness"; PT="$R/design/teams/planner"; VT="$R/design/teams/v65"; IT="$R/design/teams/issues";; esac
  mkdir -p "$R/.fable-team/bin"; printf '%s\n' "$R/.fable-team/bin" > "$R/.fable-team/LIVE_BIN"; printf '%s\n' "$R" > "$R/.fable-team/LIVE_ROOT"

  # 골 표 6칸 (ft_goal_table · ft_goal_ledger)
  o="$(env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" python3 "$SRC/ft_goal_table.py" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "상태6진행" "ⓐ$F 골 표: planner 원장 «지금 상태» 6칸을 칸 경로에서 읽었다" || bad "ⓐ$F 골 표 rc=$rc ← ${o:0:300}"
  OUTS[goal$F]="$(printf '%s' "$o" | norm "$R")"

  # HIL 원장 ask → answer
  o="$(env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" FT_ME=seat-x FT_HIL_ROUTE=route FT_SEND_DRY=1 bash "$SRC/ft-hil-ask.sh" "질문?" --options "예|아니오" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q '| seat-x | dry | 질문? |' "$HT/HIL-LEDGER.md" && ok "ⓐ$F ft-hil-ask: harness 팀 폴더 원장에 행 추가" || bad "ⓐ$F hil-ask rc=$rc ← ${o:0:300}"
  o="$(env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" FT_SEND_DRY=1 bash "$SRC/ft-hil-answer.sh" 2 예 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q '| applied:예 |' "$HT/HIL-LEDGER.md" && ok "ⓐ$F ft-hil-answer: 같은 원장 행 applied" || bad "ⓐ$F hil-answer rc=$rc ← ${o:0:300}"
  [ ! -e "$R/design/harness/HIL-LEDGER.md" ] || [ "$F" = 1 ] && ok "ⓐ$F 옛 글자 경로에 원장을 새로 만들지 않았다" || bad "ⓐ$F 옛 경로에 원장 생김"

  # harness-info: origin/main 의 칸으로 정본 실재 · 요청 원장
  o="$(cd "$R" && FT_SKILL_DIR="$T/none" bash "$SRC/ft-harness-info.sh" rules 2>&1)"
  [ "$(printf '%s\n' "$o" | grep -c '^OK    origin/main:')" = 8 ] && hasnt "$o" "없음  origin/main" "ⓐ$F harness-info rules: 정본 8개 전부 OK" || bad "ⓐ$F harness-info rules ← $o"
  OUTS[info$F]="$(printf '%s' "$o" | grep 'origin/main' | norm "$R")"
  o="$(cd "$R" && bash "$SRC/ft-harness-info.sh" requests 2>&1)"; has "$o" "| R1 |" "ⓐ$F harness-info requests: 요청 원장 행"

  # ft-goal-check: v65 정본 4개 실재
  o="$(cd "$R" && bash "$SRC/ft-goal-check.sh" seat-x 2>&1)"; hasnt "$o" "정본 부재" "ⓐ$F ft-goal-check: v65 정본 4개를 칸 경로에서 찾았다"; hasnt "$o" "REJECT" "ⓐ$F ft-goal-check: REJECT 0 ← ${o:0:200}"

  # ft-goal-tick: 프롬프트 파일(v65 칸) 게이트 통과 → target absent
  mkdir -p "$R/.fable-team/comm" "$T/tk$F"; printf '#!/bin/bash\nexit 0\n' > "$R/.fable-team/comm/mbox.sh"; printf '#!/bin/bash\nexit 0\n' > "$T/tk$F/check.sh"; chmod +x "$R/.fable-team/comm/mbox.sh" "$T/tk$F/check.sh"
  mkdir -p "$VT/20260912"; printf '```\n틱 <세션명>\n```\n' > "$VT/20260912/TICK-PROMPT-v65-unified.md"
  o="$(FT_GOAL_TICK_ROOT="$R" FT_GOAL_TICK_TARGET="r382b-없는-좌석#0" FT_GOAL_TICK_CHECK="$T/tk$F/check.sh" FT_GOAL_TICK_STREAK="$T/tk$F/streak" bash "$SRC/ft-goal-tick.sh" 2>&1)"
  has "$o" "target absent" "ⓐ$F ft-goal-tick: 프롬프트·mbox·check 게이트를 통과(칸 경로의 프롬프트)"
  rm "$VT/20260912/TICK-PROMPT-v65-unified.md"
  o="$(FT_GOAL_TICK_ROOT="$R" FT_GOAL_TICK_TARGET="r382b-없는-좌석#0" FT_GOAL_TICK_CHECK="$T/tk$F/check.sh" FT_GOAL_TICK_STREAK="$T/tk$F/streak" bash "$SRC/ft-goal-tick.sh" 2>&1)"
  has "$o" "missing mbox/check/prompt" "ⓐ$F ft-goal-tick 변이: 칸 경로의 프롬프트를 없애면 멈춘다"

  # ft-role-spawn --dry-run: 인박스·README 가 v65 칸 아래
  B="$T/rb$F"; mkdir -p "$B" "$T/fk$F"; for f in ft-role-spawn.sh ft-team-lib.sh ft_raised.py ft-resource-gate.sh ft_teamset.py ft_spawn_queue.py ft-resource-sample.sh; do cp -p "$SRC/$f" "$B/"; done
  for f in ft-index-lint.sh ft-proposal-gate.sh ft-index-move.sh ft-send-verified.sh ft-agent-ready.sh ft-sheet-events.sh; do printf '#!/bin/bash\nexit 0\n' > "$B/$f"; done
  printf '#!/bin/bash\n[ "$1" = key ] && { echo k; exit 0; }\nexit 0\n' > "$B/ft-sheet-events.sh"; chmod +x "$B"/*.sh
  printf '#!/bin/bash\nif [ "$1" = open ]; then n=""; while [ $# -gt 0 ]; do [ "$1" = --name ] && n="$2"; shift; done; echo "TMUXC-DRY $n"; fi\nexit 0\n' > "$T/fk$F/tmuxc"; printf '#!/bin/bash\nexit 1\n' > "$T/fk$F/tmux"; chmod +x "$T/fk$F/tmuxc" "$T/fk$F/tmux"
  printf '{"_master":"m#1","m#1":{"role":"master","agent":"claude","tick":null}}\n' > "$R/.fable-team/seats.json"
  o="$(cd "$R" && PATH="$T/fk$F:$PATH" FT_TEAMSET=0 bash "$B/ft-role-spawn.sh" da --dry-run 2>&1)"
  has "$o" "inbox=${VT#"$R"/}/indices/inbox/da" "ⓐ$F ft-role-spawn: 인박스 = v65 칸 아래(리포 상대) ← ${o:0:200}"

  # ft-branch-candidates: 산출 경로 = issues 칸
  o="$(cd "$R" && bash "$SRC/ft-branch-candidates.sh" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ -f "$IT/BRANCH-CANDIDATES.md" ] && ok "ⓐ$F ft-branch-candidates: issues 칸 아래에 산출" || bad "ⓐ$F branch-candidates rc=$rc ← ${o:0:300}"

  # ft-regress-reopen: LANDING-LEDGER = harness 칸(dry-run · gh 호출 0)
  sha="$(GITC "$R" rev-parse HEAD)"
  o="$(cd "$R" && bash "$SRC/ft-regress-reopen.sh" 7 "$sha" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "card-a" "ⓐ$F ft-regress-reopen: harness 칸의 LANDING-LEDGER 행(card-a)을 찾았다" || bad "ⓐ$F regress-reopen rc=$rc ← ${o:0:300}"

  # ft-press-baseline-check: FLAGS = v65 칸 아래
  printf '기준선: self\n실험: 없음\n' > "$T/card$F.md"; rm -f "$VT/baselines/FLAGS.md"
  o="$(cd "$R" && bash "$SRC/ft-press-baseline-check.sh" --card "$T/card$F.md" --repo "$R" 2>&1)"
  has "$o" "${VT#"$R"/}/baselines/FLAGS.md" "ⓐ$F ft-press-baseline-check: FLAGS.md 위치 = v65 칸(없을 때 그 경로를 말한다)"
  printf '| 토글 | 기본값 |\n|---|---|\n| X_FLAG | off |\n' > "$VT/baselines/FLAGS.md"

  # 파이썬: 결정 대기열(board_decide) · 결정 건수(decision_count) · 뉴스 폴더(news_publish) · 주간 점검(weekly_review)
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" python3 -I -c '
import sys; sys.path.insert(0, ".")
from datetime import datetime
import ft_board_decide as d
print("\n".join(d.decide_lines({"issues": []}, datetime(2026, 10, 18, 10, 0))))' 2>&1)"
  has "$o" "HIL-LEDGER open 1" "ⓐ$F ft_board_decide: harness 칸의 HIL-LEDGER 를 읽는다(open 1)"; has "$o" "MERGE-QUEUE 대기 1" "ⓐ$F ft_board_decide: harness 칸의 MERGE-QUEUE 를 읽는다(대기 1)"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" python3 -I -c '
import sys; sys.path.insert(0, ".")
import ft_decision_count as c
rows, head = c.table("NOENV", "PLAN-oppa-ledger.md", "none")
print(len(rows), head)' 2>&1)"
  has "$o" "6 ['골'" "ⓐ$F ft_decision_count.table: planner 칸의 원장(데이터 행 6 · 머리 골)"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_ROOT="$R" python3 -I -c '
import sys; sys.path.insert(0, ".")
import ft_news_publish as p
print(p._paths()[0])' 2>&1)"
  has "$o" "${PT#"$R"/}/news" "ⓐ$F ft_news_publish: 뉴스 폴더 = planner 칸/news"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
from datetime import datetime
import ft_weekly_review as w
r = Path(sys.argv[1])
print(w.p1_queue(r)); print(w.h2_requests(r)); print(w.h1_cards(r, datetime(2026, 10, 18))[0][0])' "$R" 2>&1)"
  has "$o" "열린 행 1건: 7" "ⓐ$F ft_weekly_review.p1_queue: planner 칸의 결정 대기열"; has "$o" "H2 R1" "ⓐ$F ft_weekly_review.h2_requests: harness 칸의 요청 원장"; has "$o" "H1 card-a" "ⓐ$F ft_weekly_review.h1_cards: harness 칸의 진행 카드"

  # 뉴스 틱(+cfo): 라이브 고정 루트를 읽는 도구라 격리 실행 대신 «글자 경로 0 + lib 경유» 를 대조한다
  for f in ft-news-tick ft-news-tick-cfo; do
    n="$(grep -vE '^[[:space:]]*#' "$SRC/$f.sh" | grep -cE 'design/(teams/)?(planner|harness|cfo|ops|graphics|issues|feature|kk|v65|loom|lecture|room|concierge)/')"; [ "$n" = 0 ] && ok "ⓐ$F $f: 리터럴 팀 경로 0" || bad "ⓐ$F $f 리터럴 $n곳"
  done
  has "$(grep -c 'ft_team_in' "$SRC/ft-news-tick.sh")" "1" "ⓐ$F ft-news-tick: v65 트리 = ft_team_in"; has "$(grep -c 'ft_team_in "\$CFO" cfo' "$SRC/ft-news-tick-cfo.sh")" "1" "ⓐ$F ft-news-tick-cfo: cfo 폴더 = ft_team_in"
done
for k in goal info; do [ "${OUTS[${k}1]}" = "${OUTS[${k}2]}" ] && [ -n "${OUTS[${k}1]}" ] && ok "ⓐ 꼴1 == 꼴2 정규화 출력 동일($k)" || bad "ⓐ 꼴1 ≠ 꼴2 ($k)"; done

echo "== ⓑ 린트 — 리터럴 팀 이름 경로 0 (변이 대조)"
LB="$T/lintbin"; mkdir -p "$LB"; cp "$SRC/ft-team-lib.sh" "$SRC/ft-team-path-lint.sh" "$LB/"
run_lint() { FT_REPO_ROOT="$R1" FT_TEAM_LITERAL_PENDING="${PEND:-}" bash "$LB/ft-team-path-lint.sh" 2>&1; }
printf 'x=ok\n' > "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 0 ] && ok "ⓑ 깨끗한 bin → rc0" || bad "ⓑ 깨끗한 bin rc=$rc ← $o"
printf 'L="$ROOT/design/planner/PLAN-oppa-ledger.md"\n' > "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && has "$o" "ERR 리터럴 팀 이름 경로" "ⓑ 변이: 셸 리터럴 한 줄 → ERR rc1" || bad "ⓑ 셸 변이 rc=$rc ← $o"
printf 'L="$ROOT/design/teams/harness/X.md"\n' > "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이: 꼴2(design/teams/<팀>/) 리터럴도 ERR" || bad "ⓑ 꼴2 변이 rc=$rc ← $o"
printf '# design/planner/ 는 주석\n' > "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 0 ] && ok "ⓑ 주석 줄의 글자는 제외" || bad "ⓑ 주석 rc=$rc ← $o"
rm "$LB/a.sh"; printf 'p = root / "design" / "planner" / "news"\n' > "$LB/b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이: 파이썬 쪼갠 꼴 → ERR rc1" || bad "ⓑ 파이썬 변이 rc=$rc ← $o"
printf 'p = root / "design" / "teams" / "cfo"\n' > "$LB/b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이: 파이썬 쪼갠 꼴2 → ERR rc1" || bad "ⓑ 파이썬 꼴2 변이 rc=$rc ← $o"
# DA⑥ r1 Q3 — 거짓 음성 3종(slash 없는 joined · 작은따옴표 분할 · 줄 끝 셸 변수 기본값) + 접두 오탐 0
printf 'p = root / "design/planner"\n' > "$LB/b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이(Q3): slash 없는 joined \"design/planner\" → ERR rc1" || bad "ⓑ joined 변이 rc=$rc ← $o"
printf "p = root / 'design' / 'planner'\n" > "$LB/b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이(Q3): 작은따옴표 분할 → ERR rc1" || bad "ⓑ 작은따옴표 변이 rc=$rc ← $o"
printf "p = root / 'design/teams/cfo'\n" > "$LB/b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이(Q3): 작은따옴표 joined 꼴2 → ERR rc1" || bad "ⓑ 작은따옴표 꼴2 변이 rc=$rc ← $o"
printf 'P="${X:-$ROOT/design/planner}"\n' > "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 1 ] && ok "ⓑ 변이(Q3): 셸 기본값 design/planner} → ERR rc1" || bad "ⓑ 셸 기본값 변이 rc=$rc ← $o"
printf 'p = root / "design/plannerX"\nq = "design/harness-notes"\n' > "$LB/b.py"; rm "$LB/a.sh"; o="$(run_lint)"; rc=$?; [ "$rc" = 0 ] && ok "ⓑ 접두 오탐 0 (design/plannerX · design/harness-notes)" || bad "ⓑ 접두 오탐 rc=$rc ← $o"
printf 'p = root / "design" / "planner" / "news"  # 주석 뒤\n' > "$LB/b.py"
PEND="b.py"; o="$(run_lint)"; rc=$?; [ "$rc" = 0 ] && has "$o" "INFO 리터럴 대기" "ⓑ 범위 밖 대기 목록 파일은 INFO 로 이름을 찍고 통과" || bad "ⓑ 대기 목록 rc=$rc ← $o"
printf 'x=1\n' > "$LB/b.py"; o="$(run_lint)"; has "$o" "대기 목록에서 제거할 파일" "ⓑ 깨끗해진 대기 파일은 «목록에서 제거» INFO"; unset PEND

echo "== ⓒ 셸 lib ↔ 파이썬 lib 출력 동치 (13팀 × 3꼴 · --alt · 오류)"
HR="$T/hroot"; mkdir -p "$HR/design"
for F in 1 2 3; do
  R="$T/eq$F"; mkdir -p "$R/design"; { printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n'; for t in "${TEAMS13[@]}"; do case "$F" in 1) p="design/$t/";; 2) p="design/teams/$t/";; 3) p="\$FT_HARNESS_ROOT/design/$t/";; esac; printf '| %s | `%s` | b | c |\n' "$t" "$p"; done; } > "$R/design/TEAMS.md"
  for alt in "" "--alt"; do
    sh_out="$(for t in "${TEAMS13[@]}"; do (export FT_REPO_ROOT="$R" FT_HARNESS_ROOT="$HR"; . "$SRC/ft-team-lib.sh"; ft_team_root "$t" $alt 2>&1 || echo "rc=$?"); done)"
    py_out="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_REPO_ROOT="$R" FT_HARNESS_ROOT="$HR" python3 -I -c '
import sys; sys.path.insert(0, ".")
import ft_team_lib as L
for t in sys.argv[2:]:
    try: print(L.team_root(t, alt=bool(sys.argv[1])))
    except L.TeamPathError: print("rc=1")' "$alt" "${TEAMS13[@]}" 2>&1)"
    # 셸 오류는 stderr ERROR 줄 + rc=1 — 파이썬은 rc=1 만 — ERROR 줄을 떼고 비교한다
    sh_cmp="$(printf '%s\n' "$sh_out" | grep -v '^ERROR')"
    [ "$sh_cmp" = "$py_out" ] && ok "ⓒ 꼴$F ${alt:-기본} 13팀 출력 동일" || bad "ⓒ 꼴$F ${alt:-기본} 어긋남 — sh:${sh_cmp:0:160} py:${py_out:0:160}"
  done
done
sh_n="$( (export FT_REPO_ROOT="$T/eq1"; . "$SRC/ft-team-lib.sh"; ft_team_names | paste -sd, -) )"; py_n="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_REPO_ROOT="$T/eq1" python3 -I -c 'import sys;sys.path.insert(0,".");import ft_team_lib as L;print(",".join(L.team_names()))')"
[ "$sh_n" = "$py_n" ] && ok "ⓒ 팀 이름 목록(칸 첫 일치 순서) 동일" || bad "ⓒ 팀 이름 목록 어긋남 $sh_n | $py_n"
o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_REPO_ROOT="$T/nolist" python3 -I -c 'import sys;sys.path.insert(0,".");import ft_team_lib as L
try: L.team_root("planner")
except L.TeamPathError as e: print(e)' 2>&1)"; has "$o" "팀 명단 없음" "ⓒ 명단 없음 = TeamPathError(옛 경로로 후퇴 0)"

echo "== ⓔ 꼴3(외부 harness 루트) — 소비자 2곳이 «현재 리포 안» 을 전제하지 않는다 (DA⑥ r1 Q1)"
R3="$T/r3"; HR3="$T/hroot3"; mkrepo "$R3" 2
mkdir -p "$HR3/design"; mv "$R3/design/teams/harness" "$HR3/design/harness"
sed -i.bak 's#`design/teams/harness/`#`$FT_HARNESS_ROOT/design/harness/`#' "$R3/design/TEAMS.md"; rm -f "$R3/design/TEAMS.md.bak"
GITC "$R3" add -A >/dev/null 2>&1; GITC "$R3" commit -q -m form3; GITC "$R3" update-ref refs/remotes/origin/main HEAD
GITC "$HR3" init -q -b main; GITC "$HR3" add -A >/dev/null 2>&1; GITC "$HR3" commit -q -m card
o="$(cd "$R3" && FT_HARNESS_ROOT="$HR3" bash "$SRC/ft-harness-info.sh" requests 2>&1 </dev/null)"; rc=$?
[ "$rc" = 0 ] && has "$o" "| R1 |" "ⓔ 꼴3 ft-harness-info requests: rc0 + 외부 REQUEST-LEDGER 행" || bad "ⓔ 꼴3 requests rc=$rc ← ${o:0:300}"
o="$(cd "$R3" && FT_HARNESS_ROOT="$HR3" FT_SKILL_DIR="$T/none" bash "$SRC/ft-harness-info.sh" rules 2>&1 </dev/null)"
has "$o" "OK    $HR3/design/harness/REQUEST-LEDGER.md" "ⓔ 꼴3 ft-harness-info rules: 외부 실파일 경로로 OK 표기"
mv "$HR3/design/harness/REQUEST-LEDGER.md" "$T/ledger.bak"
o="$(cd "$R3" && FT_HARNESS_ROOT="$HR3" bash "$SRC/ft-harness-info.sh" requests 2>&1 </dev/null)"; rc=$?
[ "$rc" = 1 ] && has "$o" "REQUEST-LEDGER.md 를 못 읽음" "ⓔ 변이: 외부 원장이 없으면 rc1 REJECT(옛 경로 읽기 0)" || bad "ⓔ 외부 원장 없음 rc=$rc ← ${o:0:300}"
mv "$T/ledger.bak" "$HR3/design/harness/REQUEST-LEDGER.md"
o="$(cd "$R3" && bash "$SRC/ft-harness-info.sh" requests 2>&1 </dev/null)"; rc=$?
[ "$rc" = 1 ] && has "$o" "FT_HARNESS_ROOT" "ⓔ 변이: FT_HARNESS_ROOT 없으면 rc1 ERROR" || bad "ⓔ env 없음 rc=$rc ← ${o:0:300}"
o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_HARNESS_ROOT="$HR3" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
from datetime import datetime
import ft_weekly_review as w
print(w.h1_cards(Path(sys.argv[1]), datetime(2026, 10, 18)))' "$R3" 2>&1)"
has "$o" "H1 card-a" "ⓔ 꼴3 ft_weekly_review.h1_cards: ValueError 없이 외부 카드 목록(외부 저장소 이력)"; hasnt "$o" "Traceback" "ⓔ 꼴3 h1_cards: 예외 0"
rm -rf "$HR3/.git"
o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" FT_HARNESS_ROOT="$HR3" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
from datetime import datetime
import ft_weekly_review as w
try: w.h1_cards(Path(sys.argv[1]), datetime(2026, 10, 18))
except Exception as e: print(type(e).__name__, e)' "$R3" 2>&1)"
has "$o" "TeamPathError ERROR 카드가 git 저장소 밖" "ⓔ 변이: 외부 카드가 저장소 밖이면 명시 TeamPathError(빈 목록 0)"

if [ "${FT_TLP_RUN_EXISTING:-0}" = 1 ]; then
  echo "== ⓓ 기존 시험 rc0"
  for t in test_goal_table_gate test_team_move_roundtrip; do bash "$HERE/$t.sh" > "$T/$t.out" 2>&1; rc=$?; [ "$rc" = 0 ] && ok "ⓓ $t rc0" || bad "ⓓ $t rc=$rc"; done
fi
echo "== fail=$fail"; [ "$fail" = 0 ]
