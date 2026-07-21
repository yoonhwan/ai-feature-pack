#!/usr/bin/env bash
# 왜 필요한가: PyPI headroom-ai 를 그대로 pip install 하면 운영에 필요한 결함 수정/
# 기능이 빠져 있다. 이 스크립트가 검증된 패치를 site-packages에 멱등 적용한다.
# 멱등: marker가 이미 있으면(적용됐거나 upstream이 흡수) 건너뛴다.
# 사용:  bash patches/apply.sh  [/path/to/venv/bin/python]
#
# 제거 이력(2026-07-21, headroom-ai 0.32.1 기준):
#   0001 tree-sitter thread-local  → upstream 흡수(0.24.0+ `threading.local()` 반영). 불필요.
#   0003 file-logging off toggle   → 미채택. proxy.log 상시 ON 유지(프록시 레벨 간헐 버그는
#                                    사후 로그가 유일 증거 — 진단 가치 > 60MB rotate 비용).
set -euo pipefail

PYBIN="${1:-${HEADROOM_PYTHON:-$HOME/.headroom-venv/bin/python}}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v "$PYBIN" >/dev/null 2>&1 || { echo "❌ python 없음: $PYBIN  (인자/HEADROOM_PYTHON로 지정)"; exit 1; }

TRANSFORMS="$("$PYBIN" - <<'PY'
import os, importlib.util
spec = importlib.util.find_spec("headroom")
if not spec or not spec.submodule_search_locations:
    raise SystemExit("headroom 미설치")
print(os.path.join(list(spec.submodule_search_locations)[0], "transforms"))
PY
)"
HEADROOM_ROOT="$(dirname "$TRANSFORMS")"
[ -d "$TRANSFORMS" ] || { echo "❌ transforms 디렉토리 못 찾음: $TRANSFORMS"; exit 1; }
echo "🎯 대상: $HEADROOM_ROOT"

apply_one() {
  local base_dir="$1" patch="$2" target_file="$3" marker="$4"
  local target="$base_dir/$target_file"
  [ -f "$target" ] || { echo "⚠️  $target_file 없음 — 건너뜀"; return 0; }
  if grep -qF "$marker" "$target"; then
    echo "✅ $target_file — 이미 적용됨(또는 upstream 흡수) → skip"
    return 0
  fi
  # dry-run 먼저
  if ! patch -p1 --dry-run -d "$base_dir" -i "$patch" >/dev/null 2>&1 \
       && ! ( cd "$base_dir" && git apply --check -p1 "$patch" 2>/dev/null ); then
    echo "❌ $target_file — 패치가 깨끗이 적용 안 됨(버전 불일치 의심). 수동 확인 필요."
    return 1
  fi
  cp "$target" "$target.bak-$(date +%Y%m%d-%H%M%S)"
  ( cd "$base_dir" && git apply -p1 "$patch" 2>/dev/null ) \
    || patch -p1 -d "$base_dir" -i "$patch" >/dev/null
  grep -qF "$marker" "$target" && echo "✅ $target_file — 패치 적용 완료(.bak 보관)" \
    || { echo "❌ $target_file — 적용 후 마커 미발견(실패)"; return 1; }
}

# 패치는 repo-root(a/headroom/…) 기준 → transforms/root 경로에 맞게 prefix 보정
norm_patch() { sed 's#a/headroom/transforms/#a/#; s#b/headroom/transforms/#b/#' "$1"; }
norm_root_patch() { sed 's#a/headroom/#a/#; s#b/headroom/#b/#' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
norm_patch      "$PATCH_DIR/0002-content_router-empty-output-guard.patch"   > "$TMP/0002.patch"
norm_root_patch "$PATCH_DIR/0004-streaming-server-tool-result-sse.patch"    > "$TMP/0004.patch"
norm_root_patch "$PATCH_DIR/0005-prefix-tracker-cc-session-id.patch"        > "$TMP/0005.patch"

rc=0
apply_one "$TRANSFORMS"    "$TMP/0002.patch" "content_router.py"           "Empty-output guard"       || rc=1
apply_one "$HEADROOM_ROOT" "$TMP/0004.patch" "proxy/handlers/streaming.py" "tool_search_tool_result"  || rc=1
apply_one "$HEADROOM_ROOT" "$TMP/0005.patch" "cache/prefix_tracker.py"     "x-claude-code-session-id" || rc=1

echo "---"
if [ "$rc" -eq 0 ]; then
  echo "🎉 완료. 프록시 재기동 권장: launchctl kickstart -k gui/\$(id -u)/com.headroom.proxy"
else
  echo "⚠️ 일부 실패 — 위 로그 확인. 버전: $PYBIN -m headroom --version"
fi
exit "$rc"
