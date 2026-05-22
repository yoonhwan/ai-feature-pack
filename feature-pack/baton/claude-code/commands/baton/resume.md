---
description: NEXT.md를 읽어 이전 세션 컨텍스트를 자동 복원
argument-hint: [--force]
allowed-tools: Bash
---

# /baton:resume (v1.2.5+)

현재 워크트리의 `NEXT.md`를 출력합니다. 워크트리/commit mismatch를 자동 감지해 4분류로 처리하고, archive extract 경로에서는 hard abort합니다.
키워드 `이어서` / `진행` / `go` / `continue` / `next` 입력 시에도 자동으로 이 명령이 실행됩니다.

## 사용법
```
/baton:resume          # 기본
/baton:resume --force  # mismatch 경고 무시 (archive extract는 우회 불가)
```

또는 자연어 키워드:
```
이어서 / 진행 / go / continue / next
```

## 동작
1. **archive extract hard abort** — `$PWD`가 `/tmp/baton-extracted/*` 경로면 즉시 거부 (`--force`로도 우회 불가, 데이터 손실 위험)
2. main/master root 가드 (옵션 B)
3. `CURRENT.md` frontmatter에서 `worktree`, `last_commit` 읽기 — 빈 값(legacy v1.2.4 이하)이면 silent 자동 백필
4. realpath 정규화 (저장값/현재 양쪽 `pwd -P`) + basename 이중 체크
5. **4분류 분기**:
   - `match` — 일치 → 그대로 NEXT.md 출력
   - `commit_only` — 해시만 다름 (main에 새 커밋 머지 등) → INFO + 1초 wait + 자동 진행
   - `worktree_only` — 다른 워크트리 → TTY는 `[y/N]` 확인, non-TTY는 `[baton-resume-mismatch]` info 출력 후 NEXT.md (LLM이 사용자에게 확인)
   - `both` — 둘 다 다름 → 위와 동일
6. `--force` flag로 4분류 mismatch 우회 (archive extract 제외)
7. `.baton/handoff/NEXT.md` 출력 (≤ 1KB, 다음 세션 지시문)

## 실행
```bash
bash ~/.baton/current/bin/baton resume $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부. 워크트리 내부에서만 사용.
- **archive extract 경로(`/tmp/baton-extracted/*`)는 hard abort** — `--force`로도 우회 불가. /baton:wt-create 로 새 워크트리 만들 것.
- `NEXT.md` 없으면 `CURRENT.md` 블로커·핵심 결정 섹션을 대신 출력.
- `SessionStart` 훅이 paused 상태 감지 시 자동으로 resume 알림 출력.
- `commit_only` (해시만 다름)는 block이 아닌 INFO — main 머지 후 워크트리 복귀 등 일반 시나리오 흡수.

## 키워드 트리거 (non-TTY) 동작
non-TTY 환경에서 mismatch 발생 시 `[baton-resume-mismatch] kind=... saved_worktree=... current_worktree=...` 형식의 한 줄을 stdout으로 출력합니다. LLM(adapter)은 이 라인을 받아 사용자에게 진행 여부를 확인해야 합니다.

## 참고
- SPEC Rule 1: NEXT.md 포맷 (≤ 1KB)
- SPEC 어댑터 체크리스트: 키워드 트리거 인식 필수
- Flow A (plan-first): `flows/plan-first.md`
