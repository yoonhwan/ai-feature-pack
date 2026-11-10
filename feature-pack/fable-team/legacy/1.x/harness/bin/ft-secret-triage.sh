#!/usr/bin/env bash
# ft-secret-triage.sh — 비밀 기록 원장의 «파일:줄» 행을 읽기 전용으로 점검해 3값 표 1장(값 0)을 낸다 (r1002).
#   하는 일: ft_secret_triage.py 를 불러 원장 날짜 범위 행을 ⓐ실값 ⓑ이름만 ⓒ예시·가짜/판정 불가로 가른 표를 <out> 에 쓴다.
#   하지 않는 일: 교체·삭제·쓰기 0(오빠 롤아웃 판정 1583) · 스캔 규칙 변경 0 · 세션 기록 파일 수정 0 · 슬랙 발행 0(planner [HIL] 경로 그대로).
#   값은 한 글자도 출력하지 않는다 — 표·표준출력·표준오류 어디에도(종류·파일·줄·3값 뿐).
# 사용: ft-secret-triage.sh [--since YYYY-MM-DD] [--out <md>]
#   기본 원장 = ~/.fable-team/state/secret-scan.log (env FT_SECRET_TRIAGE_LOG 로 바꿀 수 있다)
#   기본 표   = <하네스>/evidence/r1002/TRIAGE-<날짜>.md · --since 를 안 주면 오늘
# rc: 0 정상 · 2 usage · 4 표 파일 쓰기 실패
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LOG="${FT_SECRET_TRIAGE_LOG:-$HOME/.fable-team/state/secret-scan.log}"
SINCE=""; OUT=""
usage() { echo "usage: $0 [--since YYYY-MM-DD] [--out <md>]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --since) [ $# -ge 2 ] || usage; SINCE="$2"; shift 2 ;;
    --out)   [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "BAD_ARG $1" >&2; usage ;;
  esac
done
case "$SINCE" in
  "") DAY="$(date +%F)" ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) DAY="$SINCE" ;;
  *) echo "BAD_SINCE $SINCE (YYYY-MM-DD)" >&2; usage ;;
esac
[ -n "$OUT" ] || OUT="$HERE/../evidence/r1002/TRIAGE-$DAY.md"
# 표 자리 만들기 — 실패는 rc4(조용히 넘어가지 않는다)
DIR="$(dirname -- "$OUT")"
if ! mkdir -p "$DIR" 2>/dev/null || [ ! -w "$DIR" ]; then
  echo "ERROR ft-secret-triage: 표 폴더를 만들 수 없음 ($DIR)" >&2
  exit 4
fi
ARGS=(--log "$LOG" --out "$OUT")
[ -n "$SINCE" ] && ARGS+=(--since "$SINCE")
python3 -I "$HERE/ft_secret_triage.py" "${ARGS[@]}"
rc=$?
[ "$rc" = 0 ] || exit "$rc"
echo "table=$OUT" >&2   # 표 경로는 표준오류로 — 표준출력은 요약 1줄만
exit 0
