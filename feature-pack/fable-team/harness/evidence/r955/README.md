# r955 증거 — ops-intake 스크립트 키트 (하네스팀 몫 1/2)

카드: `design/harness/indices/진행/r955-ops-intake-scripts-kit.md` (BYZ-Agents harness-ops 워크트리)
브랜치: `nano/r955-ops-intake-scripts-kit` (팩) · base = origin/main `a1fccaf7`

## 무엇을 냈나

`kit/ops-intake/` 새 폴더 — write(ⓐⓑⓒ) · poster(ⓓ) · sync intake/status(ⓑ2ⓑ3ⓔ) · sat-mbox 이식(ⓕ) · plist 템플릿 3 · README 계약.
시험 = `tests/test_ops_intake.py`(19 cases) + `tests/test_ops_intake.sh` 러너(변이 6종 포함). 실 슬랙·실 gh·실 ssh·실 mini 호출 0.

## 시험 (2026-10-26 · 이 워크트리)

```
bash feature-pack/fable-team/harness/tests/test_ops_intake.sh      → ALL PASS (rc=0)
  py_compile 5/5 · plutil 3/3 · cases 19/19 · mutate 6/6
```

- `test-all.log` = 위 실행 전문.
- 변이 6종(ⓗ): mask-off → ⓑ / rescan-off → ⓑ2 / declared-off → ⓑ3 / guard-ts → ⓓ / ledger-off → ⓓ중복 / notice-off → ⓔ — 전부 «잡았다».

## 재사용한 정본 (규칙 복제 0)

| 축 | 정본 | 어떻게 |
|---|---|---|
| 비밀 마스킹 | `harness/bin/ft_secret_shapes.py` `mask()` | import 해서 그대로 호출. 모듈 없으면 rc2 «판정 불가» |
| 게시 문장 검사 | `kit/slack-mirror/post_guard.py` `SECRETS`·`INTERNAL` | 규칙표만 import(명부 판정은 mini 에 명부가 없어 «항상 사람 채널»). sha 꼴 +1줄 |
| 슬랙 호출 | `kit/slack-mirror/mirror_lib.post` | 7초 상한·재시도 1 그대로 |
| 쪽지 | `~/.claude/skills/fable-team/scripts/ft-mbox.{sh,py}` | send 는 sh, 읽기·ack 는 py 모듈(잠금·형식 복제 0) |
| pull 데몬 | 멀티호스트 가지 `docs/multihost/satellite/sat-mbox.py` | 이식(aifp #3335 승인) · 원본 그대로 보존 |

## 이식 조건(멀티호스트 팀 승인 aifp #3335) 반영

1. 내부 절대경로 기본값 제거 — `FT_MBOX_DIR`·`SAT_STATE` env → 리포 루트 추정 → 중단.
2. ssh 대상·hostname = `MINI` / `SAT_SSH`(argv 통째 교체 — 시험용).
3. 좌석 목록 파일 1개(`--seats-file` / `SAT_SEATS_FILE`) — pull 데몬 1개가 읽는다.
4. 쪽지함 큐 ≥10 이면 보내지 않고 로그 1줄(`PULL defer … 버리지 않음`), rc5.
5. 비밀·내부 식별자(프로젝트 ID·IP·계정) 코드·주석에 0.

## 시험 부작용 1건(정정 완료)

첫 시험판이 «목록 밖 좌석» 픽스처로 실 좌석 이름을 써서 그 좌석 창에 doorbell 1발이 갔다(aifp #3336 지적).
정정 = 시험 좌석명을 전부 가짜(`byz-opsintake-*`)로 · `FT_SEATS_JSON` 픽스처(tick 있음 = quiet) · `FT_MBOX_RATE_N` 상향. 이후 실행에서 실 좌석 doorbell 0.

## press 필요: 없음 (이 카드는 라이브 오디오 시험 없이 단위·캡처만)

라이브 확인이 필요한 축은 r956(h-A mini 설정 · h-B mini 설치 · h-C 이 맥 launchd)이다 — 이 카드 범위 밖.

## 남은 것(다음 카드)

- h-B 설치 목록(README §mini 설치) 그대로 실행 + `launchctl list` 확인.
- 시험 사용자 글 1건 → 이슈 #N → 상태 답 3게시가 «같은 스레드» 인지(기획 §7 합격 기준).

## 반송 r2 (DA⑥ r1 HOLD 4 · arch 147) — 고침·시험·변이

| 반례 | 고침 | 시험 | 변이 |
|---|---|---|---|
| ① 사용자 값 줄바꿈으로 `secrets_masked` 위조 | write: 모든 사용자 값을 `oneline()`(한 칸 = 한 줄). sync: `head_lines()`(첫 `---` 앞만) + `declared_masked()`(그 키 줄 정확히 1개·0 이상 정수) + `body_forges_mask()`(본문에 심은 같은 키 = 판정 불가) | `test_r1_user_value_cannot_forge_header` · `test_r1_forged_header_blocks_intake` · `test_r1_two_header_lines_block_intake` | `header-block-off` |
| ② 절대경로·«토큰 \*\*\*» 게시 통과 | poster `PATH_RX`(`/a/b…`·`~/a…`) + 비밀 종류 낱말 ∧ 가림 표시 = 게시 0 | `test_r2_paths_and_masked_secret_words_blocked`(4문장) | `path-rule-off` |
| ③ pull 중 큐 10 넘어도 계속 | sat-mbox: 쪽지 1건마다 `queue_len()` 재측정 → 넘으면 `HOLD queue=<n> remaining=<m>` · 남은 건 ack 0 · rc5 | `test_r3_queue_recounted_per_message`(로컬 9 + 원격 3 → 1건 전달·2건 보류·미니에 2건 남음) | `queue-recount-off` |
| ④ ssh 8초도 기다림(25초 상한) | `CALL_TIMEOUT=7` 하나로 통일(ssh·원격 파이썬·전달) · 넘으면 rc7 「7초 초과(단계)」 | `test_r4_ssh_over_7s_fails`(8초 응답 → rc≠0, 8.6초 안에 끝남) | `timeout-off` |

시험 = 25 cases(19 → +6) · 변이 10종(6 → +4) 전부 잡음. `test-all.log` 갱신.

## 반송 r3 (DA⑥ r2 HOLD 2 · 같은 축 2회째 = 재설계 · arch 148)

| 반례 | 왜 났나 | 재설계(구조로 닫음) | 시험 | 변이 |
|---|---|---|---|---|
| ① 게시 쪽 비밀 검사가 카드 쪽과 다름 → 토큰·전화·메일 게시 통과 | 검사기가 «쓰는 곳마다 따로»(카드 = ft_secret_shapes+, 게시 = post_guard SECRETS) — 둘의 차이가 구멍 | **검출기 하나**: `ops_intake_common.mask_text()` 를 카드 쓰기·이 맥 재검사·게시 직전이 같이 부른다. 게시는 그 결과 kinds ≥1 이면 게시 0 + ERROR 1줄 | `test_p_every_card_secret_shape_blocked_on_post`(6꼴: slack토큰·sk키·pg DSN·redis DSN·전화·메일 — 카드 검출기가 잡는 값 전부) · `test_p_masked_marker_and_paths_blocked` | `poster-secrets-off` |
| ② 성공 응답 뒤에만 원장 기록 → 깨진 응답 뒤 재실행이 같은 글을 또 게시 | 원장이 «결과 뒤» 에만 남아 이미 나간 게시를 모른다 | **기록 먼저, 보내기 뒤**: `sending` 선기록 → 게시 → `sent`. 재실행은 재게시 0 · 스레드 표식(같은 문장) 조회로 맞춤, 못 맞추면 «확인 불가» ERROR + 쪽지 보존(rc5) | `test_q_broken_response_then_recover` · `test_q_broken_before_save_then_error_not_repost` · `test_q_lookup_failure_is_error_not_repost` | `ledger-after-post-off` |

시험 = 30 cases(25 → +5 · ⓟ2 ⓠ3) · 변이 12종(10 → +2) 전부 잡음. r1 반례 4건 그대로 닫힘(r2 시험 유지).
가짜 슬랙에 `conversations.replies`(조회) 와 3모드(ok · 저장 뒤 깨진 JSON · 저장 전 5xx)를 더해 실패·재실행 순서를 실제로 돌린다.

### 보강 5줄 (fable-5.1 검토 r955-r3 · arch 148 · 하드 룰 14)

| 보강 | 반영 | 시험/변이 |
|---|---|---|
| 1. 게시 검사 = `c.mask_text` 그대로(비밀 + 이메일·전화), `masker()` 만 쓰지 않는다 | `poster.secrets()` = `c.mask_text()` · 카드와 같은 함수 | ⓟ 12꼴(ghp_·xoxb-·webhook·PGPASSWORD·jwt·named-secret·sk·pg/redis DSN·전화·이메일) · `poster-secrets-off` |
| 2. 표식은 자기 검사에 안 걸리는 꼴 · 검사는 표식 붙인 최종 본문에 · «정상 쪽지 1회 게시» 시험 | `marker()` = base36 5자(`· ops-xxxxx`) · `guard(final_text(...))` | `test_d_posts_once_in_thread`(표식 정규식 단언) |
| 3. 확인 불가는 그 쪽지만 건너뛰고 다음 계속 · ERROR 줄에 사람이 푸는 명령 1개 | 루프 `continue` · ERROR 줄에 «원장에서 키 <key> 항목을 지우고 다시 보내세요» | `test_q_lookup_failure_is_error_not_repost` · `test_q_broken_before_save_then_error_not_repost`(2회 재실행에도 요청 1회) |
| 4. 원장 단일 실행 잠금(flock) · 동시 실행 시험 · 변이 «잠금 끔» | `lock_ledger()` = `state/posted.lock` LOCK_EX, 원장 읽기~게시~기록 전 구간 | `test_q_lock_serializes_runs`(결정적: 시험이 잠금을 쥐면 게시기가 1.2초 안에 못 지나간다 → 놓으면 1회 게시) + `test_q_concurrent_runs_post_once`(0.6초 지연으로 창을 연다 — 확률적 보조) · `lock-off` |
| 5. r3 반례 1 입력 표기 정정(`토큰 ghp_…더미`) · ⓟ = 그 꼴 + RULES 종류 전부 + 이메일·전화 | ⓟ 입력 12종 | 위와 같음 |

시험 = 32 cases · 변이 13종 전부 잡음(잠금 변이 3회 반복 재현). r1·r2 시험 그대로 유지(결과 불변).

## 반송 r4 (DA⑥ r3 HOLD 4 · 보류 3회째 · arch 148)

| 반례 | 자리 | 고침 | 시험 | 변이 |
|---|---|---|---|---|
| ① symptom `ghp_…\r…` → 마스킹 뒤 CR 삭제로 토큰이 다시 붙음 | write:57·:98·:107 | **정규화 먼저**: `normalize()`(제어문자·폭 0 제거 · 탭/개행 → 공백) → 검출 → 마스킹 뒤 불변. 쪼갠 토큰은 «구분자 지운 판» 을 한 번 더 검사 | `test_r_one_split_shapes_all_kinds`(9꼴 × 5분리자 = 45) · `test_r_masked_before_cr_removed_regression` | `cr-after-mask-off` |
| ② `키 AKIA…` 게시·원장 통과 (게시 쪽이 post_guard.SECRETS 의 aws-key 꼴을 안 씀) | poster:60·:62·:191 | **비밀 꼴 정본 하나**: `mask_text` = ft_secret_shapes.RULES ∪ post_guard.SECRETS(ops-intake 안에 꼴 0). 원장에 사용자 본문 자체를 남기지 않음 | `test_s_all_shared_shapes_blocked_and_not_in_ledger`(8꼴 · 원장 값 0 단언) · ⓡ 표가 합집합을 덮는지 단언 | `own-rules-off` |
| ③ 같은 사용자 동시 실행 → 카드 6장 · 임시 파일 충돌 예외 | write:37·:93·:107·:120 | **접수 쓰기 잠금**: `c.locked("ops-intake")` 안에서 한도 확인~쪽지 예약. `write_json` 은 `mkstemp` 로 프로세스별 임시 파일 | `test_t_concurrent_same_user`(4건 선행 + 동시 4실행 → 카드 ≤5 · Traceback 0 · limits.json 정상) | `lock-scope-off` |
| ④ 1바이트씩 흘리는 슬랙 → 8.77초 뒤 게시 성공 | poster:194 · mirror_lib:60 | **벽시계 7초**: `_call()` 이 읽기 루프마다 마감 확인(소켓 timeout 의존 0) · 초과 = TimeoutError → «확인 불가»(성공 처리 0) | `test_u_dribbling_slack_bounded`(7.6초 안 · rc5 · 원장 sending 유지) · `test_u_dribbling_ssh_bounded` | `socket-timeout-only` |

시험 = 38 cases(32 → +6: ⓡ2 ⓢ1 ⓣ1 ⓤ2) · 변이 17종(13 → +4) 전부 잡음.
공용 모듈 `harness/bin/ft_secret_shapes.py` 는 **손대지 않았다**(기존 `test_secret_scan.sh` 2건이 합집합 확장에 깨졌으므로 되돌림 — 대신 union 을 호출 시점에 만든다). 기존 하네스 시험 무회귀: `test_secret_scan.sh` FAIL 0 · `test_secret_output_mask.sh` ALL PASS · `test_slack_post_guard.sh` fail=0.

## 반송 r5 (DA⑥ r4 HOLD 3 · 하드 룰 14 보류 3회째 → 오빠 결정 1번 = 구현 한 번 더 + DA 1회 추가 · arch 151·156)

base = 보존 세트 `1e96e0c9` 위 amend 1커밋. 바뀐 파일 = `ops_intake_common.py` · `ops_intake_poster.py` · 시험 1 (나머지 스크립트·pull 데몬 = r4 승인판 그대로).

| 반례 (DA r4 원문) | 뿌리 | 고침 | 시험 | 변이 |
|---|---|---|---|---|
| R1 `password=\nhunter2hunter2` → `*** hunter2hunter2` (값이 남음) | `masker()` 가 꼴에 로컬 꼬리(`[^\s'"<>()…]*`)를 붙여 스스로 만든 판 + «안전한 결과를 버리는» 분기 | 로컬 꼬리 정규식 삭제. 공용 규칙표(`post_guard.SECRETS`)는 «판정» 과 «머리표 가림» 에만 쓴다 — 이름+구분자(`= : /`)로 끝난 머리표는 뒤 첫 덩어리를 통째로 `***` | `test_v_space_split_password_value_gone` | `own-mask-regex-off` |
| R2 `-----BEGIN…-----END` 개인키 본문 전체 보존 | 줄 단위 마스킹 | `drop_pem_blocks()` — BEGIN~END 블록을 «통째» 삭제(END 없으면 끝까지). 줄 단위로 남기는 길 0 | `test_v_pem_block_removed_whole` | 위와 같음 |
| R3 4초 성공 청크 + 8초 종료 → 8.1초 rc0 · sent=1 | 읽기 «전» 만 시간 검사(막힌 recv 는 안 끊김) | `_call()` 하나로 **전체 벽시계 7초**: 입구에서 `end` 고정 → ① 감시 타이머가 마감에 `sock.shutdown` 으로 막힌 recv 를 끊는다 ② 읽기 루프마다 남은 시간 확인 ③ 읽기가 끝난 뒤에도 마감 확인. 넘으면 TimeoutError → `sent` 0 · 원장 `failed` | `test_v_slow_finish_counts_wall_clock` | `read-only-timeout` |

카드 r5 추가 계약 «가림 뒤 공용 판정을 한 번 더 돌려 남으면 접수 거절» = `mask_for_card()` — `detect_raw(가린 글)` 과 «공백 지운 판» 을 보고 남으면 rc2 · 카드 0 · 쪽지 0(조용한 통과 0). 시험 `test_v_leftover_after_mask_rejects`(한 글자씩 31조각으로 쪼갠 토큰 = 창으로 붙일 수 없는 모양).

가림·판정 정본(복사 0):

| 축 | 정본 | 어떻게 |
|---|---|---|
| 비밀 가림 | `harness/bin/ft_secret_shapes.py` `mask()` — r977 착지판(origin/main `80a476d0`) | import 해서 그대로 호출. 착지판 사본으로 43 cases 재확인 rc=0 |
| 비밀 판정 | `kit/slack-mirror/post_guard.py` `SECRETS` | 규칙표만 import — `detect_raw()` 가 판정에, `_mask_shared_heads()` 가 머리표 가림에 |
| 개인정보 | 이 파일 정규식 2줄(전화·이메일) | 공용 가림 함수에 없는 축 · ⓑ·ⓟ 계약이 요구(비밀 꼴 아님) |

r4 승인 칸 중 바뀐 것 = 1칸: `test_u_dribbling_slack_bounded` 의 원장 상태 단언 `sending` → `failed` (카드 r5 계약 «넘으면 sent 0 · 원장 failed»). 나머지 38칸 그대로.

시험 = 43 cases(38 → +5) · 변이 18종(17 → +1 · `socket-timeout-only` 를 `read-only-timeout` 으로 교체, `own-mask-regex-off` 신설) — 전부 «잡았다».

```
bash feature-pack/fable-team/harness/tests/test_ops_intake.sh  → ALL PASS (rc=0)
  py_compile 5/5 · plutil 3/3 · cases 43/43 (134.7s) · mutate 18/18
```

press 필요: 없음 (정적 판정기·가짜 슬랙 시험만 · 라이브 축은 r956).

## 반송 r6 (오빠 결정 3 = 1번 구조 교체 · DA⑥ r5 HOLD 5 · arch 157)

base 를 팩 origin/main `8bdf4574`(r977 착지 포함 · bin/ft_secret_shapes.py = 착지판)로 올렸다(리베이스 · r6 = 그 위 1커밋). 반례 집합·계약 동결, 구현만 교체.

| 결정(동결) | 구현 | 시험 | 변이 |
|---|---|---|---|
| 가림 호출 자리 하나 = `mask_for_card()` → common `mask_text()` 한 곳 · write.py·poster.py 개별 호출 0 | write.py 는 `c.mask_text()`(diff 0 · 변경 금지) · poster 는 `c.post_kinds()`(common 한 자리를 거친다) | ⓔ `write.py diff 0`(.sh 러너) · 기존 ⓟ | `lock-scope-off`(write.py 축 유지) |
| 판본 sha256 고정 — 다르면 접수 거절 | `FT_SECRET_SHAPES_SHA256 = 8bdf45744dcc61aa…` · `_ft_mask()` 가 파일 해시를 대조, 다르면 rc2 «판본 다름» | ⓒ 두 번째 사유(사본에 한 줄 더한 모듈 → rc2) | `pin-off` |
| 따옴표 안 공백·개행 값 — 가림 전에 따옴표 «경계» 로 자른다 | `mask_quoted_values()`(따옴표 쌍만 본다 · 비밀 꼴 0) → 그 안을 통째로 `***` | ⓐ 108조합(따옴표 2 × 구분자 6 × 값 앞 공백·개행 9) 전부 `hunter2` 0 | — |
| 개인키 = `PRIVATE KEY` 를 품은 모든 BEGIN 줄 → BEGIN~END 통째 삭제 | `PEM_BEGIN/PEM_END` 머리말 집합 1개(PGP `KEY BLOCK` 포함) | ⓑ PGP PRIVATE KEY BLOCK → 본문·Version 줄 0 | — |
| 타이머 시작 = `urlopen()` «호출 전» 하나(연결·상태줄·헤더·본문·종료) · 넘으면 소켓 닫고 sent 0 · 실패 | `_call()` = 작업 스레드 + `done.wait(남은 시간)` + 마감에 `sock.shutdown` | ⓓ 상태줄 즉시·헤더 4초·끝 8초 → 7.0초에 끊김 · rc5 · 원장 failed | `timer-after-urlopen` |
| 원장 rejected 1줄(사유 종류만 · 값 0) | `record_rejected()` → `state/rejected.jsonl` `{"ts","reason":"leftover-secret","kinds":[…]}` | ⓒ 첫 번째 사유(잔여 → rc2 · 1줄 · `ghp_` 0) | — |
| 변경 금지 파일 되돌림 | `ops_intake_write.py` = r4 승인판 그대로(`c.mask_text` · `_write_locked` · `c.locked`) | ⓔ | — |

```
bash feature-pack/fable-team/harness/tests/test_ops_intake.sh   → ALL PASS (rc=0)
  write.py diff 0 · py_compile 5/5 · plutil 3/3 · cases 47 · mutate 19/19
```

press 필요: 없음 (가짜 슬랙·임시 HOME 만 · 라이브 축은 r956).
