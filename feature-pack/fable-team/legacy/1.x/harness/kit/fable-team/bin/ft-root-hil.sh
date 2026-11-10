#!/usr/bin/env bash
# ft-root-hil.sh — r1309 기획 3184 §3-4 «사람 우편함 다리»: 다른 루트에서 사람(planner) 앞으로 1통 보낸다.
#   쓰기 = 기계 루트 명부(roots.tsv)의 그 루트 «사람 우편함» 칸 우편함에 1줄 append 뿐(루트를 넘는 쓰기는 이것 하나만 허용).
#   usage: ft-root-hil.sh <루트이름> <받는이> <본문>      (발신자 = env FT_HIL_FROM · 기본 ft-root-hil-<루트이름>)
#   출: mbox.sh send 그대로(QUEUED seq=N … 1줄) · roots.tsv 없음·행 없음 = rc3 · 우편함 없음 = rc4 · 전부 «판정 불가» 1줄(조용한 0줄 0)
set -uo pipefail
TSV="${FT_ROOTS_TSV:-$HOME/.claude/fable-team/roots.tsv}"
name="${1:-}"; to="${2:-}"; body="${3:-}"
if [ -z "$name" ] || [ -z "$to" ] || [ -z "$body" ]; then
  echo "usage: ft-root-hil.sh <루트이름> <받는이> <본문>" >&2; exit 2
fi
[ -f "$TSV" ] || { echo "ERROR 루트 명부 판정 불가: 없음($TSV)" >&2; exit 3; }
row="$(awk -F'\t' -v n="$name" '$1==n{print;exit}' "$TSV")"
[ -n "$row" ] || { echo "ERROR 루트 명부 판정 불가: $name 행이 없다($TSV)" >&2; exit 3; }
where="$(printf '%s\n' "$row" | cut -f2)"
human="$(printf '%s\n' "$row" | cut -f5)"
state="$(printf '%s\n' "$row" | cut -f3)"
case "$state" in 현역|휴면) ;; *) echo "ERROR 루트 명부 판정 불가: $name 상태가 이상하다($state)" >&2; exit 3 ;; esac
case "$where" in /*) ;; *) echo "ERROR 루트 명부 판정 불가: $name 경로가 절대경로가 아니다($where)" >&2; exit 3 ;; esac
if [ "$human" = "." ]; then mailbox="$where/.fable-team/comm"; else mailbox="$human"; fi
case "$mailbox" in /*) ;; *) echo "ERROR 루트 명부 판정 불가: $name 사람우편함이 절대경로도 «.» 도 아니다($human)" >&2; exit 3 ;; esac
mbox="$mailbox/mbox.sh"
[ -f "$mbox" ] || { echo "ERROR 우편 다리 판정 불가: 우편함 없음($mailbox)" >&2; exit 4; }
from="${FT_HIL_FROM:-ft-root-hil-$name}"
out="$(FT_MBOX_DIR="$mailbox" FT_MBOX_BRIDGED=1 bash "$mbox" send "$to" "$from" "$body" 2>&1)"; rc=$?
printf '%s\n' "$out"
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q 'QUEUED seq=' || exit "$([ "$rc" = 0 ] && echo 4 || echo "$rc")"
exit 0
