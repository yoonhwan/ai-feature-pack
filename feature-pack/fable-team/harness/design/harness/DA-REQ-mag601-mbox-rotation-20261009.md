# DA 요청 — 판정 601 매거진 mbox 회전본 이어 읽기 + 설치 목록 (arch#22 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · ★오늘 호 미발행 — 급함★)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 커밋 `fdc56ddd46d7ca469c6cd7e6d87efc90988212f6`(브랜치 `nano/mag601-mbox-rotation-and-install-list` · base origin/main). 변경: `scripts/harness-install/slack-mirror/magazine_collect_mbox.py`(+`read_window`·`_dedupe_seq` · `collect_mbox` 교체) · `magazine_collect_decisions.py`(`_read`→`read_window`) · `install-magazine.sh`(REQUIRED +`magazine_collect_open.py` +`thread_post_update.py`) · 시험 `tests/scripts/test_magazine_collect_mbox.py`(+7) · `tests/scripts/test_magazine_collect_detail.py`(fixture 창 앞 첫 줄 1개) · 새 `tests/harness/test_magazine_install_list.sh`.
- 카드 `design/teams/harness/indices/진행/mag601-mbox-rotation-and-install-list.md`.

## arch#22 독립 재현 (git archive 새 mktemp)
- collect_mbox 20 passed(base 13) · collect_detail 9 passed · plist rc0 · install_list rc0(새 시험을 base 에 돌리면 FAILED 1 = collect_open 누락 검출) · test_magazine_cli 5 failed = base 와 실패 목록 md5 동일(기존 실패 · 이 커밋 무관).
- ★실데이터 읽기 전용 dry★(실제 `.fable-team/comm/mailbox.log.jsonl` · 창 2026-10-08 08:00 ~ 10-09 08:00): 새 판 = OK(쪽지 6091 · 깨진 줄 0 · 판정 258 · decisions 240) · origin/main 판 = RAISE(첫 ts 21:04:13 > 창 시작) — 오늘 호 미발행 원인 재현·해소.
- 카드 밖 2건 arch 수락: ①`thread_post_update.py` = `byz_thread_post.py` 가 import(import 닫힘 시험이 찾음) ②collect_detail fixture 창 앞 줄 = decisions 가 이제 창 커버를 검사(ⓐ' 의 직접 결과).

## 질문 (bounded · 새 요구 금지)
- **Q1 누락 은폐 0**: 이어 읽어도 창 앞부분을 못 덮으면 raise 하는가 · `.1` 이 없을 때 기존 raise 그대로인가 · 현재 파일이 덮으면 `.1` 을 안 읽는가.
- **Q2 중복·순서**: 회전 경계 같은 seq 1회만 · 이어 붙인 순서가 ts 순 가정(`_seats` 의 `break`·`rows[0]`)을 깨는 경로.
- **Q3 설치 목록**: REQUIRED∪COMPANION ⊇ 진입 3개 import 닫힘 · 시험이 그걸 실제로 잡는가(변이).
- 범위 밖: test_magazine_cli 기존 5 실패 · Slack 게시·홈 설치(master).

## 판정문
`design/teams/harness/DA-mag601-mbox-rotation-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#22 · DA r1 HOLD Q2·Q3 만 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 · 급함)
- 고정 대상: `dd19902b7119a7d4aa1bbe5df59883004140df77`(부모 `fdc56ddd46`) — ①이어 붙인 경로만 seq 중복 제거 뒤 ts 안정 정렬 ②REQUIRED +`mirror_lib.py`·`mirror_summary.py` ③install_list 시험은 install-magazine.sh 목록만 비교 + collect_open·mirror_lib 제거 변이 각각 rc=1 ④Q2 반례 시험 행. 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/mag601/REJECT-mag601-r1.md`.
- arch#22 재현(git archive 새 mktemp): collect_mbox 21 passed · detail 9 · plist·install_list rc0 · cli 5 failed(기존 동일) · ★arch AST 독립 닫힘 = 38개 · 목록 누락 0★ · 실제 mailbox 읽기 전용 dry OK.
- 질문: **Q2·Q3 만** — r1 반례와 같은 성질이 남는가. Q1 은 r1 APPROVE 유지.
- 판정문: 같은 파일 `design/teams/harness/DA-mag601-mbox-rotation-20261009.md` 에 `## r2` · 끝 줄 APPROVE 또는 HOLD.
