# 인덱스: C16 매니저 가져오기 — 작성 경로 분류기 + 발견 지연 열 + 좌석 등록 쌍 래퍼
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: 표 A(요청 → Issue → 검토) · 원문 7(많은 Issue 를 가져와 분류). 핵심 한 줄: 들어온 Issue 가 어느 문으로 왔는지와 얼마나 늦게 발견됐는지를 기계가 알아야 매니저가 0 으로 줄일 수 있다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
GitHub 작성자는 전부 한 계정이라 login 으로는 오빠·좌석·사내 멤버를 가를 수 없다(사실). 그래서 폼 마커·라벨로 작성 경로 4종(기획 세션·세션 에이전트·오빠 GitHub 직접·사내 멤버)을 분류한다. 사람 등록(③④)은 라벨을 «보완» 대상으로, 좌석 등록(②)은 «반려» 대상으로 나눈다. 또 Issue 생성 시각에서 매니저 첫 코멘트까지의 지연(발견 지연)을 표로 낸다. 좌석 등록 쌍 = Issue 생성 명령과 매니저에게 가는 알림 1통을 한 묶음으로 만드는 래퍼(기본 dry-run). 정본: `design/teams/harness/issue-improvement/SPEC-github-issue-driven-20261006.md` §2 · §8 C16 · `design/teams/harness/issue-improvement/SPEC-issue-manager-slack-tmm-20261005.md` §4 ⓪.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-issue-classify.sh [--from-json <파일>]` — 읽기 전용: `gh issue list --json` 결과(또는 시험용 JSON)를 받아 Issue 마다 작성 경로(① 기획 세션 · ② 세션 에이전트 · ③ 오빠 GitHub · ④ 사내 멤버 · 미분류)와 처리 분기(보완/반려/그대로)를 표로 출력 · 판단 근거(폼 마커·라벨 이름)를 한 열로 · login 은 쓰지 않는다 · 발견 지연 열(created → 매니저 첫 코멘트, 없으면 «미발견» + 나이).
2. `scripts/fable-team-bin/ft-issue-create-pair.sh <제목> <본문파일> [--apply]` — 기본 dry-run: 실행할 `gh issue create` 명령과 매니저 알림 1통 본문(Issue 번호 자리표시)만 출력 · `--apply` 때만 실제 실행 · 매니저 수신자는 `seats-issues.json` 에서 읽고 없으면 raise(폴백 0).
3. 회귀: `bash -n` · `tests/harness/test_issue_classify.sh` — `tests/fixtures/issue_classify/` JSON 4종(경로 ①~④ 각 1)로 분류·분기·지연 열 검증 · 실제 `gh issue list` 읽기 1회 출력 첨부(열린 Issue 현황). 기존 도구 예: `scripts/fable-team-bin/ft-nano-close.sh`. 커밋은 자기 브랜치, **push 금지**. 금지: `--apply` 실행 · gh 쓰기 · mbox 실제 발신.

## 완료 조건 (닫힘 판정 기준 — master+DA 테스트 소관)
- test_issue_classify.sh 가 4 경로 fixture 의 분류와 처리 분기를 바르게 낸다(출력 첨부).
- 실제 열린 Issue 목록에 분류기를 돌린 결과(경로별 건수 · 미분류 건수)가 보고서에 있고 gh 쓰기는 0 이다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — ops 가 수락 판정문을 남긴다.

## 상태
- base_sha: 7968255bc7a26f2e78379fa0dced8fad5dab7390 (spawn 2026-10-06)
- 2026-10-06 — 대기/ 생성 (ft-harness-ops#4).
- 2026-10-06 00:18 — 대기→진행 · 좌석 ft-harness-temp-c16-issue-classify#0
- 정본 영향 없음: 하네스 스크립트·시험만 추가 — docs/architect 제품 정본 변경 없음
- 세트: 880879cfa297d826d8d8b4457a68c4c6c7897f17 · 시험: bash tests/harness/test_issue_classify.sh rc=0 · 이슈: 0
- 2026-10-06 00:27 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§16
