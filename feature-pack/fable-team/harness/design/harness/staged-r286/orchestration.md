# 오케스트레이션 운영 기준 (rules/orchestration.md)

> fable-team 4-레이어 중 **운영 기준**. 강제는 `hooks/orchestration-gate.sh`(PreToolUse, fail-open, TOP 모델 세션에만 · 워커는 agent_id 면제).
> ★원문 전체 = `~/.claude/archives/orchestration.md-full-20261001.md` (아래 «원문 행» 열 줄). 이 파일은 로스터·하드 경계만 싣는 인덱스★

## 역할·모델 로스터

| 역할 | 모델 | effort |
|------|------|--------|
| 메인 오케스트레이터 | sonnet-5 또는 fable-5 (세션 시작 시 선택) — 계획·분배·결정·종합, 직접 구현 금지 | ultracode |
| 기획/문제해결 architect | sonnet-5 기본 · fable-5 는 에스컬레이션 전용(증거팩 필수) 또는 codex-5.6-sol. max 금지(hang) | high |
| 진단 analyst | opus-4-6 (Bash 읽기전용) | high |
| 구현·추론 워커(나노 기본) | claude-sonnet-5-5[1m] | high |
| 구현·테스트·checker·tester | claude-sonnet-5-5[1m] | high |
| 대량 서치·로그·코드 분석·정본화 서치 | opencode/deepseek-v4.1-flash-free (opencode 나노 · `ft-nano-spawn.sh … --tier search`) | (effort 없음 · 빠른 모드) |
| DA(적대검증) | codex-5.6-sol 또는 grok-4.6 — 게이트 | high |
| ft-pm-memory | sonnet-4-6 — 기억·원장·BRIEF. 결정은 오케 | medium |

갱신: 2026-10-16 · 근거: 오빠 하네스 뉴스(desk#7 #100242) · 다음 뉴스 = 하네스팀 발주로 이 표만 고친다 · architect·DA 행은 r286 에서 바꾸지 않음(arch = 오빠 09-30 «꼭 opus5.5» · DA = sol 6.1 low fast 유지 — 바꾸려면 planner 판정).
★opencode 나노는 읽고 모으기 전용(코드 수정·커밋 0) · 쓰면 매번 완전히 닫는다: 나노 = `ft-nano-close.sh`(opencode 프로세스 left=0 확인까지) · Bash 직접 사용 = 끝나면 `ft-opencode-reap.sh`(판정 2035 · BOOT 41)★

## 직접 / 위임 · 우회 차단 · 증류

- **직접**: 1~2개 코드 파일 작은 수정 · *.md·*.json/yaml·`.fable-team/**` · 오타·조회. **한 턴에 코드 파일 2개까지**(3개째 게이트 차단).
- **위임 필수**: 새 기능 · 3개+ 코드 파일 · 50줄+ · 테스트 작성 · 리팩토링 · 무거운 추론 · 대량 서치.
- Bash(`sed -i`·`echo >`·`tee`·`cat >`)로 코드파일 우회 수정 금지(deny). v3: `tmuxc open|kill|clean|distill` 직접 발행 금지 — `.fable-team/bin/ft-tmux-*.sh` 래퍼만.
- 증류: **550k** warn · **600k** 신규 스폰 차단(프로젝트 훅도 같음 · R445 2026-10-19).
- **마감**: 단위 끝 = 랜딩 → 배포 브랜치 push → CLOSEOUT 정본 1장 → 전부 닫기(승계로 버티기 금지). 정본 `~/.claude/rules/closeout-policy.md`.
- **Master 금지 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환. 하는 것: 실측·라우팅·커밋·push 집행. 체인 = checker(사실) → Master → architect(설계·DA 소환 결정) → Master → impl.

## 📎 인덱스 — 이 파일에서 뺀 절 (원문 `orchestration.md-full-20261001.md`)

| 절 | 원문 행 |
|---|---|
| 문제해결 방법론 7원칙(1이슈·계측·반박·체커부터·approve loop·DA 반박·완성=라이브) | 34–43 |
| 문제해결 표준 체인 상세 · DA 상시 대기 금지 | 45–49 |
| checker 4축(FE 콘솔·poller·worker 로그·Redis) · 다이렉트 확인 루프 · 안티패턴 | 51–58 |
| 역할 표 «하는 일» 열 · 직접/위임 세부 | 7–23 |
