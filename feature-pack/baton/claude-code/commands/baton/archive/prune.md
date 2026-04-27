---
description: 만료된 archive 항목 정리 (자동 + 수동)
argument-hint: [--dry-run] [--days N]
allowed-tools: Bash
---

# /baton:archive prune

`config.json.archive.retention_days` (기본 30일) 을 초과한 archive 항목을 삭제합니다.
`--dry-run` 으로 삭제 대상을 먼저 확인하고, `--days N` 으로 보존 기간을 임시 변경할 수 있습니다.

## 사용법
```
/baton:archive prune [--dry-run] [--days N]
```

- `--dry-run`: 실제 삭제 없이 삭제 대상 목록만 출력
- `--days N`: 이 명령에 한해 보존 기간 N일로 덮어쓰기 (config 변경 아님)

## 동작
1. `.baton/archive/INDEX.jsonl` 에서 `archived_at` 필드 기준으로 만료 항목 필터링
2. `--dry-run` 시: 삭제 예정 항목 목록 + 총 해제 용량 출력 후 종료
   ```
   [dry-run] 삭제 예정 3개 (총 126KB):
     hotfix-01_20260320_0900  (38일 경과, 8KB)
     test-phase_20260318_1500 (40일 경과, 92KB)
     ...
   ```
3. 실제 실행 시: 대상 tar.gz 삭제 + `INDEX.jsonl` 에서 해당 항목 제거
4. 삭제 완료 요약 출력: "N개 항목 삭제, M KB 해제"
5. `auto_prune.lazy_check_interval_days` 기준 다음 자동 prune 예정일 갱신

## 실행
```bash
bash ~/.baton/current/bin/baton archive prune $ARGUMENTS
```

## 주의 / 가드
- main/master root에서 실행 가능.
- 삭제 전 반드시 `--dry-run` 으로 확인 권장.
- `wt-clean` 시 `config.json.archive.auto_prune.on_wt_clean: true` 이면 자동 호출됨.
- `SessionStart` 훅에서 `lazy_check_interval_days` 주기 도달 시 자동 호출됨.

## 참고
- SPEC Rule 4 (config.json): `archive.retention_days`, `auto_prune` 설정
- 관련 명령: `/baton:archive list`, `/baton:wt-clean`
