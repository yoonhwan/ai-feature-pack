#!/bin/bash
# fable-team spawn-route-gate — PreToolUse 강제 게이트 (모델 leak 예방)
# 목적: Agent/Task 도구로 ft 일회성 브레인 워커(architect/analyst/checker/implementer/tester/pm)를
#       스폰하는 것을 물리 차단 → tmuxc(ft-tmux-spawn.sh)로 유도.
#   근거: Agent-tool 워커 스폰이 환경·모델 조합에 따라 세션 모델을 상속(leak)한다(2026-07-12 실측 —
#         fable-5 오케 + Agent-tool → 워커 fable-5). tmuxc는 실제 claude 프로세스라 세대별로 뜨고,
#         ft-tmux-spawn.sh가 스폰 후 message.model 검증(exit 7)까지 수행한다.
#   면제: 장수명 드라이버(da/da2/architect-x/da-cursor/gstack/superpowers/insane-search/ouroboros/
#         omo/perplexity)는 셔틀(외부 CLI가 실브레인) — 드라이버 자체 모델 무관 → 통과.
# 대상 도구: Task | Agent  (settings.json matcher로 지정). 판정: exit 0 허용 / exit 2 deny.
#
# ★ 안전 제1원칙 — FAIL-OPEN: 파싱 오류·환경 이상에서도 exit 0(허용). 훅이 세션을 brick하지 않는다.
# ⚠️ [DA-R2 C2 정직성] 방어층의 한계 — 과장 금지:
#   이 게이트가 fail-open으로 놓친 **Agent/Task 스폰**은 tmuxc를 타지 않으므로 ft-tmux-spawn.sh의
#   사후 message.model 검증(exit 7)을 **받지 못한다**(그 검증은 tmuxc 경로 전용). 즉 Agent 경로의
#   유일한 자동 방어는 이 게이트다 — fail-open으로 놓치면 그 스폰은 미검증으로 통과한다.
#   완화: 이 게이트는 드라이버 외 ft 워커 subagent_type을 최대 폭으로 deny(아래)해 슬립 표면을 줄인다.
#   문서(SKILL.md)의 "전 경로 공통 검증"은 tmuxc/Workflow에 한한 것 — Agent 경로엔 사후검증층이 없다.

set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

python3 - "$INPUT" <<'PYEOF'
import json, sys, re

def allow():   # fail-open / 통과
    sys.exit(0)

def deny(msg): # PreToolUse 차단 (stderr → 안내가 모델에 피드백)
    sys.stderr.write(msg + "\n")
    sys.exit(2)

try:
    data = json.loads(sys.argv[1])
except Exception:
    allow()

tool = data.get("tool_name", "")
if tool not in ("Task", "Agent"):
    allow()

tin = data.get("tool_input", {}) or {}
st = (tin.get("subagent_type") or tin.get("agent_type") or "").strip().lower()
if not st:
    allow()

# 일회성 브레인 워커(leak 위험) = <prefix->{architect|analyst|checker|implementer|tester[2]|pm}.
# 드라이버(da/da2/architect-x/da-cursor/gstack/…)는 이 집합에 없으므로 자동 면제(셔틀).
BRAINS = re.compile(r'^(?:[a-z0-9]+-)?(architect|analyst|checker|implementer|tester2?|pm)$')
m = BRAINS.match(st)
if not m:
    allow()

role = m.group(1)
deny(
    "🚫 [spawn-route-gate] Agent/Task로 일회성 브레인 워커('%s') 스폰은 물리 차단됩니다.\n"
    "   Agent-tool 워커 스폰은 세션 모델을 leak한다(2026-07-12 실측 — 예: fable-5 오케 → 워커 fable-5).\n"
    "→ tmuxc로 스폰하세요: .fable-team/bin/ft-tmux-spawn.sh --agent claude --role %s <옵션>\n"
    "   (드라이버 da/da2/gstack 등 셔틀은 예외. Workflow 부득이 사용 시 스폰 후 message.model hard-stop 검증 필수.)"
    % (st, role)
)
PYEOF
GATE_RC=$?
# python이 exit 2로 deny(메시지는 python이 stderr로 출력). 그 외(0/오류)는 허용(fail-open).
# $(...)로 감싸지 않는다(bash 3.2 heredoc 파싱 버그 회피 — orchestration-gate.sh와 동일 패턴).
[ "$GATE_RC" = "2" ] && exit 2
exit 0
