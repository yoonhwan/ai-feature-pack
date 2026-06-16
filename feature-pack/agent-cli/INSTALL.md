# agent-cli — 설치 가이드 (에이전트용)

에이전트에게: "feature-pack/agent-cli/INSTALL.md 읽고 설치해줘"

## Prerequisites

- `perl`, `python3` (macOS 기본 내장 — 확인만)
- 5종 중 **최소 1개**의 에이전트 CLI 설치·인증: `claude` / `codex` / `gemini` / `opencode` / `cursor-agent`
  (미설치는 자동 SKIP. 설치는 `cli/install.md` 또는 `references/install-and-compare.md`)

## Step 1: 스킬 복사

```bash
mkdir -p ~/.claude/skills/agent-cli/references ~/.claude/skills/agent-cli/scripts
cp SKILL.md            ~/.claude/skills/agent-cli/SKILL.md
cp references/*.md      ~/.claude/skills/agent-cli/references/
cp scripts/*.sh         ~/.claude/skills/agent-cli/scripts/
chmod +x ~/.claude/skills/agent-cli/scripts/*.sh
```

> OpenClaw/다른 에이전트면 스킬 경로만 해당 규약에 맞춘다. SKILL.md는 self-contained.

## Step 2: TOOLS.md 등록 (해당 시)

`config/tools-section.md` 내용을 에이전트 TOOLS.md(또는 동급 카탈로그)에 추가.

## Step 3: (선택) OpenCode 기본 모델

기본값 `opencode/deepseek-v4-flash-free`. 다르면 `export OPENCODE_MODEL=<provider/model>` (목록: `opencode models`).

## Step 4: 검증

```bash
bash ~/.claude/skills/agent-cli/scripts/selftest.sh   # 격리/신뢰 폴더에서
```
`test/verify.md` 체크리스트도 확인.

## Step 5: 사용

세션 중 자동 발동(예): "이 PR codex로 DA 적대검증", "이 설계 제미나이 cross-check", "코덱스한테 리팩토링 시키고 결과만", "아까 세션 resume해서 후속 질문".

수동:
```bash
bash ~/.claude/skills/agent-cli/scripts/resume_chain.sh codex DA "이 diff 적대검증" "지적 우선순위 매겨줘"
```

## 안전

자동주행 플래그(dangerous/full-auto/yolo/force)는 격리/신뢰 워크스페이스 전용. 위임 CLI 자체 인증 필요. 결과는 본 세션 검수 후 사용.
