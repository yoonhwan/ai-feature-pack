model: gpt-6.1-sol
provider: headroom

# AIRAG collector binding 설계 DA r2 — PASS (blocker 0, major 0, minor 2)

**판정: PASS — blocker 0, major 0, minor 2.** 발주 #1994의 r2 기술 설계는 r1의 D1/D2를 반영했다. “모든 물리적 교체 거부가 유지됨”을 철회하고, 동일 path/inode/session/scope·검증된 소비 prefix를 가진 다른 volume 사본의 다른 suffix를 기존 epoch로 수용하는 **내용 연속성 계약**을 명시했다. 해당 반례와 pending/first-row/수기 줄키를 검증 범위에 넣었다. 이 PASS는 새 계약을 전제로 한 기술 설계 판정이며 사용자 확인·운영 집행이 완료됐다는 뜻은 아니다.

- 세션: `ft-airag-da-codex#0`. 발주/직전 확인 모델 gpt-6.1-sol low, provider=headroom. 창 크기·fast 서비스 등급은 미노출. 실제 rollout은 metadata 확인용으로도 열지 않았다.
- HEAD: `5f6ac22fc767f0846cbc2f0a1cd62c795ff2b745`.
- 검토 입력: `.fable-team/state/airag-arch-claude/arch-binding-design.md`, 맨 위 개정 r2. SHA-256 `7068be9ee0a5864762187d63b3ea6d74eff78ad8f18bd755900300873dbea088`.
- 이번 입력은 state 경로의 개정본이며, 기존 tracked artifact의 r1 문구까지 갱신됐다고 주장하지 않는다.
- `0fdde41..HEAD`의 consumer source/tests diff 0을 확인했다. Serena로 loader/collect/참조를 재대조했고, ignored r2 설계는 exact path를 셸로 읽었다. 운영 DB·실제 rollout·op는 접촉하지 않았다.

## r1 지적의 반영

| r1 항목 | r2 반영 | 판단 |
|---|---|---|
| D1: R7 전체 물리 동일성 유지 주장 | 권고/3.2에서 철회. 유지/비유지 표와 다른 volume 복제 prefix·다른 suffix의 기존 epoch 수용을 명시. | 닫힘 |
| D1: 반례가 위험 아님/동일 전체 내용이라는 설명 | suffix가 달라도 수용하는 의도된 비보장으로 변경. 위협 모델을 소비한 바이트의 무결성·단일 사용자 로컬 수집으로 한정. | 닫힘(새 계약 전제) |
| D1: 반례 테스트 없음 | T-bind-cross-volume-clone-accepted에 실제 os.replace + 새 파일의 lstat/fstat 일관된 device/inode 모델링 + 새 suffix 이벤트/old epoch 단언. | 닫힘 |
| D2: normalized id 입력 경로 | 같은 source_id를 유지하고 stored normalized_source_id만 바꾸는 fixture를 명시. | 닫힘 |
| D2: pending 재처리·offset 0 누락 | lost-ack+drift, first-row zero-prefix 테스트 추가. zero 상태의 발생 설명 보정은 R2-m1이다. | 핵심 반영 |
| D2: helper 추출 후 수기 분류 이동 | reason_code_review.py 줄키 갱신을 허용하고 구조/행위 커밋마다 registry 값 불변·closed-world 검증. | 닫힘 |

## 같은 5축 재점검

### 1. 신원 규칙과 새 내용 연속성 계약

r2는 r1에서 실제로 통과한 물리적 replacement 반례를 의도한 acceptance로 다룬다. 이는 물리적 동일성을 보증하는 설계가 아니며 악의적 replacement를 방어한다고도 주장하지 않는다. path/realpath/inode/session/tenant/project/normalized id와 prefix 검사·같은 실행 안의 lstat/fstat 경합 검사를 유지한다.

따라서 검증할 계약은 “같은 파일의 물리적 기원”이 아니라 **지정 필드와 이미 커밋한 내용이 맞는 이어받기**다. 이 범위를 받아들일 때 설계/행위/테스트의 불일치는 해소된다. 고유 inode로 교체되는 기존 R7 예시는 계속 거부된다. 다른 volume의 동일 inode 사본을 일반 R7 보호에 포함해 다시 설명해서는 안 된다.

### 2. B4·incarnation·producer_epoch

stored device/inode를 원래 seed 형식으로 검산하고 row[2]를 그대로 반환하는 방향은 적절하다. hash는 자기 일관성 검산이며 모든 행의 인증이 아니라는 정정도 반영됐다. 기존 ledger scope/incarnation binding과 plan reconstruction을 깨는 새 epoch mint를 하지 않는다.

r1의 합성 정상 drift/pending 재처리에서 기존 epoch, first_seen_at/normalized_sha256, event 중복 0을 확인했다. source 코드가 같으므로 이 근거를 다시 전체 실행하지 않았다. pending 회귀에서 “checkpoint 불변”은 이미 선행 commit된 **ledger normalized checkpoint**와 구분해 단언해야 한다. collector native checkpoint는 ack 복구 과정에서 정상적으로 앞으로 따라잡는다.

### 3. 다른 호출 경로와 원인 가설

search/status/backup verification이 현재 volume의 물리적 동일성을 인증하지 않는다는 한계를 r2가 명시했다. 복원된 metadata도 같은 내용 연속성 재방문 정책을 받는다. tour의 별도 device 검사는 범위 밖이다.

실제 stored row는 아직 미확인이다. ⑥의 device-only 우선 가설·B2/B4 확인 사다리가 맞으며, ①의 “같은 파일이 거부됐다”, “다른 필드는 모두 같다”, “소스 교체/손상 배제” 문장도 이 가설 수준으로 읽어야 한다. inode/mtime만으로 사본이나 logical row 손상을 직접 배제하지 못한다. scratch의 운영 DB 사본도 데이터 출처는 운영이며 이 DA의 합성 실험이 아니다.

### 4. shift/clone/first-row/pending 테스트

clone helper는 **새 파일의 실제 inode**를 대상으로 fstat/lstat을 찾아, 그 반환에 저장된 old inode 번호와 shifted device를 함께 덮어써야 한다. old inode로 FD를 찾으면 os.replace 뒤 새 FD를 놓쳐 false SOURCE_CHANGED_DURING_OPEN이 날 수 있다. 새 물리 inode가 실제로 다름, prefix가 원래 소비 bytes와 일치, suffix가 다름, old epoch·새 이벤트 수용을 각각 확인한다. 무관한 FD/파일은 원본 값을 유지한다.

first-row와 pending 상태를 별도로 고정하는 것도 타당하다. offset 0은 과거 내용의 anchor가 없고 session/B2 및 row 검산만 증거다. pending은 소비 prefix 외에 pending record의 native_sha256/reconstruction을 유지한다. caller의 expected_session_id만 바꾸면 앞선 session/scope guard에 막힐 수 있으므로 field matrix는 direct stored-row fixture 또는 일관된 meta/scope 입력으로 **의도한 loader guard에 도달하는지** 확인한다.

### 5. 큰 증분 부하

정확한 committed offset은 읽지 않았으므로 plan 한도와 실제 checkpoint를 동일하게 확정하지 않는다. 8 MiB는 native cursor 진행량 제한이며 기존 prefix hashing·record finalize·memory/provider 작업의 시간/I/O 상한은 아니다. 첫 수동 운영 부하 관찰은 설계 안전 검토와 별개이며 본 DA에서 live 부하를 실행하지 않았다.

## Minor

### R2-m1 — offset 0 existing row를 재부팅 직전 예외 상태로만 설명한다

- 위치: 3.2 first-row 설명의 “행 생성 직후 재부팅 전 재방문에서만” 및 T-bind-drift-before-first-commit.
- 현재 public API의 **정상 `captured_byte_limit=0`** 호출은 `_load_or_create_source`를 커밋한 뒤 loop를 돌지 않고 반환한다. 기존 row에 next_native_offset=0/빈 prefix가 남으며 예외나 reboot가 필요하지 않다. 작은 capture/batch로 첫 record를 완성하지 못하는 경우도 동일 상태의 원인이 될 수 있다.
- 새 합성 관찰:

```text
ZERO_CAPTURE_RETURNED_WITHOUT_EXCEPTION true
ZERO_CAPTURE_SOURCE_ROW_OFFSET 0
ZERO_CAPTURE_PREFIX_IS_EMPTY true
CANDIDATE_ZERO_CAPTURE_THEN_DEVICE_DRIFT_ACCEPTED true
CANDIDATE_ZERO_CAPTURE_OLD_EPOCH_PRESERVED true
```

- 후보는 r2가 의도한 동작대로 수용했고 epoch도 보존했다. 구현 실패 major가 아니라 occurrence/검증 범위의 보정이다. 설명을 **원인과 무관한 zero-prefix existing row**로 고치고 정상 zero-capture와 예외 중단 상태를 함께 회귀로 고정한다. 이 상태에 소비한 과거 내용이 검증됐다는 의미를 부여하지 않는다.

### R2-m2 — 사용자 확인 문구와 잔여 표현을 정합하게 해야 한다

- 위치: ② “확인 1건 권고·이의 없으면 진행”, B6/선택표의 “새 DB 쓰기 없음”, ① 원인 확정 문장.
- **무응답은 승인 값이 아니다.** 확인을 승인 게이트로 운영한다면 top Master가 명시 답을 받은 뒤 값을 전달해야 한다. 단순 통지 권고이고 기존 허용 scope에서 준비를 진행한다면 그것을 “사용자가 수용/승인함”으로 기록하지 않는다. 하위 DA가 사용자 인터뷰를 진행할 사안은 아니다. 본 PASS는 승인을 대신하지 않는다.
- ②의 새 문구대로 **identity 재작성/마이그레이션 없음**과 정상 collection의 checkpoint/plans/events 쓰기를 구분해 B6·표의 옛 무쓰기 문장도 맞춘다.
- 원인 확정/손상 배제처럼 남은 옛 문장은 ⑥의 가설·미확인 한계와 일치하도록 좁힌다. rollback과 실패 후 mtime 불변은 기존 logical row 값이 정상이라는 직접 증거가 아니다.
- E의 legacy 첫 전환에 stable volume anchor가 없다는 기각 이유는 이해된다. 다만 한번 anchor를 기록한 뒤의 **미래 재방문에서** 추가 구분 이득이 있을 수 있으므로 “새 안정 식별자도 언제나 같은 보증”으로 확대하지 않는다. 현재 범위/복잡도 때문에 E를 선택하지 않는 결정과 가능한 미래 기능은 구분한다.

## 증거·범위

r1 후보 A와 현재 source/tests는 `0fdde41..5f6ac22`에서 그대로다. r1에서 실행한 drift/clone/pending/prefix/tamper 후보 결과와 collector 기준선 **19 passed in 0.21s**를 기존 독립 증거로 대조했고, 이번 r2에서는 zero-capture 상태를 새로 확인했다. 기준선이나 전체 consumer를 이번 라운드에서 반복 실행했다고 주장하지 않는다. 아직 repository 구현/코드 DA가 없으므로 r2 문서의 새 테스트 전체가 실제로 작성·통과한 판정도 아니다.

zero-capture probe는 resolved 임시 경로·합성 rollout/ledger를 사용했다. source loader의 existing-row 비교만 inspect/AST로 메모리 후보를 만들고, 실제 collector/ledger/prefix 코드로 실행했다. 운영 DB·실제 rollout·op·외부 endpoint를 접촉하지 않았다.

source/test/설계 원문·설정 수정, commit/push/일반 프로세스 종료를 하지 않았다. 신규 산출물은 이 판정서 하나다.

**최종: PASS (blocker 0, major 0, minor 2).** r1의 계약/동작 불일치는 닫혔다. zero-prefix 상태의 설명·검증과 사용자 확인/잔여 문구를 보정하고, 실제 구현에서는 r2의 유지/비유지 표와 acceptance 회귀를 그대로 검증해야 한다.
