# r478d — master 단계 (나노 산출 · 실행 0)

발단: ①desk 실측(r478c HTML NEWS-20261019-2126) 요약 2줄째 «모든 팀은 작업을 멈추고 대기 중이며 사장님의 재개 지시와 합치기 승인 한 줄을 기다립니다» = 거짓(일하는 팀 5) — master#80 114286
②오빠 2차 반려 «아직 챗본이 아래에 텍스트만있는데» — 일하는 팀이 골 카드처럼 위로 안 올라옴 — master#80 114299.

1. 팩 PR: 가지 `nano/r478d-news-summary-follows-live`(origin/main 1bc45eb2 · 1.1.38 위) push → PR → 병합 `--match-head-commit`. 버전·CHANGES 머리는 master — 문안 = 아래.
   파일 = bin·kit 짝(cmp 0) 3: `ft_news_html.py` · `ft_news_html_render.py` · `ft_news_html_lint.py` + 키트 틀 `templates/news-team-map.html` + 시험 + 이 증거(HTML 1장).
2. 되돌림 준비: 위 3 파일 + 틀 `cp -p … {,.bak-r478d}`.
3. 착지 뒤 install → cmp 0 → 뉴스 틱 1회 관측: `<h2>일하는 팀</h2>` 가 `<h2>골 6개</h2>` 위 · 일하는 팀 카드(`<section class="goal work">`) 수 = live 판정 · 각주 `자율 ON|OFF|모름`.

## 고침
- ① 프롬프트(top 갈래)에 `facts` = {일하는 팀[좌석 많은 순], 쉬는 팀, 자율} — 코드 실측 사실 · «facts 가 이긴다» · 일하는 팀 ≥1 이면 «모든 팀 멈춤·대기·쉼» 금지.
- ② 자율 = `ft-autonomy.sh mode`(on|off → ON·OFF · 위변조·실패·시간 초과 7초 = 모름) · 프롬프트: ON 이면 «사장님 승인을 기다린다» 금지 · 모름이면 승인·자율 이야기 금지 · 각주에 «자율 X».
- 린트 `fact_problems`: 일하는 팀 카드 ≥1 ∧ 요약·중요한 일에 «모든/전체 팀…멈·정지·대기·쉬» · «전 팀이/은 …» · «팀이 모두/전부 …» = `LINT 일하는 팀 N개인데 «…» 문장` · 각주 자율 ≠ OFF ∧ «승인…기다·대기» = `LINT 자율 X 인데 «…» 문장` (rc3 = 발행 0). «전팀 지침…» 같은 조사 없는 제목은 제외.
- ④ 일하는 팀 = 골 카드와 같은 그림 카드(`<section class="goal work">` · 사람 셋 그림 · `일하는 좌석 N/M` = 코드 · 설명 한 문장 = LLM)를 «골 6개» 바로 위 `<h2>일하는 팀</h2>` 절에. 쉬는 팀은 맨 아래 목록 그대로. 일하는 팀 0 = «지금 일하는 좌석 0» 한 줄.
  절 순서 = 중요한 일 → 일하는 팀 → 골 6개 → 쉬는 팀(린트 H2 순서 갱신). CSS 1줄 추가 `.work .track{grid-template-columns:1fr}`.

## 실측 (라이브 입력 · 2026-10-19 21:35 · 자율 실측 OFF)
- facts: 일하는 팀 harness·v65·cfo·chatbot·loom · 쉬는 팀 8 · 자율 OFF.
- run 22.6초(top 22.6 · goals 15.9 · teams 14.0) · 린트 OK.
- `evidence/r478d/NEWS-20261019-2135.html`: `<h2>일하는 팀</h2>` 107행 · 카드 harness 112 · v65 122 · cfo 132 · chatbot 142 · loom 152 → `<h2>골 6개</h2>` 159행 → `<h2>쉬는 팀</h2>` 239행.
- 요약: «일하는 팀은 다섯 — 하네스·통역·결제·챗봇·지식검색. 쉬는 팀은 여덟.» · «모든 팀 멈춤» 류 0 · 승인 문장 1(자율 OFF 실측이라 사실 · 린트 통과).
- 참고: 발주문은 «자율 ON» 이라 했지만 21:3x 실측 `ft-autonomy.sh status` = `[자율 OFF]` — 코드는 매 틱 실측값을 쓴다.

## 시험
- `bash harness/tests/test_news_html.sh` → 26 passed rc=0 (새 2: 린트 REJECT(거짓 문장 원문 · 전 팀 · 자율 ON/모름/OFF · 일하는 팀 0 · 제목 오탐 0) / 프롬프트에 facts·각주 자율·ft-autonomy 없음=모름 · 고친 1: 일하는 팀 카드가 골 위 · 쉬는 팀 아래).

## CHANGES 절
### <날짜> — 뉴스 HTML: 일하는 팀 = 골 위 그림 카드 · 요약이 코드 판정(일하는 팀·자율)을 따른다 (r478d · <버전>)
- 오빠 2차 반려(«챗봇이 아래에 텍스트만») — 일하는 팀(라이브 좌석 실측)을 골 카드와 같은 그림 카드로 «골 6개» 위에 · 쉬는 팀은 맨 아래 목록.
- desk 실측 거짓 요약(«모든 팀 멈춤 · 승인 기다림») — 프롬프트에 코드 판정 facts(일하는/쉬는 팀 · `ft-autonomy.sh mode`) · 린트가 «일하는 팀 ≥1 인데 모두 멈춤» · «자율 OFF 아닌데 승인 기다림» 을 발행 0 으로 막는다.
