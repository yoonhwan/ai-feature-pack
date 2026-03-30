# 🔬 AutoResearch Feature Pack v3.0

**Karpathy AutoResearch 패턴 기반 자율 실험 루프.**

에이전트는 코드만 수정. `uv run`이 실험을 자율 실행. stdout JSON으로 keep/discard 판정.

## 핵심 원칙

| Before (v2) | After (v3) |
|-------------|------------|
| 에이전트가 8단계 직접 수행 | 에이전트 4단계: 수정→run→JSON→판정 |
| program.md = TODO 리스트 | program.md = 목표 선언 |
| 인프라 조작 수동 | prepare.py 자동 셋업 |
| venv + pip | uv 격리 환경 |

## 3층 구조

```
Layer 1: uv run prepare.py        (1회) 인프라 체크 + 셋업
Layer 2: 에이전트 자율 루프         코드 수정 → run → JSON → 판정
Layer 3: uv run run_experiment.py  (매회) 테스트 실행 → metric 출력
```

## 빠른 시작

```bash
# 1. 스킬 설치
cp skill/SKILL.md ~/.claude/skills/auto/SKILL.md
cp skill/references/*.md ~/.claude/skills/auto/references/

# 2. 프로젝트에 템플릿 복사
cp config/templates/* your-project/autoresearch/

# 3. 커스터마이징 (program.md, prepare.py, run_experiment.py)

# 4. 에이전트에서 /auto 실행
```

## 도메인별 예시

| 도메인 | primary_metric | RUN_CMD | prepare.py |
|--------|---------------|---------|------------|
| ML 학습 | val_bpb | `uv run train.py` | GPU + 데이터셋 체크 |
| STT 품질 | avg_cer | `python3 e2e_test.py --baseline --json` | 서버 + 브라우저 + 오디오 |
| API 레이턴시 | p99_ms | `pytest tests/perf.py --json` | 서버 + DB |
| 코드 품질 | coverage | `pytest --cov --json` | 의존성 체크 |

## 파일 구조

```
feature-pack/auto/
  manifest.json          ← 패키지 메타데이터
  INSTALL.md             ← 설치 가이드
  README.md              ← 이 파일
  skill/
    SKILL.md             ← Claude Code 스킬 (v3.0)
    references/
      git-loop-protocol.md
      run-experiment-contract.md
      report-template.md
  config/
    templates/
      pyproject.toml     ← uv 환경 템플릿
      prepare.py         ← 인프라 셋업 템플릿
      run_experiment.py  ← 실험 실행기 템플릿
      program.md         ← 목표 선언 템플릿
  test/
    verify.md            ← 설치 검증
```

## 참조

- [karpathy/autoresearch](https://github.com/karpathy/autoresearch) — 원본
- `skill/references/run-experiment-contract.md` — stdout JSON 계약 상세
