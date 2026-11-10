# 인덱스: press 게이트 ⑦ 좌석 역할(tester·checker 만) · ⑧ 직전 회차 BTS 표 · 통과 시 좌석 허가 파일 발급 (R15 카드 H)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R15 — v65 master#145 #59389·#59404, 오빠 원문 「bts, poller 없는 press 하는 tester+checker 세션은 없어야한다는게 팩트」. 안 = design/teams/harness/PLAN-r15-press-path-enforcement-20261007.md ⑤ 표 순서 1(카드 H). 이 카드는 «발사 전» 게이트 쪽만 맡는다. PTT 누름 순간의 검사(카드 V)는 v65 소관이라 여기서 다루지 않는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 추적본 `scripts/fable-team-bin/ft-press-gate.sh` + 키트 `scripts/harness-install/fable-team/bin/ft-press-gate.sh` 다. base 에 PR 869 가 들어 있어 두 사본이 같은 바이트(⑥ 기준선 포함)여야 한다. 게이트 구조: 검사 ①~⑥ 이 각각 `say "✓|✗"` 한 줄을 찍고, 막히면 `FAIL=1` · 끝에서 PASS 면 exit 0, BLOCK 이면 exit 1. 자체시험 `FT_PRESS_GATE_SELFTEST=1` 은 ①~⑤ 를 stub 으로 두고 ⑥ 만 실제로 돌린다(성공 3 · 막힘 1). 시험 `tests/harness/test_press_baseline_check.sh` 가 그 SELFTEST 로 ⑥ 을 검사한다. 지금 게이트는 «누가» 부르는지 보지 않는다. 그래서 나노(옛 이름 ft-v65-temp-* 포함)가 press 해도 막히지 않았다(사고: codex 나노의 ad-hoc press.py · poller 0). 또 BTS 4자 표(TESTER-BRIEF-TEMPLATE 「보고 형식」 1: 열 = `축 | 사실 | 시간` · 행 = 아키텍처 문서 / 코드 / 로그 / 화면)를 안 채우고 다음 회차를 쏴도 막는 것이 없다. 기존 `ft-press-permit.sh` 는 «세트·오디오 장치» 허가(C7)라 이 카드와 목적이 다르다 — 건드리지 않는다.

## 사전검증
- 소환: 아니오
- 면제: 안이 arch 승인 PLAN-r15 ②③④ 절에 값까지 고정돼 있고 게이트 단계 추가 2개 + 파일 1개 쓰기라 되돌림이 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#7

## 조사 근거
- `scripts/fable-team-bin/ft-press-gate.sh:17` ⑥·SELFTEST 블록(17–31행) · `scripts/fable-team-bin/ft-press-gate.sh:172` ⑥ 호출·판정(172–180행) — 새 단계는 같은 `say`/`FAIL` 규약.
- `tests/harness/test_press_baseline_check.sh:54` (62·89–99행 포함) — SELFTEST env 조립·기대 exit 패턴. 새 시험은 이 틀을 복사한다.
- `scripts/fable-team-bin/ft-name-lint.sh:1` — 역할 예약어 목록(master arch da tester checker analyst pm nano repro tool) · 이름 형식 `byz-<팀>-<역할>-<에이전트>#N`.

## 구현 범위 (이 넷만 — 닫힌 목록)
1. **⑦ 좌석 역할** — `scripts/fable-team-bin/ft-press-gate.sh` + `scripts/harness-install/fable-team/bin/ft-press-gate.sh`(두 사본 같은 바이트): 함수 `_role_gate`.
   - 좌석 이름 = `FT_PRESS_SEAT` 가 있으면 그 값(시험용), 없으면 `tmux display-message -p -t "$TMUX_PANE" '#{session_name}'`. TMUX_PANE 이 없거나 조회가 실패하면 ✗(fail-closed).
   - 역할 = `byz-<팀>-<역할>-…#N` 의 셋째 토막, 옛 형식 `ft-<팀>-<역할>-…#N` 도 같은 자리. 허용 = `tester`·`checker` 만. 그 밖(`nano`·`temp`·`master`·`arch`…)이나 형식 불일치는 ✗ + 사유 한 줄(「⑦ 역할 <값> — press 는 tester·checker 만(R15)」).
   - 사람 직접 press: `BYZ_PRESS_HUMAN=1` 이면 좌석 판별 대신 통과 + stderr 에 `ERROR` 배너 1줄. 단 TMUX_PANE 이 있고 그 세션 이름이 이름 lint 를 통과하는 좌석이면(좌석이 사람 행세) ✗. ★⑧ 은 사람 경로에도 그대로 적용★(arch#7 판정 · 건너뛰는 것은 ⑦ 하나).
   - ★`FT_PRESS_SEAT` 는 SELFTEST 전용★(arch#7 판정): 보통 모드에서는 읽지 않고, 값이 있기만 해도 ✗ 「⑦ 시험 변수 상속」(⑥ 의 SELFTEST 상속 규약과 같음).
2. **⑧ 직전 회차 BTS 표**: 함수 `_bts_gate`. 입력 = `FT_PRESS_EVID`(이번 회차 증거 폴더 · 없으면 ✗ 「⑧ 증거 폴더 미지정」).
   - 이 좌석의 직전 허가 파일(아래 3)이 있으면 그 `evid` 폴더의 `BTS.md` 를 읽는다. 표 머리 `| 축 | 사실 | 시간 |` 가 있고, 행 `아키텍처 문서`·`코드`·`로그`·`화면` 4개가 모두 있고, 각 행의 사실·시간 칸이 비어 있지 않고 `-`·`TODO`·`?` 가 아니면 ✓. 하나라도 모자라면 ✗ + 모자란 행 이름.
   - 직전 허가가 없으면(첫 회차) ✓ 「⑧ 첫 회차」.
   - 통과하면 이번 `FT_PRESS_EVID/BTS.md` 가 없을 때만 골격(머리 + 4행, 칸은 비움)을 쓴다. 이미 있으면 건드리지 않는다.
3. **허가 파일 발급**: ①~⑧ 이 전부 통과해 PASS 로 끝날 때만 `.fable-team/state/press-permits/<좌석>.json` 을 임시파일 + mv 로 쓴다(`FT_PRESS_PERMIT_DIR` 로 바꿀 수 있음 · 기본 = 게이트 사본 기준 리포 루트, ft-press-permit.sh 의 DIR 계산과 같은 방식). 내용 `{seat, role, runner_head, card, evid, ts}`, 같은 좌석은 덮어쓴다. 이력은 같은 폴더 `permits.log` 에 1줄 append. BLOCK·SELFTEST 일 때는 쓰지 않는다. 사람(BYZ_PRESS_HUMAN) 통과면 좌석 자리에 `human` 을 넣고 `evid/human.txt` 1줄을 쓴다.
   - SELFTEST 블록: ⑦⑧ 은 stub 이 아니라 «실제로» 돈다(⑥ 과 같은 대우). 그래야 시험이 오디오 없이 ⑦⑧ 을 검증한다. 허가 파일은 SELFTEST 에서 쓰지 않는다(exit 3 규약 유지).
4. **시험** `tests/harness/test_press_role_bts_gate.sh` 신규. SELFTEST + `FT_PRESS_SEAT` + mktemp 의 `FT_PRESS_EVID`·`FT_PRESS_PERMIT_DIR` 로 돌리고, 리포 파일 쓰기 0 · 오디오·tmux 0.
   - 사례: 역할 tester → 3 · checker → 3 · nano → 1 · `ft-v65-temp-x#0` → 1 · master → 1 · 형식 불일치 → 1 · FT_PRESS_SEAT·TMUX_PANE 둘 다 없음 → 1.
   - BTS 사례: 직전 허가 없음 → 3 + 골격 BTS.md 생성 · 직전 evid 의 BTS 4행 다 참 → 3 · 화면 행 빈칸 → 1(출력에 「화면」) · 시간 칸 `-` → 1 · FT_PRESS_EVID 없음 → 1.
   - 허가 파일: SELFTEST 에서는 파일 0개.
   - 기존 `test_press_baseline_check.sh` 는 계속 rc=0 이어야 한다(그 시험의 SELFTEST 호출에 `FT_PRESS_SEAT=byz-v65-tester-claude#0`·`FT_PRESS_EVID=<mktemp>` 를 넣는 «시험 쪽 2줄 추가»만 허용 · 기대값 변경 0).

커밋은 자기 브랜치, **push 금지**. **금지**: `ft-press-permit.sh`·`cdp_helper.py`·러너(tests/e2e) 수정(카드 V·v65 소관) · 라이브 FT_BIN·~/.claude/hooks 쓰기 · 역할 검사를 끄는 env(BYZ_PRESS_HUMAN 말고는 우회 0) · 기존 ①~⑥ 출력·판정 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_press_role_bts_gate.sh` rc=0 · `bash tests/harness/test_press_baseline_check.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 두 사본 `bash -n` OK · `cmp` 두 사본 동일.
- RESULT 에 SELFTEST 실제 출력 3개 복붙: tester 통과 · nano 막힘 · 화면 행 빈칸 막힘.
- 카드 증거 줄 형식(필수 · 없으면 반송): `세트: <sha> · 시험: <명령> rc=0 · 이슈: 0`.
- 라이브 설치(FT_BIN 교체)·TESTER-BRIEF 문구(카드 T)·v65 통지는 master 집행 — 카드 범위 밖.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b43dac515fb00e0672be4fc31e89d01f888da117 (spawn 2026-10-07)
- base: PR 869 랜딩 뒤 최신 origin/main(키트 press-gate 에 ⑥ 이 있어야 함 · `cmp` 로 두 사본 동일 확인 후 착수). ★869 랜딩 전 spawn 금지★.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#7 · 원장 R15 · 안 PLAN-r15 ⑤ 카드 H).
- 정본 영향 없음: 하네스 게이트·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 21:07 — 대기→진행 · 좌석 byz-harness-nano-r15-gate-role-bts-permit#0
- 2026-10-07 — 증거(나노 byz-harness-nano-r15-gate-role-bts-permit#0 · 골 축 6-b 원장 R15 · arch#7 재현):
  - 1차 8a46257d97(⑦ 역할 · ⑧ 직전 BTS 표 · 허가 파일) → arch 판정 2건 → 수정 a97075512b(FT_PRESS_SEAT = SELFTEST 전용 · 보통 모드에 값이 있으면 ✗ 「⑦ 시험 변수 상속」 · 사람 경로 ⑧ 유지).
  - 변경 3파일: ft-press-gate.sh 추적본+키트(같은 바이트) · tests/harness/test_press_role_bts_gate.sh(사례 11·12 = 보통 모드 위조 차단 · SELFTEST 정상).
- 세트: a97075512b984ab244147f4b8d93982855ef86fb · 시험: bash tests/harness/test_press_role_bts_gate.sh rc=0 · 이슈: 0
- 추가 시험: bash tests/harness/test_press_baseline_check.sh rc=0 · bash tests/harness/test_kit_bin_sync.sh rc=0 (둘 다 ALL PASS)
- 정본 영향: 하네스 press 게이트(추적본·키트)·시험만 — docs/architect 제품 정본 변경 없음 · 라이브 RT 반영과 TESTER-BRIEF 문구(카드 T)·v65 helper(카드 V)는 범위 밖.
- 2026-10-07 21:17 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§35
