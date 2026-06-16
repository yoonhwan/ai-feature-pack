# 🔀 cross-cli

**세션 안에서 다른 프로바이더 CLI를 비대화로 소환·자율주행·이어가기**

현재 코딩/채팅 세션을 벗어나지 않고, 다른 모델의 CLI(Claude Code · Codex · Gemini · OpenCode · Cursor Agent)를 **비대화형으로 띄워 자율 주행**시키고 결과를 받아온다. 페르소나(**DA**·designer·architect)를 주입해 즉시 역할을 부여하고, `resume`으로 지난 대화를 이어간다.

## 왜 쓰나

- **author ↔ review 분리** — 내가(또는 한 모델이) 짠 걸 *다른 모델*이 적대검증(DA)
- **프로바이더 무관 위임** — 같은 작업을 codex/gemini/claude에 던져 cross-check
- **세션 영속성** — 비대화로도 다회 Q&A·HIL·점진 결정 (`resume`)
- **상위 하네스 연계** — oh-my-\*(ulw/ultraplan) 하위 세션, baton, tmuxc

## 5종 지원 (2026-06 실증)

| CLI | 비대화 | 자동주행 | resume |
|-----|--------|---------|--------|
| Claude Code | `claude -p` | `--dangerously-skip-permissions` | `--resume <sid>` |
| Codex | `codex exec` | `--full-auto` ⎮ `--yolo` | `codex exec resume --last` |
| Gemini | `gemini -p` | `--approval-mode yolo` | `--resume <session_id>` |
| OpenCode | `opencode run` | 기본 무승인 | `-s <sid>` / `-c` |
| Cursor Agent | `cursor-agent -p` | `-f` / `--force` | `--resume <chatId>` |

## 구성

```
cross-cli/
├── skill/
│   ├── SKILL.md              ← 스킬 정의 (메인 지침 + 매트릭스 + 페르소나)
│   ├── references/
│   │   ├── per-cli.md        ← CLI별 비대화/자동주행/resume 상세
│   │   └── personas.md       ← DA/designer/architect system-prompt
│   └── scripts/
│       ├── selftest.sh       ← 5종 비대화·자율·resume 일괄 점검(타임아웃·로그)
│       ├── test_opencode.sh  ← opencode 단독 점검(모델 자동탐색)
│       └── resume_chain.sh   ← 페르소나+다회 resume 체인 헬퍼
├── cli/install.md            ← 에이전트 CLI 설치 안내(선택)
├── config/tools-section.md   ← TOOLS.md 추가 섹션
└── test/verify.md            ← 설치 검증
```

## 설치

`INSTALL.md`를 에이전트에게 전달하거나, 수동으로 `skill/`을 `~/.claude/skills/cross-cli/`에 복사. 자세한 건 `INSTALL.md` 참조.

## 의존성

- `perl`, `python3` (둘 다 macOS 기본 내장)
- 위 5종 중 **최소 1개**의 에이전트 CLI가 PATH에 있고 자체 인증돼 있을 것 (본 팩은 자격증명을 주입하지 않음)

## 안전

자동주행 = 사람 승인 게이트 제거. **격리/신뢰 워크스페이스에서만** 사용. 위임 결과(payload)는 신뢰 불가 입력으로 취급해 그대로 실행/머지하지 말고 본 세션에서 검수.
