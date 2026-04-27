---
description: archive 메타 및 tar 내용에서 키워드 검색
argument-hint: <query> [--global]
allowed-tools: Bash
---

# /baton:archive search

archive `INDEX.jsonl` 메타데이터와 tar.gz 내부 파일 내용(streaming grep)을 모두 검색합니다.
phase-id, title, 블로커, 핵심 결정, 코드 내용 등 어떤 키워드도 검색 가능합니다.

## 사용법
```
/baton:archive search <query> [--global]
```

- `query`: 검색할 키워드 (공백 포함 시 따옴표)
- `--global`: 전역 검색 (모든 프로젝트의 archive 통합)

## 동작
1. `INDEX.jsonl` 에서 `phase_id`, `title`, `tags`, `branch` 필드 대상 키워드 매칭 (1차 빠른 검색)
2. 1차 매칭 미결과 또는 `--deep` 옵션 시: `tar -tzf *.tar.gz | grep` + `tar -xOf` streaming으로 파일 내용 grep
3. 매칭된 항목 출력:
   ```
   [ID] v5-pr-a3_20260427_1430
   phase: v5-pr-a3 | 매칭: JOURNAL.md:42 — "STT 4-layer defense"
   ```
4. 여러 항목 매칭 시 최신순 정렬
5. 결과 없으면 "일치하는 archive 없음" 출력

## 실행
```bash
bash ~/.baton/current/bin/baton archive search $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능 (조회 전용).
- tar streaming grep은 대용량 archive에서 느릴 수 있음 — 1차 메타 검색으로 충분한 경우 활용.
- `--global` 시 검색 대상이 많아 시간이 걸릴 수 있음.

## 참고
- 관련 명령: `/baton:archive list`, `/baton:archive show`
