<!-- fable-team:orchestration-gate BEGIN (자동 삽입 — install-gate.sh) -->
## 오케스트레이션 (fable-team 강제 게이트)

메인 오케스트레이터(**sonnet-5 또는 fable-5** — ultracode, 세션 시작 시 사용자 선택)는 판단 중심으로 움직인다. 계획·분배·결정·종합만 맡고, 실제 구현은 서브에이전트에 위임한다.

- 기획/문제해결: fable-5 또는 codex-5.6-sol(세션 직접 — ft-architect-x 폐지) — 세션 인터뷰 선택
- 진단: opus-4-6 (high) — 3자대조 전담
- 무거운 추론·구현: opus-4-8 (high)
- 구현·테스트: sonnet-5 (high)
- 대량 서치·로그·문서: sonnet-4-6 (medium)
- DA(적대검증): codex-5.6-sol(세션 직접) 또는 grok-4.6(드라이버) (high) — 세션 인터뷰 선택
- ft-pm-memory (v3 상시): sonnet-4-6 (medium) — 흐름 기억·원장·cairn 대행·BRIEF (알림까지 — 결정은 오케)

**한 턴에 코드 파일 2개까지만 직접 수정한다. 3개째부터는 `hooks/orchestration-gate.sh`가 물리적으로 차단한다.** 코드 수정이 필요하면 ft-implementer/ft-tester에 위임한다. Bash(`sed -i`·`echo >`·`tee`)로 코드파일을 우회 수정하지 않는다. **v3 — 래퍼 외 생명주기 명령 직접 발행 금지: `tmuxc open|kill|clean|distill`은 Bash 직접 호출 금지, `.fable-team/bin/ft-tmux-*.sh` 래퍼 경유만**(게이트가 면제보다 먼저 deny). 상세 기준은 `.claude/rules/orchestration.md` 참조.

컨텍스트 300k에서 증류 경고(`ft-ctx-triage.sh` 진단→결정, 승인 2-모드), 450k에서 신규 스폰 물리 차단(`context-distill-gate.sh`). v3 워커는 tmux 세션이라 오케 증류에도 생존(워커 증류=`ft-tmux-distill.sh` #N+1 승계).
<!-- fable-team:orchestration-gate END -->
