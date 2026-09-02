#!/usr/bin/env bash
# cartier-auto 설치기 — 환경 체크 → (대화형) 확인 → 설치 → 상태 저장
# 사용법:
#   bash install.sh            # 대화형 (환경 체크 후 y로 진행)
#   bash install.sh --yes      # 비대화형 (자동 설치)
#   bash install.sh --check    # 설치/환경 상태만 확인
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${CARTIER_AUTO_SRC:-$INSTALL_DIR}"
DEST_ROOT="$HOME/.local/share/cartier-auto"
DEST="$DEST_ROOT/skill"
STATE_DIR="$HOME/.local/state/cartier-auto"
VENV_DIR="$STATE_DIR/.venv"
INSTALL_FILE="$STATE_DIR/installed.json"
BIN="$HOME/.local/bin"

MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --yes|-y) MODE="yes" ;;
    --check|-c) MODE="check" ;;
  esac
done

# ---------- [0] 환경 사전 체크 ----------
check_env() {
  local ok=0
  echo "== 환경 체크 =="
  # Python 3.11+
  PY=""
  for c in python3.12 python3.11 /opt/homebrew/bin/python3.11 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3 /usr/bin/python3; do
    if command -v "$c" >/dev/null 2>&1 && "$c" --version 2>&1 | grep -qE 'Python 3\.(1[1-9]|[2-9][0-9])'; then
      PY="$c"; break
    fi
  done
  if [ -n "$PY" ]; then
    echo "  [OK] Python: $("$PY" --version 2>&1)"
  else
    echo "  [!!] Python 3.11+ 필요 — 설치 실패"
    ok=1
  fi
  # Google Chrome
  if [ -d "/Applications/Google Chrome.app" ]; then
    echo "  [OK] Google Chrome: /Applications/Google Chrome.app"
  else
    echo "  [!!] Google Chrome 없음 — 실패"
    ok=1
  fi
  # 터미널
  echo "  [OK] 셸: bash $(bash --version | head -1 | grep -oE '[0-9.]+' | head -1)"
  # 기존 설치 상태
  if [ -f "$INSTALL_FILE" ]; then
    echo "  [i] 기존 설치 상태 있음: $(cat "$INSTALL_FILE" 2>/dev/null | grep -oE '"installed": (true|false)' | head -1 || echo '알 수 없음')"
  else
    echo "  [i] 기존 설치 상태 없음 (신규 설치)"
  fi
  # set -e에서 마지막 if(false)가 함수를 조기 종료시키지 않도록 항상 성공 반환 보장
  ok=$((ok))
  return $ok
}

if [ "$MODE" = "check" ]; then
  check_env
  exit 0
fi

check_env || { echo "환경 미충족 — 설치 중단"; exit 2; }

# ---------- [0.5] 대화형 확인 ----------
if [ "$MODE" = "interactive" ]; then
  if [[ -t 0 ]]; then
    read -rp "위 환경에서 cartier-auto를 설치할까요? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES) echo "설치 진행" ;;
      *) echo "설치 취소."; exit 0 ;;
    esac
  else
    echo "(비대화형 환경 — --yes 플래그 없이 진행할 수 없음. --yes로 재실행)" >&2
    exit 1
  fi
fi

# ---------- [1] 패키지 복사 ----------
echo "[1/7] 패키지 복사 → $DEST"
mkdir -p "$DEST"
chmod +x "$SRC_DIR/scripts"/*.sh "$SRC_DIR/scripts/cartier_auto.py" 2>/dev/null || true
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude '.venv' --exclude '__pycache__' --exclude '*.pyc' --exclude '.git' "$SRC_DIR"/ "$DEST"/
else
  rm -rf "$DEST"
  mkdir -p "$DEST"
  cp -R "$SRC_DIR"/* "$DEST"/
fi

# ---------- [2] Python venv ----------
echo "[2/7] Python 3.11+ venv 준비"
mkdir -p "$STATE_DIR"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  "$PY" -m venv "$VENV_DIR"
fi
PYBIN="$VENV_DIR/bin/python"

# ---------- [3] Playwright ----------
echo "[3/7] Playwright 설치 (chromium 채널)"
"$PYBIN" -m pip install --quiet --upgrade pip
"$PYBIN" -m pip install --quiet playwright
"$PYBIN" -m playwright install chromium || echo "  (chromium 다운로드 실패 — 시스템 Chrome 사용 가능)"

# ---------- [4] 바이너리 ----------
echo "[4/7] 바이너리 연결 → $BIN"
mkdir -p "$BIN"
ln -sf "$DEST/scripts/cartier_auto.py" "$BIN/cartier-auto"
ln -sf "$PYBIN" "$BIN/cartier-auto-python"

# ---------- [5] 스킬 경로 ----------
echo "[5/7] 스킬 경로 연결"
mkdir -p "$HOME/.codex/skills" "$HOME/.claude/skills" "$HOME/.claude/commands"
rm -f "$HOME/.codex/skills/cartier-auto" "$HOME/.claude/skills/cartier-auto" "$HOME/.claude/commands/cartier-auto.md"
ln -s "$DEST" "$HOME/.codex/skills/cartier-auto"
ln -s "$DEST" "$HOME/.claude/skills/cartier-auto"
if [ -f "$DEST/commands/cartier-auto.md" ]; then
  ln -s "$DEST/commands/cartier-auto.md" "$HOME/.claude/commands/cartier-auto.md"
else
  echo "  (commands/cartier-auto.md 없음 — 스킵)"
fi

# ---------- [6] 검증 ----------
echo "[6/7] 검증"
"$PYBIN" -m pip show playwright >/dev/null 2>&1 || { echo "playwright 설치 실패" >&2; exit 3; }

# ---------- [7] 설치 상태 저장 ----------
echo "[7/7] 설치 상태 저장 → $INSTALL_FILE"
PY_VER="$("$PYBIN" --version 2>&1)"
CHROME_PATH=""
[ -d "/Applications/Google Chrome.app" ] && CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$(dirname "$INSTALL_FILE")"
cat > "$INSTALL_FILE" <<JSON
{
  "installed": true,
  "version": "1.0.0",
  "installed_at": "$(date -Iseconds)",
  "python": "$PY_VER",
  "chrome": "$CHROME_PATH",
  "skill_dir": "$DEST"
}
JSON

echo "설치 완료."
echo "  다음: cartier-auto doctor --json   (또는) bash $DEST/scripts/run.sh doctor --json"
echo "  자격증명: bash $DEST/scripts/setup-credentials.sh"
echo "  설치 상태: cartier-auto setup"
