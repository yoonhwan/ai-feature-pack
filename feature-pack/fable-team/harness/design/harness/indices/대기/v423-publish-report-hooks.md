# 인덱스: 보드 발행 + planner 보고 의무 훅 — byz_thread_post update · ft-board-publish.sh · report-coverage(Stop) · drain-before-interview(PreToolUse) · 미러 할 일 금지 + Haiku 5.5 · ①~④ 항상 ring · 회신 상한 제외 (판정 421·423 · 430·431 · 설계 §2-3·§2-4·§3 나노 3)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 423(오빠 승인 6개: ①종류별 보고 의무 ②미러 할 일 금지+planner 처리 1줄 ③판정·승인·HIL 항상 doorbell ④회신 상한 완화 ⑤인터뷰 전 함 비우기 ⑥보드 planner 미처리 칸) · 421 발행 · 430·431 컨펌(planner #62745 · master #62749)
- 상태: 대기
- 선행: 나노 4(인박스 · nano/v425-master-inbox) 랜딩 · 나노 2(상태판 · 대기/v421-board.md) 랜딩 — 이 카드는 ft-inbox.sh 와 ft-board.py 를 «호출»만 한다(술어·스냅샷 재구현 0).
- 시험 입력: 임시 FT_ROOT(가짜 인박스 큐 파일 · 가짜 mailbox.jsonl) + 가짜 Stop/PreToolUse 훅 JSON 입력(session_id · transcript_path 픽스처 · stop_hook_active) + 스텁 env(FT_BOARD_BIN · 가짜 슬랙 API base `--api-base http://127.0.0.1:<빈 포트>` 또는 PATH 스텁) + 요약기 스텁 명령 — 실제 슬랙·claude 호출 0
- 기준값: AUDIT-r34 — planner 읽고 콘솔 미보고 10/39(26%) · 발신 상한 RATE_LIMIT 5건/60초에 7회 막혀 전부 --force · 슬랙 요약기가 처리된 일을 「판정 부탁」으로 표시 · `scripts/harness-install/slack-mirror/mirror_summary.py:17` 모델 claude-haiku-4-5-20251001

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
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/teams/harness/DA-news-board-20261009.md §2~§8 · N2 유한 훅(턴 키 1회)·오류 가시성·#seq 직접 참조·pending/미보고 분리 = 수락 · N2 잔여는 설계 §8 정본 술어로 고정 · N3 APPROVE) → 오빠 컨펌 GO 판정 430·431(planner #62745 · master #62749) · 잔여는 완료 조건 시험으로 닫고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#14

## 조사 근거
- `design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md:43`~`:47` 보드 스레드(뿌리 1개/날 · chat.update · 스냅샷 먼저 · 답글 실패 복구 · 날짜 동결 · 발행 시점) · `:50`~`:57` R34 훅 2종·미러·mbox·보드 칸 · `:72` 나노 3 시험 목록 · `:143`~`:146` 정본 술어·필수 가짜 시험·턴당 1회 상한.
- `scripts/harness-install/slack-mirror/thread_post_args.py:26` 서브명령 자리(start·progress·result·check·repair) · `scripts/harness-install/slack-mirror/byz_thread_post.py:70` cmd_start(장부 키·뿌리 글 꼴) — update 는 같은 장부 키 `board:<날짜>` 를 쓴다.
- `scripts/harness-install/slack-mirror/mirror_summary.py:17` DEFAULT_CMD 모델 · `:23`~`:27` PROMPT 의 todo 생성 지시 · `:54` todo 정규화 · `scripts/harness-install/slack-mirror/byz_mbox_slack_mirror.py:74` _close_answered · `:122` _row(행 게시).
- `tools/comm-canonical/mbox.py:386` 발신 상한 RATE_LIMIT 계산 · `tools/comm-canonical/mbox.sh:147` send 의 notify 결정 자리.
- `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:1` PreToolUse 훅 꼴(입력 JSON · deny 출력) · `scripts/harness-install/fable-team/templates/hooks/context-distill-gate.sh` 턴 단위 상태 파일 관례.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. 보드 발행:
   - `scripts/harness-install/slack-mirror/thread_post_args.py` + `byz_thread_post.py`: 서브명령 `update --key board:<날짜> --text-file <f>` — 장부에 키 없으면 뿌리 글 생성(start 와 같은 경로) · 있으면 `chat.update` 로 뿌리 본문 교체 · `--reply "<1줄>"` 이면 그 뒤 스레드 답글 1개. update 성공 · 답글 실패 = rc 3 + 장부에 `reply_pending` 기록(다음 update 가 «직전 답글 누락 snap=…» 을 함께 냄).
   - `scripts/fable-team-bin/ft-board-publish.sh` 신설(+ kit 사본): `ft-board.py snapshot` rc≠0 → 발행 0 · rc 그대로 종료 / rc 0 → `ft-board.py render --slack` 본문으로 `update` + changes 비지 않으면 변화 답글(`changes` 1줄 요약 + `snap=<전>→<후>`) · 날짜 첫 발행이면 전날 뿌리 글 끝에 `prev_day_last` 를 박고 동결(update 1회 · 이후 전날 키 갱신 0). 입력 해시가 같아도 `reply_pending` 이 있으면 막지 않는다.
2. planner 훅 2종(`scripts/harness-install/fable-team/templates/hooks/` · 실제 등록은 master 집행):
   - `report-coverage.sh`(Stop): 턴 키 = 세션 id + 이번 사용자 턴 첫 레코드 uuid(transcript_path 에서 마지막 user 레코드만 · 본문 파싱 0) · ①최종 답변 텍스트의 `#<seq>` 직접 표기(정규식 `#[0-9]{4,}` · 인용 블록 `>` 줄 안은 제외)를 모아 `ft-inbox.sh report <seq…>` ②`ft-inbox.sh show <me>` 에서 ①~④ 중 술어 거짓인 줄이 있으면 → 그 턴 키로 처음이면 block(사유 「#a·#b 를 mark 하고 보고에 #seq 로」) · 같은 턴 키 2회째·`stop_hook_active`·조회 실패·기록 실패 = 통과 + `state/inbox/hook-errors.log` 1줄(줄 상태는 그대로 남음). 턴 키 저장 = `state/inbox/stop-<세션>.json`.
   - `drain-before-interview.sh`(PreToolUse · matcher AskUserQuestion): mailbox pending>0 또는 인박스 ①~④ 술어 거짓>0 이면 턴 키당 1회 deny(사유에 pending 수 · 미보고 #seq 목록) · 저장 = `state/inbox/deny-<세션>.json`(Stop 훅 파일과 공유 0) · 같은 턴 재호출·조회/저장 실패 = 통과 + hook-errors.log.
3. 미러 요약기: `mirror_summary.py` — ①DEFAULT_CMD 모델 = `claude-haiku-5-5`(오빠 컨펌값 · 모델 하나 · 폴백 0) ②PROMPT 에서 todo «생성» 지시 삭제 → 「원문에 할 일 문장이 있으면 그대로 복사, 없으면 null」 · HIL 라벨 강제 todo 줄 삭제. `byz_mbox_slack_mirror.py`: planner 발신 행의 본문에 받은 `#seq` 가 있으면 그 seq 의 스레드에 「planner 처리: <첫 문장> (<시각>)」 1줄(새 글 0).
4. mbox(`tools/comm-canonical/mbox.py` · `mbox.sh` — 수정 전 라이브와 바이트 동일 확인 · 다르면 [structure] 동기화 커밋 먼저): ①send 의 notify = 인박스 적재 cls 가 ①~④·미상이면 tick 유무와 무관하게 doorbell(⑤⑥ 은 지금 규칙 그대로) ②RATE_LIMIT 계산(`mbox.py:386`)에서 본문 첫 80자 안에 받은 `#seq`(그 발신자에게 온 쪽지 seq)를 인용한 회신은 셈에서 제외 — 다른 가드(fan-out·재발송 쿨다운)는 그대로.
5. 시험(가짜 FT_ROOT · 스텁 · 실제 슬랙·claude 0):
   - `tests/harness/test_report_hooks.sh`: 미보고 30건 → 같은 턴 키 block 1회 → 2회째 통과 · 줄 상태 유지 / 인용 블록 안 `#seq`·판정 숫자 = report 안 됨 / 30건 중 일부만 mark+#seq → 나머지만 다음 턴 대상 / 묶음 G={S1,S2} S1 만 → G 대상 유지 / 같은 턴 pending 계속 늘어도 deny 1회 / 조회·기록 실패 = 통과 + hook-errors.log 1줄 / 인터뷰 대기 뒤 새 턴(새 uuid) 에 의무 잔존 / stop_hook_active=true 통과.
   - `tests/harness/test_board_publish.sh`: snapshot rc≠0 → update 호출 0 / 카드만 바뀜 → update 1 + 답글 1(snap 전→후) / 답글 실패 → 다음 발행이 누락 snap 함께 냄(입력 해시 같아도) / 날짜 바뀜 → 전날 뿌리 동결 1회.
   - `tests/harness/test_mirror_no_todo.sh`: 요약 스텁이 todo 를 지어내도 원문에 할 일 문장 없으면 「없음」 · planner 회신 행 → 대상 스레드 1줄 · DEFAULT_CMD 에 claude-haiku-5-5.
   - mbox: ①~④·미상 notify=1(tick 없는 좌석 포함) · 회신 6건/60초 RATE_LIMIT 0 · 비회신 6건째 RATE_LIMIT 유지.
   - `test_kit_bin_sync.sh` PASS.

★전역/planner 훅 영향 점검 표 (§57 꼴 · 구현 DA 와 master 설치 전 확인)★
| 점검 | report-coverage(Stop) | drain-before-interview(PreToolUse) |
|---|---|---|
| 입력 차단 가능성 | 턴 키당 block 1회 뒤 무조건 통과 · stop_hook_active 통과 → 영구 루프 0 | 턴 키당 deny 1회 · 같은 턴 재시도 통과 · 인터뷰 취소·변경 0 |
| 팀 밖 세션 | planner 좌석 settings 에만 등록(전역 0) · 인박스 큐 없음 = 무출력 통과 | 같음 |
| 워크트리 판정 | FT_ROOT = git 공용 디렉터리 루트(retired-seat-guard 꼴 · e70527f301) | 같음 |
| 라이브 bin 선행 | ft-inbox.sh 가 라이브 FT_BIN 에 없으면 = 통과 + hook-errors.log(차단 0) · 설치 순서 = 나노 4 bin → 훅 | 같음 |
| 되돌림 | settings 에서 훅 줄 삭제 1개 · 큐·상태 파일은 그대로 | 같음 |

커밋은 자기 브랜치, **push 금지**. **금지**: 실제 슬랙·claude 호출 · 훅 홈·settings 등록(master 집행) · 술어·스냅샷 재구현(ft-inbox.sh·ft-board.py 호출만) · transcript 본문 파싱(마지막 user 레코드 uuid 와 최종 답변 텍스트만) · 요약 모델 폴백 · 라이브 .fable-team/comm·state 쓰기 · 전역 settings 등록.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 3종 + mbox 시험 rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n · `ruff check` 0 · 새 파일 200줄 이하.
- RESULT 에 ★「미보고 30건 block 1회 → 2회째 통과 · 줄 상태 유지」★ 출력 2줄 + ★「snapshot rc≠0 → update 0」★ 1줄 복붙 — 구현 DA 가 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_report_hooks.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN·comm·slack-mirror 반영 · planner 좌석 settings 에 훅 2종 등록 · 미러 launchd 재시작 · ft-news-tick 호출부를 ft-board-publish.sh 로 교체 · 첫 적용 planner 1팀 2일(설계 §6-4 지표: 누락 0 · doorbell 수/시간).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#14 · 판정 421·423 설계 r2 §2-3·§2-4·§3 나노 3 · 오빠 컨펌 판정 430·431 · master #62749).
- 정본 영향 없음: 하네스 도구·훅·미러·시험만 — docs/architect 제품 정본 변경 없음.
