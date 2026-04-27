---
description: 특정 archive ID의 메타 정보 및 handoff 파일 미리보기
argument-hint: <id>
allowed-tools: Bash
---

# /baton:archive show

특정 archive ID의 `INDEX.jsonl` 메타 정보와 `CURRENT.md` / `NEXT.md` 미리보기를 출력합니다.
전체 내용이 필요하면 `/baton:archive extract` 로 압축을 풀어서 확인합니다.

## 사용법
```
/baton:archive show <id>
```

- `id`: archive ID (예: `v5-pr-a3_20260427_1430`)

## 동작
1. `INDEX.jsonl` 에서 해당 ID 항목 파싱 — 메타 출력:
   ```
   ID:          v5-pr-a3_20260427_1430
   phase:       v5-pr-a3
   branch:      feat/v5-pr-a3
   agent:       claude-code
   status:      done
   archived_at: 2026-04-27 14:30
   크기:         42KB
   하네스:       superpowers:writing-plans
   ```
2. tar.gz 에서 `CURRENT.md` streaming 추출 → 블로커 / 핵심 결정 / 핵심 파일 섹션 미리보기
3. `NEXT.md` 전문 출력 (≤ 1KB)
4. 포함 파일 목록: `tar -tzf <id>.tar.gz` 출력

## 실행
```bash
bash ~/.baton/current/bin/baton archive show $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능 (조회 전용).
- ID 미존재 시 "해당 archive를 찾을 수 없음" 출력 + `archive list` 안내.

## 참고
- 관련 명령: `/baton:archive list`, `/baton:archive extract`
- SPEC Rule 1: CURRENT.md / NEXT.md 포맷
