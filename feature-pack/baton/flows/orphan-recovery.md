# G: orphan-recovery

## 시나리오

`.baton/` 디렉토리 구조가 손상됐거나 `session.lock`이 orphan 상태로 남아있어 baton 명령이 정상 작동하지 않는 상황이다. 에이전트 강제 종료, 시스템 크래시, 불완전한 wt-clean 등이 원인이 된다.

`baton doctor`가 문제를 진단하고 자동 복구 가능한 부분은 처리한다. 자동 복구가 안 되면 이 문서의 수동 정리 절차를 따른다.

## 트리거

- `session.lock`이 남아있어 baton 명령 실행 시 "session already active" 오류가 날 때
- `.baton/handoff/` 파일이 손상됐거나 일부 누락됐을 때
- `git worktree list`와 `.baton/` 상태가 불일치할 때
- `phase.json`이 `status: active`인데 워크트리가 존재하지 않을 때
- baton 명령이 아무 응답 없이 hang될 때

## 단계별 시퀀스

```
사용자                    baton                      git/하네스
  │                         │                           │
  │ /baton:doctor            │                           │
  ├────────────────────────▶│                           │
  │                         │ 진단 항목 체크:           │
  │                         │  - session.lock 존재?     │
  │                         │  - lock PID 살아있나?     │
  │                         │  - phase.json 파싱 가능?  │
  │                         │  - handoff/ 4파일 존재?   │
  │                         │  - git worktree 일치?     │
  │                         │  - version.lock 호환?     │
  │                         │  - archive INDEX 무결성?  │
  │                         │                           │
  │                 진단 결과 출력 (항목별 ✓/✗)         │
  │                         │                           │
  │                         │ 자동 복구 가능 항목:      │
  │                         │  - orphan lock → 제거     │
  │                         │  - git worktree 불일치    │
  │                         │    → prune 실행           │
  │                         │                           │
  │                         │ 수동 복구 필요 항목:      │
  │                         │  - phase.json 손상        │
  │                         │  - handoff/ 파일 손상     │
  │                         │  → 수동 절차 안내 출력    │
  │                         │                           │
  │ (수동 복구 절차 수행)    │                           │
  │                         │                           │
  │ /baton:doctor            │                           │
  ├────────────────────────▶│                           │
  │                         │ 재진단 → 모두 ✓ 확인     │
```

## 명령 시퀀스

```bash
# 1단계: 진단
/baton:doctor
# → 항목별 ✓/✗ 출력, 자동 복구 가능 항목 즉시 처리

# 2단계: orphan session.lock 수동 제거 (자동 복구 실패 시)
# lock PID 확인
cat .baton/session.lock
# PID가 살아있지 않으면 제거
kill -0 <PID> 2>/dev/null || rm .baton/session.lock

# 3단계: git worktree 불일치 수동 정리
git worktree list
git worktree prune
# 여전히 불일치면:
git worktree remove --force .worktrees/{broken-name}

# 4단계: phase.json 손상 시
# git history에서 마지막 커밋 버전 복구
git show HEAD:.baton/phase.json > .baton/phase.json.bak
# 내용 확인 후 복원
cp .baton/phase.json.bak .baton/phase.json

# 5단계: handoff/ 파일 손상 시
# → H: handoff-rollback 플로우로 이동

# 6단계: 복구 완료 확인
/baton:doctor
# → 모든 항목 ✓

# 7단계: 정상 작업 재개
/baton:resume
```

## 메모리 흐름

orphan-recovery는 메모리를 생성하는 것이 아니라 기존 메모리를 보존하고 복구하는 것이 목표다.

- **PLAN.md** ← 손상 여부 확인. 손상 시 **H: handoff-rollback**으로 archive에서 복원.
- **JOURNAL.md** ← 손상 여부 확인. 복구 후 "orphan recovery 수행" Turn을 수동 append 권장.
- **CURRENT.md** ← `session.lock` 제거 후 `status`가 `active`면 그대로 사용. 손상 시 직접 편집.
- **NEXT.md** ← 대부분 텍스트 파일이라 손상 드묾. 없으면 빈 파일로 재생성 후 `resume`.

## 진단 항목 상세

| 항목 | 자동 복구 | 수동 필요 |
|------|-----------|-----------|
| orphan session.lock (PID 사망) | O (doctor가 제거) | — |
| git worktree 불일치 | O (prune 실행) | 강제 제거 필요 시 |
| phase.json JSON 파싱 실패 | X | git history 복원 |
| handoff/ 파일 손상 | X | H: handoff-rollback |
| version.lock 호환 범위 초과 | X | baton upgrade 또는 다운그레이드 |
| archive INDEX.jsonl 손상 | X | tar.gz 재스캔으로 재생성 |

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `doctor`가 hang됨 | session.lock이 살아있는 PID를 가짐 | 다른 터미널에서 해당 PID kill 후 재실행 |
| `git worktree remove --force` 실패 | 해당 경로에 uncommitted 변경 | 변경 사항 stash 또는 포기 후 재시도 |
| phase.json 복원 후에도 파싱 실패 | 인코딩 문제 | `file .baton/phase.json`으로 인코딩 확인, UTF-8로 재저장 |
| archive INDEX.jsonl 손상 | 동시 쓰기 충돌 | `ls .baton/archive/*.tar.gz`로 실제 파일 목록 확인 후 INDEX 재생성 |

## 다음 케이스 연계

- handoff/ 파일 손상 확인됨 → **H: handoff-rollback**
- 복구 완료 후 작업 재개 → **A: plan-first** 또는 **B: wt-first**
- 복구 불가능한 phase → **E: abandoned**로 처리 후 새 워크트리 시작

## Don't

- `.baton/` 디렉토리를 통째로 삭제하지 말 것 — archive가 있는지 먼저 확인. `mv .baton/ .baton.bak/`으로 이름 변경 후 진행
- `doctor` 실행 전에 lock 파일을 수동으로 삭제하지 말 것 — PID가 실제로 살아있는 세션일 수 있음
- `git worktree remove --force`를 확인 없이 실행하지 말 것 — uncommitted 변경 사항 유실 위험
- handoff/ 파일이 손상됐을 때 `doctor`만으로 복구하려 하지 말 것 — doctor는 구조 진단만, 내용 복원은 **H: handoff-rollback**
