#!/usr/bin/env bash
# test_lessons_evolve_r1433.sh — ft-lessons(3계층+락) · ft-evolve(하루 1회 게이트) 동작 반례 (r1433·r1434)
#   1) lessons: init → check rc0 · 상한 초과 add → 자동 SPLIT + .archive 생성 · check rc0 유지 · 락 파일 실재
#   2) evolve: --dry-run 은 파일 변경 0(evolution 폴더 생기지 않는다) · --gate 1회차 기록 · 2회차 SKIP
#   격리: HOME·FT_ROOT 를 임시 폴더로. 실데이터 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export FT_ROOT="$T/pack/.fable-team"; mkdir -p "$FT_ROOT"
mkdir -p "$HOME/.claude/logs" "$HOME/.claude/rules"
printf -- '- [11-01] 전역 다이제스트 더미\n' > "$HOME/.claude/rules/dumb-time-digest.md"
LS="$KIT/ft-lessons.sh"; EV="$KIT/ft-evolve.sh"
fail=0
ck(){ if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 (기대=$3 실제=$2)"; fail=$((fail+1)); fi; }
has(){ case "$1" in *"$2"*) echo 1;; *) echo 0;; esac; }

echo "== lessons =="
out="$(bash "$LS" init 2>&1)"; ck "init rc0" "$?" 0
ck "init 이 상한 3개를 안내" "$(has "$out" 'seat≤2048 team≤4096 global≤2048')" 1
bash "$LS" add seat nano-a "첫 교훈" >/dev/null 2>&1
bash "$LS" add team aifp-ft "팀 교훈" >/dev/null 2>&1
ck "add seat 파일 생성" "$([ -f "$FT_ROOT/state/lessons/seat/nano-a.md" ] && echo 1 || echo 0)" 1
ck "락 파일 생성" "$([ -f "$FT_ROOT/state/lessons/seat/nano-a.md.lock" ] && echo 1 || echo 0)" 1
out="$(bash "$LS" check 2>&1)"; rc=$?
ck "check rc0" "$rc" 0
ck "check 이 3계층을 센다" "$(has "$out" '계층파일=3')" 1

# 상한 초과 → 자동 SPLIT
for i in $(seq 1 40); do bash "$LS" add seat nano-a "상한 초과용 긴 교훈 줄 $i — 자동 분리를 확인하는 문장" >/dev/null 2>&1; done
out="$(bash "$LS" add seat nano-a "마지막" 2>&1)"
sz="$(wc -c < "$FT_ROOT/state/lessons/seat/nano-a.md" | tr -d ' ')"
ck "좌석 LESSONS 상한 준수(≤2048)" "$([ "$sz" -le 2048 ] && echo 1 || echo 0)" 1
ck "archive 파일 생김" "$(ls "$FT_ROOT"/state/lessons/seat/*.archive-*.md >/dev/null 2>&1 && echo 1 || echo 0)" 1
out="$(bash "$LS" check 2>&1)"; rc=$?
ck "분리 뒤 check rc0" "$rc" 0
ck "archive 는 계층 파일로 세지 않는다" "$(has "$out" '계층파일=3')" 1

echo "== evolve =="
before="$(find "$FT_ROOT/state" -name 'evolution' -o -name 'last-run' 2>/dev/null | wc -l | tr -d ' ')"
out="$(bash "$EV" --dry-run 2>&1)"; rc=$?
ck "dry-run rc0" "$rc" 0
ck "dry-run 1줄 형식" "$(has "$out" '학습 후보')" 1
ck "dry-run 파일 변경 0" "$(has "$out" '파일 변경 0')" 1
after="$(find "$FT_ROOT/state" -name 'evolution' -o -name 'last-run' 2>/dev/null | wc -l | tr -d ' ')"
ck "dry-run 이 evolution 폴더를 안 만든다" "$before" "$after"

out="$(bash "$EV" --gate 2>&1)"
ck "gate 1회차 후보 파일" "$([ -f "$FT_ROOT/state/evolution/last-run" ] && echo 1 || echo 0)" 1
out="$(bash "$EV" --gate 2>&1)"
ck "gate 2회차 SKIP" "$(has "$out" 'SKIP')" 1
ck "게이트는 하루 1회만" "$(has "$out" '파일 변경 0')" 1
ck "candidates 파일 1장" "$(ls "$FT_ROOT"/state/evolution/candidates-*.md | wc -l | tr -d ' ')" 1

echo "== ft-issues-daily 게이트 연결 =="
ck "issues-daily 가 evolve --gate 를 부른다" "$(grep -c 'EVOLVE_ARGS=(--gate)\|bash "\$HERE/ft-evolve.sh" "' "$KIT/ft-issues-daily.sh")" 2
ck "exec 로 rc 를 잃지 않는다" "$(grep -c '^exit "\$rc"' "$KIT/ft-issues-daily.sh")" 1

if [ "$fail" = 0 ]; then echo "ALL PASS (lessons 11 · evolve 7 · 연결 2)"; exit 0; fi
echo "FAIL $fail 건"; exit 1
