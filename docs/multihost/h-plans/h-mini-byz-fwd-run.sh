#!/usr/bin/env bash
# h-mini-byz-fwd-run.sh — mini 시험 서버의 «역방향 포워딩만» 다시 연다(DB 38309 · LLM 8000←이 맥 18703 · STT/TTS 8001). 서버 프로세스는 건드리지 않는다.
#   쓸 때: 서버 health 는 200 인데 mini 의 38309·8000·8001 LISTEN 이 0 일 때(포워딩 ssh 가 죽음 — 2026-10-22 19:2x 실측).
#   이미 살아 있으면 «할 일 없음» 으로 끝난다(재실행 안전).
set -uo pipefail
SHA=4c876d7f47f70da6c4dde8606bd685c059b79cfe KEY_SRC=dotenv ACTION=fwd \
  exec bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/h-mini-byz-server.sh
