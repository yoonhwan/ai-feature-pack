<!-- fable-team:orchestration-gate BEGIN (자동 삽입 — install-gate.sh) -->
## 오케스트레이션 (fable-team 강제 게이트)

메인 오케스트레이터(**opus-4-8**)는 판단 중심으로 움직인다. 계획·분배·결정·종합만 맡고, 실제 구현은 서브에이전트에 위임한다.

- 기획/문제해결: opus-4-8 또는 fable-5 (FT 구성 시 선택·기록)
- 무거운 추론·구현: opus-4-6 (medium/high)
- 구현·테스트: sonnet-5 (high)
- 대량 서치·로그·문서: sonnet-4-6 (high)

**한 턴에 코드 파일 2개까지만 직접 수정한다. 3개째부터는 `hooks/orchestration-gate.sh`가 물리적으로 차단한다.** 코드 수정이 필요하면 ft-implementer/ft-tester에 위임한다. Bash(`sed -i`·`echo >`·`tee`)로 코드파일을 우회 수정하지 않는다. 상세 기준은 `.claude/rules/orchestration.md` 참조.

컨텍스트 300k에서 증류 경고, 450k에서 신규 스폰 물리 차단(`context-distill-gate.sh`).
<!-- fable-team:orchestration-gate END -->
