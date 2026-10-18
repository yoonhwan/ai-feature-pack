# C4 산출 — 회귀 출력 (읽기 전용 시험 · `unset GH_TOKEN` · gh issue edit/close/label 실행 0)

골좌표: 하네스 GOAL 표 A(이상 1건 = Issue 1건 · 검토) — 랜딩↔Issue 연결(Closes)·close 검사를 기계로.

| 시험 | 입력 | exit | 결과 |
|---|---|---|---|
| `bash -n` | check · reopen | 0 | OK |
| 매핑 누락 라벨 | `gh label list` 72개 ↔ ISSUE-TRANSITIONS.md | — | 누락 0 / 총 72 |
| check · 5항 있음 | fixture `closed-with-5items.json`(CLOSED) | **0** | `PASS #9001 완료 5항 + Closes 연결` |
| check · 5항 없음 | fixture `closed-without-5items.json`(CLOSED) | **1** | 5항 중 4 MISS(자리표시 `<적을 것>` 은 미기재 취급) · Closes 연결 MISS |
| check · 실 닫힌 Issue | #810(CLOSED · PR #817 연결) | **1** | 5항 5개 MISS · `OK Closes 연결 PR #817` — 5항 코멘트 관행이 아직 없어서 |
| check · 실 열린 Issue | #827(OPEN) | **1** | 5항 5 MISS · Closes 연결 MISS |
| check · usage | `abc` | 2 | usage |
| reopen dry-run | `810 HEAD` | 0 | `gh issue reopen / edit / comment` 3줄만 출력(실행 0) |
| reopen · 없는 sha | `810 deadbeef0000` | 2 | sha 검증 실패 |

참고: 「5항 있음」 exit 0 은 실제 닫힌 Issue 중 5항 코멘트를 단 건이 아직 없어 fixture 로 시험했다.
