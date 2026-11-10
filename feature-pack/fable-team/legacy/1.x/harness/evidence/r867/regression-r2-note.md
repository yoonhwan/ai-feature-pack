# r867 r2 회귀 메모 (HEAD = origin/main 병합 뒤 · 같은 HEAD 한 세트)
- 카드 시험: pytest-card-r2.txt — 44 passed rc=0 (r2 3칸 + r1 41)
- 넓은 시험(-k "magazine or news or ledger"): pytest-magazine-news-ledger-r2.txt — 731 passed · 3 failed
- 실패 3 = r1 때와 같은 기존 결함(regression-failures-note.md): test_disk_census · test_nano_spawn_rollback · test_r649_news_team_lines_isolate_error
  - 셋 다 이번에 바꾼 모듈(magazine_celebrate · magazine_celebrate_eli5 · magazine_guide_check · magazine_doc)을 import 하지 않음(grep 0)
- r1 의 부하 흔들림 1(test_magazine_eli5 7초) 은 이번 회차 통과
- 변이: mutation-r2.txt — 3건 각 그 시험 빨강
