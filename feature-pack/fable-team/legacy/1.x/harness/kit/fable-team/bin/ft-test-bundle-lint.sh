#!/usr/bin/env bash
# ft-test-bundle-lint.sh — 팀 명부 seats-<팀>.json 의 test_bundle 선언 칸 검사 (C2). 읽기 전용.
#
# 사용: ft-test-bundle-lint.sh <seats-x.json>
#   PASS <파일>             exit 0
#   REJECT <파일>: <사유>    exit 1 (사유 stdout) · 인자·파일 오류 exit 2
#
# 규칙 (SPEC-team-essentials-20261005 §3 명부 행 · MERGED 충돌 ⑫ P9 mode 5값):
#   - 최상위 키 test_bundle 가 객체여야 한다 — 없거나 객체가 아니면 REJECT
#   - mode ∈ press-mic|press-api|press-inject|alt|none — 빈칸·그 밖의 값 REJECT
#   - mode press-* 면 card · seat · open_event 셋 다 비어 있지 않아야 한다
#   - mode alt 면 alt_axes 가 비어 있지 않은 목록이어야 한다
#   - state 가 있으면 open|reported|classified|reopen|pending|closed|closed-retained 중 하나 (reported·classified = C10 ft-bundle-state.sh 전이값)
set -uo pipefail

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: ft-test-bundle-lint.sh <seats-x.json>" >&2; exit 2; }
F="$1"
[ -f "$F" ] || { echo "REJECT $F: 파일 없음" >&2; exit 2; }

python3 - "$F" <<'PY'
import json, sys

path = sys.argv[1]
MODES = ("press-mic", "press-api", "press-inject", "alt", "none")
STATES = ("open", "reported", "classified", "reopen", "pending", "closed", "closed-retained")

def rej(why):
    print(f"REJECT {path}: {why}")
    sys.exit(1)

def blank(v):
    return v is None or (isinstance(v, str) and not v.strip())

try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except ValueError as e:
    print(f"REJECT {path}: JSON 파싱 실패 ({e})", file=sys.stderr)
    sys.exit(2)

if not isinstance(doc, dict) or "test_bundle" not in doc:
    rej("test_bundle 선언 칸 없음")
tb = doc["test_bundle"]
if not isinstance(tb, dict):
    rej("test_bundle 가 객체가 아니다")

mode = tb.get("mode")
if blank(mode):
    rej("test_bundle.mode 빈칸")
if mode not in MODES:
    rej(f"test_bundle.mode '{mode}' 는 {'|'.join(MODES)} 가 아니다")
if mode.startswith("press-"):
    missing = [k for k in ("card", "seat", "open_event") if blank(tb.get(k))]
    if missing:
        rej(f"mode={mode} 인데 빈칸: {', '.join(missing)}")
if mode == "alt":
    axes = tb.get("alt_axes")
    if not isinstance(axes, list) or not [a for a in axes if not blank(a)]:
        rej("mode=alt 인데 alt_axes 가 비어 있다")
state = tb.get("state")
if state is not None and state not in STATES:
    rej(f"test_bundle.state '{state}' 는 {'|'.join(STATES)} 가 아니다")

print(f"PASS {path}")
PY
