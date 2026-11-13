#!/usr/bin/env bash
# ft-autonomy-oppa.sh — approve-merge 의 --oppa-slack 처리 (r1275 · 판정 2904) — ft-autonomy.sh 가 source 한다(단독 실행 금지 · ft-autonomy.sh 200줄 상한 때문에 분리)
#   oppa_parse "$@"  인자에서 --oppa-slack <ts>(숫자.숫자6자리)를 떼어 OPPA · OPPA_SHAS 에 둔다 — 꼴 틀림 = REJECT rc2
#   oppa_gate "$@"   잠금 안 · 쓰기 전: 인자 있음 → ft_oppa_slack_check.py(슬랙 오빠 답글 확인 · 아니면 REJECT rc2) · 인자 없음 → 범위 승인이 «살아 있으면» REJECT rc2(직접 실행·옛 h 재실행 포함 · 범위 없음 = 지금 그대로)
OPPA=""; OPPA_SHAS=()
oppa_parse() {
  while [ $# -gt 0 ]; do case "$1" in
    --oppa-slack) [[ "${2:-}" =~ ^(C[A-Z0-9]{8,12}:)?[0-9]+\.[0-9]{6}$ ]] || { echo "REJECT --oppa-slack 값 꼴 틀림([<채널>:]숫자.숫자6자리): ${2:-없음}" >&2; exit 2; }; OPPA="$2"; shift 2 ;;
    *) OPPA_SHAS+=("$1"); shift ;; esac; done
}
oppa_gate() {
  local st chk
  if [ -z "$OPPA" ]; then
    st="$( . "$HERE/ft-autonomy-scope.sh"; cmd_scope_status 2>/dev/null)"
    [[ "$st" =~ ^\[범위\ 승인\ (S[0-9]+)\ ·\  ]] && { echo "REJECT 범위 승인 ${BASH_REMATCH[1]} 중 approve-merge 는 --oppa-slack <질문 글 ts> 필요(판정 2904)" >&2; exit 2; }
    return 0
  fi
  chk="$(python3 "$HERE/ft_oppa_slack_check.py" "$OPPA" "$@" 2>&1)" || { printf '%s\n' "$chk" >&2; exit 2; }
  printf '%s\n' "$chk" >&2   # 감사 = SLACK-OK <sha> parent=<ts> reply=<ts>
}
