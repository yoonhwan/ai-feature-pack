---
name: "auto"
description: "AutoResearch 자율 실험 루프 — Karpathy 패턴. 에이전트는 코드만 수정, uv run으로 자율 실행, stdout JSON으로 판정."
version: "3.0.0"
created: 2026-03-28
updated: 2026-03-30
status: active
---

# AutoResearch — 자율 실험 루프 스킬 v3

Karpathy AutoResearch 패턴. **에이전트는 코드만 수정. 실행은 `uv run`. 개입 없음.**

## 핵심 원칙

```
에이전트 역할: 코드 수정 → uv run run_experiment.py → stdout JSON 읽기 → 판정
                (4단계. 나머지는 전부 Python 스크립트가 자율 처리)
```

1. **에이전트는 코드만 수정** — 서버 reload, 페이지 리로드, 테스트 실행 등 인프라 조작 금지
2. **uv run이 모든 걸 한다** — `run_experiment.py`가 인프라 체크 + 테스트 실행 + metric 출력
3. **stdout JSON이 유일한 인터페이스** — 에이전트는 JSON만 읽고 keep/discard 판정
4. **program.md는 목표 선언** — TODO 리스트가 아닌 metric + scope + constraints

## 아키텍처

```
{프로젝트}/
  autoresearch/
    pyproject.toml          ← uv 의존성 (autoresearch 전용)
    prepare.py              ← 인프라 셋업 (1회 실행, 멱등)
    run_experiment.py       ← 실험 실행기 (uv run 대상, stdout JSON)
    e2e_test.py             ← 평가 하네스 (프로젝트별, 수정 금지)
    program.md              ← 에이전트 지시서 (목표 선언형)
    results.tsv             ← 실험 결과 로그 (untracked)
    run.log                 ← 최신 실행 로그 (untracked)
    upstream/               ← karpathy/autoresearch 클론 (참조용)
```

### 3층 실행 구조

```
Layer 1: uv run prepare.py      (1회) 인프라 셋업
Layer 2: 에이전트 자율 루프       코드 수정 → uv run → JSON → 판정
Layer 3: uv run run_experiment.py (매회) 자체 완결 실험기
```

### 파일 역할

| 파일 | 작성자 | 수정 권한 | 실행 방법 |
|------|--------|----------|----------|
| pyproject.toml | /auto setup | 사용자 | `uv sync` |
| prepare.py | /auto setup | 수정 금지 | `uv run prepare.py` (1회) |
| run_experiment.py | /auto setup | 수정 금지 | `uv run run_experiment.py` (매 실험) |
| e2e_test.py | 사용자 | 수정 금지 | run_experiment.py가 내부 호출 |
| program.md | 사용자 + /auto | 사용자 | 에이전트가 읽기 |

## Trigger

### 자동 실행
- "auto", "/auto", "autoresearch", "자율 실험", "오토리서치"
- "실험 루프", "experiment loop", "자율주행 리서치"
- "베이스라인 돌려", "baseline run"

### 트리거 제외
- 단순 코드 수정 요청 (autoresearch 패턴이 아닌 경우)

## Behavioral Guidelines

1. **Think First** — program.md를 완전히 읽고 이해한 후에만 실험 시작
2. **한 번에 한 가지 변경** — 여러 변경을 동시에 하지 않는다
3. **Surgical** — 타깃 영역(1~2파일)만 수정, 다른 파일 절대 건드리지 않음
4. **Goal-Driven** — 점수가 개선되면 keep, 아니면 즉시 revert
5. **No Infrastructure Touch** — autoresearch/ 안의 파일은 절대 수정하지 않음

---

## Workflow 0: 프로젝트 초기화 (Setup)

### 목적
현재 프로젝트에 `autoresearch/` 폴더를 만들고 uv 환경을 구성한다.

### 실행 조건
- `{프로젝트}/autoresearch/` 폴더가 없을 때
- 또는 사용자가 `/auto setup` 명시

### 플로우

```
Step 1: autoresearch/ 디렉토리 생성
  mkdir -p autoresearch/upstream

Step 2: upstream 클론 (참조용)
  if [ ! -d "autoresearch/upstream/.git" ]; then
    git clone https://github.com/karpathy/autoresearch.git autoresearch/upstream
  fi

Step 3: pyproject.toml 생성
  [project]
  name = "autoresearch"
  version = "0.1.0"
  requires-python = ">=3.11"
  dependencies = ["requests>=2.31"]
  # 프로젝트별 추가 의존성은 사용자가 편집

Step 4: uv sync
  cd autoresearch && uv sync

Step 5: 사용자와 함께 핵심 파일 작성

  [program.md — 목표 선언형]
  사용자에게 질문:
  - "무엇을 최적화하고 싶은가요?" (metric)
  - "수정 가능한 영역은?" (scope)
  - "수정 금지 영역은?" (off-limits)
  - "실행 환경은?" (서버, 브라우저, GPU 등)
  - "평가 방법은?" (기존 테스트 스크립트? 새로 작성?)

  [prepare.py — 인프라 셋업]
  프로젝트 환경에 맞게 check_* 함수 커스터마이징:
  - 웹앱: 서버 + 브라우저 + CDP
  - ML: GPU + 데이터셋 + 모델
  - CLI: 바이너리 + 테스트 픽스처

  [run_experiment.py — 실험 실행기]
  프로젝트에 맞게 커스터마이징:
  - RUN_CMD: 실험 실행 커맨드
  - parse_result(): 출력 파싱 → JSON
  - TIMEOUT: 실험당 시간 예산

  [e2e_test.py — 평가 하네스 (선택)]
  기존 테스트가 있으면 --json 출력 추가
  없으면 에이전트가 프로젝트 맥락에 맞게 작성 도움

Step 6: .gitignore 업데이트
  autoresearch/.venv/
  autoresearch/run.log
  autoresearch/results.tsv
  autoresearch/upstream/
```

---

## Workflow 1: Stage 1 — 베이스라인 실행 (HIL Gate 1)

### 플로우

```
Step 1: 전용 브랜치 생성
  TAG=$(date +%b%d | tr '[:upper:]' '[:lower:]')
  git checkout -b autoresearch/$TAG

Step 2: program.md 읽기 → 타깃, metric, 게이트 파싱

Step 3: 인프라 준비
  cd autoresearch && uv run prepare.py
  → {"ready": true, ...} 확인

Step 4: 베이스라인 실험 실행 (코드 수정 없이)
  cd autoresearch && uv run run_experiment.py
  → stdout JSON에서 score 추출

Step 5: results.tsv 확인 (run_experiment.py가 자동 기록)

Step 6: 사용자에게 결과 보고
  "베이스라인: avg_cer = 0.004, 13/14 통과"
  "이 결과를 기준으로 실험을 시작할까요?"
```

### HIL Gate 1
- 베이스라인 합리적인지 확인
- 환경 문제 없는지 확인
- **확인 후에만** Stage 2로

---

## Workflow 2: Stage 2 — 목표 설정 (HIL Gate 2)

### 인터뷰

```
Q1: 목표 유형?
  (A) 구체적 숫자 — "avg_cer를 0.002 이하로"
  (B) 최대한 개선 — "가능한 한 낮게"
  (C) 특정 영역 탐색 — "레이턴시만 줄여서"

Q2: 제약 조건?

Q3: 우선 탐색 방향?
```

### HIL Gate 2
- 목표와 제약 확정 → program.md 업데이트
- **확인 후에만** Stage 3로

---

## Workflow 3: Stage 3 — 루프 설정 + 자율주행 시작 (HIL Gate 3)

### 인터뷰

```
Q1: 총 실행 시간? (기본: 1시간)
Q2: 중간 보고 간격? (기본: 10실험마다)
Q3: 조기 종료 조건? (기본: 목표 달성 시)
```

### HIL Gate 3
- "시작!" 받으면 자율주행 돌입
- 이후 사용자가 멈출 때까지 질문하지 않는다

---

## Workflow 4: 자율주행 실험 루프 (Autonomous)

### 루프 프로토콜 (4단계)

```
LOOP START (시간 또는 횟수 도달까지):

  1. 컨텍스트 수집
     - program.md 읽기 (목표, scope, constraints)
     - results.tsv 읽기 (히스토리, best_score)
     - 타깃 영역 코드 읽기

  2. 가설 → 코드 수정
     - 이전 결과에서 패턴 파악
     - 한 번에 한 가지 변경, 1영역 1~2파일
     - Edit tool로 수정
     - git commit -m "[실험] <설명>"

  3. uv run run_experiment.py (원커맨드, 개입 없음)
     - 에이전트는 이 커맨드만 실행
     - 서버 reload, 페이지 리로드, 테스트 실행은 전부 스크립트가 처리
     - stdout 마지막 줄 JSON 읽기

  4. 판정
     exit 1 (크래시) → 간단 수정(최대 2회) 또는 revert + crash 기록
     score > gate → revert + discard 기록
     score <= best_score → keep, best_score 갱신
     score > best_score (게이트 통과) → revert + discard 기록

  (중간 보고 — N실험마다)
  (종료 조건 확인 — 시간/목표/인터럽트)

LOOP END
```

### 전략 피벗 (연속 5회 실패 시)
```
1. 현재 카테고리 기록
2. 미시도 카테고리로 전환
3. 카운터 리셋
4. 모든 카테고리 소진 → near-miss 조합, 반대 방향, 코드 단순화
```

---

## Workflow 5: 최종 리포트

자율주행 완료 후 `autoresearch/report-{tag}.md` 생성.
상세 템플릿: `references/report-template.md` 참조.

---

## /auto 사용법

| 명령 | 설명 |
|------|------|
| `/auto` | 시작 (setup→baseline→목표→자율주행) |
| `/auto setup` | autoresearch/ 초기화만 |
| `/auto 2h` | 2시간 자율주행 |
| `/auto 30m` | 30분 자율주행 |
| `/auto overnight` | 8시간 자율주행 |
| `/auto resume` | 기존 브랜치에서 이어서 |
| `/auto report` | results.tsv 기반 리포트 생성 |
| `/auto update` | upstream/ git pull |

---

## stdout JSON 계약

run_experiment.py 출력 형식. 상세: `references/run-experiment-contract.md`

```json
{
  "score": 0.004,
  "passed": 13,
  "total": 14,
  "failed": ["zh-TW-long"],
  "grade_summary": "13S 1A",
  "flush_e2e_ms": null,
  "status": "ok",
  "duration_s": 187.3
}
```

- exit 0 = 정상 (에이전트가 score로 keep/discard 판정)
- exit 1 = 크래시 (에이전트가 revert 또는 수정 시도)

---

## Best Practices

1. **program.md를 잘 쓰는 것이 핵심** — metric, scope, constraints가 에이전트 행동 범위 결정
2. **prepare.py는 1회 실행** — 멱등이므로 불안하면 다시 돌려도 됨
3. **짧은 시간 예산** — 실험당 5분 이내로 설정해야 많은 실험 가능
4. **전용 브랜치** — master에서 직접 실험하지 않음
5. **1영역 1~2파일** — 디버깅과 롤백이 쉬움
6. **한 번에 한 가지 변경** — 패턴 감지에 명확성 필요
7. **autoresearch/ 인프라 절대 수정 금지** — 에이전트는 프로젝트 소스만 수정

## References

- `references/git-loop-protocol.md` — git 기반 실험 루프 프로토콜
- `references/run-experiment-contract.md` — stdout JSON 계약 명세
- `references/report-template.md` — 리포트 템플릿

## Evolution Engine

### Permanent Evolution
- v2.0: 스킬은 순수 가이드만, 런타임 파일은 프로젝트 autoresearch/ 폴더에 생성
- v3.0: Karpathy 패턴 정합성 복원 — 에이전트 4단계(수정→run→JSON→판정), uv 기반, program.md 목표 선언형

### Ongoing Evolution
- 2026-03-30: v2→v3 재설계 | 에이전트 8단계→4단계, prepare.py+run_experiment.py 3층 구조 도입, program.md TODO→목표 선언형, uv 기본 패키지 매니저
- 2026-03-28: v1→v2 구조 개편 | 클론을 스킬 안이 아닌 프로젝트에 두도록 변경
