#!/usr/bin/env bash
# test_card_map_lint_r984.sh — 카드 «## 계약↔시험 대응표» lint(r984) 시험.
#   검사 3(ⓐ 계약마다 시험 ≥ 1 · ⓑ 같은 입력 다른 기대 0 · ⓒ 시험 번호 순서 = 계약 순서) · 날짜 스위치(전 WARN/뒤 REJECT)
#   · 알려진 자기모순 2건(r963 r4 계약 ② ↔ 시험 ⓙ · r899 r3 설계 순서 ≠ 구현 순서)이 구현 전에 잡히는지.
#   실데이터(하네스 대기 카드)는 FT_R984_INDICES 경로(기본 harness-ops 워크트리)가 있을 때만 — 없으면 SKIP.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../kit/fable-team/bin/ft-index-lint.sh"
MOD="$HERE/../bin/ft_card_map_lint.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n ft-index-lint.sh" || bad "bash -n ft-index-lint.sh"
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$MOD" && ok "python ast ft_card_map_lint.py" || bad "python ast"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design/harness/indices src
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > design/TEAMS.md
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\nl2\nl3\n' > src/target.sh
export FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md"
unset FT_CARD_GATE_STRICT_FROM 2>/dev/null || true

# mk <이름> <대응표 절 본문|-> — "-" 면 그 절을 만들지 않는다. 카드 경로를 출력.
mk() {
  local f="$T/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '시험 통과.'
    [ "$2" != "-" ] && { echo "## 계약↔시험 대응표"; printf '%b\n' "$2"; }
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
run()   { ( cd "$T" && bash "$LINT" "$1" 2>&1 ); }
runS()  { ( cd "$T" && FT_CARD_GATE_STRICT_FROM=2025-01-01 bash "$LINT" "$1" 2>&1 ); }   # «스위치 뒤» 모드 — 위반을 REJECT 로 본다
mod()   { ( cd "$T" && python3 "$MOD" "$1" 2>&1 ); }
expect_ok()  { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$rc $(echo "$out"|tr '\n' ';')"; }
expect_rej() { local out rc; out="$(runS "$1")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -qF "$3" && ok "$2" || bad "$2 → rc=$rc $(echo "$out"|tr '\n' ';')"; }
expect_warn() { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -qF "$3" && echo "$out" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$rc $(echo "$out"|tr '\n' ';')"; }

HDR=$'| 계약 | 입력 | 기대 | 시험 |\n|---|---|---|---|'
GOOD="$HDR"$'\n| C1 모순 2건 검출 | 모순 카드 2건 | REJECT 2/2 | 시험 ③ |\n| C2 옛 카드 WARN | 10-01 추가 카드 | WARN 만 | 시험 ④ |'

# ── ⓐ~ⓒ 정상 · 위반 ──
expect_ok  "$(mk map-ok "$GOOD")"                                  "정상 대응표(2계약·입력/기대 열) = OK"
expect_ok  "$(mk map-2col $'| 계약 | 시험 |\n|---|---|\n| C1 대응표만 | 시험 ③ |\n| C2 두번째 계약 | 시험 ④ |')" "입력·기대 열 없는 2열 표도 OK(ⓑ 는 적용 안 함)"
expect_rej "$(mk map-empty "$HDR"$'\n| C1 계약만 | 입력 A | 기대 A |  |')"       "ⓐ 시험 칸 빈 행 = REJECT"  "시험 없음 — 계약마다 시험 ≥ 1"
expect_rej "$(mk map-norow "$HDR")" "표 머리만(계약 행 0) = REJECT" "표 머리만 있고 계약 행 0"
expect_rej "$(mk map-nocol $'| 계약 | 시험결과 |\n|---|---|\n| C1 | ③ |')"       "머리에 «시험» 열 없음 = REJECT" "«계약»·«시험» 열 없음"
expect_rej "$(mk map-nosep '계약 C1 → 시험 ③ (표 아님)')"                       "표 아님(자유 글만) = REJECT" "표 없음"
expect_ok  "$(mk map-info "$HDR"$'\n| C1 a | in | out | 시험 ③ |\n| C2 b | in2 | out2 | 반례 집합 «x» |\n| C3 c | in3 | out3 | 시험 ③ |\n표 밖 메모 한 줄')" "번호 없는 시험 칸·중복 번호·표 밖 글 = 통과(INFO)"

# ── 반례 r1-1: 셀 안 이스케이프 `\|` 는 열 경계가 아니다(DA r1 수용 1) ──
expect_rej "$(mk esc-1 $'| 계약 | 시험 |\n|---|---|\n| C1 A\\|B |  |')" "이스케이프 \| 가 든 빈 시험 칸 = REJECT(ⓐ 안 건너뜀)" "시험 없음"
expect_rej "$(mk esc-2 "$HDR"$'\n| C1 | A\\|B | 성공 | ① |\n| C2 | A\\|B | 실패 | ② |')" "이스케이프 \| 가 든 같은 입력·다른 기대 = REJECT(ⓑ)" "같은 입력 다른 결과"
expect_ok  "$(mk esc-3 $'| 계약 | 시험 |\n|---|---|\n| C1 x\\|y | ① |')" "이스케이프 \| 가 든 정상 표 = OK(셀 안 | 로 읽힌다)"

# ── ⓑ r963 r4 자기모순: 계약 ②«표식 0» ↔ 시험 ⓙ«표식 그대로» (evidence/r963-da6/REWORK-r963-r4.md:27 · :20) ──
R963="$HDR"$'\n| C2 git 호출 실패 → 표식 0 | 루트 탐색 rc128 | 그날 표식 0 + ERROR + 확인 불가 발신 | 시험 ④ |\n| C5 시험 ⓙ 요구 | 루트 탐색 rc128 | 표식 그대로 | 시험 ⓙ |'
expect_rej "$(mk r963r4 "$R963")" "ⓑ r963 r4 모순(같은 입력·다른 기대) 검출" "같은 입력 다른 결과"

# ── r899 r3 = 원문 그대로(REWORK-r899-r3.md:24 · C1→ⓗ·ⓘ · C2→ⓙ · C3→빈 칸) — 잠히는 곳은 ⓐ(C3 시험 없음) 이다 ──
R899="$HDR"$'\n| C1 CAS 교체 | 동시 쓰기 | 교체 0 | ⓗ·ⓘ |\n| C2 잠금 고침 | 빈 잠금 창 | 0건 | ⓙ |\n| C3 tmux 재확인 순서 | 재확인 순서 | CAS 뒤 |  |'
expect_rej "$(mk r899r3 "$R899")" "r899 r3 원문 입력 = BAD rc1(ⓐ C3)" "계약 «C3» 시험 없음"
# ⓒ 는 합성 입력(«시험 순서 역전»)으로 시험한다 — 원문에는 순서 역전이 없다
expect_rej "$(mk order-rev "$HDR"$'\n| C1 CAS 교체 | 동시 쓰기 | 교체 0 | 시험 ⓗ |\n| C2 잠금 고침 | 빈 잠금 창 | 0건 | 시험 ⓙ |\n| C3 tmux 재확인 순서 | 재확인 순서 | CAS 뒤 | 시험 ⓘ |')" "ⓒ 시험 순서 역전(합성) 검출" "시험 순서 ≠ 계약 순서"
expect_ok  "$(mk r899ok "$HDR"$'\n| C1 CAS 교체 | 동시 쓰기 | 교체 0 | 시험 ⓗ |\n| C2 잠금 고침 | 빈 잠금 창 | 0건 | 시험 ⓘ |\n| C3 tmux 재확인 순서 | 재확인 순서 | CAS 뒤 | 시험 ⓙ |')" "같은 3계약·시험 순서만 맞으면 OK(대조군)"
out963="$(runS "$T/r963r4.md")"; rc963=$?; out899="$(runS "$T/r899r3.md")"; rc899=$?
[ $rc963 -eq 1 ] && [ $rc899 -eq 1 ] && ok "알려진 자기모순 2건 검출 2/2 (r963 r4 ⓑ · r899 r3 ⓐ)" || bad "모순 2건 → r963 rc=$rc963 r899 rc=$rc899"

# ── 날짜 스위치: 절 없음 = 새 카드 WARN(전) / REJECT(뒤) · 옛 카드 WARN ──
expect_warn "$(mk none-new -)" "절 없음 · 새 카드 · 스위치 전(기본 2026-10-30) = WARN + rc0" "절 없음: ## 계약↔시험 대응표"
out="$(FT_CARD_GATE_STRICT_FROM=2026-01-01 run "$T/none-new.md")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q '절 없음' && ok "절 없음 · 스위치 뒤(2026-01-01) = REJECT" || bad "스위치 뒤 REJECT → rc=$rc $out"
out="$(FT_CARD_GATE_STRICT_FROM=2026-01-01 run "$T/r963r4.md")"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q '같은 입력 다른 결과' && ok "모순 카드도 스위치 뒤 = REJECT" || bad "모순·스위치 뒤 → rc=$rc $out"
old="$(mk none-old -)"; git add "$old" >/dev/null 2>&1
GIT_AUTHOR_DATE="2026-10-01T09:00:00" GIT_COMMITTER_DATE="2026-10-01T09:00:00" git -c user.email=t@t -c user.name=t commit -qm old >/dev/null 2>&1
expect_warn "$old" "옛 카드(10-01 추가) 절 없음 = WARN + rc0" "절 없음"
expect_warn "$(mk old-map "$R963")" "옛 카드여도 모순표는 WARN(REJECT 0)" "같은 입력 다른 결과"

# ── ⓒ 셀 번호 «전부» 순서 비교(DA r2 수용 ⑤) — 산문 속 번호는 안 센다 ──
expect_rej "$(mk ord-multi $'| 계약 | 시험 |\n|---|---|\n| C1 | ①·③ |\n| C2 | ② |')" "ⓒ «①·③» 뒤 «②» = REJECT(⼀번째 번호만 보면 놓친다)" "시험 3 뒤"
expect_ok  "$(mk ord-prose $'| 계약 | 시험 |\n|---|---|\n| C1 | 칸 ⓐ: 대역 → 통과 |\n| C2 | 칸 ⓑ 성공·거질 3경우 |\n| C3 | 칸 ⓒ |')" "산문 속 번호(«칸 ⓐ: …»)는 순서 비교 제외 = OK(r1000·r706 오탐 0)"

# ── 스위치 값 꼴 오류 = rc3 · 통과 0 (판정기·lint 같은 층) ──
out="$(FT_CARD_GATE_STRICT_FROM=2026-13-99 mod "$T/map-ok.md" 2>&1)"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q '날짜 스위치 꼴 오류' && ok "스위치 꼴 오류(2026-13-99) = rc3" || bad "스위치 꼴 → rc=$rc $out"
out="$(FT_CARD_GATE_STRICT_FROM=abc mod "$T/map-ok.md" 2>&1)"; rc=$?
[ $rc -eq 3 ] && ok "스위치 꼴 오류(abc) = rc3" || bad "스위치 abc → rc=$rc $out"
out="$(FT_CARD_GATE_STRICT_FROM=abc run "$T/map-ok.md" 2>&1)"; rc=$?
[ $rc -eq 3 ] && echo "$out" | grep -q '날짜 스위치 꼴 오류' && ok "lint 도 스위치 꼴 오류 = REJECT · rc3(전 OK rc0)" || bad "lint 스위치 꼴 → rc=$rc $out"
unset FT_CARD_GATE_STRICT_FROM

# ── ft-index-lint.sh 160줄 상한(검사는 새 파일) · kit 짝 cmp0 ──
n="$(wc -l < "$LINT" | tr -d ' ')"
[ "$n" -le 160 ] && ok "ft-index-lint.sh 줄 수 $n ≤ 160" || bad "ft-index-lint.sh $n 줄 > 160"
cmp -s "$MOD" "$HERE/../kit/fable-team/bin/ft_card_map_lint.py" && ok "kit 짝 cmp0 (ft_card_map_lint.py)" || bad "kit 짝 다름"

# ── 실데이터: 하네스 대기 카드 = BAD 0(스위치 전 WARN 만) · 배치 1회 · git log 1회 · 7초 ──
RD="${FT_R984_INDICES:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/indices/대기}"
GW="$T/gitwrap"; mkdir -p "$GW"; RG="$(command -v git)"
printf '#!/bin/bash\ncase " $* " in *" log "*) echo x >> "%s/logcount";; esac\nexec "%s" "$@"\n' "$GW" "$RG" > "$GW/git"; chmod +x "$GW/git"
if [ -d "$RD" ]; then
  ncard=$(ls "$RD"/*.md 2>/dev/null | wc -l | tr -d ' ')
  t0=$(python3 -c 'import time;print(time.time())')
  out="$( ( cd "$T" && PATH="$GW:$PATH" python3 "$MOD" "$RD"/*.md 2>/dev/null ) )"; rc=$?
  t1=$(python3 -c 'import time;print(time.time())')
  el=$(python3 -c "print(f'{$t1-$t0:.2f}')")
  nbad=$(printf '%s\n' "$out" | grep -c $'^BAD\t')
  nwarn=$(printf '%s\n' "$out" | grep -c $'^WARN\t')
  nok=$(printf '%s\n' "$out" | grep -c $'^OK\t')
  nlog=$(wc -l < "$GW/logcount" | tr -d ' ')
  [ "$rc" -eq 0 ] && [ "$nbad" -eq 0 ] && [ "$((nok + nwarn))" -eq "$ncard" ] && ok "실데이터 하네스 대기 ${ncard}장: BAD 0 · WARN ${nwarn} · OK ${nok}" || bad "실데이터 rc=$rc BAD=$nbad OK=$nok WARN=$nwarn (카드 ${ncard})"
  [ "$nlog" = 1 ] && ok "첫 추가일 git log 호출 수 = 1(${ncard}장 한번에)" || bad "git log 호출 수 $nlog (1 이어야 한다)"
  awk -v e="$el" 'BEGIN{exit !(e<=7)}' && ok "배치 판정기 ${ncard}장 경과 ${el}초 ≤ 7초" || bad "배치 판정기 경과 ${el}초 > 7초"
  mkdir -p "$HERE/../evidence/r984"; echo "INFO 배치 판정기 ${ncard}장 경과=${el}초 · git log 호출=${nlog}" >> "$HERE/../evidence/r984/timing.txt"
  # 8초 지연 래퍼(모든 git) → 판정기 7초 상한 → rc3(«판정 불가» 를 WARN 으로 숨기지 않음)
  SW="$T/slowgit"; mkdir -p "$SW"; printf '#!/bin/bash\nsleep 8\nexec "%s" "$@"\n' "$RG" > "$SW/git"; chmod +x "$SW/git"
  out="$( ( cd "$T" && PATH="$SW:$PATH" python3 "$MOD" "$T/map-ok.md" 2>&1 ) )"; rc=$?
  [ "$rc" -eq 3 ] && echo "$out" | grep -q '이력 조회 판정 불가' && ok "git 8초 지연 = 7초 상한 넘음 → rc3 판정 불가(통과 0)" || bad "8초 지연 → rc=$rc $(echo "$out"|tr '\n' ';')"
  # 같은 지연을 lint 로 — 셀 배치가 아니라 판정기 안에서 끊기고, lint 도 «판정 불가» = rc3
  SL="$T/slowlog"; mkdir -p "$SL"; printf '#!/bin/bash\ncase " $* " in *" log "*) sleep 8;; esac\nexec "%s" "$@"\n' "$RG" > "$SL/git"; chmod +x "$SL/git"
  t0=$(python3 -c 'import time;print(time.time())')
  out="$( ( cd "$T" && PATH="$SL:$PATH" bash "$LINT" "$T/map-ok.md" 2>&1 ) )"; rc=$?
  t1=$(python3 -c 'import time;print(time.time())')
  el3=$(python3 -c "print(f'{$t1-$t0:.2f}')")
  [ "$rc" -eq 3 ] && echo "$out" | grep -q '이력 조회 판정 불가' && awk -v e="$el3" 'BEGIN{exit !(e<=12)}' && ok "lint 도 git log 8초 지연 → ${el3}초에 끊고 rc3(전 8.2초 WARN·rc0)" || bad "lint 지연 → rc=$rc ${el3}초 $(echo "$out"|tr '\n' ';')"
  # 사전 파일 정리 — mktemp+trap · 남는 파일 0 · lint 1회에 git log 1회
  before=$(ls "${TMPDIR:-/tmp}"/ft_card_map_dates.* 2>/dev/null | wc -l | tr -d ' ')
  ( cd "$T" && PATH="$GW:$PATH" bash "$LINT" "$RD"/*.md >/dev/null 2>&1 ); nlog2=$(wc -l < "$GW/logcount" | tr -d ' ')
  after=$(ls "${TMPDIR:-/tmp}"/ft_card_map_dates.* 2>/dev/null | wc -l | tr -d ' ')
  [ "$before" = "$after" ] && ok "사전 파일 남음 0 (mktemp+trap EXIT)" || bad "사전 파일 남음 $before→$after"
  [ "$nlog2" = 2 ] && ok "lint 1회 git log 호출 = 1(누적 2 · 첫 실행 1 + 이번 1)" || bad "git log 누적 $nlog2 (2 이어야 한다)"
  # Bash 3.2(/bin/bash) 로 전체 lint — 3.2 구문 오류 0 · 결과 동일(DA r2 수용 ③ 재발 방지)
  RR="$(git -C "$RD" rev-parse --show-toplevel 2>/dev/null || echo "$RD/..")"
  t0=$(python3 -c 'import time;print(time.time())')
  GL="${FT_R984_GOAL_LINES:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin-harness/goal-lines-harness.txt}"
  [ -f "$GL" ] || GL="$T/goal.txt"
  out5="$( ( cd "$RR" && FT_GOAL_LINES_FILE="$GL" bash "$LINT" "$RD"/*.md 2>&1 ) )"
  out32="$( ( cd "$RR" && FT_GOAL_LINES_FILE="$GL" /bin/bash "$LINT" "$RD"/*.md 2>&1 ) )"; rc32=$?
  t1=$(python3 -c 'import time;print(time.time())')
  el2=$(python3 -c "print(f'{$t1-$t0:.2f}')")
  nrej=$(echo "$out32" | grep -c '^REJECT')
  [ "$rc32" -le 1 ] && ! echo "$out32" | grep -qi 'syntax error\|unbound variable' && [ "$out32" = "$out5" ] && ok "/bin/bash 3.2 전체 lint = bash 5 와 같은 출력(구문오류 0 · REJECT ${nrej} · ${el2}초)" || bad "3.2 전체 lint → rc=$rc32 $(echo "$out32" | grep -iE 'syntax|unbound' | head -2 | tr '\n' ';') · bash5 와 같은 출력=$([ "$out32" = "$out5" ] && echo yes || echo no)"
  awk -v e="$el2" 'BEGIN{exit !(e<=60)}' && ok "실데이터 전체 ft-index-lint 경과 ${el2}초(기준 86.4초 · 7초는 배치 판정기 몫)" || bad "전체 lint 경과 ${el2}초 > 60초(기준 86.4초)"
  echo "INFO 실데이터 ${ncard}장 전체 lint 경과=${el2}초 · /bin/bash 3.2 rc=${rc32} (기준 86.4초 · DA r1 실측 · 남은 비용 = 다른 lint 항목 카드당 git 호출 — 범위 밖)" >> "$HERE/../evidence/r984/timing.txt"
else
  echo "SKIP 실데이터 — $RD 없음"
fi

echo "fail=$fail"; [ $fail -eq 0 ]
