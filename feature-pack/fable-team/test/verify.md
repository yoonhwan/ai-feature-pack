# fable-team 검증 절차

## V1. 설치 검증 (install.sh 직후)

```bash
test -f ~/.claude/skills/fable-team/SKILL.md && echo SKILL_OK
ls ~/.claude/skills/fable-team/references/agent-templates/*.tpl | wc -l   # 기대: 6
```

## V2. 워커 프로브 (인터뷰 완료 후, 새 세션)

각 워커에 표준 질의 (orchestration-playbook.md §프로브):

| 체크 | 기대값 | 실측 근거 |
|------|--------|-----------|
| tools에 Agent/Task 없음 | ✅ | 서브의 서브 차단 |
| spawn_test | `NO_SPAWN_TOOL` | 워커가 직접 스폰 시도 후 보고 |
| 실제 모델 | 지정 모델과 일치 | `~/.claude/projects/<proj>/<session>/subagents/agent-*.meta.json`의 `model` |
| 금지 모델 | 워커 중 fable-5/opus-4-8 없음 (planner 제외) | 동일 meta.json |

## V3. E2E 미니 사이클 (선택)

작은 버그 픽스처(예: 음수 미지원 mul)로 파이프라인 1회전:

1. checker → 버그 요약 JSON
2. planner(Workflow) → `DESIGN_WRITTEN <경로>` + 설계 파일 4섹션 존재
3. implementer(SendMessage) → `IMPLEMENTED` + 최소 diff
4. tester → `ALL_PASS`
5. DA → codex 헤더(`gpt-5.5/xhigh` 등) + `APPROVED`

기준: 오케스트레이터가 설계/판정 내용을 직접 쓰지 않고 완주하면 PASS.

## V4. 실패 모드 재현 (지식 확인)

- ultracode 세션에서 sonnet5 워커를 Agent 경로로 스폰 → `400 level "xhigh" not supported` 확인 (이게 Workflow 경로 분리의 근거)
- codex를 `< /dev/null` 없이 백그라운드 실행 → hang 확인 (권장하지 않음, 문서로 대체 가능)
