#!/bin/bash
# fable-team da-live-evidence-gate — PreToolUse 강제 게이트 (DA 라운드 상한 + 라이브증거 필수)
# 목적: 같은 트랙에서 DA 3라운드 초과 진입을 "라이브 스팟 증거(JSONL) 첨부" 없이 물리 차단.
#   근거: BYZ v6 retro §2.3 — DA 16라운드 중 라이브증거 반영 2라운드(12.5%), 나머지는 탁상
#   재정교화. 산문 DA가 못 잡는 결함을 라이브 1회가 즉시 잡는다(실측). 운영규율 #2의 물리화.
# 판정 휴리스틱:
#   활성 트랙 = <proj>/.fable-team/state/ 하위에서 가장 최근 수정된 트랙 디렉토리.
#   그 트랙의 da-round*.md 수가 상한(기본 3) 이상이고, 마지막 라운드 파일 이후 생성/수정된
#   라이브 증거(*.jsonl — 트랙 내)가 없으면 → DA 워커 스폰 deny + "라이브 먼저" 안내.
# 대상 도구: Task | Agent  (settings.json matcher — spawn-route-gate와 동일 지점).
# ★ FAIL-OPEN: 파싱 오류·상태 불명은 전부 허용. deny는 "증거 없는 4라운드+" 확신 케이스만.
#   차단 대상은 DA 스폰뿐 — 구현·테스트·라이브 작업은 어떤 경우에도 막지 않는다(유도 게이트).

set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

DA_MAX_ROUNDS="${FT_DA_MAX_ROUNDS:-3}"

python3 - "$INPUT" "$DA_MAX_ROUNDS" <<'PYEOF'
import json, sys, os, glob, re

def allow():
    sys.exit(0)

def deny(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(2)

try:
    data = json.loads(sys.argv[1])
    max_rounds = int(sys.argv[2])
except Exception:
    allow()

if data.get("tool_name", "") not in ("Task", "Agent"):
    allow()

st = ((data.get("tool_input", {}) or {}).get("subagent_type") or "").strip().lower()
# DA 계열만 대상 (spawn-route-gate가 면제하는 드라이버 중 DA 레인: <prefix>-da / -da2 / -da-cursor 등)
if not re.search(r'-da(2|-[a-z0-9]+)?$', st):
    allow()

proj = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ""
state = os.path.join(proj, ".fable-team", "state")
if not os.path.isdir(state):
    allow()

try:
    # 활성 트랙 = state/ 직하 디렉토리 중 최근 수정
    tracks = [d for d in glob.glob(os.path.join(state, "*")) if os.path.isdir(d)]
    if not tracks:
        allow()
    track = max(tracks, key=os.path.getmtime)
    rounds = sorted(glob.glob(os.path.join(track, "da-round*.md")), key=os.path.getmtime)
    if len(rounds) < max_rounds:
        allow()
    last_round_mtime = os.path.getmtime(rounds[-1])
    # 라이브 증거 = 마지막 DA 라운드 이후 생성/갱신된 트랙 내 *.jsonl
    fresh = [f for f in glob.glob(os.path.join(track, "**", "*.jsonl"), recursive=True)
             if os.path.getmtime(f) > last_round_mtime]
    if fresh:
        allow()
except Exception:
    allow()

deny(
    "🚫 [da-live-evidence-gate] 트랙 '%s' — DA %d라운드 도달, 마지막 라운드 이후 라이브 증거(*.jsonl) 없음.\n"
    "   증거 없는 설계 재정교화(탁상심사)는 차단됩니다(운영규율 #2 — BYZ v6 retro: DA 16R 중 라이브증거 2R).\n"
    "→ 먼저 라이브 스팟을 실행해 증상 관측 JSONL을 트랙 디렉토리에 남기세요. 그 후 DA 재스폰은 통과됩니다.\n"
    "   (상한 조정: env FT_DA_MAX_ROUNDS. 이 게이트는 DA 스폰만 막습니다 — 구현·테스트·라이브는 자유.)"
    % (os.path.basename(track), len(rounds))
)
PYEOF
GATE_RC=$?
[ "$GATE_RC" = "2" ] && exit 2
exit 0
