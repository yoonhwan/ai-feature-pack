---
description: 현재 phase 상태 + 활성 워크트리 목록 + 마지막 하네스 출력
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:status

프로젝트 전체의 활성 워크트리 목록, 각 phase 상태, 포트 할당 현황, 마지막으로 사용한 하네스를 한눈에 보여줍니다.
main/master root에서도 실행 가능한 전역 조회 명령입니다.

## 사용법
```
/baton:status
```

## 동작
1. `.worktrees/` 하위 디렉토리를 스캔하여 활성 워크트리 목록 수집
2. 각 워크트리의 `.baton/handoff/CURRENT.md` frontmatter 파싱:
   - `phase`, `status`, `agent`, `last_updated`, `last_harness` 출력
3. `phase.json` 의 `completion_criteria` 달성률 계산 + 출력
4. `.worktree-info.json` 기반 포트 할당 현황 테이블 출력
5. `session.lock` 존재하는 워크트리는 "실행 중" 표시

출력 예시:
```
워크트리          phase        status   agent         마지막 하네스
─────────────────────────────────────────────────────────────
.worktrees/v5-a3  v5-pr-a3   active   claude-code   superpowers:writing-plans
.worktrees/hotfix hotfix-01  paused   codex         -
```

## 실행
```bash
bash ~/.baton/current/bin/baton status $ARGUMENTS
```

## 주의 / 가드
- main/master root에서도 실행 가능 (전역 조회 허용).
- `CURRENT.md` 파싱 실패한 워크트리는 `(손상)` 표시 + `baton doctor` 실행 안내.

## 참고
- SPEC Rule 3: 옵션 B 허용 목록 (status는 main에서 허용)
- 관련 명령: `/baton:doctor`, `/baton:archive list`
