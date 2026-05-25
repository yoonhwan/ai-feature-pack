---
description: 다중 세션 컨텍스트를 단일 SSOT 파일로 압축
argument-hint: <topic>
allowed-tools: Bash, Read, Write
---

# /baton:digest (v1.2.8+)

다중 세션 + 문서 + 코드 + 아키텍처 + auto memory → **단일 SSOT 파일**로 압축.
수동 트리거 전용. 전체 대화를 열어서 압축하는 무거운 작업.

## 언제 사용하나

| 상황 | 도구 |
|------|------|
| 세션 종료 시 다음 턴 지시 | `/baton:save` (NEXT.md ≤1KB) |
| **N세션 누적 컨텍스트를 SSOT 1파일로** | `/baton:digest` |

`baton:save`는 1세션 스냅샷. `baton:digest`는 N세션 종합 압축.

## 사용법

```
/baton:digest gpu-stt-tts        # → docs/digest/GPU_STT_TTS.md
/baton:digest auth-refactor      # → docs/digest/AUTH_REFACTOR.md
```

topic은 kebab-case 입력 → 파일명은 UPPER_SNAKE_CASE 자동 변환.

## 출력 위치

```
{project}/docs/digest/{TOPIC}.md
```

- **git 커밋 대상** — 워크트리 아카이브 후에도 main에서 접근 가능
- `.baton/handoff/` 에 두지 않음 (워크트리 압축 시 소실)

## 동작 (3-step)

### Step 1: 소스 수집 (Read)

현재 세션 컨텍스트 + 아래 소스를 Read:

| 소스 | 경로 | 용도 |
|------|------|------|
| 핸드오프 4파일 | `.baton/handoff/{PLAN,JOURNAL,CURRENT,NEXT}.md` | 세션 히스토리, 결정, 블로커 |
| auto memory | `~/.claude/projects/*/memory/*.md` | 프로젝트별 메모리 |
| git log | `git log --oneline` (base branch 이후) | 커밋 타임라인 |
| git diff stat | `git diff --stat {base}..HEAD` | 변경 규모 |
| 기존 digest | `docs/digest/{TOPIC}.md` (있으면) | 증분 업데이트 |

### Step 2: DIGEST 작성 (Write)

아래 **7섹션 strict 템플릿**으로 `docs/digest/{TOPIC}.md` 작성.

```markdown
# {제목} — DIGEST

> 이 파일 하나로 신규 세션이 풀 컨텍스트 캐치 가능.

## 세션 히스토리

| 항목 | 값 |
|------|---|
| 워크트리 | `.worktrees/{name}` |
| 브랜치 | `feat/{name}` (base: `main`) |
| 생성일 | YYYY-MM-DD |
| 기간 | YYYY-MM-DD ~ YYYY-MM-DD (N일) |
| 대화 턴 | N턴 |
| 커밋 | N개 (hash_first ~ hash_last) |
| 파일 변경 | N파일, +N줄 / -N줄 |
| PR | #N OPEN/MERGED/없음 |

### 커밋 타임라인

| 날짜 | 커밋 수 | 주요 내용 |
|------|--------|----------|
| MM-DD HH:MM~HH:MM | N | 한 줄 요약 |

---

## §1 현재 상태

### 인프라 (가동 중 / 미배포 / 해당없음)
- 배포 상태, 환경, 핵심 설정

### 코드 (PR #N / 브랜치만)
- 브랜치, 커밋 수, 변경 규모, lint 상태
- 주요 신규/변경 파일 테이블

---

## §2 확정 결정

| # | 결정 | 근거 |
|---|------|------|
| 1 | **결정 한 줄** | 근거 한 줄 |

**DA 승인**: N회 리뷰 요약 (또는 "미실시")

---

## §3 핵심 수치

벤치마크/성능 테이블. **결론만, raw 데이터 금지.**

### 기각된 최적화 (있으면)

| 옵션 | 결과 | 판정 |
|------|------|------|
| 옵션명 | 결과 한 줄 | ✅/❌ |

---

## §4 차단/리스크

### 항목명 (BLOCKED / WARNING / MONITORING)
- 상태 설명
- **다음 단계**: 구체적 행동

---

## §5 남은 작업

| Phase | 내용 | 상태 |
|-------|------|------|
| **1** | 작업 한 줄 | 미착수/진행중/완료 |

실행 순서: `1 → 2 → 3` (병렬이면 `1 → (2∥3) → 4`)

---

## §6 파일 맵 + 명령어

### 주요 경로
(tree 형태, 파일별 역할 한 줄)

### 핵심 명령어
(복붙 가능한 코드블록)
```

### 템플릿 규칙

| 규칙 | 설명 |
|------|------|
| 총 분량 | ≤300줄 (초과 시 §3/§6 먼저 축소) |
| 추측 금지 | 확인된 사실만. 미확인은 §4 차단/리스크로 |
| raw 데이터 금지 | §3에 결론 테이블만. 원본은 소스 파일 경로 참조 |
| 섹션 생략 | 해당 없는 섹션은 `(해당 없음)` 한 줄로 대체. 섹션 자체는 삭제 금지 |
| 증분 업데이트 | 기존 digest 있으면 diff 기반 갱신 (전체 재작성 금지) |

### Step 3: NEXT.md 연결 (선택)

digest 작성 후 `/baton:save` 도 실행한다면, NEXT.md에 digest 포인터 추가:

```
**DIGEST**: docs/digest/{TOPIC}.md (풀 컨텍스트 — 먼저 읽을 것)
```

`baton:resume` 시 NEXT.md에 DIGEST 포인터가 있으면 해당 파일도 Read.

## 주의 / 가드

- **옵션 B**: main/master 브랜치 root에서도 **실행 허용** (digest는 문서 생성이므로 코드 변경 아님)
- **워크트리 전용 아님** — main에서도 과거 워크트리의 digest 작성 가능
- `docs/digest/` 디렉토리 없으면 자동 생성
- 기존 파일 덮어쓰기 전 git diff 확인 (dirty 상태면 경고)

## 참고

- 참조 구현: BYZ-Agents `docs/digest/GPU_STT_TTS.md` (212줄, 12턴 5일 → SSOT 1파일)
- baton:save와 상호보완 — save는 세션 스냅샷, digest는 N세션 종합
- digest는 baton CLI (`bash ~/.baton/current/bin/baton`)에 서브커맨드 없음 — 순수 에이전트 스킬
