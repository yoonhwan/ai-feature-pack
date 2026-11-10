# r867 r3 회귀 메모 (HEAD 54fd025e · 팩 origin/main 뒤처짐 0 · 같은 HEAD 한 세트)
- 카드 시험: pytest-card-r3.txt — 48 passed rc=0 (r3 4칸 + r2 3 + r1 41)
- 넓은 시험(-k "magazine or news or ledger"): pytest-magazine-news-ledger-r3.txt — 735 passed · 3 failed
- 실패 3 = r1·r2 와 같은 기존 결함(test_disk_census · test_nano_spawn_rollback · test_r649_news_team_lines_isolate_error) · 바꾼 모듈 import 0
- 변이: mutation-r3.txt — sha 판정→작업명 비교 = ⓑ 빨강 · 전체 상한 제거 = ⓐ 빨강
- 실 원장 collect 드라이런(외부 호출 0): dryrun-collect-r3.txt — 10-25 창 48건(카드) · 원장 축하 0(근거 sha 행 2 · 둘 다 창 밖)
