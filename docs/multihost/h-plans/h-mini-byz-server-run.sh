#!/usr/bin/env bash
# h-mini-byz-server-run.sh — h-mini-byz-server.sh 를 오빠 결정값으로 부르는 짧은 진입점(`!` 줄 60자 규칙).
#   오빠 결정(2026-10-22): 시험 코드 = BYZ main 33335c7a(고정) · 키 = 이 맥 .env 에서 이름만 stdin 주입(dotenv)
# 사용: bash /tmp/h<N>        → 기동(up)
#       bash /tmp/h<N> stop   → 이 h 가 띄운 pid 만 정지
set -uo pipefail
case "${1:-up}" in up|stop) ;; *) echo "[h-byz-run] REJECT 인자는 up|stop 만" >&2; exit 2;; esac
SHA=33335c7a353e09f17cc9048e3989e4e8b5d9a05a KEY_SRC=dotenv ACTION="${1:-up}" \
  exec bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/h-mini-byz-server.sh
