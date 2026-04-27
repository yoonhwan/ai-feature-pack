---
description: NEXT.md를 읽어 이전 세션 컨텍스트를 자동 복원
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:resume

현재 워크트리의 `NEXT.md`를 출력하고 `CURRENT.md` 상태를 `active`로 전환합니다.
키워드 `이어서` / `진행` / `go` / `continue` / `next` 입력 시에도 자동으로 이 명령이 실행됩니다.

## 사용법
```
/baton:resume
```

또는 자연어 키워드:
```
이어서 / 진행 / go / continue / next
```

## 동작
1. 현재 브랜치가 main/master root인지 확인 — 워크트리 밖이면 거부 (옵션 B 가드)
2. `.baton/handoff/NEXT.md` 내용을 출력 (≤ 1KB, 다음 세션 지시문)
3. `CURRENT.md` frontmatter 갱신:
   - `status: active`
   - `agent: claude-code`
   - `last_updated: <현재 ISO8601>`
4. `JOURNAL.md` 에 새 Turn 항목 추가 (`INTENT`: 세션 재개)
5. `session.lock` 발급
6. 환경 검증 — 심볼릭 링크 유효성, 포트 충돌 없는지 확인

## 실행
```bash
bash ~/.baton/current/bin/baton resume $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부. 워크트리 내부에서만 사용.
- `NEXT.md` 없으면 `CURRENT.md` 블로커·핵심 결정 섹션을 대신 출력.
- `SessionStart` 훅이 paused 상태 감지 시 자동으로 resume 알림 출력.

## 참고
- SPEC Rule 1: NEXT.md 포맷 (≤ 1KB)
- SPEC 어댑터 체크리스트: 키워드 트리거 인식 필수
- Flow A (plan-first): `flows/plan-first.md`
