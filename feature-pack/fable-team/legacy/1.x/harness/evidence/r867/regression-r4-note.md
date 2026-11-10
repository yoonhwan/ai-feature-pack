# r867 r4 회귀 메모 (HEAD = 팩 origin/main 병합 4f6c2e67 위 · 같은 HEAD 한 세트)
- 카드 시험: pytest-card-r4.txt — 47 passed rc=0 (r3 원장 칸 2개 → «원장 행만 완료 → 축하 0 · 안내 1줄» 1개로 바꿈)
- 넓은 시험(-k "magazine or news or ledger"): pytest-magazine-news-ledger-r4.txt — 744 passed · 3 failed
- 실패 3 = r1~r3 와 같은 기존 결함(test_disk_census · test_nano_spawn_rollback · test_r649_news_team_lines_isolate_error) · 바꾼 모듈 import 0
- 변이: mutation-r4.txt — r3 원장 갈래 되살림 → r4 원장 칸 시험 빨강
- 실 원장 드라이런(외부 호출 0): dryrun-collect-r4.txt
