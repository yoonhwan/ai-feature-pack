# Feature Pack: auto (AutoResearch)
> 에이전트 자율 설치 프롬프트 — 자율 실험 루프 스킬

## 개요

`/auto` 스킬은 Karpathy AutoResearch 패턴 기반 자율 실험 루프.
에이전트가 타깃 파일 1개를 수정→실행→평가→commit/revert를 반복하며 자율 최적화한다.

**순수 스킬** — 외부 CLI 설치 없음. 스킬 파일 복사만으로 설치 완료.

**할 수 있는 것:**
- 베이스라인 수립 → 목표 설정 → 자율주행 실험 루프
- git 기반 실험 추적 (전용 브랜치, commit/revert)
- results.tsv 결과 로그 + 최종 리포트 생성
- 전략 피벗 (연속 실패 시 탐색 방향 자동 전환)

## Prerequisites

| 항목 | 필수 | 확인 명령 |
|------|------|----------|
| git | ✅ | `git --version` |
| python3 | ✅ | `python3 --version` |

> 이미 시스템에 설치된 도구만 필요. 추가 설치 없음.

## Step 1: 스킬 파일 복사

```bash
mkdir -p {{CLAUDE_SKILLS_PATH}}/auto/references/
cp -r skill/SKILL.md {{CLAUDE_SKILLS_PATH}}/auto/
cp -r skill/references/ {{CLAUDE_SKILLS_PATH}}/auto/
```

> Placeholder `{{CLAUDE_SKILLS_PATH}}`: Claude 스킬 경로 (기본: `~/.claude/skills`)

검증:
```bash
ls -la {{CLAUDE_SKILLS_PATH}}/auto/SKILL.md
ls -la {{CLAUDE_SKILLS_PATH}}/auto/references/
```

## Step 2: 설치 검증

```bash
# 1. 메인 스킬 파일 존재
test -f {{CLAUDE_SKILLS_PATH}}/auto/SKILL.md && echo "✅ SKILL.md" || echo "❌ SKILL.md missing"

# 2. git-loop-protocol 레퍼런스
test -f {{CLAUDE_SKILLS_PATH}}/auto/references/git-loop-protocol.md && echo "✅ git-loop-protocol.md" || echo "❌ missing"

# 3. report-template 레퍼런스
test -f {{CLAUDE_SKILLS_PATH}}/auto/references/report-template.md && echo "✅ report-template.md" || echo "❌ missing"

# 4. git 사용 가능
git --version && echo "✅ git OK" || echo "❌ git not found"

# 5. python3 사용 가능
python3 --version && echo "✅ python3 OK" || echo "❌ python3 not found"
```

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `/auto` 트리거 안 됨 | 스킬 파일 미복사 | Step 1 재실행 |
| `references/` 누락 | 디렉토리 복사 실패 | `cp -r skill/references/ {{CLAUDE_SKILLS_PATH}}/auto/` |
| `git: command not found` | git 미설치 | `brew install git` 또는 `xcode-select --install` |
| `python3: command not found` | python3 미설치 | `brew install python3` |

## Placeholder 정리

| Placeholder | 질문 | 기본값 |
|-------------|------|--------|
| `{{CLAUDE_SKILLS_PATH}}` | Claude 스킬 경로가 어디인가요? | `~/.claude/skills` |

## 설치 완료 후

```bash
# 프로젝트에서 바로 사용
/auto            # 전체 흐름 시작
/auto setup      # autoresearch/ 폴더 초기화만
/auto 2h         # 2시간 자율주행
/auto resume     # 기존 브랜치에서 이어서
/auto report     # 결과 리포트 생성
```
