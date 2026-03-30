# AutoResearch v3.0 — 설치 가이드

## Prerequisites

- Python 3.11+
- git
- [uv](https://docs.astral.sh/uv/) — `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Claude Code 또는 호환 에이전트 CLI

## 설치

### Step 1: 스킬 파일 복사

```bash
# 스킬 디렉토리 생성
mkdir -p ~/.claude/skills/auto/references

# 스킬 파일 복사
cp skill/SKILL.md ~/.claude/skills/auto/SKILL.md
cp skill/references/*.md ~/.claude/skills/auto/references/
```

### Step 2: 프로젝트에 autoresearch 초기화

프로젝트 루트에서:

```bash
# autoresearch 디렉토리 생성
mkdir -p autoresearch

# 템플릿 복사
cp config/templates/pyproject.toml autoresearch/
cp config/templates/prepare.py autoresearch/
cp config/templates/run_experiment.py autoresearch/
cp config/templates/program.md autoresearch/

# uv 환경 초기화
cd autoresearch && uv sync
```

### Step 3: 프로젝트에 맞게 커스터마이징

1. **program.md** — 실험 목표, metric, scope 작성
2. **prepare.py** — `check_runtime()`, `check_data()` 커스터마이징
3. **run_experiment.py** — `RUN_CMD`, `parse_result()`, `TIMEOUT` 커스터마이징

### Step 4: .gitignore 추가

```bash
cat >> autoresearch/.gitignore << 'EOF'
.venv/
run.log
results.tsv
upstream/
__pycache__/
EOF
```

## 검증

```bash
# 스킬 로드 확인
grep "version" ~/.claude/skills/auto/SKILL.md
# Expected: version: "3.0.0"

# uv 환경 확인
cd autoresearch && uv run python -c "import requests; print('OK')"
```

## 사용법

에이전트 세션에서:

```
/auto              # 전체 플로우 시작
/auto setup        # 초기화만
/auto 2h           # 2시간 자율주행
/auto resume       # 이어서
/auto report       # 리포트 생성
```

## 아키텍처

```
에이전트: 코드 수정 → uv run run_experiment.py → stdout JSON 읽기 → 판정
                    (4단계. 나머지는 전부 Python 스크립트가 자율 처리)

autoresearch/
  pyproject.toml          ← uv 의존성
  prepare.py              ← 인프라 셋업 (1회, 멱등)
  run_experiment.py       ← 실험 실행기 (stdout JSON 계약)
  program.md              ← 목표 선언형 지시서
  results.tsv             ← 실험 결과 (untracked)
```
