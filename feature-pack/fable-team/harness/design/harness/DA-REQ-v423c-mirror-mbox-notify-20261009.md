# DA 요청 — v423c 미러 요약기 할 일 금지 + Haiku 5.5 · planner 처리 1줄 · mbox ①~④ 항상 doorbell · 회신 발신 상한 제외 구현 검토 (arch#19 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — 「슬랙 메세지 이런거 왜 플래너로 안올라오냐」「빠르게 공유 처리가 안되는게 문제」).

## 고정 대상
- 커밋 `58aca7b61485747809041b7a45b36b7c3f8c38f6`(브랜치 `nano/v423c-mirror-mbox-notify` · base origin/main · 9파일 +299 −13):
  `scripts/harness-install/slack-mirror/mirror_summary.py`(DEFAULT_CMD 모델 → claude-haiku-5-5 · PROMPT todo = 원문 복사만 · `parse_summary(raw, source)` 원문에 없는 todo → null) · `byz_mbox_slack_mirror.py`(200줄 · post_handled 호출 1줄) · `mirror_board.py`(180줄 · `post_handled` · `SEQ_REF`) · `tools/comm-canonical/mbox.py`(582→610 · `_is_reply` · guard 기록 `r` · RATE 셈 제외) · `tools/comm-canonical/mbox.sh`(inbox_ingest 가 `cls` 를 INBOX_CLS 에 · `inbox_must_ring` ①~④·미상 → notify=1 · send·relay) · 시험 2 새 + 2 갱신.
- 카드 `design/teams/harness/indices/진행/v423c-mirror-mbox-notify.md` · 원 카드 사전 DA `design/teams/harness/DA-news-board-20261009.md`(2 HOLD 종료 · 잔여 = 구현 DA 재확인) · 오빠 컨펌 430·431.
- 증거(arch#19 재현 · origin/main 3f6414e070 아카이브 + 나노 diff): test_mirror_no_todo · test_mbox_inbox_notify_reply_rate · test_kit_bin_sync · test_question_board · test_slack_readonly_share · test_inbox · test_slack_mirror_signature — 전부 rc=0.
  미러·proposal pytest 6파일(`tests/scripts/test_byz_*_slack_mirror.py` · `test_mirror_summary_cc_route.py` · `test_proposal_*.py`): 수정 전 main = 16 failed / 59 passed · 수정 후 = 16 / 59 · ★실패 목록 diff 0(회귀 0 · 기존 16건은 이 카드 밖)★.
  모델 실호출(arch · `~/.headroom/claude-hr.sh -p --model claude-haiku-5-5 …` + SUMMARY_ENV): rc=0 정상 응답(4-5 도 rc=0). 원장 R57 의 Haiku 실패(51줄 · 20초 Timeout)는 래퍼 없는 `claude -p`(ft-inbox 분류) 경로 — 이 카드 경로와 다름.
  부하(arch 실측): `_is_reply` 는 본문 앞 80자에 `#N` 이 있을 때만 큐 + 보낸 행 사본 2파일(지금 1.16MB + 5.24MB · 9,604줄)을 읽는다 — 1회 40ms · 최대 RSS 14MB · send 1건당 2회(verdict·record). 회전(.1 상한)으로 상한 있음.
- 범위 영향(나노 보고 · arch 확인): DEFAULT_CMD 는 `byz_github_slack_mirror.py:131` · `byz_proposal_publish.py:29` · `magazine_summary.py:16` 도 가져다 쓴다 → 그 셋의 요약 모델도 haiku-5-5 로 바뀐다(모델 하나 · 폴백 0 · 실호출 정상).

## 질문 (모두 «사람이 볼 할 일·알림이 지어지거나 빠지지 않는다 · 발신 가드가 회신 외에는 그대로» 하나의 수락 표로 · 반례는 코드 줄 + 재현 입력)
- **Q1 회신 판정(`mbox.py` `_is_reply`)**: 회신이 아닌 쪽지가 RATE 에서 빠지는 경로 — 본문 앞 80자의 `PR #1027`·`Issue #996` 같은 번호가 frm 이 옛날에 받은 seq 와 우연히 같을 때 · 머리 `[a->b]` 제거 정규식이 깨진 머리 · 같은 받은 seq 를 반복 인용한 연속 발신(FANOUT·쿨다운 외 상한 0 인가). record 와 verdict 가 같은 판정을 내는가.
- **Q2 doorbell(`mbox.sh`)**: ①~④·미상이면 tick 없는 좌석도 울리는가 · ingest 실패·SKIP(이미 적재)·출력 꼴 변화에서 notify 가 지금 규칙으로 돌아가는가(조용히 0 으로 꺼지거나 set -e 로 전송이 실패하는 경로) · send·relay 양쪽 같은가.
- **Q3 요약기 할 일(`mirror_summary.py`)**: 모델이 지어낸 할 일이 `parse_summary` 를 통과하는 경로(원문의 «할 일 아닌» 조각 복사 · 공백 정규화 차이 · 110자 절단) · HIL 라벨 강제 todo 가 남아 있는가.
- **Q4 planner 처리 1줄(`mirror_board.py` `post_handled`)**: 새 글(스레드 없음)을 만드는 경로 · planner 아닌 발신 · 좌석명 `master#19` 오인 · 한 행이 여러 스레드에 줄을 다는가.
- 범위 밖(새 요구 금지): 기존 pytest 16건 실패 · R57 분류 실패 · mbox.py 200줄 초과(기존 · 별 카드) · DEFAULT_CMD 공유 범위(판정 = master/planner 몫 — 사실만 기록).

## 판정문
`design/teams/harness/DA-v423c-mirror-mbox-notify-20261009.md` 에 r1 — Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.
