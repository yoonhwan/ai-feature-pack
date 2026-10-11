# 인덱스: 쪽지 가드 — 은퇴·닫힌 수신자 REJECT + planner 앞 허용 머리 집합 + [결정] 3줄 lint (N3 · 팀 운영 구조 근원 수정 · 판정 1070·1079 · arch#29)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → planner ORDER(판정 1069·1070) · 설계 PLAN-harness-networking-20261011.md §2 D3·D4 · 요청 원장 R97(수신자 검증 부재) 흡수
- 제안서: 없음 — 오빠 판정 1070 으로 착수 승인된 하네스 구조 수정(판정 1079 3차 DA APPROVE #76290)
- 상태: 대기
- 선행: N1 랜딩(측정 스크립트가 효과 숫자를 잰다) · 설계 = `git show f0d974ab20:design/harness/PLAN-harness-networking-20261011.md`(r2 · ★나노 워크트리에는 없다 · 위 명령으로 읽는다★)
- 시험 입력: 명부 픽스처(승계 전/후 · 깨진 JSON · stop-ready/closed/stopped/_retired_role · 중복 키 · `_closed` 팀 `_kept` 보존 · planner 명부 정상+타 팀 깨짐 복합) × 머리별 본문 · `FT_SEND_DRY=1`/임시 큐 폴더 — 실 큐·실 doorbell·루트 `.fable-team/` 쓰기 0
- 기준값(arch#29 실측 · 2026-10-11): planner 앞 쪽지 238/일 중 분류 ⑥진행·참고 76 + ⑤결과 50 = 57% · `[HIL]` 87/일(전 좌석) · `[HIL·merge]` 13 · 옛 이름 send 검증 0(R97) · mbox 정본 `tools/comm-canonical/mbox.sh` = 라이브 `.fable-team/comm/mbox.sh`(R85 `user_facing` 핫픽스 + `.bak-userfacing-1010` 포함) · `ft-seat-retire.sh` 38행 직접 쓰기(원자적 아님).

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
상위 제약(제품 골 · CLAUDE.md ACTIVE TRACK GOAL 바이트 일치): 목표는 빠른 유용 원문, 실시간 교정, N언어의 병렬·독립 발행, 소실·비의도 중복 없는 최종 말풍선이다. / LST ON 우선이며 LST OFF/전환과 기존 M0–M7·통합 조건도 남긴다. / 단순히 실패 사례를 많이 모았다는 이유로 실험을 닫지 않는다.
planner 원문 2(팀 배정·운영 · 베이스-위성 연결 관리) / 닫는 증거(PLAN §8 복붙): 「planner 앞 쪽지/일(238 → ≤60)」 + PLAN §6 N3 「은퇴 이름 send 가 REJECT+후계 이름 · 깨진 명부 REJECT · `[HIL]` 전송 100%」.
골의 축: 근원 ①(승계 때 수신자 샘)·②(오빠 질문 과다)·⑤(수신 누락) — 채택안 A·B·D.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
승계 때 옛 좌석 이름으로 보낸 쪽지가 옛 세션 큐에 쌓여 아무도 못 읽고(실측 planner arch#3→master#4), planner 앞으로는 하루 238통 중 57% 가 쪽지일 필요가 없는 진행·결과 보고라 오빠 창구가 병목이 됐다. 이 카드는 보내는 쪽(`mbox.sh send|relay`)에서 둘을 막는다. ①수신 가능 판정표(PLAN D3): authoritative 명부 = 수신자 이름의 팀 글자로 정한 파일 하나(`byz-<팀>-…`→`seats-<팀>.json` · `byz-v65-`/`ft-v65-`→`seats.json`) — `_replaced_by` 있음 → REJECT rc 3 + `→ 현역 <후계>`(체인 끝까지) · `role ∈ {closed,stopped}` → REJECT · `stop-ready`(은퇴 표시 없음) → WARN+전송 · 행 없음 → WARN `미등록`+전송 · 같은 키 2파일 → REJECT `명부 충돌` · authoritative 파일 파싱 실패 → REJECT `명부 읽기 실패 — 다시 보내라` · 다른 팀 파일 깨짐 → WARN 만. ★안전 보고 우선순위★: 머리 `[HIL]`·`[긴급]` 은 어떤 명부 상태에서도 REJECT 하지 않는다 — 못 읽으면 명시 이름으로 적재+WARN+`.fable-team/state/mbox-guard.log` 1줄, 은퇴가 확실히 읽히면 후계로 «전달»(REJECT 아님). ②planner 앞 허용 머리 집합(PLAN D4 표): `[결정]`(필수 줄 3 `비가역:`·`선례:`·`선택지:` 없으면 REJECT) · `[HIL]`(§7 4항 중 ①②④ 없으면 WARN 만) · `[긴급]` · `[합치기]` · `[정지 레디]`·`[완료]`(증거 줄 없으면 WARN) · `[부팅 보고]` — 그 밖은 REJECT(문장 PLAN D4 그대로) · `[HIL·merge]`→`[합치기]` 자동 치환 2주 · 모드 키 `queues.conf` `planner_head_mode=warn|reject`(기본 warn · warn 은 로그 `.fable-team/state/planner-head.log` + 전송). ③`ft-seat-retire.sh` 쓰기를 tmp+`os.replace` 원자 교체로(동작 무변경). 세부는 PLAN §2 D3·D4 가 정본 — 카드와 PLAN 이 다르면 PLAN 이 이긴다.

## 사전검증
- 소환: 예 — DA byz-harness-da-codex#1 r0 HOLD #76217 · r1 HOLD #76265 · r2 APPROVE #76290(판정 1079) — arch 서명 byz-harness-arch-claude#29
- 조사 근거: `tools/comm-canonical/mbox.sh`(send/relay 분기 · `notify_policy`·`user_facing`·`inbox_must_ring`) · `.fable-team/comm/mbox.py`·`queues.conf` · `scripts/fable-team-bin/ft-seat-retire.sh`(28~38행) · `scripts/fable-team-bin/ft_inbox_core.py`(분류 ①~⑥ 정규식 · 머리 표와 충돌 0 확인) · 기존 시험 `tests/harness/test_mbox*.sh`(있으면 꼴 재사용)
- 7초 룰 점검(판정 666): 외부 호출 0(명부 json·큐 파일만)

## 구현 범위 (닫힌 목록 · 나노 · PLAN §6 N3 · 한 번에 하나)
관련 파일(기존 · origin/main 실재 · 나노 base): tools/comm-canonical/mbox.sh · scripts/fable-team-bin/ft-seat-retire.sh · scripts/fable-team-bin/ft_inbox_core.py · tests/harness/test_mbox_py_link_import.sh
1. ①시험 빨강 먼저 — 새 `tests/harness/test_mbox_guard.sh` + 픽스처 `tests/fixtures/mbox_guard/`(명부 8종 × 머리 8종 기대 rc 표 · 복합 3: planner 정상+타 팀 깨짐 / planner 깨짐 / 수신자 은퇴+`[HIL]`) · retire 원자성(쓰기 중 kill 흉내 → 원본 무손상). 이 커밋에서 rc≠0(빨강).
2. ②`tools/comm-canonical/mbox.sh`(정본) — send/relay 앞단에 수신 판정 함수 + planner 머리 함수(각 ≤40줄 · 파일 200줄 넘으면 `mbox_guard.sh` 로 분리해 `source`) · R85 `user_facing` 동작 무변경 · `queues.conf` 키 1개 추가(기본 warn).
3. ③`scripts/fable-team-bin/ft-seat-retire.sh` 38행 — tmp 파일 + `os.replace` (1 hunk · 출력 무변경).
4. ④미러: `scripts/harness-install/fable-team/bin/` + 정본 사본 경로(`tools/comm-canonical/check-drift.sh` 가 보는 자리) `cmp` 0.

커밋은 자기 브랜치(단계별 · [test]→[feature]→[structure] 분리), **push 금지**. **금지**: 라이브 `.fable-team/comm/mbox.sh`·루트 `.fable-team/` 쓰기(설치는 master · 백업 `.bak-networking-<ts>`) · 실 큐 전송 · doorbell 규칙(`notify_policy`·`user_facing`) 변경 · 분류 ①~⑥·보고 의무 훅 변경 · 위 목록 밖 파일 수정 0.

## 완료 조건 (닫힘 판정 기준)
- `bash tests/harness/test_mbox_guard.sh` rc=0 · 기존 `tests/harness/test_mbox*.sh` rc=0 · `bash -n` · 미러 `cmp` 0 · `tools/comm-canonical/check-drift.sh` 가 보는 사본 동일.
- 카드 증거 줄(«세트:» 로 시작 · 접두 없음): 세트: <40hex> · 시험: bash tests/harness/test_mbox_guard.sh rc=0 · 이슈: 0
- 루트 지침: 완료 그 턴에 증거 줄 + arch#29 에 `[완료·휴식]` 1통.

## 상태
- base: origin/main 32d0374ed0e8c600e3c7ae07537cc814be989b60 (arch#29 카드 작성 시점 · spawn 때 `--base origin/main` 으로 다시 고정 · base_sha 줄은 spawn 도구가 쓴다)
- 2026-10-12 — 대기/ 생성 (byz-harness-arch-claude#29 · N3 · 설계 PLAN r2 f0d974ab20 · DA APPROVE #76290 · 판정 1070·1079).
- 정본 영향: 쪽지 정본 mbox.sh 1 + ft-seat-retire 1 hunk · 미러·라이브 설치는 master(.bak-networking) · BOOT 13 글은 S5.
