# r899 r6 — restore 줄 대응표 (반송서 REWORK-r899-r6 의사 코드 ↔ ft_team_move_cleanup.py 함수 본문)

대상: `feature-pack/fable-team/harness/bin/ft_team_move_cleanup.py` (키트 사본 cmp0) · 세트 = 이 커밋

| 의사 코드 줄 | 구현 줄 | 내용 |
|---|---|---|
| `orig = read_bytes(보관본 경로)` · 없음 → ERROR rc1 | 357–361 (`restore_one`) | `Path(m["kept"]).read_bytes()` 실패(KeyError·OSError) → `ERROR … 보관본 없음` · rc1 |
| `if sha(orig) != 항목.b1_sha` → ERROR 손상 rc1 | 362–364 | `ERROR … 보관본 손상` · rc1 |
| `cur = read_bytes(대상) 또는 «없음»` | 365–368 | FileNotFoundError → `cur=None` |
| `kind == NCB` · `cur 없음 → O_EXCL 로 orig 새로 씀 → RESTORED` | 369–371 → 332–350 (`put_new`) | tmp 에 보관본 바이트·fsync·mode → `os.link(tmp, 대상)`(없을 때만 · 덮어쓰기 0) · FileExistsError → SKIP `바뀜 — 다시 실행` rc1 |
| `cur == orig → SKIP «이미 원본»` | 372–374 | rc0 |
| `그 밖 → SKIP «또 바뀜» rc1` | 375–376 | |
| `sha(cur) == 항목.new_sha → CAS 교체(B2 = cur · 바이트 = orig 그대로)` | 378–386 (`cas_replace(p, orig, cs)` 380) | 쓰는 바이트 = 보관본 바이트 · JSON 파싱·재생성 0 |
| `sha(cur) == 항목.b1_sha → SKIP «교체 안 됨»` | 387–389 | rc0 |
| `그 밖 → SKIP «또 바뀜» rc1` | 390–391 | |
| 보관본은 pending «전» 저장 · sha 기록 · b1 과 다르면 그 파일 교체 0 | 176–185 (`save_kept`) · 262–268 (`run_file`) | 쓰고 fsync 하고 다시 읽어 sha == b1_sha 확인 · 실패 = `보관본 저장 실패 — 교체 0` |
| 하나라도 ERROR·«또 바뀜» 이면 rc1 | 394–420 (`cmd_restore`) | `casfail or fail` → `return 1` · 옛 형식(files 칸 없음)은 ERROR rc1 |
| 행 지문·new_row_sha 판정은 restore 에서 삭제 | `restore_file`·`restore_ncb` 삭제 · `compute` 의 `new_row_sha` 칸 삭제 | `row_sha` 는 run 쪽 계획 검증(`run_file` 238)에만 남음 |

## 시험 ↔ 반례

| 반례 | 시험 | 변이(빨강) |
|---|---|---|
| ① 원본 대신 JSON 재생성 → 바이트 다름 | ⓡ 4칸 들여쓰기·sort_keys·\u 이스케이프 명부 → run → done 기록 실패 → restore → 바이트 동일 | 변이10: restore 가 `dump_like` 로 재생성해 씀 |
| ② 교체 안 된 pending 을 행 지문으로 되살려 남의 수정을 덮음 | ⓢ B2 불일치(교체 0) → 남이 행 수정 → restore SKIP «또 바뀜» rc1 · 바이트 그대로 / ⓖ4 | 변이4: «교체 전만 아니면 되살림» |
| ③ 보관본 없음·손상을 rc0 성공 처리 | ⓣ replace·move 둘 다: 없음 = ERROR rc1 · 손상 = ERROR rc1 · 대상 그대로 | 변이13: sha 검사 끔 · 변이14: 없음을 조용한 rc0 |
