#!/usr/bin/env bash
# h-db-fwd-apply.sh — h1 실제 적용 진입점(`!` 한 줄 규칙). 오빠 승인 3가지(VM 생성 · 방화벽 1 · IAM 조건 1) 뒤에만 쓴다.
#   실제 로직은 h-db-fwd-create.sh (DRY=0). 쓰기 순서·되돌림 4줄·실패 시 중단은 그 스크립트가 한다.
set -uo pipefail
DRY=0 exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/h-db-fwd-create.sh"
