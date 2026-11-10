## 강제 게이트 (orchestration-gate) — 선언 아닌 물리 차단

CLAUDE.md·SKILL.md에 "오케는 위임한다"고 적는 건 **권고**라 모델이 우회 가능. **PreToolUse 훅으로 물리 차단**해야 실제로 막힌다(출처: joel__w__w 스레드). fable-team은 4-레이어를 **한 세트로** 유지·배포한다:

| 레이어 | 파일 | 역할 |
|--------|------|------|
| 선언 | `templates/CLAUDE.orchestration.snippet.md` → 프로젝트 CLAUDE.md | declaration |
| 역할 | `references/agent-templates/` (로스터) | role assignment |
| 기준 | `templates/rules/orchestration.md` → `.claude/rules/` | operating criteria |
| 강제 | `templates/hooks/orchestration-gate.sh`·`orchestration-turn-reset.sh`·`context-distill-gate.sh` → `.claude/hooks/` + settings.json | enforcement |

- **오케 편집 게이트**: 최상위 모델 오케(fable-5/sonnet-5)가 한 턴에 **코드 파일 2개까지**, 3개째 Edit/Write/Bash(sed·echo>·tee) **하드 deny**+위임 메시지. 워커(opus-4-6/sonnet)는 무제한(모델 판별=transcript 마지막 assistant model). **fail-open**(오류 시 허용 — 세션 brick 금지).
- **컨텍스트 증류 게이트**: 300k warn 주입 / 450k 신규 스폰 하드 deny.
- **설치**: `templates/install-gate.sh --check|--install [proj]` — 상태 진단 + 멱등 설치(settings 병합·백업). **패치마다 4-레이어 세트로 함께 갱신**(update.md).
