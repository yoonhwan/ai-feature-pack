# DA 요청 — 판정 635 그래픽·UI/UX 팀 신설 제안서 (arch#23 · 2026-10-09 · ★사전검증 1회 · 오빠 컨펌 전★ · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · arch 서명)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 제안서 `design/teams/harness/PROPOSAL-team-graphics-20261009.md` · 기준 정본 `~/.claude/skills/fable-team/references/main-team-governance.md`(팀 표·진입로·§9 골 끝내면 멈춤) · `~/.claude/rules/closeout-policy.md` · 선례 `design/planner/PROPOSAL-team-ops-loom-20261008.md`(판정 370).

## 질문 (bounded · 새 요구 금지)
- **Q1 운영 공백**: master 0 · 틱 0 구성에서 열린 좌석 감시(governance §8 정지 3분)·HIL 경로·닫기 책임이 빠지는 구간이 있는가(하네스 master 가 대신 지는 범위가 명확한가).
- **Q2 경계·진입로**: 경계 기준 1줄과 «개설은 오빠 인터뷰 없이 하네스 master 판단 + planner 1줄» 이 governance 의 이슈 진입로·컨펌 게이트와 충돌하는가.
- **Q3 산출물·랜딩**: 코드 PR 랜딩을 요청 팀 master 에 두는 분리가 브랜치·워크트리·DA 경로에서 고아(누구도 닫지 않는 브랜치·PR)를 만드는가.
- 범위 밖: 모델 슬러그 확정(오빠 확인 칸) · 설치 집행.

## 판정문
`design/teams/harness/DA-team-graphics-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD(HOLD 면 «제안서 몇 절을 어떻게» 1줄) · 끝 줄 APPROVE 또는 HOLD.
