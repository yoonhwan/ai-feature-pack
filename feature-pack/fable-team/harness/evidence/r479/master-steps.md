# r479 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r479-goal-tick-check-table-roster-from-r` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(22fb0b6a · r478 착지 뒤) 위. ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(병행 가지 충돌 방지) — 착지 순서대로 master 가 다음 번호. 문안 = 아래 «CHANGES 절».
   파일 = bin·kit 짝(cmp 0) 3: `ft-goal-check.sh` · `ft_team_lib.py` · `ft_goal_ledger.py` (+ 시험 새 2 · 기존 시험 픽스처 1).
   `ft_goal_table.py` 는 변경 0 — `planner_dir` 를 그대로 import 해 고친 함수를 탄다(카드 «import 만» 보다 더 적음).
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft-goal-check.sh{,.bak-r479}` · `cp -p <LIVE_BIN>/ft_team_lib.py{,.bak-r479}` · `cp -p <LIVE_BIN>/ft_goal_ledger.py{,.bak-r479}`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>` → 3 파일 `cmp <키트> <LIVE_BIN>` = 0 ·
   루트 comm 쪽 쪽지 가드가 부르는 `ft-goal-table.sh` 경로(`_ft_live_bin`) 가 같은 LIVE_BIN 인지 확인 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 틱 재시작(master 손 · kickstart 1회): goal-tick 을 돌리는 launchd 잡 kickstart.
5. 실사건 1(닫는 증거): `/tmp/ft-tick.log` 의 goal-tick 줄이 `rc=0`(tick quiet) 또는 `rc=3`(REREAD → v65 master 가 --touch) 로 돌아오고 `rc=4` 0 ·
   골 표 쪽지 1통(master·planner 아무 쪽지) 가드 통과 = 골 표 발행 정상 · ★공유 루트·LIVE_ROOT(v6) 의 TEAMS.md 는 옛 판 그대로 둔다(갈아끼우기 0 — 바꿔도 안 바꿔도 같은 결과가 끝선)★.
   v6 TEAMS.md 를 옛 판 그대로 두면 골 표 경로마다 stderr `WARN 체크아웃 명단 … planner 칸이 origin/main 와 다르다` 1줄이 남는다(판정 영향 0 · 사라지게 하려면 v6 명단 갱신 = master 판단 · 갱신해도 결과 동일 = 시험 ⓔ2).
6. 뒤 일(arch 손 · 착지 뒤): `COMM-GUIDE-BOOT.md` 14 자리 규칙 줄에 «goal-check·골 표 원장도 명단 = ref(r479)» · 보드 r475 카드에 «`team_in_ref` 사용» 1줄 · PATHSUBST r477 카드에 «명단 = `team_rows_ref`» 1줄.

## 동작 요약 (카드 §구현 범위 대조)
- 1 `ft_team_lib.py` 추가만: `team_rows_ref(ref="origin/main", repo=None)`(`git -C <repo> show <ref>:design/TEAMS.md` · 7초 · 실패 = `TeamPathError «명단 ref 못 읽음»`) · `team_cands_ref(root, team, ref)`(셸 `ft_team_cands_ref` 와 같은 순서 = 명단 꼴 먼저 · 쌍둥이 뒤 · 꼴3 쌍둥이 0 · 그중 그 루트에 실재하는 폴더만) · `team_in_ref(root, team, ref)`(실재 정확히 1 · 0·2+ = TeamPathError 사유에 후보 전부).
  기존 함수 동작 변경 0 — `team_rows`·`team_root` 의 몸통을 `_rows_text`·`_rel_path` 로 빼서 ref 판이 같은 파서·같은 꼴 규칙을 쓰게 했다(구조 이동만 · 시험 ⓘ + 기존 시험 그대로 통과).
- 2 `ft_goal_ledger.planner_dir`: `team_in(root,"planner")` → `team_in_ref(root, "planner", FT_TEAMS_REF 기본 origin/main)` · 체크아웃 `design/TEAMS.md` 의 planner 칸이 ref 와 다르면 stderr WARN 1줄(판정 영향 0).
- 3 `ft-goal-check.sh`: v65 폴더 = `ft_team_cands_ref` 후보 중 실재 정확히 1 → 체크아웃 파일·`git log` sha(지금과 같음) · 실재 0 → 정본 4파일을 `ft_team_doc_ref` 임시 본문으로 읽고 sha = `git log -1 <ref> -- <명단 꼴 경로>` · 실재 2+ = `ERROR … 후보 2개` exit 4 · ref 못 읽음 = `ERROR … 명단 ref 못 읽음` exit 4 · REJECT exit 4 = cited 문구 검사 + 꼴3 «리포 밖» 만.
  체크아웃 명단의 v65 칸이 ref 와 다르면 WARN 1줄 — ★stderr 끝★에 낸다(틱이 `2>&1` 로 받아 `head -1` 을 요약에 쓰므로 첫 줄이 판정 줄로 남게).

## 편차·범위 밖 (나노 판단 · 근거)
- ① 실재 0 일 때 sha = ref 의 «마지막 커밋 sha»(카드는 «blob sha»): 체크아웃 경로의 sha 가 `git log` 커밋 sha 라, 같은 종류여야 공유 루트가 나중에 따라잡아도 좌석 원장이 헛 REREAD 를 안 낸다.
- ② `ft_goal_table.py` 변경 0(위 1).
- ③ 기존 시험 `test_goal_table_gate.sh` 픽스처 `teams_md()` 가 그 폴더를 git 리포로 만들고 명단 커밋을 `origin/main` 에 둔다 — 새 규칙(명단 = ref)이 바뀐 동작이라 픽스처도 ref 를 갖춰야 한다(단언 변경 0 · 97 통과).
- ④ 틱의 relay 본문 `/tmp/goal-tick.XXXXXX` 는 지금도 지우지 않는다(옛 동작 · 범위 밖) — 새 시험은 자기가 만든 것만 지운다.
- 범위 밖(카드 5): 공유 루트·LIVE_ROOT 체크아웃 갱신 · 보드 수집(r475) · PATHSUBST(r477) · 뉴스 원장 경로(r458 — `ft_news_ledger` 는 `team_rel` 그대로 · 기존 r458 시험 통과로 영향 0 확인).

## 시험
- 새 `bash harness/tests/test_goal_check_ref.sh` → 21 passed rc=0 (ⓐ 8 · ⓑ 3 · ⓒ 1 · ⓓ 3 · ⓔ 4 · 600/300 1 · 가짜 tmux = `export -f`(틱이 PATH 앞에 homebrew 를 붙여도 함수가 먼저) · 가짜 mbox).
- 새 `python3 -m pytest harness/tests/scripts/test_team_lib_ref.py` → 9 passed (ⓕ 2 · ⓖ 1 · ⓗ 5 · ⓘ 1).
- 기존: `test_goal_table_gate.sh` 97 passed rc0 · `test_harness_root.sh` 74 rc0 · `test_tick_shim_guard.sh` 26 rc0.
- ★기존 RED(origin/main 22fb0b6a 에서도 같은 실패 · 이 가지 무관 · 같은 워크트리에서 변경을 걷어 실측)★ — 고침 단위 따로 필요(master 판단):
  `test_team_literal_paths.sh` 6 F · `test_team_literal_paths2.sh` 18 F · `test_team_move_roundtrip.sh` 3 F · `test_team_tick_unify.sh` 1 F ·
  pytest 15 F(`test_ft_weekly_review.py` 13 = «리포 공용 루트를 못 풂 — cwd 가 .fable-team/ 있는 git 리포 아님» · `test_ft_tick_passes_shellcheck` · `test_repo_original_finds_kit_folder`).
- py_compile 3 · bash -n 1 · ruff 0 · `ft-tmp-trap-lint.sh` PASS 2 · 짝 cmp 0 3.

## CHANGES 절 (착지 번호를 붙여 머리에)
### <버전> — r479 골 읽기 판정기·골 표 원장도 «명단 = ref origin/main · 폴더 = 그 루트에 실재»
- `ft-goal-check.sh` 가 v65 폴더를 체크아웃 `design/TEAMS.md` 가 아니라 ref 명단(`FT_TEAMS_REF` · 기본 origin/main)으로 풀고, 그 루트에 실재하는 후보 1개를 쓴다(0개 = ref 본문 · 2개+ = ERROR). 공유 루트에 명단 파일이 없어 v65 master 에 매 틱 REJECT(rc=4)가 가던 일이 끝난다.
- `ft_goal_ledger.planner_dir`(골 표 원장 · 쪽지 가드 · 뉴스 골 표) 도 같은 규칙 — LIVE_ROOT 의 명단을 새 판으로 갈아도 옛 판 그대로여도 같은 원장을 찾는다.
- `ft_team_lib` 에 ref 판 3(`team_rows_ref` · `team_cands_ref` · `team_in_ref`) — 셸 `ft_team_cands_ref` 와 같은 규칙 · 기존 함수 동작 그대로.
