# r823 기존 spawn 시험(ft-nano-spawn.sh 를 부르는 시험 49개 · 새 시험 포함) — 변경 뒤 vs 원본 spawn(HEAD)
| 시험 | 변경 뒤 병렬 4 | 원본 spawn | 변경 뒤 단독 재실행(픽스처 보강 뒤) | 판정 |
|---|---|---|---|---|
| test_all_stop_r626 | rc=0 | - | - | PASS |
| test_baseline_lint | rc=0 | - | - | PASS |
| test_cherry_gate_identical_head | rc=0 | - | - | PASS |
| test_da_hold_gate | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_dead_seat_resume | rc=137 | rc=0 | rc=0 390s | PASS(재실행) |
| test_finished_cleanup_auto | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_from_current_r730 | rc=0 | - | - | PASS |
| test_graphics_install | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_harness_root | rc=0 | - | - | PASS |
| test_idle_slot_fill_r667 | rc=0 | - | - | PASS |
| test_installed_root | rc=0 | - | - | PASS |
| test_live_bin_drift_check | rc=0 | - | - | PASS |
| test_nano_close_sha_base | rc=0 | - | - | PASS |
| test_nano_slots | rc=0 | - | - | PASS |
| test_nano_slots_cards_wt | rc=0 | - | - | PASS |
| test_nano_spawn_body_press | rc=0 | - | - | PASS |
| test_nano_spawn_body_search_roster | rc=0 | - | - | PASS |
| test_nano_spawn_pi_effort_kind_r631 | rc=0 | - | - | PASS |
| test_nano_spawn_pi_effort_serena | rc=0 | - | - | PASS |
| test_nano_spawn_recheck_cited | rc=0 | - | - | PASS |
| test_nano_spawn_reuse_info | rc=0 | - | - | PASS |
| test_nano_spawn_teamset_cap | rc=7 | rc=7 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_nano_spawn_tier | rc=0 | - | - | PASS |
| test_nano_team_env | rc=0 | - | - | PASS |
| test_pack_nano_worktree_place | rc=0 | - | - | PASS |
| test_penalty_spawn_gate | rc=0 | - | - | PASS |
| test_pi_agent_allow_r540 | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_planner_nano_path | rc=1 | rc=0 | rc=0 69s | PASS(재실행) |
| test_proposal_gate_wiring | rc=0 | - | - | PASS |
| test_r655_nano_name_prefix | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_raised_seat | rc=1 | rc=1 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_resource_freeze_exempt | rc=0 | - | - | PASS |
| test_resource_gate | rc=0 | - | - | PASS |
| test_resource_reclaim | rc=0 | - | - | PASS |
| test_resource_reclaim_preventive | rc=137 | rc=0 | rc=0 302s | PASS(재실행) |
| test_root_bin_shim | rc=0 | - | - | PASS |
| test_satellite_rosters | rc=0 | - | - | PASS |
| test_seat_cap_nano_only_r666 | rc=0 | - | - | PASS |
| test_sheet_events | rc=0 | - | - | PASS |
| test_spawn_agent_ready | rc=0 | - | - | PASS |
| test_spawn_gate_landing_branch | rc=0 | - | - | PASS |
| test_spawn_hold | rc=0 | - | - | PASS |
| test_spawn_issue_gate_r823 | rc=0 | - | - | PASS |
| test_spawn_proxy_probe_r669 | rc=4 | - | rc=0 53s | PASS(재실행) |
| test_team_literal_paths2 | rc=1 | - | rc=0 43s | PASS(재실행) |
| test_team_path_oldpath_md | rc=0 | - | - | PASS |
| test_team_roster_ref | rc=8 | rc=8 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_teamset_gitref | rc=3 | rc=3 | - | 기존 실패(원본도 같은 FAIL 줄 집합 · 변경 무관) |
| test_tracked_bin_call_gate | rc=0 | - | - | PASS |

- 원본 대조 = 실패 12개를 HEAD 판 spawn 으로 되돌려 실행(runbase) · 기존 실패 9개는 FAIL 줄 집합 sha 같음.
- 픽스처 보강(기대값 변경 0 · 카드 머리 `- Issue: #1` + 가짜 gh OPEN + 게이트 사본): test_spawn_proxy_probe_r669 · test_team_literal_paths2 · test_planner_nano_path · test_dead_seat_resume.
- rc=137 2건(reclaim_preventive · dead_seat_resume) = 병렬 부하에서 300·500초 KILL · 단독 재실행 302·390초 rc0.
