# 인덱스: 아침 매거진 수집 중단 — 옛 형식 완성 카드(상태·골좌표 없음)를 «형식 미달 카드» 로 드러내고 계속 발행 (판정 602 · planner 값 ① 채택 #67185 · master#21 쪽지 #67187)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 602(판정 601 ③ PR 1059 `e8c5718a8c` 설치 뒤 수집 dry 중단 · 급함)
- 상태: 대기
- 선행: 없음
- 시험 입력: 임시 git 리포 픽스처(카드 md)로 `collect_detail` · `magazine_render_full` 을 부른다(Slack 게시 0)
- 기준값: origin/main `scripts/harness-install/slack-mirror/magazine_collect_detail.py:73-94` `_card` 는 `## 상태`·`## 배경`·`## 골좌표`·제목 중 하나라도 없으면 raise → 창 안 완성 카드 113장 중 `design/cfo` 옛 형식 11장 때문에 매거진 전체가 멈춘다(master#21 실측 #67184).
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포 발행(슬랙) — 다른 팀 카드 형식 한 장 때문에 전 팀 매거진이 멈추지 않는다 · 형식 미달은 숨기지 않고 매거진 본문과 로그에 보인다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
아침 매거진 풀 디테일의 D1(닫힌 단위)은 `magazine_collect_detail.py` 의 `_units` → `_card` 가 창 안에 `design/*/indices/완성/` 으로 추가·이동된 카드마다 제목·`## 상태`·`## 배경`·`## 골좌표` 를 뽑는다. 하나라도 없으면 `MagazineError` 로 수집 전체가 멈춘다(반쪽 결과 금지 설계). 그런데 카드 형식은 팀마다 시기마다 달라서(design/cfo 옛 카드 11장), 남의 팀 카드 한 장이 전 팀 매거진을 막는다. BYZ #0 규칙(NO SILENT FALLBACK)상 «조용히 건너뛰기» 는 금지이고, 예외는 ①명시 opt-in ②ERROR 로그 ③사용자에게 보이는 경고 셋을 «모두» 갖출 때만이다. 이 카드는 그 세 가지를 갖춘 «형식 미달 카드 보고» 모드를 더한다.

## 사전검증
- 소환: 아니오 (arch#22 설계 = 아래 닫힌 목록)
- 구현 DA: ★예 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료★ — Q1 opt-in 없을 때 동작 불변(raise) · Q2 opt-in 때 형식 미달이 «조용히» 빠지는 경로 0(로그·본문 둘 다) · Q3 정상 카드 출력 바이트 불변.

## 설계 (닫힌 목록)
1. **opt-in**: 환경변수 `MAGAZINE_MALFORMED_CARDS`. 값 `report` 일 때만 아래 2~3 · 그 외(없음 포함) = 지금처럼 raise. 다른 값(오타 등)은 raise(«알 수 없는 값»). launchd 템플릿 `scripts/harness-install/slack-mirror/com.byz.ft-magazine.plist.template` EnvironmentVariables 에 `MAGAZINE_MALFORMED_CARDS=report` 를 명시(설치가 곧 opt-in 기록).
2. **수집** `scripts/harness-install/slack-mirror/magazine_collect_detail.py`: `_card` 에서 빠진 절(제목 포함)을 모은다. `report` 모드에서 빠진 것이 있으면 그 카드는 `units` 에 넣지 않고 `detail["malformed"]` 목록에 `{"path", "team", "missing": [절 이름…], "moved_sha", "ref"}` 로 넣는다 + stderr 에 `ERROR magazine: 형식 미달 카드 <path> (빠진 절: …)` 1줄씩. 카드 파일 읽기(`blob`) 실패·git 실패는 모드와 무관하게 raise 그대로.
3. **보이는 경고(planner 조건 c — 호 첫 화면·부록)**: 경고 문구 = 「⚠ 형식 미달 카드 N장: <경로1> · <경로2> …」(경로 전부 · 카드 내용 추정·채우기 0).
   - 첫 화면: `scripts/harness-install/slack-mirror/magazine_render_full.py` `render_full` 의 목차 바로 뒤(1부 요약판 첫 절 앞)에 그 1줄 + Slack 뿌리 글(`scripts/harness-install/slack-mirror/magazine_slack.py` `root_text`)에 같은 1줄(`scripts/harness-install/slack-mirror/byz_morning_magazine.py` 가 넘김 · 기존 `warn`(쉬운 판 실패)과 별 줄).
   - 부록: `_appendix` 맨 앞에 h3 「형식 미달 카드 N장」 + 카드별 1줄(`팀 · 경로 · 빠진 절`).
   - `malformed` 0 이면 세 곳 모두 출력 바이트 불변. `check_detail`/`DETAIL_KEYS` 에 `malformed` 추가(없으면 기존 키 검사와 같이 raise).
4. 200줄 규칙: `magazine_collect_detail.py` 176줄 · `magazine_render_full.py` 148줄 — 넘으면 형식 검사·경고 문구 함수를 새 파일 `scripts/harness-install/slack-mirror/magazine_card_shape.py` 로(그 경우 `scripts/harness-install/slack-mirror/install-magazine.sh` REQUIRED 추가 + `tests/harness/test_magazine_install_list.sh` 통과).
5. 내일 08:00 예약 실행: plist 템플릿 env 추가(설계 1)를 이 카드에 포함 — 재적재(bootout/bootstrap)는 master 집행.

## 구현 범위 (닫힌 목록)
1. 위 설계 1~4.
2. 시험 `tests/scripts/test_magazine_collect_detail.py` 에 행: M1 opt-in 없음 + 옛 형식 카드 → raise(지금과 같음) · M2 `report` + 옛 형식 1장 + 정상 2장 → units 2 · malformed 1(빠진 절 = 상태·골좌표) · stderr 에 ERROR 1줄 · M3 `report` + 정상만 → malformed 0 · 정상 카드 출력이 opt-in 없을 때와 같다 · M4 알 수 없는 값 → raise · M5 카드 blob 읽기 실패는 `report` 여도 raise.
3. 렌더 시험(새 파일 `tests/scripts/test_magazine_malformed_render.py` · 100줄 이하): malformed 2 → 목차 뒤 1줄·뿌리 글 1줄·부록 h3+2줄에 경로 전부 · malformed 0 → 세 곳 출력이 기존과 같다 · plist 템플릿에 `MAGAZINE_MALFORMED_CARDS` `report` 존재(`tests/harness/test_magazine_plist.sh` 행 추가).
4. 기존 PASS: `tests/scripts/test_magazine_collect_mbox.py` · `tests/scripts/test_magazine_collect_detail.py` · `tests/harness/test_magazine_plist.sh`(템플릿 변경 반영) · `tests/harness/test_magazine_install_list.sh`.
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.hermes/` 쓰기·launchd·Slack 게시 · design/cfo 카드 수정(그건 planner 선택지 ②).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 구현 DA APPROVE(또는 2 HOLD 뒤 arch 서명).
- 카드 증거 줄: `세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_detail.py rc=0 · 이슈: 0`.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#22 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: install-magazine.sh(plist 재생성 · opt-in 포함) → 수집 dry 1회(raise 0 · ERROR 11줄 · malformed 11) → 10-09 호 수동 재발행(env 를 명령에 직접) → 첫 화면·뿌리 글·부록에 «형식 미달 11장» 이 보이는지 1줄 → planner 보고 뒤 plist 재적재.

## 상태
- base_sha: e8c5718a8ce6e74eb0d66c52df190a657011c07a (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#22 · 판정 602 · planner ① #67185 · master#21 #67187). CFO 옛 형식 11장 보정 = cfo 몫(완성 후) · 이 카드는 경로만 드러낸다.
- 정본 영향 없음: 하네스 매거진 키트·시험만.
- 2026-10-09 08:25 — 대기→진행 · 좌석 byz-harness-nano-mag602-malformed-cards-report#0

## 결과 (나노 RESULT #67197 · arch#23 재현 · DA r1 APPROVE · master#21 옮김 2026-10-09)
세트: 4b047d19ed5b7df3487703e0c974e2c88c3b404b · 시험: .venv/bin/python -m pytest --noconftest tests/scripts/test_magazine_collect_detail.py rc=0 · 이슈: 0
정본 영향 없음: 하네스 슬랙 미러 키트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 08:42 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§103
