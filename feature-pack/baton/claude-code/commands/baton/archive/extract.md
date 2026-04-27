---
description: archive를 /tmp/baton-extracted/<id>/ 로 압축 해제
argument-hint: <id>
allowed-tools: Bash
---

# /baton:archive extract

특정 archive ID를 `/tmp/baton-extracted/<id>/` 디렉토리로 압축 해제합니다.
handoff 파일(PLAN.md, JOURNAL.md, CURRENT.md, NEXT.md) 전체를 열람하거나 내용을 복원할 때 사용합니다.

## 사용법
```
/baton:archive extract <id>
```

- `id`: archive ID (예: `v5-pr-a3_20260427_1430`)

## 동작
1. `INDEX.jsonl` 에서 해당 ID 항목 및 tar.gz 경로 확인
2. `/tmp/baton-extracted/<id>/` 디렉토리 생성
3. `tar -xzf <id>.tar.gz -C /tmp/baton-extracted/<id>/` 실행
4. 압축 해제된 파일 목록 출력:
   ```
   /tmp/baton-extracted/v5-pr-a3_20260427_1430/
   ├── PLAN.md       (8.2KB)
   ├── JOURNAL.md    (21.4KB)
   ├── CURRENT.md    (1.1KB)
   └── NEXT.md       (0.8KB)
   ```
5. 임시 폴더 정리 방법 안내: `/baton:archive close <id>`

## 실행
```bash
bash ~/.baton/current/bin/baton archive extract $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능 (조회 전용).
- 동일 ID가 이미 `/tmp/baton-extracted/` 에 존재하면 덮어쓸지 확인.
- `/tmp/` 는 재시작 시 초기화됨. 영구 보존 필요 시 수동 복사 권장.

## 참고
- 관련 명령: `/baton:archive show`, `/baton:archive close`
- SPEC Rule 1: 4-template 핸드오프 파일 포맷
