---
description: 현재 작업 상태를 handoff 파일에 즉시 저장
argument-hint: [--skip-spawn]
allowed-tools: Bash
---

# /baton:save (v1.2.4+)

`.baton/handoff/.events.jsonl` (sidecar)를 헤드리스 에이전트가 JOURNAL.md / CURRENT.md / NEXT.md 로 일괄 정리합니다. Claude Edit tool과의 mtime race를 회피하기 위한 핵심 명령.

## 사용법
```
/baton:save              # 정상 동작 (LLM spawn으로 정리)
/baton:save --skip-spawn # 메타데이터만 갱신 (긴급 상황)
```

## 동작 (race-free pipeline)
1. main/master root 가드 (옵션 B): 워크트리 안에서만 허용
2. CURRENT.md frontmatter `status: paused`, `last_updated` 갱신
3. `.events.jsonl` 비어 있으면 즉시 종료 (메타데이터만 갱신)
4. **save lock 획득** (`mkdir .save.lock` atomic) — 동시 save 방지, 최대 30s 대기
5. **선 rotate snapshot**: `.events.jsonl` → `.events.snapshot-{ts}_{pid}_{rnd}.jsonl` (atomic mv)
   - 새 hook 이벤트는 새 `.events.jsonl`에 적재 → 다음 save가 처리 (race 차단)
6. 헤드리스 에이전트 spawn (BATON_SKIP_HOOKS=1):
   - claude `--dangerously-skip-permissions`
   - codex `exec --ephemeral`
   - gemini `--yolo`
   - opencode `run --pure`
7. spawn에 snapshot 경로 입력 → JOURNAL/CURRENT/NEXT 정리
8. 결과 분기:
   - **성공**: snapshot → `.events.processed-*.jsonl`
   - **fallback 성공**: jq raw dump → `.events.processed-*.jsonl`
   - **fallback 실패**: snapshot → `.events.failed-*.jsonl` (raw 보존)
9. lock 해제

## 환경변수
- `BATON_SAVE_AGENT=claude|codex|gemini|opencode` — spawn 강제 지정
- `BATON_SAVE_LOCK_TIMEOUT=30` — lock 대기 시간(초)
- `BATON_SKIP_HOOKS=1` — baton hook 자가 차단 (헤드리스 spawn 시 자동 설정)

## 실행
```bash
bash ~/.baton/current/bin/baton save $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부
- 동시 `/baton:save` 호출은 lock으로 직렬화됨
- spawn 중 사용자 다른 hook(omc/gas-town 등)이 핸드오프 파일을 mutate하면 race 재발 가능 — 가능하면 그 hook도 BATON 핸드오프 파일 회피하도록 설정

## 참고
- SPEC: race-free sidecar pipeline (1.2.4)
- 자동 호출: `/baton:finish`, `/baton:wt-clean` (events_count > 0 시)
- 마이그레이션: `/baton:migrate` (v1.2.2 이하 워크트리에서)
