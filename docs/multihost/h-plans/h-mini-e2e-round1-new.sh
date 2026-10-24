#!/usr/bin/env bash
# h-mini-e2e-round1-new.sh — 러너 1회차를 «새 회차(NEW=1)» 로 시작하는 짧은 진입점(`!` 줄 한 줄 규칙). 실제 로직은 h-mini-e2e-round1-run.sh.
#   2026-10-24 · aifp-multihost-master-claude#3 · 오빠 결정 «mini 웹 dev 교체» 뒤(h302 rc=0) 첫 정식 회차 — 마이크 1회 press → STT 최종본 1건
# 사용: bash /tmp/h<N>          → 새 회차 시작(press 1회)
#       DRY=1 bash /tmp/h<N>    → 사전점검까지만(쓰기 0 · 러너 시작 안 함)
#       ACTION=stop bash /tmp/h<N> → 도는 회차 정지
set -uo pipefail
NEW=1 exec bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/h-mini-e2e-round1-run.sh
