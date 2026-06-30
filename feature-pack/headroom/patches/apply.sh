#!/usr/bin/env bash
# 왜 필요한가: PyPI 최신 headroom-ai==0.23.0 은 tree-sitter thread-local fix가
# "빠진 갈래"에서 태깅돼 릴리스됐다(upstream main에는 6/3에 들어갔지만 0.23.0 미포함,
# 0.24.0 미릴리스). 그래서 0.23.0 을 pip 설치하면 ThreadPoolExecutor 워커에서
# tree-sitter Parser(pyo3 unsendable)를 스레드 공유하다 PanicException → 500/400.
# 멱등: 이미 적용됐거나(또는 0.24.0+ 로 이미 thread-local) 이면 건너뛴다.
# 사용:  bash patches/apply.sh  [/path/to/venv/bin/python]
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
    echo "✅ $target_file — 이미 적용됨(또는 0.24.0+) → skip"
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

# transforms 경로 기준이라 패치의 a/headroom/transforms/ prefix를 strip(-p1) → 파일명만 남김
# (패치는 repo-root 기준이므로 -p1 대신 transforms 직접 적용을 위해 경로 보정)
norm_patch() { sed 's#a/headroom/transforms/#a/#; s#b/headroom/transforms/#b/#' "$1"; }
norm_root_patch() { sed 's#a/headroom/#a/#; s#b/headroom/#b/#' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
norm_patch "$PATCH_DIR/0001-code_compressor-thread-local-parser.patch" > "$TMP/0001.patch"
norm_patch "$PATCH_DIR/0002-content_router-empty-output-guard.patch"   > "$TMP/0002.patch"
norm_root_patch "$PATCH_DIR/0003-proxy-file-logging-env-toggle.patch"   > "$TMP/0003.patch"

rc=0
apply_one "$TRANSFORMS"    "$TMP/0001.patch" "code_compressor.py" "_tree_sitter_thread_local" || rc=1
apply_one "$TRANSFORMS"    "$TMP/0002.patch" "content_router.py"  "Empty-output guard"        || rc=1
apply_one "$HEADROOM_ROOT" "$TMP/0003.patch" "proxy/helpers.py"   "file_logging_enabled"      || rc=1

echo "---"
if [ "$rc" -eq 0 ]; then
  echo "🎉 완료. 프록시 재기동 권장: launchctl kickstart -k gui/\$(id -u)/com.headroom.proxy"
  echo "   (0.24.0 릴리스되면 'pip install -U headroom-ai' 후 이 패치 불필요)"
else
  echo "⚠️ 일부 실패 — 위 로그 확인. 버전이 0.23.0 인지 점검: $PYBIN -m headroom --version"
fi
exit "$rc"
