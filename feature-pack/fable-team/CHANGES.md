# Changes

## 2026-07-11 — v3 업그레이드 (tmux 기반 전면 개편)

fable-team이 각 에이전트를 tmux 세션으로 직접 띄우고, 서로 메시지를 주고받고, 작업이 끝나면 스스로
정리하도록 구조를 전면 교체했습니다. 여기에 더해 세션 압축(증류) 시 모델의 확장 컨텍스트(1M)/추론
강도 설정이 유실되던 문제 수정, 전문가(fable-5) 브레인의 전체 구현 재검토, 대규모 동작 검증(23개
시나리오) 중 실측으로 발견한 버그 다수를 함께 처리했습니다.

- 요약 문서: [docs/artifact/2026-07-11-v3-upgrade-summary.html](docs/artifact/2026-07-11-v3-upgrade-summary.html)
- 설계 원문: [.fable-team/designs/roster-v3-design.md](.fable-team/designs/roster-v3-design.md)
- 구현 전체 검토 보고서: [.fable-team/state/v3-upgrade-design/implementation-review-fable5.md](.fable-team/state/v3-upgrade-design/implementation-review-fable5.md)
- 진행 원장(전 과정 기록): [.fable-team/state/state.md](.fable-team/state/state.md)
