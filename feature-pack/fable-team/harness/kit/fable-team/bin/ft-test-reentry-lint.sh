#!/usr/bin/env bash
# ft-test-reentry-lint.sh <시험 파일…> — r1041: 시험이 «자기 파일을 다시 부르는데» 재진입 표지(환경변수 검사 + exit)를 안 두면 rc3.
#   계기: 2026-10-28 10:4x 나노 r1038 시험 test_da_rounds_three_r1038.sh 의 변이 칸이 자기 파일(BASH_SOURCE)을 다시 불러
#         자식도 변이 칸에 들어가 멈춤 조건 0 재귀 → 사용자 프로세스 상한(kern.maxprocperuid 6000) 도달, 전 좌석 셸이 fork 실패.
#   판정: 한 줄에 (bash|sh|source|.) 호출이 있고 그 «대상» 이 자기 파일일 때(같은 파일 이름이거나 $0·BASH_SOURCE 그 자체),
#         그 앞에 환경변수 표지를 검사하는 exit(같은 줄이거나, 검사문 뒤 곧이어 오는 exit)가 없으면 위반.
#   출력: 위반 = `REENTRY <파일>:<줄>` (파일마다 1줄 · 그 줄들이 첫 줄부터) rc3 · 위반 0 = `OK <파일>` rc0 · 사용법 rc2 · 없는 파일 = `ERROR <파일> 없음 — 판정 불가` rc2
#   범위 밖: «다른 시험 파일» 을 부르는 줄(R4 · 자기 파일만 본다) · 옵션으로 시작하는 호출(bash -c/-n · 그 안의 $0 은 대상 파일이 아니다) · bash -x «자기 파일»(옵션 뒤 자기 호출) · 다른 스크립트를 거친 간접 순환(알려진 한계 — ft-resource-watch 프로세스 수 경보가 받는다)
#   시험 = harness/tests/test_test_reentry_lint.sh (샘플 6 + 변이) · 자기 자신을 다시 부르지 않는다
set -uo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <시험 파일…>" >&2; exit 2; }

PROG='
BEGIN{ hit=0; g=0; pend=0 }
{
  l=$0; sub(/^[ \t]+/,"",l)
  if (l ~ /^#/) next
  # ── 재진입 표지 추적(호출 줄 «앞» 에서만 센다 — 호출 줄을 만나면 그 자리에서 끝난다) ──
  if (l ~ /\$\{?[A-Za-z_][A-Za-z0-9_]*/ && l ~ /(^|[ \t;&|(])(exit|return)([ \t;]|$)/) g=1
  else if (l ~ /\$\{?[A-Za-z_][A-Za-z0-9_]*/ && l ~ /(^|[ \t;&|(])(if|\[|\[\[|test|case)([ \t]|$)/) pend=1
  else if (pend==1 && l ~ /(^|[ \t;&|(])(exit|return)([ \t;]|$)/) { g=1; pend=0 }
  # ── 자기 호출 판정 — «대상이 자기 파일» 일 때만 본다(다른 파일을 부르는 줄 = R4 통과) ──
  if (match(l, /(^|[ \t;&|(])(bash|sh|source|\.)[ \t]+/) && substr(l, RSTART+RLENGTH) !~ /^-/) {
    rest=substr(l, RSTART+RLENGTH)
    if (rest ~ /dirname/ || index(rest, "/") > 0) self = (base != "" && index(rest, base) > 0)
    else self = (rest ~ /\$0([^0-9]|$)/ || rest ~ /BASH_SOURCE/)
    if (self==1 && g==0) { printf "REENTRY %s:%d\n", FILENAME, FNR; hit=1; exit 3 }
  }
}
END{ if (hit==0) printf "OK %s\n", FILENAME; exit (hit?3:0) }
'

RE_LINES=""; OK_LINES=""; rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "ERROR $f 없음 — 판정 불가" >&2; exit 2; }
  o="$(awk -v base="$(basename -- "$f")" "$PROG" "$f")"; arc=$?
  case "$o" in REENTRY*) RE_LINES="${RE_LINES}${o}"$'\n';; *) OK_LINES="${OK_LINES}${o}"$'\n';; esac
  [ "$arc" = 0 ] || rc=3
done
[ -z "$RE_LINES" ] || printf '%s' "$RE_LINES"
[ -z "$OK_LINES" ] || printf '%s' "$OK_LINES"
[ "$rc" = 0 ] || echo "REENTRY 위반 — 그 줄 앞에 표지 검사(환경변수 검사 + exit)를 둔다(자기 파일 재호출 = 무한 재귀 · r1041)" >&2
exit "$rc"
