# 인덱스: v558 인박스 «면제(waived)» — 판정이 정한 옛 백로그를 보고 의무에서 뺀다 · reported 거짓 표시 0 · 정본 술어 한 곳 (판정 558 ④ · master#19 쪽지 #65914)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 558 ④(planner 인박스 21:38 이전 79건 = 훅 술어에서 제외 · reported 거짓 표시 0)
- 상태: 대기
- 선행: v423b 랜딩(완료 · PR 1023 · 73d9c25819) · ★v423b 훅 planner 등록은 이 카드 랜딩 + master 의 79건 면제 집행 «뒤»★
- 시험 입력: `tests/harness/test_inbox.sh` 의 임시 FT_ROOT(가짜 mailbox · 가짜 큐) — 라이브 `.fable-team/state/inbox` 접촉 0
- 기준값: (arch#19 실측 · 라이브 읽기 전용 23:5x · `state/inbox/byz-planner-master-claude.jsonl` 314줄): 21:38 이전 ①~④ = **79줄 전부 mark=보류 · reported=false → 술어 거짓(열림)** · 21:38 이전 ⑤⑥·미상 mark 없음 133줄 · 이후 ①~④ 46줄 · 이후 그 밖 56줄.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — planner 가 읽고 안 올리는 26% · v423b 훅을 켜기 위한 선행). 핵심 한 줄: 판정 번호가 붙은 «면제» 만 보고 의무를 닫는다 — 보고했다고 거짓으로 적지 않고, 술어는 한 곳에서만 바뀐다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
정본 술어 `obligation_closed(line) = mark != null ∧ (cls ∉ {①,②,③,④} ∨ reported == true)`(`scripts/fable-team-bin/ft_inbox_core.py:77-79`)는 show·archive·묶음과 보드 미보고 칸(`ft_board_env.py:88` — show 줄 수)이 모두 부르는 하나뿐인 술어다. v423b 훅(report-coverage)도 `ft-inbox show` 로만 «열린 ①~④» 를 본다. 판정 558 ④는 v423b 설치 전 쌓인 옛 79건을 의무에서 빼라고 했고 «reported=true 거짓 표시는 0» 이어야 한다. 두 길 중 ⓐ훅 쪽 시각 필터는 쓰지 않는다 — 훅이 술어를 일부 재구현하게 되고(v423b 금지 사항), 보드 미보고 칸과 archive 는 여전히 79건을 열린 것으로 봐 화면 셋이 서로 다른 답을 낸다. ⓑ정본 술어에 «면제» 한 항을 더한다: 줄에 `waived = {"by": "판정 N", "ts": …}` 가 있으면 닫힘. 면제는 새 명령 `waive` 로만 붙고, mark 가 이미 있는 줄에만, 판정 번호가 있는 사유로만 붙는다. reported 는 건드리지 않으므로 «보고함» 기록은 거짓이 되지 않는다. 술어가 한 곳이라 훅·보드·archive 가 같은 답을 낸다.

## 사전검증
- 소환: 아니오
- 면제 사유: 정본 술어에 «명시 면제» 1항 추가(기존 닫힘 조건 불변 · 면제 없는 줄 동작 0 변경) · 면제는 명시 명령 + 판정 번호 필수 · 되돌림 = waived 필드 삭제 1줄 — 구현 DA 1회(bounded · 아래 Q1~Q2)로 닫는다 — arch 서명 byz-harness-arch-claude#19
- 구현 DA 질문(고정): Q1 면제가 판정 번호 없이·mark 없이·다른 좌석 큐에·`--before` 경계 밖 줄에 붙는 경로 · Q2 면제 없는 줄의 술어·show·archive·보드 미보고 셈이 바뀌는 경로.

## 조사 근거 (origin/main 73d9c25819 · arch#19)
- `scripts/fable-team-bin/ft_inbox_core.py:77-79` obligation_closed · `:82-83` group_closed (129줄).
- `scripts/fable-team-bin/ft-inbox.py:122-125` cmd_mark(사유 필수) · `:128-129` cmd_report · `:132-145` cmd_archive(술어 거짓 = REFUSED) · `:149-166` main 분기·usage (170줄).
- `scripts/fable-team-bin/ft_board_env.py:88` 미보고 = show 줄 수(술어 재작성 0) — 이 카드로 자동 반영, 수정 0.
- 시험 `tests/harness/test_inbox.sh`.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft_inbox_core.py` `obligation_closed`: `… ∨ line["reported"] is True ∨ line.get("waived") is not None` 1항 추가(독스트링에 「판정 558 ④ · 명시 면제」 1줄). `mark is not None` 전제는 그대로(면제도 mark 필수).
2. `scripts/fable-team-bin/ft-inbox.py` 새 명령 `waive <좌석> --before <ISO ts> "<사유>"`:
   - 사유에 `판정 [0-9]+` 가 없으면 rc=2(usage). 그 좌석 큐(`qpath` · 잠금 안)에서 `ts < --before` ∧ `mark is not None` ∧ `not obligation_closed` 인 줄에만 `waived={"by": <사유>, "ts": now}`. reported 불변.
   - 출력 `WAIVED n seq=<…>` + 대상 밖으로 남은 «경계 안 mark 없음» 줄 수 `SKIPPED_NO_MARK m`(조용히 넘기지 않는다). `--before` 형식 오류 = rc=2.
   - usage 문자열 두 곳(`:4` 머리말 · `:166`)에 `waive` 추가. 파일 200줄 이하 유지.
3. 키트 사본 `scripts/harness-install/fable-team/bin/ft_inbox_core.py` · `ft-inbox.py` 같은 바이트.
4. 시험 새 `tests/harness/test_inbox_waive.sh`(기존 `tests/harness/test_inbox.sh` 193줄이라 추가 불가 · 같은 픽스처 꼴):
   - ⓐ ①~④ mark=보류 · ts 경계 전 3줄 + 경계 후 1줄 → waive 뒤 앞 3줄 show 에서 사라짐 · 뒤 1줄 남음 · 4줄 모두 reported=false 그대로.
   - ⓑ 사유에 판정 번호 없음 → rc=2 · 변경 0. ⓒ mark 없는 경계 전 줄 → 면제 0 · `SKIPPED_NO_MARK 1`.
   - ⓓ 다른 좌석 큐 불변. ⓔ waive 뒤 archive → 면제 줄 이동(REFUSED 0) · 이동본에 waived·reported=false 보존.
   - ⓕ 면제 없는 줄의 show·archive 출력이 변경 전과 바이트 같음(대조 실행). ⓖ 묶음: 같은 group 에 경계 전 1줄 + 경계 후 1줄 → group_closed 거짓 유지.
   - 기존 `tests/harness/test_inbox.sh` · `tests/harness/test_report_hooks.sh` · `tests/harness/test_kit_bin_sync.sh` PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: reported 를 true 로 쓰는 경로 · 훅(report-coverage·drain) 수정 · 시각 필터를 술어 밖(훅·보드)에 두기 · 라이브 `.fable-team/state/inbox` 쓰기(79건 면제 집행은 master · 카드 밖).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 rc=0(위 4) · `bash -n` · `ruff check` 0 · 사본 cmp · 고친 파일 200줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_inbox_waive.sh rc=0 · 이슈: 0`.
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp+cmp → `ft-inbox.sh waive byz-planner-master-claude --before 2026-10-08T21:38 "판정 558 ④ — v423b 설치 전 백로그"` → 출력 `WAIVED 79` 확인(다르면 멈추고 보고) → show ①~④ 열린 줄 = 21:38 이후 줄만 → 그 뒤 v423b 훅 planner 등록(판정 558 · 등록 보류 해제 판단은 master).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 2fca4abc0cff06bc6fc490c0f0ac6cdfe86b3485 (spawn 2026-10-09)
- 2026-10-08 23:5x — 대기/ 생성 (byz-harness-arch-claude#19 · 판정 558 ④ · master#19 쪽지 #65914 · 술어 제외 방식 = 정본 술어 «명시 면제» 1항(훅 쪽 필터 기각) · v555 와 묶지 않음(파일·검토자·선행 다름 — 이 카드가 v423b 훅 등록의 선행이라 v555 보다 앞 순서 권고)).
- 범위 밖(관찰만): 21:38 이전 ⑤⑥·미상 mark 없음 133줄은 훅 대상이 아니지만 보드 미보고 칸에는 잡힌다 — 정리(mark) 여부는 planner 판단.
- 정본 영향 없음: 하네스 인박스 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 00:01 — 대기→진행 · 좌석 byz-harness-nano-v558-inbox-waive-backlog#0
- 2026-10-09 00:xx — 완료 증거(DA r1 APPROVE): 세트: 7a6d8f4152c74aa48bedd624bc3a61e43f1ede7b · 시험: bash tests/harness/test_inbox_waive.sh rc=0 · 이슈: 0
- 정본 영향 없음: 하네스 인박스 도구·시험만 — docs/architect 제품 정본 변경 없음.
