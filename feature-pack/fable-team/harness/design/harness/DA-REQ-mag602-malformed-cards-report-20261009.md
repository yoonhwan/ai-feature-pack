# DA 요청 — 판정 602 매거진 형식 미달 카드 보고 모드 (arch#23 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · ★오늘 호 미발행 — 급함★)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 커밋 `4b047d19ed5b7df3487703e0c974e2c88c3b404b`(브랜치 `nano/mag602-malformed-cards-report` · base `e8c5718a8c`). 변경: 새 `scripts/harness-install/slack-mirror/magazine_card_shape.py`(`report_mode`·`missing_parts`·`error_for`·`report_line`·`warning_line`) · `magazine_collect_detail.py`(`_card`·`_units`·`collect_detail` → `malformed`) · `magazine_collect.py`(+`malformed` 전달) · `magazine_render_full.py`(`DETAIL_KEYS`+`malformed` · 목차 뒤 1줄 · `_appendix` 앞 h3) · `magazine_slack.py`(`root_text(malformed=)`) · `byz_morning_magazine.py`(`Made.malformed`) · `install-magazine.sh`(REQUIRED +`magazine_card_shape.py`) · plist 템플릿(`MAGAZINE_MALFORMED_CARDS=report`) · 시험 M1~M5 · 새 `tests/scripts/test_magazine_malformed_render.py` · fixture 3곳 `"malformed": []`.
- 카드 `design/teams/harness/indices/진행/mag602-malformed-cards-report.md`(설계 닫힌 목록 1~5).

## arch#23 독립 재현 (git archive 새 mktemp)
- collect_detail·malformed_render·collect_mbox·render_full **50 passed** · `test_magazine_plist.sh` ALL PASS · `test_magazine_install_list.sh` ALL PASS · ruff clean.
- `tests/scripts -k magazine` 13 failed = base `e8c5718a8c` 와 FAILED 목록 동일(diff 0) — 이 커밋 무관. (그중 `test_magazine_collect_decisions.py` 4건은 판정 601 PR 1059 가 만든 것 — 범위 밖 · 별 카드.)
- ★실데이터 읽기 전용 dry★(실제 리포 · DEFAULT_REFS · 창 2026-10-09): env 없음 = RAISE(`## 상태` 없음 · cfo 카드 · 지금과 같음) · `Report`(오타) = RAISE(알 수 없는 값) · `report` = raise 0 · units 138 · **malformed 13**(cfo 12 + harness 1) · stderr `ERROR magazine: 형식 미달 카드` 13줄 · 그 밖 stderr 0.

## 질문 (bounded · 새 요구 금지)
- **Q1 opt-in 없을 때 동작 불변**: env 없음 → 기존과 같은 순서·문구로 raise(제목→상태→배경→골좌표) · env 빈 문자열·오타 → raise · blob/git 실패는 `report` 여도 raise.
- **Q2 조용한 누락 0**: `report` 모드에서 형식 미달 카드가 units 에서 빠질 때마다 stderr ERROR 1줄 + 첫 화면(목차 뒤)·뿌리 글·부록 h3 세 곳에 경로 전부 — 어느 한 곳이라도 빠지는 경로(예: eli5 실패 날 · 다른 ref 가 같은 경로를 먼저 본 경우)가 있는가.
- **Q3 정상 카드 출력 불변**: malformed 0 이면 render_full·root_text·appendix 바이트 불변 · 정상 카드의 units 항목 내용이 기존과 같다(`pick` 을 `next(...)` 로 바꾼 부분 포함).
- 범위 밖: 기존 13 실패 · design/cfo 카드 보정(cfo 몫) · Slack 게시·홈 설치·plist 재적재(master).

## 판정문
`design/teams/harness/DA-mag602-malformed-cards-report-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD · 끝 줄 APPROVE 또는 HOLD.
