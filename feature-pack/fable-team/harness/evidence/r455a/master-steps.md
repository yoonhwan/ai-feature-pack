# r455a master-steps — 팩 시험 빨강(루트 3분리·명부 폴더 raise 뒤 픽스처) + `ft-harness-info.sh seats` 판정 불가 = 표시 0 (집행 순서 · master)

카드 `design/harness/indices/진행/r455a-harness-tests-red-root-resolver-fixtures.md` · 나노 byz-harness-nano-r455a-harness-tests-red-root-resolver-fi#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r455a-harness-tests-red-root-resolver-fi` (워크트리 `.worktrees/nano-r455a-harness-tests-red-root` · base ed8e118e = origin/main) | 키트 `ft-harness-info.sh`(bin·kit 짝 cmp0) · 시험 7 파일 픽스처 · `test_autonomy_preflight` 주석 1줄 · CHANGES 1절 · manifest 1.1.23 · 이 파일 · `tests-rc.txt` |
| BYZ-Agents | `nano/r455a-harness-tests-red-root-resolver-fi` | 커밋 0(이 단위는 팩만) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 팩 루트에서 `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash feature-pack/fable-team/harness/tests/test_<이름>.sh` — 결과 = `tests-rc.txt`.
2. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → `cmp <팩>/feature-pack/fable-team/harness/kit/fable-team/bin/ft-harness-info.sh <LIVE_BIN>/ft-harness-info.sh` rc0 · 되돌림 = `.bak-r455a`. `ft-live-install-check.sh --range ed8e118e..<착지 sha>` OK.
3. 실사건 1(설치 뒤 · 라이브 좌석 1의 Bash): comm 없는 git 리포 cwd 에서 라이브 실행본으로 seats —
   `D=<스크래치>; mkdir -p "$D/.fable-team"; git -C "$D" init -q; echo '{"_master":"m#0"}' > "$D/.fable-team/seats-x.json"; (cd "$D" && env -u FT_ROOT -u FT_AGENT_ALIVE_BIN bash <LIVE_BIN>/ft-harness-info.sh seats; echo rc=$?)`
   → 기대: `== 팀 명부 (루트 .fable-team/seats-*.json) ==` + `seats-x.json master=m#0 …` + `rc=0`(옛 판 = `ERROR 라이브 루트를 못 풂 …` rc1). 그 두 줄을 카드 `- 실사건:` 줄에 복붙.
   (나노 사전 관측 = 팩 워크트리 키트 직접 실행: 옛 harness-live 판 rc=1 명부절=0 ERROR=1 · 새 판 rc=0 명부절=1 seats-a줄=1 ERROR=0)
4. r274 카드 실사건 줄(이 단위 `tests-rc.txt` 의 rc0 6줄) → r274 완성 이동. r175 는 아래 ⑦ 판정 뒤.

## 남은 빨강 (이 단위 밖 · 원인 확인됨)
- `test_graphics_install` ⑦ · `test_graphics_690` ⑦: 라이브 `~/.claude/skills/fable-team/references/{main-team-governance,harness-map}.md` 가 staged 판(649·690 …)으로 승격된 적 없음 = 카드 «판정 요청» (master → planner).
- `test_planner_nano_path` 하위 `test_nano_spawn_body_press` → r455b.
- 새 카드 후보 2(base ed8e118e 에서도 rc1): `test_team_literal_paths`(같은 comm 계약 `ERROR comm 폴더 없음 …/r1/.fable-team/comm` + 골 표 정본 `design/planner/AUTONOMY-GOAL-A6-20261018.md` 픽스처 없음) · `test_agent_alive_fg_judge` ⓔ(BYZ 경로 `scripts/fable-team-bin/…`·`tools/comm-canonical/…` 목록 · 팩 이식 누락).

## 편차
- 카드 «시험 6 파일» → 7 파일: `test_planner_nano_path` 가 부르는 `test_nano_team_env` 가 같은 꼴(close 가 r448 뒤 `ft-seat-reap.sh` 를 부르는데 임시 bin 에 없음 · rc127)로 빨강이라 스텁 1줄(`test_seat_close.sh` 와 같은 스텁).
- `test_graphics_install` ⑥ 은 FT_ROOT 만으로 안 풀림 — 뒤에 숨은 2개: 임시 ROOT 에 `origin/main` ref 없음(R400 r3 명단) · 팩엔 `design/graphics/GOAL-graphics.md` 가 없어 `cp` 가 조용히 실패(→ 선언된 정본 없음 REJECT). ref 1줄 + «있으면 복사 · 없으면 설치된 골 3줄로 시험용 GOAL».
- `test_proposal_gate_wiring` 14: FT_ROOT 뒤 create-pair 가 `FT_ME`(보내는 좌석)·`FT_ISSUES_SEATS`(issues 명부)를 요구 — 임시 값으로 줌(기존 단언 그대로).
- 덤: `test_harness_info` base rc2 → rc0(키트 고침).
