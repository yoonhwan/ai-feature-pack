# 인덱스: 메인팀 인박스 — ft-inbox.sh(ingest·show·mark·report·archive·--compact) · 분류 기준표 · 중복 묶기 · 정본 술어 obligation_closed (판정 425-B · 430 · 설계 §6 · §8)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 425-B·430(오빠 「인박스=스크립트 큐+Haiku 5.5 일회 호출 · 상시 0」 · planner #62745)
- 상태: 대기
- 선행: 없음(안 = design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md §6-3 · §8) · 나노 1(판정 원장)과 병렬 · 나노 3 은 이 카드 뒤
- 시험 입력: 임시 FT_ROOT(가짜 mailbox.jsonl · bodies/ · 가짜 명부) + 가짜 Haiku(env FT_INBOX_HAIKU 스텁) — 실제 mbox·claude 호출 0
- 기준값: planner 앞 쪽지 55건 중 읽고 콘솔 미보고 10/39(AUDIT-r34) · 같은 내용 재발송 짝 62296/62305 · 62298/62335 · 읽힌 행은 mailbox.jsonl 에서 회전돼 사라짐(#62598)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: A(모니터·오빠 요청 — 「메세지가 밀리고 … 누락하고 하는 문제」). 핵심 한 줄: 쪽지를 계보별 큐에 정렬·묶어 쌓고, «처리 표시 + 보고» 둘 다 될 때만 닫힌다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
master 들은 쪽지가 밀려 메인 작업이 끊기고, 읽은 쪽지가 회전돼 사라지며, 오빠께 안 올라간 채 묻힌다(R34 실측 26%). 상시 LLM 좌석(예전 pm·HELM)은 판단 침범·틱 중복·승계 문제로 실패했기에, 인박스는 «좌석 없는 스크립트 큐 + 애매한 것만 Haiku 5.5 일회 호출»이다. mbox send 가 큐에 넣은 직후 `ft-inbox.sh ingest <seq>` 가 수신 좌석 «계보»(이름의 # 앞) 키 큐 파일에 한 줄을 쌓고(승계로 이름이 바뀌어도 같은 큐), 고정 기준표로 분류한다. 닫힘은 한 함수 `obligation_closed(line) = mark != null ∧ (cls ∉ {①,②,③,④} ∨ reported == true)` 로만 판정하고, show·보드·지표·묶음·archive 가 이 함수를 공유한다(DA r2 잔여 N2). reported 는 나노 3 의 Stop 훅이 최종 답변의 `#seq` 로 true 로 바꾼다 — 이 카드는 필드와 `report <seq…>` 명령까지만. 깨우기 규칙 변경은 나노 3.

## 사전검증
- 소환: 아니오
- 면제: 사전 DA 는 소환됐고 2 HOLD 로 리뷰 종료(bounded_da_review · 판정문 design/teams/harness/DA-news-board-20261009.md §2~§8 · N1·N3 APPROVE · N2 잔여는 설계 §8 정본 술어로 고정) → 오빠 컨펌 GO 판정 430·431(planner #62745 · master #62749) · 잔여는 완료 조건 시험으로 닫고 구현 DA 에서 재확인 — arch 서명 byz-harness-arch-claude#13

## 조사 근거
- `design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md:113` 적재(계보 키 · 줄 형식 · bodies 보존) · `:114` 분류 기준표 ①~⑥·미상 · `:116` 중복 묶기.
- `design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md:118` 닫는 사건 · `:119` 압축(요청 때만·보기 전용) · `:120` 클린업(술어로 닫힌 줄만).
- `design/teams/harness/DESIGN-news-tree-workqueue-viz-20261009.md:143` 정본 술어 obligation_closed + 필수 가짜 시험.
- `tools/comm-canonical/mbox.sh:147` notify_policy 자리(이 카드는 ingest 호출 1줄만) · ★라이브 .fable-team/comm/mbox.sh 가 tools/comm-canonical/mbox.sh 보다 앞서 있음(diff 60줄 실측) — 수정 전 사본을 라이브와 같게 맞추는 [structure] 커밋 먼저★.

## 구현 범위 (닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-inbox.sh`(+ `scripts/harness-install/fable-team/bin/` 사본 · 본체 로직은 같은 디렉터리 ft-inbox.py 허용 · 인자·rc 꼴은 `scripts/fable-team-bin/ft-hil-ask.sh` 관례):
   - `ingest <seq>`: mailbox(+log) 행 → 본문을 bodies/<seq>.txt 에 보존(없으면 복사 · /tmp/mbox 휘발 대비) → 큐 `<FT_ROOT>/.fable-team/state/inbox/<계보>.jsonl` 에 `{seq,ts,from,cls,prio,group,body_path,mark:null,reported:false}`.
   - 분류 = 첫 줄 태그·발신 접두 기준 고정표 ①오빠 원문 ②[HIL]·파괴 승인 ③판정 요청 ④막힘 ⑤결과 ⑥진행·참고 · 안 맞으면 미상 → `${FT_INBOX_HAIKU:-claude -p --model claude-haiku-5-5}` 일회 호출로 라벨만 · 실패 시 미상 유지(①과 ② 사이 · 빼기 0).
   - 묶기 = 같은 from ∧ 정규화 본문 해시(접두·seq·시각 제거) 같음 → 같은 group · 묶인 seq 전부 유지.
   - `show <좌석> [--compact]`: 우선순위 순 · 묶음 1줄(seq 목록 + 원문 경로) · 술어 거짓인 줄만 · `--compact` = Haiku 일회 호출 보기(줄마다 seq+경로 · 큐 무변경).
   - `mark <seq|group> 처리|위임|보류 "<1줄>"` · `report <seq…>`(reported:true) · `archive <좌석>`(술어 참인 줄만 inbox/archive/<계보>-<날짜>.jsonl 로 이동 · 삭제 0).
   - obligation_closed 는 한 함수 · 모든 하위 명령이 그것만 호출.
2. `tools/comm-canonical/mbox.sh`: ①먼저 라이브 사본과 같게([structure] 커밋 · 동작 변화 0) ②send·relay 큐 적재 성공 뒤 ingest 1줄(실패 = stderr WARN · 쪽지 전송 rc 불변).
3. 시험 `tests/harness/test_inbox.sh`: 분류표 6+미상(Haiku 스텁 성공/실패) · 묶음 짝 2쌍 · 계보 키(#9→#10 같은 큐) · ★술어: S(cls③) mark 후 report 없음 → show 유지·archive 이동 거부 → report S → 닫힘·이동 / 묶음 G={S1,S2} 중 S1 만 report → G 미닫힘★ · ⑥ 은 mark 만으로 닫힘 · archive 삭제 0 · ingest 실패가 send rc 불변 · `test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 상시 좌석·데몬 · 인박스 자발 압축·정리 · 원문 대체 요약 · 술어를 하위 명령마다 다시 쓰기 · 라이브 .fable-team/comm·실제 state 쓰기 · 깨우기 규칙 변경(나노 3).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_inbox.sh` rc=0 · `test_kit_bin_sync.sh` PASS · 사본 cmp · bash -n(+ python 이면 ruff).
- RESULT 에 ★술어 시험(mark 후 report 없음 → archive 이동 거부)★ 출력 2줄 복붙 — 구현 DA 가 재확인.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN·comm 반영 · 첫 적용 planner 1팀(누락 0 · doorbell 수/시간 · ingest 50 ms 미만 · 큐 일 1 MB 미만).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: d21481fe6cfb31a37c0be00020755cc36844a0e1 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#13 · 판정 421·423·425-B 설계 r2 §8 · 오빠 컨펌 판정 430·431).
- 정본 영향 없음: 하네스 도구·훅·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 14:43 — 대기→진행 · 좌석 byz-harness-nano-v425-master-inbox#0
- 2026-10-08 — 나노 산출(브랜치 nano/v425-master-inbox · push 금지): ff9172d328 [structure] mbox.sh 라이브 맞춤 → 6daa9f3fd7 [feature] ft-inbox + 훅 + 시험.
- 2026-10-08 — 반송 반영(62810·62817·62822): 97090f6d43 [fix] Haiku 비동기 + 2파일 분리 + mbox 훅 축소.
- 세트: d2ce4b6ff312dda92c9bdcc5aa7259beca5d0789 · 시험: bash tests/harness/test_inbox.sh rc=0 · 이슈: 0
- 2026-10-08 15:08 — 진행→완성 · 좌석 byz-harness-nano-v425-master-inbox#0 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§59
