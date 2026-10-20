# aifp-worker-master-claude#0 → #1 인계 스냅샷 (2026-10-20 · main 9a7e608e)

> 골 원문(불변)은 발주 본문 첫 3줄에 있다. 이 파일은 «진행»만 적는다.

## 끝난 것 (닫는 증거)
| 단위 | 증거 |
|---|---|
| tmm 0.8.5·0.8.6·0.9.0·0.9.1·0.9.2 (세션 수·프로젝트→팀 트리·pi 표시) | PR #146·#148·#151·#158 · tmm 0.9.2 설치 |
| Pi parity (agent-cli 2.2.0 · tmuxc 0.4.2 · tmm 0.9.1) | PR #151 `6231d988` · agent-cli 설치 2026-10-20(`~/.claude/skills/agent-cli`) |
| ft-nano-spawn 일반화(r543) — 티어는 기본값 공급자 · 검색 나노 기본 pi | PR #159 `9a7e608e` · fable-team 1.1.95 |
| pi 팀장 좌석 `aifp-pi-master-pi#0` (cwd `~/Project/pi-agent-ops/.worktrees/pi-master`) | 인계 도달 REACHED · pi 프로젝트 git init `ccf8605` · op 지침 커밋 `66bc4c6`(pi/master) |
| main 작업 트리 미커밋 정리 | `/tmp/h9003` · 백업 `/tmp/main-dirty-20261020.patch` |
| 검색 도구 pi 연결(perp·searchapi-wrapper) | `~/.agents/skills` 링크 · pi-agent-ops `64dd163` |

## 열린 것
1. **하네스(r543 카드 닫기 · 키트 `ft-nano-spawn.sh` 설치)** — 하네스 master `byz-harness-master-claude#85` 몫. 설치 뒤 `ft-nano-spawn.sh --agent pi --tier search --dry-run` 이 `agent=pi` 인지 실측해 보고(선행: 하네스 알림).
2. **정리 스크립트 `/tmp/h9007`**(`nano-spawn-gen` + `feat/ft-nano-spawn-generalize`) — 오빠 `!` 한 줄 · 「워크트리와 가지는 항상 같이 정리」(메모리 `feedback_cleanup_worktree_and_branch_together`).
3. **구 세션 정리** — `aifp-worker-master-claude`(오빠 판정: 유지) · `aifp-worker-master-claude#0`(이 좌석 · 후계 부팅 보고 뒤 오빠 승인으로 닫기).
4. **pi 상태 판독 갭** — pi 의 HUMAN(인터뷰)·BLOCK(오류) 프롬프트를 아직 판독하지 않음(tmm CLAUDE.md 에 기록) · 오빠 결정 대기(카드로 잡을지).
5. **옛 피커 `tmm`·`tmm-3`(0.9.1)** 이 공유 스캔 캐시를 옛 판정기로 덮어 pi 좌석 상태가 BUSY 로 남음 — 닫기 승인 대기(`tmm-2`=오빠가 보는 0.9.2 는 건드리지 않음).
6. 로컬 전용 아님 — pi 프로젝트 `pi/master` 의 커밋 `66bc4c6`·`64dd163`(main) 은 pi-agent-ops 안에만 있음(원격 없음).

## 하지 말 것 (오빠 결정)
- main 작업 트리: 깨끗(9a7e608e). 그 위에서 직접 작업·커밋 금지(`.worktrees/<브랜치>`).
- 하네스 소유 파일(`fable-team`)은 번호 직렬(1.1.9x) — 먼저 하네스에 묻는다. `skill/scripts/ft-nano-spawn.sh` 사본은 옛 판(319줄 갈라짐)이라 건드리지 않음.
- 브랜치 삭제는 HIL — 정리는 `refs/archive` 이동 뒤 삭제 스크립트(`/tmp/h<N>`)를 오빠 `!` 로.
- 병합은 오빠 `! gh pr merge <N> --repo yoonhwan/ai-feature-pack --merge`(이 리포는 LIVE_ROOT 없어 가드가 막음).

## 함정 (실측)
- 훅 `harness-freeze-gate`: `$변수` 경로·같은 호출에서 만든 경로 «검사 불가» → 절대경로를 글자 그대로, 생성과 사용을 호출 둘로.
- zsh 은 변수를 단어로 안 쪼갠다(`$a` = 한 덩어리) · `=NAME` 은 명령 확장 → bash -c 와 따옴표.
- 시험 임시 tmux 소켓은 짧은 경로(`mktemp -d -t`) · `kill-server` 금지.
- 측정은 임시 폴더에서(속도 측정이 main 루트에 `count_files.sh` 를 만든 사고).
- `git add -A` 금지(훅) — 경로 지정.

## 좌석·쪽지
- 상위 오케 없음 → 오빠께는 이 pane(`[mobile→…]`). 쪽지: `FT_MBOX_DIR=<리포>/.fable-team/comm bash ~/.claude/skills/fable-team/scripts/ft-mbox.sh recv|send` · BYZ 하네스 쪽: `FT_MBOX_DIR=…/BYZ-Agents/.fable-team/comm bash ~/.claude/fable-team/live/1.1.92/bin/ft-mbox.sh`.
- 하네스 master = `byz-harness-master-claude#85`(번호가 바뀐다 — 보내기 전 `ft-harness-info.sh seats`) · pi 팀장 = `aifp-pi-master-pi#0`.
- 부팅 직후: CronCreate 10분 체크 틱(mbox recv + 하위 pane 실측 + 오빠 3줄) · 상태 칸은 pane 실측(쪽지 문장 복사 금지) · 상대 팀을 «대기»할 땐 그 팀 좌석 pane 을 읽는다(멍청한짓 원장 줄 84).
