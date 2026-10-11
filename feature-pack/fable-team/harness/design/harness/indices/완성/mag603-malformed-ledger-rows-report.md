# 인덱스: 아침 매거진 수집 중단 — REQUEST-LEDGER 형식 미달 행(열 수 ≠ 7)을 report 모드에서 «형식 미달 요청 행» 으로 드러내고 계속 발행 (판정 603 · planner 값 ① #67205 · master#21 쪽지 #67206)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 603(판정 602 PR 1060 `b545ab1225` 설치 뒤 수집 dry 가 원장에서 중단 · 급함)
- 상태: 대기
- 선행: 판정 602(PR 1060 · `MAGAZINE_MALFORMED_CARDS` opt-in · `scripts/harness-install/slack-mirror/magazine_card_shape.py`)
- 시험 입력: 임시 git 리포 픽스처(REQUEST-LEDGER md)로 `collect_open` · `magazine_render_full` 을 부른다(Slack 게시 0)
- 기준값: origin/main `scripts/harness-install/slack-mirror/magazine_collect_open.py:53-61` `_request` 는 열 수 ≠ 7 이면 raise → 창 끝 스냅샷(origin/main `1c2828e1f8`)의 원장 4열 행 22개(R38~R59) 때문에 매거진 전체가 멈춘다(arch#23 실측 · 정리 PR 1061 은 창 뒤라 오늘 호에 안 잡힘).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포 발행(슬랙) — 원장 행 형식 하나 때문에 전 팀 매거진이 멈추지 않는다 · 형식 미달 행은 숨기지 않고 매거진 본문과 로그에 보인다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진 풀 디테일의 D6(열린 행)은 `magazine_collect_open.py` 의 `_requests` → `_request` 가 창 끝 sha 의 `design/harness/REQUEST-LEDGER.md` 에서 `| R` 로 시작하는 행을 7열로 읽는다. 열 수가 다르면 `MagazineError` 로 수집 전체가 멈춘다. 판정 602 는 같은 문제(완성 카드 형식 미달)를 opt-in `MAGAZINE_MALFORMED_CARDS=report` 로 풀었다(①opt-in ②stderr ERROR 줄 ③첫 화면·뿌리 글·부록 경고 — BYZ #0 NO SILENT FALLBACK 예외 3요건). 이 카드는 «같은 opt-in» 을 원장 행에도 넓힌다. 새 환경변수는 만들지 않는다. 행 내용은 추정·채우지 않는다(행 id 와 열 수만).

## 사전검증
- 소환: 아니오 (arch#23 설계 = 아래 닫힌 목록 · 판정 602 의 직접 확장)
- 구현 DA: ★예 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료★ — Q1 opt-in 없을 때·오타일 때 동작 불변(raise) · Q2 report 때 형식 미달 행이 «조용히» 빠지는 경로 0(로그·본문 둘 다) · Q3 정상 행·malformed 0 출력 바이트 불변.

## 설계 (닫힌 목록)
1. **opt-in**: 판정 602 의 `scripts/harness-install/slack-mirror/magazine_card_shape.py` `report_mode()` 를 그대로 쓴다(없음=False · `report`=True · 그 밖=raise). 새 환경변수·plist 변경 0.
2. **수집** `scripts/harness-install/slack-mirror/magazine_collect_open.py`: `_request(line, report)` — 열 수 ≠ 7 이고 `report` 아니면 지금처럼 raise. `report` 면 행을 건너뛰고 `{"id": <첫 칸 그대로>, "cells": <열 수>}` 를 형식 미달 목록에 넣고 stderr 에 `ERROR magazine: 형식 미달 요청 행 <id> (열 수 <n> · 기대 7)` 1줄. `_requests` 는 (정상 행, 형식 미달 행) 둘을 돌려주고 `collect_open` 반환에 키 `malformed_requests` 추가. 원장 blob 읽기 실패는 모드와 무관하게 지금 그대로(raise).
3. **보이는 경고(602 와 같은 세 곳 · 같은 모양)**: 문구 = 「⚠ 형식 미달 요청 행 N개: R38 · R39 …」(id 전부).
   - 첫 화면: `scripts/harness-install/slack-mirror/magazine_render_full.py` `render_full` 목차 뒤 — 602 카드 경고 줄 다음 줄(둘 다 있으면 2줄 · 각자 0 이면 그 줄 없음).
   - 뿌리 글: `scripts/harness-install/slack-mirror/byz_morning_magazine.py` 가 `scripts/harness-install/slack-mirror/magazine_slack.py` `root_text` 에 넘기는 형식 미달 경고에 같은 줄(카드 줄과 별 줄).
   - 부록: `_appendix` 앞 602 h3 다음에 h3 「형식 미달 요청 행 N개」 + 행별 1줄(`id · 열 수 n(기대 7)`).
   - 형식 미달 행 0 이면 세 곳 모두 출력 바이트 불변. `OPEN_KEYS` 에 `malformed_requests` 추가(없으면 기존 키 검사와 같이 raise) · 시험 fixture 의 `open` 에 `"malformed_requests": []`.
4. 문구·ERROR 줄 함수는 `scripts/harness-install/slack-mirror/magazine_card_shape.py` 에 더한다(새 파일 0 · install 목록 변경 0). 200줄 규칙 유지.

## 구현 범위 (닫힌 목록)
1. 위 설계 1~4.
2. 시험 `tests/scripts/test_magazine_collect_open.py`(없으면 새 파일 · 100줄 이하): L1 opt-in 없음 + 4열 행 → raise(지금과 같음) · L2 `report` + 4열 2행 + 정상 7열 2행 → requests 정상 2(닫힘 제외 규칙 그대로) · malformed_requests 2(id·열 수) · stderr ERROR 2줄 · L3 `report` + 정상만 → malformed_requests 0 · requests 가 opt-in 없을 때와 같다 · L4 알 수 없는 값 → raise · L5 원장 blob 읽기 실패는 `report` 여도 기존대로(모든 ref 실패면 raise).
3. 렌더 시험 `tests/scripts/test_magazine_malformed_render.py` 에 행: 형식 미달 행 2 → 목차 뒤 줄·뿌리 글 줄·부록 h3+2줄에 id 전부 · 카드·행 둘 다 있을 때 두 줄 별 줄 · 둘 다 0 → 세 곳 출력이 기존과 같다.
4. 기존 PASS: `tests/scripts/test_magazine_collect_detail.py` · `tests/scripts/test_magazine_malformed_render.py` · `tests/scripts/test_magazine_render_full.py` · `tests/scripts/test_magazine_collect_mbox.py` · `tests/harness/test_magazine_plist.sh` · `tests/harness/test_magazine_install_list.sh`. `tests/scripts -k magazine` 의 기존 13 실패(base `60ed7677dd` 와 FAILED 목록 동일)는 범위 밖 — 목록이 늘면 안 된다.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.hermes/` 쓰기·launchd·Slack 게시 · REQUEST-LEDGER 수정 · 행 내용 추정·채우기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 구현 DA APPROVE(또는 2 HOLD 뒤 arch 서명).
- 카드 증거 줄: `세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_open.py rc=0 · 이슈: 0`.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#23 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: install-magazine.sh → 수집 dry 1회(report · raise 0 · 형식 미달 카드 13 · 형식 미달 요청 행 22) → 10-09 호 수동 재발행(env 를 명령에 직접) → 첫 화면·뿌리 글·부록에 두 경고 줄 1줄 확인 → planner 보고. ★상한(master#21 #67206)★: 오늘 호 dry 가 5번째 원인에서 또 막히면 멈추고 오늘 호 생략 — 추가 수정 라운드 0.

## 대조 (구현 범위 밖 · 참고)
- arch#23 사전 dry(읽기 전용 · origin/main 키트 · `_request` 만 건너뛰게 바꾼 사본 · 실제 리포·mailbox · gh 읽기): 수집 전체 통과 · 건너뛴 원장 행 22 · units 138 · 형식 미달 카드 13 — 수집 단계에 5번째 원인 없음(렌더·LLM 요약 단계는 미확인).

## 상태
- base_sha: 60ed7677dd17ee1d82e6bda4e1780f86c329de77 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#23 · 판정 603 · planner ① #67205 · master#21 #67206).
- 정본 영향 없음: 하네스 매거진 키트·시험만.
- 2026-10-09 08:45 — 대기→진행 · 좌석 byz-harness-nano-mag603-malformed-ledger-rows-report#0

## 결과 (나노 RESULT #67228 · arch#23 재현 · DA 2 HOLD → arch 서명 · master#22 옮김 2026-10-09)
세트: 8202e8fe82f46c2b8b8981f67263e3e0ee7f092f · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_open.py rc=0 · 이슈: 0
정본 영향 없음: 하네스 매거진 키트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 09:12 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§104
