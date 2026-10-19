# r478c — master 단계 (나노 산출 · 실행 0)

발단: 오빠 반려 «다시 만들어 왜 일하는 세션 찻봇같은거는 아래에 쉬는쩍에 있냐» (master#80 발주 114239 · desk 실측: chatbot tmux 좌석 라이브인데 «쉬는 팀» 에).

1. 팩 PR: 가지 `nano/r478c-news-teams-live-order`(origin/main 36a43b06 · 1.1.37 위) push → PR → 병합 `--match-head-commit <가지 HEAD 40자>`. 버전·CHANGES 머리는 master — 문안 = 아래.
   파일 = bin·kit 짝(cmp 0) 2: `ft_news_html.py` · `ft_news_html_render.py` + 시험 `tests/scripts/test_ft_news_html.py` + 이 증거(HTML 1장 포함).
2. 되돌림 준비: `cp -p <LIVE_BIN>/ft_news_html.py{,.bak-r478c}` · `cp -p <LIVE_BIN>/ft_news_html_render.py{,.bak-r478c}`.
3. 착지 뒤 install → 2 파일 cmp 0 → 뉴스 틱 1회 관측: HTML 에서 `<h2>일하는 팀</h2>` 줄 < 쉬는 팀 줄 · 일하는 팀 칸 첫머리 `일하는 좌석 N/M`.

## 원인 (어디서 틀렸나)
- 일하는/쉬는 팀 판정을 «LLM» 이 했다 — 입력은 보드 스냅샷 줄(`• chatbot — 일함 2 · …`)이었고 스냅샷(21:18)은 chatbot 일함 2 로 맞았는데 LLM 이 쉬는 쪽에 넣었다. 스냅샷 명부에는 나노 좌석도 빠져 있었다(chatbot 3석만 · 실제 tmux 나노 2석 더).
- 템플릿 순서는 원래 일하는 팀 → 쉬는 팀(절 머리 순서는 맞음) — 문제는 «어느 칸에 넣나» 였다.

## 고침
- `ft_news_html.live_teams(root)`: 팀 = 명부 `seats-<팀>.json`(+ `seats.json` = v65) · 좌석 = `tmux ls` 세션 중 `byz-<팀>-`·`ft-<팀>-` 로 시작 · 일하는 좌석 = `ft-seat-status.sh turn <좌석> --no-reported` 첫 칸 WORKING(병렬 8 · 각 7초 · 실패 = «확인 불가» 로 셈). 입력 묶음 `live` 칸.
- `ft_news_html_render.bucket`: 일하는 팀 = 일하는 좌석 ≥1 · 일하는 좌석 많은 순 → 위 · 나머지 = 쉬는 팀 → 아래. 칸 글 = `일하는 좌석 N/M · <설명>` / `라이브 좌석 M · 일하는 좌석 0 · <설명>` (확인 불가 있으면 표시).
- LLM(teams 갈래)은 `team_notes`(팀별 설명 한 문장)만 낸다 — 일함/쉼 판정·좌석 수는 안 쓴다. live 없음 = NewsHtmlError(발행 0).
- 옛 이름 계보(byz-concierge-*) 세션은 명부에 없는 팀이라 어느 팀에도 안 섞인다.

## 실측 (라이브 입력 · 2026-10-19 21:26)
- build 14초(좌석 turn 36석) · run 34.0초(top 34.0 · goals 11.9 · teams 19.9) · 린트 OK.
- live: chatbot 2/5 · harness 2/6 · loom 2/4 · cfo 1/3 · ops 1/3 일함 · feature·graphics·issues·kk·lecture·planner·room·v65 일함 0.
- `evidence/r478c/NEWS-20261019-2126.html`: `<h2>일하는 팀</h2>` 186행 · chatbot 188행(맨 위) · `<h2>쉬는 팀</h2>` 195행 · 쉬는 팀 197~204행.

## 시험
- `bash harness/tests/test_news_html.sh` → 24 passed rc=0 (새 3: 라이브 좌석 기준 일하는 팀이 위·쉬는 팀에 없음·LLM 판정 버림 / live 없음 = 발행 0 / tmux·turn 실측 집계(옛 이름 안 섞임 · seats.json=v65 · 확인 불가 셈)).

## CHANGES 절
### <날짜> — 뉴스 HTML «일하는 팀» = 라이브 좌석 실측 · 일하는 팀이 위 (r478c · <버전>)
- 오빠 반려(일하는 chatbot 이 쉬는 팀에) — 일하는/쉬는 팀 판정을 LLM 에서 코드로: 명부 팀별 tmux 좌석 + `ft-seat-status.sh turn` WORKING 수로 나누고 일하는 좌석 많은 순으로 위에 · LLM 은 팀별 설명 한 문장만.
