# ft 2.0 독립 기획 3안과 반증 인덱스

사용자 지시: 현재 Astra 세션이 메인으로 오케스트레이션한다. Fable·DA·현재 Astra가 같은 조사 근거로 각각 완결된 안을 작성하고, 3안 비교 공개·동일 시뮬레이션·교차 반증을 거쳐 사용자와 선택한 뒤 확정본을 공개한다. aifp-ft master는 일반화·현재 구현·설치 상태를 확인 지원한다.

현재: 세 독립 초안과 교차 반증 수신·고정·공개. 공식 Pi가 첫 격리 실험용 구현에 착수했다. 시험 결과·선택·제품 구현·2.0 랜딩·실환경 이관 완료가 아니다.

최신 사용자 조건과 인터뷰는 `GATE-ft20-full-spec-before-implementation-20261109.md`, `INTERVIEW-ft20-decision-20261109.md`에 있다. 완료근거/결정은 Git 보존·상세로그만 회전으로 확정했고, planner 유지 여부는 두 후보의 실험으로 결정한다. 전체 풀스펙 HTML을 이해하고 명시 컨펌한 뒤 제품 구현을 시작한다.
별도 세션 수명 비교 설계는 `SIM-ft20-session-lifetime-comparison-20261109.md`. 파일 상태 실험 r1496/r1497과 실제 모델 재개·토큰·캐시 비용 실험을 구분하며, 현재는 설계만 있고 실행은 미착수다.

| 작성자 | 고정 commit | 문서 |
|---|---|---|
| Fable arch | e32e745d4b | PLAN-ft20-fable-independent-20261109.md |
| DA | 27cec5495d | PLAN-ft20-da-independent-20261109.md |
| 현재 Astra | 57a4a56f6b | PLAN-ft20-astra-independent-20261109.md |

문서는 모두 `design/harness/research/ft-2.0/` 아래에 있다. 현재 checkout에 없으면 표의 commit에서 읽는다. 원안 수정은 별도 보완판으로 식별한다.

| 검토·지원 | 근거 | 상태 |
|---|---|---|
| 현재 Astra 교차 검토 | REVIEW-ft20-three-proposals-astra-20261109.md | 설계 반례·명세 미완·미측정 구분. DA JSON안을 첫 최소 실험 후보로 추천, 최종 채택 아님 |
| DA 교차 검토 | REVIEW-ft20-three-proposals-da-20261109.md @28f855c8ed | 수신. Fable 반례 3개, Astra 명세 미완 2개, 자기안의 만료·권한·비용 조건 |
| Fable 교차 검토 | REVIEW-ft20-three-proposals-fable-20261109.md @52d1d3f12a, 쪽지275410 | 수신. DA를 첫 실험 기준선으로 추천. 비용·잠금·FULL, Astra 압축·타이머·미확정 책임 검토 |
| aifp-ft 현황 | /tmp/ft-2.0/STATUS-aifp-ft-20261109.md 및 STATUS-aifp-ft-20261109-addendum.md, 쪽지275393·275403 | 담당 aifp-ft-master-pi#2. 소스/설치 차이, 일부 일반화 도구, binding 호출범위, 구형 writer 차단 미확인 기록 |
| 첫 격리 실험 | /tmp/ft-2.0/SIM-ft20-minimal-contract-v1.md 및 SIM-ft20-minimal-contract-v1-confirmation.md | DA275412 확인·착수 신호275416. master275522와 pane으로 Pi r1496 착수 확인, Issue #8095. 좌석 `byz-harness-nano-r1496-ft20-sim-atomic-json-isolated-pi-i#0`. r1497 checker는 구현 commit 고정 뒤 개설. 시험 결과 미수신 |

공통 입력: OMO c80279585d, gajae-code db554d3112, ft 비교 ce0b3f6379, 기존 파일 실험 a043add0ef, DA 정정275365, 기존 파일 구조 PLAN 97f84ede64. 기존 실험은 새 3안의 통과 증거가 아니다.

파일 위치:
- 전체 목표: `/tmp/ft-2.0/GOAL-ft-2.0.md`.
- 공통 발주: `/tmp/ft-2.0/three-proposals-brief.md`.
- 비교 매거진: `/tmp/ft-2.0/2026-11-09-three-proposals.html`. 원안 전문 3개를 내장한 오프라인 파일. 설명용 시퀀스이며 실험 실행 화면이 아니다.
- 누적 근거: `/tmp/ft-2.0/root-ideas-comparison.md`.

공개 단계: 원안 3개 → 교차 반증 → 미완 계약 보완 → 동일 격리 실험 → 추천·사용자 선택 → 확정본. 안전 조건을 통과하지 못한 안을 비용 점수로 채택하지 않는다. 기존 런타임 HTML의 합의 내용을 선택 전 새 안으로 덮어쓰지 않는다.

메인의 교차검토 해석: Fable의 JSON 병목 지적은 현재 비용 미측정이다. 비용을 재기 전에 진행 필드를 다른 정본으로 분리하지 않는다. Astra의 압축 중 N+1 사건 유실 순서는 원안의 같은 팀 잠금 아래에서는 허용되지 않으므로 확정 실패 대신 crash·복구·잠금 비용 시험으로 남긴다. 운영 중인 timer 금지와 미선택 설계의 타이머 배치는 구분하며 이번 시뮬레이션은 가상 시계만 사용한다.

첫 실험은 DA 원안을 공개 보완한 후보에 한정한다. 세 작성자의 추천은 같은 팀의 접수·owner·결과를 한 교체 경계로 다뤄 복구 경계가 적다는 이유다. 제품 비용 우위나 다른 두 안의 실행 실패를 입증한 것은 아니다. 실제 외부 효과 강제와 구형 writer 차단은 설치 검증 전 미확정이다.

검증: Astra 원안의 Mermaid 시퀀스 2개 termaid 렌더 rc0, 문서 UTF-8·diff check 통과. 매거진 JavaScript 문법·기획 선택·상황 선택·단계 이동·원안3개 내장·브라우저 오류 없음 확인. 이 검증은 하네스 설계의 실행 검증이 아니다.
