# Git 기반 실험 루프 프로토콜

## 브랜치 전략

```
master (또는 main)
  └── autoresearch/<tag>     ← 실험 전용 브랜치
       ├── commit: baseline
       ├── commit: [실험] increase LR to 0.04    ← keep (전진)
       ├── (reverted: switch to GeLU)             ← discard (되돌림)
       ├── commit: [실험] double model width      ← keep (전진)
       └── ...
```

## 브랜치 생성

```bash
# 태그 자동 생성 (날짜 기반)
TAG=$(date +%b%d | tr '[:upper:]' '[:lower:]')

# 기존 브랜치 확인
if git rev-parse --verify "autoresearch/$TAG" >/dev/null 2>&1; then
  # 이미 존재하면 넘버링: mar28-2, mar28-3...
  N=2
  while git rev-parse --verify "autoresearch/$TAG-$N" >/dev/null 2>&1; do
    N=$((N+1))
  done
  TAG="$TAG-$N"
fi

git checkout -b "autoresearch/$TAG"
```

## 실험 커밋 규칙

### 실험 전 커밋
```bash
# 타깃 파일만 스테이징
git add <target_file>
git commit -m "[실험] <한 줄 설명>"
```

### 성공 시 (keep)
```bash
# 커밋 유지 — 아무것도 안 함
# results.tsv에 keep 기록 (untracked)
```

### 실패 시 (discard)
```bash
# 마지막 커밋 되돌리기
git reset --hard HEAD~1
# results.tsv에 discard 기록 (untracked이므로 reset 영향 없음)
```

### 크래시 시
```bash
# 간단한 수정 가능하면:
#   수정 후 git add && git commit --amend → 재실행

# 근본적 문제면:
git reset --hard HEAD~1
# results.tsv에 crash 기록
```

## results.tsv 관리

### 핵심 규칙
- **git에 추가하지 않는다** (.gitignore에 등록 권장)
- 모든 실험 결과를 순서대로 기록 (keep, discard, crash 모두)
- 탭 구분 (TSV), 쉼표는 description에서 사용 금지

### 컬럼 (프로젝트별 커스터마이징)

**LLM 학습 도메인:**
```
commit	val_bpb	memory_gb	status	description
```

**STT 벤치마크 도메인:**
```
commit	provider	model	avg_cer	avg_latency_ms	cost_usd	composite	status	description
```

**범용 (최소):**
```
commit	score	status	description
```

### 상태값
| status | 의미 |
|--------|------|
| `keep` | 개선됨, 커밋 유지 |
| `discard` | 개선 안 됨, 커밋 되돌림 |
| `crash` | 실행 실패, 커밋 되돌림 |
| `baseline` | 최초 기준 실행 |

## 실험 이어하기 (Resume)

```bash
# 기존 브랜치 확인
git branch | grep autoresearch/

# 이어서 실행
git checkout autoresearch/<tag>

# 마지막 결과 확인
tail -5 results.tsv

# 현재 best score 확인
# (results.tsv에서 keep 중 최고/최저 추출)
```

## 안전장치

### 타임아웃
```bash
# 실험당 시간예산 × 2 초과 시 강제 종료
timeout $((TIME_BUDGET * 2)) $RUN_CMD > run.log 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 124 ]; then
  echo "TIMEOUT" >> run.log
fi
```

### 실행 전 검증
```bash
# 문법 검사 (Python)
python -c "import ast; ast.parse(open('train.py').read())"
```

### 복구
```bash
# 상태가 꼬였을 때
git status
git stash  # 필요시
git reset --hard HEAD  # 현재 커밋으로 복원
```
