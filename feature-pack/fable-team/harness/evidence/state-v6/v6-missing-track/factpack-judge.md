# factpack-judge.md — 판정기(missing_phrases) 오탐/정탐 분석 (chk-lang, 2026-07-08)

## ① 판정기 코드 위치·기준

**위치**: `tests/e2e/rt_corpus/lib/judge.py` — `check_phrases_pass()` (line 33~53)

**매칭 기준 (2단계)**:
1. casefold + 연속공백→단일공백 정규화 후 substring 비교
2. 실패 시 공백 전부 제거(nospace) 후 substring 재비교 (KO 띄어쓰기 변이 흡수)

그룹 내 alt 1개라도 매칭 → PASS. 전부 실패 → `group[0]`을 `missing_phrases`에 추가.
`clause_loss`: `len(missing_phrases) > 0`이면 True.

## ② check_phrases 정의 (JSONL)

- v1_ko: `[["배포 이후로"], ["인프라팀","인프라 팀"], ["로드"], ["교차 확인"]]`
- v1_en: `[["morning debugging"], ["digging through the logs"], ["regression test"], ["smallest customer segment","Smallest customer segment"]]`

## ③ 분류표 (실유실 / 조사·어형 변형 오탐 / STT 오인식)

| 출처 | cell | missing phrase | 분류 | 근거 |
|------|------|----------------|------|------|
| HIL 웜탭 | v1_en | "digging through the logs" | 실유실 | 2번째 문장 전체 없음 |
| HIL 웜탭 | v1_en | "smallest customer segment" | 실유실 | text 끝 "starting with the." 잘림 |
| HIL 웜탭 | v1_ko | "배포 이후로" | **조사 변형 오탐** | text="배포 이후 특정..." — "이후로"→"이후" |
| HIL 웜탭 | v1_ko | "교차 확인" | 실유실 | text 끝 "알려주시면" 잘림 |
| HIL 콜드탭 | v1_en | "morning debugging" | STT 오인식 | "morning detailing. Debugging" |
| 5회전 R2 | v1_en | "digging…logs"+"smallest…" | 실유실 ×2 | 문장 소실+끝 잘림 |
| 5회전 R2 | v1_ko | "배포 이후로" | STT 오인식 | "대폭 할인 이후로" |
| 5회전 R3·R4 | v1_en | 동일 2건 | 실유실 ×4 | 동일 패턴 |
| 5회전 R5 | en/ko | 없음 | PASS | — |
| partdb-5r R1 | v1_en | "morning debugging" | STT 오인식 | 동일 패턴 |
| partdb-5r R1 | v1_en | "smallest customer segment" | 실유실 | 끝 잘림 |

**집계**: 실유실 11 / 조사 변형 오탐 1 / STT 오인식 3.

## ④ 판정기 개선 레버 후보 (제안만)

| 레버 | 대상 오류 | 방법 |
|------|----------|------|
| JSONL alt 확장 | 조사 변형 오탐 | `["배포 이후로","배포 이후"]` — 즉시 적용, 수정 최소 |
| KO 조사 suffix strip | 조사 변형 오탐 | 조사(로/으로/에서/은/는/이/가) strip 후 비교 |
| EN 핵심어 분리 AND 매칭 | STT 오인식 일부 | "morning" AND "debugging" 개별 포함 (연속성 완화) |
| edit-distance ≤ 1 | 조사 1자 차이 | KO 오탐 유효, EN 완전 오인식 비효과 |
| (참고) 실유실은 판정기 개선 불가 | — | 파이프라인 문제 |

**주의(orch)**: 5회전 라운드 라벨은 evidence 덮어쓰기 때문에 chk 세션별 스냅샷 기준 — 라벨 신뢰도는 메커니즘 분류(정탐/오탐)에 한정해 사용.
