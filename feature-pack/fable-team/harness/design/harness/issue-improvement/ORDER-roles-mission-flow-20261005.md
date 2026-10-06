# ORDER — planner·issue-manager 역할 + 병렬 발주·병렬 처리 + 미션 클리어 방식 기획 (ops#2 → arch · 2026-10-05)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
>
> 골의 축: 표 A(모니터) 둘째 단위 「각 오케가 일을 어떻게 받고 병렬로 처리·클리어하는지」를 읽히게 한다. 닫는 증거 = DA APPROVE + 오빠 「맞다」.

## 오빠 지시 (2026-10-05 원문)
> 「좋아 이 구조에 planner 와 issuemgr 세부수행역할 기획, 별도로 planner 출발 메인팀들의 병렬발주관리, 메인팀 하위 나노와 세션들의 병렬처리 관리, 메인팀이 여러 미션을 받고 클리어해나가는 방식 기획 정리」
> 앞 단위 원칙(유지): 「스택이 너무 크다 · 파일 하나 · 하나씩 · 모든 작업은 arch da 진행 기획」

## 기반 구조 (오빠 확정 · 다시 묻지 않는다)
`design/harness/issue-improvement/SPEC-main-orch-tree-20261005.md`(37e19724b5): 오빠 ↔ planner(컨트롤 베이스·거시) 아래 v65·cfo·harness-ops(메인)·ccu·kk(위성) 서로 동등 · issue-manager = planner 가 쓰는 Issue 실행 도구(정의된 GitHub Issue 단위 폴링·수정·테스트·랜딩·클린업). 이 트리·mbox 방식은 이미 정본 — 이 문서는 그 위에 «역할·흐름»만 얹는다.

## 산출 = 문서 1개 `design/harness/issue-improvement/SPEC-roles-mission-flow-20261005.md` (200줄 이내 · 읽는 사람 = 오빠)
네 절 · 각 절 «지금(실측 사실)» + «제안» 분리 · 오빠 값이 필요한 선택은 문서 끝 질문 목록(최대 5):
1. **planner · issue-manager 세부 수행 역할** — 표: 입력 · 하는 일 · 출력(정본 위치) · 하지 않는 일. 둘의 경계(거시 vs Issue 1건 단위) 명시.
2. **planner → 메인팀 병렬 발주 관리** — 발주 단위 · 팀당 동시 몇 건 · 상태 추적 · 자원 충돌(GPU·오디오 press 는 직렬) 순번 · 회수.
3. **메인팀 하위 나노·세션 병렬 처리 관리** — 나노 상한(`FT_NANO_SLOTS` 기본 6) · spawn·카드·워크트리·freshness·close · 한 팀 안 병렬/직렬 규칙.
4. **메인팀이 여러 미션을 받고 클리어하는 방식** — 미션 큐 · 우선순위 · 활성 단위 수 · «클리어»의 정의(닫는 증거) · 마감(closeout-policy).
- 예시 팀은 v65·cfo·ccu. 제외: Slack · 설치 키트 · 질문 원장 구현 · 멀티머신 · 구현 코드.

## 방식
- 사실 수집 = ft-harness-nano#1(읽기 전용): planner 발주의 실제 형식·건수(mbox 로그) · `design/planner/` 정본 · `design/issues/` README·LOOP-LEDGER · `ft-nano-slots/spawn/close` 흐름·한도 · 팀별 `indices/` 대기·진행·완료 구조와 현재 건수. [사실]/[추측] 표기 · 원자료 facts-raw.
- 작성 = arch · 검증 = ft-harness-da#1 **1회 · 10분 · 범위 = 위 4절만**. HOLD 2회면 직렬 DA 종료 → ops 통합 수락.
- 완료 = 경로 + sha + 남은 일 3줄을 mbox 로 ops 에. 이후 ops 가 /eli5 발행 · 오빠 공유.
