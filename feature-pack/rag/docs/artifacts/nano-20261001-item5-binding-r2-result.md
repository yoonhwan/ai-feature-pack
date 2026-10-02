model: claude-sonnet-5-5[1m]
provider: claude-code session (ft-airag-nano-r1#1, effort=high)

# AIRAG binding r2 — DA r16 minor R16-m1 결과

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 5순위 U1(C12·C07) — DA r16 minor R16-m1(zero-prefix 테스트의 event/ledger epoch 직접 비교 누락). 발주 #2013(HELM #2012).

## 결과
커밋 `5f3ec4d` ([test]) · consumer 전체 pytest 마지막 줄: `364 passed` (기준선 유지; 추가 단언만이라 개수 불변 — 실행 출력 원문은 아래 확인란). **`src/` 변경 0**(`git diff --stat -- feature-pack/rag-consumer/src` 빈 출력). push 없음.

## 변경
`tests/test_collector.py::test_a_row_with_nothing_consumed_yet_survives_a_device_change`(`zero_limit`·`interrupted` 두 파라미터)에 기존 단언 유지 + 추가:
- `stored_events(ledger)[0]["producer_epoch"] == 최초 stored incarnation`(= device shift 전에 읽은 `source_row` 의 incarnation)
- `SELECT incarnation FROM sources`(ledger.sources) `== (최초 stored incarnation,)`

## 뮤테이션 확인
- 추가 후 정상 코드: 2 passed.
- 임시 뮤테이션: `collector._normalize_message` 가 만드는 event 의 `"producer_epoch": producer_epoch` 를 `"mutated-epoch"` 로 교체 → 두 파라미터 **모두 FAILED**(`2 failed`; DA r16 은 수정 전 두 테스트가 통과했다고 보고).
- 원복: 백업 파일로 되돌린 뒤 `git diff --stat` 에 `tests/test_collector.py` 3줄만 남음 — 뮤테이션이 작업트리·커밋에 남지 않음.

범위·금지 확인: 테스트만 변경. 운영 DB·실제 rollout·op·launchd·runtime.json 접촉 없음. 신규 *.md 는 이 파일 하나.
