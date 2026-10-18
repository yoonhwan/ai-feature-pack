# R218 의존 표 — 자원 문지기를 «실 머신 센서»로 타는 시험 (격리 전·후)

- 측정: 2026-10-15 · 나노 `byz-harness-nano-r218-tests-isolate-resource-gate#0` · base e2f6ad3019 (R213 병합 뒤)
- ⓐ = 그대로(실 센서) · ⓑ = PATH 앞에 «REJECT 값 가짜 센서»(압력 단계 4 · 에이전트 99 · `fake_resource_env <dir> reject`)를 걸고 같은 시험 실행
- 그 시각 실 머신 `ft-resource-gate.sh check` = `OK disk=75GiB swap=6641MiB memfree=52% level=1 rate=14 agents=44` (agents 44 · 상한 55 — 머신이 REJECT 가 아닌 시각 · 그래서 ⓑ 로 REJECT 상태를 재현)
- 후보 = 문지기 호출 도구 이름(`ft-role-spawn`·`ft-nano-spawn`·`ft-successor-open`·`ft-proxy-decide`·`ft-resource-*`)이 나오는 `tests/harness/*.sh` 26개 + `tests/scripts/test_*.py` 5개 = 31개
- 시험 명령 · harness: `env -u GIT_* bash tests/harness/<파일>` · scripts: `.venv/bin/python -m pytest -q <파일>`

## 의존 시험 (ⓐ ≠ ⓑ 이거나 센서 파일 누락으로 항상 RED) — 10개

| 시험 | ⓐ rc | ⓑ rc | 문지기를 부르는 줄 · 원인 | 격리 뒤 ⓐ/ⓑ |
|---|---|---|---|---|
| test_role_spawn_name.sh | 0 | **1** | `ft-role-spawn --dry-run` 입구 문지기(`ft-role-spawn.sh:27`) — 실 압력·에이전트 수 | 0 / 0 |
| test_seat_retire.sh | 0 | **1** | `SPAWN`(ft-role-spawn) 호출(`:7`) | 0 / 0 |
| test_cherry_gate_identical_head.sh | 0 | **1** | `ft-nano-spawn` 입구 문지기. R213 이전 이름의 env(`FT_SWAP_MAX_MIB` 등)로 우회하던 줄 — 새 문턱에 안 맞아 무효 | 0 / 0 |
| test_graphics_install.sh | 0 | **1** | 〃 (`:87` spawn --dry-run) | 0 / 0 |
| test_spawn_gate_landing_branch.sh | 0 | **1** | spawn 블록 추출 안 문지기 호출 | 0 / 0 |
| test_live_bin_drift_check.sh | **1** | 1 | 문지기를 임시 bin 에 «복사만»(샘플러 `ft-resource-sample.sh` 없음) → `ERROR resource measure pressure sample … 없음` rc4 — 머신 부하와 무관하게 R213 이후 항상 RED | 0 / 0 |
| test_nano_team_env.sh | **1** | 1 | 〃 (`:19` 실 gate 복사) | 0 / 0 |
| test_planner_nano_path.sh | **1** | 1 | 〃 (`:24`) | 0 / 0 |
| test_proposal_gate_wiring.sh | **1** | 1 | 〃 (`:12`) | 0 / 0 |
| test_raised_seat.sh | **1** | 1 | 〃 (`:31`) | 0 / 0 |

## 의존 없음 (ⓐ = ⓑ = 0) — 21개 (파이썬 5개 포함)

이미 자체 가짜 센서·임시 `FT_RES_ROOT` 로 격리됐거나 문지기를 실제로 타지 않는다: test_autonomy_core · test_autonomy_hooks · test_autonomy_kinds_1675 · test_baseline_lint · test_dead_seat_resume · test_distill_recv_gate · test_nano_close_sha_base · test_nano_slots · test_nano_spawn_body_press · test_nano_spawn_reuse_info · test_proxy_decide_r188(`FT_RESOURCE_GATE` env) · test_resource_gate · test_resource_gate_pressure · test_resource_reclaim · test_sheet_events · test_successor_open(옛 env 문턱 + R213 교정 4 의 인라인 스텁 → **헬퍼로 이전**, 이전 전후 0/0) · tests/scripts 5개(`test_ft_nano_spawn_evidence_template` · `test_ft_sibling_reject` · `test_nano_spawn_base_sha` · `test_nano_spawn_branch_collision` · `test_nano_spawn_rollback` — 5개 묶음 pytest ⓐ rc0 · ⓑ rc0).

## 격리 방법 (제품 코드 0 · 문지기 우회 경로 0)

- `tests/harness/lib/fake_resource_env.sh` — `fake_resource_env <임시폴더> [ok|reject]` : PATH 앞에 가짜 `sysctl`·`vm_stat`·`memory_pressure`·`df`·`pgrep`(`-a -x claude`/`-a -x codex` 만 가짜 수 · 그 밖 인자는 `/usr/bin/pgrep`) + 임시 `FT_RES_ROOT` + 신선한 `pressure.tsv` 2줄(문지기를 임시 bin 에 복사해 쓰는 시험도 샘플러 없이 통과).
- `tests/scripts/fake_resource_env.py` + conftest 픽스처 `fake_resource_env(mode)` — 같은 값의 env dict (`tests/scripts/test_fake_resource_env_fixture.py` 2건).
- 시험 의도가 «문지기가 막는 것» 인 곳(`test_resource_gate*.sh`)은 기존 자체 가짜 센서 그대로 · `reject` 모드로 같은 값 재현은 `test_fake_resource_env.sh` ⓑ.
- `test_fake_resource_env.sh` : ⓐ ok → 실 gate rc0 · ⓑ reject → rc≠0 + `REJECT resource level=4`(승계 점검도) · ⓒ 가짜 pgrep 이 `-x claude` 외 인자를 진짜로 넘김 · ⓓ 임시 FT_RES_ROOT 에만 기록·실 `RESOURCE_FREEZE` 변화 0 · ⓔ 파이썬 판 ok/reject.

## 격리 후 전수 (ⓐ 실 센서 · ⓑ REJECT 값 가짜를 «덮어씌운» 실행 — 격리가 덮어쓰므로 같아야 한다)

바뀐 11개 + 헬퍼 시험 1개 = 12개: **ⓐ 전부 rc0 · ⓑ 전부 rc0**. 나머지(의존 없음)는 위 표 그대로.

## 원장 R218 처리 칸 (master 가 본 원장 R218 행에 옮길 문장 — 이 브랜치의 원장 사본엔 R218 행이 없어 직접 수정하지 않음)

> 처리: 시험 격리 — 공통 가짜 센서 헬퍼(셸·파이썬) + 의존 시험 10개 격리 · successor_open 스텁 이전 · 전수 표 `design/teams/harness/staged-r218/dependency-table.md` (REJECT 값 가짜 센서 ⓑ 에서도 전부 rc0) · 제품 코드 0 · 시험 삭제·skip 0 · 발견: 의존 10개 중 5개는 부하와 무관하게 R213 이후 항상 RED(임시 bin 에 문지기만 복사해 샘플러 없음).

## 교정 1 — 문턱 env 를 건 채 / 안 건 채 rc 표 (arch#63 재현: 호출자 셸의 문턱 env 가 새던 구멍)

문턱 env 10개(`FT_AGENT_MAX` `FT_DISK_MIN_GIB` `FT_MEM_FREE_MIN_PCT` `FT_MEM_FREE_MIN_SUCC` `FT_PRESSURE_MAX` `FT_PRESSURE_MAX_SUCC` `FT_SWAP_HARD_MIB` `FT_SWAP_MAX_MIB` `FT_SWAP_RATE_MAX` `FT_SWAP_RATE_MAX_SUCC`)를 «막는 값»(1·99999·99·99·0·0·1·1·0·0)으로 export 한 셸 vs 안 건 셸. 두 헬퍼가 이 10개를 지운다(셸 `unset` · 파이썬 `pop` · 목록 상수 헬퍼당 1곳).

| 시험 | 문턱 env 건 rc | 안 건 rc |
|---|---|---|
| test_role_spawn_name.sh | 0 | 0 |
| test_successor_open.sh | 0 | 0 |
| test_seat_retire.sh | 0 | 0 |
| test_cherry_gate_identical_head.sh | 0 | 0 |
| test_graphics_install.sh | 0 | 0 |
| test_spawn_gate_landing_branch.sh | 0 | 0 |
| test_live_bin_drift_check.sh | 0 | 0 |
| test_nano_team_env.sh | 0 | 0 |
| test_planner_nano_path.sh | 0 | 0 |
| test_proposal_gate_wiring.sh | 0 | 0 |
| test_raised_seat.sh | 0 | 0 |
| test_fake_resource_env.sh (ⓔ 추가) | 0 | 0 |

tests/scripts 6파일(픽스처 시험에 문턱 env 단언 1개 추가): 76 passed.
