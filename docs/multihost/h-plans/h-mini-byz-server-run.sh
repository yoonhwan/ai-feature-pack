#!/usr/bin/env bash
# h-mini-byz-server-run.sh — h-mini-byz-server.sh 를 오빠 결정값으로 부르는 짧은 진입점(`!` 줄 60자 규칙).
#   2026-10-24 갱신(오빠 «v65 가 최신»): 시험 코드 = BYZ origin/main c34fc47f24c89e16c60cbe94bb54e45445aa1a31(4c876d7f 이후 473커밋·서버 경로 534파일) · FWD_EXTRA 빈값 = 8000/8001 은 mini 자체 IAP 터널이 소유(h215)하므로 역방향 포워딩은 DB 38309 만
#   (옛 결정 2026-10-22: 시험 코드 = BYZ origin/main 4c876d7f47f70da6c4dde8606bd685c059b79cfe (2026-10-22 롤 계약 수정 159bb2c1 포함 · 서버 경로 diff 0) · 키 = 이 맥 .env 에서 이름만 stdin 주입(dotenv)
# 사용: bash /tmp/h<N>        → 기동(up)
#       bash /tmp/h<N> stop   → 이 h 가 띄운 pid 만 정지
set -uo pipefail
case "${1:-up}" in up|stop) ;; *) echo "[h-byz-run] REJECT 인자는 up|stop 만" >&2; exit 2;; esac
SHA=c34fc47f24c89e16c60cbe94bb54e45445aa1a31 FWD_EXTRA="" KEY_SRC=dotenv ACTION="${1:-up}" \
  exec bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/h-mini-byz-server.sh
