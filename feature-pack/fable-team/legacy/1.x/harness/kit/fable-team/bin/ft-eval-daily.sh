#!/usr/bin/env bash
# ft-eval-daily.sh — 매일 10:00 «오빠와 함께 평가할 1건» 을 뽑아 desk 로 1통 (r1446)
#   오빠 지시 2026-11-06 «매일 평가해보자 오전 10시쯤 나랑 하나씩»
#   하는 일: 큐(state/eval/queue.md)에서 «아직 안 본» 항목 1개 → state/eval/daily-<날짜>.md 1장 → desk 1통.
#   안 하는 일: 자동 수정·자동 승격·삭제 0(읽기 + 1장 쓰기). 하루 1회(멱등: 오늘 파일 있으면 SKIP).
#   측정값은 그날 실측만 붙인다(지어내지 않는다 · 못 재면 «판정 불가» 1줄).
#   exit 0 정상 · 2 usage · 1 큐 없음/쓰기 실패 · 3 판정 불가
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_eval_daily.py" ] || { echo "REJECT ft_eval_daily.py 없음: $HERE"; exit 1; }
command -v python3 >/dev/null || { echo "REJECT python3 없음"; exit 1; }
exec python3 "$HERE/ft_eval_daily.py" "$@"
