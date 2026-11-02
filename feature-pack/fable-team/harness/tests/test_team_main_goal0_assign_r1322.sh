#!/usr/bin/env bash
# R1322 — 팀 메인 파일: 1행 제0목표 · 2행 옛 헤드라인 · ④ 배정표 절(팀장 손 ASSIGN.md 본문 그대로 · 낡음 20분 · 읽기 실패 판정 불가) ·
#         ASSIGN.md 틀(없을 때만 · 있으면 바이트 무변경) · ft-team-attach 새 팀도 같은 틀.
# 반례 A1~A7 + 변이 5(①1행 제0목표 제거 ②있어도 덮어씀 ③낡음 표시 제거 ④읽기 실패를 빈 절로 ⑤attach 틀 호출 제거).
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
BIN="$HERE/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ulimit -u 2000 2>/dev/null || true
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/repo"; D="$TMP/data"; AR="$TMP/attach-root"; NOW=1793600000; BAD=0; CASEBAD=0
GOAL0='제0목표: 진행 중 카드를 완성하고 닫는다'
HEADER='| 카드 | 좌석 | 선행 | 다음 수 | 줄 주인 |'

ck() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $d"; else echo "FAIL $d"; CASEBAD=1; fi; }
has() { grep -qF -- "$1" "$2"; }
case_() { CASEBAD=0; "$@"; return $CASEBAD; }
run() { ( cd "$R" && FT_TEAM_MAIN_NOW="$NOW" bash "$BIN/ft-team-main.sh" render "${1:---all}" ) 2>"$TMP/err"; }
sf() { echo "$D/.fable-team/state/team-main/$1/STATE.md"; }
af() { echo "$D/.fable-team/state/team-main/$1/ASSIGN.md"; }
latest() { mkdir -p "$R/.fable-team/state/$1"; printf '%s\n' "$2" > "$R/.fable-team/state/$1/latest.json"; }
fresh() { printf '{"tool":"t","kind":"%s","written_at":%s,"stamp":"1793600000-abcd1234","line":"","items":%s}' "$1" "$NOW" "$2"; }
commit() { git -C "$R" add -A >/dev/null; git -C "$R" commit -qm "${1:-fixture}" >/dev/null; git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"; }
mt() { python3 -c 'import os,sys; os.utime(sys.argv[1], (float(sys.argv[2]),)*2)' "$1" "$2"; }   # mt <파일> <epoch>

reset() {  # 임시 git 루트 · 데이터 루트(LIVE_ROOT) · TEAMS.md(현역 alpha · 휴면 sleep) · 지시 표 · 카드 1 · 집계 3종
  rm -rf "$R" "$D"; mkdir -p "$R/.fable-team/state" "$D" "$R/design/teams/planner" "$R/design/teams/alpha/indices/진행"
  printf '.fable-team/\n' > "$R/.gitignore"; printf '%s\n' "$D" > "$R/.fable-team/LIVE_ROOT"
  printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | byz-alpha-master-claude | 현역 |\n| sleep | `design/teams/sleep/` | FB_SLEEP | 휴면 |\n' > "$R/design/TEAMS.md"
  printf 'alpha\t.\torigin/main\tdesign/teams/alpha/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  mkdir -p "$R/.fable-team/state/alpha-tick"; echo "08:25 · alpha 헤드라인 1줄" > "$R/.fable-team/state/alpha-tick/HEADLINE.md"
  printf '| # | 시각 · ts | 팀 | 지시(원문 요약) | 상태 | 닫는 증거 |\n|---|---|---|---|---|---|\n| 1 | 15:00 | alpha | 알파 하나 | 진행 | - |\n' \
    > "$R/design/teams/planner/THREAD-oppa-directives-1793487673-20261101.md"
  printf '# 인덱스: A-m0\n- 지시 #: 16\n## 상태\n- 2026-11-02T08:1x 진행\n' > "$R/design/teams/alpha/indices/진행/A-m0.md"
  latest card-assign "$(fresh card-assign '[]')"; latest decision "$(fresh decision '[]')"; latest hil "$(fresh hil '[]')"
  git -C "$R" init -q -b main; commit base; }

ledger3() {  # 팀장 손 배정표 3행(A1·A3 공용)
  mkdir -p "$(dirname "$(af alpha)")"
  printf '| 카드 | 좌석 | 선행 | 다음 수 | 줄 주인 |\n|---|---|---|---|---|\n| A-m0 | byz-alpha-nano-x#0 | 없음 | 시험 | alpha-master |\n| A-d0 | 없음 | A-m0 | 배정 | alpha-arch |\n| A-c0 | byz-alpha-nano-y#0 | 없음 | 판정 | alpha-master |\n' > "$(af alpha)"
  mt "$(af alpha)" "$NOW"; }

case_a1() {  # 있음 → 1행 제0목표 · 2행 옛 머리 · ④ = 3행 그대로 · ASSIGN.md 바이트 무변경
  reset; ledger3; local sha; sha="$(shasum -a 256 "$(af alpha)" | cut -d' ' -f1)"; run --all; local s; s="$(sf alpha)"
  ck "A1 1행 제0목표" sh -c "head -1 '$s' | grep -qxF '$GOAL0'"
  ck "A1 2행 옛 머리(헤드라인)" sh -c "head -2 '$s' | tail -1 | grep -qxF '08:25 · alpha 헤드라인 1줄'"
  ck "A1 ④ 절 머리 · 3행 그대로" sh -c "grep -qF '## ④ 배정표 (팀장 손 · 파일' '$s' \\
    && grep -qF '| A-m0 | byz-alpha-nano-x#0 | 없음 | 시험 | alpha-master |' '$s' \\
    && grep -qF '| A-d0 | 없음 | A-m0 | 배정 | alpha-arch |' '$s' \\
    && grep -qF '| A-c0 | byz-alpha-nano-y#0 | 없음 | 판정 | alpha-master |' '$s'"
  ck "A1 ④ 가 ③ 뒤(절 순서)" sh -c "[ \"\$(grep -n '^## ' '$s' | tail -1 | cut -d: -f2-)\" = '## ④ 배정표 (팀장 손 · 파일 '\"\$(date -r '$NOW' +%H:%M)\"')' ]"
  ck "A1 ASSIGN.md 바이트 무변경" test "$sha" = "$(shasum -a 256 "$(af alpha)" | cut -d' ' -f1)"
  return $CASEBAD; }

case_a2() {  # 없음 → 틀 1개(1행 제0목표 · 2행 표 머리) · ④ 절 = 틀
  reset; run --all; local s; s="$(sf alpha)"
  ck "A2 ASSIGN.md 생김" test -f "$(af alpha)"
  ck "A2 틀 1행·2행" sh -c "[ \"\$(wc -l < '$(af alpha)')\" -eq 2 ] && head -1 '$(af alpha)' | grep -qxF '$GOAL0' && head -2 '$(af alpha)' | tail -1 | grep -qxF '$HEADER'"
  ck "A2 ④ 절 = 틀" sh -c "grep -qF '## ④ 배정표 (팀장 손 · 파일' '$s' && grep -qF '$HEADER' '$s'"
  return $CASEBAD; }

case_a3() {  # render 두 번 → ASSIGN.md 바이트 무변경 · STATE 1행 같음
  reset; ledger3; run --all; local sha s1; sha="$(shasum -a 256 "$(af alpha)" | cut -d' ' -f1)"; s1="$(head -1 "$(sf alpha)")"
  run --all
  ck "A3 두 회차 ASSIGN.md 무변경" test "$sha" = "$(shasum -a 256 "$(af alpha)" | cut -d' ' -f1)"
  ck "A3 두 회차 1행 같음" test "$s1" = "$(head -1 "$(sf alpha)")"
  return $CASEBAD; }

case_a4() {  # 수정 21분 전 → ④ 머리에 «낡음 21분»
  reset; ledger3; mt "$(af alpha)" "$((NOW - 21 * 60))"; run --all
  ck "A4 낡음 21분" has "낡음 21분 — 팀장이 이번 루프에 다시 쓴다(R12)" "$(sf alpha)"
  return $CASEBAD; }

case_a5() {  # 폴더(읽기 실패) → ④ 판정 불가 1줄 · 다른 절 정상
  reset; mkdir -p "$(af alpha)/안"; run --all; local s; s="$(sf alpha)"
  ck "A5 ④ 판정 불가 1줄" sh -c "grep -qF '판정 불가(ASSIGN.md 읽기 실패' '$s' && [ \"\$(grep -c '판정 불가(ASSIGN.md' '$s')\" -eq 1 ]"
  ck "A5 다른 절 정상(①②③)" sh -c "grep -qF '## ① 절대 지침' '$s' && grep -qF '## ② 카드' '$s' && grep -qF '진행 1장' '$s' && grep -qF '## ③ 배정받은 작업' '$s'"
  return $CASEBAD; }

case_a6() {  # 휴면 팀 → 1행 제0목표 · 2행 «… [휴면]»
  reset; run --all; local s; s="$(sf sleep)"
  ck "A6 휴면 1행 제0목표" sh -c "[ \"\$(wc -l < '$s')\" -eq 2 ] && head -1 '$s' | grep -qxF '$GOAL0'"
  ck "A6 휴면 2행 [휴면]" sh -c "head -2 '$s' | tail -1 | grep -qF '[휴면]'"
  return $CASEBAD; }

case_a7() {  # attach 새 팀 → ASSIGN.md 틀 · 이미 있으면 무변경
  rm -rf "$AR"; mkdir -p "$AR/design/teams/zznew/indices" "$AR/.fable-team/bin" "$AR/LaunchAgents"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zznew | design/teams/zznew/ | x | 현역 |\n' > "$AR/design/TEAMS.md"
  printf '| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| zznew | 3 | 0 | 상시 |\n' > "$AR/design/TEAMSET.md"
  printf '#!/bin/sh\nexit 0\n' > "$AR/.fable-team/bin/ft-tick.sh"
  git -C "$AR" init -q -b main; git -C "$AR" add design >/dev/null; git -C "$AR" commit -qm seed >/dev/null
  local aaf="$AR/.fable-team/state/team-main/zznew/ASSIGN.md" env
  env() { FT_ROOT="$AR" FT_TEAMS_MD="$AR/design/TEAMS.md" FT_TEAMSET_MD="$AR/design/TEAMSET.md" \
          FT_TEAM_ATTACH_SANDBOX=1 FT_TICK_PLIST_DIR="$AR/LaunchAgents" "$@"; }
  env bash "$BIN/ft-team-attach.sh" zznew --apply >/dev/null 2>&1
  ck "A7 attach 새 팀 → 틀 2행" sh -c "[ -f '$aaf' ] && [ \"\$(wc -l < '$aaf')\" -eq 2 ] && head -1 '$aaf' | grep -qxF '$GOAL0' && head -2 '$aaf' | tail -1 | grep -qxF '$HEADER'"
  printf '| 카드 | 좌석 | 선행 | 다음 수 | 줄 주인 |\n|---|---|---|---|---|\n| Z-m0 | seat | 없음 | 시험 | lead |\n' > "$aaf"
  local sha; sha="$(shasum -a 256 "$aaf" | cut -d' ' -f1)"
  env bash "$BIN/ft-team-attach.sh" zznew --apply >/dev/null 2>&1
  ck "A7 이미 있으면 무변경" test "$sha" = "$(shasum -a 256 "$aaf" | cut -d' ' -f1)"
  return $CASEBAD; }

for c in case_a1 case_a2 case_a3 case_a4 case_a5 case_a6 case_a7; do case_ "$c" || BAD=1; done

mutant() {  # mutant <이름> <케이스들(공백)> <파일> <찾을 글자> <바꿀 글자>
  rm -rf "$TMP/mut"; mkdir -p "$TMP/mut"
  cp "$BIN/ft_team_main.py" "$BIN/ft_team_main_assign.py" "$BIN/ft_team_main_inputs.py" "$BIN/ft_team_lib.py" \
     "$BIN/ft_headline_seats.py" "$BIN/ft-team-main.sh" "$BIN/ft-team-attach.sh" "$BIN/ft_team_attach.py" \
     "$BIN/ft_team_attach_lib.py" "$BIN/ft_team_attach_ops.py" "$BIN/ft_team_attach_state.py" "$BIN/ft_team_attach_roots.py" \
     "$BIN/ft_tick_lock.py" "$TMP/mut/" 2>/dev/null
  local keep="$BIN" cases="$2" c blown=0
  BIN="$TMP/mut"
  for c in $cases; do case_ "$c" >/dev/null 2>&1 || blown=1; done
  if [ "$blown" = 1 ]; then echo "FAIL 무변이 대조 실패(변이 전에도 케이스 실패): $1"; BAD=1; BIN="$keep"; return; fi
  python3 - "$TMP/mut/$3" "$4" "$5" <<'PY' || { echo "FAIL 변이 적용 실패: $1"; BAD=1; BIN="$keep"; return; }
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
if sys.argv[2] not in t:
    sys.exit(1)
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
  blown=0
  for c in $cases; do case_ "$c" >/dev/null 2>&1 || blown=1; done
  if [ "$blown" = 1 ]; then echo "PASS 변이 탐지: $1"; else echo "FAIL 변이 미탐지: $1"; BAD=1; fi
  BIN="$keep"; }

mutant "1행 제0목표 제거" "case_a1 case_a6" ft_team_main.py '[assign.GOAL0, head_line,' '[head_line,'
mutant "있어도 덮어씀" "case_a1 case_a3" ft_team_main_assign.py '    if path.exists():
        return' '    if False:
        return'
mutant "낡음 표시 제거" "case_a4" ft_team_main_assign.py 'if now - mtime > STALE_SEC:' 'if False:'
mutant "읽기 실패를 빈 절로" "case_a5" ft_team_main_assign.py 'f"판정 불가(ASSIGN.md 읽기 실패 · {why})"' '""'
mutant "attach 틀 호출 제거" "case_a7" ft_team_attach_ops.py '    ensure_team(root, team)   # r1322 G5' '    pass'

[ "$BAD" -eq 0 ] && echo "ALL PASS r1322 제0목표·배정표 절"
exit "$BAD"
