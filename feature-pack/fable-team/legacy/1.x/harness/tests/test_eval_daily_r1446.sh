#!/usr/bin/env bash
# test_eval_daily_r1446.sh — 매일 10:00 평가 1건 (오빠 지시 «매일 평가 … 10시쯤 나랑 하나씩»)
#   ① dry-run 파일 변경 0 ② 1회차 = daily-<날짜>.md 1장 + 큐 [x] 표시 ③ 2회차 SKIP ④ 큐 소진 시 순환 ⑤ desk 송신 생략 스위치
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/p/.fable-team" FT_EVAL_NO_SEND=1
mkdir -p "$FT_ROOT"
fail=0
ck(){ if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 (기대=$3 실제=$2)"; fail=$((fail+1)); fi; }
has(){ case "$1" in *"$2"*) echo 1;; *) echo 0;; esac; }

out="$(bash "$KIT/ft-eval-daily.sh" --dry-run 2>&1)"
ck "dry-run rc0" "$?" 0
ck "dry-run 파일 변경 0" "$(has "$out" '파일 변경 0')" 1
ck "dry-run 은 파일을 안 만든다" "$([ -e "$FT_ROOT/state/eval" ] && echo 0 || echo 1)" 1

out="$(bash "$KIT/ft-eval-daily.sh" 2>&1)"
ck "1회차 rc0" "$?" 0
ck "daily 파일 1장" "$(ls "$FT_ROOT"/state/eval/daily-*.md | wc -l | tr -d ' ')" 1
ck "큐 [x] 표시" "$(grep -c '^- \[x\]' "$FT_ROOT/state/eval/queue.md")" 1
ck "오빠께 물을 것 1개" "$(grep -c '^## 오빠께 물을 것' "$FT_ROOT"/state/eval/daily-*.md)" 1
ck "자동 실측 5줄 이상" "$(sed -n '/자동 실측/,/오빠께/p' "$FT_ROOT"/state/eval/daily-*.md | grep -c '^- ' | awk '{print ($1>=5)?1:0}')" 1

out="$(bash "$KIT/ft-eval-daily.sh" 2>&1)"
ck "2회차 SKIP" "$(has "$out" 'SKIP')" 1

# 큐 소진 → 순환
rm -f "$FT_ROOT"/state/eval/daily-*.md
python3 - "$FT_ROOT/state/eval/queue.md" <<'PYQ'
import sys
p=sys.argv[1]
lines=[l.replace('- [ ]','- [x]',1) if l.startswith('- [ ]') else l for l in open(p,encoding='utf-8').read().splitlines()]
open(p,'w',encoding='utf-8').write('\n'.join(lines)+'\n')
PYQ
out="$(bash "$KIT/ft-eval-daily.sh" 2>&1)"
ck "큐 소진 순환" "$(has "$out" '순환')" 1
ck "순환 뒤에도 오늘 1장" "$(ls "$FT_ROOT"/state/eval/daily-*.md | wc -l | tr -d ' ')" 1

if [ "$fail" = 0 ]; then echo "ALL PASS (11)"; exit 0; fi
echo "FAIL $fail 건"; exit 1
