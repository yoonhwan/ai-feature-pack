# S5 정본 갱신 묶음 — arch#29 초안 (판정 1070·1079 · PLAN-harness-networking r2 f0d974ab20 §3 S5) · master 집행(cp+cmp · Edit) · 설치 시점 = S4 와 같은 묶음(v65·loom·graphics 정지 레디 뒤 또는 warn 로그 7일 0건)

골 원문(GOAL-harness 3줄): 「내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.」「하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.」「메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.」
골의 축: C(업그레이드·반영 — 정본 7곳) · 근원 ①②③⑤ 의 «규칙 문장» 설치.

## A. 완성본 3 (이 폴더 · 라이브 바이트에서 arch 가 고친 것 · master 는 `.bak` → cp → cmp)

| 파일 | 라이브 위치 | 라이브 sha256 앞16(초안 기준) | 바뀐 자리 |
|---|---|---|---|
| `COMM-GUIDE-BOOT.md` | `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` + 키트 `ai-feature-pack/feature-pack/tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md` | `aa31a07120bb41ac` | 13 조항 끝 1문장(옛 이름 REJECT · retire 1명령 · [HIL]·[긴급] 통과) · 16 조항 본문(틱 = `ft-tick-line.sh` 1회 · 할 일 없음 1줄 · UNKNOWN≠0 · 개입 직전 turn 재측정) |
| `main-team-governance.md` | `~/.claude/skills/fable-team/references/main-team-governance.md` + 키트 `scripts/harness-install/fable-team/references/`(있으면) | `8e4898aeb0b3e560` | 머리 판정 줄 1 · §1-1 «수명» 열 + v65 상시 줄 · §2 ① 컨펌 열(인터뷰 종류 머리) · §7 경계 1줄([HIL]/[결정]/[긴급]) · §8 틱 값·불일치 N·_kept 1줄 · §11 신설(팀 수명 = 일감 단위) · §12 신설(planner 로 가는 쪽지) |
| `closeout-policy.md` | `~/.claude/rules/closeout-policy.md` | `58864e59d5c18ca4` | 5 닫기 체크 1줄(ft-team-close 경로 · _kept · 승계 없음) |

적용 전 라이브 sha 가 위 값과 다르면 **cp 하지 않고** arch 에 반송(라이브가 그새 바뀜 → 초안 재생성).

## B. 전역 `~/.claude/CLAUDE.md` — 하드 룰 13 신설 (Edit 1 hunk · 그 뒤 CLAUDE_MASTER_SYNC 2곳 재생성)

하드 룰 인덱스의 12 번 줄 바로 뒤에 추가:
```
13. **최상위 오케 앞 쪽지 = 허용 머리만 · 되돌릴 수 있는 것은 묻지 않는다**: planner(현역 `_master`) 앞 쪽지는 `[결정]`(비가역 · `비가역:`·`선례:`·`선택지:` 3줄)·`[HIL]`(훅 차단·사람 손 · 하드 룰 2 경로 그대로)·`[긴급]`·`[합치기]`(`ft-merge-queue.sh add` 1줄)·`[정지 레디]`·`[완료]`·`[부팅 보고]` 만 — 진행·결과·참고는 상태판(`ft-board`)이 나른다 · 되돌릴 수 있고 사람 손이 안 필요한 것은 팀 master 가 `ft-precedent.sh` 선례로 결정하고 하루 묶음 보고 · 팀 수명 = 일감 단위(상시 = planner·harness·v65 완성 전 · 그 밖은 `ft-team-open`/`ft-team-close`) · 틱 = `ft-tick-line.sh` 1회(「할 일 없음」 1줄로 턴 종료 · UNKNOWN≠0). (2026-10-11 오빠 「그래 … 문제 근원 수정 개선」 판정 1069·1070 · DA 1079 · PLAN-harness-networking-20261011) → fable-team `main-team-governance.md` §11·§12 · BOOT 13·16
```
- 전파 동기화(하드 룰 전파 규칙): 같은 세션에서 `~/.codex/AGENTS.md`(`CLAUDE_MASTER_SYNC:BEGIN v=2026-10-10` → `v=2026-10-12`) · `~/.hermes/SOUL.md`(`v=2026-10-10b` → `v=2026-10-12`) 블록을 하드 룰 인덱스 현행으로 재생성(codex 는 `~/.codex/AGENTS.user.md` 사본도).
- 한도: 전역 CLAUDE.md 지금 34,267B — 이 1줄(+약 700B) 뒤에도 «부팅에서 뺀 절» 이관 규칙은 그대로(한도 위반 시 아카이브 이관은 별건).

## C. 프로젝트 `design/planner/STRUCTURE-main-satellite.md` §2 표 (planner 정본 · v6-realtime-live 워크트리 · Edit 2 hunk)

1. 「개설」 행 «누가» 칸: `planner 발주 → 메인 오케 집행` → `planner 가 \`ft-team-open.sh <팀> …\` 1명령(governance §11) · 확정 사건 = 팀 master 부팅 보고 도달 뒤 \`_master\`·\`_opened\` 쓰기`
2. 「종료」 행 «누가» 칸: `위성 오케 작성 → planner 확인 → 영역 소유 메인 오케 집행` → `위성 오케가 CLOSEOUT 작성·커밋·push → planner 가 \`ft-team-close.sh <팀>\`(①admission: 역할 좌석 전부 jsonl IDLE 포함 → ②정리 → ③4항 검증 · 보존 2 = \`_kept\` · 그 kill 은 HIL 계획)`
(4항 본문·«세션 개수 0 은 종료 조건이 아니다»·검증 사례는 무변경.)

## D. `design/teams/harness/issue-improvement/GUIDE-human-report-20261005.md` §2 말 규칙 끝에 1줄

```
- 인터뷰(AskUserQuestion)는 첫 줄에 종류 머리(`[제안]`·`[이슈]`·`[합치기]`·`[HIL]`·`[긴급]`·`[결정]`) + 링크 1개(제안·이슈·PR — `[HIL]`·`[긴급]` 은 명령 원문 줄로 대신) + `선례:` 줄 + 질문 1개 — 훅 `interview-lint` 가 막는다(governance §12).
```

## E. 설치 순서·되돌림 (master)
1. A 3파일: 라이브 sha 대조 → `.bak-net-<ts>` → cp → cmp 0 → 키트 사본도 같은 바이트(`ft-version.sh check` 로 BOOT sha 갱신 · 키트 커밋은 ai-feature-pack 리포).
2. B: Edit 1 hunk → SYNC 2곳 재생성 → `wc -c`.
3. C·D: planner 워크트리 파일은 planner master 에 relay(planner 소유 정본 · harness 가 직접 쓰지 않음) / D 는 harness 워크트리 Edit.
4. 되돌림 = `.bak` 복원(A·B) · C·D 는 git revert.
5. 닫는 증거(PLAN §8): 정본 7곳 sha + SYNC v=2026-10-12 두 파일 → CLOSEOUT 에 복붙.
