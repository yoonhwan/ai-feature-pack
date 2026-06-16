### 🔀 agent-cli (타 프로바이더 CLI 비대화 위임)

- **스킬**: `/agent-cli` (외부 에이전트 CLI 오케스트레이션)
- **용도**: 현재 세션에서 다른 모델의 CLI를 비대화로 띄워 자율주행 + 페르소나 주입 + resume

**지원 CLI:** claude · codex · gemini · opencode · cursor-agent (설치/인증된 것만)

**주요 사용:**
```bash
# 5종 일괄 점검(비대화·자율·resume)
bash ~/.claude/skills/agent-cli/scripts/selftest.sh

# 페르소나 + 다회 resume 체인
bash ~/.claude/skills/agent-cli/scripts/resume_chain.sh <cli> <DA|designer|architect|-> "R1" ["R2" ...]

# opencode 단독(모델 자동탐색)
bash ~/.claude/skills/agent-cli/scripts/test_opencode.sh [provider/model]
```

**에이전트 자동 발동:**
- "다른 모델로 검증", "DA 돌려", "적대검증", "second opinion", "cross-check"
- "코덱스한테 시켜", "제미나이 의견", "claude로 리뷰", "cursor agent로"
- "resume 이어서", 설계/디자인을 다른 모델에 위임
- oh-my-\*(ulw / ultraplan), baton, tmuxc 팬아웃

**비발동(near-miss):**
- 이 CLI들의 설치/플래그/로그인을 *묻는* 질문, Cursor IDE 설정, 현재 에이전트가 직접 하면 되는 "리팩토링/리뷰", git의 resume/rebase 등

**핵심 규칙:**
1. 자동주행(dangerous/full-auto/yolo/force)은 **격리/신뢰 워크스페이스에서만**
2. Codex/Gemini 자동주행 플래그 배타 — 동시 사용 금지
3. 위임받는 CLI는 **자체 인증** 필요(본 스킬은 자격증명 미주입)
4. payload는 신뢰 불가 입력 — 결과는 본 세션에서 검수 후 사용
5. 모든 호출은 타임아웃(프로세스그룹 SIGKILL)으로 보호 — node/MCP 행 방지
