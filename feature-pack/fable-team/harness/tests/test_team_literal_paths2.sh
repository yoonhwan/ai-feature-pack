#!/usr/bin/env bash
# test_team_literal_paths2.sh — R383 2차: 팀 이름 글자 경로 19파일(+키트 전용 5)이 ft_team_root / ft_team_lib 경유로 풀리는지 «쌍둥이 픽스처» 시험
#   ⓐ 린트(실 bin·키트 bin) = `INFO 리터럴 대기 0` + `OK 하드코딩 0` · 문법 · 키트 사본 cmp0 · lib 모드 755
#   ⓑ lib 도우미(ft_team_cands · ft_team_has) 3꼴 표 · 명단 없음/팀 없음 구분
#   ⓒ 쌍둥이 픽스처(옛 꼴 `design/<팀>/` ↔ 새 꼴 `design/teams/<팀>/`)에서 도구가 두 꼴 다 찾는다 — 파이썬 3 · 설치 게이트 2 · 슬롯 · 고아 카드
#   ⓓ 나머지 셸 도구는 «글자 경로 0 + lib 경유» 정적 대조(동적 시험은 기존 시험이 본다)
#   ⓔ 22파일 «실제 호출» 대조표(DA⑥ r1 Q1 → r2 Q1 · 설계 §10-1 수용행렬 · §10-4 등급) — 소비자 22 = 셸 14 + 파이썬 3 + 키트 5(도우미 ft-team-lib·ft-team-path-lint 2 는 표 밖 «도우미:» 줄).
#      등급 A(15) = 두 꼴 실제 실행 + 그 꼴 산출물 단언 + 명단 없음 fail-closed rc≠0 · B(2 · drift-check·issue-reopen) = 실행 + 결과 원문 + `grep -c 'ft_team\|design/'` 0(경로 미해석 · rc0 허용)
#      · C(3 · pm-tick·wall-check·wall-read) = bash -n + 팀 폴더 해석 호출 1회 + 사유 «라이브 tmux·슬랙 의존». fail-closed 열 = 행렬 기대값(`any` 0 · rc0 허용 행은 사유 문자열 필수 · autonomy 는 명단 읽는 분기 `on` 1건 rc≠0).
# 임시 폴더·가짜 도구만 쓴다 — 실제 리포·seats·tmux 세션·mbox 는 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
_T0="$(mktemp -d)"; T="$(cd "$_T0" && pwd -P)"; trap 'rm -rf "$_T0"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

CHANGED_SH=(ft-nano-spawn ft-nano-slots ft-nano-spawn-undo ft-nano-close ft-index-gate ft-index-move ft-index-move-install ft-orphan-cards ft-live-bin-drift-check ft-issue-reopen ft-autonomy-start ft-autonomy ft-proposal-gate ft-proxy-decide ft-team-lib ft-team-path-lint)
CHANGED_PY=(ft_news_io ft_news_ledger ft_news_ledger_notify)
KITONLY_SH=(ft-index-lint-install ft-index-lint ft-pm-tick ft-wall-check ft-wall-read)
# 수용행렬(설계 §10-1·§10-4) — 소비자 22 = CONS_SH 14 + CHANGED_PY 3 + KITONLY_SH 5 · 도우미 2 는 표 밖
CONS_SH=(ft-nano-spawn ft-nano-slots ft-nano-spawn-undo ft-nano-close ft-index-gate ft-index-move ft-index-move-install ft-orphan-cards ft-live-bin-drift-check ft-issue-reopen ft-autonomy-start ft-autonomy ft-proposal-gate ft-proxy-decide)
HELPER_SH=(ft-team-lib ft-team-path-lint)
grade() { case "$1" in ft-live-bin-drift-check|ft-issue-reopen) echo B;; ft-pm-tick|ft-wall-check|ft-wall-read) echo C;; *) echo A;; esac; }   # §10-4 등급 = 행렬 기대(실측 미달 칸은 enote 사유로 낮춘다 · 아래 표 단언)

echo "== ⓐ 린트 · 문법 · 키트 사본 cmp0 · lib 모드"
out="$(bash "$SRC/ft-team-path-lint.sh" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "$out" "INFO 리터럴 대기 0" "ⓐ 실 bin 린트: INFO 리터럴 대기 0" && has "$out" "OK 하드코딩 0" "  └ OK 하드코딩 0" || bad "ⓐ 실 bin 린트 rc=$rc ← $out"
out="$(bash "$SRC/ft-team-path-lint.sh" "$KIT" 2>&1)"; rc=$?; [ "$rc" = 0 ] && has "$out" "INFO 리터럴 대기 0" "ⓐ 키트 bin 린트(키트 전용 5 포함): INFO 대기 0 · rc0" || bad "ⓐ 키트 bin 린트 rc=$rc ← $out"
for f in "${CHANGED_SH[@]}"; do bash -n "$SRC/$f.sh" && ok "bash -n $f" || bad "bash -n $f"; cmp -s "$SRC/$f.sh" "$KIT/$f.sh" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"; done
for f in "${CHANGED_PY[@]}"; do python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/$f.py" && ok "ast $f" || bad "ast $f"; cmp -s "$SRC/$f.py" "$KIT/$f.py" && ok "키트 사본 cmp0 $f.py" || bad "키트 사본 cmp $f.py"; done
for f in "${KITONLY_SH[@]}"; do bash -n "$KIT/$f.sh" && ok "bash -n 키트 전용 $f" || bad "bash -n 키트 전용 $f"; done
[ "$(stat -f %Lp "$SRC/ft-team-lib.sh" 2>/dev/null || stat -c %a "$SRC/ft-team-lib.sh")" = 755 ] && ok "ⓐ ft-team-lib.sh 모드 755(추적본)" || bad "ⓐ lib 모드"
[ "$(stat -f %Lp "$KIT/ft-team-lib.sh" 2>/dev/null || stat -c %a "$KIT/ft-team-lib.sh")" = 755 ] && ok "ⓐ ft-team-lib.sh 모드 755(키트)" || bad "ⓐ 키트 lib 모드"

TEAMS=(harness planner cfo ops v65)
mkteams() {  # <루트> <꼴 1|2|3> [<꼴3 외부 루트>]  — TEAMS.md 만 쓴다
  local R="$1" form="$2" t p; mkdir -p "$R/design"
  { printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n'
    for t in "${TEAMS[@]}"; do case "$form" in 1) p="design/$t/";; 2) p="design/teams/$t/";; 3) p="\$FT_HARNESS_ROOT/design/$t/";; esac; printf '| %s | `%s` | b | 현역 |\n' "$t" "$p"; done; } > "$R/design/TEAMS.md"
}

echo "== ⓑ lib 도우미 — ft_team_cands · ft_team_has (3꼴 표)"
for F in 1 2 3; do mkteams "$T/b$F" "$F"; done; mkdir -p "$T/hr/design"
c1="$(bash -c '. "$1"; ft_team_cands "$2" v65 | tr "\n" " "' _ "$SRC/ft-team-lib.sh" "$T/b1")"
[ "$c1" = "$T/b1/design/v65 $T/b1/design/teams/v65 " ] && ok "ⓑ cands 꼴1 = 명단 꼴 → 쌍둥이" || bad "ⓑ cands 꼴1: $c1"
c2="$(bash -c '. "$1"; ft_team_cands "$2" v65 | tr "\n" " "' _ "$SRC/ft-team-lib.sh" "$T/b2")"
[ "$c2" = "$T/b2/design/teams/v65 $T/b2/design/v65 " ] && ok "ⓑ cands 꼴2 = 새 꼴 → 옛 꼴" || bad "ⓑ cands 꼴2: $c2"
c3="$(FT_HARNESS_ROOT="$T/hr" bash -c '. "$1"; ft_team_cands "$2" v65 | tr "\n" " "' _ "$SRC/ft-team-lib.sh" "$T/b3")"
[ "$c3" = "$T/hr/design/v65 " ] && ok "ⓑ cands 꼴3 = 외부 루트 1개(쌍둥이 0)" || bad "ⓑ cands 꼴3: $c3"
out="$(bash -c '. "$1"; ft_team_cands "$2" zz; echo rc=$?' _ "$SRC/ft-team-lib.sh" "$T/b1" 2>&1)"; has "$out" "rc=1" "ⓑ cands 명단에 없는 팀 = ERROR rc1"
has_t() { bash -c '. "$1"; ft_team_has "$2" "$3" "$4"; echo $?' _ "$SRC/ft-team-lib.sh" "$@" 2>/dev/null; }
for F in 1 2; do
  R="$T/b$F"; export FT_REPO_ROOT="$R"
  [ "$(has_t planner "/x/design/planner/indices/대기/a.md" indices/)" = 0 ] && [ "$(has_t planner "design/teams/planner/indices/a.md" indices/)" = 0 ] && ok "ⓑ has 꼴$F: 옛·새 꼴 경로 둘 다 안(상대·절대)" || bad "ⓑ has 꼴$F 안"
  [ "$(has_t planner "/x/design/cfo/indices/a.md" indices/)" = 1 ] && [ "$(has_t planner "/x/design/plannerX/indices/a.md" indices/)" = 1 ] && ok "ⓑ has 꼴$F: 다른 팀·접두 오탐 → 밖(rc1)" || bad "ⓑ has 꼴$F 밖"
  [ "$(has_t kk "/x/design/kk/indices/a.md" indices/)" = 1 ] && ok "ⓑ has 꼴$F: 명단에 없는 팀 = 밖(rc1 · ERROR 아님)" || bad "ⓑ has 꼴$F 없는 팀"
done
unset FT_REPO_ROOT
[ "$(FT_TEAMS_MD=/nonexistent has_t planner /x indices/)" = 2 ] && ok "ⓑ has 명단 파일 없음 = rc2(ERROR · 후퇴 0)" || bad "ⓑ has 명단 없음"
export FT_REPO_ROOT="$T/b3" FT_HARNESS_ROOT="$T/hr"
[ "$(has_t harness "$T/hr/design/harness/indices/a.md" indices/)" = 0 ] && ok "ⓑ has 꼴3: FT_HARNESS_ROOT 절대경로 아래만 안" || bad "ⓑ has 꼴3"
unset FT_REPO_ROOT FT_HARNESS_ROOT

echo "== ⓒ 쌍둥이 픽스처 — 옛 꼴 ↔ 새 꼴"
mkfix() {  # <루트> <꼴 1|2>  — planner 판정 원장 1줄 · v65·harness·cfo 카드 폴더
  local R="$1" F="$2" base; mkteams "$R" "$F"; case "$F" in 1) base="$R/design";; 2) base="$R/design/teams";; esac
  mkdir -p "$R/.fable-team" "$base/planner" "$base/harness/indices/진행" "$base/cfo/indices/진행" "$base/v65/indices/대기"
  printf '| 번호 | 시각 | 내용 |\n|---|---|---|\n| 77 | 10:00 | (오빠) 결정 시험 |\n' > "$base/planner/VERDICTS-planner-1-20261018.md"
  printf '# 원장\n' > "$base/planner/PLAN-oppa-ledger.md"
  git -C "$R" init -q -b main; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init
}
for F in 1 2; do
  R="$T/f$F"; mkfix "$R" "$F"
  # 파이썬 3: 워크트리(.worktrees/<wt>)의 팀 폴더를 그 워크트리 명단으로 푼다
  W="$R/.worktrees/wt"; mkdir -p "$R/.worktrees"; git -C "$R" worktree add -q "$W" -b nano/wt 2>/dev/null
  printf '{"_cards_wt": "wt"}\n' > "$R/.fable-team/seats-planner.json"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from datetime import datetime
from pathlib import Path
import ft_news_io as io, ft_news_ledger_notify as nt
r = Path(sys.argv[1])
print(io.read_ledger(r, datetime(2026, 10, 18, 10, 0)))
print(nt.verdict_rows(r, "wt"))' "$R" 2>&1)"
  has "$o" "(오빠) 결정 시험" "ⓒ$F ft_news_io.read_ledger: 칸 경로의 판정 원장을 읽는다"; has "$o" "('77', '(오빠) 결정 시험')" "ⓒ$F ft_news_ledger_notify.verdict_rows: 같은 원장 행"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
import ft_news_ledger as nl
print(nl.planner_ledger_rel(Path(sys.argv[1])))' "$R" 2>&1)"
  case "$F" in 1) want="design/planner/PLAN-oppa-ledger.md";; 2) want="design/teams/planner/PLAN-oppa-ledger.md";; esac
  [ "$o" = "$want" ] && ok "ⓒ$F ft_news_ledger.planner_ledger_rel = $want" || bad "ⓒ$F ledger_rel: $o"
  # 설치 게이트 2: 하네스 팀 카드 판정이 두 꼴 다 통한다
  card() { printf '# 인덱스: c\n%s\n## 상태\n- x\n' "$2" > "$1"; }
  card "$R/design/$([ "$F" = 2 ] && echo teams/)harness/indices/진행/h.md" "- 설치: 있음"
  card "$R/design/$([ "$F" = 2 ] && echo teams/)cfo/indices/진행/c.md" "- x"
  card "$R/design/$([ "$F" = 2 ] && echo teams/)harness/indices/진행/n.md" "- x"
  H="$R/design/$([ "$F" = 2 ] && echo teams/)harness/indices/진행"; C="$R/design/$([ "$F" = 2 ] && echo teams/)cfo/indices/진행/c.md"
  o="$(bash "$SRC/ft-index-move-install.sh" "$H/h.md" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$o" "--landed" "ⓒ$F ft-index-move-install: 하네스 카드(설치: 있음) + --landed 없음 → REJECT" || bad "ⓒ$F install 하네스 rc=$rc ← $o"
  o="$(bash "$SRC/ft-index-move-install.sh" "$C" 2>&1)"; rc=$?; [ "$rc" = 0 ] && ok "ⓒ$F ft-index-move-install: 다른 팀 카드 = 범위 밖 통과" || bad "ⓒ$F install cfo rc=$rc ← $o"
  o="$(cd "$R" && bash "$KIT/ft-index-lint-install.sh" "$H/n.md" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$o" "설치:" "ⓒ$F ft-index-lint-install(키트): 하네스 카드 설치 줄 없음 → REJECT" || bad "ⓒ$F lint-install 하네스 rc=$rc ← $o"
  o="$(cd "$R" && bash "$KIT/ft-index-lint-install.sh" "$C" 2>&1)"; rc=$?; [ "$rc" = 0 ] && ok "ⓒ$F ft-index-lint-install(키트): 다른 팀 카드 통과" || bad "ⓒ$F lint-install cfo rc=$rc ← $o"
  # 슬롯: FT_INDEX_DIR 없이 v65 칸의 indices 를 찾는다
  mkdir -p "$T/sb$F" "$T/slot$F"; cp "$SRC/ft-nano-slots.sh" "$SRC/ft-team-lib.sh" "$T/sb$F/"
  printf '#!/usr/bin/env bash\necho "IDLE 2020-01-01T00:00:00Z"\n' > "$T/sb$F/ft-seat-status.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/sb$F/tmux"; chmod +x "$T/sb$F/"*
  V="$R/design/$([ "$F" = 2 ] && echo teams/)v65/indices/대기"
  printf '# 인덱스: slot-c\nIssue: #7\n상태: 대기\n선행: 없음\n시험 입력: 없음\n기준값: 없음 → 대체 축 x\n## 구현 범위\nx\n' > "$V/slot-c.md"
  echo '{}' > "$T/slot$F/seats.json"
  o="$(cd "$R" && PATH="$T/sb$F:$PATH" FT_SEATS_JSON="$T/slot$F/seats.json" bash "$T/sb$F/ft-nano-slots.sh" 2>/dev/null)"
  has "$o" "slot-c" "ⓒ$F ft-nano-slots: v65 칸(${F}꼴)의 indices/대기 카드를 찾는다(FT_INDEX_DIR 없이)"
  # 고아 카드: 워크트리 cfo 카드 폴더 기본값
  mkdir -p "$R/.worktrees/c-level-planning/design"; cp "$R/design/TEAMS.md" "$R/.worktrees/c-level-planning/design/TEAMS.md"
  mkdir -p "$R/.worktrees/c-level-planning/design/$([ "$F" = 2 ] && echo teams/)cfo/indices/진행"; printf '# 인덱스: orphan-cfo\n' > "$R/.worktrees/c-level-planning/design/$([ "$F" = 2 ] && echo teams/)cfo/indices/진행/orphan-cfo.md"
  mkdir -p "$T/ob$F"; cp "$SRC/ft-orphan-cards.sh" "$SRC/ft-team-lib.sh" "$T/ob$F/"; printf '#!/usr/bin/env bash\necho "no server running on /tmp/x" >&2; exit 1\n' > "$T/ob$F/tmux"; chmod +x "$T/ob$F/tmux"
  o="$(cd "$R" && PATH="$T/ob$F:$PATH" FT_SEATS_JSON="$T/slot$F/seats.json" bash "$T/ob$F/ft-orphan-cards.sh" 2>&1)"
  has "$o" "orphan-cfo" "ⓒ$F ft-orphan-cards: c-level-planning 워크트리의 cfo 팀 폴더(${F}꼴) 진행 카드를 센다"
done
# 제안서 게이트 ⓑ(byz-tank approved + 인터뷰 판정): 판정 원장 폴더를 planner 팀 폴더(두 꼴)에서 «그 순간» 에 푼다 — FT_PLANNER_VERDICTS_DIR 없이
printf '#!/usr/bin/env bash\ncase "$1 $2" in\n  "issue view") cat "$FAKE/view-$3.json";;\n  "api --paginate") n="${4#repos/*/issues/}"; cat "$FAKE/timeline-${n%%/timeline}.json";;\n  *) exit 1;;\nesac\n' > "$T/gh"
for F in 1 2; do
  R="$T/f$F"; WV="$R/.worktrees/v6-realtime-live"; mkdir -p "$WV/design"; cp "$R/design/TEAMS.md" "$WV/design/TEAMS.md"
  PB="$WV/design/$([ "$F" = 2 ] && echo teams/)planner"; mkdir -p "$PB"
  printf '816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택\n' > "$PB/VERDICTS-planner-1-20261018.md"
  mkdir -p "$T/gh$F"; python3 "$HERE/_proposal_issue_fixture.py" "$T/gh$F" 12 b; cp "$T/gh" "$T/gh$F/gh"
  o="$(cd "$R" && env -u FT_PLANNER_VERDICTS_DIR FAKE="$T/gh$F" FT_GH_READ="bash $T/gh$F/gh" GH_REPO="o/r" FT_GATE_GH_TIMEOUT=2 BYZ_ROOT="$R" bash "$SRC/ft-proposal-gate.sh" --issue 12 2>&1)"
  has "$o" "OK #12 승인 ⓑ 판정 816" "ⓒ$F ft-proposal-gate: 판정 원장 폴더를 v6 워크트리의 planner 칸(${F}꼴)에서 푼다(FT_PLANNER_VERDICTS_DIR 없이)"
done
rm -f "$T/f1/.worktrees/v6-realtime-live/design/TEAMS.md"
o="$(cd "$T/f1" && env -u FT_PLANNER_VERDICTS_DIR FAKE="$T/gh1" FT_GH_READ="bash $T/gh1/gh" GH_REPO="o/r" FT_GATE_GH_TIMEOUT=2 BYZ_ROOT="$T/f1" bash "$SRC/ft-proposal-gate.sh" --issue 12 2>&1)"; rc=$?
[ "$rc" = 1 ] && has "$o" "판정 원장 폴더를 못 풀었다" "ⓒ 변이: 명단을 못 읽으면 옛 경로로 후퇴하지 않고 REJECT rc1" || bad "ⓒ 판정 원장 명단 없음 rc=$rc ← $o"
# 명단을 못 읽으면 후퇴하지 않고 REJECT
mkdir -p "$T/nolist/design/harness/indices/진행"; git -C "$T/nolist" init -q -b main; printf '# 인덱스: c\n- 설치: 있음\n' > "$T/nolist/design/harness/indices/진행/h.md"
o="$(bash "$SRC/ft-index-move-install.sh" "$T/nolist/design/harness/indices/진행/h.md" 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$o" "하네스 팀 폴더를 못 풀었다" "ⓒ 변이: TEAMS.md 없으면 «범위 밖 통과» 로 후퇴하지 않고 REJECT rc1" || bad "ⓒ 명단 없음 rc=$rc ← $o"

echo "== ⓓ 나머지 셸 도구 — 글자 경로 0 + lib 경유 (정적)"
for f in ft-nano-spawn ft-nano-spawn-undo ft-nano-close ft-index-gate ft-index-move ft-autonomy-start ft-autonomy ft-proxy-decide ft-proposal-gate; do
  n="$(grep -vE '^[[:space:]]*#' "$SRC/$f.sh" | grep -cE 'design/(teams/)?(planner|harness|cfo|ops|graphics|issues|feature|kk|v65|loom|lecture|room|concierge)/')"
  [ "$n" = 0 ] && grep -qE 'ft[-_]team[-_]lib' "$SRC/$f.sh" && ok "ⓓ $f: 리터럴 팀 경로 0 · lib 경유(셸 ft-team-lib.sh 또는 파이썬 ft_team_lib)" || bad "ⓓ $f 리터럴 ${n}곳 또는 lib 미참조"
done
for f in ft-autonomy-start ft-autonomy ft-proxy-decide; do grep -q 'ft_team_in "\$ROOT" planner' "$SRC/$f.sh" && ok "ⓓ $f: planner 폴더 = ft_team_in" || bad "ⓓ $f planner 해석"; done
grep -q 'ft_team_has_ref "\$WT" planner "\$IDX" indices/' "$SRC/ft-nano-spawn.sh" && ok "ⓓ ft-nano-spawn: planner 카드 판정 = ft_team_has_ref(명단 = ref · R406)" || bad "ⓓ spawn planner 판정"
grep -q 'ft_team_file_ref "\$WT" v65 SEATBELT-README.md' "$SRC/ft-nano-spawn.sh" && ok "ⓓ ft-nano-spawn: SEATBELT 경로 = ft_team_file_ref v65(명단 = ref · 실재 1개 · R406)" || bad "ⓓ spawn SEATBELT"
for f in ft-nano-close ft-nano-spawn-undo; do grep -q 'ft_team_in .* v65' "$SRC/$f.sh" && ok "ⓓ $f: 기본 원장 = ft_team_in v65" || bad "ⓓ $f 원장"; done

echo "== ⓔ 22파일 «실제 호출» 두 꼴 대조표 (DA⑥ r1 Q1 · 옛 꼴 ↔ 새 꼴 픽스처마다 실행 · 읽기 도구는 꼴에만 있는 산출물을 찾는다 · 쓰기 도구는 decoy(다른 꼴 폴더) 불변 + 새 경로 쓰기)"
exe() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$1"; chmod +x "$1"; }
snap() { local r="$1"; shift; (cd "$r" && find "$@" -type f 2>/dev/null | LC_ALL=C sort | xargs shasum 2>/dev/null); }   # <루트> <하위 폴더…> — decoy 불변 대조용 sha 목록
bf() { case "$1" in 1) echo design;; 2) echo design/teams;; esac; }   # 꼴 → 팀 폴더 접두
af() { case "$1" in 1) echo design/teams;; 2) echo design;; esac; }   # 꼴 → decoy(다른 꼴) 접두
enote() { echo "$2" > "$T/en.$1"; }   # <도구> <사유·결과 원문> — B·C 행(또는 A 미달 칸)의 표 줄 사유
erec() {  # <도구> <꼴> <rc> <풀린 경로 조각|-> — 표 한 칸 기록 + 꼴 단언(옛 꼴 = design/<팀>/ · 새 꼴 = design/teams/<팀>/)
  echo "$3" > "$T/er.$1.$2"; echo "$4" > "$T/ep.$1.$2"
  [ "$4" = - ] && return 0
  case "$2" in
    1) case "$4" in *design/teams/*) bad "ⓔ$2 $1 — 옛 꼴 픽스처인데 새 경로: $4";; *design/*) ok "ⓔ$2 $1 — 옛 꼴 경로로 풀림";; *) bad "ⓔ$2 $1 — 경로 조각 이상: $4";; esac;;
    2) case "$4" in *design/teams/*) ok "ⓔ$2 $1 — 새 꼴 경로로 풀림";; *) bad "ⓔ$2 $1 — 새 꼴 픽스처인데 옛 경로: $4";; esac;;
  esac
}
efix() {  # <루트> <꼴> — 리포 · TEAMS.md(꼴) · v65 대기/진행/20260912 · planner · decoy(다른 꼴) 같은 이름 파일(다른 내용) · v6 워크트리
  local R="$1" F="$2" b a; b="$(bf "$F")"; a="$(af "$F")"; mkdir -p "$R" && git -C "$R" init -q -b main; mkteams "$R" "$F"
  mkdir -p "$R/$b/v65/20260912" "$R/$a/v65/20260912" "$R/$b/v65/indices/대기" "$R/$b/v65/indices/진행" "$R/$a/v65/indices/대기" "$R/$b/planner" "$R/$a/planner" "$R/.fable-team/comm"
  : > "$R/$b/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"; echo decoy > "$R/$a/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"
  echo decoy > "$R/$a/planner/VERDICTS-planner-1-20261018.md"; echo decoy > "$R/$a/v65/indices/대기/slug.md"
  printf '.worktrees/\n.fable-team/\n' > "$R/.gitignore"; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init
}
SEAT_N='ft-v65-temp-u#0'; SEAT_C='byz-planner-nano-ovr#0'
# ── 쓰기 도구 3 + undo: decoy 불변 + 새 경로 쓰기 ─────────────────────────────
p_spawn() {  # ft-nano-spawn(등급 A · §10-4) — 카드 이동은 «실파일» ft-index-move.sh 로(대역 0): 새 꼴 진행/ 에 카드 실파일 + decoy 카드 불변 · SEATBELT 경로 = 그 꼴 v65 폴더
  local F="$1" R="$T/xs$F" b a hb sh o rc s0; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  printf '# 카드\n\n## 구현 범위\n- `worker/w.py` 를 고친다\n\n## 상태\n- 대기\n' > "$R/$b/v65/indices/대기/slug.md"; mkdir -p "$R/worker"; echo w > "$R/worker/w.py"; echo '{}' > "$R/.fable-team/seats.json"; echo sb > "$R/$b/v65/SEATBELT-README.md"   # R406: README = 그 꼴 v65 폴더에 실재 1개
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m card
  hb="$T/xhb$F"; sh="$T/xsh$F"; mkdir -p "$hb" "$sh"; cp "$SRC/ft-nano-spawn.sh" "$SRC/ft-index-move.sh" "$SRC/ft-team-lib.sh" "$SRC"/ft_*.py "$hb/"
  for s in ft-index-lint ft-proposal-gate ft-resource-gate ft-agent-ready; do exe "$hb/$s.sh" 'exit 0'; done   # 카드 형식 린트·게이트만 대역 — 이동 자체는 실파일
  exe "$hb/ft-send-verified.sh" "echo \"SEND \$*\" >> $T/xcalls$F.log; exit 0"
  exe "$hb/ft-sheet-events.sh" 'case "$1" in key) echo k;; esac; exit 0'
  exe "$sh/sleep" 'exit 0'; exe "$sh/tmuxc" "touch $T/xopened$F; exit 0"
  exe "$sh/tmux" "case \"\$1\" in has-session) [ -e $T/xopened$F ] && [[ \"\$*\" == *\"#0\"* ]]; exit \$? ;; list-panes) echo \"ft-v65-temp-slug#0|%1|123\" ;; show-option) echo 1 ;; esac; exit 0"
  s0="$(snap "$R" "$a/v65" "$a/planner")"
  o="$(cd "$R" && PATH="$sh:$PATH" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_TEAMSET=0 FT_TEAMS_REF=HEAD timeout 20 bash "$hb/ft-nano-spawn.sh" "$R/$b/v65/indices/대기/slug.md" --from me#1 2>&1)"; rc=$?   # R406: 명단 = ref — 픽스처는 origin/main ref 0 · 명단은 HEAD 커밋
  [ "$rc" = 0 ] && ok "ⓔ$F ft-nano-spawn: rc0" || bad "ⓔ$F ft-nano-spawn rc=$rc ← $(printf "%s" "$o" | grep -E "REJECT|ERROR|WARN 중복|이미" | head -3 | cut -c1-300)"
  [ -f "$R/$b/v65/indices/진행/slug.md" ] && [ ! -e "$R/$b/v65/indices/대기/slug.md" ] && ok "ⓔ$F ft-nano-spawn: 실파일 ft-index-move 로 ${F}꼴 진행/ 에 카드 실파일 존재(대기/ 에서 사라짐)" || bad "ⓔ$F ft-nano-spawn 카드 실파일 위치 ← $(cd "$R" && find "$b/v65/indices" -type f | tr '\n' ' ')"
  [ -f "$R/$a/v65/indices/대기/slug.md" ] && ok "ⓔ$F ft-nano-spawn: decoy 카드(다른 꼴 대기/)는 그대로 있다" || bad "ⓔ$F ft-nano-spawn decoy 카드 사라짐"
  has "$(cat "$T/xcalls$F.log" 2>/dev/null)" "$R/$b/v65/SEATBELT-README.md" "ⓔ$F ft-nano-spawn: 발주 본문 SEATBELT 경로 = ${F}꼴 v65 폴더(ft_team_file_ref)"
  [ "$(snap "$R" "$a/v65" "$a/planner")" = "$s0" ] && ok "ⓔ$F ft-nano-spawn: decoy(다른 꼴 폴더) sha 불변" || bad "ⓔ$F ft-nano-spawn decoy 변함"
  erec ft-nano-spawn "$F" "$rc" "$b/v65/indices/진행/slug.md"
}
p_close() {  # ft-nano-close — 명부 index 는 «다른 꼴» 경로(쌍둥이 후보로 카드를 찾는다) · 원장 = ${꼴} v65 폴더 · decoy 원장 불변
  local F="$1" R="$T/xc$F" b a LW NW SHA bin fake oi si o rc s0 L; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  LW="$R/.worktrees/v6-realtime-live"; GITC "$R" worktree add -q "$LW" -b feat/v6-realtime-live
  NW="$R/.worktrees/v65-ovr"; GITC "$R" worktree add -q "$NW" -b nano/ovr; git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m work; SHA="$(git -C "$NW" rev-parse HEAD)"
  bin="$T/xcb$F"; fake="$T/xcf$F"; mkdir -p "$bin" "$fake" "$T/xcm$F/bodies"
  cp "$KIT/ft-nano-slots.sh" "$KIT/ft-nano-close.sh" "$KIT/ft-nano-evidence-check.sh" "$KIT/ft-wt-sweep.sh" "$KIT/ft-team-lib.sh" "$KIT/ft-hil.sh" "$KIT/ft-sheet-events.sh" "$KIT"/ft_sheet_events.py "$KIT"/ft_sheet_confirm.py "$KIT"/ft_sheet_key.py "$KIT"/ft_board_env.py "$KIT"/ft_board_mail.py "$bin/"
  exe "$bin/ft-nano-cherry-gate.sh" 'echo "OK cherry stub"; exit 0'
  exe "$fake/tmux" 'case "$1" in list-panes) case "$*" in *pane_current_path*) cat "$FAKE_PANE_CWDS";; *) cat "$FAKE_PANES";; esac;; display-message) cat "$FAKE_CWD";; has-session) exit 1;; set-option|kill-session) echo "$*" >> "$FAKE_LOG";; esac'
  oi="design/v65/indices/진행/ovr.md"; si="design/teams/v65/indices/진행/ovr.md"; [ "$F" = 1 ] && oi="$si"   # oi = 명부에 적힌 «다른 꼴» 경로
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT_C" "$oi" > "$R/.fable-team/seats-planner.json"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$R/$b/v65/indices/진행/ovr.md"
  echo seq > "$T/xcm$F/bodies/1.txt"; echo res > "$T/xcr$F.md"; printf '%s|%%1\n' "$SEAT_C" > "$T/xcp$F"; printf '%s|%s\n' "$SEAT_C" "$NW" > "$T/xcw$F"; printf '%s' "$NW" > "$T/xcd$F"; : > "$T/xcl$F"
  s0="$(snap "$LW" "$a/v65" "$a/planner")"
  o="$(cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$T/xcsr$F" HIL_DIR="$T/xch$F" HIL_CLIP=0 PATH="$fake:$PATH" FAKE_PANES="$T/xcp$F" FAKE_CWD="$T/xcd$F" FAKE_PANE_CWDS="$T/xcw$F" FAKE_LOG="$T/xcl$F" FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$R/.fable-team/seats-planner.json" FT_INBOX_ROOT="$T/xcm$F" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/xcc$F" timeout 60 bash "$bin/ft-nano-close.sh" "$SEAT_C" --result "$T/xcr$F.md" --recv 1 --wt "$NW" --branch nano/ovr 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "CLOSED $SEAT_C" "ⓔ$F ft-nano-close: 명부 index(다른 꼴)의 카드를 쌍둥이 후보로 찾아 CLOSED" || bad "ⓔ$F ft-nano-close rc=$rc ← ${o:0:400}"
  L="$LW/$b/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"; has "$(cat "$L" 2>/dev/null)" "$SEAT_C" "ⓔ$F ft-nano-close: 원장 append = ${F}꼴 v65 폴더(ft_team_in 원장 워크트리)"
  [ "$(snap "$LW" "$a/v65" "$a/planner")" = "$s0" ] && ok "ⓔ$F ft-nano-close: decoy 원장(다른 꼴) sha 불변" || bad "ⓔ$F ft-nano-close decoy 변함"
  erec ft-nano-close "$F" "$rc" "$b/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"
}
p_undo() {  # ft-nano-spawn-undo — 롤백 모드: 원장 줄 = ${꼴} v65 폴더 · decoy 불변
  local F="$1" R="$T/xu$F" b a LW NW BS fake NOW o rc s0 L; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  printf '# c\n' > "$R/$b/v65/indices/대기/u.md"; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m card
  LW="$R/.worktrees/v6-realtime-live"; GITC "$R" worktree add -q "$LW" -b feat/v6-realtime-live
  NW="$R/.worktrees/v65-u"; GITC "$R" worktree add -q "$NW" -b nano/u; BS="$(git -C "$NW" rev-parse HEAD)"
  printf '{"branch":"nano/u","base_sha":"%s"}\n' "$BS" > "$NW/.worktree-info.json"; echo '{}' > "$R/.fable-team/seats.json"; : > "$R/.fable-team/comm/mailbox.log.jsonl"
  fake="$T/xuf$F"; mkdir -p "$fake"; NOW="$(date +%s)"
  exe "$fake/tmux" "case \"\$1\" in list-panes) echo \"$SEAT_N|%1|$NOW\";; display-message) printf '%s' \"$NW\";; set-option|kill-session|show-option) echo \"\$*\" >> $T/xul$F;; esac"
  s0="$(snap "$LW" "$a/v65" "$a/planner")"
  o="$(cd "$R" && PATH="$fake:$PATH" HOME="$T/xuh$F" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_UNDO_STATE="$T/xus$F" FT_MBOX_DIR="$R/.fable-team/comm" timeout 30 bash "$SRC/ft-nano-spawn-undo.sh" "$SEAT_N" --owned "%1:$NOW" --card "$R/$b/v65/indices/대기/u.md" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "UNDONE $SEAT_N" "ⓔ$F ft-nano-spawn-undo: 롤백 UNDONE" || bad "ⓔ$F ft-nano-spawn-undo rc=$rc ← ${o:0:300}"
  L="$LW/$b/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"; has "$(cat "$L" 2>/dev/null)" "$SEAT_N" "ⓔ$F ft-nano-spawn-undo: 원장 줄 = ${F}꼴 v65 폴더"
  [ "$(snap "$LW" "$a/v65" "$a/planner")" = "$s0" ] && ok "ⓔ$F ft-nano-spawn-undo: decoy 원장 sha 불변" || bad "ⓔ$F ft-nano-spawn-undo decoy 변함"
  erec ft-nano-spawn-undo "$F" "$rc" "$b/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"
}
p_move() {  # ft-index-move — 진행→대기(되돌리기): 카드 이동 = ${꼴} 폴더 · decoy 카드 불변
  local F="$1" R="$T/xm$F" b a o rc s0; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  printf '# 인덱스: mv\n## 상태\n- x\n' > "$R/$b/v65/indices/진행/mv.md"; printf '# 인덱스: mv\n## 상태\n- decoy\n' > "$R/$a/v65/indices/대기/mv.md"; mkdir -p "$R/$a/v65/indices/진행"; cp "$R/$a/v65/indices/대기/mv.md" "$R/$a/v65/indices/진행/mv.md"; rm "$R/$a/v65/indices/대기/mv.md"
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m cards; s0="$(snap "$R" "$a/v65" "$a/planner")"; mkdir -p "$T/xms$F"
  o="$(cd "$R" && FT_INDEX_STATE_DIR="$T/xms$F" timeout 30 bash "$SRC/ft-index-move.sh" "$R/$b/v65/indices/진행/mv.md" 대기 --seat s#1 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "MOVED 진행→대기 $R/$b/v65/indices/대기/mv.md" "ⓔ$F ft-index-move: 이동 도착 = ${F}꼴 폴더(v65 판정 = ft_team_has)" || bad "ⓔ$F ft-index-move rc=$rc ← ${o:0:300}"
  [ -f "$R/$b/v65/indices/대기/mv.md" ] && [ ! -e "$R/$b/v65/indices/진행/mv.md" ] && ok "ⓔ$F ft-index-move: ${F}꼴 폴더에서 실제로 옮겨짐" || bad "ⓔ$F ft-index-move 파일 위치"
  [ "$(snap "$R" "$a/v65" "$a/planner")" = "$s0" ] && ok "ⓔ$F ft-index-move: decoy(다른 꼴) 카드 sha 불변" || bad "ⓔ$F ft-index-move decoy 변함"
  # 진행→완성: v65 카드 판정(ft_team_has)으로 원장 트랙이 v65 — 두 꼴 모두 index-ledger.v65.jsonl 에 기록 · 카드는 그 꼴 완성/ 으로
  printf '# 인덱스: dn\n- 정본 영향 없음: 시험용 카드라서 정본 갱신 대상이 없다\n- 규칙: 없음 — 시험용 카드라서 규칙 줄 대상이 아니다\n## 상태\n- 세트: x\n' > "$R/$b/v65/indices/진행/dn.md"; printf '## §1 dn\n닫힘 dn\n' > "$T/xmda$F.md"
  GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m dn; s0="$(snap "$R" "$a/v65" "$a/planner")"
  o="$(cd "$R" && FT_INDEX_STATE_DIR="$T/xms$F" timeout 30 bash "$SRC/ft-index-move.sh" "$R/$b/v65/indices/진행/dn.md" 완성 --da "$T/xmda$F.md#§1" --seat s#1 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "MOVED 진행→완성 $R/$b/v65/indices/완성/dn.md" "ⓔ$F ft-index-move(완성): 도착 = ${F}꼴 폴더 완성/" || bad "ⓔ$F ft-index-move 완성 rc=$rc ← ${o:0:300}"
  [ -s "$T/xms$F/index-ledger.v65.jsonl" ] && [ ! -e "$T/xms$F/index-ledger.default.jsonl" ] && ok "ⓔ$F ft-index-move(완성): 원장 트랙 = v65(ft_team_has 가 ${F}꼴 폴더를 v65 카드로 판정)" || bad "ⓔ$F 원장 트랙 ← $(ls "$T/xms$F")"
  [ "$(snap "$R" "$a/v65" "$a/planner")" = "$s0" ] && ok "ⓔ$F ft-index-move(완성): decoy sha 불변" || bad "ⓔ$F ft-index-move 완성 decoy 변함"
  erec ft-index-move "$F" "$rc" "$b/v65/indices/완성/dn.md"
}
for F in 1 2; do p_spawn "$F"; p_close "$F"; p_undo "$F"; p_move "$F"; done
# ── 읽기·판정 도구: 그 꼴 폴더에만 놓은 산출물을 찾아야 한다(다른 꼴에는 decoy) ─────────
p_reads() {
  local F="$1" R="$T/xr$F" b a o rc W; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  mkdir -p "$R/$b/harness/indices/진행" "$R/$b/cfo/indices/진행"
  # ft-nano-slots — v65 칸의 indices/대기 카드를 FT_INDEX_DIR 없이 찾는다(카드는 그 꼴 폴더에만)
  rm -f "$R/$a/v65/indices/대기/slug.md"; mkdir -p "$T/xsl$F" "$T/xslt$F"; cp "$SRC/ft-nano-slots.sh" "$SRC/ft-team-lib.sh" "$T/xsl$F/"
  exe "$T/xsl$F/ft-seat-status.sh" 'echo "IDLE 2020-01-01T00:00:00Z"'; exe "$T/xsl$F/tmux" 'exit 0'; echo '{}' > "$T/xslt$F/seats.json"
  printf '# 인덱스: slot-c\nIssue: #7\n상태: 대기\n선행: 없음\n시험 입력: 없음\n기준값: 없음 → 대체 축 x\n## 구현 범위\nx\n' > "$R/$b/v65/indices/대기/slot-c.md"
  o="$(cd "$R" && PATH="$T/xsl$F:$PATH" FT_SEATS_JSON="$T/xslt$F/seats.json" timeout 20 bash "$T/xsl$F/ft-nano-slots.sh" 2>/dev/null)"; rc=$?
  has "$o" "slot-c" "ⓔ$F ft-nano-slots: ${F}꼴 v65 indices/대기 의 카드를 찾는다"; erec ft-nano-slots "$F" "$rc" "$b/v65/indices/대기/slot-c.md"
  # ft-orphan-cards — c-level-planning 워크트리의 cfo 팀 폴더(그 워크트리의 TEAMS.md · 그 꼴) 진행 카드
  mkdir -p "$R/.worktrees/c-level-planning/design" "$R/.worktrees/c-level-planning/$b/cfo/indices/진행"; cp "$R/design/TEAMS.md" "$R/.worktrees/c-level-planning/design/TEAMS.md"
  printf '# 인덱스: orphan-cfo\n' > "$R/.worktrees/c-level-planning/$b/cfo/indices/진행/orphan-cfo.md"
  mkdir -p "$T/xob$F"; cp "$SRC/ft-orphan-cards.sh" "$SRC/ft-team-lib.sh" "$T/xob$F/"; exe "$T/xob$F/tmux" 'echo "no server running on /tmp/x" >&2; exit 1'
  o="$(cd "$R" && PATH="$T/xob$F:$PATH" FT_SEATS_JSON="$T/xslt$F/seats.json" timeout 20 bash "$T/xob$F/ft-orphan-cards.sh" 2>&1)"; rc=$?
  has "$o" "orphan-cfo" "ⓔ$F ft-orphan-cards: cfo 팀 폴더(${F}꼴) 진행 카드를 센다"; erec ft-orphan-cards "$F" "$rc" "$b/cfo/indices/진행/orphan-cfo.md"
  # ft-index-move-install(설치 게이트) — 하네스 카드(설치: 있음) + --landed 없음 → REJECT · 다른 팀 카드는 범위 밖 통과
  printf '# 인덱스: c\n- 설치: 있음\n## 상태\n- x\n' > "$R/$b/harness/indices/진행/h.md"; printf '# 인덱스: c\n## 상태\n- x\n' > "$R/$b/cfo/indices/진행/c.md"
  o="$(timeout 20 bash "$SRC/ft-index-move-install.sh" "$R/$b/harness/indices/진행/h.md" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "$o" "--landed" "ⓔ$F ft-index-move-install: 하네스 카드(${F}꼴 폴더) 설치: 있음 → REJECT" || bad "ⓔ$F ft-index-move-install rc=$rc ← ${o:0:200}"
  timeout 20 bash "$SRC/ft-index-move-install.sh" "$R/$b/cfo/indices/진행/c.md" >/dev/null 2>&1 && ok "ⓔ$F ft-index-move-install: 다른 팀 카드 = 범위 밖 통과" || bad "ⓔ$F install cfo"
  erec ft-index-move-install "$F" "$rc" "$b/harness/indices/진행/h.md"
  # kit 전용 ft-index-lint-install(등급 A · §10-2 ② = ⓒ :100~101 과 같은 실호출을 표 행으로) — 하네스 카드(설치: 있음) = 그 꼴 폴더로 판정 → 통과 rc0 · 다른 팀 카드 = 범위 밖 rc0
  o="$(cd "$R" && timeout 20 bash "$KIT/ft-index-lint-install.sh" "$R/$b/harness/indices/진행/h.md" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && ok "ⓔ$F ft-index-lint-install(키트): 하네스 카드(${F}꼴 폴더 · 설치: 있음) 통과 rc0" || bad "ⓔ$F ft-index-lint-install rc=$rc ← ${o:0:200}"
  printf '# 인덱스: c\n## 상태\n- x\n' > "$R/$b/harness/indices/진행/n.md"; o="$(cd "$R" && timeout 20 bash "$KIT/ft-index-lint-install.sh" "$R/$b/harness/indices/진행/n.md" 2>&1)"; rc2=$?
  [ "$rc2" = 1 ] && has "$o" "설치:" "ⓔ$F ft-index-lint-install(키트): 하네스 카드(${F}꼴) 설치 줄 없음 → REJECT rc1(다른 꼴로 풀리면 «범위 밖 통과» 가 됐을 것)" || bad "ⓔ$F ft-index-lint-install n.md rc=$rc2 ← ${o:0:200}"
  erec ft-index-lint-install "$F" "$rc" "$b/harness/indices/진행/h.md"
  # ft-proposal-gate — 판정 원장 폴더 = v6 워크트리의 planner 칸(꼴)에서 «그 순간» 푼다
  W="$R/.worktrees/v6-realtime-live"; mkdir -p "$W/design" "$W/$b/planner"; cp "$R/design/TEAMS.md" "$W/design/TEAMS.md"
  printf '816 오빠 인터뷰(A안 · Issue https://github.com/o/r/issues/12): 채택\n' > "$W/$b/planner/VERDICTS-planner-1-20261018.md"
  mkdir -p "$T/xgh$F"; python3 "$HERE/_proposal_issue_fixture.py" "$T/xgh$F" 12 b; printf '#!/usr/bin/env bash\ncase "$1 $2" in\n  "issue view") cat "$FAKE/view-$3.json";;\n  "api --paginate") n="${4#repos/*/issues/}"; cat "$FAKE/timeline-${n%%/timeline}.json";;\n  *) exit 1;;\nesac\n' > "$T/xgh$F/gh"; chmod +x "$T/xgh$F/gh"
  o="$(cd "$R" && env -u FT_PLANNER_VERDICTS_DIR FAKE="$T/xgh$F" FT_GH_READ="bash $T/xgh$F/gh" GH_REPO="o/r" FT_GATE_GH_TIMEOUT=2 BYZ_ROOT="$R" timeout 30 bash "$SRC/ft-proposal-gate.sh" --issue 12 2>&1)"; rc=$?
  has "$o" "OK #12 승인 ⓑ 판정 816" "ⓔ$F ft-proposal-gate: v6 워크트리 planner 칸(${F}꼴)의 판정 816 을 읽는다"; erec ft-proposal-gate "$F" "$rc" "$b/planner/VERDICTS-planner-1-20261018.md"
  # ft-index-gate — close(--da 없음) REJECT 문장이 «풀린 카드 경로» 를 찍는다
  printf '# 인덱스: gx\n' > "$R/$b/v65/indices/진행/gx.md"; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m gx; mkdir -p "$T/xgs$F"
  g() { (cd "$R" && FT_TRACK=v65 FT_INDEX_STATE_DIR="$T/xgs$F" timeout 20 bash "$SRC/ft-index-gate.sh" "$@" 2>&1); }
  g open gx s#1 목적 >/dev/null; g confirm gx 근거 >/dev/null; o="$(g close gx)"; rc=$?
  has "$o" "카드 $R/$b/v65/indices/진행/gx.md 가 있다" "ⓔ$F ft-index-gate: 카드 후보 = ${F}꼴 v65 폴더(ft_team_cands)"; erec ft-index-gate "$F" "$rc" "$b/v65/indices/진행/gx.md"
  # kit 전용 ft-index-lint(등급 A · §10-4 · `:171` 류 exit 0 대역 0) — 기본 골 원장 = 그 꼴 v65 폴더의 GOAL-LEDGER(decoy 원장은 닫는 증거가 없어 다른 꼴로 풀리면 REJECT 가 난다) · 실제 린트 OK rc0 + 출력 ledger= 가 그 꼴
  printf 'G1\nG2\nG3\n' > "$T/goal3"
  printf '## 닫는 증거\n- M1 / 닫는 증거: 시험 카드 닫는 증거 문장 스무 자 이상 복붙용\n' > "$R/$b/v65/GOAL-LEDGER-v65.md"; printf '## decoy\n- 없음\n' > "$R/$a/v65/GOAL-LEDGER-v65.md"
  printf '# 인덱스: lint\n- 제안서: 없음 — 시험 카드\n## 골 원문 (항상 이 3줄)\nG1\nG2\nG3\n## 골좌표\nM1 / 닫는 증거: 「시험 카드 닫는 증거 문장 스무 자 이상 복붙용」\n## 배경\nx\n## 구현 범위\n- x\n## 완료 조건\n- x\n## 상태\n- x\n' > "$R/$b/v65/indices/진행/lint.md"
  o="$(cd "$R" && FT_GOAL_LINES_FILE="$T/goal3" FT_TEAMS_REF=HEAD timeout 30 bash "$KIT/ft-index-lint.sh" "$b/v65/indices/진행/lint.md" 2>&1)"; rc=$?   # R406: 명단 = ref(HEAD 커밋) · 두 꼴 다 실재(decoy) = 고르지 않고 REJECT
  [ "$rc" = 1 ] && has "$o" "실재 후보 2개" "ⓔ$F ft-index-lint: 두 꼴에 원장(decoy 포함) = 추측 0 REJECT(R406)" || bad "ⓔ$F ft-index-lint decoy rc=$rc ← ${o:0:300}"
  rm -f "$R/$a/v65/GOAL-LEDGER-v65.md"
  o="$(cd "$R" && FT_GOAL_LINES_FILE="$T/goal3" FT_TEAMS_REF=HEAD timeout 30 bash "$KIT/ft-index-lint.sh" "$b/v65/indices/진행/lint.md" 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "OK $b/v65/indices/진행/lint.md (ledger=$b/v65/GOAL-LEDGER-v65.md)" "ⓔ$F ft-index-lint(키트 · 실제 린트): OK rc0 · 기본 골 원장 = ${F}꼴 v65 폴더(ft_team_file_ref)" || bad "ⓔ$F ft-index-lint rc=$rc ← ${o:0:300}"
  erec ft-index-lint "$F" "$rc" "$b/v65/GOAL-LEDGER-v65.md"
  # kit 전용 ft-wall-read / ft-wall-check(등급 C · §10-4) — bash -n(ⓐ) + 팀 폴더 해석 호출 1회: 벽 문서 = ${꼴} v65 폴더(문구는 그 꼴 벽에만) · 사유 = 라이브 tmux·슬랙 의존(본 동작은 실좌석에서만)
  mkdir -p "$R/$a/v65"; echo "decoy-phrase" > "$R/$a/v65/DIRECTIVE-v65-wall.md"; echo "wall-phrase-$F" > "$R/$b/v65/DIRECTIVE-v65-wall.md"; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m wall
  o="$(cd "$R" && timeout 20 bash "$KIT/ft-wall-read.sh" seat1 "wall-phrase-$F" 2>&1)"; rc=$?
  has "$o" "WALL-READ seat=seat1" "ⓔ$F ft-wall-read(키트): 인용 문구를 ${F}꼴 벽에서 찾는다"; erec ft-wall-read "$F" "$rc" "$b/v65/DIRECTIVE-v65-wall.md"
  enote ft-wall-read "C: bash -n + 팀 폴더 해석 1회(벽 = 그 꼴 v65) · 사유 = 라이브 tmux·슬랙 의존"
  o="$(cd "$R" && timeout 20 bash "$KIT/ft-wall-check.sh" seat1 2>&1)"; rc=$?
  has "$o" "WALL-OK seat=seat1" "ⓔ$F ft-wall-check(키트): 읽음 원장 대조 OK"; erec ft-wall-check "$F" "$rc" "$b/v65/DIRECTIVE-v65-wall.md"
  enote ft-wall-check "C: bash -n + 팀 폴더 해석 1회(벽 = 그 꼴 v65) · 사유 = 라이브 tmux·슬랙 의존"
  # kit 전용 ft-pm-tick(등급 C) — xtrace 로 RULES_FILE 가 ${꼴} v65 폴더로 풀리는 것을 본다(루프는 «target session gone» 으로 바로 끝난다)
  o="$(cd "$R" && FT_PM_TICK_PIDFILE="$T/xpm$F.pid" FT_PM_TICK_STAMP="$T/xpm$F.last" PATH="$T/xob$F:$PATH" timeout 20 bash -x "$KIT/ft-pm-tick.sh" 2>&1)"; rc=$?
  has "$o" "RULES_FILE=$b/v65/20260826/RULES-ammo-and-distill-20260826.md" "ⓔ$F ft-pm-tick(키트): RULES_FILE = ${F}꼴 v65 폴더(ft_team_rel)"; erec ft-pm-tick "$F" "$rc" "$b/v65/20260826/RULES-ammo-and-distill-20260826.md"
  enote ft-pm-tick "C: bash -n + 팀 폴더 해석 1회(RULES_FILE = 그 꼴 v65 · xtrace) · 사유 = 라이브 tmux·슬랙 의존(틱 루프는 target session gone 으로 종료)"
}
for F in 1 2; do p_reads "$F"; done
# ── 자율 3종(ft-autonomy-start · ft-autonomy · ft-proxy-decide): planner 폴더 = ${꼴} · decoy 불변 ──────
p_auto() {
  local F="$1" R="$T/xa$F" b a o rc s0 A D st PD; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"; PD="$R/$b/planner"; st="$T/xas$F"; mkdir -p "$st" "$T/xag$F"
  printf '%s\n' '- **100** (오빠) foo 착수 승인' > "$PD/VERDICTS-planner-1-20261018.md"; printf '%s\n' '- **100** [대리 · 자율 ON A1] decoy' '- **101** [대리 · 자율 ON A1] decoy' '- **102** [대리 · 자율 ON A1] decoy' > "$R/$a/planner/VERDICTS-planner-1-20261018.md"
  exe "$T/xag$F/gcloud" 'exit 1'; s0="$(snap "$R" "$a/planner" "$a/v65")"
  A() { (cd "$R" && env -u FT_PLANNER_DIR PATH="$T/xag$F:$PATH" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$st" timeout 60 bash "$SRC/ft-autonomy.sh" "$@" 2>&1); }
  D() { (cd "$R" && env -u FT_PLANNER_DIR PATH="$T/xag$F:$PATH" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$st" timeout 60 bash "$SRC/ft-proxy-decide.sh" "$@" 2>&1); }
  o="$(A on)"; rc=$?; [ -f "$PD/AUTONOMY-START-A1.md" ] && ok "ⓔ$F ft-autonomy-start(on 이 부름): 시작 장부 = ${F}꼴 planner 폴더에 씀" || bad "ⓔ$F 시작 장부 위치 ← ${o:0:200}"
  erec ft-autonomy-start "$F" "$rc" "$b/planner/AUTONOMY-START-A1.md"
  o="$(D --kind press-order --q "순서?" --choice "A 다음 B" --why w --undo u)"; rc=$?
  [ "$rc" = 0 ] && grep -qF '[대리 · 자율 ON A1] 순서?' "$PD/VERDICTS-planner-1-20261018.md" && ok "ⓔ$F ft-proxy-decide: 대리 줄 = ${F}꼴 planner 원장(번호 101)에 append" || bad "ⓔ$F proxy-decide rc=$rc ← ${o:0:300}"
  erec ft-proxy-decide "$F" "$rc" "$b/planner/VERDICTS-planner-1-20261018.md"
  D --kind reversible-choice --q "q2" --choice c --why w --undo u >/dev/null; [ -f "$PD/AUTONOMY-QUEUE.md" ] && ok "ⓔ$F ft-proxy-decide: 큐 파일 = ${F}꼴 planner 폴더" || bad "ⓔ$F 큐 파일 위치"
  o="$(A status)"; has "$o" "대리 1 · 큐 1" "ⓔ$F ft-autonomy status: 대리·큐 수를 ${F}꼴 planner 폴더에서 센다(decoy 의 대리 3줄은 안 센다)"
  o="$(A off)"; rc=$?; has "$o" "큐 파일 $PD/AUTONOMY-QUEUE.md" "ⓔ$F ft-autonomy off: 큐 파일 경로 = ${F}꼴 planner 폴더"; erec ft-autonomy "$F" "$rc" "$b/planner/AUTONOMY-QUEUE.md"
  [ "$(snap "$R" "$a/planner" "$a/v65")" = "$s0" ] && ok "ⓔ$F 자율 3종: decoy(다른 꼴 폴더) sha 불변" || bad "ⓔ$F 자율 3종 decoy 변함"
}
for F in 1 2; do p_auto "$F"; done
# ── 글자만 바꾼 2종(경로를 풀지 않는다 — 실행해 «글자 하드코딩 경로가 출력에 없고 rc 가 두 꼴에서 같음» 을 본다) ──
p_text() {
  local F="$1" R="$T/xt$F" b o rc; b="$(bf "$F")"; efix "$R" "$F"; mkdir -p "$R/scripts/harness-install/fable-team/bin" "$T/xtb$F" "$T/xtg$F"
  echo '#!/usr/bin/env bash' > "$R/scripts/harness-install/fable-team/bin/x.sh"; GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m kit
  o="$(cd "$R" && timeout 20 bash "$SRC/ft-live-bin-drift-check.sh" --bin "$T/xtb$F" --repo "$R" --ref HEAD 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "$o" "DRIFT" "ⓔ$F ft-live-bin-drift-check: 빈 bin 이면 DRIFT rc1" || bad "ⓔ$F drift rc=$rc ← ${o:0:200}"
  hasnt "$o" "design/harness/" "ⓔ$F ft-live-bin-drift-check: HINT 에 글자 경로(design/harness/) 없음"; has "$o" "하네스 팀 폴더의 PLAN-release" "  └ HINT = 팀 폴더 서술형"; erec ft-live-bin-drift-check "$F" "$rc" -
  echo "r$F=rc$rc 문구 «DRIFT … 하네스 팀 폴더의 PLAN-release»" >> "$T/eo.ft-live-bin-drift-check"
  printf '#!/usr/bin/env bash\ncase "$1 $2" in "repo view") echo https://example.test/o/r;; esac\n' > "$T/xtg$F/gh"; chmod +x "$T/xtg$F/gh"
  o="$(cd "$R" && PATH="$T/xtg$F:$PATH" timeout 20 bash "$SRC/ft-issue-reopen.sh" 7 HEAD 2>&1)"; rc=$?
  [ "$rc" = 0 ] && has "$o" "DRY-RUN" "ⓔ$F ft-issue-reopen: dry-run rc0" || bad "ⓔ$F issue-reopen rc=$rc ← ${o:0:200}"
  hasnt "$o" "design/harness/" "ⓔ$F ft-issue-reopen: 본문에 글자 경로(design/harness/) 없음"; has "$o" "하네스 팀 폴더의 ISSUE-TRANSITIONS.md" "  └ 본문 = 팀 폴더 서술형"; erec ft-issue-reopen "$F" "$rc" -
  echo "r$F=rc$rc 문구 «DRY-RUN … 하네스 팀 폴더의 ISSUE-TRANSITIONS.md»" >> "$T/eo.ft-issue-reopen"
}
# 등급 B 사유(§10-4) = 두 꼴 실행 결과 원문 + `grep -c 'ft_team\|design/'` 가 0(경로를 풀지 않는다 — 상수 «해당 없음» 금지 · 실측 원문)
for f in ft-live-bin-drift-check ft-issue-reopen; do
  gc="$(grep -c 'ft_team\|design/' "$SRC/$f.sh")"
  [ "$gc" = 0 ] && ok "ⓔ $f: grep -c 'ft_team\\|design/' $f.sh = 0 — 경로 미해석(글자만)" || bad "ⓔ $f: grep -c = $gc (경로를 푼다면 등급 B 가 아니다)"
  enote "$f" "B: $(tr '\n' ' ' < "$T/eo.$f" 2>/dev/null)· grep -c 'ft_team\\|design/' $f.sh = $gc · 해당 없음 — 경로 미해석(grep 0) · rc0 허용"
done
for F in 1 2; do p_text "$F"; done
# ── lib · 린트 · 파이썬 3 ───────────────────────────────────────────────
p_misc() {
  local F="$1" R="$T/xl$F" b a o rc W; b="$(bf "$F")"; a="$(af "$F")"; efix "$R" "$F"
  o="$(cd "$R" && FT_REPO_ROOT="$R" bash -c '. "$1"; ft_team_root v65' _ "$SRC/ft-team-lib.sh" 2>/dev/null)"; rc=$?   # r447: 쌍둥이 공존이면 stderr WARN 1줄 — 값은 stdout 만
  [ "$o" = "$R/$b/v65" ] && ok "ⓔ$F ft-team-lib: ft_team_root v65 = $R/$b/v65" || bad "ⓔ$F lib root: $o"; erec ft-team-lib "$F" "$rc" "$b/v65"
  mkdir -p "$T/xld$F" "$T/xlc$F"; echo 'x="design/v65/indices"' > "$T/xld$F/a.sh"; echo 'echo hi' > "$T/xlc$F/a.sh"
  o="$(cd "$R" && FT_REPO_ROOT="$R" FT_TEAM_LITERAL_PENDING= timeout 30 bash "$SRC/ft-team-path-lint.sh" "$T/xld$F" 2>&1)"; rc=$?
  [ "$rc" = 1 ] && has "$o" "ERR" "ⓔ$F ft-team-path-lint: 글자 팀 경로(design/v65/) 심은 폴더 = ERR rc1(팀 이름은 ${F}꼴 TEAMS.md 에서 동적)" || bad "ⓔ$F lint 변이 rc=$rc ← ${o:0:200}"
  o="$(cd "$R" && FT_REPO_ROOT="$R" timeout 30 bash "$SRC/ft-team-path-lint.sh" "$T/xlc$F" 2>&1)" && ok "ⓔ$F ft-team-path-lint: 깨끗한 폴더 = OK rc0" || bad "ⓔ$F lint 정상 ← ${o:0:200}"
  erec ft-team-path-lint "$F" "$rc" -
  # 파이썬 3 — 그 꼴 폴더에만 판정 원장·원장 파일을 둔 워크트리(.worktrees/wt) · decoy(다른 꼴 planner)는 워크트리에서 지운다
  W="$R/.worktrees/wt"; GITC "$R" worktree add -q "$W" -b nano/wt 2>/dev/null; rm -rf "$W/$a/planner"; mkdir -p "$W/$b/planner"
  printf '| 번호 | 시각 | 내용 |\n|---|---|---|\n| 77 | 10:00 | (오빠) 결정 시험 |\n' > "$W/$b/planner/VERDICTS-planner-1-20261018.md"; printf '# 원장\n' > "$R/$b/planner/PLAN-oppa-ledger.md"
  printf '{"_cards_wt": "wt"}\n' > "$R/.fable-team/seats-planner.json"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from datetime import datetime
from pathlib import Path
import ft_news_io as io
print(io.read_ledger(Path(sys.argv[1]), datetime(2026, 10, 18, 10, 0)))' "$R" 2>&1)"; rc=$?
  has "$o" "(오빠) 결정 시험" "ⓔ$F ft_news_io.read_ledger: ${F}꼴 planner 판정 원장(워크트리 명단)을 읽는다"; erec ft_news_io "$F" "$rc" "$b/planner/VERDICTS-planner-1-20261018.md"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
import ft_news_ledger_notify as nt
print(nt.verdict_rows(Path(sys.argv[1]), "wt"))' "$R" 2>&1)"; rc=$?
  has "$o" "('77', '(오빠) 결정 시험')" "ⓔ$F ft_news_ledger_notify.verdict_rows: ${F}꼴 판정 행"; erec ft_news_ledger_notify "$F" "$rc" "$b/planner/VERDICTS-planner-1-20261018.md"
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c '
import sys; sys.path.insert(0, ".")
from pathlib import Path
import ft_news_ledger as nl
print(nl.planner_ledger_rel(Path(sys.argv[1])))' "$R" 2>&1)"; rc=$?
  [ "$o" = "$b/planner/PLAN-oppa-ledger.md" ] && ok "ⓔ$F ft_news_ledger.planner_ledger_rel = $b/planner/PLAN-oppa-ledger.md" || bad "ⓔ$F ledger_rel: $o"; erec ft_news_ledger "$F" "$rc" "$o"
}
for F in 1 2; do p_misc "$F"; done
# ── fail-closed 열: 같은 픽스처에서 TEAMS.md 만 지우고 «같은 호출» 을 다시 — 옛 경로로 후퇴하지 않고 «팀 명단 없음» 류 오류를 낸다 ─────
echo "== ⓔ fail-closed — 명단을 지운 같은 픽스처에서 같은 호출(옛 경로 후퇴 0)"
dropteams() { rm -f "$1/design/TEAMS.md"; for w in "$1"/.worktrees/*/; do rm -f "${w}design/TEAMS.md"; done; }
fcrec() {  # <도구> <rc> <출력> <기대 문구> [nz|z0 <사유>] — 행렬 기대값으로 판정(`any` 없음): nz(기본) = rc≠0 + 문구 · z0 = 행렬이 rc0 를 허용한 행(사유 문자열 필수 · 문구는 그대로 단언)
  local mode="${5:-nz}" why="${6:-}"
  case "$mode" in
    nz) [ "$2" != 0 ] && has "$3" "$4" "ⓔ fail-closed $1: rc=$2 · «$4»" || bad "ⓔ fail-closed $1 rc=$2 (행렬 기대 rc≠0) ← ${3:0:300}"; echo "rc=$2 «$4»" > "$T/ef.$1";;
    z0) [ -n "$why" ] && [ "$2" = 0 ] && has "$3" "$4" "ⓔ fail-closed $1: rc=0 허용 · «$4» · 사유 = $why" || bad "ⓔ fail-closed $1 rc=$2 (rc0 허용 행인데 rc≠0 이거나 사유 없음) ← ${3:0:300}"; echo "rc=$2 «$4» · rc0 허용 사유 = $why" > "$T/ef.$1";;
    *) bad "ⓔ fail-closed $1: 모드 $mode 는 없다(any 금지)";;
  esac
}
for d in xs1 xc1 xu1 xm1 xr1 xa1 xl1; do dropteams "$T/$d"; done
R="$T/xs1"; o="$(cd "$R" && PATH="$T/xsh1:$PATH" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_TEAMSET=0 timeout 20 bash "$T/xhb1/ft-nano-spawn.sh" "$R/design/v65/indices/대기/slug.md" --from me#1 2>&1)"; fcrec ft-nano-spawn $? "$o" "design/TEAMS.md)을 못 읽음"   # R406: 명단 = ref(origin/main) — 픽스처엔 ref 가 없다
R="$T/xc1"; o="$(cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$T/xcsr1" HIL_DIR="$T/xch1" HIL_CLIP=0 PATH="$T/xcf1:$PATH" FAKE_PANES="$T/xcp1" FAKE_CWD="$T/xcd1" FAKE_PANE_CWDS="$T/xcw1" FAKE_LOG="$T/xcl1" FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$R/.fable-team/seats-planner.json" FT_INBOX_ROOT="$T/xcm1" FT_NANO_IDLE_MIN=0 timeout 60 bash "$T/xcb1/ft-nano-close.sh" "$SEAT_C" --result "$T/xcr1.md" --recv 1 --wt "$R/.worktrees/v65-ovr" --branch nano/ovr 2>&1)"; fcrec ft-nano-close $? "$o" "팀 명단 없음"
R="$T/xu1"; o="$(cd "$R" && PATH="$T/xuf1:$PATH" HOME="$T/xuh1" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_UNDO_STATE="$T/xus1" FT_MBOX_DIR="$R/.fable-team/comm" timeout 30 bash "$SRC/ft-nano-spawn-undo.sh" "$SEAT_N" --card "$R/design/v65/indices/대기/u.md" 2>&1)"; fcrec ft-nano-spawn-undo $? "$o" "팀 명단 없음"
R="$T/xm1"; printf '# 인덱스: dn2\n- 정본 영향 없음: 시험용 카드라서 정본 갱신 대상이 없다\n- 규칙: 없음 — 시험용 카드라서 규칙 줄 대상이 아니다\n## 상태\n- 세트: x\n' > "$R/design/v65/indices/진행/dn2.md"; printf '## §1 dn2\n닫힘 dn2\n' > "$T/xmda2.md"
o="$(cd "$R" && FT_INDEX_STATE_DIR="$T/xms1" timeout 30 bash "$SRC/ft-index-move.sh" "$R/design/v65/indices/진행/dn2.md" 완성 --da "$T/xmda2.md#§1" --seat s#1 2>&1)"; fcrec ft-index-move $? "$o" "팀 명단 없음"
R="$T/xr1"; o="$(cd "$R" && PATH="$T/xsl1:$PATH" FT_SEATS_JSON="$T/xslt1/seats.json" timeout 20 bash "$T/xsl1/ft-nano-slots.sh" 2>&1)"; fcrec ft-nano-slots $? "$o" "팀 명단 없음"
o="$(cd "$R" && PATH="$T/xob1:$PATH" FT_SEATS_JSON="$T/xslt1/seats.json" timeout 20 bash "$T/xob1/ft-orphan-cards.sh" 2>&1)"; rc=$?
fcrec ft-orphan-cards "$rc" "$o" "팀 명단 없음" z0 "모니터 — cfo 폴더를 못 풀면 ERROR 를 찍고 그 팀만 빼고 스캔을 계속한다(ft-orphan-cards.sh :13 설계) · 제품 코드 0 범위라 r5 에서 rc≠0 로 못 올림"
enote ft-orphan-cards "A→B 하향: fail-closed rc=$rc(행렬 기대 rc≠0 미달 · 문구는 있음 · 사유는 fail-closed 칸) · 제품 코드 0 · 후속 카드 후보"
o="$(timeout 20 bash "$SRC/ft-index-move-install.sh" "$R/design/harness/indices/진행/h.md" 2>&1)"; fcrec ft-index-move-install $? "$o" "하네스 팀 폴더를 못 풀었다"
o="$(cd "$R" && timeout 20 bash "$KIT/ft-index-lint-install.sh" "$R/design/harness/indices/진행/h.md" 2>&1)"; fcrec ft-index-lint-install $? "$o" "하네스 팀 폴더를 못 풀었다"
o="$(cd "$R" && FT_GOAL_LINES_FILE="$T/goal3" timeout 30 bash "$KIT/ft-index-lint.sh" design/v65/indices/진행/lint.md 2>&1)"; fcrec ft-index-lint $? "$o" "design/TEAMS.md)을 못 읽음"   # R406: 명단 = ref(origin/main)
o="$(cd "$R" && env -u FT_PLANNER_VERDICTS_DIR FAKE="$T/xgh1" FT_GH_READ="bash $T/xgh1/gh" GH_REPO="o/r" FT_GATE_GH_TIMEOUT=2 BYZ_ROOT="$R" timeout 30 bash "$SRC/ft-proposal-gate.sh" --issue 12 2>&1)"; fcrec ft-proposal-gate $? "$o" "판정 원장 폴더를 못 풀었다"
mkdir -p "$T/xgs_fc"; g() { (cd "$R" && FT_TRACK=v65 FT_INDEX_STATE_DIR="$T/xgs_fc" timeout 20 bash "$SRC/ft-index-gate.sh" "$@" 2>&1); }; g open gx s#1 x >/dev/null; g confirm gx r >/dev/null; o="$(g close gx)"; rc=$?
fcrec ft-index-gate "$rc" "$o" "후보를 못 풀었다" z0 "close 는 카드 탐색을 건너뛰고(ft-index-gate.sh :135 ERROR 뒤 계속) 상태 기록만 닫는다 · 제품 코드 0 범위라 r5 에서 rc≠0 로 못 올림"
enote ft-index-gate "A→B 하향: fail-closed rc=$rc(행렬 기대 rc≠0 미달 · 문구는 있음 · 사유는 fail-closed 칸) · 제품 코드 0 · 후속 카드 후보"
o="$(cd "$R" && timeout 20 bash "$KIT/ft-wall-read.sh" seat1 "wall-phrase-1" 2>&1)"; fcrec ft-wall-read $? "$o" "팀 명단 없음"
o="$(cd "$R" && timeout 20 bash "$KIT/ft-wall-check.sh" seat1 2>&1)"; fcrec ft-wall-check $? "$o" "팀 명단 없음"
o="$(cd "$R" && FT_PM_TICK_PIDFILE="$T/xpm9.pid" FT_PM_TICK_STAMP="$T/xpm9.last" PATH="$T/xob1:$PATH" timeout 20 bash "$KIT/ft-pm-tick.sh" 2>&1)"; fcrec ft-pm-tick $? "$o" "팀 명단 없음"
R="$T/xa1"; o="$(cd "$R" && env -u FT_PLANNER_DIR FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$T/xas1" timeout 30 bash "$SRC/ft-autonomy-start.sh" ledger A5 2>&1)"; fcrec ft-autonomy-start $? "$o" "팀 명단 없음"
o="$(cd "$R" && env -u FT_PLANNER_DIR FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$T/xas1" timeout 30 bash "$SRC/ft-proxy-decide.sh" --kind press-order --q q --choice c --why w --undo u 2>&1)"; fcrec ft-proxy-decide $? "$o" "팀 명단 없음"
printf '1\ton\tA7\n' > "$T/xas1/autonomy.log"; printf '{"event": "A7", "mode": "on"}\n' > "$T/xas1/autonomy.json"
o="$(cd "$R" && env -u FT_PLANNER_DIR FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$T/xas1" timeout 30 bash "$SRC/ft-autonomy.sh" off 2>&1)"; fcrec ft-autonomy $? "$o" "팀 명단 없음" z0 "off 는 명단을 안 읽는 분기(상태 파일만 닫는다 · 행렬 §10-1 «rc0 허용 · 명단을 안 읽는 분기»)"
# 행렬 §10-1 autonomy: 명단을 «읽는» 분기(on → ft-autonomy-start ledger) 1건은 rc≠0
o="$(cd "$R" && env -u FT_PLANNER_DIR PATH="$T/xag1:$PATH" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$T/xas1" timeout 60 bash "$SRC/ft-autonomy.sh" on 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$o" "팀 명단 없음" "ⓔ fail-closed ft-autonomy(on · 명단 읽는 분기): rc=$rc · «팀 명단 없음»" || bad "ⓔ fail-closed ft-autonomy on rc=$rc (행렬 기대 rc≠0) ← ${o:0:300}"
echo "$(cat "$T/ef.ft-autonomy") · on(명단 읽는 분기)=rc$rc «팀 명단 없음»" > "$T/ef.ft-autonomy"
R="$T/xl1"; o="$(cd "$R" && FT_REPO_ROOT="$R" bash -c '. "$1"; ft_team_root v65' _ "$SRC/ft-team-lib.sh" 2>&1)"; fcrec ft-team-lib $? "$o" "팀 명단 없음"
o="$(cd "$R" && FT_REPO_ROOT="$R" timeout 30 bash "$SRC/ft-team-path-lint.sh" "$T/xlc1" 2>&1)"; fcrec ft-team-path-lint $? "$o" "TEAMS.md 를 못 읽어" z0 "린트는 명단 없이도 돈다(팀 이름 목록만 못 넓힘 · 도우미 · 표 밖)"
for m in "ft_news_io|import ft_news_io as m; from datetime import datetime; m.read_ledger(Path(sys.argv[1]), datetime(2026,10,18,10,0))" "ft_news_ledger_notify|import ft_news_ledger_notify as m; m.verdict_rows(Path(sys.argv[1]), 'wt')" "ft_news_ledger|import ft_news_ledger as m; m.planner_ledger_rel(Path(sys.argv[1]))"; do
  o="$(cd "$SRC" && env -i HOME="$HOME" PATH="$PATH" python3 -I -c "import sys; sys.path.insert(0, '.'); from pathlib import Path; ${m#*|}" "$R" 2>&1)"; fcrec "${m%%|*}" $? "$o" "팀 명단 없음"
done
# 등급 B 두 행(drift-check · issue-reopen)의 fail-closed = 명단을 지운 같은 호출(xt1) — 경로를 풀지 않으니 rc 는 명단과 무관(행렬: 해당 없음 · rc0 허용 · 사유 = grep 0)
R="$T/xt1"; dropteams "$R"
o="$(cd "$R" && timeout 20 bash "$SRC/ft-live-bin-drift-check.sh" --bin "$T/xtb1" --repo "$R" --ref HEAD 2>&1)"; rc=$?; [ "$rc" = 1 ] && has "$o" "DRIFT" "ⓔ fail-closed ft-live-bin-drift-check: 명단 없어도 같은 DRIFT rc1(경로 미해석)" || bad "ⓔ fail-closed drift rc=$rc ← ${o:0:200}"
echo "rc=$rc «DRIFT» · 해당 없음 — 경로 미해석(grep 0) · 명단 무관" > "$T/ef.ft-live-bin-drift-check"
o="$(cd "$R" && PATH="$T/xtg1:$PATH" timeout 20 bash "$SRC/ft-issue-reopen.sh" 7 HEAD 2>&1)"; fcrec ft-issue-reopen $? "$o" "DRY-RUN" z0 "해당 없음 — 경로 미해석(grep 0) · 명단 무관"

# ── 대조표: 수용행렬 22 × 옛 꼴 · 새 꼴 + 등급(§10-4) — DA·arch 가 줄 수·등급·A 칸 산출물 단언을 센다 ──────────────
echo "== ⓔ 대조표 22줄 = 수용행렬(셸 14 + 파이썬 3 + 키트 5) · 등급 A15/B2/C3 기대 (옛 꼴 design/<팀>/ ↔ 새 꼴 design/teams/<팀>/)"
n22=0; nA=0; nB=0; nC=0
for f in "${CONS_SH[@]}" "${CHANGED_PY[@]}" "${KITONLY_SH[@]}"; do
  r1="$(cat "$T/er.$f.1" 2>/dev/null)"; r2="$(cat "$T/er.$f.2" 2>/dev/null)"; p1="$(cat "$T/ep.$f.1" 2>/dev/null)"; p2="$(cat "$T/ep.$f.2" 2>/dev/null)"; fc="$(cat "$T/ef.$f" 2>/dev/null)"; nt="$(cat "$T/en.$f" 2>/dev/null)"
  g="$(grade "$f")"; case "$nt" in A→B*) g=B;; esac   # 실측이 행렬 기대에 못 미친 칸 = 등급 하향 + 사유(§10-4 착지 규칙)
  [ "$p1" != - ] || { p1="글자 경로 없음"; p2="글자 경로 없음"; }
  echo "표: [$g] $f old=${r1:-?} new=${r2:-?} path=old:${p1:-?} | new:${p2:-?} fail-closed=${fc:-?}${nt:+ 사유=$nt}"
  [ -n "$r1" ] && [ "$r1" = "$r2" ] && [ -n "$fc" ] && ok "ⓔ 표 [$g] $f: rc 가 두 꼴에서 같다(old=$r1 new=$r2) + fail-closed 기록" || bad "ⓔ 표 [$g] $f: 기록 없음(old=$r1 new=$r2 fc=$fc)"
  case "$g" in
    A) nA=$((nA+1)); case "$fc" in *"명단 읽는 분기)=rc0 "*|*"명단 읽는 분기)=rc0") bad "ⓔ 표 [A] $f: 명단 읽는 분기가 rc0";; *"명단 읽는 분기)=rc"*) ok "ⓔ 표 [A] $f: fail-closed = 명단 읽는 분기 rc≠0(안 읽는 분기 rc0 허용 · 사유 있음)";; "rc=0 "*) bad "ⓔ 표 [A] $f: fail-closed 가 rc0 — A 는 rc≠0 이어야 한다";; "rc="*) ok "ⓔ 표 [A] $f: fail-closed rc≠0";; *) bad "ⓔ 표 [A] $f: fail-closed 기록 형식";; esac; [ "$p1" != "글자 경로 없음" ] && ok "ⓔ 표 [A] $f: 두 꼴 산출물 경로 단언 있음" || bad "ⓔ 표 [A] $f: 산출물 경로 없음";;
    B) nB=$((nB+1)); [ -n "$nt" ] && ok "ⓔ 표 [B] $f: 사유·결과 원문 있음" || bad "ⓔ 표 [B] $f: 사유 없음";;
    C) nC=$((nC+1)); case "$nt" in *"라이브 tmux·슬랙 의존"*) ok "ⓔ 표 [C] $f: 해석 1회 + 사유 «라이브 tmux·슬랙 의존»";; *) bad "ⓔ 표 [C] $f: 사유 없음";; esac;;
  esac
  n22=$((n22+1))
done
for f in "${HELPER_SH[@]}"; do echo "도우미: $f old=$(cat "$T/er.$f.1" 2>/dev/null) new=$(cat "$T/er.$f.2" 2>/dev/null) fail-closed=$(cat "$T/ef.$f" 2>/dev/null) — 쌍둥이 시험(ⓑ) + 린트 자가 실행 · 표 밖"; done
[ "$n22" = 22 ] && ok "ⓔ 표 줄 수 = 22(수용행렬 = 셸 14 + 파이썬 3 + 키트 5 · 도우미 2 는 표 밖)" || bad "ⓔ 표 줄 수 $n22"
echo "등급 합계: A=$nA B=$nB C=$nC (행렬 §10-4 열거 = A17 B2 C3 · 실측 미달 칸은 표 줄 사유 «A→B 하향»)"
[ $((nA+nB+nC)) = 22 ] && ok "ⓔ 등급 합계 = 22" || bad "ⓔ 등급 합계 $((nA+nB+nC))"
echo "== fail=$fail"; [ "$fail" = 0 ]
