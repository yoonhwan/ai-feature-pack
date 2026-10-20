#!/usr/bin/env bash
# test_goal_check_ref.sh — r479: 골 읽기 판정기(ft-goal-check.sh)·골 틱(ft-goal-tick.sh)·골 표 원장(ft_goal_table.py)의 명단 = ref origin/main · 폴더 = 그 루트에 실재하는 후보.
# 픽스처 = mktemp 임시 리포 2(①«공유 루트» main 체크아웃에 TEAMS.md 없음 + 로컬 ref origin/main 에 새 꼴 명단·v65 정본 ②«LIVE_ROOT» 워크트리 = 옛 꼴 planner 폴더 · design/teams 0)
# 가짜 tmux(export -f · 틱이 PATH 앞에 homebrew 를 붙여도 함수가 먼저) · 가짜 mbox · 외부 호출 0 · GIT_* env 0 · 실 큐·루트 .fable-team 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
g() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
HEADROW='| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n'
PHRASE="닫는증거-느린-leaf-barrier-중-다음-kept-STT-착수-관측"
ledger() { printf '# 골 원장 %s\n\n| 단위 | 닫는 증거 | 상태 |\n|---|---|---|\n| **M0** 원문 | %s | 진행 |\n| **M1** 교정 | 다른 증거 | CLOSE |\n' "$1" "$PHRASE"; }
v65_tree() {  # <폴더> <표지> — 정본 4 + 틱 프롬프트
  mkdir -p "$1/20260909" "$1/20260910" "$1/20260911" "$1/20260912"; ledger "$2" > "$1/GOAL-LEDGER-v65.md"
  for f in 20260909/GOAL-archastra-lst-on-off-completion.md 20260910/LIST-v65-lst-completion-MERGED.md 20260911/PLAN-v65-sm65-experiment-completion-handoff.md; do echo "src $2" > "$1/$f"; done
  printf '프롬프트\n```\n<세션명> 틱 본문 %s\n```\n' "$2" > "$1/20260912/TICK-PROMPT-v65-unified.md"; }
CANON_TXT='# 자율 골 A6

## 골 → 팀 → 닫는 증거

| 골(원문) | 담당 팀 | 닫는 증거 |
|---|---|---|
| v65 마이크 넘기기 완성 | v65 | 착지 sha |
| m.room 멀티 사용자 | room | 착지 sha |
| m.lecture 멀티 사용자 | lecture | 착지 sha |
| 하네스팀 랜딩부터 | harness | 설치 cmp0 |
| 전팀 지침과 프로젝트 폴더 기준 재기동 | harness | ERROR 0 |
| 메모리 세션 제한으로 안 멈춰 있게 완성 | harness | 멈춘 팀 0 |'
planner_tree() {  # <폴더>
  mkdir -p "$1"; printf '%s\n' "$CANON_TXT" > "$1/AUTONOMY-GOAL-A6-20261018.md"
  { printf '# 원장\n\n> 마지막 갱신: %s · t\n\n## 메인 골 6줄 — 지금 상태\n\n| 골 | 지금 상태 | 남은 것 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
    for i in 1 2 3 4 5 6; do printf '| 골 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done; } > "$1/PLAN-oppa-ledger.md"; }

# ── 픽스처: S = origin/main 판(새 꼴 명단 + design/teams/v65 · planner) · R = 공유 루트(main = TEAMS.md 없음) · LR = R 의 워크트리(옛 꼴)
S="$T/src"; R="$T/root"; mkdir -p "$S/design" "$R"; g "$S" init -q -b main; g "$R" init -q -b main
printf "$HEADROW"'| harness | `$FT_HARNESS_ROOT/design/harness/` | x | 현역 |\n| planner | `design/teams/planner/` | x | 현역 |\n| v65 | `design/teams/v65/` | x | 현역 |\n' > "$S/design/TEAMS.md"
v65_tree "$S/design/teams/v65" REF; planner_tree "$S/design/teams/planner"; g "$S" add -A; g "$S" commit -qm ref
echo root > "$R/README"; g "$R" add -A; g "$R" commit -qm base; g "$R" fetch -q "$S" main:refs/remotes/origin/main
REFSHA="$(g "$R" log -1 --format=%h refs/remotes/origin/main -- design/teams/v65/GOAL-LEDGER-v65.md)"
export TMPDIR="$T/tmpd"; mkdir -p "$TMPDIR"
check() { OUT="$(cd "${CWD:-$R}" && env -u FT_ROOT bash "$BIN/ft-goal-check.sh" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }

# r485-⓪ 상태 자리(공용 루트 .fable-team/) 못 풂 → ERROR exit 4(조용히 cwd 에 쓰기 0) · 그 뒤 픽스처에 .fable-team/ 를 둔다(실 공용 루트 꼴)
check seat-a; [ "$RC" = 4 ] && printf '%s' "$OUT" | grep -q '^ERROR seat=seat-a 공용 루트를 못 풂' && [ ! -e "$R/.fable-team" ] && ok "r485-⓪ .fable-team 없는 리포 → ERROR 공용 루트 exit 4 · 쓰기 0" || bad "r485-⓪ rc=$RC :: $OUT :: $ERR"
mkdir -p "$R/.fable-team"

# ⓐ 공유 루트 cwd · 체크아웃에 v65 폴더 0 · 명단 파일 0 → ref 명단 + ref 본문으로 판정(못 풀었다 0 · exit 4 는 cited 에만)
check seat-a; [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q "^REREAD-REQUIRED seat=seat-a (좌석 원장 부재" && printf '%s' "$OUT" | grep -q "골원장 sha=$REFSHA" && ok "ⓐ1 폴더 0 → ref 본문·ref sha 로 REREAD-REQUIRED rc3" || bad "ⓐ1 rc=$RC :: $OUT :: $ERR"
printf '%s%s' "$OUT" "$ERR" | grep -q '못 풀었다\|팀 명단 없음' && bad "ⓐ1 옛 REJECT 문구" || ok "ⓐ1 «못 풀었다·팀 명단 없음» 0"
check seat-a --touch "$PHRASE"; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "^GOAL-READ seat=seat-a ledger=$REFSHA" && printf '%s' "$OUT" | grep -q '^NEXT M0 / 닫는 증거: '"$PHRASE" && ok "ⓐ2 --touch(ref 본문 원장 문구) → GOAL-READ·GOAL-OK·NEXT rc0" || bad "ⓐ2 rc=$RC :: $OUT :: $ERR"
check seat-a; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-OK seat=seat-a' && ok "ⓐ3 재실행 GOAL-OK rc0" || bad "ⓐ3 rc=$RC :: $OUT"
check seat-a --touch "원장에-없는-문구-스무자-이상-길게-적는다"; [ "$RC" = 4 ] && printf '%s' "$OUT" | grep -q '^REJECT seat=seat-a cited 문구가 골 원장에 없다' && ok "ⓐ4 cited 없음 → REJECT exit 4(유일한 REJECT 4)" || bad "ⓐ4 rc=$RC :: $OUT"
[ "$(ls "$TMPDIR" | grep -c ft-team-doc)" = 0 ] && ok "ⓐ5 ref 본문 임시 파일 정리(trap)" || bad "ⓐ5 임시 파일 남음: $(ls "$TMPDIR")"
# 실제 공유 루트 꼴: 체크아웃에 옛 꼴 design/v65 실재(쌍둥이 1개) → 그 체크아웃 파일로 판정
v65_tree "$R/design/v65" OLD; g "$R" add -A; g "$R" commit -qm old-v65
check seat-b; [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '열어라: design/v65/GOAL-LEDGER-v65.md' && ok "ⓐ6 체크아웃 옛 꼴 폴더 실재 1 → 그 폴더(design/v65) 로 판정" || bad "ⓐ6 rc=$RC :: $OUT :: $ERR"
check seat-b --touch "$PHRASE"; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-OK seat=seat-b' && ok "ⓐ7 체크아웃 원장 --touch → GOAL-OK rc0" || bad "ⓐ7 rc=$RC :: $OUT :: $ERR"
# r495: 쌍둥이 둘 다 실재 → ref 트리로 가름(ⓐ8 기대 변경 — r479 «ERROR» 는 뒤처진 체크아웃마다 v65 골 틱을 세웠다)
v65_tree "$R/design/teams/v65" NEW; check seat-b
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-OK seat=seat-b' && ! printf '%s' "$OUT" | grep -q '^NOTE' && [ "$(printf '%s\n' "$ERR" | grep -c "^WARN TWIN-STALE .*/design/v65 (ref 에 없음 · 체크아웃 ref 뒤 [0-9]*커밋)$")" = 1 ] && ok "ⓐ8 쌍둥이 ∧ ref 한쪽(teams) → GOAL-OK rc0 + stderr WARN TWIN-STALE 1줄(옛 꼴) · NOTE 0" || bad "ⓐ8 rc=$RC :: $OUT :: $ERR"
DV="$(g "$R" rev-parse HEAD:design/v65)"   # ⓐ8b ref = origin/main + design/v65(이동 중 커밋 꼴)
ND="$( { g "$R" ls-tree refs/remotes/origin/main:design; printf '040000 tree %s\tv65\n' "$DV"; } | g "$R" mktree)"
NT="$( { g "$R" ls-tree refs/remotes/origin/main | grep -v $'\tdesign$'; printf '040000 tree %s\tdesign\n' "$ND"; } | g "$R" mktree)"
g "$R" update-ref refs/remotes/origin/both "$(g "$R" commit-tree -p refs/remotes/origin/main -m both "$NT")"
FT_TEAMS_REF=origin/both check seat-b
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-OK seat=seat-b' && [ "$(printf '%s\n' "$ERR" | grep -c "^WARN TWIN-BOTH [^ ]*/design/teams/v65 [^ ]*/design/v65 (ref 에 둘 다 · 명단 꼴 [^ ]*/design/teams/v65)$")" = 1 ] && ok "ⓐ8b ref 에 둘 다 → 명단 꼴(teams) + WARN TWIN-BOTH rc0" || bad "ⓐ8b rc=$RC :: $OUT :: $ERR"
LB="$(g "$R" hash-object -w "$S/design/TEAMS.md")"   # ⓐ8c ref = 명단만(v65 폴더 0)
LT="$(printf '040000 tree %s\tdesign\n' "$(printf '100644 blob %s\tTEAMS.md\n' "$LB" | g "$R" mktree)" | g "$R" mktree)"
g "$R" update-ref refs/remotes/origin/onlylist "$(g "$R" commit-tree -m onlylist "$LT")"
FT_TEAMS_REF=origin/onlylist check seat-b
[ "$RC" = 4 ] && printf '%s' "$OUT" | grep -q '^ERROR seat=seat-b v65 폴더 실재 후보 2개 — 정확히 1개여야 한다(명단 origin/onlylist:design/TEAMS.md · 후보 .*) (ref 에 둘 다 없음)$' && ! printf '%s' "$OUT" | grep -q 'GOAL-\|REREAD' && ok "ⓐ8c ref 에 둘 다 없음 → ERROR 후보 2개 (ref 에 둘 다 없음) exit 4(fail-closed 그대로)" || bad "ⓐ8c rc=$RC :: $OUT :: $ERR"
rm "$R/design/teams/v65/GOAL-LEDGER-v65.md"; check seat-b   # ⓐ8d 고른 새 꼴 폴더에 원장 없음 → 그 파일만 ref 본문 + NOTE(끝 줄)
[ "$RC" = 0 ] && [ "$(printf '%s\n' "$OUT" | head -1 | cut -d' ' -f1)" = GOAL-OK ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "NOTE 정본 = origin/main 본문(체크아웃 ref 뒤 $(g "$R" rev-list --count HEAD..origin/main)커밋): GOAL-LEDGER-v65.md" ] && ok "ⓐ8d 새 꼴에 원장 없음 → ref 본문 + NOTE 끝 줄 · GOAL-OK rc0" || bad "ⓐ8d rc=$RC :: $OUT :: $ERR"
check seat-b --touch "$PHRASE"; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-READ seat=seat-b' && ok "ⓐ8d2 --touch 문구 = ref 본문 원장에서 찾음 rc0" || bad "ⓐ8d2 rc=$RC :: $OUT :: $ERR"
[ "$(ls "$TMPDIR" | grep -c ft-team-doc)" = 0 ] && ok "ⓐ8d3 ref 본문 임시 파일 정리(trap)" || bad "ⓐ8d3 임시 파일 남음: $(ls "$TMPDIR")"
rm -rf "$R/design/teams"; g "$R" update-ref -d refs/remotes/origin/both; g "$R" update-ref -d refs/remotes/origin/onlylist

# ⓑ 체크아웃에 TEAMS.md 를 둬도(옛 꼴 · v65 행 없음) 결과 동일 — 파일이 아니라 ref · 어긋남 = 끝에 WARN 1줄
check seat-b; BASE_OUT="$(printf '%s' "$OUT" | head -1 | cut -d' ' -f1-2)"; BASE_RC=$RC
printf "$HEADROW"'| planner | `design/planner/` | x | 현역 |\n' > "$R/design/TEAMS.md"
check seat-b; [ "$RC" = "$BASE_RC" ] && [ "$(printf '%s' "$OUT" | head -1 | cut -d' ' -f1-2)" = "$BASE_OUT" ] && ok "ⓑ1 옛 명단 파일이 있어도 rc·첫 줄 동일($BASE_OUT rc=$RC)" || bad "ⓑ1 rc=$RC/$BASE_RC :: $OUT"
[ "$(printf '%s\n' "$ERR" | grep -c '^WARN 체크아웃 명단 .* v65 칸이 origin/main 와 다르다')" = 1 ] && ok "ⓑ2 명단 어긋남 = stderr WARN 1줄" || bad "ⓑ2 WARN :: $ERR"
cp "$S/design/TEAMS.md" "$R/design/TEAMS.md"; check seat-b; [ "$RC" = "$BASE_RC" ] && [ -z "$ERR" ] && ok "ⓑ3 ref 와 같은 명단 파일 → WARN 0 · rc 동일" || bad "ⓑ3 rc=$RC :: $ERR"
rm -f "$R/design/TEAMS.md"

# ⓒ ref 없음(fetch 안 된 리포) → ERROR 명단 ref 못 읽음 exit 4 · 추측·옛 글자 경로 0
g "$R" update-ref -d refs/remotes/origin/main
check seat-b; [ "$RC" = 4 ] && printf '%s' "$OUT" | grep -q '^ERROR seat=seat-b 명단 ref 못 읽음' && ! printf '%s' "$OUT" | grep -q 'GOAL-\|REREAD' && ok "ⓒ ref 없음 → ERROR 명단 ref 못 읽음 exit 4" || bad "ⓒ rc=$RC :: $OUT"
g "$R" fetch -q "$S" main:refs/remotes/origin/main

# ⓓ ft-goal-tick.sh 전체 — rc=3 → relay 1 · rc=0 → tick quiet · rc=4 → relay 에 REJECT 문구(지금과 같음)
mkdir -p "$R/.fable-team/comm"; MLOG="$T/mbox.log"
printf '#!/bin/bash\necho "ARGS $*" >> "%s"; [ "$1" = relay ] && cat "$4" >> "%s"; exit 0\n' "$MLOG" "$MLOG" > "$R/.fable-team/comm/mbox.sh"; chmod +x "$R/.fable-team/comm/mbox.sh"
tmux() { [ "$1" = has-session ]; }; export -f tmux
tick() { : > "$MLOG"; TOUT="$(FT_GOAL_TICK_ROOT="$R" FT_GOAL_TICK_TARGET=seat-t FT_GOAL_TICK_STREAK="$T/streak" FT_GOAL_TICK_CHECK="${1:-$BIN/ft-goal-check.sh}" bash "$BIN/ft-goal-tick.sh" 2>&1)"; TRC=$?
  sed -n 's#^ARGS relay [^ ]* [^ ]* \(/tmp/goal-tick\.[A-Za-z0-9]*\) .*#\1#p' "$MLOG" | while IFS= read -r f; do rm -f "$f"; done; }   # 틱 relay 본문(/tmp) 정리 — 시험이 남기지 않는다
tick; [ "$TRC" = 0 ] && printf '%s' "$TOUT" | grep -q 'tick sent target=seat-t rc=3' && [ "$(grep -c '^ARGS relay seat-t os-goal-tick' "$MLOG")" = 1 ] && grep -q '틱 본문 OLD' "$MLOG" && ok "ⓓ1 새 좌석 → rc=3 relay 1(체크아웃 실재 폴더 프롬프트)" || bad "ⓓ1 trc=$TRC :: $TOUT :: $(cat "$MLOG")"
(cd "$R" && bash "$BIN/ft-goal-check.sh" seat-t --touch "$PHRASE" >/dev/null 2>&1)
tick; [ "$TRC" = 0 ] && printf '%s' "$TOUT" | grep -q 'tick quiet target=seat-t rc=0' && [ ! -s "$MLOG" ] && ok "ⓓ2 읽은 좌석 → rc=0 tick quiet · relay 0" || bad "ⓓ2 trc=$TRC :: $TOUT :: $(cat "$MLOG")"
printf '#!/bin/bash\necho "REJECT seat=$1 cited 문구가 골 원장에 없다 (열지 않았다): x"; exit 4\n' > "$T/rej.sh"; chmod +x "$T/rej.sh"
tick "$T/rej.sh"; [ "$TRC" = 0 ] && printf '%s' "$TOUT" | grep -q 'tick sent target=seat-t rc=4' && grep -q 'rc=4 · REJECT seat=seat-t cited' "$MLOG" && ok "ⓓ3 판정기 rc=4 → relay 에 REJECT 문구(지금과 같음)" || bad "ⓓ3 trc=$TRC :: $TOUT :: $(cat "$MLOG")"
unset -f tmux

# ⓔ 골 표 원장(쪽지 가드 경로 ft_goal_table.py render) — r545: 출처 = ref(origin/main) 트리 · 체크아웃 디스크 실재 여부는 안 본다
LR="$T/live"; g "$R" worktree add -q -b v6 "$LR" main
printf "$HEADROW"'| planner | `design/planner/` | x | 현역 |\n' > "$LR/design/TEAMS.md"; planner_tree "$LR/design/planner"
mkdir -p "$R/.fable-team/livebin"; printf '%s\n' "$R/.fable-team/livebin" > "$R/.fable-team/LIVE_BIN"; printf '%s\n' "$LR" > "$R/.fable-team/LIVE_ROOT"
render() { OUT="$(cd "$T" && env -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER -u FT_LEDGER_REPO -u FT_LEDGER_PATH FT_ROOT="$R" python3 "$BIN/ft_goal_table.py" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
render; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '상태3 진행' && [ "$(printf '%s' "$OUT" | grep -c '진행')" = 6 ] && ok "ⓔ1 옛 명단 그대로 → 골 표 6행 + 원장 상태" || bad "ⓔ1 rc=$RC :: $OUT :: $ERR"
FIRST="$OUT"; cp "$S/design/TEAMS.md" "$LR/design/TEAMS.md"
render; [ "$RC" = 0 ] && [ "$OUT" = "$FIRST" ] && [ -z "$ERR" ] && ok "ⓔ2 LIVE_ROOT 명단을 origin/main 판으로 갈아도 같은 골 표(planner = ref 판 1개) · WARN 0" || bad "ⓔ2 rc=$RC :: $OUT :: $ERR"
mkdir -p "$LR/design/teams/planner"; render
[ "$RC" = 0 ] && [ "$OUT" = "$FIRST" ] && ok "ⓔ3 체크아웃 디스크 쌍둥이(빈 새 꼴) 있어도 ref 판 1개로 rc0 · 표 동일(r545 — 디스크 실재 후보로 고르지 않는다)" || bad "ⓔ3 rc=$RC :: $OUT :: $ERR"
REFSHA_E="$(g "$R" rev-parse refs/remotes/origin/main)"; planner_tree "$S/design/planner"; g "$S" add -A; g "$S" commit -qm twin; g "$R" fetch -q "$S" main:refs/remotes/origin/main
render; [ "$RC" = 1 ] && printf '%s' "$ERR" | grep -q 'planner 폴더가 origin/main 에 2개' && ok "ⓔ3b ref 에 쌍둥이 둘 다 → ERROR 2개 rc1(추측 0)" || bad "ⓔ3b rc=$RC :: $OUT :: $ERR"
g "$R" update-ref refs/remotes/origin/main "$REFSHA_E"; rmdir "$LR/design/teams/planner"; mv "$LR/design/planner" "$T/planner.off"
render; [ "$RC" = 0 ] && [ "$OUT" = "$FIRST" ] && ok "ⓔ4 체크아웃에 planner 폴더가 없어도 ref 판으로 rc0 · 표 동일(r545 — 공용 체크아웃이 뒤처져도 안 멈춘다)" || bad "ⓔ4 rc=$RC :: $OUT :: $ERR"
g "$S" rm -rq design/teams/planner design/planner; g "$S" commit -qm nogoal; g "$R" fetch -q "$S" main:refs/remotes/origin/main
render; [ "$RC" = 1 ] && printf '%s' "$ERR" | grep -q 'planner 폴더가 origin/main 에 0개' && ok "ⓔ4b ref 에도 없음 → ERROR 0개 rc1(추측·옛 글자 경로 후퇴 0)" || bad "ⓔ4b rc=$RC :: $OUT :: $ERR"
g "$R" update-ref refs/remotes/origin/main "$REFSHA_E"

# ── r485: 원장 키 = ref sha · 상태 = 공용 루트 1개 · 경과 = ref 기준
# 픽스처: P = origin 판 · Q = 공용 루트(clone · main 이 ref 보다 원장 1커밋 뒤) · W = Q 의 워크트리(원장 한 줄 더 커밋 = 체크아웃 sha ≠ ref sha) · 세 루트의 원장 sha 가 전부 다르다(실측 꼴)
P="$T/r485src"; Q="$T/r485"; W="$T/r485wt"; X="$T/r485nov"; LP=design/teams/v65/GOAL-LEDGER-v65.md
WT_ONLY="체크아웃에만-있는-문구-워크트리-좌석이-추가했다"; REF_ONLY="ref-에만-있는-문구-origin-main-이-추가했다"
mkdir -p "$P/design"; g "$P" init -q -b main
printf "$HEADROW"'| v65 | `design/teams/v65/` | x | 현역 |\n' > "$P/design/TEAMS.md"; v65_tree "$P/design/teams/v65" R485; g "$P" add -A; g "$P" commit -qm c1
git clone -q "$P" "$Q"; mkdir -p "$Q/.fable-team"
printf '| **M2** 참조 | %s | 진행 |\n' "$REF_ONLY" >> "$P/$LP"; g "$P" commit -qam c2; g "$Q" fetch -q origin
g "$Q" worktree add -q -b wt "$W" origin/main
printf '| **M3** 좌석 | %s | 진행 |\n' "$WT_ONLY" >> "$W/$LP"; g "$W" commit -qam c3
rsha() { g "$Q" log -1 --format=%h origin/main -- "$LP"; }
SQ="$(g "$Q" log -1 --format=%h -- "$LP")"; SW="$(g "$W" log -1 --format=%h -- "$LP")"; SR="$(rsha)"
[ "$SQ" != "$SR" ] && [ "$SW" != "$SR" ] && [ "$SQ" != "$SW" ] && ok "r485 픽스처 원장 sha 셋 다름(Q=$SQ W=$SW ref=$SR)" || bad "r485 픽스처 sha Q=$SQ W=$SW ref=$SR"
ST="$Q/.fable-team/state/goal-read-ledger.json"
row() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));e=d.get(sys.argv[2],{});print(e.get(sys.argv[3],""))' "$ST" "$1" "$2"; }

# r485-ⓐ 워크트리 cwd 에서 --touch → 공용 루트 state 에만 행 1 · ledger_sha = ref sha(체크아웃 sha 아님) · ref_sha 칸
CWD="$W" check seat-r --touch "$PHRASE"
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "^GOAL-READ seat=seat-r ledger=$SR .* ref=$(g "$Q" rev-parse --short origin/main) state=.*/r485/.fable-team/state/goal-read-ledger.json OK" && ok "r485-ⓐ1 워크트리 touch → GOAL-READ ref=· state=공용 루트 rc0" || bad "r485-ⓐ1 rc=$RC :: $OUT :: $ERR"
[ -f "$ST" ] && [ ! -e "$W/.fable-team" ] && [ "$(row seat-r ledger_sha)" = "$SR" ] && [ "$(row seat-r ref_sha)" = "$(g "$Q" rev-parse --short origin/main)" ] && ok "r485-ⓐ2 상태 = 공용 루트 1개 · ledger_sha=ref($SR ≠ 체크아웃 $SW) · ref_sha 칸" || bad "r485-ⓐ2 ledger=$(row seat-r ledger_sha) ref=$(row seat-r ref_sha) wt=$(ls -a "$W" | tr '\n' ' ')"

# r485-ⓑ 공용 루트 cwd(틱 자리)에서 같은 좌석 → GOAL-OK rc0 · REREAD 0
CWD="$Q" check seat-r; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-OK seat=seat-r' && ! printf '%s' "$OUT" | grep -q REREAD && ok "r485-ⓑ 공용 루트 cwd → GOAL-OK rc0(틱과 좌석이 같은 행)" || bad "r485-ⓑ rc=$RC :: $OUT :: $ERR"

# r485-ⓒ ref 에 원장 커밋 1 → 양쪽 cwd 모두 rc3 «골 원장 갱신됨»
printf '| **M4** 추가 | 원장-갱신-문구-하나-더 | 진행 |\n' >> "$P/$LP"; g "$P" commit -qam c4; g "$Q" fetch -q origin
CWD="$Q" check seat-r; R1=$RC; O1="$OUT"; CWD="$W" check seat-r
[ "$R1" = 3 ] && [ "$RC" = 3 ] && printf '%s' "$O1" | grep -q "골 원장 갱신됨 ${SR}→$(rsha)" && printf '%s' "$OUT" | grep -q '골 원장 갱신됨' && ok "r485-ⓒ ref 원장 커밋 → 공용 루트·워크트리 둘 다 rc3 골 원장 갱신됨" || bad "r485-ⓒ rc=$R1/$RC :: $O1 :: $OUT"

# r485-ⓓ 경과 = ref 기준 — 워크트리 로컬 커밋만 늘면 rc0 · ref 에 다른 파일 커밋 MAX+1 → rc3
CWD="$W" check seat-r --touch "$PHRASE" >/dev/null
for i in 1 2 3; do echo "$i" > "$W/local$i"; g "$W" add -A; g "$W" commit -qm "l$i"; done
OUT="$(cd "$W" && env -u FT_ROOT FT_GOAL_MAX_COMMITS=2 bash "$BIN/ft-goal-check.sh" seat-r 2>&1)"; RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'commits_since=0' && ok "r485-ⓓ1 워크트리 로컬 커밋 3(>MAX 2) → rc0 commits_since=0" || bad "r485-ⓓ1 rc=$RC :: $OUT"
for i in 1 2 3; do echo "$i" > "$P/other$i"; g "$P" add -A; g "$P" commit -qm "o$i"; done; g "$Q" fetch -q origin
OUT="$(cd "$W" && env -u FT_ROOT FT_GOAL_MAX_COMMITS=2 bash "$BIN/ft-goal-check.sh" seat-r 2>&1)"; RC=$?
[ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '커밋 3개 경과 > 2' && ok "r485-ⓓ2 ref 에 다른 파일 커밋 3 → rc3 커밋 3개 경과" || bad "r485-ⓓ2 rc=$RC :: $OUT"

# r485-ⓔ cited — 체크아웃에만 있는 문구 → OK(체크아웃 파일) · 체크아웃 폴더 없음 + ref 에만 있는 문구 → OK(ref 본문) · 옛 꼴 행(ref_sha 없음) → REREAD
CWD="$W" check seat-r --touch "$WT_ONLY"; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^GOAL-READ seat=seat-r' && ok "r485-ⓔ1 체크아웃 전용 문구 touch → OK" || bad "r485-ⓔ1 rc=$RC :: $OUT :: $ERR"
g "$Q" worktree add -q -b nov "$X" origin/main; g "$X" rm -rq design/teams/v65; g "$X" commit -qm nov
CWD="$X" check seat-x --touch "$REF_ONLY"; [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q "^GOAL-READ seat=seat-x ledger=$(rsha)" && ok "r485-ⓔ2 체크아웃 폴더 0 + ref 전용 문구 → ref 본문으로 OK" || bad "r485-ⓔ2 rc=$RC :: $OUT :: $ERR"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["seat-r"].pop("ref_sha");json.dump(d,open(sys.argv[1],"w"))' "$ST"
CWD="$Q" check seat-r; [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '옛 꼴 행 — ref_sha 없음' && ok "r485-ⓔ3 옛 꼴 행(ref_sha 없음) → REREAD rc3 «다시 touch»" || bad "r485-ⓔ3 rc=$RC :: $OUT"
[ -n "$(rsha)" ] && [ "$(row seat-x ledger_sha)" = "$(rsha)" ] && [ -n "$(row seat-r ledger_sha)" ] && [ ! -e "$X/.fable-team" ] && ok "r485-ⓔ4 상태 파일 1개에 seat-r·seat-x 둘 다(워크트리 X 자리 0)" || bad "r485-ⓔ4 seat-x=$(row seat-x ledger_sha)"

grep -nE '\b(600|300)\b' "$BIN/ft-goal-check.sh" "$BIN/ft_team_lib.py" "$BIN/ft_goal_ledger.py" >/dev/null && bad "600/300 상한 등장" || ok "고친 파일 600/300 0"
echo "== test_goal_check_ref: fail=$fail"; [ "$fail" = 0 ]
