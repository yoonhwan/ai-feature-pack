# Pi seat adapter 구현 동결

단계별 초: 계약/소비자 13.214초, 실제 gate 11.306초, 불변/회귀 2.494초, ruff 대조 0.137초, byte 증명 0.062초, quality 0.114초. 원rc는 전부 0입니다.

기준 branch는 `fix/pi-seat-status-adapter`, 기준 commit은 `cff35549`입니다. 계약 v3 SHA256은 `86c9de6f42d496225c535f4854a3ae3c3c3cf95a8f70490973c3603462b342bc`입니다. 코드와 시험 수정은 종료했습니다. commit/push/install은 root 담당입니다.

모든 신규 실행 시험은 pytest `tmp_path` 아래 `FT_ROOT`, 명부, 합성 Pi session/message, 가짜 tmux로 격리했습니다. 살아 있는 fixture 작성 프로세스의 pid 존재만 `ps -p ... -o pid=`로 확인했습니다. 실좌석, 실제 Pi 대화, 모델 추론, 우편함, auth는 수정하지 않았습니다. close 성공 시험의 `kill-session`은 임시 tmux 스텁에만 기록됩니다.

## 원문 증거

| 파일 | 결과 |
|---|---|
| `01-red.txt` | adapter 부재 RED, 원rc 1, 12 failed / 2 passed |
| `02-green-contract-consumers.txt` | adapter와 소비자 43 passed, 원rc 0 |
| `03-green-gate.txt` | 실제 haswork_gate/actionable/fire/goal 30 passed, 원rc 0 |
| `04-regression.txt` | byte 불변 21건과 기존 Codex/Claude 관련 24건, 총 45 passed, 원rc 0 |
| `05-ruff-baseline.txt` | 기준판과 현재판의 `(code, message, source line)` multiset 대조, 신규 경고 0 |
| `06-byte-proof.txt` | 불변 SHA256과 source/kit 11짝 cmp0 |
| `07-quality.txt` | 신규 Python/시험 ruff, bash -n, compile, git diff --check 원rc 0 |
| `08-collected-nodes.txt` | 신규 pytest node 94개 실수집 목록 |

`python3` 기본 환경에는 pytest가 없어 기존 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.venv/bin/python`의 pytest 9.0.3으로 실행했습니다. 수정된 기존 `ft_roster_lib.py`의 ruff 경고는 36개에서 27개로 줄었고 `ft_seat_bind.py`는 10개 그대로입니다. 바이트 동결 대상의 기존 압축 스타일은 재포맷하지 않았습니다.

## 원발주 11개 논리 케이스

node 경로의 공통 앞부분은 `feature-pack/fable-team/harness/tests/scripts/`입니다. 개별 케이스 초는 측정하지 않았습니다. 아래 초는 해당 파일이 포함된 실행 그룹의 실측값입니다.

| 원발주 케이스 | 실제 pytest node | 그룹 결과 |
|---|---|---|
| 1. toolUse 중간 | `test_ft_seat_pi.py::test_contract_turns[records0-WORKING]` | 계약/소비자 rc0, 13.214초 |
| 2. toolUse 직후 toolResult | `test_ft_seat_pi.py::test_contract_turns[records1-WORKING]` | 계약/소비자 rc0, 13.214초 |
| 3. 새 user | `test_ft_seat_pi.py::test_contract_turns[records2-PENDING]` | 계약/소비자 rc0, 13.214초 |
| 4. queue 문면 | `test_ft_seat_pi.py::test_contract_turns[records3-IDLE]` | 계약/소비자 rc0, 13.214초 |
| 5. 503 내부 rate_limit | `test_ft_seat_pi.py::test_contract_turns[records4-RATELIMITED]` | 계약/소비자 rc0, 13.214초 |
| 6. auth 실패 근거 | `test_ft_seat_pi.py::test_contract_turns[records5-LOGGEDOUT]` | 계약/소비자 rc0, 13.214초 |
| 7. 동일 cwd 다좌석 | `test_ft_seat_pi.py::test_same_cwd_other_seat_is_not_selected`, `test_same_cwd_other_seat_does_not_hide_unique_match` | 계약/소비자 rc0, 13.214초 |
| 8. 동일 UUID 다파일 | `test_ft_seat_pi.py::test_duplicate_uuid_files_are_ambiguous` | 계약/소비자 rc0, 13.214초 |
| 9. 재기동 | `test_ft_seat_pi.py::test_restart_uses_live_uuid`, `test_ft_seat_pi_consumers.py::test_resume_bind_expect_same_file_and_restart_invalidates` | 계약/소비자 rc0, 13.214초 |
| 10. 불명 UNKNOWN | `test_ft_seat_pi.py::test_contract_turns[records7-UNKNOWN]` | 계약/소비자 rc0, 13.214초 |
| 11. timeout와 실제 gate 상태별 발사 0/1 | `test_ft_seat_pi.py::test_external_timeout_is_bounded_and_fail_closed`, `test_ft_seat_pi_gate.py::test_actual_gate_sends_only_normal_idle`의 전체 30개 node | 계약/소비자 rc0, 13.214초 / gate rc0, 11.306초 |

gate는 명시 stop/end_turn/max_tokens/null만 발사 1회입니다. toolUse, 후속 user/toolResult, 구조 queue, lookup 실패, rate-limit, auth, 일반 503, timeout 오류, aborted, stopReason 누락은 발사 0회입니다. gate 시험의 agent_gate는 허용 스텁입니다. 기존 Pi 프로세스 생존 정책은 별도 `test_existing_agent_alive_pi_policy_with_synthetic_processes`의 R+/T/전경 셸 3건으로 확인했습니다. 실제 Pi 본체를 띄운 시험은 아닙니다.

## 소비자 7종

| 소비자 | 완료/미완과 근거 |
|---|---|
| seat-status one/list/idle/stalled/jsonl/--file | 완료. 단일 명부 Pi dispatch를 사용합니다. 비IDLE은 idle/stalled 대상에서 제외합니다. 명시 `--file`은 파일 schema 판정만 하며 live 소유 결속을 증명하지 않습니다. |
| ft_team_turns locate/turn_at | 완료. Pi는 공용 locator로 선분리하고 Pi 판정기로 읽습니다. child_teams의 명시 root도 연결했고, FT_ROOT/FT_SEATS_JSON 없는 경계 시험을 통과했습니다. |
| ft-news-tree | 완료. Pi는 공용 locator/판정기를 사용합니다. UNKNOWN의 pane IDLE 후퇴를 차단했습니다. |
| ft_model_swap | 확인 완료, intentional exclusion. 기존 agent==claude 대상 정책을 유지합니다. Pi 자동 모델 교대는 미지원이며 정책을 확대하지 않았습니다. |
| ft_roster_lib.pi_seat_resume | 완료. cwd 최신파일 추정을 제거하고 상태 판정과 같은 locator로 파일을 확정합니다. |
| seat-bind/close/retire 동일파일 결속 | 완료. bind와 resume의 binding이 같고 restart 시 expect가 실패합니다. retire는 stale keep-existing을 수용하지 않습니다. close는 기록 뒤 binding을 재확인하고 불명 시 명부 쓰기/kill을 막습니다. 성공/모호성 실패를 임시 환경에서 확인했습니다. |
| agent_gate/도달확인 | 완료. 기존 agent_alive의 Pi 자손 정책은 변경하지 않고 합성 프로세스로 확인했습니다. Pi reach는 공용 locator의 현재 UUID 파일 한 개만 세며 후보 0/2개 이상은 rc5입니다. |

## 바이트 불변

| 대상 | 기준판과 현재판의 SHA256 |
|---|---|
| `ft_seat_codex.py` source/kit 전체 | `abdad84455d2b3d60855e0f5ab90061c35eab8b08c37540c8fc54838ca23491c` |
| `ft_seat_turn.py` source/kit 전체 | `d6cc8b8416f550953d7e9aabda018e83d70bf1831776cc804738f65522cfce56` |
| `ft_api_outage_util.py` source/kit 전체 | `514e9ff180ee211c240d45ed11230cafa1fc5873d4464c6bb701f6d2e1f266ba` |
| `ft-seat-status.sh` 신규 Pi 삽입 제거본 | `f958261c5e9c66b819ce7734b4faf41ced753432fbb239293341eef00951d6c1` |

`test_ft_seat_pi_invariants.py`는 status/team_turns/team_state/news-tree/bind/retire/close의 `PI ADAPTER` 삽입 제거본을 기준판과 byte 비교합니다. roster는 기존 Pi 함수 앞의 전체 원문을 비교합니다. reach는 Pi 전용 함수 변경과 신규 Pi 삽입만 제외하고 비교합니다. `find_jsonls`와 Claude/Codex 판정기 원문은 그대로입니다.

알려진 한계: 새 live locator는 세션 파일이 생기기 전에는 후보 0개로 판정 불가를 반환합니다. 초기 도달 count도 이때 rc5이며, 0건의 확정 증거로 추정하지 않습니다. Pi 오류 상태의 list/one age는 `-`라서 stalled 후보로 쓰이지 않습니다.

## 승인 v1 이후 정상 설치 경로 1건 보정

위 43/30/45 passed는 승인 v1의 원문입니다. 이를 보정판의 전체 재시험 결과로 바꾸어 쓰지 않았습니다. v1 index와 root의 보존 diff도 그대로입니다.

신규 node는 `test_ft_seat_pi_consumers.py::test_installed_reach_uses_live_modules_behind_normal_python_shims` 한 개입니다. 기존 `ft-root-bin-shim.sh`의 `shim_body_py` 원문으로 임시 project bin에 정상 Python shim을 생성했습니다. `tmpROOT/.fable-team/LIVE_BIN`은 별도의 임시 실제 모듈 bin을 가리킵니다. 실제 설치와 모델 호출은 하지 않았습니다.

| 단계 | 원문 결과 |
|---|---|
| RED | 정상 shim을 import하다 ImportError, rc1, 0.864초 |
| GREEN | 신규 1건 passed, rc0, 0.878초 |
| 최종 영향회귀 | 소비자 20건과 byte 불변 21건, 총 41 passed, rc0, 8.402초 |
| quality | source/kit cmp0, bash -n, ruff consumer test, diff --check 모두 rc0, 0.096초 |

Pi reach 함수만 권위 `../LIVE_BIN`을 먼저 읽도록 보정했습니다. source 개발형과 실제 live bin 실행은 실제 모듈 폴더를 사용합니다. project bin shim은 직접 import하지 않습니다. 같은 신규 node에서 설치 comm의 count 1/REACHED와 실제 live bin 직접 실행의 count 1을 확인했습니다. 기존 source 형태는 기존 reach 소비자 시험으로 확인했습니다.

원문은 `09-installed-reach-red-green.txt`입니다. reach source/kit SHA256은 둘 다 `e93cea227c439def5e89fefb5250db1497660738f50722b6f1dddf7d4b5705a8`입니다. 기존 Claude/Codex 전체 SHA와 비Pi 원문 불변 시험도 41건 영향회귀에 포함돼 통과했습니다. 이 보정판의 코드/시험 수정도 종료했습니다.

## 최신 명시 승인 272156/272158에 따른 최종 보충

앞의 `09` 원문은 단일 설치형 case의 RED/GREEN 기록으로 보존했습니다. 승인 v1의 43/30/45 원문도 수정하지 않았습니다. 최종 보충 원문은 `10-installed-layout-two-cases.txt`입니다.

Pi 함수는 LIVE_BIN의 실제 모듈을 먼저 검사합니다. 해당 모듈이 없거나 shim이면 root/bin의 실제 모듈을 검사합니다. root/bin을 선택하면 stderr에 LIVE_BIN 실모듈 확인 불가 사유와 fallback을 남깁니다. 두 후보가 없거나 shim뿐이면 rc5로 차단합니다.

| 최종 검증 | 실제 node / 결과 | 실측 단계 초 |
|---|---|---|
| shim만 있고 LIVE 실모듈 없음 | `test_installed_reach_shim_only_without_live_modules_is_rc5`: count rc5, reach rc5, stdout의 REACHED 없음. pytest rc0, 1 passed | 0.643초 |
| LIVE 실모듈만 있고 root/bin 실모듈 없음 | `test_installed_reach_live_modules_only_counts_and_reaches`: count 1/rc0, REACHED/rc0. pytest rc0, 1 passed | 0.927초 |
| 기존 Claude/Codex 회귀 재실행 | 기존 `test_ft_seat_codex.py`, `test_ft_seat_turn_window.py`, `test_seat_turn_compact.py`: pytest rc0, 24 passed | 2.256초 |
| 기존 source/rootbin 양성 영향검증 | `test_reach_counts_only_live_uuid_and_ambiguous_is_rc5`: pytest rc0, 1 passed | 0.797초 |
| 최종 quality/byteproof | source/kit cmp0, bash -n, ruff, diff --check, 비Pi 본문 및 Claude/Codex byte 비교 모두 rc0 | 0.113초 |

별도 두 node의 공통 경로는 `tests/scripts/test_ft_seat_pi_consumers.py`입니다. 정상 shim은 기존 `shim_body_py` 원문으로 생성했습니다. 임시 FT_ROOT와 합성 fixture만 사용했습니다. 이미 통과한 byteproof pytest 21건은 반복 실행하지 않고 필요한 파일의 byte만 직접 비교했습니다.

현재 최종 reach source/kit SHA256은 `91d8051306b6257ecce4512ae5a213591c6c6bfb281f2ccbeb2fed2b7881b101`입니다. 위 `e93...`은 `09` 단계 보정판의 값입니다. 최종 코드/시험 수정은 종료했습니다. root의 새 보정판 DA 1회와 checker 1회 이후 절차로 넘기며 commit/push/install/실좌석 변경은 수행하지 않았습니다.
