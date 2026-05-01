---
description: 페이즈 완료 처리 (save 자동 호출 후 status=done)
argument-hint: [--skip-save]
allowed-tools: Bash
---

# /baton:finish (v1.2.4+)

페이즈를 완료(`done`) 상태로 처리합니다. `events_count > 0` 이면 `/baton:save` 를 자동 호출해 컨텍스트를 먼저 정리합니다.

## 사용법
```
/baton:finish              # 정상 동작 (events 있으면 save 후 status=done)
/baton:finish --skip-save  # save 우회 (events.jsonl 그대로 보존)
```

## 동작
1. main/master root 가드 (옵션 B)
2. `events_count > 0` 이면 `baton_cmd_save` 자동 호출
   - LLM spawn → JOURNAL/CURRENT/NEXT 정리
   - `--skip-save`로 우회 가능
3. CURRENT.md frontmatter `status: done`
4. tmux attach hint 출력
5. 다음 단계 안내 (verify, PR, wt-clean)

## 실행
```bash
bash ~/.baton/current/bin/baton finish $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: 워크트리 안에서만 사용
- `finish` 는 워크트리를 삭제하지 않음 — `/baton:wt-clean` 이 담당
- PR 생성 전에 실행 권장 (PR 머지 후 `wt-clean --merged` 패턴)
- 이중 save 방지: events_count = 0 이면 save spawn skip

## 참고
- 다음 단계: `/baton:wt-clean`
- 자동 정리: `/baton:save` 패턴 따름
