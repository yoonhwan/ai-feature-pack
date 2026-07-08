# 🔀 agent-cli

**AI 코딩 에이전트 CLI 툴킷 — 설치·비교 + 비대화 위임 하네스**

AI 코딩 에이전트 CLI(Claude Code · Codex · Gemini · OpenCode · Cursor Agent)의 **설치·인증·비교**부터, 현재 세션 안에서 **다른 모델을 비대화로 소환→자율주행→resume**으로 이어가는 **위임 하네스**까지 한 팩으로 제공한다. 페르소나(**DA**·designer·architect)를 주입해 즉시 역할을 부여한다.

> v2.0 — 기존 `agent-cli`(설치·비교 가이드)에 `cross-cli`의 실행 하네스(스크립트·페르소나·안전·oh-my/baton/tmuxc 연계)를 통합하고, 2026-06 실증으로 4건 오류를 정정.

## 왜 쓰나

- **author ↔ review 분리** — 내가/한 모델이 짠 걸 *다른 모델*이 적대검증(DA)
- **프로바이더 무관 위임** — 같은 작업을 codex/gemini/claude에 던져 cross-check
- **세션 영속성** — 비대화로도 다회 Q&A·HIL·점진 결정 (`resume`)
- **설치·비교·Trust 가이드** — 어떤 CLI를 어떻게 깔고 래핑할지
- **상위 하네스**(선택, 로컬 설치 시) — oh-my-\*(ulw/ultraplan), baton, tmuxc. **미설치면 무시** — 핵심 기능(비대화 위임·페르소나·resume)은 이들 없이도 동작

## 5종 지원 (2026-06 실증 보정)

| CLI | 비대화 | 자동주행 | resume |
|-----|--------|---------|--------|
| Claude Code | `claude -p` | `--dangerously-skip-permissions` | `--resume <sid>` |
| Codex | `codex exec` | `--full-auto` ⎮ `--yolo` | `codex exec resume --last` |
| Gemini | `gemini -p` | `--approval-mode yolo` | `--resume <session_id>` |
| OpenCode | `opencode run` | 기본 무승인 | `-s <sid>` / `-c` |
| Cursor Agent | `cursor-agent -p` | `-f` / `--force` | `--resume <chatId>` |

(+ Aider/Amp/Pi 참고 — `references/install-and-compare.md`)

## 구성

```
agent-cli/
├── SKILL.md                       ← 스킬 정의 (메인 지침 + 매트릭스 + 페르소나)
├── references/
│   ├── per-cli.md                 ← CLI별 비대화/자동주행/resume 상세
│   ├── install-and-compare.md     ← 설치·인증·Trust·래핑 비교·함정
│   └── personas.md                ← DA/designer/architect system-prompt
├── scripts/
│   ├── selftest.sh                ← 5종 비대화·자율·resume 일괄 점검(타임아웃·로그)
│   ├── test_opencode.sh           ← opencode 단독(모델 자동탐색)
│   └── resume_chain.sh            ← 페르소나+다회 resume 체인
├── cli/install.md                 ← 에이전트 CLI 설치 안내
├── config/tools-section.md        ← TOOLS.md 추가 섹션
└── test/verify.md                 ← 설치 검증
```

## 지원 환경

**macOS · Linux · WSL.** 처음이거나 WSL이면 환경 감지부터:
```bash
bash scripts/detect-env.sh   # OS 구분 + 지금 쓸 수 있는 CLI + 설치 힌트 + WSL 주의
```

## 설치

`INSTALL.md`를 에이전트에게 전달하거나, 수동으로 `SKILL.md`+`references/`+`scripts/`를 `~/.claude/skills/agent-cli/`에 복사.

## 의존성

- `perl`, `python3` — macOS 내장 / **WSL·Ubuntu**: `sudo apt install -y perl python3`
- 5종 중 **최소 1개** 에이전트 CLI가 PATH + 자체 인증 (본 팩은 자격증명 미주입)
- WSL 주의: OAuth는 Windows 브라우저로 열림(URL 수동 복붙 가능) · cursor-agent는 없을 수 있음(자동 SKIP) · 작업은 `~/` 안에서

## 안전

자동주행 = 사람 승인 게이트 제거. **격리/신뢰 워크스페이스에서만**. 위임 결과는 신뢰 불가 입력으로 취급해 본 세션에서 검수 후 사용.

## Claude 모델 고정

`resume_chain.sh`는 Claude 호출 시 `CLAUDE_MODEL`과 `CLAUDE_EFFORT` 환경변수를 그대로 전달한다.

```bash
CLAUDE_MODEL=claude-fable-5 CLAUDE_EFFORT=high \
bash scripts/resume_chain.sh claude DA \
  "이 변경을 적대검증해줘" \
  "최종 승인 여부만 다시 말해줘"
```
