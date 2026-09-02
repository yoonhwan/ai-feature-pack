#!/usr/bin/env bash
# cartier-auto 자격증명 설정
# ID는 일반 입력, 비밀번호는 숨김 입력, 0700 디렉터리 + 0600 파일 + 아토믹 저장
set -euo pipefail

CRED_FILE="${CARTIER_AUTO_CREDENTIALS:-$HOME/.config/cartier-auto/credentials.env}"
CRED_DIR="$(dirname "$CRED_FILE")"

mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"

prompt_secret() {
  local label="$1" value=""
  if [[ -t 0 ]]; then
    read -rsp "$label: " value
    echo >&2
  else
    read -r value
  fi
  printf '%s' "$value"
}

echo "cartier-auto 자격증명 설정 (4가지)"
export CARTIER_ID
export CARTIER_PASSWORD
export NAVER_ID
export NAVER_PASSWORD
CARTIER_ID="$(prompt_secret "까르띠에 ID(이메일): ")"
CARTIER_PASSWORD="$(prompt_secret "까르띠에 비밀번호: ")"
NAVER_ID="$(prompt_secret "네이버 아이디: ")"
NAVER_PASSWORD="$(prompt_secret "네이버 비밀번호: ")"

python3 - "$CRED_FILE" << 'PYEOF'
import os, sys
from pathlib import Path

target = Path(sys.argv[1])
target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
keys = ("CARTIER_ID", "CARTIER_PASSWORD", "NAVER_ID", "NAVER_PASSWORD")
values = {k: os.environ.get(k, "") for k in keys}

def quote(value: str) -> str:
    if value and any(c in value for c in " \\\"'#$&()*;<>?[]`|~"):
        return "'" + value.replace("'", "'\\''") + "'"
    return value

lines = ["# cartier-auto 자격증명", ""]
for key in keys:
    lines.append(f"{key}={quote(values[key])}")
tmp = target.with_suffix(".tmp")
tmp.write_text("\n".join(lines) + "\n", encoding="utf-8")
tmp.chmod(0o600)
tmp.replace(target)
os.chmod(target, 0o600)
PYEOF

echo "자격증명 저장 완료: $CRED_FILE"
echo "doctor 재확인: cartier-auto doctor --json"
