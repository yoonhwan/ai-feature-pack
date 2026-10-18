# 첫 단위 (planner P9 · 오빠 GO 13:0x) — 골 축 A·B·C 전부 한 번씩

골 원문: 「내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.」
골의 축: 첫 단위 = B(접수 3건 등록) → C(가장 작은 1건 수정·커밋·PR·RELEASE-0.1) → A(모니터 10분 루프 켜기).

1. 이관 Issue 3 인수(team:shared-harness 라벨 확인): #733 V14 세트 버저닝 · #737 V19 트랙별 FT 분담 · #761 C13c FT pack wip 리뷰 — 각 Issue 에 「인수 · 담당 ft-harness-ops#0」 코멘트 1줄(gh 는 unset GH_TOKEN 먼저).
2. REQUEST-LEDGER R1~R3 → Issue 3건 생성(라벨 team:shared-harness scope:direct phase:pre-completion type:agent-ops status:needs-triage · 마일스톤 goal-outside) · 번호를 원장에 적음.
3. R1(백틱 훅) 수정 1건 = 축 C 첫 발행: 훅이 mbox 인자만 검사하도록(heredoc 본문 제외) · 셔뱅 -n · 실측 1회 → 커밋 → PR(main) → design/teams/harness/RELEASE-0.1.md(변경·설치 명령 · 머신 행: 로컬 1) → planner mbox 3줄(경로·sha·남은 일).
4. 축 A: 모니터 체크 1벌 정의(훅 로그 · 좌석 부팅 실패 · mbox DROPPED · 자동로드 예산 hygiene-check.sh rules) → 10분 루프는 좌석 자체(틱 데몬 0).
금지: 제품 코드 · 라이브 인프라 · 다른 머신 세션 send-keys · 글로벌 CLAUDE.md 하드 룰 변경(= [HIL] → planner).

## 닫는 증거 (10-04 마감 · planner #56528 인정)
| 항목 | 증거 |
|---|---|
| 1 Issue 인수 | #733·#737·#761 코멘트 「인수 · 담당 ft-harness-ops#0」 |
| 2 R1~R3 등록 | Issue #799·#800·#801 · REQUEST-LEDGER 행 |
| 3 R1 수정·발행 | PR #802 main dedceb2ba6 · RELEASE-0.1.md · R3 PR #804 f38294ffac |
| 4 모니터 체크 | PR #806 03368493dd · scripts/fable-team-bin/harness-monitor.sh |
| 별건 | #805 test_vllm_cached_tokens 2건 → issue-manager 하위 나노 |
