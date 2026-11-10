# r451 master-steps — op 볼트 develop 강제 홈 훅 (집행 순서 · master)

카드 `design/harness/indices/진행/r451-op-vault-develop-gate-hook-and-doc-line.md` · 나노 byz-harness-nano-r451-op-vault-develop-gate-hook-and-doc-#0

## 가지 2
| 리포 | 가지 | sha | 내용 |
|---|---|---|---|
| ai-feature-pack | `nano/r451-op-vault-develop-gate-hook-and-doc-` (워크트리 `.worktrees/nano-r451-op-vault-develop` · base a77973b0) | 이 파일을 담은 HEAD | 새 `harness/kit/hooks/op-vault-develop-gate.sh` · `install.sh` HOME_HOOKS 1토큰 · `kit/fable-team/templates/settings-hooks.snippet.json` PreToolUse Bash 1항 · 새 `harness/tests/test_op_vault_develop_gate.sh` · CHANGES 1절 |
| BYZ-Agents | `nano/r451-op-vault-develop-gate-hook-and-doc-` (base 643bf03512) | 06e85ded8a | `.claude/skills/byz-keys/SKILL.md` 1줄 · `design/teams/ops/keys/PROCEDURE-key-rotation.md` 머리 1줄(docs/rules/ 에 키 절차 문서 없음 → 카드 지시대로 기존 R277 문서) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 `bash feature-pack/fable-team/harness/tests/test_op_vault_develop_gate.sh` rc0(49 PASS).
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → 출력 `HOOK ~/.claude/hooks/op-vault-develop-gate.sh` · 확인 `cmp <팩>/harness/kit/hooks/op-vault-develop-gate.sh ~/.claude/hooks/op-vault-develop-gate.sh` rc0.
3. 홈 settings.json 등록(`cp ~/.claude/settings.json ~/.claude/settings.json.bak-r451` 뒤) — `hooks.PreToolUse` 에 1항 추가(기존 `tracked-bin-call-gate`·`harness-freeze-gate` 와 같은 꼴):
   `{"matcher": "Bash", "hooks": [{"type": "command", "command": "$HOME/.claude/hooks/op-vault-develop-gate.sh"}]}`
   되돌림 = 이 1항 제거(또는 `.bak-r451` 복원).
4. 실사건 1(설치 뒤 · BYZ 워크트리 좌석 1곳의 Bash 도구): `op item create --vault kskill --title r451-probe` → 훅이 실행 전에 막는다(실제 op 호출 0) · stderr 1줄을 카드 `- 실사건:` 줄에 복붙:
   `REJECT op 볼트 = develop 만 — kskill 은 슬랙 자동화 전용(오빠 10-19) · 꼴: OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op … --vault develop (빠진 것: --vault develop · develop 토큰(OP_SERVICE_ACCOUNT_TOKEN_DEVELOP))`
   (나노 사전 관측 = 훅 파일 직접 실행: BYZ 워크트리·BYZ 공용 루트 cwd rc2 · `~/.hermes`·ai-feature-pack cwd rc0)
5. BYZ 문서 가지 PR → main 착지(master).
6. 착지 뒤 arch 손: tmuxc `COMM-GUIDE-BOOT.md` 23 에 «op 볼트 = develop + develop 토큰 · kskill 0 · 훅이 막음(r451)» 1줄(카드 §정본).

## 전파본(하드 룰 15) 읽기 확인 — 나노 2026-10-19
- `~/.codex/AGENTS.md` CLAUDE_MASTER_SYNC v=2026-10-19 · `1Password|kskill` 2건(반영됨으로 보임).
- `~/.hermes/SOUL.md` 블록 src = «§⛔ 파괴·비가역 작업 HIL 필수» 절 전파본(하드 룰 인덱스 전체가 아님) · `1Password|kskill` 1건 — 하드 룰 15 가 그 블록 범위인지는 master 판단(안 돼 있으면 [HIL] 1줄 · 카드 §4).

## 편차
- BYZ 판별: 카드 «cwd(또는 FT_ROOT) 가 BYZ 리포 안» — 파일 표식(`.fable-team`)은 팩 리포에도 있고, 공용 루트 체크아웃(옛 main)에는 `byz-keys` 가 없어(실측) origin URL `…/byz-agents(.git)` 을 주 판별 · 최상위 `.claude/skills/byz-keys/` 를 보조로 둠.
- `op read`: `--vault` 인자를 받지 않는 명령이라 «모든 `op://` 참조의 볼트 = develop» 으로 검사.
- `op item move` 등 카드 목록 밖 item 하위 명령은 통과(시연 계정 8개 develop 이전 = ops 몫이 막히지 않게).
- `skill/templates/settings-hooks.snippet.json`(쌍둥이)은 base 에서 이미 키트 사본과 달라 손대지 않음.

press 필요: 없음(훅 단위 시험만).
