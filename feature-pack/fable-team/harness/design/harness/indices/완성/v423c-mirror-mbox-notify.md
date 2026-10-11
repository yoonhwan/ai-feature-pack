# 인덱스: v423c 미러 요약기 할 일 금지 + Haiku 5.5 · planner 처리 1줄 · mbox ①~④ 항상 doorbell · 회신 발신 상한 제외 (판정 423 ②③④ · 430·431 · 설계 §3 · v423 분할 3/3)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 423(오빠 승인 6개: ①종류별 보고 의무 ②미러 할 일 금지+planner 처리 1줄 ③판정·승인·HIL 항상 doorbell ④회신 상한 완화 ⑤인터뷰 전 함 비우기 ⑥보드 planner 미처리 칸) · 421 발행 · 430·431 컨펌(planner #62745 · master #62749)
- 상태: 대기
- 선행: R49 랜딩(완료 · #1004 75bf03175f — `byz_mbox_slack_mirror.py` 199줄 · `mirror_board.py` 신설) · v423b 랜딩 뒤 착수(순서만) · ★`mbox-sh-split-200` 카드(판정 545 ④)보다 «먼저» — 같은 `mbox.sh` 를 만진다★
- 시험 입력: 임시 FT_ROOT(가짜 mailbox.jsonl · 가짜 seats.json · 가짜 인박스 큐) + 요약기 스텁 명령 + 가짜 슬랙 API base — 실제 슬랙·claude 호출 0
- 기준값: 발신 상한 RATE_LIMIT 5건/60초에 7회 막혀 전부 --force(AUDIT-r34) · 슬랙 요약기가 처리된 일을 「판정 부탁」으로 표시 · `scripts/harness-install/slack-mirror/mirror_summary.py:17` 모델 claude-haiku-4-5-20251001
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 「슬랙 메세지 이런거 왜 플래너로 안올라오냐」「빠르게 공유 처리가 안되는게 문제」). 핵심 한 줄: 읽은 쪽지 ①~④ 는 «mark + 최종 답변의 #seq» 둘 다 될 때까지 턴마다 대상으로 남고, 보드는 하루 1 뿌리 글을 갱신하며 변화만 답글로 낸다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
R34 실측: planner 는 쪽지를 빨리 읽지만(중앙값 22초) 읽은 뒤 오빠께 안 올리는 것이 26%, 슬랙 요약기가 이미 처리된 일을 「오빠 할 일」로 만들어 혼동을 키우며, 발신 상한·인터뷰 중 정지가 planner 손을 묶는다. 나노 4 의 인박스 큐(좌석 계보 키 · 정본 술어 `obligation_closed(line) = mark != null ∧ (cls ∉ {①,②,③,④} ∨ reported == true)`)가 의무의 저장소다. 이 카드는 ①planner Stop 훅이 턴 끝에 «닫히지 않은 ①~④» 를 턴 키당 1회 block 하고, 최종 답변의 `#seq` 직접 표기로 `ft-inbox.sh report` 를 불러 reported 를 세우며 ②AskUserQuestion 직전 함이 비지 않았으면 턴 키당 1회 deny 하고 ③슬랙 미러 요약기가 할 일을 지어내지 못하게 하고(모델 = 오빠 컨펌값 Haiku 5.5) ④mbox 깨우기를 인박스 분류로 정하고 회신은 발신 상한에서 빼고 ⑤보드를 byz_thread_post 의 `update` 로 하루 1 뿌리 글에 갱신 발행한다(스냅샷 먼저 · 나노 2 의 `ft-board.py snapshot` rc=0 일 때만). 오류는 전부 «통과 + 기록 + 보드에 보임» — 훅이 사람 입력을 영구히 막는 경로 0.

## 사전검증
- 소환: 아니오
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/harness/DA-news-board-20261009.md §2~§8 · N2 유한 훅(턴 키 1회)·오류 가시성·#seq 직접 참조·pending/미보고 분리 = 수락 · N2 잔여는 설계 §8 정본 술어로 고정 · N3 APPROVE) → 오빠 컨펌 GO 판정 430·431(planner #62745 · master #62749) · 잔여는 완료 조건 시험으로 닫고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#14
- 분할(arch#18): 원 카드 사전검증·DA·컨펌이 세 카드를 그대로 덮는다(범위는 원 카드 구현 범위의 부분집합).

## 조사 근거 (origin/main dbbf096099 재확인 · arch#18)
- `scripts/harness-install/slack-mirror/mirror_summary.py:17` DEFAULT_CMD 모델 · `:24`~`:27` PROMPT 의 todo 생성 지시(HIL 이면 todo 강제 줄 :26) · `:54` todo 정규화(75줄).
- `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py:77` _close_answered · `:128` _row(행 게시) — ★지금 199줄 → «planner 처리 1줄»은 `scripts/harness-install/slack-mirror/mirror_board.py`(161줄) 또는 새 파일에 함수로 두고 미러엔 호출 1줄만★.
- `tools/comm-canonical/mbox.py:388` 발신 상한 RATE_LIMIT 계산(파일 582줄 — 기존 초과 · 이 카드는 그 함수 안 수정만) · `tools/comm-canonical/mbox.sh:147` notify_policy · `:184` send 의 notify 결정 — 둘 다 라이브 `.fable-team/comm/` 과 cmp 같음(23:0x).
- 인박스 분류 `scripts/fable-team-bin/ft_inbox_core.py:114` rule_class(①~⑥·미상).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. 미러 요약기: `mirror_summary.py` — ①DEFAULT_CMD 모델 = `claude-haiku-5-5`(오빠 컨펌값 · 모델 하나 · 폴백 0) ②PROMPT 에서 todo «생성» 지시 삭제 → 「원문에 할 일 문장이 있으면 그대로 복사, 없으면 null」 · HIL 라벨 강제 todo 줄 삭제. `byz_mbox_slack_mirror.py`: planner 발신 행의 본문에 받은 `#seq` 가 있으면 그 seq 의 스레드에 「planner 처리: <첫 문장> (<시각>)」 1줄(새 글 0).
2. mbox(`tools/comm-canonical/mbox.py` · `mbox.sh` — 수정 전 라이브와 바이트 동일 확인 · 다르면 [structure] 동기화 커밋 먼저): ①send 의 notify = 인박스 적재 cls 가 ①~④·미상이면 tick 유무와 무관하게 doorbell(⑤⑥ 은 지금 규칙 그대로) ②RATE_LIMIT 계산(`mbox.py:386`)에서 본문 첫 80자 안에 받은 `#seq`(그 발신자에게 온 쪽지 seq)를 인용한 회신은 셈에서 제외 — 다른 가드(fan-out·재발송 쿨다운)는 그대로.
3. 시험:
   - `tests/harness/test_mirror_no_todo.sh`: 요약 스텁이 todo 를 지어내도 원문에 할 일 문장 없으면 「없음」 · planner 회신 행 → 대상 스레드 1줄 · DEFAULT_CMD 에 claude-haiku-5-5.
   - mbox: ①~④·미상 notify=1(tick 없는 좌석 포함) · 회신 6건/60초 RATE_LIMIT 0 · 비회신 6건째 RATE_LIMIT 유지.
   - `test_kit_bin_sync.sh` · `tests/harness/test_question_board.sh` · `test_slack_readonly_share.sh` PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: 실제 슬랙·claude 호출 · 훅 홈·settings 등록(master 집행) · 술어·스냅샷 재구현(ft-inbox.sh·ft-board.py 호출만) · transcript 본문 파싱(마지막 user 레코드 uuid 와 최종 답변 텍스트만) · 요약 모델 폴백 · 라이브 .fable-team/comm·state 쓰기 · 전역 settings 등록.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_mirror_no_todo.sh` rc=0 · mbox 시험 rc=0 · 기존 시험 PASS · 사본 cmp · bash -n · `ruff check` 0 · 새·고친 파일 200줄 이하(mbox.py 는 기존 초과 — 늘린 줄 수 RESULT 에 명시).
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_mirror_no_todo.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다(그 뒤 커밋·추가 확인 0).
- 랜딩 뒤 master 집행(카드 밖): 라이브 comm(mbox 2파일)·slack-mirror 반영 · 미러 launchd 재시작 · doorbell 수/시간 1일 관찰(설계 §6-4).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 5efbed6cc45c78b17de8b806af7665307e16f5b0 (spawn 2026-10-09)
- 2026-10-09 00:3x — arch#19 spawn 전 재확인(origin/main 162591a1da 이후 · v558 랜딩 7a13b099e9 포함): 인용 줄 그대로 — mirror_summary.py:17 haiku-4-5 · mbox.py:388 RATE_LIMIT(582줄) · byz_mbox_slack_mirror.py 199줄 · mirror_board.py 161줄 · 라이브 .fable-team/comm mbox.py·mbox.sh = 추적본 같은 바이트 · ft_inbox_core.py 130줄(v558 waived 항 반영 — 이 카드의 인박스 분류 호출과 충돌 0) · ft-nano-spawn --dry-run PLAN 통과.
- 2026-10-08 — 원 카드 대기/ 생성 (byz-harness-arch-claude#14 · 판정 421·423 설계 r2 §2-3·§2-4·§3 나노 3 · 오빠 컨펌 판정 430·431 · master #62749).
- 2026-10-08 23:0x — v423 원 카드(나노 3 · 구현 범위 5덩어리 · 시험 4종)를 arch#18 이 3장으로 분할(판정 545 순서 ① · master#18 #65524): v423a 보드 발행 → v423b planner 보고 훅 → v423c 미러 요약기·mbox. 설계·DA·오빠 컨펌(430·431) 범위 변경 0 · 원 카드 글자는 각 카드에 그대로 옮김 · 참조 줄 origin/main dbbf096099 기준 재확인.
- 정본 영향 없음: 하네스 도구·훅·미러·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 00:37 — 대기→진행 · 좌석 byz-harness-nano-v423c-mirror-mbox-notify#0

## 결과 (나노 RESULT r2 · master#20 옮김 2026-10-09)
세트: f911f4fb50147862a2e286216f6e1baadd7a2371 · 시험: bash tests/harness/test_mbox_inbox_notify_reply_rate.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 통신·미러 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 01:41 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§89
