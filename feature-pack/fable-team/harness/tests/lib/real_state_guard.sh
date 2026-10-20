#!/usr/bin/env bash
# real_state_guard.sh — source 전용 · 시험이 «실» 하네스 상태를 바꾸지 않게 (r541 · 파이썬 짝 tests/scripts/real_state_guard.py).
# 사건: test_autonomy_hooks_layout 이 FT_ROOT 없이 BYZ 워크트리 cwd 에서 돌자 ft_data_root ②(cwd 공용 루트 LIVE_ROOT)를
#   따라 실 자율 상태에 on/approve-merge/off 8회(A11~A18). 도구는 그대로 두고 시험 쪽에서 막는다.
# 쓰는 법: 시험 맨 위 1줄 `. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"`
#   guard_begin = ①시험 시작 전 cwd 기준 실 루트 3종(데이터·리포·우편함) 지문 ②git 밖 mktemp -d 로 cd + GIT_CEILING_DIRECTORIES
#   ③같은 시험을 자식으로 다시 돌림(RSG_ACTIVE=1 · 자식의 guard_begin 은 통과) ④guard_end = 지문 비교 → exit.
#   trap 대신 재실행 — 시험 본문의 `trap … EXIT` 를 덮지 않는다. 시험 rc 가 0 이 아니면 그 rc · 지문 FAIL 이면 1.
#   stderr 1줄: `REAL-STATE-GUARD PASS …` / `REAL-STATE-GUARD FAIL 실 상태 바뀜: <파일>` · 실 루트를 못 풀면 PASS «실 루트 없음».
RSG_PY="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../scripts" && pwd)/real_state_guard.py"

guard_begin() {
  [ -n "${RSG_ACTIVE:-}" ] && return 0
  local self tmp snapd rc=0
  self="$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")"
  tmp="$(cd "$(mktemp -d)" && pwd -P)"; snapd="$(mktemp -d)"
  python3 "$RSG_PY" snap --out "$snapd/snap.json" --cwd "$PWD" || { echo "REAL-STATE-GUARD ERROR 지문 못 뜸" >&2; rm -rf "$tmp" "$snapd"; exit 2; }
  ( cd "$tmp" && RSG_ACTIVE=1 GIT_CEILING_DIRECTORIES="$(dirname -- "$tmp")" exec "$BASH" "$self" "$@" ) || rc=$?
  guard_end "$snapd/snap.json" "$rc"
  local grc=$?
  rm -rf "$tmp" "$snapd"
  exit "$grc"
}

# guard_end <지문 파일> <시험 rc> → 시험 rc(0 아니면) · 지문 FAIL 이면 1 · 둘 다 0 이면 0
guard_end() {
  local g=0
  python3 "$RSG_PY" compare "$1" || g=$?
  [ "${2:-0}" -ne 0 ] && return "$2"
  return "$g"
}
