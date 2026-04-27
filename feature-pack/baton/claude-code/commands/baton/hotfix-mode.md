---
description: main에서 직접 hotfix 작업 (lite mode, 메모리 비활성)
argument-hint: "[finish]"
allowed-tools: Bash
---

# /baton:hotfix-mode

main/master 브랜치에서 직접 작업하는 lite mode. baton의 phase/handoff/메모리 비활성. 종료 시 archive에 `tag:hotfix` 만 남김.

## 사용법
```
/baton:hotfix-mode           # 활성화 안내
/baton:hotfix-mode finish    # 작업 끝 — 가벼운 archive 생성
```

## 동작
1. 현재 위치가 main/master 브랜치 root인지 확인
2. 활성화 시 baton 메모리(handoff/) 비활성 안내만 출력
3. `finish` 인자 시 최근 commit + diff 를 가벼운 tar.gz 로 archive에 추가 (tag:hotfix)
4. Archive INDEX.jsonl 에 메타 1줄 append

## 실행
```bash
bash ~/.baton/current/bin/baton hotfix-mode $ARGUMENTS
```

## 가드
- main/master 브랜치 root에서만 동작 (워크트리에서는 거부)
- 옵션 B의 예외 케이스

## 참고
- [flows/hotfix-mode.md](../../../../flows/hotfix-mode.md) — F 케이스 시나리오
- 일반 phase 작업은 `/baton:wt-create` 사용
