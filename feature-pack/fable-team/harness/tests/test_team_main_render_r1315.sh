#!/usr/bin/env bash
# R1315 — ft-team-main.sh render: 고정 꼴 STATE · ①팀 열/판정 불가 · ②카드·seats · ③집계 귀속 · 닫힌 줄 월 archive · 상한 WARN · 쓰기 위치.
# 변이 6(판정 불가→빈 칸 · 꼴 다름 생략 · 쓰기 위치 · archive 생략 · 상한 절단 · 결정 귀속 0)은 아래에서 «탐지 + 무변이 대조 통과» 면 PASS.
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
BIN="$HERE/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ulimit -u 2000 2>/dev/null || true
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$TMP/repo"; D="$TMP/data"; NOW=1793600000; BAD=0; CASEBAD=0

ck() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $d"; else echo "FAIL $d"; CASEBAD=1; fi; }
has() { grep -qF -- "$1" "$2"; }
case_() { CASEBAD=0; "$@"; return $CASEBAD; }
card() { mkdir -p "$1/indices/$2"; { echo "# 인덱스: $3"; [ -n "${4:-}" ] && echo "- 지시 #: $4"; echo "## 상태"; echo "- $5"; [ "${6:-}" = check ] && echo "- 확인: 설치 cmp0"; } > "$1/indices/$2/$3.md"; }
latest() { mkdir -p "$R/.fable-team/state/$1"; printf '%s\n' "$2" > "$R/.fable-team/state/$1/latest.json"; }
fresh() { printf '{"tool":"t","kind":"%s","written_at":%s,"stamp":"1793600000-abcd1234","line":"","items":%s}' "$1" "${2:-$NOW}" "$3"; }
commit() { git -C "$R" add -A >/dev/null; git -C "$R" commit -qm "${1:-fixture}" >/dev/null; git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"; git -C "$R" update-ref refs/remotes/origin/ops/main-base "$(git -C "$R" rev-parse HEAD)"; }
run() { ( cd "$R" && FT_TEAM_MAIN_NOW="$NOW" bash "$BIN/ft-team-main.sh" render "${1:---all}" ) 2>"$TMP/err"; }
sf() { echo "$D/.fable-team/state/team-main/$1/STATE.md"; }
tbl() { mkdir -p "$(dirname "$1")"; if [ "$2" = yes ]; then printf '| # | 시각 · ts | 팀 | 지시(원문 요약) | 상태 | 닫는 증거 |\n|---|---|---|---|---|---|\n| 1 | 15:00 | alpha | 알파 하나 | 진행 | - |\n| 2 | 15:10 | alpha | 알파 둘 | 진행 | - |\n| 3 | 15:20 | 전팀 | 전팀 하나 | 진행 | - |\n| 4 | 15:30 | beta | 베타 하나 | 진행 | - |\n| 5 | 15:40 | alpha | 알파 닫힘 | ★닫힘(판정 1)★ | ts |\n| 6 | 15:50 |  | 빈 칸 | 진행 | - |\n' > "$1"; else printf '| # | 시각 · ts | 지시(원문 요약) | 상태 | 닫는 증거 |\n|---|---|---|---|---|\n| 1 | 15:00 | 지시 하나 | 진행 | - |\n' > "$1"; fi; }
reset() {  # 임시 git 루트 · TEAMS.md · 카드 루트 표 · 카드 · 지시 표(현역 ts 최대 + 옛 표) · latest 3종
  rm -rf "$R" "$D"; mkdir -p "$R/.fable-team/state" "$D" "$R/design/teams/planner"
  printf '.fable-team/\n' > "$R/.gitignore"; printf '%s\n' "$D" > "$R/.fable-team/LIVE_ROOT"
  printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | byz-alpha-master-claude | 현역 |\n| beta | `design/teams/beta/` | byz-beta-master-claude | 현역 |\n| planner | `design/teams/planner/` | byz-planner-master-claude | 현역 |\n| harness | `$FT_HARNESS_ROOT/design/harness/` | byz-harness-master-claude | 현역 |\n| sleep | `design/teams/sleep/` | FB_SLEEP | 휴면 |\n' > "$R/design/TEAMS.md"
  printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\torigin/ops/main-base\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  mkdir -p "$R/.fable-team/state/alpha-tick"; echo "08:25 · alpha 헤드라인 1줄" > "$R/.fable-team/state/alpha-tick/HEADLINE.md"
  tbl "$R/design/teams/planner/THREAD-oppa-directives-1793487673-20261101.md" yes
  printf '| # | 시각 · ts | 팀 | 지시(원문 요약) | 상태 | 닫는 증거 |\n|---|---|---|---|---|---|\n| 99 | 10:00 | alpha | 옛 행 | 진행 | - |\n' > "$R/design/teams/planner/THREAD-oppa-directives-1793000000-20261020.md"
  card "$R/design/teams/alpha" 진행 A-m0 16 "2026-11-02T08:1x 진행"; card "$R/design/teams/alpha" 진행 A-m1 17 "2026-11-02T08:2x 진행"
  card "$R/design/teams/alpha" 대기 A-d0 18 "2026-11-01T09:00 대기"; card "$R/design/teams/alpha" 대기 A-d1 19 "2026-10-30T09:00 대기"
  card "$R/design/teams/alpha" 대기 A-d2 20 "2026-11-01T10:00 대기"; card "$R/design/teams/alpha" 완성 A-c0 21 "2026-11-01T09:00 완성" check
  card "$R/design/teams/alpha" 완성 A-c1 22 "2026-11-01T10:00 완성"; card "$R/design/teams/beta" 진행 B-m0 16 "2026-11-02T07:0x 진행"
  card "$R/design/teams/beta" 진행 B-m1 "" "2026-11-02T07:1x 진행"; card "$R/design/harness" 진행 H-m0 16 "2026-11-02T07:3x 진행"
  latest card-assign "$(fresh card-assign "$NOW" '[{"team":"alpha","kind":"없음","stem":"A-m0"},{"team":"alpha","kind":"발주","stem":"P-m0"}]')"
  latest decision "$(fresh decision "$NOW" '["#9 byz-alpha-master-claude#3 12분 질문"]')"; latest hil "$(fresh hil "$NOW" '[]')"
  git -C "$R" init -q -b main; commit base; }

case_r1() {  # 고정 꼴 · 쓰기 위치(데이터 루트) · stderr 줄 · 루트에 새 파일 0
  reset; run --all; local s; s="$(sf alpha)"
  ck "R1 머리줄 = HEADLINE 첫 줄" has "08:25 · alpha 헤드라인 1줄" <(head -1 "$s")
  ck "R1 ①②③ 절" sh -c "grep -qF '## ① 절대 지침' '$s' && grep -qF '## ② 카드' '$s' && grep -qF '## ③ 배정받은 작업' '$s'"
  ck "R1 ② 카드 고정 꼴(진행·좌석?·대기·완성)" sh -c "grep -qF '진행 2장' '$s' && grep -qF -- '- A-m0 · 지시 #16 · 좌석 ? · 상태 2026-11-02T08:1x 진행' '$s' \\
    && grep -qF '좌석 칸 판정 불가(seats 파일 없음 · r1290 대기)' '$s' && grep -qF '대기 3장 · 가장 오래 2026-10-30' '$s' && grep -qF '완성(확인 전) 1장' '$s'"
  ck "R1 ③ 배정 없음 1·발주 1·결정 1" sh -c "grep -qF '배정 없음 1 · 대기 초과 0 · 카드 없는 발주 1' '$s' && grep -qF '결정 대기 1건' '$s'"
  ck "R1 beta 지시 # 없음 1장" has "지시 # 없음: 카드 1장" "$(sf beta)"
  ck "R1 stderr 팀마다 1줄" has "team-main alpha 진행 2 대기 3 완성미확인 1 발주 1 결정 1" "$TMP/err"
  ck "R1 루트에 새 파일 0(추적·미추적)" [ -z "$(git -C "$R" status --porcelain)" ]
  return $CASEBAD; }

case_r2() {  # ① 팀 열 없음 = 판정 불가 · 다른 칸은 쓴다
  reset; tbl "$R/design/teams/planner/THREAD-oppa-directives-1793487673-20261101.md" no; commit r2; run --all
  ck "R2 팀 열 없음 판정 불가 · ② 정상" sh -c "grep -qF '판정 불가(지시 표 팀 열 없음)' '$(sf alpha)' && grep -qF '진행 2장' '$(sf alpha)'"
  return $CASEBAD; }

case_r2b() {  # ref 에 지시 표 없음
  reset; git -C "$R" rm -q design/teams/planner/THREAD-oppa-directives-1793487673-20261101.md design/teams/planner/THREAD-oppa-directives-1793000000-20261020.md; commit r2b; run --all
  ck "R2b 지시 표 없음 판정 불가" has "판정 불가(지시 표 없음)" "$(sf alpha)"
  return $CASEBAD; }

case_r3() {  # 팀 열 · 현역 표(ts 최대) · 이 팀+전팀 · 닫힘 제외 · 빈 칸 «팀 미지정»
  reset; run --all
  ck "R3 이 팀·전팀 행 · 다른 팀/닫힘/옛 표 0 · 팀 미지정 1: #6" sh -c "s='$(sf alpha)'; grep -qF '| 1 | 15:00 | 알파 하나 |' \$s && grep -qF '| 2 | 15:10 | 알파 둘 |' \$s \\
    && grep -qF '| 3 | 15:20 | 전팀 하나 |' \$s && ! grep -qF '베타 하나' \$s && ! grep -qF '알파 닫힘' \$s && ! grep -qF '옛 행' \$s && grep -qF '팀 미지정 1: #6' \$s"
  return $CASEBAD; }

case_r4() {  # 집계가 20분 넘게 다름 = 그 종류만 판정 불가
  reset; latest decision "$(fresh decision "$((NOW - 25 * 60))" '["#9 byz-alpha-master-claude#3 40분 질문"]')"; run --all
  ck "R4 decision 만 판정 불가(집계 25분 전) · ②·card-assign 정상" sh -c "s='$(sf alpha)'; grep -qF '판정 불가(decision 집계 25분 전)' \$s && grep -qF '진행 2장' \$s && grep -qF '배정 없음 1' \$s"
  return $CASEBAD; }

case_r5() {  # JSON 아님 · items 꼴 다름 = 판정 불가 · rc0
  reset; latest decision 'not json'; latest card-assign "$(fresh card-assign "$NOW" '["문자열"]')"; run --all; local rc=$?
  ck "R5 rc0 · 둘 다 판정 불가 · ② 정상" sh -c "[ $rc -eq 0 ] && s='$(sf alpha)'; grep -qF '판정 불가(decision latest JSON 아님)' \$s && grep -qF '판정 불가(card-assign latest 꼴 다름)' \$s && grep -qF '진행 2장' \$s"
  return $CASEBAD; }

case_r5b() {  # 최상위가 객체 아님([]·null) = 그 종류만 판정 불가 · AttributeError 0
  reset; latest card-assign '[]'; latest decision 'null'; run --all; local rc=$?
  ck "R5b rc0 · []·null 판정 불가(꼴 다름) · 다른 칸 정상" sh -c "[ $rc -eq 0 ] && s='$(sf alpha)'; grep -qF '판정 불가(card-assign latest 꼴 다름(written_at·items))' \$s \\
    && grep -qF '판정 불가(decision latest 꼴 다름(written_at·items))' \$s && grep -qF '진행 2장' \$s && ! grep -qF 'Traceback' '$TMP/err'"
  return $CASEBAD; }

case_r6() {  # 결정 귀속 = 문자열 첫 좌석 토큰 · 같은 seq 1건 · 토큰 없음 = planner 몫
  reset; latest decision "$(fresh decision "$NOW" '["#9 byz-alpha-master-claude#3 12분 질문","#9 byz-alpha-master-claude#3 12분 질문","#10 사람 확인 필요"]')"; run --all
  ck "R6 alpha 결정 1건 · beta 0건 · planner 좌석 토큰 없음 1건" sh -c "grep -qF '결정 대기 1건' '$(sf alpha)' && grep -qF '결정 대기 0건' '$(sf beta)' && grep -qF '좌석 토큰 없음 1건(planner 몫)' '$(sf planner)'"
  return $CASEBAD; }

case_r6b() {  # 미실행 h = planner 에만 (다른 팀은 «planner 몫» 1줄)
  reset; latest hil "$(fresh hil "$NOW" '[{"id":"h1","minutes":5},{"id":"h2","minutes":9}]')"; run --all
  ck "R6b planner 미실행 h 2건 · beta 는 planner 몫 1줄" sh -c "grep -qF '미실행 h 2건 : h1 h2' '$(sf planner)' && grep -qF '미실행 h 은 planner 몫' '$(sf beta)' && ! grep -qF '미실행 h 2건' '$(sf beta)'"
  return $CASEBAD; }

case_r7() {  # 진행 카드가 ref 에서 빠짐 → 월 archive 1줄 append
  reset; run --all; git -C "$R" rm -q design/teams/alpha/indices/진행/A-m1.md; commit r7; run --all
  local a; a="$D/.fable-team/state/team-main/alpha/archive/STATE-closed-$(date -r $NOW +%Y%m).md"
  ck "R7 archive 1줄 · A-m1 · STATE 에선 빠짐" sh -c "[ \"\$(wc -l < '$a')\" -eq 1 ] && grep -qF 'A-m1' '$a' && ! grep -qF 'A-m1' '$(sf alpha)'"
  return $CASEBAD; }

case_r7b() {  # 본문에 «## 상태» 글자가 먼저 있어도 줄 머리 제목만 본다
  reset; printf '# 인덱스: A-m0\n- 지시 #: 16\n- 규칙: «## 상태» 절 마지막 줄을 쓴다\n## 상태\n- 2026-11-02T09:9x 진짜 상태\n' > "$R/design/teams/alpha/indices/진행/A-m0.md"; commit r7b; run --all
  ck "R7b 줄 머리 «## 상태» 절만 · 본문 글자 무시" sh -c "grep -qF '상태 2026-11-02T09:9x 진짜 상태' '$(sf alpha)' && ! grep -qF '상태 절 마지막 줄을 쓴다' '$(sf alpha)'"
  return $CASEBAD; }

case_r8() {  # 진행 41장 → 다 씀 + 머리 WARN
  reset; local i=0; while [ $i -lt 39 ]; do card "$R/design/teams/alpha" 진행 "A-x$i" 16 "2026-11-02T08:0x 진행"; i=$((i + 1)); done; commit r8; run --all
  ck "R8 진행 41장 · 41줄 다 씀 · 머리 상한 초과" sh -c "s='$(sf alpha)'; grep -qF '진행 41장' \$s && [ \"\$(grep -c '^- A-' \$s)\" -eq 41 ] && head -1 \$s | grep -qF '[상한 초과 ②+1줄 — 닫기 우선]'"
  return $CASEBAD; }

case_r9() {  # seats 파일 있으면 좌석 칸 값 · 없으면 «?»(R1)
  reset; printf 'A-m0\t✻ 08:2x\n' > "$R/.fable-team/state/alpha-tick/HEADLINE-seats.txt"; run --all
  ck "R9 좌석 칸 = seats 값 · 나머지 ? · 판정 불가 0" sh -c "s='$(sf alpha)'; grep -qF -- '- A-m0 · 지시 #16 · 좌석 ✻ 08:2x ·' \$s && grep -qF '좌석 ? ·' \$s && ! grep -qF 'seats 파일 없음' \$s"
  return $CASEBAD; }

case_r10() {  # harness = origin/ops/main-base · ① 은 언제나 origin/main 표 · «$FT_HARNESS_ROOT» 폴더 안 생김
  reset; local old; old="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" rm -q design/teams/planner/THREAD-oppa-directives-1793487673-20261101.md design/teams/planner/THREAD-oppa-directives-1793000000-20261020.md; commit r10
  git -C "$R" update-ref refs/remotes/origin/main "$old"; run --all
  ck "R10 harness ② 정상 · ① 은 origin/main 표(그 ref 엔 표 없음) · 루트 폴더 0" sh -c "s='$(sf harness)'; grep -qF -- '- H-m0 · 지시 #16' \$s && grep -qF '| 3 | 15:20 | 전팀 하나 |' \$s && [ ! -e '$R/\$FT_HARNESS_ROOT' ]"
  return $CASEBAD; }

case_r11() {  # 휴면 팀 = 머리 «휴면» 1줄만
  reset; run --all
  ck "R11 휴면 머리 1줄 · 휴면 글자" sh -c "[ \"\$(wc -l < '$(sf sleep)')\" -eq 1 ] && grep -qF '휴면' '$(sf sleep)'"
  return $CASEBAD; }

case_r12() {  # 없는 ref 팀 = 그 팀 ② 만 판정 불가 · 다른 팀 정상
  reset; printf 'alpha\t.\torigin/none\tdesign/teams/alpha/indices\n' >> "$R/.fable-team/state/directive-roots.tsv"; run --all
  ck "R12 alpha ② 판정 불가(git · beta 정상" sh -c "grep -qF '판정 불가(git' '$(sf alpha)' && grep -qF '진행 2장' '$(sf beta)'"
  return $CASEBAD; }

case_r12b() {  # 정상 → 실패 → 정상(카드 그대로) = archive 0줄
  reset; run --all; cp "$R/.fable-team/state/directive-roots.tsv" "$TMP/roots.ok"
  printf 'alpha\t.\torigin/none\tdesign/teams/alpha/indices\n' >> "$R/.fable-team/state/directive-roots.tsv"; run --all
  cp "$TMP/roots.ok" "$R/.fable-team/state/directive-roots.tsv"; run --all
  ck "R12b 실패 회차 archive 0" [ -z "$(ls "$D/.fable-team/state/team-main/alpha/archive" 2>/dev/null)" ]
  return $CASEBAD; }

case_r12c() {  # 정상 A·B → 실패 중 B 완성 → 정상 A = archive B 1줄(기준 파일 · DA③ 안 1)
  reset; run --all; cp "$R/.fable-team/state/directive-roots.tsv" "$TMP/roots.ok"
  printf 'alpha\t.\torigin/none\tdesign/teams/alpha/indices\n' >> "$R/.fable-team/state/directive-roots.tsv"
  git -C "$R" mv design/teams/alpha/indices/진행/A-m1.md design/teams/alpha/indices/완성/A-m1.md; commit r12c; run --all
  cp "$TMP/roots.ok" "$R/.fable-team/state/directive-roots.tsv"; run --all
  local a; a="$D/.fable-team/state/team-main/alpha/archive/STATE-closed-$(date -r $NOW +%Y%m).md"
  ck "R12c archive 1줄 · A-m1" sh -c "[ \"\$(wc -l < '$a')\" -eq 1 ] && grep -qF 'A-m1' '$a'"
  return $CASEBAD; }

for c in case_r1 case_r2 case_r2b case_r3 case_r4 case_r5 case_r5b case_r6 case_r6b case_r7 case_r7b case_r8 case_r9 case_r10 case_r11 case_r12 case_r12b case_r12c; do
  case_ "$c" || BAD=1
done

mutant() {  # mutant <이름> <케이스> <파일> <찾을 글자> <바꿀 글자> — 무변이 대조 통과 + 변이 탐지 = PASS
  rm -rf "$TMP/mut"; mkdir -p "$TMP/mut"
  cp "$BIN/ft_team_main.py" "$BIN/ft_team_main_inputs.py" "$BIN/ft_team_lib.py" "$BIN/ft-team-main.sh" "$TMP/mut/"
  local keep="$BIN"
  BIN="$TMP/mut"; case_ "$2" >/dev/null 2>&1 || { echo "FAIL 무변이 대조 실패(변이 전에도 케이스 실패): $1"; BAD=1; BIN="$keep"; return; }
  python3 - "$TMP/mut/$3" "$4" "$5" <<'PY' || { echo "FAIL 변이 적용 실패: $1"; BAD=1; BIN="$keep"; return; }
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
if sys.argv[2] not in t:
    sys.exit(1)
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
  if case_ "$2" >"$TMP/mut.log" 2>&1; then echo "FAIL 변이 미탐지: $1"; BAD=1; else echo "PASS 변이 탐지: $1"; fi; BIN="$keep"
}

mutant "판정 불가 갈래를 빈 칸으로" case_r2 ft_team_main.py 'return out + [f"판정 불가({e})"]' 'return out'
mutant "판정 불가(꼴 다름) 생략" case_r5 ft_team_main.py 'return "판정 불가(card-assign latest 꼴 다름)", {}' 'return "", {}'
mutant "쓰기 위치를 공용 루트로" case_r1 ft_team_main.py '= data / ".fable-team/state/team-main" / team' '= root / ".fable-team/state/team-main" / team'
mutant "닫힌 줄 archive 생략" case_r7 ft_team_main.py '_archive(folder, now, _baseline(folder / "cards-baseline.tsv"), cur)' 'pass'
mutant "상한 넘으면 잘라 씀" case_r8 ft_team_main.py 'out += list(cur.values())' 'out += list(cur.values())[:MAX_LINES]'
mutant "결정 귀속을 전부 0 으로" case_r6 ft_team_main.py 'mine = len(seen.get(team, ()))' 'mine = 0'

[ "$BAD" -eq 0 ] && echo "ALL PASS r1315 팀 메인 파일 렌더"
exit "$BAD"
