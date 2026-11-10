# r478b — master 단계 (나노 산출 · 실행 0)

발단: 1.1.34 설치 뒤 첫 실제 뉴스 틱(`FT_NEWS_MODE=html` · `FT_NEWS_EFFORT=max`) = `ERROR 지도 만들기 실패 — 발행 0: opencode run 총 마감 70s 초과` (master 113945).

1. 팩 PR: 가지 `nano/r478b-news-html-split-calls`(origin/main 22fb0b6a 위) push → PR → 병합 `--match-head-commit <가지 HEAD 40자>`. ★버전·CHANGES 머리는 master★ — 문안 = 아래 «CHANGES 절».
   파일 = bin·kit 짝(cmp 0) 2: `ft_news_html_render.py` · `ft_news_html.py` + 시험 `tests/scripts/test_ft_news_html.py` + 이 증거.
2. 되돌림 준비: `cp -p <LIVE_BIN>/ft_news_html_render.py{,.bak-r478b}` · `cp -p <LIVE_BIN>/ft_news_html.py{,.bak-r478b}`.
3. 착지 뒤 install → 2 파일 `cmp` 0 · `ft-live-install-check.sh --range …` OK.
4. plist `FT_NEWS_MODE=html` 줄 되돌림 · `FT_NEWS_EFFORT` = 사람 결정값(권장 base · 표 `design/harness/EFFORT-news-html-20261019.md` r478b 절) → 재적재 → 틱 1회 관측: 로그 `ft-news-html: 만듦 … secs=<최대>(top=… goals=… teams=…)` + `ft-news-publish: 발행 완료 ts=…`.

## 원인 (실측 · 같은 라이브 입력 18,591 B)
- pong 4.6초 · 큰 입력 base 30.6/44.4/30.2초 · max 65.6초 / 130초+ → 입력 크기가 아니라 «한 호출에 내용 전부(출력 3~4.4K자) × max 생각 시간».
- 부가: stdin 을 물려받은 실행은 180·240초 동안 step_start 0 → `stdin=/dev/null`.

## 고침 (7초 룰 «쪼갤 수 있으면 쪼갠다»)
- 갈래 3개 병렬: top(요약·중요한 일·근거 ← now·goals·ledger·urgent·commits) · goals(골 6 ← now·goals·ledger) · teams(일하는·쉬는 팀 ← now·teams). 갈래마다 «그 갈래 입력만».
- 시도당 상한 = min(3.5 + 7 × ceil(max(입력 토큰 ÷ 2000, 예상 출력 글자 ÷ 기준 출력량)), 70) — teams 31.5초 · top 38.5초 · goals 45.5초(라이브 입력) · 총 마감 70초(병렬) · 재시도 = 첫 출력 전 실패만 1회.
- 실패 = 어느 갈래든 NewsHtmlError → 발행 0(옛 동작 그대로). build 는 `prompt-{top,goals,teams}.txt` 3장.

## 실측 (분할 뒤 · 같은 입력)
- base 17.9초(top 15.5 · goals 17.8 · teams 14.2) · max 30.5초(30.3 · 21.6 · 24.6) · 둘 다 rc0 · 린트 OK · 남은 opencode run 0.

## 시험
- `bash harness/tests/test_news_html.sh` → 21 passed rc=0 (새 2: 갈래별 입력만·stdin=/dev/null · 상한 크기 비례·70 천장 / 고친 2: 재시도 4·3회 · effort 변형마다 갈래 3).
- 뉴스·매거진 묶음 546 passed / 6 failed — 5건 = main 기준선 같은 «기존 빨강»(r481 묶음) · 1건 `test_magazine_eli5::test_run_cmd_is_7_seconds…` = 부하(load 21)에서 흔들림 · 단독 재실행 1 passed.

## CHANGES 절 (착지 번호를 붙여 머리에)
### <날짜> — 뉴스 HTML 모드 호출 쪼개기: 갈래 3개 병렬 · 크기 비례 상한 · stdin 차단 (r478b · <버전>)
- 첫 실제 틱이 `opencode run 총 마감 70s 초과`(max) — 원인 = 한 호출에 출력 전부(3~4.4K자) × max 생각 시간(실측 65.6초·130초+). 7초 룰대로 top·goals·teams 3갈래를 «그 갈래 입력만» 넣어 병렬 호출 · 시도당 상한 = 크기 비례(≤70) · stdin=/dev/null.
- 실측(같은 입력): base 30~44초 → 17.9초 · max 65.6~130초+ → 30.5초 · 린트 OK.
