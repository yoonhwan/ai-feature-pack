# run_experiment.py stdout JSON 계약

## 출력 형식

run_experiment.py는 stdout에 **정확히 1줄 JSON**을 출력한다 (마지막 줄).
그 외 모든 출력(progress, warnings)은 stderr 또는 run.log에 기록.

## 필드 정의

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| score | float\|null | Y | primary metric 값 |
| passed | int | Y | 통과한 테스트 수 |
| total | int | Y | 전체 테스트 수 |
| failed | string[] | Y | 실패한 테스트 ID |
| grade_summary | string | Y | 등급 요약 (예: "13S 1A") |
| flush_e2e_ms | float\|null | N | secondary metric |
| status | string | Y | "ok" \| "crash" \| "error" |
| reason | string | N | status가 crash/error일 때 원인 |
| duration_s | float | Y | 실험 소요 시간 (초) |

## Exit Code

| code | 의미 | 에이전트 행동 |
|------|------|-------------|
| 0 | 실험 정상 완료 | score로 keep/discard 판정 |
| 1 | 크래시 또는 인프라 실패 | revert 또는 수정 시도 (최대 2회) |

## 에이전트 판정 규칙

```
if exit_code == 1:
    verdict = "crash"
    git reset --hard HEAD~1
elif score > gate_threshold:
    verdict = "discard"
    git reset --hard HEAD~1
elif score <= best_score:
    verdict = "keep"
    best_score = score
else:
    verdict = "discard"
    git reset --hard HEAD~1
```

## results.tsv 기록 흐름

1. run_experiment.py가 실행 직후 자동 append (status=ok/crash, verdict=빈칸)
2. 에이전트가 판정 후 verdict 컬럼 업데이트 (keep/discard/crash)

## 프로젝트별 커스터마이징

| 도메인 | score 필드 | 방향 | 게이트 |
|--------|-----------|------|--------|
| STT 품질 | avg_cer | lower is better | < 0.03 |
| LLM 학습 | val_bpb | lower is better | 프로젝트별 |
| 레이턴시 | p99_ms | lower is better | — |
| 정확도 | accuracy | higher is better | > 0.95 |
