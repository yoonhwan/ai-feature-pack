#!/usr/bin/env bash
# ctx-waste 스모크 — 픽스처로 6개 섹션이 실제로 찍히는지 본다. 네트워크 0.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "  [✗] $*"; exit 1; }
ok()   { echo "  [✓] $*"; }

# 픽스처: 자동 로드 메모리 + 프로젝트 rules
mkdir -p "$TMP/proj/.claude/rules"
printf '# big\n%s\n' "$(python3 -c 'print("가"*6000)')" > "$TMP/proj/.claude/rules/big.md"
printf '# tiny\n한 줄\n' > "$TMP/proj/CLAUDE.md"

OUT="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" 2>&1)"

for sec in "[1] 자동 로드 메모리" "자동 로드 큰 파일" ; do
  case "$OUT" in *"$sec"*) ok "섹션: $sec" ;; *) fail "섹션 누락: $sec" ;; esac
done
case "$OUT" in *"proj/.claude/rules/big.md"*) ok "큰 메모리 파일 탐지" ;; *) fail "메모리 파일 탐지 실패" ;; esac

# JSON 모드
J="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" --json 2>&1)"
python3 - "$J" <<'PY' || fail "JSON 모드"
import json,sys
d=json.loads(sys.argv[1])
assert "memory" in d and "burn" in d and "fixed_prefix_tokens" in d
print("  [✓] JSON 모드: memory %d개 · requests %d" % (len(d["memory"]), d["requests"]))
PY

# 요청 본문 마커 형식
cat > "$TMP/req.log" <<'EOF'
=== REQUEST BODY ===
{"model":"x","messages":[{"content":[{"type":"text","text":"hello"}]}],"system":[{"type":"text","text":"sys"}],"tools":[{"name":"Big","description":"d","input_schema":{"type":"object"}},{"name":"Later","description":"d","defer_loading":true}]}
=== RESPONSE ===
{}
EOF
OUT2="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" --request "$TMP/req.log" 2>&1)"
case "$OUT2" in *"요청 본문 해부"*) ok "요청 본문 파싱" ;; *) fail "요청 본문 파싱 실패" ;; esac
case "$OUT2" in *"비defer 툴 1개"*) ok "defer 구분" ;; *) fail "defer 구분 실패" ;; esac

echo "ctx-waste smoke OK"
