# AutoResearch 리포트 템플릿

## 파일명 규칙
```
autoresearch-report-{tag}.md
```
예: `autoresearch-report-mar28.md`

---

## 템플릿

```markdown
# AutoResearch 리포트 — {tag}

## 요약

| 항목 | 값 |
|------|-----|
| 브랜치 | `autoresearch/{tag}` |
| 기간 | {시작} ~ {종료} ({총 시간}) |
| 실험 횟수 | {total} |
| 성공 (keep) | {keep_count} ({keep_pct}%) |
| 실패 (discard) | {discard_count} ({discard_pct}%) |
| 크래시 (crash) | {crash_count} ({crash_pct}%) |
| 베이스라인 | {baseline_score} |
| 최종 최고 | {best_score} |
| 개선률 | {improvement_pct}% |
| 최고 기록 커밋 | `{best_commit}` |

## 점수 추이

| # | commit | score | memory | status | description |
|---|--------|-------|--------|--------|-------------|
| 1 | a1b2c3d | 0.9979 | 44.0 | baseline | baseline |
| 2 | b2c3d4e | 0.9932 | 44.2 | keep | increase LR to 0.04 |
| ... | ... | ... | ... | ... | ... |

## 성공한 변경들

### 1. {description} (실험 #{n})
- **변경**: {구체적 코드 변경 내용}
- **점수**: {이전} → {이후} ({차이})
- **커밋**: `{hash}`

### 2. {description} (실험 #{n})
- ...

## 실패에서 배운 교훈

### 효과 없던 방향
- **{카테고리}**: {시도 내용} → {결과 요약}

### 크래시 원인
- **{원인}**: {발생 횟수}회 — {회피 방법}

## Git 히스토리

```
{git log --oneline 출력}
```

## 다음 단계 제안

1. **아직 미시도**: {구체적 아이디어}
2. **유망했지만 시간 부족**: {구체적 아이디어}
3. **다른 접근**: {근본적으로 다른 방향}
```

---

## 리포트 생성 로직

### 데이터 수집
```python
# results.tsv 파싱
import csv
with open('results.tsv') as f:
    reader = csv.DictReader(f, delimiter='\t')
    rows = list(reader)

total = len(rows)
keeps = [r for r in rows if r['status'] == 'keep']
discards = [r for r in rows if r['status'] == 'discard']
crashes = [r for r in rows if r['status'] == 'crash']
baseline = rows[0] if rows else None

# 최고 점수 (방향에 따라)
if direction == 'minimize':
    best = min(keeps, key=lambda r: float(r['score']))
else:
    best = max(keeps, key=lambda r: float(r['score']))
```

### git 히스토리 수집
```bash
git log --oneline autoresearch/{tag}
```

### 개선률 계산
```python
if direction == 'minimize':
    improvement = (baseline_score - best_score) / baseline_score * 100
else:
    improvement = (best_score - baseline_score) / baseline_score * 100
```
