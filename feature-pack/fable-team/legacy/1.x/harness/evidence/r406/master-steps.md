# r406 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r406-spawn-lint-team-roster-from-origin-` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `56abafed`(r403 1.1.8 가지 HEAD · main 미착지). r403 이 먼저 착지해야 이 가지가 r403 위에 그대로 얹힌다(파일 겹침 0 — r403 = ft-mbox.* · r406 = lint·spawn·team-lib + 시험).
   manifest 1.1.9 — 다른 카드가 먼저 1.1.9 를 착지하면 번호를 다음으로(CHANGES 머리·manifest 둘 다).
2. 되돌림 준비(설치 전): 라이브 bin 의 `ft-index-lint.sh` · `ft-nano-spawn.sh` · `ft-team-lib.sh` 3 파일 `cp -p … .bak-r406`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 키트 3 파일 `cmp <키트>/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 닫는 증거(공유 루트 cwd · 쓰기 0): `cd <BYZ>/.worktrees/v6-realtime-live` 에서
   `bash <LIVE_BIN>/ft-nano-spawn.sh design/v65/indices/대기/M7-overlap-e2-late-commit-window.md --dry-run --base origin/main` → `OK … (ledger=design/v65/GOAL-LEDGER-v65.md)` + `PLAN seat=…`
   · 같은 줄 lecture 카드(`design/lecture/indices/대기/L1-room-init-stale-init-retry.md`) → `PLAN seat=byz-lecture-nano-…`(상한 3/3 이면 `FT_TEAMSET=0`). → 카드 `- 실사건:` 줄.

## 관측 (실행→나온 것 · 원문 test.txt)
- 키트 사본으로 공유 루트 cwd dry-run(설치 전): v65 M7 · lecture L1 둘 다 rc0 PLAN · 같은 자리 라이브 bin 1.1.7 은 `ERROR v65 은 팀 명단(TEAMS.md)에 없다 / REJECT … 선언된 정본 없음: /GOAL-LEDGER-v65.md` 그대로(arch#94 재현).
- 새 시험 `test_team_roster_ref.sh` ALL PASS · 옛 3 파일로 돌리면 13 FAIL(변이 확인).
- 픽스처 갱신 7 시험(origin/main ref 없는 임시 리포 = `FT_TEAMS_REF=HEAD` · 발주 README 실재) — 도구 쪽 «명단 못 읽음 = REJECT» 는 그대로.
- `test_nano_spawn_teamset_cap.sh` 는 main(252ce484)·1.1.8 에서도 9 FAIL(픽스처 FT_ROOT·comm 없음 — r385 라이브 루트 뒤) → 픽스처 2줄로 ALL PASS.
- 기존 실패 9 시험(planner_nano_path 3 · team_literal_paths2 13 · cherry_gate 3 · da_hold 1 · graphics_install 6 · penalty_spawn 6 · proposal_wiring 2 · teamset_gitref 4 · tracked_bin_call 25)은 1.1.8 기준선과 FAIL 집합이 같다 — 이 단위가 만든 실패 0.

## 끝선 뒤 카드 (범위 밖 · 손 0)
- `ft-index-lint-install.sh`(lint ⑩ 하네스 카드 판정)는 아직 «카드 워크트리의 design/TEAMS.md» 를 읽는다. 지금 공유 루트엔 옛 명단(harness·planner 행)이 있어 안 막히지만, 명단 파일이 «아예 없는» 워크트리면 `하네스 팀 폴더를 못 풀었다` REJECT. 같은 규칙(`ft_team_has_ref`) 1줄 + lit2 ⓔ 픽스처 — 카드 1장.
- 위 «기존 실패 9 시험» — 이 단위와 무관하지만 빨강 그대로(판정 1395: 기존 RED 도 고치는 단위 필요).
