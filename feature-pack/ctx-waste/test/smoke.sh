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
OUTKO="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" --lang ko 2>&1)"

for sec in "[0] Runtime environment" "auto-loaded memory" "total" ; do
  case "$OUT" in *"$sec"*) ok "section: $sec" ;; *) fail "missing section: $sec" ;; esac
done
case "$OUT" in *"proj/.claude/rules/big.md"*) ok "big memory file detected" ;; *) fail "memory detect" ;; esac
case "$OUTKO" in *"실행 환경"*) ok "korean output (--lang ko)" ;; *) fail "--lang ko" ;; esac
case "$OUT" in *"claude"*"codex"*"pi"*"opencode"*"hermes"*"openclaw"*"commandcode"*) ok "7 runtimes listed" ;; *) fail "runtime list" ;; esac

# JSON 모드
J="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" --json 2>&1)"
python3 - "$J" <<'PY' || fail "JSON 모드"
import json,sys
d=json.loads(sys.argv[1])
assert "runtimes" in d and "claude" in d["runtimes"]
assert "memory" in d["runtimes"]["claude"]
print("  [✓] JSON mode: runtimes %d" % len(d["runtimes"]))
PY

# 요청 본문 마커 형식
cat > "$TMP/req.log" <<'EOF'
=== REQUEST BODY ===
{"model":"x","messages":[{"content":[{"type":"text","text":"hello"}]}],"system":[{"type":"text","text":"sys"}],"tools":[{"name":"Big","description":"d","input_schema":{"type":"object"}},{"name":"Later","description":"d","defer_loading":true}]}
=== RESPONSE ===
{}
EOF
OUT2="$("$PKG/bin/ctx-waste" --hours 24 --project "$TMP/proj" --request "$TMP/req.log" 2>&1)"
case "$OUT2" in *"request anatomy"*|*"요청 본문 해부"*) ok "request body parsed" ;; *) fail "request body" ;; esac
case "$OUT2" in *"live tools 1"*) ok "defer split" ;; *) fail "defer split" ;; esac

echo "ctx-waste smoke OK"
