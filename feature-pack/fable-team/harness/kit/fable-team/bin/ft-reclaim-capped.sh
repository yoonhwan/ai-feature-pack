#!/usr/bin/env bash
# ft-reclaim-capped.sh — 회수(ft-resource-reclaim.sh) 호출을 «상한 시간 안에서만» 돌리는 공용 함수 (r921 · DA⑥ r1 W3).
#   쓰는 법:  . ft-reclaim-capped.sh
#             ft_reclaim_capped <결과파일> <명령…>    # rc = 그 명령의 rc · 124 = 상한 초과(프로세스 종료됨) · 출력(stdout+stderr) = <결과파일>
#   왜: 회수가 tmux·git·착지 판정을 부르느라 오래 걸리면 spawn 이 그만큼 멈춘다 — 오빠 2026-10-25 «멈춰 있으면 머할건데».
#       상한을 넘으면 부르는 쪽이 `WARN 회수 시간 초과 — 진행` 1줄을 남기고 그대로 진행한다.
#   상한 = FT_RECLAIM_TIMEOUT_SEC(기본 7) · timeout/gtimeout 이 있으면 그것을, 없으면 직접 재어 종료시킨다(bash 3.2 호환).
#   주의: 종료는 TERM → 0.3초 → KILL. 손자 프로세스까지 확실히 끊으려고 프로세스 그룹을 만들지 않는다(부르는 쪽 셸의 그룹을 건드리면 좌석 세션이 위험하다).
set -uo pipefail
FT_RECLAIM_TIMEOUT_SEC="${FT_RECLAIM_TIMEOUT_SEC:-7}"

ft_reclaim_capped() { # <결과파일> <명령…>
  local out="$1"; shift
  [ -n "$out" ] || return 2
  local lim="$FT_RECLAIM_TIMEOUT_SEC"
  case "$lim" in ''|*[!0-9]*|0) lim=7;; esac
  local to; to="$(command -v timeout || command -v gtimeout || true)"
  if [ -n "$to" ]; then
    "$to" "$lim" "$@" >"$out" 2>&1; local rc=$?
    case "$rc" in 124|137) return 124;; *) return "$rc";; esac
  fi
  ( "$@" >"$out" 2>&1 ) & local pid=$!
  local i=0 n=$((lim * 10))
  while [ "$i" -lt "$n" ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null; sleep 0.3; kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid" 2>/dev/null
  return $?
}
