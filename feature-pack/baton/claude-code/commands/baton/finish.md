---
description: 페이즈 완료 처리 후 wt-clean 제안
argument-hint: (없음)
allowed-tools: Bash
---

# /baton:finish

현재 phase를 `done` 상태로 완료 처리합니다.
`CURRENT.md` status를 `done`으로 설정하고, `phase.json` 의 현재 세션 status도 갱신합니다.
완료 후 `/baton:wt-clean` 실행 여부를 사용자에게 제안합니다.

## 사용법
```
/baton:finish
```

## 동작
1. 현재 브랜치가 main/master root인지 확인 — 워크트리 밖이면 거부 (옵션 B 가드)
2. `phase.json` completion_criteria 체크 — 미충족 항목 있으면 경고 출력 후 진행 확인
3. `CURRENT.md` frontmatter 갱신:
   - `status: done`
   - `last_updated: <현재 ISO8601>`
4. `phase.json` 현재 세션 status → `done`, `duration_min` 계산하여 기록
5. `JOURNAL.md` 에 완료 Turn 항목 추가
6. `session.lock` 해제
7. `/baton:wt-clean` 실행 권장 메시지 출력 (yes/no 선택)

## 실행
```bash
bash ~/.baton/current/bin/baton finish $ARGUMENTS
```

## 주의 / 가드
- **옵션 B**: main/master 브랜치 root에서 실행 시 거부. 워크트리 내부에서만 사용.
- `finish` 는 워크트리를 삭제하지 않음. 정리는 `wt-clean` 이 담당.
- PR 생성 전에 실행 권장 (PR 머지 후 `wt-clean --merged` 패턴).

## 참고
- Flow C (wt-finish): `flows/wt-finish.md`
- SPEC Rule 2: phase.json sessions 스키마
- 다음 단계: `/baton:wt-clean`
