---
description: 현재 작업 상태를 handoff 파일에 즉시 저장
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:save

현재 세션의 작업 상태를 `CURRENT.md`에 즉시 dump합니다.
`status`를 `paused`로 설정하고 `last_updated`를 갱신하여 다음 세션(또는 다른 에이전트)이 이어받을 수 있도록 핸드오프 스냅샷을 만듭니다.

## 사용법
```
/baton:save
```

## 동작
1. 현재 브랜치가 main/master root인지 확인 — 워크트리 밖이면 거부 (옵션 B 가드)
2. `CURRENT.md` frontmatter 갱신:
   - `status: paused`
   - `last_updated: <현재 ISO8601>`
   - `last_harness: <가장 최근 사용 하네스>`
3. `CURRENT.md` 본문(블로커, 핵심 결정, 핵심 파일) 최신 상태로 갱신
4. `NEXT.md` 를 다음 세션 첫 입력으로 사용할 1KB 이내 자연어 지시문으로 갱신
5. `session.lock` 해제

## 실행
```bash
bash ~/.baton/current/bin/baton save $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부. 워크트리 내부에서만 사용.
- `save`는 작업을 중단시키지 않음. 언제든 중간 저장 가능.
- `PreCompact` / `SessionEnd` 훅이 자동으로 호출하는 명령이기도 함.

## 참고
- SPEC Rule 1: CURRENT.md / NEXT.md 포맷
- 훅 연동: `hooks/pre-compact.sh`, `hooks/session-end.sh`
- Flow C (wt-finish): `flows/wt-finish.md`
