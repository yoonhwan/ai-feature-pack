---
description: 워크트리 생성 + 포트 할당 + 심볼릭 링크 + 메모리 초기화
argument-hint: <name>
allowed-tools: Bash
---

# /baton:wt-create

새 git worktree를 생성하고, 포트를 자동 할당하며, `.env`/`.venv`/`.claude`/`.omc` 등 심볼릭 링크를 설정합니다.
`.baton/handoff/` 4-template 파일도 초기화하여 바로 작업을 시작할 수 있는 상태로 준비합니다.

## 사용법
```
/baton:wt-create <name>
```

## 동작
1. `git worktree add .worktrees/<name> <branch>` 실행 (브랜치 없으면 신규 생성)
2. `config.json.worktree_port_offset` 기반으로 포트 자동 계산 — `.worktree-info.json.index`에 기록
3. `config.json.shared_links` 목록의 파일/폴더를 심볼릭 링크로 연결 (`.env`, `.venv`, `.claude`, `.omc` 등)
4. `.baton/handoff/` 디렉토리 생성 + PLAN.md / JOURNAL.md / CURRENT.md / NEXT.md 초기화
5. `CURRENT.md` frontmatter에 `status: active`, `agent: claude-code`, `worktree`, `branch` 기록
6. 생성 완료 후 `cd .worktrees/<name>` 안내 및 다음 단계(`/baton:plan`) 출력

## 실행
```bash
bash ~/.baton/current/bin/baton wt-create $ARGUMENTS
```

## 주의 / 가드
- main/master에서도 `wt-create` 자체는 허용 (포트 할당 + 심링만 수행).
- 워크트리 생성 후 `cd .worktrees/<name>` 없이 다른 baton 명령(`save`, `resume`, `finish`) 실행 시 옵션 B 가드로 거부됨.
- 포트 충돌 시 자동으로 다음 index를 찾아 재할당.

## 참고
- SPEC Rule 3: 워크트리 위치 + 포트 할당 (Rule 4)
- Flow B (wt-first): `flows/wt-first.md`
- 심볼릭 링크 대상: `config.json.shared_links`
