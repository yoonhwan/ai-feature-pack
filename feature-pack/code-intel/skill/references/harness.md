# 하네스별 설치·호출 (claude / codex / opencode / pi / hermes)

## 제네릭 설치 (권장 — 4개 하네스 한 번에)
```bash
~/.claude/skills/code-intel/scripts/install.sh          # 바이너리+심링크+ci+doctor
~/.claude/skills/code-intel/scripts/install.sh --check  # 진단만
```
install.sh 가 감지/처리하는 스킬 루트:
```
정본(실폴더)  ~/.claude/skills/code-intel
심링크        ~/.agents/skills/code-intel           → pi · hermes (claude 공용 루트도 여기)
              ~/.codex/skills/code-intel            → codex
              ~/.config/opencode/skills/code-intel  → opencode
진입점        ~/.local/bin/ci
```
갱신은 정본에서만. 심링크는 `install.sh` 재실행(또는 `ln -sfn`)으로 복구.

## 수동 랜딩 (install.sh 를 못 쓸 때)

```bash
ln -sfn ~/.claude/skills/code-intel ~/.agents/skills/code-intel
ln -sfn ~/.claude/skills/code-intel ~/.codex/skills/code-intel
ln -sfn ~/.claude/skills/code-intel ~/.config/opencode/skills/code-intel
ln -sfn ~/.claude/skills/code-intel/scripts/ci ~/.local/bin/ci
```

## 하네스별 실행 경로
| 하네스 | 스킬 발견 | 셸 실행 | 비고 |
|---|---|---|---|
| **Claude Code** | `~/.claude/skills/*` (자동) | Bash 툴 | Skill 툴로 자동 로드, MCP 불필요 |
| **Codex** | `~/.codex/skills/*` | shell | `~/.codex/config.toml` 에 MCP 등록 불필요 |
| **OpenCode** | `~/.config/opencode/skills/*` | bash | v2.0.32, SKILL.md 포맷 동일(심링크 확인됨) |
| **pi** | `~/.agents/skills/*` | bash 툴 | MCP 설정 자체가 없음 → CLI 래퍼가 정답 |
| **Hermes** | `~/.agents/skills/*` | tool | 게이트웨이 toolset에 bash 있으면 동일 |

## 절대경로 폴백 (PATH 차이 대비)
모든 하네스에서 동일하게 동작하는 유일한 형태:
```bash
ci doctor          # PATH (~/.local/bin/ci 심링크)
~/.agents/skills/code-intel/scripts/ci doctor   # 폴백 (정본으로 심링크됨)
```

## 지침 연결 지점 (프로젝트/전역)
| 파일 | 역할 |
|---|---|
| `~/.claude/CLAUDE.md` | 전역 규칙 — Serena 언급을 code-intel로 |
| `<repo>/CLAUDE.md` | Context Triangulation `[REALITY]` + `## 🔍 Code Intelligence` 섹션 |
| `<repo>/AGENTS.md` | codex/opencode 공용 지침 (있으면 동일 문구) |
| `~/.config/opencode/AGENTS.md` | opencode 전역 지침 |
| `~/.codex/AGENTS.md` (있으면) | codex 전역 |
| `~/.agents/**/SKILL.md` | serena 의존 스킬 문구 치환 |

## SessionStart 훅 주의
기존 훅이 `serena activate_project` 를 호출했다면 **반드시 제거**한다.
code-intel은 사전 활성화가 없다 — 훅이 남아 있으면 죽은 MCP를 계속 치게 된다.
확인: `grep -rn "serena" ~/.claude/settings.json ~/.claude/hooks 2>/dev/null`
