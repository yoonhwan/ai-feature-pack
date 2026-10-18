#!/usr/bin/env bash
# ft-op-token.sh — 운영 계정 access_token 을 저장된 cred 로 매번 새로 발급한다 (판정 675).
# 사용: ft-op-token.sh <email> | --init <email> (클립보드 비밀번호 1회) | --list
# 비밀번호는 argv·환경변수로 가지 않는다 — pbpaste 출력을 파이썬 stdin 으로만 넘긴다.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${FT_OP_TOKEN_PYTHON:-python3}"

if [ "${1:-}" = "--init" ]; then
  [ -n "${2:-}" ] || { echo "usage: ft-op-token.sh --init <email>" >&2; exit 2; }
  pbpaste | "$PY" "$HERE/ft_op_token.py" --init "$2"
  rc=${PIPESTATUS[1]}
  printf '' | pbcopy   # 결과와 무관하게 클립보드 비움 (유니버설 클립보드·기록 앱 전파 차단)
  exit "$rc"
fi
exec "$PY" "$HERE/ft_op_token.py" "$@"
