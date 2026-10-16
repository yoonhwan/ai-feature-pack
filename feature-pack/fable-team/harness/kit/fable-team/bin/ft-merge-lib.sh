#!/usr/bin/env bash
# ft-merge-lib.sh — 병합·랜딩 도구 공용 함수 (R230 · source 전용 · 7초 룰 판정 666)
#   fm_t7 <명령…>            : 시도당 timeout 7 초 + 재시도 1 (총 14 초 상한) — timeout 도구 없으면 rc 127 (조용한 통과 0)
#   fm_fetch <repo> <remote> <ref> : fm_t7 로 한 ref 만 받는다
fm_timeout_bin() { command -v timeout || command -v gtimeout; }
fm_t7() {
  local tb rc=0 i; tb="$(fm_timeout_bin)" || { echo "timeout/gtimeout 없음 — 7초 상한을 걸 수 없어 외부 호출 거절" >&2; return 127; }
  for i in 1 2; do "$tb" 7 "$@" && return 0; rc=$?; done
  return "$rc"
}
fm_fetch() { fm_t7 git -C "$1" fetch --quiet "$2" "$3"; }
#   fm_flag_off_new <repo> <옛> <새> : R239 랜딩 직후 «새로 생긴 기본 꺼짐 플래그» 줄 출력 — 출력만(rc 항상 0 · 실패는 WARN 1줄 · 로컬 git 만 읽는다)
FM_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fm_flag_off_new() {
  local tb out rc; tb="$(fm_timeout_bin)" || { echo "WARN flag-off 검사 실패 timeout 도구 없음"; return 0; }
  out="$("$tb" 7 python3 "$FM_HERE/ft_flag_off.py" --repo "$1" --new-between "$2" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then [ -z "$out" ] || printf '%s\n' "$out"; else echo "WARN flag-off 검사 실패 rc=$rc $(printf '%s' "$out" | tail -n1)"; fi
  return 0
}
