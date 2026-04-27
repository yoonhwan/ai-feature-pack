---
description: 최근 30일 archive 목록 조회 (현재 프로젝트 또는 전역)
argument-hint: [--days N] [--global]
allowed-tools: Bash
---

# /baton:archive list

현재 프로젝트의 `.baton/archive/INDEX.jsonl` 을 파싱하여 archive 목록을 출력합니다.
`--global` 플래그 시 홈 디렉토리 이하 모든 프로젝트의 archive를 통합 조회합니다.

## 사용법
```
/baton:archive list [--days N] [--global]
```

- `--days N`: 최근 N일 이내 항목만 표시 (기본값: 30)
- `--global`: 전역 조회 (모든 프로젝트의 `.baton/archive/` 통합)

## 동작
1. `--global` 없으면 현재 프로젝트 `.baton/archive/INDEX.jsonl` 읽기
2. `--global` 이면 `find ~ -name "INDEX.jsonl" -path "*/.baton/archive/*"` 로 전체 수집
3. `--days N` 기준으로 `archived_at` 필터링
4. 결과를 테이블 형식 출력:
   ```
   ID                        phase       status  archived_at          크기
   ────────────────────────────────────────────────────────────────────
   v5-pr-a3_20260427_1430   v5-pr-a3   done    2026-04-27 14:30     42KB
   hotfix-01_20260426_0900  hotfix-01  done    2026-04-26 09:00     8KB
   ```
5. 만료 예정(retention_days 내) 항목은 `(D-3)` 형식으로 경고 표시

## 실행
```bash
bash ~/.baton/current/bin/baton archive list $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능 (조회 전용).
- `INDEX.jsonl` 없는 프로젝트는 "(archive 없음)" 출력.

## 참고
- SPEC Rule 3: `.baton/archive/INDEX.jsonl` 위치
- 관련 명령: `/baton:archive search`, `/baton:archive prune`
