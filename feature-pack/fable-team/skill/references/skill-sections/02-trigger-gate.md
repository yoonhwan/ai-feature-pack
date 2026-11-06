## 트리거 시 체크 게이트 (허들)

스킬 발동 즉시 확인하고, 미충족이면 진행 전 사용자에게 보고한다:

0. **솔로/오케 판별 (retro §7 — FT 발동 자체의 게이트)**: **"다음 액션이 관찰 결과에 따라 달라지는가?" YES(라이브 디버깅·관찰의존 반복) → FT 반려, 솔로 세션+긴밀 BTS 권고**(1세션 + 필요 시 tester 러너 1개). NO(작업 목록 이미 확정 — 병렬 구현·대량 마이그레이션·광역 서치/감사) → FT 진행. 근거: BYZ v6 2주 실측 — 관찰의존 작업에 오케 투입 시 릴레이 5홉·증상 재등록·DA 탁상심사로 비용/편익 마이너스(retro §7.1).

1. **프로파일 체크(D3)**: 현재 세션이 ⓐ Agent/Workflow **양면 지원**(도구 존재 — Workflow는 스킬 지시 호출로 opt-in 충족) ⓑ 로스터 **첫 가용 모델** ⓒ 그 모델의 **최대 유효 effort**(D1 상한 = high)인가? ⓒ만 미달이고 세션 내 조정 가능하면(`/effort high`) 조정 안내 후 진행. ⓑ 미충족(하위 모델 세션)이면 특정 모드 고정 안내(`/effort ultracode` 등) 금지 — **로스터 요건을 충족하는 세션에서 재트리거**하도록 안내 후 중단. ⓐ 중 Workflow만 부재 시 architect/tester 스폰을 미들웨어 드라이버 서브에이전트 경유 `claude -p`(스폰 경로 표 3행)로 전환 선언 후 진행.
2. **세션 effort 상속 함정**: 세션이 xhigh(ultracode)면 claude-5 계열(sonnet-5, fable-5) 워커는 Agent 팀 하네스에서 effort 상속으로 400 에러 즉사 — **스폰 경로 분리 규칙**(아래) 준수. claude-5 유효 effort는 low/medium/high/max(**xhigh 없음**) — 즉사 발생 시 교정: 해당 워커 pane에 `/effort high` 주입 또는 Workflow 경로로 `effort: high` 명시 재스폰. **claude-5 워커 표준 effort = high — architect 포함(기본 high)**. **architect effort = high(D1 표준 — max 퇴출: fable5/max hang 2세션 실측)**. 기존 설계의 보강·조임 회전은 high(수 분 내), 문구 수준 수정은 오케스트레이터 직접(기획 불요 기계적 — 게이트 처방이 명시된 경우). **비차단 규범**: architect/DA 회전은 백그라운드가 원칙 — 회전 대기로 사용자 개발을 정지시키지 않는다(파일이 증거, 릴레이 도착 시 처리·중간엔 다른 요청 계속).
3. 에이전트 정의 존재: 대상 위치에 `<prefix>-architect/checker/implementer/tester/da`가 설치돼 있는가? 없으면 설치 인터뷰(`references/install-interview.md`)부터.
4. **연동 프로브**: install.json `integrations`가 on/required면 가용성 프로브 — required 실패 시 보고 후 대기(headless는 override 정책 — `references/integrations.md` §0), on 실패 시 degrade 기록 후 속행. **프로브 출력(baton status stdout)은 보관해 부팅 시퀀스 1의 discovery가 재사용** — 같은 명령을 다시 실행하지 않는다.
