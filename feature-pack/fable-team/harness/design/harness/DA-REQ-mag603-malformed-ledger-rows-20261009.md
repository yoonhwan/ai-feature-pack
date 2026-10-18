# DA 요청 — 판정 603 매거진 원장 형식 미달 행 보고 모드 (arch#23 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · ★오늘 호 미발행 — 급함★)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 커밋 `74ab10e7a2516d7dbb9fecdf76dc28e8ebf16d5b`(브랜치 `nano/mag603-malformed-ledger-rows-report` · base `60ed7677dd`). 변경: `scripts/harness-install/slack-mirror/magazine_collect_open.py`(`_requests(report)` · 새 `_parse`·`_cells` · `_request(cells)` · `collect_open` → `malformed_requests`) · `magazine_card_shape.py`(+`request_report_line`·`requests_warning_line`·`bad_lines`) · `magazine_render_full.py`(`OPEN_KEYS`+`malformed_requests` · 목차 뒤 줄 2개 · `_appendix` 앞 h3 2개) · `byz_morning_magazine.py`(`Made.malformed = bad_lines(model)`) · 새 `tests/scripts/test_magazine_collect_open.py`(L1~L5) · `tests/scripts/test_magazine_malformed_render.py`(+행).
- 카드 `design/teams/harness/indices/진행/mag603-malformed-ledger-rows-report.md`(설계 닫힌 목록 1~4 · 판정 602 opt-in 의 직접 확장).

## arch#23 독립 재현 (git archive 새 mktemp)
- collect_open·malformed_render·collect_detail·render_full·collect_mbox **58 passed** · `tests/harness/test_magazine_plist.sh` ALL PASS · `test_magazine_install_list.sh` ALL PASS · ruff clean.
- `tests/scripts -k magazine` 13 failed = base `60ed7677dd` 와 FAILED 목록 diff 0(192 → 200 passed).
- ★실데이터 전체 dry-run★(키트 사본 `byz_morning_magazine.py --date 2026-10-09 --dry-run` · env `report` · 실제 리포·mailbox·LLM 요약·PDF · 게시·push·상태 0 — `report_failure` 는 dry-run 에서 게시 0 확인): **rc=0** · PDF 537쪽 · stderr `형식 미달 카드` 13줄 + `형식 미달 요청 행` 22줄 · md 목차 뒤 16·18행에 두 경고 줄 · 부록 h3 「형식 미달 카드 13장」·「형식 미달 요청 행 22개」 · 뿌리 글에 두 줄 별 줄(R38~R59). 그 밖 stderr = 쉬운 판 `AI 풀이 생략` ERROR 18줄(기존 기능의 보이는 경고 · 이 단위 무관).

## 질문 (bounded · 새 요구 금지)
- **Q1 opt-in 없을 때 동작 불변**: env 없음 → 열 수 ≠ 7 행에서 기존과 같은 문구로 raise · 빈 문자열·오타 → raise · 원장 blob 읽기 실패 처리(다음 ref → 모두 실패면 raise)는 모드와 무관하게 그대로.
- **Q2 조용한 누락 0**: `report` 에서 형식 미달 행마다 stderr ERROR 1줄 + 첫 화면·뿌리 글·부록 세 곳에 id 전부 — 빠지는 경로가 있는가(예: id 칸이 빈 행 · 끝 빈 칸 정리 뒤 7열이 되는 행 · 닫힘 행).
- **Q3 정상 출력 불변**: 형식 미달 행 0 이면 requests·render_full·root_text·appendix 바이트 불변 · 7열 행의 닫힘 제외·text 규칙이 기존과 같다(`_request` 분리 포함).
- 범위 밖: 기존 13 실패 · REQUEST-LEDGER 내용 · 쉬운 판 AI 풀이 생략 · Slack 게시·홈 설치·plist(master).

## 판정문
`design/teams/harness/DA-mag603-malformed-ledger-rows-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD · 끝 줄 APPROVE 또는 HOLD.

## r2 (DA r1 HOLD Q2 반송 → 정정 · Q2 만)
- 고정 `dbcb4d6c5061c25aac586c8c4b171bd8cfae949e`(같은 브랜치 · `74ab10e7a2` 위 1커밋 · `scripts/harness-install/slack-mirror/magazine_collect_open.py` `_parse` 전 줄 순회 + `_is_data_row`·`_flag` · 시험 L6 2건).
- arch#23 재현(mktemp): 관련 60 passed · plist·install_list ALL PASS · ruff clean · `-k magazine` 13 failed = base `60ed7677dd` FAILED diff 0(202 passed).
- 실데이터(읽기 전용 · report): requests 35 · malformed_requests 22 · `(빈 ID)` 0 — 오늘 호 출력은 r1 과 같다.
- 프로브: `|  | a | 요지 | 상태 |` → `(빈 ID) 줄 1`·4열 · `|---|:--|`·`| # | x |` → 0.
- ★arch 명시 제한★: 칸이 전부 빈 줄(`|  |  |  |`)은 구분선과 같이 취급(형식 미달 0) — 담긴 내용이 없어 잃을 정보가 없다. 기본 모드는 `| R` 필터 그대로(Q1 불변).
- 질문: **Q2 만** — r1 반례가 report 에서 ERROR 1·세 곳 경고로 드러나는가 · 위 명시 제한 밖에서 조용히 빠지는 데이터 행이 남는가. 판정문은 같은 파일에 «r2» 절 추가 · 끝 줄 APPROVE|HOLD.
