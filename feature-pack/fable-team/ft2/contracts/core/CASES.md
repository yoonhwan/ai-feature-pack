# ft2 공통 코어 상태 계약 사례표 (r1546)

ft 2.0 PR② 구현이 통과해야 닫히는 **입력 사건 → 기대 결과** 표다. 사례는 r1496·r1497 원자료
(`design/harness/research/ft-2.0/sim-atomic-json/`)에서 옮겼고, 실험 코드는 실행하지 않는다.

## 원자료 재계수 (2026-11-10 · BYZ origin/main `db18c453c77868355ffeb813d3b4c49f2047806a`)

| 항목 | 값 | 근거 |
|---|---|---|
| 사례 함수 | **12** | `cases_a` 3 · `cases_b` 4 · `cases_c` 3 · `cases_conc` 1 · `cases_corrupt` 1 — `grep '^def case_'` |
| 사례표 파일 | **12** | `cases/*.json`(`_judge-run.json` 은 사례 아님) |
| 실험 검증 줄 | 68 | `c.check(` 16·24·15·6·7 |
| 그중 출처(`source=`) 지정 | 47 | `source="…"` |
| 재생 대조 키 | **13** | `checker-r1497/judge-output-r3.json` — 사례별 10 · 회차 3 |
| 비채택 표시 | 9 | 아래 §비채택 |

## 결과 낱말 — 정본 «처리 결과» 7군 (새 낱말 0)

정본 `PLAN-ft20-single-module-and-slack-20260909.md` §파일 배치·최소 상태 의미 후보 표
«처리 결과: 접수 성공/거부·복구 필요·낡은 실행권·BUSY·용량 부족·완료 유보·회수 결과» 를 그대로 쓴다.
`접수 성공/거부` 가 한 군이라 **군은 7, 낱말은 8** 이다. 사례표 `expect.처리 결과` 는 이 8낱말 밖으로 나가지 않는다.

| 군 | 계약 낱말 | 실험 관측 낱말(계약 아님 · 인용) |
|---|---|---|
| 1 | 접수 성공 · 접수 거부 | ACCEPTED · REJECTED · REFUSED |
| 2 | 복구 필요 | CORRUPT_STATE · crash 뒤 재요청 회수 |
| 3 | 낡은 실행권 | STALE_OWNER · EXPIRED |
| 4 | BUSY | BUSY |
| 5 | 용량 부족 | FULL · PENDING_CAP |
| 6 | 완료 유보 | UNCERTAIN · BLOCKED_UNCERTAIN · IN_PROGRESS · RETRY |
| 7 | 회수 결과 | PRUNED |

## 사례표 12행

| id | 사례 (실험 폴더) | 처리 결과 | 상태 revision 변화 | 관측 대조 | 근거 검증(실험 check label) |
|---|---|---|---|---|---|
| case_01_happy_life | 정상 생애 (01) | 접수 성공 | 참 | — | 두 카드 접수 ACK |
| case_02_concurrent_4x300 | 다른 카드 동시 갱신 (02) | BUSY | 참 | k1_02 k2_02 k3_02 k4_02 | BUSY 는 다음 tick 사건 |
| case_03_same_key | 동일 카드·동일 키 (03) | 접수 성공 | 참 | k1_03 k2_03 k4_03 | GRANTED 정확히 1 |
| case_04_stale_owner | 옛 owner (04) | 낡은 실행권 | 거짓 | — | 정본 불변(revision·cards digest) |
| case_05_inflight | 구효과 진행 (05) | 완료 유보 | 참 | — | A 카드 = UNCERTAIN 보존 |
| case_06_accept_crash | 접수 crash (06) | 복구 필요 | 참 | — | 교체 후 crash: 영속 접수(카드 1) |
| case_07_effect_crash | 효과 crash (07) | 완료 유보 | 참 | — | 효과 후 crash: 결과 미확정 + 재실행 0 |
| case_08_expiry_full | 만료/포화 (08) | 용량 부족 | 거짓 | — | pending 8 유지 · 새 입력 FULL · 성공 ACK 0 |
| case_09_slow_team | 느린 팀 (09) | BUSY | 참 | k1_09 | A 잠금 점유 중 claim = BUSY |
| case_10_progress | 진행 구분 (10) | 완료 유보 | 참 | — | C 외부 대기 = 시한 보존 · 멈춤 아님 |
| case_11_close_race | 마감 경합 (11) | 접수 성공 | 참 | — | 신규 골 소실 0 |
| case_12_corrupt | 상태 손상 (12) | 복구 필요 | 거짓 | k6 k7 | 읽기 후 원본 바이트 불변 |

각 사례 파일 칸 = `id` · `출처`(정본 경로·sha·함수·줄 + 실험 literal 필드명) · `given`(사건 열) ·
`expect`(처리 결과 · 상태 revision 변화 · 근거 검증 · 관측 대조) · `비채택`.
`expect.관측 대조` 는 `judge-output-r3.json` 값을 **한 글자도 바꾸지 않고** 옮긴 것이고,
회차 전체 키(k5_baseline · k5_carried42 · k8)는 `cases/_judge-run.json` 에 둔다.

## 비채택 — 정본이 계약으로 채택하지 않은 실험 관측

| 사례 | 실험 관측 | 표시(정본 문장) |
|---|---|---|
| 02 | BUSY 상한 tick×(자식−1) · ticks ≥ 300 · 적용 300/카드 | 비채택: «숫자 확정·실측 PASS 아님» |
| 02 | 회차 실측 wall_s 0.431 | 비채택: «숫자 확정·실측 PASS 아님» |
| 03 | same-key 재요청 = IN_PROGRESS | 비채택: 7군에 IN_PROGRESS 낱말 없음 |
| 06 | 교체 전 잔여 임시 파일 ≥ 1 | 비채택: «구체 fsync/rename 순서와 checkpoint 규칙은 구현·장애 실험으로 검증» |
| 08 | 대기 한도 8건(PENDING_MAX) | 비채택: «숫자 확정·실측 PASS 아님» |
| 09 | BUSY 즉시 반환 < 1초 | 비채택: «숫자 확정·실측 PASS 아님» |
| 10 | 멈춤 문턱 stall_after = 3 | 비채택: «숫자 확정·실측 PASS 아님» |
| 12 | 원자 쓰기 fsync 계수 3/3 | 비채택: «구체 fsync/rename 순서와 checkpoint 규칙은 구현·장애 실험으로 검증» |
| 12 | 전원 손실 미실시(dir fsync 는 계수로만 확인) | 비채택: «전원 손실·장시간 내구성을 대신 증명하지 않음» |

## 실행

```
# 재생 검사 (rc 0 통과 · 1 불일치 · 3 표 없음/빈 표 · 4 원자료 못 읽음)
python3 -I ft2/contracts/core/replay_check.py \
  --judge "git:<BYZ 리포 절대경로>@db18c453c77868355ffeb813d3b4c49f2047806a@design/harness/research/ft-2.0/sim-atomic-json/checker-r1497/judge-output-r3.json"

# 시험 (같은 경로를 \`FT20_BYZ_REPO\` 또는 \`FT20_JUDGE_JSON\` 으로 지정)
python3 -m pytest ft2/tests/test_contract_core_replay.py
```

원자료가 없으면 검사기는 **rc≠0** 으로 끝난다(빈 표 통과 0 · no silent fallback).

## 알려진 한계

- 표는 실험이 본 사례까지만 담는다. 전원 손실·실환경·장시간 내구성은 정본대로 미시험이다.
- 수치(300 · 8건 · 문턱 · 소요 초)는 관측값이며 계약값이 아니다. PR② 는 수치를 계약으로 쓰지 않는다.
- 실험 코드는 1회도 실행하지 않았다. 이 표는 원자료 재계수·대조만 한다(재실행 증거 아님).
