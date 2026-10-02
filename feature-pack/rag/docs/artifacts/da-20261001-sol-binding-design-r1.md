model: gpt-6.1-sol
provider: headroom

# AIRAG collector binding 설계 DA r1 — REJECT (blocker 0, major 1, minor 1)

**판정: REJECT — blocker 0, major 1, minor 1.** 발주 #1984의 major 0 기준은 충족하지 못한다. device가 재부팅 뒤 달라지는 가설과 저장 incarnation을 유지하는 방향은 코드/체커 사실에 부합한다. 합성 후보에서 정상 device drift·pending 재처리·prefix/절단/새 inode 거부도 확인했다. 다만 “R7 파일 교체 탐지가 약해지지 않는다”는 보장은 성립하지 않는다. 다른 물리 파일이 동일 inode 번호·기존 소비 prefix를 가지면 **다른 미소비 suffix를 기존 epoch로 수용**한다. 이 새로운 내용 연속성 수용 규칙을 물리적 파일 동일성과 구분해 계약·검증에 반영해야 한다.

- 세션: `ft-airag-da-codex#0`. 발주 표기 `gpt-6.1-sol low fast`, 직전 runtime 확인 model/provider는 위 두 줄·effort=low. 창 크기·fast 서비스 등급은 미노출이다. 이번 검토에서는 실제 rollout을 metadata 확인용으로도 열지 않았다.
- 최신 발주 #1984를 기준으로 동일 설계의 이전 #1981 요청도 대조했다. 회신 대상은 최신 Master 발주의 `ft-airag-master-claude#1`이다.
- HEAD: `0fdde41ce59dc2413f1d90d71faac1cdb04b1d4c`.
- 설계: `arch-20261001-item5-binding-design.md`, SHA-256 `01c96e5c99fd7910420244c2a8f93af9372dc874a9f5c566bcb4ecb501fabe45`.
- 입력 사실: `.fable-team/state/airag/checker-binding-facts.json`만 읽었다. 그 안의 운영 경로를 열거나 stat/hash/DB 조회로 재검증하지 않았다.
- Serena로 collector/ledger/runtime의 본문·참조 및 p08a01 계약/R7 기존 판정을 대조했다. ignored checker facts는 셸로 읽었다. source·테스트·설계 원문은 수정하지 않았다.

## Major — D1: physical replacement 거부와 prefix 연속성 수용을 동일 보장으로 설명한다

- 위치: 설계 ② 권고의 R7 유지 주장, ③3.2 안전성 논증, ⑥4의 “실질적으로 같은 소스” 잔여 설명.
- 같은 소비 prefix의 SHA-256은 **이미 커밋한 바이트의 동일성**을 증명한다. 미소비 suffix나 물리적인 파일/볼륨의 동일성을 증명하지 않는다. inode는 filesystem별 번호이므로 다른 볼륨에서 같은 숫자를 가질 수 있다. device를 비교에서 제외하고 저장 device로 incarnation을 검산하면 현재 볼륨이 기존 볼륨과 같은지는 검증하지 않는다.
- 기존 R7은 같은 바이트의 새 inode 교체를 거부하며, 현재 코드의 device+inode binding은 다른 volume/device도 거부한다. A는 새 inode 거부를 유지하지만 다른 볼륨의 동일 inode 번호·경로·session·소비 prefix 복제는 허용한다. R7 전체가 약해지지 않는다고 표현할 수 없다.

### 독립 end-to-end 합성 반례

현재 `_load_or_create_source`를 읽어 **메모리에서만** A의 비교 변경을 구성했다. INSERT는 그대로, existing-row 비교에서 device만 제거, incarnation은 stored device/inode로 검산하고 원래 row[2]를 반환한다. 실제 collect/ledger/plan/normalization/prefix 코드는 원본을 실행했다.

1. 합성 rollout의 session_meta와 메시지를 수집한다.
2. 같은 실제 파일에 append한 뒤, 해당 source의 lstat/fstat만 device+1로 바꾸면 A는 정상 이어받는다.
3. 실제 `os.replace`로 **다른 물리 파일**을 같은 경로에 놓는다. 기존 소비 prefix를 복사하고 새 메시지 suffix를 추가한다.
4. 다른 볼륨의 동일 inode 사례를 모델링하도록 이 새 source의 lstat/fstat만 device+1·저장된 inode 번호로 일관되게 반환한다. 실제 다른 볼륨을 마운트하거나 운영 경로를 사용하지 않았다.
5. 현재 코드는 COLLECTOR_SOURCE_BINDING_MISMATCH로 거부한다. A는 새 suffix를 수용하고 이전 producer_epoch를 그대로 쓴다.

```text
REPLACEMENT_ACTUAL_INODE_CHANGED true
CURRENT_OTHER_VOLUME_SAME_INODE_CLONE COLLECTOR_SOURCE_BINDING_MISMATCH
CANDIDATE_OTHER_VOLUME_SAME_INODE_CLONE_ACCEPTED 3
CANDIDATE_CLONE_OLD_EPOCH_REUSED true
```

accepted=3은 **누적 카운트**다. 앞서 2개를 수집한 상태에서 새 replacement의 suffix 메시지 1개가 추가 수용됐다. prefix hash collision을 만든 공격이 아니라 기존 prefix를 그대로 복사한 경우다.

### 닫아야 할 설계 결정

내용 기반 이어받기를 새 계약으로 택하는 것은 가능한 방향이다. `p08a01-contract.json:47`도 persisted incarnation을 session id·verified prefix에 묶는 표현을 사용한다. 다만 그것을 **다른 파일을 거부한다는 기존 물리적 R7 보장이 그대로라는 근거**로 쓰면 안 된다.

- 내용 연속성을 수용한다면 동일 prefix·동일 session/inode/path를 가진 다른 volume 파일의 **다른 suffix도 수용한다**는 사실, 기존 epoch 재사용의 의미, first-row offset 0 및 pending-plan 때의 수용 조건을 계약에 명시하고 위 반례를 의도한 acceptance/rejection 회귀로 고정한다. 그 계약 선택을 전제로 R7의 유지되는 범위를 새 inode·path/scope·committed prefix 등의 거부로 한정한다.
- 물리적 다른 volume/file 교체 거부를 유지해야 한다면 stable filesystem identity 또는 검증된 전환 근거가 필요하다. stored ephemeral device를 hash에 다시 넣는 것만으로 그 보장은 복구되지 않는다.

방향 A 자체나 실제 데이터 유출을 단정하는 판정이 아니다. 현재 판정의 major는 **핵심 안전 보장과 실제 허용 범위의 불일치**다. 합성 반례를 “같은 전체 내용이므로 위험이 아님”으로 제외한 채 major 0으로 승인할 수 없다.

## B4·ledger/producer_epoch·다른 경로

저장 row[9]/row[10]을 이용해 기존 seed 형식 그대로 검산하면 새 device로 epoch를 mint하지 않는다. 저장 row가 정상이고 prefix가 일치하는 경우 ledger `_bind_source`의 incarnation/scope/policy-version과 event producer_epoch가 유지된다. 합성 정상 drift와 lost-ack pending 재처리에서 이를 확인했다.

```text
CURRENT_DEVICE_SHIFT COLLECTOR_SOURCE_BINDING_MISMATCH
CANDIDATE_DEVICE_SHIFT_ACCEPTED_EVENTS 2
CANDIDATE_SOURCE_METADATA_UNCHANGED true
CANDIDATE_ALL_PRODUCER_EPOCHS_STABLE true
CANDIDATE_REPLAY_CHECKPOINT_STABLE true
DEVICE_DRIFT_PENDING_PLAN_EVENT_COUNT 1
DEVICE_DRIFT_PENDING_PLAN_FINALIZED true
DEVICE_DRIFT_PENDING_EPOCH_STABLE true
STORED_ROW_SINGLE_FIELD_TAMPER device COLLECTOR_SOURCE_BINDING_MISMATCH
STORED_ROW_SINGLE_FIELD_TAMPER incarnation COLLECTOR_SOURCE_BINDING_MISMATCH
CANDIDATE_DRIFT_PREFIX_REWRITE SOURCE_PREFIX_REWRITTEN
DEVICE_DRIFT_TRUNCATION SOURCE_TRUNCATED
DEVICE_DRIFT_DIFFERENT_INODE_REPLACEMENT COLLECTOR_SOURCE_BINDING_MISMATCH
```

첫 accepted=2 역시 기존 1개+append 1개의 누적이다. source metadata 불변은 device/inode/incarnation identity 컬럼에 대한 것으로, 정상 수집의 offsets/prefix/plans/events는 기존대로 갱신된다. 따라서 설계의 “운영 DB에 아무것도 쓰지 않는다”는 문장은 **identity 재작성/마이그레이션을 요구하지 않는다**로 좁혀야 한다. 수정 후 정상 collection까지 DB 무쓰기라는 뜻은 아니다.

B4는 row의 **자기 일관성 검산**이다. unkeyed hash이므로 모든 컬럼의 인증이나 일관되게 다시 쓴 row에 대한 독립 tamper 인증은 아니다. offset/prefix는 이후 파일 검사, producer_epoch는 ledger binding/plan replay가 각각 책임진다. 저장 device만 바꾸거나 incarnation만 바꾸는 경우는 위처럼 조기에 거부된다.

`_open_enrolled`·`_finalize_plan`의 같은 실행 안에서의 dev/inode 경합 검사는 그대로 유지해야 한다. collector만 epoch를 바꾸지 않으므로 ledger/search의 source namespace가 새 epoch로 갈라지지 않는다. backup/restore의 `_verify_ledger_links`는 contiguous receipts와 normalized checkpoint를 대조하고 device를 재비교하지 않는다. 기존 snapshot으로 복원한 뒤의 source 재방문도 같은 정책 선택(D1)을 받으며 백업 검증이 현재 source의 물리적 volume 동일성을 대신 증명하지는 않는다.

## Minor — D2: 테스트 입력·필수 검증 파일의 명세를 보완해야 한다

- 위치: ④ field-mismatch matrix 및 ⑤ B1/B5 변경 파일 목록.
- **normalized suffix는 독립 public 인자가 아니다.** source_id를 바꾸면 다른 PK로 SELECT/INSERT하며 normalized_source_id도 새 값으로 만들어진다. 기존 행의 suffix mismatch 검사를 시험하려면 source_id를 유지한 합성 stored normalized_source_id를 바꾸거나 해당 binding row를 직접 fixture로 구성해야 한다. 단순 source_id 변경에 COLLECTOR_SOURCE_BINDING_MISMATCH를 기대하는 테스트는 다른 경로를 시험한다.

```text
PUBLIC_SOURCE_ID_CHANGE_SELECTS_NEW_ROW true
PUBLIC_SOURCE_ID_CHANGE_SOURCE_ROWS 2
NORMALIZED_SUFFIX_NOT_INDEPENDENT_INPUT true
```

- **pending-plan+drift 회귀가 빠져 있다.** 기존 lost-ack 테스트에 device drift를 결합해 first_seen_at·normalized_sha256·producer_epoch·checkpoint 및 event 중복 0을 고정한다. 독립 후보 probe에서는 성공했지만 source.incarnation을 바꾸는 잘못된 구현을 잡는 영구 테스트가 필요하다. committed-prefix가 아직 0인 existing row도 별도 경우다.
- **수기 reason-code 위치가 이동할 수 있다.** `tests/reason_code_review.py`에는 collector.py:443의 EXCLUDED_NON_MESSAGE_RESPONSE/EXCLUDED_REASONING 출현이 줄 번호로 고정돼 있다. `_incarnation` 추출·binding 코드 변경으로 이 줄이 이동하면 structural commit부터 closed-world가 실패한다. 필요한 수기 키 갱신을 변경 파일 범위에 허용하고 reason_codes 값 불변과 review 항목 일치를 별도로 검사한다. line padding으로 문제를 가리는 것을 권하지 않는다.
- D1의 동일 inode/다른 volume·복제 prefix/다른 suffix 반례도 명세에 들어가야 한다. 기존 “새 inode replacement” 테스트만으로 해당 정책 변화를 검증하지 못한다.

## 원인 가설의 근거와 한계

체커 사실상 type=EventError와 call path는 collector의 `_load_or_create_source` throw와 맞다. plan의 dev와 현재 dev 차이, 같은 inode·선택 경로/session 설정, 부팅 시각·이전 성공 수집이 가설을 지지한다. allow_gaps는 이후 `_classify`에서만 쓰므로 이 binding 오류의 원인이 아니다.

그러나 실제 stored row는 미확인이다. plan/current inode가 같다는 것만으로 다른 volume의 inode 재사용·복제 파일을 배제할 수 없으며, DB의 source_path/normalized id/incarnation 등 전체 비교 값이 plan과 동일함을 직접 증명한 것도 아니다. **device drift는 우선 가설**이고 “device 단독 원인”은 아직 실제 row로 확정되지 않았다. 수정 후 같은 코드가 남는 경우도 B2 필드뿐 아니라 B4의 stored-row/incarnation 문제를 포함할 수 있다. 후보의 합성 성공을 운영 원인 확정으로 표현하지 않는다.

운영 DB 복제본은 데이터 출처가 운영이라는 점에서 합성 fixture가 아니다. 이 검토에서는 복제·키 조회·실제 rollout 읽기를 수행하지 않았다. 미래 Master의 점검은 이번 증거와 구분된다.

## 첫 46MB 증분 부하 — 별건

체커가 기록한 현재 source 크기는 약 46MB이고, 과거 capture 한도는 plan 254,203B와 문서 28,156,963B가 불일치한다. **실제 committed offset은 미확인**이므로 첫 패스의 정확한 증분을 46MB−특정 한도로 확정하지 않는다.

max_batch_bytes=8 MiB는 이번 호출의 native cursor 진행량을 제한하지만 총 I/O·시간·LLM 부하 상한은 아니다. `_prefix_sha256`이 기존 committed prefix를 읽고 record finalize 때도 prefix를 계산하며, 이후 memory/provider 작업이 붙을 수 있다. live 부하를 이 설계 DA에서 실행하지 않았다. device 변경의 안전 판정과 운영 첫 패스 관찰은 별개다.

## 독립 검증과 범위

현재 기준선:

```text
../rag/.venv/bin/python -m pytest tests/test_collector.py -q -p no:cacheprovider
19 passed in 0.21s
exit 0
```

후보 A는 inspect/AST로 현재 함수의 existing-row 비교만 변경한 **별도 Python 프로세스의 메모리 함수**다. 저장 incarnation은 원본 row를 사용하고 actual collector/ledger/prefix/plan 코드를 실행했다. fake device/inode는 임시 source의 lstat/fstat만 감싸고 다른 파일/FD는 원본 값을 유지했다. 실제 reboot/다른 volume mount·운영 DB/rollout·op·외부 endpoint를 사용하지 않았다.

| 검토 파일 | SHA-256 |
|---|---|
| `feature-pack/rag-consumer/src/airag_consumer/collector.py` | `1d89f368762335fbcf075f4f8d2a538ad023c6afbe7cc466e1270ffd8164c708` |
| `feature-pack/rag-consumer/src/airag_consumer/ledger.py` | `6f6ff9b97618604529dc11d3442f87577578c5b7ac58809ad60879b051389c97` |
| `feature-pack/rag-consumer/tests/test_collector.py` | `d3cfecfed95d8a10b3e0b201f06721effbbea353bc8433aa6dd84bf82716385f` |

source/test/설계 원문·설정 수정, commit/push/일반 프로세스 종료를 하지 않았다. 신규 산출물은 이 판정서 하나다.

**최종: REJECT (blocker 0, major 1, minor 1).** D1의 물리적 동일성/내용 연속성 계약과 반례의 수용 정책을 먼저 명확히 하고, D2의 실제 가능한 입력·pending 회귀·수기 분류 갱신을 구현 명세에 반영하면 major 0 여부를 재검토할 수 있다.
