#!/usr/bin/env bash
# ft-budget.sh [jsonl] [--gate N] [--prefix N]   (r1430)
#   지금 이 좌석의 «남은 작업 공간»을 한 줄로 낸다. 팀장 [정리] 줄에 그대로 붙인다.
#   핵심 = 게이트(경고선)에서 프리픽스와 현재 대화를 뺀 나머지. 새로 증류하면 이 값이 크게 돌아온다.
#   출력 = `여유 82% (246k/300k) · 새 시작 권장` 또는 `여유 17% (50k/300k) · 증류 권장` · rc 는 항상 0
#   값 출처 = ft-thresholds.sh(게이트) · transcript 마지막 usage(ctx) · 메인 프리픽스 기본 48600
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
for _t in "$HERE/ft-thresholds.sh" "$HOME/.claude/fable-team/thresholds.env"; do
  [ -f "$_t" ] || continue
  case "$_t" in *.env) set -a; . "$_t"; set +a;; *) eval "$(bash "$_t" --export 2>/dev/null)" || true;; esac
  break
done
GATE="${FT_DISTILL_WARN:-300000}"; PREFIX=48600; F=""
while [ $# -gt 0 ]; do case "$1" in
  --gate) GATE="$2"; shift 2;; --prefix) PREFIX="$2"; shift 2;; -*) shift;; *) F="$1"; shift;; esac; done
if [ -z "$F" ]; then
  # r1435: codex 좌석은 ~/.codex/sessions 의 rollout 을 본다(claude jsonl 아님)
  F="$(ls -t "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -1)"
fi
[ -n "$F" ] && [ -f "$F" ] || { echo "여유 ? (transcript 없음)"; exit 0; }
case "$F" in *.codex*|*rollout-*) PYSRC=codex;; *) PYSRC=claude;; esac
python3 - "$F" "$GATE" "$PREFIX" "$PYSRC" <<'PY'
import json, sys
path, gate, prefix, src = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
ctx = 0
if src == "codex":
    try:
        for line in open(path, encoding="utf-8", errors="ignore"):
            if "token_usage_record" not in line: continue
            try: d = json.loads(line)
            except ValueError: continue
            u = (d.get("payload") or {}).get("usage") or {}
            if not u: continue
            c = (u.get("input_tokens") or 0) + (u.get("cache_write_input_tokens") or 0)
            if c: ctx = c
    except OSError:
        print("여유 ? (읽기 실패)"); sys.exit(0)
    room = max(0, gate - ctx)
    pct = 100.0 * room / gate if gate else 0
    advice = "새 시작 권장" if pct >= 60 else ("증류 준비" if pct >= 30 else "증류 권장")
    print("여유 %.0f%% (%dk/%dk) · %s · codex" % (pct, room // 1000, gate // 1000, advice))
    sys.exit(0)
try:
    for line in open(path, encoding="utf-8", errors="ignore"):
        if '"usage"' not in line: continue
        try: d = json.loads(line)
        except ValueError: continue
        u = (d.get("message") or {}).get("usage") or {}
        if not u: continue
        cc = u.get("cache_creation") or {}
        c = (u.get("cache_read_input_tokens") or 0) + (cc.get("ephemeral_1h_input_tokens") or 0) \
            + (cc.get("ephemeral_5m_input_tokens") or 0) + (u.get("input_tokens") or 0)
        if c: ctx = c
except OSError:
    print("여유 ? (읽기 실패)"); sys.exit(0)
if not ctx:
    print("여유 ? (usage 없음)"); sys.exit(0)
room = max(0, gate - ctx)
pct = 100.0 * room / gate if gate else 0
advice = "새 시작 권장" if pct >= 60 else ("증류 준비" if pct >= 30 else "증류 권장")
print("여유 %.0f%% (%dk/%dk) · %s" % (pct, room // 1000, gate // 1000, advice))
PY
