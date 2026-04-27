# H: handoff-rollback

## 시나리오

`.baton/handoff/` 내 파일(PLAN.md, JOURNAL.md, CURRENT.md, NEXT.md)이 손상되거나 실수로 삭제된 상황이다. handoff 파일은 `.gitignore`에 포함되어 git history로는 복원이 불가능하다. 대신 baton이 `wt-clean`·`save`·`PreCompact` 시점에 자동 생성한 archive tar.gz에서 복원한다.

손상 원인은 에디터 충돌, 디스크 오류, 불완전한 sed/awk 처리, 잘못된 수동 편집 등 다양하다. archive가 최근 상태를 보존하고 있다면 대부분 복원 가능하다.

## 트리거

- `resume` 시 "NEXT.md not found" 또는 "CURRENT.md parse error" 오류가 날 때
- handoff/ 파일이 비어있거나 frontmatter가 깨져있을 때
- `baton save` 실행 시 JOURNAL.md append 실패 오류가 날 때
- `baton doctor`가 "handoff/ 파일 손상" 항목을 ✗로 표시할 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ /baton:doctor            │                           │
  ├────────────────────────▶│                           │
  │                         │ handoff/ 파일 상태 진단   │
  │                         │ → 손상 항목 ✗ 표시        │
  │                         │ → archive 검색 제안 출력  │
  │                         │                           │
  │ /baton:archive list      │                           │
  ├────────────────────────▶│                           │
  │                         │ INDEX.jsonl 파싱          │
  │                         │ 최근 30일 archive 목록    │
  │                         │ 출력 (phase_id, 날짜, 상태)│
  │                         │                           │
  │ /baton:archive show {id} │                           │
  ├────────────────────────▶│                           │
  │                         │ tar.gz 내부 목록 + 메타   │
  │                         │ 출력 (파일 크기, 날짜)    │
  │                         │                           │
  │ /baton:archive extract {id}│                         │
  ├────────────────────────▶│                           │
  │                         │ /tmp/baton-extract/{id}/  │
  │                         │ 로 압축 해제              │
  │                         │                           │
  │ (추출 내용 확인)         │                           │
  │                         │                           │
  │ (복원할 파일 선택 복사)  │                           │
  ├─────────────────────────────────────────────────────▶│
  │                         │                           │ cp 실행
  │                         │                           │
  │ /baton:archive close {id}│                           │
  ├────────────────────────▶│                           │
  │                         │ /tmp/baton-extract/{id}/  │
  │                         │ 정리                      │
  │                         │                           │
  │ /baton:doctor            │                           │
  ├────────────────────────▶│                           │
  │                         │ 재진단 → 모두 ✓ 확인     │
  │                         │                           │
  │ /baton:resume            │                           │
  ├────────────────────────▶│                           │
  │                         │ NEXT.md 출력              │
  │                         │ 작업 재개 가능            │
```

## 명령 시퀀스

```bash
# 1단계: 진단으로 손상 확인
/baton:doctor
# → "handoff/CURRENT.md: parse error" 등 확인

# 2단계: archive 목록 확인 (이 phase의 최신 archive 탐색)
/baton:archive list
/baton:archive search v5-pr-a3
# → archive ID 확인

# 3단계: archive 내용 미리 보기
/baton:archive show v5-pr-a3_20260427_1430
# → 포함 파일 목록, 각 파일 크기 출력

# 4단계: 임시 폴더로 압축 해제
/baton:archive extract v5-pr-a3_20260427_1430
# → /tmp/baton-extract/v5-pr-a3_20260427_1430/ 생성

# 5단계: 내용 확인
ls /tmp/baton-extract/v5-pr-a3_20260427_1430/handoff/
cat /tmp/baton-extract/v5-pr-a3_20260427_1430/handoff/CURRENT.md

# 6단계: 손상된 파일만 선택 복원
# 전체 복원:
cp /tmp/baton-extract/v5-pr-a3_20260427_1430/handoff/* \
   .worktrees/v5-pr-a3/.baton/handoff/

# 특정 파일만 복원 (예: CURRENT.md만 손상):
cp /tmp/baton-extract/v5-pr-a3_20260427_1430/handoff/CURRENT.md \
   .worktrees/v5-pr-a3/.baton/handoff/CURRENT.md

# 7단계: 임시 폴더 정리
/baton:archive close v5-pr-a3_20260427_1430

# 8단계: 복구 확인
/baton:doctor
# → 모든 항목 ✓

# 9단계: 작업 재개
cd .worktrees/v5-pr-a3
/baton:resume
```

## 메모리 흐름

rollback은 기존 메모리를 archive에서 복원하는 것이 목표다. 복원 후 JOURNAL.md에 복구 이력을 수동 append하는 것을 권장한다.

- **PLAN.md** ← archive에서 복원. 복원 후 "rollback from archive {id}" 한 줄 append 권장.
- **JOURNAL.md** ← archive에서 복원. 복원 후 다음 Turn을 수동 추가:
  ```markdown
  ## 2026-04-27 15:00 — Rollback Turn
  **INTENT**: handoff-rollback 수행
  **ACTIONS**: archive {id}에서 handoff/ 파일 복원
  **TODO**: 복원 후 작업 상태 재확인
  ```
- **CURRENT.md** ← archive에서 복원 후 `last_updated`를 현재 시각으로 수동 갱신. `status`가 `done`이나 `abandoned`로 복원됐다면 `active`로 변경.
- **NEXT.md** ← archive에서 복원. 내용이 오래됐다면 현재 상황에 맞게 수동 수정.

## archive가 없을 때 수동 재생성

archive가 전혀 없거나 너무 오래된 경우 handoff 파일을 최소 수준으로 재생성한다:

```bash
# CURRENT.md 최소 재생성
cat > .baton/handoff/CURRENT.md << 'EOF'
---
session_id: 2026-04-27_1500
phase: v5-pr-a3
branch: feat/v5-pr-a3
worktree: .worktrees/v5-pr-a3
agent: claude-code
status: active
started_at: 2026-04-27T14:00:00Z
last_updated: 2026-04-27T15:00:00Z
last_harness: null
---

## ⚠️ 블로커
handoff-rollback으로 수동 재생성. 이전 상태 불명.

## 📌 핵심 결정
- archive 복원 불가로 수동 재생성

## 🔗 핵심 파일
- .baton/phase.json
EOF

# NEXT.md 최소 재생성
echo "이전 handoff 손상으로 복구됨. git log로 최근 작업 확인 후 진행." \
  > .baton/handoff/NEXT.md

# JOURNAL.md 최소 재생성
cat > .baton/handoff/JOURNAL.md << 'EOF'
# Journal — v5-pr-a3

## 2026-04-27 15:00 — Recovery Turn
**INTENT**: handoff-rollback 수동 재생성
**HARNESS**: 없음
**ACTIONS**: archive 복원 실패, 최소 파일 수동 생성
**TODO**: git log로 최근 작업 확인
EOF
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `archive list`에 해당 phase가 없음 | wt-clean 전 손상 발생 | git stash 확인 또는 수동 최소 재생성 |
| `archive extract` 후 파일이 비어있음 | tar.gz 생성 시 이미 손상됨 | 더 오래된 archive ID로 재시도 |
| `archive extract` 권한 오류 | /tmp 접근 불가 | `TMPDIR` 환경변수로 다른 경로 지정 |
| 복원 후에도 `doctor` ✗ | CURRENT.md frontmatter 형식 불일치 | frontmatter 필수 필드(session_id, phase, branch, worktree, agent, status) 확인 |
| JOURNAL.md append 후 baton이 못 읽음 | 인코딩 문제 | `file` 명령으로 UTF-8 확인, `iconv`로 변환 |

## 다음 케이스 연계

- 복원 완료 후 작업 재개 → `resume` 후 기존 케이스(A 또는 B) 계속
- archive 자체가 없어 복원 불가 → 수동 최소 재생성 후 **B: wt-first**처럼 진행
- `.baton/` 구조 전체 손상 → **G: orphan-recovery** 먼저 수행
- 복원보다 포기가 나을 때 → **E: abandoned**
