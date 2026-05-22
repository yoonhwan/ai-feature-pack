---
description: 기존 워크트리를 v1.2.4 sidecar 패턴으로 마이그레이션
argument-hint: [--dry-run] [path?]
allowed-tools: Bash
---

# /baton:migrate (v1.2.4+)

v1.2.2 이하에서 생성된 워크트리의 `.baton/handoff/` 를 v1.2.4 sidecar 패턴으로 비파괴 마이그레이션. 데이터 손실 없음.

## 사용법
```
/baton:migrate              # 모든 .worktrees/* 마이그레이션
/baton:migrate --dry-run    # 변경 미리 보기
/baton:migrate <path>       # 특정 워크트리만
```

## 동작 (워크트리당)
1. 이미 현재 baton 버전과 동일 → skip
2. `.baton/handoff/.events.jsonl` 없으면 빈 파일 생성 (없어도 첫 hook이 자동 생성하지만 명시적 생성)
3. `JOURNAL.md` → `JOURNAL.md.pre-1.2.4.bak` 백업 (1회만, 이미 있으면 skip)
4. **CURRENT.md frontmatter `last_commit` 백필 (v1.2.5+)** — 필드 없으면 `git rev-parse --short HEAD` 로 자동 채움
5. `.baton/version.lock` 갱신:
   - `baton_version: <current>`
   - `migrated_from: <이전 버전>`
   - `migrated_at: <ISO8601>`
6. 결과 요약 출력 (migrated/already_ok/skipped 카운트)

## 실행
```bash
bash ~/.baton/current/bin/baton migrate $ARGUMENTS
```

## 주의
- 비파괴 — 기존 핸드오프 파일 절대 삭제·덮어쓰지 않음
- 누적된 JOURNAL Turn은 그대로 보존 (백업까지 추가 보호)
- `--dry-run` 으로 사전 점검 권장

## 롤백
- `JOURNAL.md.pre-1.2.4.bak` 파일 복원
- `~/.baton/current` 심링크를 이전 버전(예: `versions/1.2.2`)으로 변경

## 참고
- v1.2.4 sidecar 패턴: `/baton:save`
- 신규 워크트리는 마이그레이션 불필요
