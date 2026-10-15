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
