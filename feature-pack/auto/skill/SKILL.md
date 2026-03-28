---
name: "auto"
description: "AutoResearch 자율 실험 루프 — program.md 기반 에이전트 자율 연구. 베이스라인→목표→자율주행 3단계 HIL."
version: "2.0.0"
created: 2026-03-28
updated: 2026-03-28
status: active
---

# AutoResearch — 자율 실험 루프 스킬

Karpathy AutoResearch 패턴 기반. 에이전트가 **타깃 파일 1개를 수정 → 실행 → 평가 → commit/revert**를 반복하며 자율적으로 실험을 진행한다.

## 아키텍처 원칙

**스킬 = 순수 가이드. 런타임은 프로젝트에.**

```
~/.claude/skills/auto/              ← 이 스킬 (가이드 + 레퍼런스만)
  SKILL.md
  references/
    git-loop-protocol.md
    report-template.md

{프로젝트}/                          ← /auto를 실행하는 곳
  autoresearch/                     ← /auto가 프로젝트 안에 생성
    upstream/                       ← karpathy/autoresearch 클론 (참조+업데이트용)
    program.md                      ← 에이전트 지시서 (목표, 규칙, 평가 방법)
    prepare.py                      ← 고정 인프라 (데이터, 평가 함수)
    <target>.py                     ← 에이전트가 수정할 타깃 파일 (1개만)
    e2e_test.py                     ← 벤치마크/E2E 테스트 (선택)
    results.tsv                     ← 실험 결과 로그
    run.log                         ← 최신 실행 로그
```

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
3. **Surgical** — 타깃 파일만 수정, 다른 파일 절대 건드리지 않음
4. **Goal-Driven** — 점수가 개선되면 keep, 아니면 즉시 revert

---

## Workflow 0: 프로젝트 초기화 (Setup)

### 목적
현재 프로젝트에 `autoresearch/` 폴더를 만들고 실험 환경을 구성한다.

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
  else
    cd autoresearch/upstream && git pull --ff-only
  fi

Step 3: 기존 파일 감지
  프로젝트 루트에 이미 program.md, train.py 등이 있는지 확인
  → 있으면: "기존 파일을 autoresearch/ 로 이동할까요, 아니면 그대로 쓸까요?"
  → 없으면: Step 4로

Step 4: 사용자와 함께 핵심 파일 작성

  [program.md — 목표 가이드]
  사용자에게 질문:
  - "이 프로젝트에서 무엇을 최적화하고 싶은가요?"
  - "에이전트가 수정할 파일은 어떤 건가요? (1개)"
  - "실행 커맨드는? (예: uv run train.py, python experiment.py)"
  - "평가 지표와 방향은? (예: val_bpb 낮을수록 좋음)"
  - "시간 예산은? (예: 실험당 5분)"
  - "수정 금지 사항은? (예: prepare.py 건드리지 마)"

  답변을 기반으로 program.md 초안 작성 → 사용자 확인

  [prepare.py — 고정 인프라]
  - upstream에서 참조하거나 사용자가 직접 제공
  - 또는 에이전트가 프로젝트 맥락에 맞게 작성 도움

  [target 파일]
  - 이미 있는 파일 지정 또는 새로 생성
  - program.md에 명시

  [e2e_test.py — 벤치마크 (선택)]
  - 자동화된 평가 스크립트
  - 없으면 run 커맨드 + grep으로 결과 파싱

Step 5: .gitignore 업데이트
  autoresearch/upstream/   ← 클론은 추적하지 않음
  autoresearch/run.log     ← 로그는 추적하지 않음
  autoresearch/results.tsv ← 결과는 추적하지 않음 (선택)
```

---

## Workflow 1: Stage 1 — 베이스라인 실행 (HIL Gate 1)

### 목적
현재 코드 그대로 실행하여 기준 점수를 확립한다.

### 전제 조건
- `autoresearch/program.md` 존재
- 타깃 파일 존재
- 실행 환경 준비 완료 (데이터, 의존성)

### 플로우

```
Step 1: 전용 브랜치 생성
  TAG=$(date +%b%d | tr '[:upper:]' '[:lower:]')
  git checkout -b autoresearch/$TAG

Step 2: program.md 읽기
  → 타깃 파일, 실행 커맨드, 평가 지표, 시간 예산 파싱

Step 3: 타깃 파일을 수정 없이 실행
  $RUN_CMD > autoresearch/run.log 2>&1

Step 4: 결과 파싱
  run.log에서 평가 지표 추출

Step 5: 베이스라인 기록
  results.tsv 헤더 + baseline 행 추가

Step 6: 사용자에게 결과 보고 + 확인
  "베이스라인: val_bpb = 0.9979, VRAM = 44.0GB"
  "이 결과를 기준으로 실험을 시작할까요?"
```

### HIL Gate 1
- 베이스라인 점수 합리적인지 확인
- 환경 문제 없는지 확인
- **확인 후에만** Stage 2로

---

## Workflow 2: Stage 2 — 목표 설정 (HIL Gate 2)

### 목적
사용자와 개선 목표를 합의한다.

### 인터뷰

```
Q1: 목표 유형?
  (A) 구체적 숫자 — "val_bpb를 0.95 이하로"
  (B) 최대한 개선 — "가능한 한 낮게"
  (C) 특정 영역 탐색 — "옵티마이저만 바꿔서 개선"

Q2: 제약 조건?
  - VRAM 제한, 아키텍처 유지, 금지 변경 등

Q3: 우선 탐색 방향?
  - "학습률 위주", "아키텍처 위주", "알아서"
```

### HIL Gate 2
- 목표와 제약 조건 확정
- program.md에 목표 섹션 추가/업데이트
- **확인 후에만** Stage 3로

---

## Workflow 3: Stage 3 — 루프 설정 + 자율주행 시작 (HIL Gate 3)

### 인터뷰

```
Q1: 총 실행 시간? (기본: 1시간)
Q2: 중간 보고 간격? (기본: 10실험마다)
Q3: 조기 종료 조건? (기본: 목표 달성 시)
```

### 설정 확정 요약
```
[AutoResearch 설정 확정]
  타깃: train.py
  지표: val_bpb (lower is better)
  베이스라인: 0.9979
  목표: 0.95 이하
  시간: 2시간 (약 24실험)
  보고: 10실험마다
  브랜치: autoresearch/mar28
```

### HIL Gate 3
- 최종 설정 확인
- **"시작!" 받으면 자율주행 돌입**
- 이후 사용자가 수동으로 멈출 때까지 질문하지 않는다

---

## Workflow 4: 자율주행 실험 루프 (Autonomous)

### 루프 프로토콜

```
LOOP START (시간 또는 횟수 도달까지):

  1. 컨텍스트 수집
     - 타깃 파일 읽기
     - results.tsv 히스토리 읽기
     - 현재 best_score 확인

  2. 가설 선택
     - 이전 결과에서 패턴 파악
     - 한 번에 한 가지 변경만 선택
     - 연속 실패 5회 → 전략 피벗

  3. 코드 수정
     - 타깃 파일만 Edit
     - 변경 내용 한 줄 description 요약

  4. git commit (실험 전)
     - git add <타깃파일>
     - git commit -m "[실험] <description>"

  5. 실행
     - $RUN_CMD > autoresearch/run.log 2>&1
     - 타임아웃: 시간예산 × 2 초과 시 kill

  6. 결과 파싱
     - run.log에서 지표 추출
     - 크래시: tail -n 50 run.log 확인

  7. 판정
     크래시 → 간단 수정(최대 2회) 또는 revert + crash 기록
     개선됨 → results.tsv keep 기록, best_score 갱신
     개선 안됨 → results.tsv discard 기록, git reset --hard HEAD~1

  8. 중간 보고 (N실험마다)
     "=== [10/24] 중간 보고 ==="
     "  최고: 0.9721 (실험 #7)"
     "  성공률: 4/10 (40%)"

  9. 종료 조건 확인
     시간 초과 / 목표 달성 / 사용자 인터럽트 → LOOP END

LOOP END
```

### 전략 피벗 (연속 5회 실패 시)
```
1. 현재 카테고리 기록 (아키텍처/옵티마이저/하이퍼파라미터/정규화)
2. 미시도 카테고리로 전환
3. 카운터 리셋
4. 모든 카테고리 소진 → near-miss 조합, 반대 방향, 코드 단순화
```

---

## Workflow 5: 최종 리포트

### 자율주행 완료 후 생성

리포트 저장 위치: `autoresearch/report-{tag}.md`

내용:
- 요약 (기간, 실험 횟수, 성공률, 베이스라인→최고점수, 개선률)
- 점수 추이 테이블 (results.tsv → 마크다운)
- 성공한 변경 상세
- 실패 교훈/패턴 분석
- git log (성공 커밋만)
- 다음 단계 제안

상세 템플릿: `references/report-template.md` 참조

---

## /auto 사용법

| 명령 | 설명 |
|------|------|
| `/auto` | 현재 프로젝트에서 시작 (setup→baseline→목표→자율주행) |
| `/auto setup` | autoresearch/ 폴더 초기화만 |
| `/auto 2h` | 2시간 자율주행 |
| `/auto 30m` | 30분 자율주행 |
| `/auto overnight` | 8시간 자율주행 |
| `/auto resume` | 기존 브랜치에서 이어서 실행 |
| `/auto report` | 현재 results.tsv 기반 리포트만 생성 |
| `/auto update` | upstream/ 클론 git pull |

---

## 프로젝트별 파일 역할

| 파일 | 누가 작성 | 누가 수정 | 설명 |
|------|----------|----------|------|
| `autoresearch/upstream/` | /auto (클론) | /auto (pull) | Karpathy 원본 참조용 |
| `autoresearch/program.md` | 사용자 + /auto 도움 | 사용자 | 에이전트 지시서 (목표, 규칙, 평가) |
| `autoresearch/prepare.py` | 사용자 | 수정 금지 | 고정 인프라 (데이터, 평가 함수) |
| `autoresearch/<target>.py` | 사용자/에이전트 | 에이전트만 | 실험 대상 파일 (유일한 수정 대상) |
| `autoresearch/e2e_test.py` | 사용자 + /auto 도움 | 수정 금지 | 벤치마크/E2E 테스트 (선택) |
| `autoresearch/results.tsv` | /auto | /auto | 실험 결과 (untracked) |
| `autoresearch/run.log` | /auto | /auto | 최신 실행 로그 (untracked) |
| `autoresearch/report-*.md` | /auto | /auto | 최종 리포트 |

---

## Best Practices

1. **program.md를 잘 쓰는 것이 핵심** — 에이전트의 행동 범위가 여기서 결정됨
2. **upstream은 참조용** — 직접 수정하지 않고 패턴/코드 참고만
3. **짧은 시간 예산** — 실험당 5분 이내로 설정해야 많은 실험 가능
4. **results.tsv는 untracked** — git에 추가하지 않고 로컬에만 유지
5. **전용 브랜치** — master에서 직접 실험하지 않음
6. **타깃 파일은 반드시 1개** — 디버깅과 롤백이 쉬움

## References

- `references/git-loop-protocol.md` — git 기반 실험 루프 상세 프로토콜
- `references/report-template.md` — 리포트 템플릿

## Evolution Engine

### Permanent Evolution
(장기 기억 — 절대 삭제 금지)
- v2.0: 스킬은 순수 가이드만, 런타임 파일은 프로젝트 `autoresearch/` 폴더에 생성하는 구조로 전환

### Ongoing Evolution
(최근 경험. FIFO 관리. 250줄 초과 시 오래된 항목 삭제)
- 2026-03-28: v1→v2 구조 개편 | 클론을 스킬 안이 아닌 프로젝트에 두도록 변경 | 사용자 피드백 반영
