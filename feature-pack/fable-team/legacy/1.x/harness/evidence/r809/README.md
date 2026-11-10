# r809 — 뉴스(HTML) 틱 «원장 리포를 먼저 정하고 받기» · 받기 실패면 «판정 불가» 머리 줄

기준판 = 팩 origin/main `73f097b3`. 브랜치 `nano/r809-news-default-repo-fetch-then-unknow`. push 0(집행 = master).

## 무엇을 고쳤나 (닫힌 목록 · 카드 §구현 범위 1~3)

| # | 파일 | 변경 |
|---|---|---|
| 1 | `kit/fable-team/bin/ft_news_ledger.py` `_run` | 리포 정하기(`FT_LEDGER_REPO` or `live_root`)를 **받기 앞**으로 · html 모드면 env 유무와 무관하게 그 리포로 `fetch_if_stale(repo)` · html 아님 = `sync_repo()` 그대로 |
| 2 | `kit/fable-team/bin/ft_news_html.py` | `zero_change_line(now, last, warn)` — warn 있으면 `[뉴스 HH:MM] 판정 불가 — <warn> · 지도 <링크>`, 없으면 지금 그대로 `변화 없음 · 지도 <링크>` |
| 3 | 짝 사본 `harness/bin/ft_news_ledger.py` · `ft_news_html.py` | cmp0(`03-mirror-cmp0.txt`) |
| 4 | `tests/scripts/test_r809_news_default_repo_fetch.py` | 신규 8시험(ⓐ~ⓔ·ⓖ·ⓗ) |

범위 밖(무변경): 경보·경보 상태 파일 · fetch 재시도 규칙 · `FT_NEWS_FETCH_TIMEOUT/BUDGET` · `news_ref` · `check_stale` · 지도 재발행 규칙 · r805 팀별 표.

## 로그

| 파일 | 무엇 |
|---|---|
| `00-red-baseline.txt` | 기준판에서 신규 시험 = ⓐ·ⓑ·ⓖ2 FAIL(3 failed, 5 passed) |
| `01-green-fixed.txt` | 고친 판 = 8 passed |
| `02-existing-news-suite.txt` | `-k "news or News"` = 1 failed 270 passed — FAIL 1칸은 `test_r649_news_team_lines_isolate_error`(7초 상한 문구) |
| `05-r649-baseline.txt` | 같은 1칸이 **기준판에서도 FAIL**(= 이 카드의 변경과 무관 · 카드 ⓕ 가 «같은지 대조만» 이라 적은 그 칸) |
| `03-mirror-cmp0.txt` | kit ↔ harness/bin 2파일 cmp0 + sha256 |
| `04-change.diff` | 코드 diff(시험·증거 제외) |

## 기존 시험 1칸을 고친 이유 (DA 판정 대상)

`tests/scripts/test_ft_news_html.py::test_r503_sync_error_rides_map_head_and_repeat_line` 는 **옛 규격**(`변화 없음 · 지도 … · <warn>` 꼬리)을 단정하고 있었다 — 카드 §구현 범위 2가 그 줄 머리를 «판정 불가 — …» 로 바꾸라고 했으므로 그 단정만 새 규격으로 갱신했다(그 시험의 나머지 단정 = 지도 머리 `FT_NEWS_HEAD` 경로는 그대로 통과).

## 시험 입력 매핑(카드 ⓐ~ⓗ → 실제 시험)

- ⓐ env 없음 + 원격이 1커밋 앞 → 받기 스텁 1회 · 새 판 지도 1장 · «변화 없음» 0 · 기준선 전진 = `test_a_…`
- ⓑ 같은 꼴 + 받기 실패(스텁 rc1 «fatal: offline») → 줄 머리 «판정 불가 — 원장 ref fetch 실패 …» · «변화 없음» 글자 0 · 지도 0 = `test_b_…`
- ⓒ `FT_LEDGER_REPO` 있는 꼴 → 받기 1회 · ⓐ 와 같은 결과 = `test_c_…`
- ⓓ 받기 성공 + 원격 = 로컬 = 기준선 → `변화 없음 · 지도 http://x/0` 그대로 = `test_d_…`
- ⓔ `FT_NEWS_MODE` 없음 → `sync_repo()` 1회 · 받기 스텁 0 = `test_e_…`
- ⓕ 기존 news 계열 = `02`·`05` (r649 1칸은 기준판도 FAIL)
- ⓖ 변이 = `test_g1_…`(받기 0 → ⓐ 단정 FAIL) · `test_g2_…`(«판정 불가» → «변화 없음» 되돌림 → ⓑ 단정 FAIL)
- ⓗ 격리 = 임시 bare 원격·임시 루트·가짜 발행기/지도 생성(실 원격·실 원장·실 슬랙·실 mbox 0) = `test_h_…`

## 남은 것 (나노 소관 밖)

- press 필요: 없음(단위·캡처·기존 로그만 · 라이브 실사건 1 = master 집행: 받기 실패 틱의 슬랙 뉴스 줄 원문이 «판정 불가 — …» 로 시작).
- 설치 cmp0(라이브 `LIVE_BIN` 키트) = master.
