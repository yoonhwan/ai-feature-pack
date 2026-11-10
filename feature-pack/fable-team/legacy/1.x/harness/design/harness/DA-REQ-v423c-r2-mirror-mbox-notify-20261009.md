# DA 요청 r2 — v423c 반송 r1 수정 재확인 (arch#20 · 2026-10-09 · bounded: Q1·Q3·Q4 + 새 시험만 · 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — 「슬랙 메세지 이런거 왜 플래너로 안올라오냐」「빠르게 공유 처리가 안되는게 문제」).

## 고정 대상
- 커밋 `82dd9e8d16c37d38f4d51d18390be990b9247989`(브랜치 `nano/v423c-mirror-mbox-notify` · 부모 r0 `58aca7b614` · 6파일 +215 −57). r1 판정문 `design/teams/harness/DA-v423c-mirror-mbox-notify-20261009.md`(Q2 APPROVE · Q1·Q3·Q4 HOLD) · 반송서 `.fable-team/state/drafts-r21/REJECT-v423c-mirror-mbox-notify-r1.md`(arch 결정 = 아래 수락 기준).
- 바뀐 곳: `tools/comm-canonical/mbox.py`(`_REPLY_REF` · `_reply_seqs` · `_received_seqs` · `_reply_exempt` · `send()` 가 잠금 안에서 1회 계산해 `_guard_verdict(…, exempt)`·`_guard_record(…, exempt)` 에 전달 · 기록 `r` = 면제 seq 목록) · `mirror_summary.py`(`_SPLIT`·`_sentences`·`parse_summary(raw, source, label)` · PROMPT todo 에 HIL 조건) · `mirror_deliver.py`(`existing_thread` · `Deliverer.send` 의 `reply_only` 분기) · `mirror_board.py`(item 에 `reply_only: True`) · 시험 2.

## arch#20 독립 재현 (증거 · 82dd9e8d16 아카이브 · 스크래치패드 새 폴더)
- test_mirror_no_todo 39 PASS · test_mbox_inbox_notify_reply_rate 34 PASS · test_kit_bin_sync · test_question_board · test_slack_readonly_share · test_inbox · test_slack_mirror_signature — 전부 rc=0. ruff 미러 4파일 0 · `mbox.py` 17건 = merge-base `5efbed6cc4` 와 같은 수(기존).
- 순수 함수 반례 재생(FT_MBOX_DIR 임시): `_reply_seqs` — `PR #1027 업데이트`·`Issue #1027`·`#1027 건` = [] · `쪽지 #1027·#1028` = [1027, 1028] · `쪽지#1027` = [1027] · 80자 밖 = []. `_reply_exempt` — 같은 frm 기록 `r:[1027]` 뒤 `쪽지 #1027` 재인용 = [](셈 포함) · `쪽지 #1028` = [1028]. `parse_summary` — 라벨 `보고` + 원문 문장 = None · HIL + 원문 한 문장 = 그대로 · HIL + 원문 문장 + 지어낸 꼬리 = None · HIL + 조각 = None.
- ★알고 둔 경계 2(arch 설계 결정 · 반례 아님)★: ①HIL 보고 안의 «상태» 문장을 모델이 복사하면 남는다 — 원천 = HIL 라벨(보고 자체가 사람 결정 요청)로 인정한 범위. ②옛 기록 `r: 1`(int)은 seq 를 모르므로 같은 seq 재면제를 막지 못한다 — 가드 보관 창(`max(FANOUT_WIN, RATE_WIN)`)이 지나면 사라지는 일회성 호환.

## 질문 (bounded — r1 HOLD 3개 + 새 시험만 · 새 요구 금지)
- **Q1** 회신 면제가 `쪽지 #<seq>` 꼴에서만 나는가 · 받은 seq 1개당 1회인가(같은 seq 를 다른 본문으로 반복해 RATE 무한 면제가 남는가) · verdict·record 가 한 번 계산된 같은 값을 쓰는가 · `_reply_exempt` 예외 시 `exempt=[]`·verdict None(기존 fail-open 규약)이 RATE 를 «더 넓게» 여는 경로가 있는가.
- **Q3** todo 가 HIL 라벨 + 원문 한 문장 «전체» 정확 일치(절단 전 길이 ≤110)에서만 남는가 · 110자 접두 + 꼬리 · 조각 · 공백·구두점 정규화 차이로 통과하는 경로가 남는가.
- **Q4** `reply_only` item 이 정상·resume(pending 재개) 두 경로 모두에서 `ensure_thread`/`make_root` 를 부르지 않는가 · 맵에 키 없음 = 0줄(WARN) · `_send_item` 의 question 분기가 reply_only item 에서 `thread_ts` 를 부르는 길이 있는가.
- 범위 밖: Q2(r1 APPROVE · `mbox.sh` 무변경) · 기존 pytest 17 실패(수정 전과 같은 목록) · `mbox.py` 200줄 초과(626 · 기존 · 별 카드) · 위 «알고 둔 경계 2»(설계 결정 — 반례로 다시 올리지 않는다).

## 판정문
`design/teams/harness/DA-v423c-mirror-mbox-notify-20261009.md` 끝에 `## r2` 절 — Q1·Q3·Q4 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD. 실행 헤더 `model:`/`provider:` 두 줄 그대로.
