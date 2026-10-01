# Nano item5 결과 — DA r6 잔존 R6-M1·R6-m1 수정

- 세션: `ft-airag-nano-r1#0` · 모델: claude-sonnet-5-5[1m]
- 골의 어느 축인가: A03 — A02 트리 5순위(사용자 판정 «5순위 때 처리») — R6-M1·R6-m1 수정 → DA major 0.
- 변경은 투어 폴더(`.fable-team/bin/tour/`, 이제 git 추적)의 helper·검증 스크립트 2개뿐. 코어(`feature-pack/rag-consumer`) 무변경. 커밋·push 안 함. `~/.local/share/airag`·launchd·운영 키 미접촉(합성 fixture 만), 기억 본문·키 값 미출력.
- `verify_14_isolated.py` 최종 줄: `ALL 33 CHECKS PASSED` (기존 26 + 신규 7), 기본·`ISO14_KEEP_GOING=1` 모두 exit 0
- pytest (`feature-pack/rag-consumer`): `218 passed in 7.26s` (기준선 218, 코어 무변경)

## R6-M1 — 락 대기 뒤 신선함 재검사 없음
- 원인(DA 설명과 일치): 6시간 신선함 검사(`verified_receipt`)가 `decision_lock` 진입 «전»에만 있었다. 다른 프로세스가 쥔 flock 에서 오래 기다리면 락을 얻은 뒤 의도/코어 쓰기 시점에는 이미 6시간을 넘겨도 그대로 적용됐다.
- 수정: 신선함 판정을 `assert_fresh(app, receipt)`(영수증 `at` 과 검증 결과 `completed_at` 모두 현재 시계로 0~6시간)로 분리하고, `verified_receipt` 가 `completed_at` 을 영수증 사본에 실어 반환. `decide` 는 `decision_lock` 을 얻은 «직후», 로그 읽기·의도 쓰기 전에 `assert_fresh` 를 다시 호출. 비용 큰 복원 검증은 기존대로 락 밖. `memory_confirmation.py` `assert_fresh`, `verified_receipt`, `decide` 의 락 블록 첫 줄.
- 추가 check: `R6-M1 lock holder is running` · `R6-M1 gate passed while the lock is held elsewhere` · `R6-M1 decision is waiting, core untouched` · `R6-M1 stale-after-wait decision is refused` · `R6-M1 core unchanged after refusal`. 방법: 별도 Python 자식 프로세스가 실제 `tour-14.lock` 을 쥐고, 합성 시각을 백업 완료 후 5시간 59분으로 맞춘 뒤 helper `decide` 를 스레드로 호출, 게이트 통과(Event)·대기 중·기억 0 을 확인하고 시각을 2분 진행한 다음 자식을 정상 종료(stdin 신호)시켜 락을 해제.
- Red: 대기 후 결정이 예외 없이 적용(`stale-after-wait decision is refused · None`)되고 코어 기억이 증가(`core unchanged after refusal` 실패). Green: `BACKUP_RECEIPT_STALE`, 코어 무변경.

## R6-m1 — KEEP_GOING 이 실패를 출력하고도 ALL PASSED·exit 0
- 원인(DA 설명과 일치): 마지막 요약이 `RESULTS` 의 실패 여부와 무관하게 `ALL N CHECKS PASSED` 를 출력.
- 수정: 요약을 `finish()` 로 분리. 실패가 하나라도 있으면 `FAILED n of N CHECKS: <이름들>` 을 출력하고 `SystemExit(1)`, 없으면 기존 `ALL N CHECKS PASSED`. `verify_14_isolated.py` `finish`. 기본 모드(첫 실패에서 즉시 중단)는 동작 불변.
- 추가 check: `R6-m1 KEEP_GOING failure ends with a failing summary` · `R6-m1 KEEP_GOING failure exits non-zero`. 방법: 스크립트가 자신을 `ISO14_KEEP_GOING=1 ISO14_SELFTEST_FAIL=1`(고의 실패 check 1개만 실행하는 자식 진입)로 서브프로세스 실행하고 마지막 줄·종료코드를 확인.
- Red: 마지막 줄 `ALL 1 CHECKS PASSED`, exit 0. Green: `FAILED 1 of 1 CHECKS: synthetic failing check`, exit 1.

## 작업 중 사실
- 첫 Red 시도에서 내 스크립트 편집 실수(`finish()` 본문이 자기 자신을 호출)로 RecursionError 가 났고 즉시 바로잡았다. Red 결과는 수정 후 다시 얻은 것이다.
- 작업 시작 시 `catalog.json` 이 수정 상태로 보였으나 내 변경이 아니었고 건드리지 않았다(종료 시점 git status 에서는 사라짐).
- DA 가 남긴 한계(manifest 의 `completed_at` 은 plaintext 메타데이터라 manifest 까지 재작성하는 변조는 범위 밖)는 이번에도 해결 대상이 아니다.

## 변경 파일
- `.fable-team/bin/tour/memory_confirmation.py` · `.fable-team/bin/tour/verify_14_isolated.py` (git 추적, diff 에 보임)
