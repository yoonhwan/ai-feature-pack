# r478e — master 단계 (나노 산출 · 실행 0)

발단: 첫 자동 틱 실패 — top 갈래(요약+중요한 일+근거)가 max · load 25 에서 38.5초 상한 초과(master#80 114436).

1. 팩 PR: 가지 `nano/r478e-news-split-top`(origin/main 3ca1e15f · 1.1.39 위) push → PR → 병합 `--match-head-commit`. 버전·CHANGES 머리는 master.
   파일 = bin·kit 짝(cmp 0) 1: `ft_news_html_render.py` + 시험 + 이 증거.
2. 되돌림 준비: `cp -p <LIVE_BIN>/ft_news_html_render.py{,.bak-r478e}`.
3. 착지 뒤 install → cmp 0 → ★plist `FT_NEWS_EFFORT=high` 권장(아래 실측 · max 는 30초 목표 못 맞춤)★ → 틱 1회 관측 `secs=<최대>(summary=… important=… goals=… teams=…)`.

## 고침
- ① top → 2갈래 병렬: `summary`(요약 + 근거 refs ← now·facts·goals·ledger·urgent·commits · 예상 출력 700자) · `important`(중요한 일 1~7 ← now·facts·goals·ledger·urgent · 1000자). facts 규칙은 두 갈래 모두. 갈래 4개(summary·important·goals·teams) · 상한 크기 비례(≤70) 그대로 — 라이브 입력 상한 summary 24.5 · important 31.5 · goals 45.5 · teams 31.5초.
- ② 시도당 상한 초과 = «첫 출력 전 실패»(opencode 는 답 글을 끝에 한 번에 준다) → 총 마감 70초 안에서 재시도 1회(전엔 초과 = 바로 실패). 출력이 시작된 뒤 실패는 그대로 재시도 0.

## 실측 (같은 라이브 입력 `input.json` 21:5x · 갈래별 초)
| 변형 | load | 결과 | 최대 갈래 | summary / important / goals / teams |
|---|---|---|---|---|
| max | 21 | 실패(summary 24.5초 초과 · 재시도 전 판) | - | - |
| max | 24 | OK 린트 OK | 22.2 | 17.0 / 22.2 / 19.1 / 17.0 |
| max | 19 | 실패(important 31.5초 × 2 초과) | - | - |
| max | 25 | OK(재시도로) 린트 OK | 62.0 | 11.3 / 62.0 / 21.2 / 20.8 |
| max | 15 | OK 린트 OK | 43.2 | 35.9 / 43.2 / 36.9 / 17.9 |
| high | 18 | OK | 26.4 | 10.5 / 14.3 / 26.4 / 16.5 |
| high | 50 | OK | 20.9 | 12.4 / 20.9 / 14.3 / 14.4 |
| base | 41 | OK | 27.9 | 12.4 / 19.7 / 27.9 / 15.0 |
| base | 47 | OK | 29.2 | 22.5 / 15.1 / 29.2 / 11.6 |

- 결론: 쪼개도 max 는 «생각 시간»이 출력 크기와 무관하게 갈래당 30~60초로 흔들려 30초 목표·상한을 못 맞춘다(5회 중 실패 2 · 성공 3 중 2회가 30초 초과). high·base 는 부하 18~50 에서 최대 갈래 20.9~29.2초 · 4회 전부 성공.
- 권장: `FT_NEWS_EFFORT=high`(최대 갈래 20.9~26.4초 · master 실측 top 19.0초와 같은 결) — 기본값 결정은 사람 1줄.
- 남은 opencode run 0(매 회 확인).

## 시험
- `bash harness/tests/test_news_html.sh` → 28 passed rc=0 (기존 26 유지 + 새 2: 한 갈래만 부하 지연 → 상한 초과 → 전체 발행 0 / 상한 초과 = 첫 출력 전 실패 → 총 마감 안 재시도 1 · 고친 칸: 갈래 수 4 · 재시도 5·4회 · effort 변형마다 4 호출).

## CHANGES 절
### <날짜> — 뉴스 HTML 요약 갈래 쪼개기 · 상한 초과 재시도 1 (r478e · <버전>)
- 첫 자동 틱 실패(top 갈래 max · load 25 에서 38.5초 초과) — 요약+근거 / 중요한 일 2갈래로 나눠 4갈래 병렬 · 시도당 상한 초과는 첫 출력 전 실패로 보고 총 마감 70초 안 재시도 1.
- 실측: max 는 쪼개도 갈래당 30~60초로 흔들림(5회 중 실패 2) · high 최대 갈래 20.9~26.4초 · base 27.9~29.2초 → 기본 변형 high 권장.
