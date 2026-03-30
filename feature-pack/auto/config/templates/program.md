# {PROJECT_NAME} AutoResearch

## Objective
{한 문장으로 실험 목표 — 예: "val_bpb를 최소화한다"}

## Metrics
| 지표 | 방향 | 베이스라인 | 게이트 |
|------|------|----------|--------|
| {primary} | {lower/higher} is better | {값} | {임계값} |
| {secondary} | {lower/higher} is better | {값} | — |

primary_metric: {게이트 — 악화 시 무조건 revert}
secondary_metric: {최적화 대상}

## Run Command
```bash
cd autoresearch && uv run run_experiment.py
```

## Scope (수정 가능 영역)
- {디렉토리/파일 패턴}

## Off-Limits (수정 금지)
- `autoresearch/*` — 실험 인프라
- {프로젝트별 금지 영역}

## Constraints
- 한 실험에 1영역 1~2파일만 수정
- 게이트 메트릭 통과 실패 시 무조건 revert
- 연속 5회 실패 시 전략 피벗

## Exploration Hints (선택적)
- {방향만 제시, 구체적 라인 번호 없이}
