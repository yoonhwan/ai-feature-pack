# 인덱스: 나노 첫 발주문(ft-nano-spawn BODY)에 「press 금지」 1문장 (R15 T ①)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R15(문구 부분 T · design/teams/harness/PLAN-r15-press-path-enforcement-20261007.md ⑤ 표 3행)
- 상태: 대기
- 선행: 없음
- 시험 입력: 리포 안 두 사본의 BODY 줄(정적 grep) — 실행·네트워크·tmux 0
- 기준값: 없음 → 대체 축 「나노가 받는 첫 발주문에 press 금지 문장이 있는가」 — 지금 0(ft-nano-spawn.sh:218 BODY 에 press 단어 0)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 원문 1 C(업그레이드·커밋·push — 닫는 증거 = 랜딩 sha + 라이브 cmp 0). 핵심 한 줄: 원장 R15 의 문구 부분(T) — 오빠 10-07 「press = tester/checker + 러너 + poller + BTS, 아니면 press 없음 · 나노는 press 하지 않는다」 · arch#8 제안 #60760 → master#11 승인 #60761(①만 · ② SEATBELT 211행은 v65 몫).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
press(라이브 오디오 시험)는 10-07 부터 tester·checker 좌석만 쏜다. 강제 장치는 이미 있다 — `ft-press-gate.sh` ⑦ 이 좌석 이름의 역할 토막을 읽어 tester·checker 가 아니면 거부한다(R15 H · PR 874). 그런데 나노가 처음 받는 발주문(`ft-nano-spawn.sh` 218행 BODY)에는 press 이야기가 한 줄도 없어서, 나노는 게이트에 막힌 «뒤에야» 금지를 안다. 이 카드는 BODY 에 1문장을 넣어 «시작할 때» 알게 한다. 동작 변화는 0이다(문자열 1문장 추가). spawn 의 `--dry-run` 은 159행에서 끝나 BODY 를 출력하지 않으므로 시험은 두 사본의 BODY 줄을 정적으로 읽는다.

## 사전검증
- 소환: 아니오
- 면제: 발주 문자열 1문장 추가이고 제어 흐름·인자·종료코드 변화 0이다. 되돌림 1커밋 revert + 라이브 cp. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#8

## 조사 근거
- `scripts/fable-team-bin/ft-nano-spawn.sh:218` `BODY="[Seatbelt 발주] …"` — press 단어 0 · 220행 `ft-send-verified.sh "$NAME" "$BODY"` 로 나노 창에 감.
- `scripts/fable-team-bin/ft-nano-spawn.sh:159` `--dry-run` 은 여기서 exit 0 — BODY 미출력(시험은 정적 grep).
- `scripts/fable-team-bin/ft-press-gate.sh:25` ⑦ 좌석 역할 — press 는 tester·checker 좌석만 · 조회 실패 fail-closed.
- `tests/harness/test_role_spawn_name.sh:62` 비슷한 문장 시험 꼴(BODY 줄에서 문장 grep) — 단 그건 role-spawn 의 dry-run 출력이고, nano-spawn 은 정적 grep.
- `tests/harness/test_kit_bin_sync.sh:7` 추적본 ⊂ 키트(바이트·모드).

## 구현 범위 (이 셋만 — 닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/fable-team-bin/ft-nano-spawn.sh` 218행 BODY 문자열 안, 「산출 경로를 mbox 로 $FROM 에.」 바로 뒤에 아래 1문장을 그대로 넣는다(따옴표·`$` 0 — 셸 확장 없음):
   `★press(라이브 오디오 시험) 금지 — 나노는 쏘지 않는다(ft-press-gate ⑦ 이 tester·checker 좌석만 허가 · 오빠 10-07) · 시험은 단위·캡처·기존 로그만, press 가 필요하면 산출에 「press 필요: <무엇을 볼지>」 1줄로 적어 $FROM 에 넘긴다★`
   ★예외: 마지막 `$FROM` 은 기존 BODY 와 같은 확장(발주자 좌석 이름)이다.★ 줄 수 변화 0(같은 줄 안).
2. `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh` — 1과 같은 바이트.
3. 시험 `tests/harness/test_nano_spawn_body_press.sh` 신규(정적 · 실행 0):
   - 두 사본 각각 `^BODY=` 줄 1개 · 그 줄에 `press(라이브 오디오 시험) 금지` 와 `ft-press-gate ⑦` 이 있다.
   - 두 사본 `cmp` 동일 · `bash -n` OK.
   - 음성 대조: mktemp 복사본에서 그 문장을 지우면 시험 함수가 FAIL 을 낸다.
   - 기존 무변화 rc=0: `tests/harness/test_kit_bin_sync.sh` · `tests/harness/test_nano_team_env.sh` · `tests/harness/test_live_bin_drift_check.sh`.

커밋은 자기 브랜치, **push 금지**. **금지**: BODY 의 다른 문장 수정 · 게이트·훅 변경 · SEATBELT-README·docs/rules 수정(v65·문서 몫 — 아래) · 라이브 FT_BIN 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_spawn_body_press.sh` rc=0 · 위 기존 시험 rc=0 · 두 사본 cmp 동일.
- RESULT 에 바뀐 BODY 줄의 새 문장 부분 복붙 1줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_nano_spawn_body_press.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): main 병합 → fetch → 라이브 bin 에 ft-nano-spawn.sh cp → `ft-live-bin-drift-check.sh` OK.
- 카드 밖 정본 충돌 2곳(v65·문서 몫 · master 가 planner 경유 통지): `design/v65/SEATBELT-README.md:211` 규칙 15 「press 를 쏜 나노가 그 회차의 tester·checker」 · `docs/rules/single_set_testing.md:25` 「나노의 press 는 §3 ② 뒤에만 … 쏜다」 — 둘 다 10-07 「나노 press 0」 과 충돌.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 06d3d70b3240389f0fac825b3440d5420c106572 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#8 · 원장 R15 T ① · master#11 #60761). spawn 은 master 판단.
- 정본 영향 없음: 하네스 나노 발주 문자열·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 00:37 — 대기→진행 · 좌석 byz-harness-nano-r15t-nano-body-no-press#0
- 2026-10-08 — 증거(나노 r15t-nano-body-no-press · 골 축 원문 1 C · 원장 R15 T ① · master#11 독립 검증 #60775 · arch#8 재현):
  - 변경: ft-nano-spawn.sh BODY 218행 안 1문장 삽입(「산출 경로를 mbox 로 $FROM 에.」 뒤 · 그 밖 바이트 0 변경 — arch 대조 exact-insert True) — 추적본=키트 cmp 동일 · tests/harness/test_nano_spawn_body_press.sh 신규(정적 grep + 음성 대조).
- 세트: 613122a5ccbff052e3a5ac6954d5b0328d2f0aa7 · 시험: bash tests/harness/test_nano_spawn_body_press.sh rc=0 · 이슈: 0
- 추가 시험: test_kit_bin_sync · test_nano_team_env · test_live_bin_drift_check 전부 rc=0(master) · arch 재현 test_nano_spawn_body_press ALL PASS(음성 대조 포함).
- 정본 영향: 하네스 나노 발주 문자열·시험만 — docs/architect 제품 정본 변경 없음 · 정본 충돌 2곳(design/v65/SEATBELT-README.md:211 · docs/rules/single_set_testing.md:25)은 v65·문서 몫으로 planner 경유 통지(master#11) · 라이브 ft-nano-spawn.sh cp 는 master 집행(main 병합 → fetch → cp → drift-check OK).
- 2026-10-08 00:40 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§40
