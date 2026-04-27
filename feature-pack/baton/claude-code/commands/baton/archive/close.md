---
description: extract로 생성된 /tmp/baton-extracted/<id>/ 임시 폴더 정리
argument-hint: <id>
allowed-tools: Bash
---

# /baton:archive close

`/baton:archive extract` 로 생성된 `/tmp/baton-extracted/<id>/` 임시 폴더를 삭제합니다.
extract 후 열람이 끝나면 이 명령으로 임시 공간을 정리합니다.

## 사용법
```
/baton:archive close <id>
```

- `id`: archive ID (예: `v5-pr-a3_20260427_1430`)

## 동작
1. `/tmp/baton-extracted/<id>/` 경로 존재 여부 확인
2. 경로 존재 시 `rm -rf /tmp/baton-extracted/<id>/` 실행
3. 삭제 완료 메시지 출력:
   ```
   /tmp/baton-extracted/v5-pr-a3_20260427_1430/ 삭제 완료
   ```
4. 경로 미존재 시 "(이미 정리됨 또는 extract 안 됨)" 출력

## 실행
```bash
bash ~/.baton/current/bin/baton archive close $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능.
- `/tmp/baton-extracted/<id>/` 만 삭제. 원본 tar.gz는 보존.
- `id` 인자 없이 실행 시 현재 열려 있는 모든 임시 폴더 목록 표시 후 선택 안내.

## 참고
- 관련 명령: `/baton:archive extract`, `/baton:archive list`
