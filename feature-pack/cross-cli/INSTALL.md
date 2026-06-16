# cross-cli — 설치 가이드 (에이전트용)

이 파일을 에이전트에게: "feature-pack/cross-cli/INSTALL.md 읽고 설치해줘"

## Prerequisites

- `perl`, `python3` (macOS 기본 내장 — 확인만)
- 아래 5종 중 **최소 1개**의 에이전트 CLI가 설치·인증돼 있을 것:
  `claude` / `codex` / `gemini` / `opencode` / `cursor-agent`
  (미설치 CLI는 자동으로 SKIP된다. 설치는 `cli/install.md` 참조 — 선택)

## Step 1: 스킬 복사

```bash
mkdir -p ~/.claude/skills/cross-cli/references ~/.claude/skills/cross-cli/scripts
cp skill/SKILL.md                ~/.claude/skills/cross-cli/SKILL.md
cp skill/references/*.md         ~/.claude/skills/cross-cli/references/
cp skill/scripts/*.sh            ~/.claude/skills/cross-cli/scripts/
chmod +x ~/.claude/skills/cross-cli/scripts/*.sh
```

> OpenClaw/다른 에이전트면 스킬 디렉토리만 해당 에이전트 규약에 맞게 바꾼다(예: `~/.config/opencode` 스킬 경로). SKILL.md 자체는 self-contained.

## Step 2: TOOLS.md / AGENTS.md 등록 (해당 시)

`config/tools-section.md` 내용을 에이전트의 TOOLS.md(또는 동급 도구 카탈로그)에 추가.

## Step 3: (선택) 자동주행 기본 모델 확인

OpenCode를 쓰면 유효 provider/model이 필요하다. 기본값은 `opencode/deepseek-v4-flash-free`.
다르면 환경변수로: `export OPENCODE_MODEL=<provider/model>` (목록: `opencode models`).

## Step 4: 검증

```bash
# 설치된 CLI만 점검 (미설치는 SKIP). 격리/신뢰 폴더에서 실행 권장.
bash ~/.claude/skills/cross-cli/scripts/selftest.sh
```
`test/verify.md`의 체크리스트도 함께 확인.

## Step 5: 사용

세션 중 다음처럼 트리거된다(예시):
- "이 PR codex로 DA 적대검증 받아줘"
- "이 설계 제미나이 의견도 cross-check"
- "코덱스한테 이 리팩토링 비대화로 시키고 결과만 받아와"
- "아까 그 검토 세션 resume해서 후속 질문 더"

수동 호출:
```bash
# 페르소나 + 다회 resume 체인
bash ~/.claude/skills/cross-cli/scripts/resume_chain.sh codex DA "이 diff 적대검증" "지적사항 우선순위 매겨줘"
```

## 안전 규칙

자동주행 플래그(dangerous/full-auto/yolo/force)는 **격리/신뢰 워크스페이스에서만**. 위임받는 CLI의 자체 인증 필요(본 팩은 자격증명 미주입). 결과는 본 세션에서 검수 후 사용.
