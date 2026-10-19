# r459 master-steps — 틱 데몬 자리 규칙 3줄(코드 = LIVE_BIN · 데이터 = 공용 루트 · 정본 = ref origin/main) (집행 순서 · master)

카드 `design/harness/indices/진행/r459-tick-daemon-comm-at-common-root-shim-guard-goal-ref.md` · 나노 byz-harness-nano-r459-tick-daemon-comm-at-common-root-shi#0

## 가지 1
| 리포 | 가지 | 내용 |
|---|---|---|
| ai-feature-pack | `nano/r459-tick-daemon-comm-at-common-root-shi` (워크트리 `.worktrees/r459-tick-comm-root` · base d8305edb = origin/main) | 키트 9 파일(bin·kit 짝 cmp0): `ft-harness-root.sh` · `ft-tick.sh` · `ft-tick-team.sh` · `ft-team-lib.sh` · `ft-goal-tick.sh` · `ft-news-tick.sh` · `ft-tick-install.sh` · `ft-tick.plist` · `ft-nano-close.sh`(문구) · `ft_live_install_check.py`(restart_due 추출 + --restart-scan) + 설치기 `install.sh` · 시험 `test_harness_root.sh`(r459 ⓐ~ⓔ) · 새 `test_tick_shim_guard.sh` · `test_nano_close_fail_closed.sh`(문구) · CHANGES 1절 · manifest 1.1.30 · 이 파일 · `tests-rc.txt` |
| BYZ-Agents | `nano/r459-tick-daemon-comm-at-common-root-shi` | 커밋 0(이 단위는 팩만 · 카드 증거 줄은 harness-ops 카드에) |

## 순서
1. 팩 PR → main 착지(push·PR·`ft-merge-land` = master). 착지 전 팩 루트에서 `tests-rc.txt` 의 명령 재실행.
2. 설치 전 확인(읽기만): `bash feature-pack/fable-team/harness/install.sh --dry-run --project <BYZ 공용 루트>` → `COMM copied=24 same=8` 근처 · ★`COMM …/mbox.sh <- … (다름 …)` 는 루트 mbox.sh 가 팩보다 뒤(r408 uf_watch 미설치) — 덮으면 r408 동작이 같이 들어간다(되돌림 = `mbox.sh.bak-1.1.30`)★.
3. 설치: `bash feature-pack/fable-team/harness/install.sh --apply --project <BYZ 공용 루트>` → LIVE_BIN(1.1.30) 키트 cmp0 + 루트 comm 도구 cmp0(`COMM copied=… same=…`) · 출력 끝 `RESTART <라벨> — launchctl kickstart -k gui/501/<라벨>` 줄 목록. `ft-live-install-check.sh --range d8305edb..<착지 sha>` OK.
4. 메인 plist 재생성(선택 · 임시 완화 (가)가 이미 env 3줄을 넣었으면 cmp 만): `bash <LIVE_BIN>/ft-tick-install.sh --worktree <BYZ 공용 루트> --script <지금 메인 plist 의 스크립트> --dry-run` + `FT_TICK_PRINT_PLIST=1` → WorkingDirectory·env 3줄 = 공용 루트 comm 확인. 되돌림 = plist `.bak`.
5. kickstart(★master 집행★ · 3 의 RESTART 줄 그대로): 틱 6 라벨(`com.byz.ft-tick` · `-cfo` · `-ops` · `-loom` · `-feature` + 나머지 팀) — 나노 실측 읽기 시점(설치 전)엔 팀 4 + 슬랙 수신 2(`com.hermes.byz-slack-mbox-inbound`·`-talk-inbound`)가 RESTART 대상.
6. 실사건 1(카드 `- 실사건:` 줄): kickstart 뒤 `/tmp/ft-tick.log` 새 `ft-tick started` 줄 · 그 뒤 `SyntaxError` 0 · `에이전트 판정 불가` skip 0 · v65 master 좌석 «발사 1» 줄 · `/tmp/ft-goal-tick.log` ERROR 0. 네 값 + 줄 번호를 복붙.
7. 정본 1줄(arch 손 · 착지 뒤): `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 14 끝 «자리 규칙 3줄 …(r459)».

## 편차
- 카드 «`test_harness_root.sh` 새 파일» → 이미 있음(r385b ⓖ~ⓛ) — 같은 파일 끝에 r459 ⓐ~ⓔ 를 붙였다(기존 단언 불변).
- 카드 «RESTART = `:137-157` 함수 재사용» → `plist_items` 안 판정식을 `restart_due(pid, scripts)` 로 뽑아 plist_items 와 새 `restart_scan` 이 같이 부른다(복제 0). 대상 스크립트 = ProgramArguments 의 하네스 스크립트(템플릿 `__HOME__` 자리가 아니라 설치된 plist) · shim 이면 `../LIVE_BIN` 지도 파일·라이브 도구 mtime 도 포함(버전 전환 = 지도 파일이 바뀜).
- 키트 범위에 `ft-tick.plist`(템플릿 env 3줄)·`ft_live_install_check.py` 포함 — 카드 4·5 를 하려면 필요.
- 뉴스 틱 `WT=<루트>/.worktrees/v6-realtime-live`(도구 폴더)는 남김 — r458 범위.

## 남은 빨강 (이 단위 밖 · base 에서도 같음 — tests-rc.txt 참조 · 판정 1395 «기존 RED» 변명 0 → 새 카드 후보)
- `test_ft_tick_master_seat.sh` 44 → 4: base 는 ft-tick 이 comm 을 못 풀어 첫 줄 exit 1(44 전부). 이제 comm 이 풀려 다음 단계까지 가고, 남은 4 = `dead_seat_watch: ERROR autonomy mode unreadable (none)` — 픽스처가 자율 상태(FT_ROOT·LIVE_ROOT) 없이 팩 cwd 에서 돈다. 새 카드 후보: 픽스처에 `FT_TICK_RESUME=0` 또는 자율 상태 주입.
- `test_team_literal_paths.sh` 10 → 6: 이 단위 계약 2줄(goal-tick 변이 문구 · news-tick 헬퍼 grep)은 고쳤다. 남은 6 = ⓐ1·ⓐ2 골 표 픽스처 `AUTONOMY-GOAL-A6-20261018.md` 없음 · hil-ask/answer 가 `FT_ROOT=<픽스처>` 인데 그 comm 폴더를 시험이 나중(84행)에야 만든다 — 옛 ft_comm_dir(FT_ROOT → ft_data_root)도 같은 폴더를 요구해 같은 ERROR.
- 그 밖 base 와 같은 빨강: agent_alive_fg_judge · autonomy_core · da_hold_gate · evidence_inject_scan · ft_wt_sweep_route_timeout · goal_table_gate · graphics_690 · graphics_install · hil_run_marker · live_install · live_install_check ⑥ · live_install_check_tip ⓕ · live_snapshot_all_rosters · loom_tunnel_install · nano_succession_index · pack_relocation ⓒ(git diff rev..HEAD — main 자체에서 빨강) · planner_nano_path · seat_retire · team_literal_paths2 · team_move_roundtrip · team_scaffold_empty_template · team_tick_unify · teamset_check · tick_line · tracked_bin_call_gate · wt_clean_plan_self_check.

press 필요: 없음(틱 데몬·설치기 단위 — 라이브 오디오 경로 0).
