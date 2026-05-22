# baton 업그레이드 요청: 세션 종료 시 다음 세션 시작 메시지 자동 생성

## 문제

매 세션 종료(`baton save` / `baton:finish`) 시 CURRENT.md + NEXT.md는 저장되지만, **다음 세션을 열 때 붙여넣을 시작 메시지**가 자동 생성되지 않는다.

사용자가 매번 수동으로 "다음 세션 시작 메시지 만들어줘" / "아이스브레이킹 문구 줘"를 요청하는 패턴이 반복되고 있다.

## 요청 사항

### 1. `baton save` / 세션 종료 시 시작 메시지 자동 생성

`baton save` 또는 `SessionEnd` 훅 실행 시, CURRENT.md + NEXT.md 저장 **후** 자동으로:

1. `.baton/handoff/RESUME_MSG.md` 파일 생성 — 다음 세션에 복사+붙여넣기할 간결한 메시지 (3~5줄)
2. 메시지에 포함할 필수 정보:
   - **워크트리 경로**: `.worktrees/{name}/`
   - **브랜치명**: `feat/xxx`
   - **마지막 커밋 해시 (short)**: `abc1234`
   - **NEXT.md 첫 액션 요약**: 1줄
   - **baton resume 지시**: `NEXT.md 읽고 시작`
3. 생성 후 터미널에 **복사 가능한 형태로 출력**:
   ```
   ═══ 다음 세션 시작 메시지 ═══
   <메시지 내용>
   ═══════════════════════════
   ```

### 2. `baton resume` 시 워크트리 + 해시 검증

`baton resume` 실행 시:

1. `RESUME_MSG.md` (또는 CURRENT.md frontmatter)에 기록된 **워크트리 경로**와 **커밋 해시**를 읽는다
2. 현재 실행 환경의 워크트리 경로 + `git rev-parse --short HEAD`와 비교
3. **일치**: 정상 진행 (기존 동작)
4. **불일치**: 경고 + 확인 절차:
   ```
   ⚠️ 워크트리/해시 불일치 감지
   저장된: .worktrees/v5-phase-c (abc1234)
   현재:   .worktrees/v5-phase-c (def5678)
   
   main에 새 커밋이 있을 수 있습니다. 계속하시겠습니까? [y/n]
   ```
5. 불일치 사유 자동 추론:
   - 해시만 다름 → "main에 새 커밋이 머지됨" 안내
   - 워크트리 다름 → "다른 워크트리에서 실행 중" 경고
   - 둘 다 다름 → "완전히 다른 컨텍스트" 경고 + NEXT.md 내용 표시

### 3. RESUME_MSG.md 예시

```markdown
NEXT.md 읽고 시작. ultragoal G003~G004 이어서.

V4 통역+강의 Cloud Run 정상화 완료 (PTT 2.5s, 강의 confirmed 8개).
이제 E2E 풀 시나리오 검증 + V5 노트테이커 독립 검증 차례.

배포 시 byz-deploy 스킬 참조 (Worker 트래픽 --to-latest 수동 필수).

---
worktree: .worktrees/v5-phase-c
branch: feat/v5-notetaker-polish
commit: 002b9609
```

## 구현 위치

- `baton save` 명령 끝단 (CURRENT.md/NEXT.md 저장 후)
- `SessionEnd` 훅 (동일 위치)
- `baton resume` 명령 시작점 (NEXT.md 읽기 전)

## 기대 효과

- 사용자가 "시작 메시지 만들어줘"를 매번 요청할 필요 없음
- 다른 세션/워크트리에서 실수로 resume하는 것 방지
- main에 새 커밋이 머지된 상태에서 resume 시 인지 가능
