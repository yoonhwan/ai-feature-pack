# r478 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r478-news-html-team-map-deepseek-script-` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(457f34fc · r474 착지 뒤) 위. ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(병행 가지 충돌 방지) — 착지 순서대로 master 가 다음 번호. 문안 = 아래 «CHANGES 절».
   파일 = bin·kit 짝(cmp 0) 6: 새 `ft_news_html.py` · 새 `ft_news_html_render.py` · 새 `ft_news_html_lint.py` · 새 `ft-news-effort-test.sh` · `ft_news_ledger.py` · `ft_news_publish.py`
   + 키트 새 틀 `kit/fable-team/templates/news-team-map.html` + hermes 짝 `kit/slack-mirror/magazine_slack.py` + 시험 `tests/scripts/test_ft_news_html.py` · `tests/test_news_html.sh`.
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft_news_ledger.py{,.bak-r478}` · `cp -p <LIVE_BIN>/ft_news_publish.py{,.bak-r478}` · `cp -p ~/.hermes/scripts/magazine_slack.py{,.bak-r478}` (새 파일 4 + 틀 1 은 되돌림 시 삭제).
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>` → 6 파일 + 틀 `cmp <키트> <LIVE>` = 0 ·
   hermes: `kit/slack-mirror/install.sh`(기존 경로) 뒤 `cmp kit/slack-mirror/magazine_slack.py ~/.hermes/scripts/magazine_slack.py` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
   ★순서★: hermes `magazine_slack.py` 를 «먼저» 깐다 — HTML 모드 게시가 `upload_file(..., comment=)` 를 부른다(옛 판 경로는 이 인자를 안 써서 순서 무관 · import 는 HTML 경로 안에서만).
4. plist env(master 손 · 되돌림 = 줄 제거): `com.byz.ft-news-planner` 에 `FT_NEWS_MODE=html` 1줄 + `FT_NEWS_EFFORT=<결정값>` 1줄(결정 전엔 비움 = 변형 없음) → launchctl 재적재.
5. 실사건 1(닫는 증거): 뉴스 틱 1회 → 슬랙 채널 최상위 글 `[뉴스 HH:MM] 팀 지도 — <요약 1줄>` + 요약 2줄 + `NEWS-<날짜>-<HHMM>.html` 첨부 1건 · 출력 줄 `ft-news-publish: 발행 완료 ts=<ts> …` (ts 기록) · 첫 HTML 은 desk 로(오빠 확인).
   변화 0 틱 = 30분마다 `[뉴스 HH:MM] 변화 없음 · 지도 <직전 지도 링크>` 한 줄만(`FT_NEWS_REPEAT_MIN`) · 하루 첫 틱은 변화 없어도 지도 1장.
6. effort 표: BYZ `design/harness/EFFORT-news-html-20261019.md`(나노 실측 2변형 · 사람 점수 칸 비어 있음) → desk/오빠 점수 + 기본값 1줄 → 4 의 `FT_NEWS_EFFORT`.
7. 뒤 일(arch 손 · 착지 뒤): `COMM-GUIDE-BOOT.md` 4 «뉴스·매거진 첫머리 골 표» 문장에 «HTML 모드는 골 6행이 지도 안 · 슬랙 한 줄은 고정 문구» 1줄 · `design/harness/README.md` 뉴스 절 1줄.

## 동작 요약 (카드 §구현 범위 대조)
- 1 `ft_news_html.py build|run|publish` + `tick()`: 입력 묶음 = 골 표 6행(ft_goal_table 정본+원장 상태 칸) · 원장 절(«오빠 할 일»·«팀 작업»·«드러난 문제»·«체크리스트» + «**지금» 줄 · 절 2500자·합 9000자) · 24시간 안 [긴급 쪽지 머리 5 · 팀 줄(보드 스냅샷 = ft_news_status 와 같은 원천 · 없으면 «원천 없음» 그대로) · main 커밋 15줄(기준선 이후) · 시크릿 꼴 «[가림]».
  `run` = `opencode run --standalone --model opencode/deepseek-v4.1-flash-free[#<FT_NEWS_EFFORT>] --format json <프롬프트>` · 총 마감 70초(시간 초과 = 프로세스 묶음 kill) · 첫 출력 전 실패만 재시도 1 · JSON 아님·필수 키·골 6 아님 = rc1(파일·발행 0).
- 2 `ft_news_ledger._run`: `FT_NEWS_MODE=html` 일 때만 `return tick(...)`(알림 notify 뒤) · 그 밖 = 옛 판 경로 그대로(줄 추가 4 · 기존 시험 그대로 통과).
- 3 `ft_news_publish.publish_html`: 글 1개 = `files.completeUploadExternal(initial_comment=…)`(채널 최상위 · 스레드 0) · 그날 같은 글 있으면 채택 · 첨부 실패 = 글만 + «(지도 HTML 미첨부 — 다음 틱 재시도)» + rc3 + `state/news-publish/pending-attach.json` → 다음 틱 `retry_attach` 가 그 글 스레드에 첨부(최상위 글엔 나중에 파일을 붙일 수 없어서). `publish_line` = 변화 없음 한 줄. 고정 문구 = `html_post_text`(`FT_NEWS_HEAD` · 기본 «팀 지도») 한 곳.
- 4 `ft_news_html_lint.py`: 절 5 · 중요한 일 1~7 · 골 6 · 본문 번호(#숫자·판정 N·sha 꼴)는 `<p class="foot">` 에만 · 요약 1~3줄·≤600B · 시크릿 꼴 0 → OK / `LINT …` rc3(발행 0).
- 5 `ft-news-effort-test.sh --variants … --input … [--table]`: 변형마다 run 1회 → 표(걸린 초·rc·린트·중요한 일 수·요약 B·사람 점수 칸) + `<표>-files/<순번>/` 산출 · `base` = 변형 없음 · `depth:<문장>` = 프롬프트 깊이(FT_NEWS_DEPTH).

## 편차·범위 밖 (나노 판단 · 근거)
- ① 새 파일 1 더(`ft_news_html_render.py` · 프롬프트·호출·파싱·틀 주입): 한 파일이면 370줄 — 파일 길이 한도 때문에 나눴다.
- ② 팀 줄 원천 = `ft-board.py collect` 를 틱마다 돌리지 않고 «보드 스냅샷»(collect dict 를 ft-sheet-publish 가 남긴 것)을 읽는다 — collect 실측 60초+ (이 좌석 실측 `teams`·`collect` 둘 다 120초 안에 안 끝남 · ft_news_status 머리 주석 «40~60 s · 7초 룰»).
- ③ 지도 실패 연속 호출 방지: 실패 뒤 `FT_NEWS_RETRY_MIN`(기본 5분) 동안 다시 안 부른다(60초 틱마다 70초 호출이 이어지지 않게) — 사유 `지도 만들기 실패(재시도 대기)` 는 정지 감시에 그대로 보인다.
- ④ HTML 모드에선 옛 경로의 planner 요약 쪽지(maybe_send)·골 표 문(goal_gate)을 부르지 않는다 — 골 6행은 린트가 지도 안에서 검사.
- ⑤ 기준본 자체는 린트에 1건 걸린다(«일하는 팀» 칸 `#78`) — 린트 규칙이 맞고 기준본이 번호 규칙을 어긴 것.
- ⑥ 변형 이름 유효성: `opencode run --model …#max` 가 rc0 · 린트 OK 로 끝났지만 opencode 가 모르는 변형을 거절하는지는 실측 0(실호출 상한 3회 · `opencode models --verbose` rc1) — 기본값 정할 때 desk 가 `#bogus` 1회로 확인 권장.
- 범위 밖(카드 7): 매거진 · 보드 시트 · 원장 내용 품질 · TUI 좌석(r476) · 채널·토큰.

## 시험
- `bash harness/tests/test_news_html.sh` → 19 passed rc=0 (ⓐ build·원천 없음 2 · ⓑ 인자·틀 2 · ⓒ 실패 6 · ⓓ 린트 2 · ⓔ 게시·미첨부·틱 4 · ⓕ 1 · ⓖ 1 · ⓗ 1).
- 기존 뉴스·매거진·게시 시험 묶음(test_ft_news*·test_*magazine*·test_*thread_post*·test_news*) → 545 passed / 5 failed / 1 skipped —
  ★5건은 origin/main(457f34fc) 에서도 같은 5건 실패(이 가지 변경 무관 · 기준선 실측)★: test_ft_tick_passes_shellcheck · test_repo_original_finds_kit_folder · test_real_ledger_rows_sum_and_nothing_lost · test_h1_tick_calls_stale_watch_when_ledger_off · test_attach_uploads_files_into_root_thread_and_prints_first_link → 고침 단위 따로 필요(master 판단).
- py_compile 6 · bash -n 2 · ruff 0 · 짝 cmp 0 6.
- 실 opencode 3회(무료 · /tmp 밖 scratch): 스모크 30.0초 · effort base 21.7초 · max 22.4초 — 셋 다 rc0 · 린트 OK · 남은 opencode 프로세스 전후 4=4(기존 serve).

## CHANGES 절 (착지 번호를 붙여 머리에)
### <버전> — r478 뉴스 HTML 모드: 팀 지도 HTML + 한 줄 (오빠 확정 10-19 19:3x)
- `FT_NEWS_MODE=html` 이면 뉴스 틱이 원장·골 표·보드 스냅샷·[긴급] 머리·main 커밋을 묶어 `opencode run --standalone`(딥식 무료 · 70초 총 마감)에 넘기고, 내용 JSON 을 고정 틀(`templates/news-team-map.html` · 기준본과 같은 CSS·절)에 넣어 HTML 을 만든 뒤 린트 통과분만 슬랙 최상위 글 «[뉴스 HH:MM] 팀 지도 — 요약» + HTML 첨부로 올린다. 변화 0 = 30분마다 한 줄 · 하루 첫 틱 = 지도.
- 새: `ft_news_html.py` · `ft_news_html_render.py` · `ft_news_html_lint.py` · `ft-news-effort-test.sh` · 틀 1 · `magazine_slack.upload_file(thread_ts=None, comment=)`.
- 모드 없음 = 옛 판 경로 그대로 · 되돌림 = plist env 줄 제거.
