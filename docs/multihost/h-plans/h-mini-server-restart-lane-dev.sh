#!/usr/bin/env bash
# h-mini-server-restart-lane-dev.sh — mini 서버를 «같은 코드(h-mini-byz-server-run.sh 의 sha)·worker 만 c2c 개발 레인(WORKER_LANE=dev)» 으로 다시 올린다. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   2026-10-26 · aifp-multihost-master-claude#4 · v65 arch#313 판정(쪽지 168663): 말풍선 0 이 «worker 레인 차이» 때문인지 «새 코드(3c250223d1)의 FE» 때문인지 가르는 실험 — 같은 코드에서 레인만 바꾼다.
#   하는 일: WORKER_LANE=dev 를 설정하고 h-mini-server-restart-dev.sh 를 그대로 부른다(정지→기동→웹 dev→증거). 그 외 변경 0.
# 사용: bash /tmp/h<N> · DRY=1 → 사전점검만(restart-dev 의 DRY)
set -uo pipefail
export WORKER_LANE=dev
exec bash /Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans/h-mini-server-restart-dev.sh
