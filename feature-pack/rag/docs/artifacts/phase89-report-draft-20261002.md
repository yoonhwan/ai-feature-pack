골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
골의 어느 축인가: A03 · A02 6순위 C13 — acceptance-gates phase 8·9(사용자 리뷰·KakaoBot 최종 통합 보고서). 닫는 증거(예정): 사용자 수용 + P08-02·03·P08A-08·P09-01~03 체크박스 갱신.
상태: **초안(DRAFT) — 판정 아님.** 재료 = `.fable-team/state/airag/checker-phase89-facts.json`(HEAD 18d72ec 기준 checker 사실). 이 문서는 «요구 ↔ 있는 증거 ↔ 비어 있음» 대조표만 담고, 완료 판정은 사용자·DA 가 한다.

# AIRAG phase 8·9 최종 통합 보고서 — 초안 (2026-10-02)

## 1. 요구 원문 (acceptance-gates.json)
- phase 8 `tour`: mixed_source_demo · inspect_originals · expand_connections · live_update · delete_restore · user_review
- phase 9 `completion`: approved_requirements_traceability · no_unreported_incomplete_capabilities · user_tour_done · final_kakaobot_integration_report

## 2. 대조표
| 요구 | 있는 증거 | 비어 있음 |
|---|---|---|
| 투어(P08-02·03, P08A-08) | 투어 catalog 12건 사용자 수용(`.fable-team/bin/tour/catalog.json`) · 투어 14 수용(2026-10-01, 승인 10·검증 10 반영) | 11-load-repro·12-load·13-multi-load 미수용 · 잔여 확인대기 51·검증대기 25 사용자 보류 · PLAN.md 체크박스 [ ] 그대로 |
| 승인 요구 추적(P09-01) | DA r1~r17(r17 PASS 0/0/0) · 회귀 로그 r1~r7 EXIT=0 · final-integration-result.json(09-28) | 항목 ↔ 투어 매핑표·승인요구 추적표 없음 |
| 미완 기능 무은폐(P09-01·03) | 알려진 한계 목록(final-integration-result.json limits · R15-m1 · fork 손자 락 · 다른 볼륨 복제 prefix 수용) | **published succeeded 0 (10→14→14 시도, 성공 0)** — 원인 확정 전(architect 가설 H1/H2, DB 열람 승인 대기). 확정·처리 전에는 «미완 기능 무은폐» 항목에 «보고된 미완»으로 올려야 함 |
| 운영 근거(P08A-08·P09-02) | com.airag.consumer launchd 등록 · 첫 틱·2틱 exit 0 ok(2026-10-02) · 03:00 슬롯 백업 관찰 예정(C12) | 03:00 슬롯 backup_created 관찰 전 |
| 최종 KakaoBot 통합 보고서 | PLAN.md P09-02·03 이 가장 인접한 문구(소비 프로젝트용 통합 자료·최종 통합 결과) | **형식·수신처·필수 내용을 정의한 문서 0건**(DECISIONS.md·PLAN.md·.fable-team 전체) |

## 3. 사용자 결정이 필요한 것 (이 초안이 스스로 정하지 않음)
1. 「최종 KakaoBot 통합 보고서」의 형식·수신처·필수 내용 — 정의 문서가 없다.
2. published 0 을 «해결 후 보고»로 할지 «보고된 미완»으로 두고 phase 9 를 진행할지.
3. 투어 미수용 3건(11-load-repro·12·13)과 보류 76건(51+25)을 phase 8 완료 전에 닫을지 범위 결정으로 기록할지(P08-03 허용 방식).

## 4. 다음
위 3건 결정이 오면 대조표의 «비어 있음» 칸을 채워 보고서 본문으로 확장하고 DA 최종 대조를 받는다.
