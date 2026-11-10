# r490 — master 단계 (나노 산출 · 실행 0)

발단: 22:04 뉴스(load 25~31) chatbot 5석 turn 전부 7초 초과 «?» → `facts`·`bucket` 이 일하는 0 인 팀을 «쉬는 팀» 으로 발행(오빠 «챗봇팀은 왜쉬어?» · master 80 114787).

1. 팩 PR: 가지 `nano/r490-news-html-unknown-turn-is-not-resti`(origin/main 86257c17 · 1.1.44 위) push → PR → 병합. 버전·CHANGES 머리 번호는 master(r489 와 겹치면 재번호).
   파일 = bin·kit 짝(cmp 0) 3 `ft_news_html.py` · `ft_news_html_lint.py` · `ft_news_html_render.py` + 틀 `kit/fable-team/templates/news-team-map.html` + 시험 + 이 증거.
   ★카드 «설치: 키트 3» 에 render 1 이 더해짐 — 3분류 bucket·`{{UNKNOWN}}` 렌더가 render 에 있다(카드는 ft_news_html.py 로 적음).★
2. 되돌림 준비: `for f in ft_news_html.py ft_news_html_lint.py ft_news_html_render.py; do cp -p <LIVE_BIN>/$f{,.bak-r490}; done` · `cp -p <LIVE_BIN>/../templates/news-team-map.html{,.bak-r490}`.
3. 착지 뒤 `install.sh --apply --project <루트>` → LIVE_BIN cmp 0 4(py 3 + 틀 1) · plist 재시작 0(틱이 매번 새로 부름).
4. 실사건(자동 틱 1회): HTML 경로 + `/tmp/byz-ft-news-planner.log:줄` — «확인 불가» 칸이 비거나(정상 부하) 있으면 그 팀이 «쉬는 팀» 에 없음 + 요약에 그 팀 «쉼» 문장 0.
   ★선행 막힘(범위 밖 · master 114854): opencode 무료 모델이 지금 이 IP 에서 403 FreeTierError — 해소 전엔 틱이 «지도 만들기 실패» 로 끝나 실사건 관측 불가.★

## 고침
- ① `_turn` = 첫 출력 전 실패(시간 초과·rc≠0) 재시도 1 · 반환 `(state, reason)` · 시간 초과는 `start_new_session` + `killpg`(손자가 파이프를 쥐어도 상한 안 · render `_once` 와 같은 꼴) · 합계 ≤ 2×SEAT_S.
- ② 풀 = `max(1, min(좌석 수, SEAT_POOL=32))` — 지금 라이브 좌석 ≈ 33 → 거의 한 번에.
- ③ 팀 dict `unknown_reason`(«turn 시간 초과 N석 · 실패 M석») · `facts` 3분류 {일하는 팀 · 확인 불가 · 쉬는 팀 · 자율} · 프롬프트 FACT_RULES 에 «확인 불가 팀은 쉬는 팀이 아니다» 1줄.
- ④ render `bucket` 3분류 + `{{UNKNOWN}}`(`<div class="team unk">` · 사유 칸) · 틀 H2 «확인 불가»(일하는 팀 ↔ 골 6개) + chip `c-unk` · 블록 비면 H2 만.
- ⑤ 린트 H2 5개(«절 6 아님») · `unknown_problems` = «확인 불가» 블록 팀 이름(경계 `(?<![\w-])…(?![\w-])`) + 같은 문장에 쉬|멈|정지|대기 = 위반.

## 시험 (test-run.txt)
- `test_news_html.sh` 32 passed(기존 28 + r490 ⓐ~ⓓ) · 옛 판 RED 4.
- 카드 «시험 입력» 과 다른 점: ⓐⓑ 는 SEAT_S 7→2 · 느린 좌석 9→5초(비율 유지 · 시험 시간) · ⓑ 는 a-3(rc 1)도 그대로 두어 a = 확인 불가 3(«turn 시간 초과 2석 · 실패 1석») · 가짜 tmux ls = `_sessions` 바꿔치기 · ⓓ = 40석 × 1초 ≤ 2×SEAT_S(풀 8 이면 5회전 ≥ 5초).
- effort 1회: 실 opencode = 403(위) · 같은 live 입력 + 가짜 opencode = lint OK.
- 한계: 린트 이름 대조는 팀 영문 이름(chatbot)만 — 요약이 «챗봇팀은 쉼» 처럼 한글 별칭을 쓰면 못 잡는다(프롬프트 규칙이 막음).

press 필요: 없음.
