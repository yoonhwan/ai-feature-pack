# 인덱스: v423b planner 보고 의무 훅 2종 — report-coverage(Stop · 턴 키당 block 1회 · 최종 답변 #seq → ft-inbox report) · drain-before-interview(PreToolUse AskUserQuestion · 턴 키당 deny 1회) (판정 423 ①⑤ · 430·431 · 설계 §2-4 · v423 분할 2/3)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 423(오빠 승인 6개: ①종류별 보고 의무 ②미러 할 일 금지+planner 처리 1줄 ③판정·승인·HIL 항상 doorbell ④회신 상한 완화 ⑤인터뷰 전 함 비우기 ⑥보드 planner 미처리 칸) · 421 발행 · 430·431 컨펌(planner #62745 · master #62749)
- 상태: 대기
- 선행: v425 인박스 랜딩(완료 · #929 b8275bf997 · `ft-inbox.py` show·mark·report·obligation_closed 실재) · v423a 랜딩 뒤 착수(순서만 · 파일 겹침 0)
- 시험 입력: 임시 FT_ROOT(가짜 인박스 큐 파일 · 가짜 mailbox.jsonl) + 가짜 Stop/PreToolUse 훅 JSON 입력(session_id · transcript_path 픽스처 · stop_hook_active) + 스텁 `ft-inbox.sh` — 실제 claude·tmux 0
- 기준값: AUDIT-r34 — planner 읽고 콘솔 미보고 10/39(26%) · 훅 0(`scripts/harness-install/fable-team/templates/hooks/` 에 report·drain 이름 0)
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
- `design/harness/DESIGN-news-tree-workqueue-viz-20261009.md:50`~`:57` R34 훅 2종 · `:143`~`:146` 정본 술어·필수 가짜 시험·턴당 1회 상한.
- `scripts/fable-team-bin/ft-inbox.py:4` 명령(ingest·show·mark·report·archive) · `:128` cmd_report · `scripts/fable-team-bin/ft_inbox_core.py` obligation_closed(술어 재구현 0 — `show` 출력·`report` 호출만).
- `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:1` PreToolUse 훅 꼴(입력 JSON · deny 출력) · `scripts/harness-install/fable-team/templates/hooks/context-distill-gate.sh` 턴 단위 상태 파일 관례.
- 판정 514(루트 지침 · governance §9 B): planner 는 큐가 비면 오빠께 AskUserQuestion 으로 «다음 일»을 묻는다 — drain-before-interview 는 그 인터뷰 직전에 함을 비우게 하는 쪽이라 충돌 0(팀 master 의 `[완료·휴식]` 쪽지도 인박스 줄 — 분류는 `rule_class` 그대로).

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. planner 훅 2종 — 새 파일 `scripts/harness-install/fable-team/templates/hooks/report-coverage.sh` · `scripts/harness-install/fable-team/templates/hooks/drain-before-interview.sh`(꼴 = 기존 `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh` · 호출만 하는 기존 도구 = `scripts/fable-team-bin/ft-inbox.sh`(`show`·`report` · 본체 `scripts/fable-team-bin/ft-inbox.py` 수정 0) · 실제 등록은 master 집행):
   - `report-coverage.sh`(Stop): 턴 키 = 세션 id + 이번 사용자 턴 첫 레코드 uuid(transcript_path 에서 마지막 user 레코드만 · 본문 파싱 0) · ①최종 답변 텍스트의 `#<seq>` 직접 표기(정규식 `#[0-9]{4,}` · 인용 블록 `>` 줄 안은 제외)를 모아 `ft-inbox.sh report <seq…>` ②`ft-inbox.sh show <me>` 에서 ①~④ 중 술어 거짓인 줄이 있으면 → 그 턴 키로 처음이면 block(사유 「#a·#b 를 mark 하고 보고에 #seq 로」) · 같은 턴 키 2회째·`stop_hook_active`·조회 실패·기록 실패 = 통과 + `state/inbox/hook-errors.log` 1줄(줄 상태는 그대로 남음). 턴 키 저장 = `state/inbox/stop-<세션>.json`.
   - `drain-before-interview.sh`(PreToolUse · matcher AskUserQuestion): mailbox pending>0 또는 인박스 ①~④ 술어 거짓>0 이면 턴 키당 1회 deny(사유에 pending 수 · 미보고 #seq 목록) · 저장 = `state/inbox/deny-<세션>.json`(Stop 훅 파일과 공유 0) · 같은 턴 재호출·조회/저장 실패 = 통과 + hook-errors.log.

★전역/planner 훅 영향 점검 표 (§57 꼴 · 구현 DA 와 master 설치 전 확인)★
| 점검 | report-coverage(Stop) | drain-before-interview(PreToolUse) |
|---|---|---|
| 입력 차단 가능성 | 턴 키당 block 1회 뒤 무조건 통과 · stop_hook_active 통과 → 영구 루프 0 | 턴 키당 deny 1회 · 같은 턴 재시도 통과 · 인터뷰 취소·변경 0 |
| 팀 밖 세션 | planner 좌석 settings 에만 등록(전역 0) · 인박스 큐 없음 = 무출력 통과 | 같음 |
| 워크트리 판정 | FT_ROOT = git 공용 디렉터리 루트(retired-seat-guard 꼴 · e70527f301) | 같음 |
| 라이브 bin 선행 | ft-inbox.sh 가 라이브 FT_BIN 에 없으면 = 통과 + hook-errors.log(차단 0) · 설치 순서 = 나노 4 bin → 훅 | 같음 |
| 되돌림 | settings 에서 훅 줄 삭제 1개 · 큐·상태 파일은 그대로 | 같음 |
2. 시험:
   - `tests/harness/test_report_hooks.sh`: 미보고 30건 → 같은 턴 키 block 1회 → 2회째 통과 · 줄 상태 유지 / 인용 블록 안 `#seq`·판정 숫자 = report 안 됨 / 30건 중 일부만 mark+#seq → 나머지만 다음 턴 대상 / 묶음 G={S1,S2} S1 만 → G 대상 유지 / 같은 턴 pending 계속 늘어도 deny 1회 / 조회·기록 실패 = 통과 + hook-errors.log 1줄 / 인터뷰 대기 뒤 새 턴(새 uuid) 에 의무 잔존 / stop_hook_active=true 통과.
   - `test_kit_bin_sync.sh` PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: 실제 슬랙·claude 호출 · 훅 홈·settings 등록(master 집행) · 술어·스냅샷 재구현(ft-inbox.sh·ft-board.py 호출만) · transcript 본문 파싱(마지막 user 레코드 uuid 와 최종 답변 텍스트만) · 요약 모델 폴백 · 라이브 .fable-team/comm·state 쓰기 · 전역 settings 등록.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_report_hooks.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n · 새 파일 200줄 이하.
- RESULT 에 ★「미보고 30건 block 1회 → 2회째 통과 · 줄 상태 유지」★ 출력 2줄 복붙 — 구현 DA 가 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_report_hooks.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다(그 뒤 커밋·추가 확인 0).
- 랜딩 뒤 master 집행(카드 밖): 구현 DA(카드 「사전검증」 — 잔여 N2 는 구현 DA 에서 재확인) · planner 좌석 settings 에 훅 2종 등록(전역 0) · 첫 적용 planner 1팀 2일(설계 §6-4 지표: 누락 0).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 44e45993f6159038efbaa75e2288c958ed034f00 (spawn 2026-10-08)
- 2026-10-08 — 원 카드 대기/ 생성 (byz-harness-arch-claude#14 · 판정 421·423 설계 r2 §2-3·§2-4·§3 나노 3 · 오빠 컨펌 판정 430·431 · master #62749).
- 2026-10-08 23:0x — v423 원 카드(나노 3 · 구현 범위 5덩어리 · 시험 4종)를 arch#18 이 3장으로 분할(판정 545 순서 ① · master#18 #65524): v423a 보드 발행 → v423b planner 보고 훅 → v423c 미러 요약기·mbox. 설계·DA·오빠 컨펌(430·431) 범위 변경 0 · 원 카드 글자는 각 카드에 그대로 옮김 · 참조 줄 origin/main dbbf096099 기준 재확인.
- 2026-10-08 23:2x — spawn lint REJECT(master#19 #65691 · 구현 범위에 실재 경로 0) → 새 훅 2 전체 경로 + 실재 기존 파일 3 인용(arch#18 · 범위 변경 0).
- 정본 영향 없음: 하네스 도구·훅·미러·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 23:13 — 대기→진행 · 좌석 byz-harness-nano-v423b-report-hooks#0
- 2026-10-08 23:5x — 완료 증거(DA r2 APPROVE): 세트: 8567db092392521683d3e2bc2de8c8fc0d5eb284 · 시험: bash tests/harness/test_report_hooks.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 훅·시험만 — docs/architect 제품 정본 변경 없음.
