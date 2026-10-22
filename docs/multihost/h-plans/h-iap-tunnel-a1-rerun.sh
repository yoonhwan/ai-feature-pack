#!/usr/bin/env bash
# h-iap-tunnel-a1-rerun.sh — h3(rc=5) 재실행: SA·바인딩은 이미 있다(REUSE=1) · 키 개인 부분은 이전 실행이 지워서 새 키가 필요(ROTATE=1).
#   이전 실행에서 발급된 사용자 키(미사용)는 이 스크립트가 지우지 않는다 — 폐기는 사람 승인(HIL). 키 ID 는 h-A1 이 «키 장부» 로 출력한다.
set -uo pipefail
REUSE=1 ROTATE=1 exec bash "$(dirname "$0")/h-iap-tunnel-a1.sh"
