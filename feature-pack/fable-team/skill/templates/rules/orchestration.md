# 오케스트레이션 운영 기준 (rules/orchestration.md)

> fable-team 4-레이어 중 **운영 기준(operating criteria)** 레이어. 선언(CLAUDE.md/SKILL.md)·역할(agents)·강제(hooks/orchestration-gate.sh)와 함께 간다.
> 핵심 원칙: **"오케스트레이터가 똑똑하게 일하게" 가 아니라 "비싼 일을 직접 못 하게 물리적으로 막는다."** 이 문서는 기준이고, `hooks/orchestration-gate.sh`가 강제한다.

## 역할·모델 로스터

| 역할 | 모델 (선택지) | effort | 하는 일 |
|------|--------------|--------|---------|
| **메인 오케스트레이터**(세션) | **sonnet-5 또는 fable-5** (ultracode — 세션 시작 시 사용자 선택) | ultracode | 계획·분배·결정·종합. **직접 구현 금지**(게이트로 강제) |
| **기획/문제해결 architect** | **fable-5** 또는 **codex-5.6-sol**(세션 직접 — ft-architect-x 드라이버 폐지) — 세션 인터뷰 선택 | high | 원인 분석·해결 설계 → 설계 파일. max 금지(hang) |
| **진단 analyst** | **opus-4-6** | high | 로그↔코드↔스펙 3자대조 진단. Bash 읽기전용 |
| 구현·추론 워커 | **opus-4-8** | high | 설계 기반 구현 |
| 구현·테스트 워커 | **sonnet-5** | high | 구현·테스트·repro |
| 대량 서치·로그·문서 | **sonnet-4-6** | medium | 로그·문서·아키텍처·코드 서치(단말성) |
| DA(적대검증) | **codex-5.6-sol**(세션 직접) 또는 **grok-4.6**(드라이버) — 세션 인터뷰 선택 | high | 게이트 |
| **ft-pm-memory** (v3 상시) | **sonnet-4-6** | medium | 흐름 기억·원장·cairn 대행·BRIEF. 알림까지 — 결정은 오케, 워커 직접 지시·파괴 금지 |

## 오케스트레이터 직접 처리 (위임 안 함)

- 1~2개 파일의 작은 코드 수정
- 문서 수정(*.md), 설정 변경(*.json/*.yaml), 상태 파일(.fable-team/**)
- 오타·포맷 수정, 단순 질문·조회, 서치
- **한 턴에 코드 파일 2개까지** — 작은 작업까지 위임하면 왕복 비용이 더 크다.

## 위임 대상 (반드시 서브에이전트)

- 새 기능 구현
- **3개 이상 코드 파일 변경** (게이트가 3개째를 물리 차단)
- 50줄 이상 변경 예상
- 테스트 코드 작성
- 리팩토링
- 무거운 추론(→ opus-4-6) / 대량 서치(→ sonnet-4-6)

## 우회 경로 차단 (게이트가 강제하지만 규칙으로도 명문화)

- **오케스트레이터는 Bash로 코드 파일을 수정하지 않는다.** `sed -i`, `echo >`/`>>`, `tee`, `cat >` 로 코드파일을 고치는 것도 게이트가 deny한다.
- 코드 수정이 필요하면 반드시 서브에이전트(ft-implementer/ft-tester)에 위임한다.
- **v3 — 래퍼 외 생명주기 명령 직접 발행 금지(§0-2 L3)**: 오케는 `tmuxc open|kill|clean|distill`을 Bash로 직접 발행하지 않는다. 세션 생성·증류·정리는 `.fable-team/bin/ft-tmux-*.sh` 검증 래퍼 경유만 — orchestration-gate가 **면제 판별보다 먼저** 생명주기 deny를 평가하므로 워커·ft-자칭 세션·`bash -c`·절대경로 우회도 차단된다. `tmuxc clean`(zombie 일괄)은 스크립트화하지 않고 사용자 확인 경로 유지.
- 오케스트레이션은 "좋은 말"이 아니라 우회 경로까지 줄이는 운영 규칙이다.

## 컨텍스트 증류 (하드 게이트 + v3 자율 증류)

- **300k 토큰** = `context-distill-gate.sh warn`이 매 턴 증류 경고 주입 → **`ft-ctx-triage.sh` 진단 → 문제 수정 → 증류 결정**(context-management.md §2.5·설계 §2-2). 결정 후 승인 2-모드(standing=자율 / 미승인=AskUserQuestion+op-token).
- **450k 토큰** = `context-distill-gate.sh block`이 신규 서브에이전트/워크플로/**Bash `ft-tmux-spawn.sh` 스폰**을 물리 차단 — 진행분만 마무리하고 즉시 증류.
- **워커·오케 증류는 독립 축**: 워커 증류는 `ft-tmux-distill.sh`(#N+1 승계, handover token), 오케 증류(A=자기 setsid distill / B=재시작)는 워커 tmux 세션을 건드리지 않는다(생존이 v3 계약).

## 강제 장치와의 관계

이 기준을 어기면 `hooks/orchestration-gate.sh`(PreToolUse)가 실제로 막는다. 규칙은 선언, 훅은 강제 — 둘 다 있어야 우회가 줄어든다. 훅은 **fail-open**(오류 시 허용)이라 세션을 brick하지 않는다. 게이트는 **오케스트레이터(TOP 모델: fable-5/sonnet-5) 세션에만** 발동 — 워커는 agent_id 면제(제1 판별 — sonnet-5 tester 포함)로 무제한.
