# Nano item4 r3 결과 — DA r5 잔존 major 2·minor 1 수정

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 4순위(C05·C06) DA r5(PASS, major 2·minor 1 잔존) → major 0 로 닫기.
- 수정은 전부 투어 helper(`.fable-team/bin/tour/memory_confirmation.py`, gitignore 영역). 코어(`feature-pack/rag-consumer`)는 변경하지 않았다. 커밋·push 안 함. `~/.local/share/airag`·운영 키·실데이터 미접촉(합성 fixture 만), 기억 본문·키 값 미출력.
- `verify_14_isolated.py` 최종 줄: `ALL 26 CHECKS PASSED` (기존 19 + 신규 7)
- pytest (`feature-pack/rag-consumer`): `218 passed in 7.26s` (기준선 218, 코어 무변경)

## 대조 — DA r5 설명 3건 모두 코드와 일치

### R5-M1 — 겹친 결정 호출의 로그 유실
- 원인: `decide` 의 «로그 읽기 → 의도 쓰기 → 코어 변경 → 마무리 쓰기» 전체가 직렬화되지 않아, 먼저 읽은 호출이 나중에 전체 파일을 덮어써 다른 호출의 항목이 사라진다(atomic rename 은 개별 교체만 보호).
- 수정: 프로젝트 폴더의 `tour-14.lock` 에 `fcntl.flock(LOCK_EX)` 를 거는 `decision_lock(app)` 을 추가하고, 로그 읽기부터 마무리 쓰기까지를 그 안에서 실행. 백업 게이트(`verified_receipt`)는 락 밖에 둬 락 보유 시간을 짧게 유지. flock 은 프로세스·스레드 모두에서 배타. `memory_confirmation.py` `decision_lock`, `decide` 의 `with decision_lock(app):` 블록.
- 추가 check: `R5-M1 both overlapping decisions applied` · `R5-M1 both decisions stay in the log`. A 를 첫 write 직전에 최대 1.5초 멈추고 그 사이 B 를 실행하는 합성 스레드 시나리오(저장·승인·마무리는 실제 구현).
- Red: 두 호출 모두 materialized 이지만 `R5-M1 both decisions stay in the log · 1 entries` 실패(B 의 의도·결과 소실). Green: 2 entries, 두 후보 모두 `done` 결과 기록.

### R5-M2 — 영수증 at·run 재작성으로 48시간 전 실제 백업 재사용
- 원인: 신선함 근거가 재작성 가능한 영수증의 `at`·`run` 뿐이었다. 실제 `verify_backup` 성공은 복원 가능성만 증명하고, helper 는 verify 결과의 `completed_at`(runtime.py 가 manifest 에서 반환)을 쓰지 않았다.
- 수정: `verified_receipt` 가 실제 검증 결과의 `completed_at` 으로 나이를 다시 계산해 0~6시간을 요구(미래·초과는 `BACKUP_RECEIPT_STALE`). 영수증의 `at` 검사는 유지(이중 조건). `memory_confirmation.py` `verified_receipt` 의 `completed_age`.
- 추가 check: `R5-M2 old backup still passes real verification`(재작성 전제 확인) · `R5-M2 rewritten receipt cannot reopen decisions` · `R5-M2 core unchanged`.
- Red: 영수증 at·run 재작성 + 시계 2일 진행 후 `decide` 가 예외 없이 통과(`no exception`), 코어 기억 증가. Green: `BACKUP_RECEIPT_STALE`, 코어 무변경.

### R5-m1 — run 없는 backup 이 실제 백업을 만든 뒤 실패
- 원인: `backup` 액션이 강제 백업·검증을 수행한 다음에야 run 을 검사.
- 수정: run 검사를 `before = counts(app)`·`app.backup(...)` 앞으로 이동(기존의 뒤쪽 검사는 제거). `memory_confirmation.py` `work` 의 `backup` 분기.
- 추가 check: `R5-m1 run-less backup refused` · `R5-m1 refusal created no backup`(거부 호출 전후 `backup_count` 불변).
- Red: `R5-m1 refusal created no backup` 실패(backup_count 증가). Green: 불변.

## 부수 변경
- `verify_14_isolated.py`: 위 7개 check 추가, `ISO14_KEEP_GOING=1` 환경변수(첫 실패에서 멈추지 않고 모든 FAIL 출력 — 진단용, 기본 동작은 기존과 동일), `threading` import.

## 참고 (DA 보고서와 별개)
- 작업 중 `feature-pack/rag/docs/artifacts/da-20261001-sol-r4.md` 가 내 작업과 무관하게 수정 상태로 표시되어 있었다(git status). 내가 바꾼 것이 아니며 건드리지 않았다.
- 선행조건(설치 런타임 재설치, 투어 파일 gitignore)은 이전 결과 그대로.

## 변경 파일
- gitignore 영역(`.fable-team/bin/tour/`): `memory_confirmation.py` · `verify_14_isolated.py`
- git 추적 파일 변경 없음.
