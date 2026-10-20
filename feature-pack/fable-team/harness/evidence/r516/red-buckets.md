# r516 — 하네스 시험 «밖 RED» 원인 묶음표 (셸 62 · pytest 104)

- 바탕: 팩 origin/main `9af3b78a`(r509 착지 판) · `ft-scratch-repo.sh` 사본 · nice 15 · 직렬 · GIT_* env 0 · 외부 호출 0
- 원문: 셸 `before-shell-rc.txt`(253개 · 실패 62) · pytest `before-pytest-tail.txt`(104 failed, 1748 passed, 2 skipped)
- 셈 단위: 셸 = 시험 파일 1개 · pytest = 시험 함수 1개. 한 셸 시험에 원인이 둘이면 «부분»으로 두 묶음에 적는다(FAIL 줄 수로 나눔).
- r509 SAME 62 와 대조: 같은 62개 중 61개 일치 · `test_wt_clean_two_stage` 는 이번 RED(부하 timeout · r509 은 재실행 rc0) · `test_inbox_watch` 는 이번 PASS(r509 RED) — 둘 다 부하 흔들림(⑧).
- 고침 꼴: 시험 = 시험 파일만 · 픽스처 = 픽스처 파일만 · 도구 = harness/bin+kit 짝 · 환경 = 실행 조건 · 결정 = arch 판단 필요(시험 자리·대상이 BYZ 냐 팩이냐)

## 묶음표

| # | 묶음 | 시험 수 | 대표 실패 원문 1줄 | 원인 한 줄 | 고침 꼴 | 상태 |
|---|---|---|---|---|---|---|
| ① | slack 수신 시험 KIT 경로 이중 `harness/harness/kit` | pytest 79 | `ImportError … test_byz_slack_mbox_inbound.py … ModuleNotFoundError: No module named 'mirror_questions'`(단독 실행) · 전체 실행에선 같은 파일 44+35 FAILED | r386 tests/scripts 이전 때 `KIT = HERE.parents[1]/"harness"/kit/slack-mirror` — 팩에선 parents[1] 이 이미 `harness/` | 시험 | **이 카드에서 고침**(2줄) |
| ② | BYZ `tests/fixtures` 미이관(팩 픽스처 두 자리 `harness/fixtures`·`fable-team/tests/fixtures` 로 갈림) | 셸 9 + pytest 1 | `FAIL 유예 주석 + 경로 없음 → REJECT(파일:행·줄 복사) → rc=2 usage: git diff A...B \| ft-deferral-lint.sh …`(test_deferral_lint) | BYZ `tests/fixtures/{deferral,issue_classify,issue_close,seat_request,mbox_guard,magazine}` 이 팩으로 안 옮겨짐 · team_literal_paths 는 goal_table 사본이 다른 자리 | 픽스처 | **이 카드에서 고침**(BYZ 6c22cefe01 그대로 88파일 + 가려 있던 2건) |
| ③ | 공용 루트·comm·팀 명단 전제(r459 `ft_comm_dir` LIVE_ROOT 끊음 · `ft_repo_root` cwd `.fable-team` · ref TEAMS.md) | 셸 15 + pytest 19 | `ERROR comm 폴더 없음: <T>/repo/.fable-team/comm (공용 루트 · LIVE_ROOT 는 보지 않는다)`(test_teamset_gitref) | 시험의 임시 리포에 `.fable-team/comm`·`design/TEAMS.md` 가 없거나 FT_ROOT 를 안 줌 — 도구가 r459·r385b 뒤 그 자리를 «필수» 로 바꿈 | 시험(임시 루트에 comm·명단 · FT_ROOT) | 카드화 후보 |
| ④ | BYZ 리포 전용 파일 전제(`.claude/skills·hooks·settings.json` · `scripts/git-hooks·server` · `.github` · `shared/config` · 실 `design/TEAMS·TEAMSET` · BYZ 커밋 sha) | 셸 16(+deferral 부분) | `FAIL list rc=0 (기대 '0' 실제 '127')`(test_byz_keys_ledger · `$HERE/../../.claude/skills/byz-keys` 없음) | 시험 대상이 팩 도구가 아니라 BYZ 리포 파일 — 팩 사본엔 대상 자체가 없다 | 결정(시험을 BYZ 리포로 되돌릴지 · env 로 BYZ 체크아웃을 줄지) | arch 판단 |
| ⑤ | 옛 BYZ 배치 경로 기대(`scripts/fable-team-bin` · `scripts/harness-install` · `tools/comm-canonical`) | 셸 6 | `FAIL bash -n <S>/feature-pack/fable-team/scripts/fable-team-bin/mbox-v2.sh`(test_mbox_v2_guard) | r385 배치 이동(harness/bin · harness/kit/fable-team/bin) 뒤 시험 기대·복사 자리가 옛 경로 | 시험 | 카드화 후보 |
| ⑥ | 시험 임시 bin 짝 누락(도구가 형제 파일 source 를 늘림) | 셸 5 | `<T>/live/.fable-team/bin/ft-autonomy.sh: 줄 16: <T>/live/.fable-team/bin/ft-harness-root.sh: No such file or directory`(test_autonomy_hooks_layout) | 임시 bin 에 도구 1개만 복사 — `ft-harness-root.sh`·`ft-team-lib.sh`·`ft_da_hold_gate.py`·모듈 짝이 빠짐(r509 tick_line 과 같은 꼴) | 시험 | 카드화 후보 · **r515 가 닿음**(ft-autonomy·ft-team-lib) 2개 |
| ⑦ | 홈·라이브 실물 대조(실 `~/.claude` 정본·설치본 내용을 기대) | 셸 6 | `FAIL ① 홈 BOOT sha=e3d462c58051abbd — 기준 329582414d727dd5 도 스테이징(aa31a07120bb41ac)도 아님(그사이 다른 판정이 바꿈)`(test_r66_codex_serena_boot) | 시험이 실 홈 파일의 «그때» sha·문구를 대조 — 홈이 바뀌면 영구 RED | 시험(대조 사본 고정) 또는 결정 | 카드화 후보 |
| ⑧ | 낡은 대조·환경·개별 | 셸 5 + pytest 5 | `AssertionError: origin/main 판이 이미 고친 판 — 대조 기준 아님`(test_seat_turn_batch) | 대조 기준이 origin/main 을 따라감 · 러너 nice 상속 · 부하 timeout · 도구 결함 후보 1 | 시험·환경·도구(개별) | 개별 카드 |

## 묶음별 시험 이름

- ①(pytest 79): `test_byz_slack_mbox_inbound.py` 44 · `test_inbound_humans_and_install.py` 35
- ②(10): 셸 `test_boot_report_gate` · `test_deferral_lint`(부분 32/66 — 나머지 34 = ④) · `test_ft_wt_sweep_route_timeout` · `test_issue_classify` · `test_issue_close_canon` · `test_mbox_guard` · `test_mbox_lineage` · `test_seat_request` · `test_team_literal_paths`(부분 2/6 — 나머지 4 = ③) · pytest `test_magazine_doc_three::test_real_ledger_rows_sum_and_nothing_lost`
  - 가려 있던 실패 2(픽스처를 넣자 드러남 · 같은 시험 안이라 같이 고침): `test_mbox_guard` R320 3건 = ⑥ 꼴(`ft-spawn-hold.sh` 가 형제 `ft-harness-root.sh` source) · `test_issue_close_canon` ⑧ 1건 = ③ 꼴(`ft-close-reason-check.sh` 가 `--repo` 없이 cwd 리포를 공용 루트로)
- ③(34): 셸 `test_cherry_gate_identical_head` · `test_flag_off_scan` · `test_ft_land` · `test_penalty_spawn_gate` · `test_resource_gate` · `test_resource_gate_pressure` · `test_seat_handover` · `test_teamset_gitref` · `test_live_install_check_tip` · `test_team_scaffold_empty_template` · `test_team_move_roundtrip` · `test_proposal_card` · `test_press_role_bts_gate` · `test_sheet_verify` · `test_spawn_gate_landing_branch`(identical_head 연쇄) · (`test_team_literal_paths` 나머지 4) · pytest `test_ft_weekly_review.py` 13 · `test_disk_census.py` 6(명부 env `FT_SEATS_JSON` 전제 · 추정)
- ④(16): `test_autonomy_core`(`shared/config/external_call.py`) · `test_byz_keys_ledger` · `test_byz_keys_usage` · `test_key_change_gate`(`design/ops/keys/usage`) · `test_goal_hook_adoption_archive` · `test_goal_hook_merge`(`scripts/git-hooks/v65-goal-commit-msg.sh`) · `test_issue_forms`(`.github/ISSUE_TEMPLATE`) · `test_loom_tunnel_install`(`scripts/server/loom_dsn.sh`) · `test_nano_spawn_body_press`(`.gitignore` node_modules) · `test_planner_nano_path`(앞 시험 연쇄) · `test_orch_gate_master`(BYZ sha `43eb52ed632a`) · `test_orch_gate_top_models`(PROJ 훅) · `test_regress_pack`(BYZ `tests/regression/issue_pack.jsonl` 실물) · `test_settings_lint`(리포 `.claude/settings.json`) · `test_team_upgrade` · `test_teamset_check`(실 `design/TEAMS.md`·`TEAMSET.md`) · (`test_deferral_lint` 나머지 34 = BYZ `.claude/hooks/deferral-lint-gate.sh`)
- ⑤(6): `test_agent_alive_fg_judge` · `test_kit_exec_modes` · `test_live_install_check`(⑥ 단언) · `test_mbox_v2_guard` · `test_tracked_bin_call_gate`(ⓖ 임시 리포 `scripts/fable-team-bin/` 자리) · `test_live_install`(옛 설치 사본 shim 판정)
- ⑥(5): `test_autonomy_hooks_layout`(r515 가 닿음) · `test_nano_succession_index`(r515 가 닿음 · ft-team-lib) · `test_wt_clean_plan_self_check`(ft-team-lib) · `test_evidence_inject_scan`(ft_da_hold_gate.py · design/ 자리) · `test_fake_resource_env`(모듈 경로)
- ⑦(6): `test_da_hold_gate` · `test_graphics_690` · `test_graphics_install` · `test_r66_codex_serena_boot` · `test_live_snapshot_all_rosters`(실 명부 · 추정) · `test_hil_run_marker`(ft-tick 실 기동 줄 · 추정) · (`test_inbox_watch` — 기준선 rc0 · 재실행 RED · ⓔ 가 팩 공용 루트 `~/Project/ai-feature-pack/.fable-team/LIVE_BIN` 을 읽음 · 두 판 같음)
- ⑧(10): 셸 `test_pack_relocation`(병합 뒤 변경 528 — 대조 기준 낡음) · `test_op_vault_develop_gate`(install.sh HOME_HOOKS 가 r491 뒤 find 로 계산 — 옛 글자 대조) · `test_resource_watch`(nice=20 — 러너 nice 15 상속 · 환경) · `test_wt_clean_two_stage`(부하 timeout 4s · 흔들림) · `test_slack_readonly_share`(`AttributeError: 'Namespace' object has no attribute 'state_dir'` — 도구 결함 후보) · pytest `test_seat_turn_batch.py` 2 · `test_press_gate_set_membership::test_set_paths_single_source_in_set_check` · `test_ft_hil_secret_lint.py` 1 (`test_mirror_team_inbound::test_t5c_…` 는 ①의 헬퍼 import 라 ① 고친 뒤 통과 → ① 로 셈)

## 결과 (원문 `compare.txt` · `bucket-before-after.txt`)

- ① pytest 79 + 같은 헬퍼를 쓰는 `test_mirror_team_inbound` 1 → 전부 통과(⑧ 에서 ① 로 옮김 · 고친 뒤 81 = ① 80 + ② magazine 1).
- ② 셸 9 중 7개 rc0 · `test_deferral_lint` 66→35(남은 줄 전부 gate = ④) · `test_team_literal_paths` 6→4(남은 4 = ③).
- 전체 전·후(같은 바탕 9af3b78a): 셸 실패 62 → 55 · pytest 104 → 23 failed · 후에만 실패한 pytest 0 · 셸 «후에만» 1(`test_inbox_watch` — 두 판 단독 재실행 같은 RED = 팩 공용 루트 실물 환경 · ⑦ 에 넣음).
- 남은 밖 RED: 셸 55 · pytest 23 — ③ 셸 15(+team_literal_paths 부분) · pytest 19 · ④ 셸 16(+deferral_lint 부분) · ⑤ 6 · ⑥ 5 · ⑦ 7(inbox_watch 포함) · ⑧ 셸 4(wt_clean_two_stage 이번 통과) · pytest 4.
- 합친 판(origin/main 1.1.79 병합 `b1b53f05`)에서 고친 시험 재확인: ② 7개 rc0 · pytest 4파일 109 passed 1 skipped.

## 첫 묶음 선택

- 시험 수가 가장 많은 묶음 = ①(pytest 79). ②는 pytest 분류 전에 셸 원문만으로 먼저 고쳤다(10개 · 시험·픽스처만 · 키트 diff 0) — 두 묶음 다 되돌림 = 해당 커밋 revert.
- 다음 큰 것: ③(34 · 시험 고침 꼴 — 다음 카드 1순위 후보) · ④(셸 16 — «고침» 이 아니라 «시험 자리 결정» 이라 arch 몫).
