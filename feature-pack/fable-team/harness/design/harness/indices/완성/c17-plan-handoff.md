# 인덱스: C17 임시 기획 세션 인계 — ft-plan-handoff.sh (정리본 → issue-manager mbox 1통)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A(요청 → Issue). 핵심 한 줄: 오빠가 임의로 연 기획 세션의 정리본이 Issue 로 들어가는 길이 지금 없다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
오빠가 임시로 연 기획 세션(`byz-planner-master-claude#N` · P6 문법)이 실험·정리한 정리본을 issue-manager 에 넘기는 현행 경로는 없다(사실). 정리본(tracked 파일 · 머리줄 `주제:` `골좌표:` `쪼갠 단위 N`)을 받아 mbox 1통으로 매니저에 보내 «단위 1 = Issue 1건» 생성 요청 + planner 분류 요청 1통을 만드는 한 명령을 만든다. Issue 생성 자체는 하지 않는다(매니저 몫). 정본: `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §2 ① · §8 C17 · `design/teams/harness/issue-improvement/SPEC-session-naming-20261005.md`.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-plan-handoff.sh <정리본 경로> [--dry-run]` — 머리줄 3개 검증(없으면 exit 1 사유) → `FT_SEND_DRY=1` 이면 보낼 mbox 본문 2통(매니저 · planner)만 출력 · 아니면 mbox 로 발신(수신자 이름은 `seats-issues.json` 의 매니저 행에서 읽기 · 없으면 raise — 폴백 0).
2. `design/teams/harness/PLAN-HANDOFF-TEMPLATE.md` — 정리본 머리줄 3개 + 단위 표 예시.
3. 회귀: `bash -n` · `tests/harness/test_plan_handoff.sh` — dry-run 으로 정상 정리본/머리줄 누락 정리본 2케이스. 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: 실제 mbox 발신 · Issue 생성.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_plan_handoff.sh 가 정상/누락 2케이스를 바르게 판정(출력 첨부).
- dry-run 출력의 mbox 본문에 정리본 경로·골좌표·단위 수가 들어 있다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: eafbbaa4563e2fb6c59bbfd8e0ed28cea02f4625 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:11 — 대기→진행 · 좌석 ft-harness-temp-c17-plan-handoff#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: f3def419b20035f9f05db12c62b35c36ae650b78 · 시험: bash tests/harness/test_plan_handoff.sh rc=0 · 이슈: 0
- 2026-10-06 00:17 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§10
