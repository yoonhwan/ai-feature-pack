# 인덱스: tmm 의 bash4 소문자 변환 `${x,,}` 6곳을 bash 3.2 호환으로 + 시험을 /bin/bash 3.2 로도 (R24)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 R24(design/teams/harness/REQUEST-LEDGER.md 9행)
- 상태: 대기
- 선행: 없음
- 시험 입력: 기존 tests/harness/test_tmm_group.sh 의 격리 env(TMM_CATEGORIES·TMM_CAT_SESSIONS) — tmux·~/.tmm 0
- 기준값: 이 Mac /bin/bash 3.2.57 로 test_tmm_group.sh = 실패 18건(전부 `${n,,}: bad substitution` · bash5 는 0건 · arch#8 실측)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 원문 5(머신 독립 배분 — byzs-mac-mini 는 macOS 기본 bash 3.2 · 좌석 운용 «전» 선행). 핵심 한 줄: 원장 R24 — 하네스 시험 32개를 bash5·/bin/bash 3.2 로 각각 돌린 결과 3.2 에서만 실패는 이것 1개(키트 fable-team 은 0) · 야간 자율 안 design/teams/harness/PLAN-night-autonomy-20261008.md 단위 2.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`tmm`(tmux 세션 선택기)의 그룹 탭 라벨 함수 `cat_of()` 는 이름을 소문자로 바꿀 때 bash 4 전용 문법 `${x,,}` 을 쓴다. macOS 기본 `/bin/bash` 3.2 에서는 이 줄이 실행될 때 `bad substitution` 으로 죽는다. `bash -n`(문법 검사)은 이 오류를 못 잡는다 — 실행 때만 드러난다. 이 Mac 은 셔뱅 `#!/usr/bin/env bash` 가 homebrew bash 5 를 잡아 문제가 안 보였고, byzs-mac-mini 처럼 bash 3.2 만 있는 머신에서 처음 터진다. 고칠 것은 소문자 변환 6곳을 `tr` 로 바꾸는 것뿐이고 결과 문자열은 같다(라벨은 ASCII 이름 · 한글 등 비ASCII 는 tr 이 그대로 둔다 — `${x,,}` 도 C 로케일에선 같음).

## 사전검증
- 소환: 아니오
- 면제: 같은 결과를 내는 문자열 변환 6곳 교체이고 제어 흐름 변화 0이다. 기존 시험 기대 그대로가 bash5 에서 통과하고, 3.2 실행 줄이 새로 붙는다. 되돌림 1커밋 revert. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#8

## 조사 근거
- `scripts/harness-install/tmm/tmm:189` `printf '%s' "${label,,}"` · 197행 `lower="${n,,}"` · 202행 `pl="${pfx,,}"` · 208행 `pl="${pfx,,}"` · 219행 `pl="${pfx,,}"` · 223행 `n="${n,,}"` — 6곳 전부.
- `tests/harness/test_tmm_group.sh:23` `label()` 이 `bash -c 'source "$0" __lib; cat_of "$1"'` 로 부른다(PATH 의 bash = 이 Mac 에선 5).
- 이 Mac `/bin/bash` 3.2 실행 로그: `tmm: line 197: ${n,,}: bad substitution` → `FAIL byz-v65-master-claude#143 → '' (기대 'v65')` 등 18건.
- 라이브 `~/.local/bin/tmm` → `~/.tmm/current/core/bin/tmm`(versions/0.7.4) = 추적본 cmp 동일.

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/harness-install/tmm/tmm`: 함수 1개 `_lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }` 를 `cat_of()` 바로 위에 두고 6곳을 `$(_lc "$x")` 로 바꾼다(189행은 `printf '%s' "$(_lc "$label")"`). 그 밖 변경 0. 파일 안에 `,,}`·`^^}` 가 0건이어야 한다.
2. `tests/harness/test_tmm_group.sh`: `label()` 이 부르는 셸을 `${TMM_TEST_BASH:-bash}` 로 바꾸고, 파일 끝에서 `/bin/bash` 가 3.x 면 같은 check 묶음을 `TMM_TEST_BASH=/bin/bash` 로 한 번 더 돈다(3.x 가 없으면 `SKIP bash3 없음` 1줄 — 실패 아님). 추가 정적 검사 1줄: tmm 에 `,,}` 0건.

커밋은 자기 브랜치, **push 금지**. **금지**: `~/.tmm/` 아래 수정·`current` 전환(설치는 오빠 승인 영역 — 아래) · 다른 bash4 문법 «추정» 수정(실행으로 드러난 것만) · 키트 fable-team 변경(3.2 실패 0).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_tmm_group.sh` rc=0 이고 출력에 3.2 묶음 PASS 가 있다 · `/bin/bash tests/harness/test_tmm_group.sh` rc=0 · `grep -c ',,}' scripts/harness-install/tmm/tmm` = 0.
- RESULT 에 3.2 묶음 PASS 줄 2개 복붙.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_tmm_group.sh rc=0 · 이슈: 0`.
- 랜딩 뒤(카드 밖 · 사람 승인 영역): `~/.tmm/versions/` 새 버전 설치·`current` 전환 · byzs-mac-mini 에 tmm 반영은 원격 쓰기라 아침 사람 판단.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 293199de7566a8c583f629e85c3ad312020631a0 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#8 · 원장 R24 · 야간 자율 단위 2). spawn 은 master 판단.
- 정본 영향 없음: tmm 추적 사본·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 01:46 — 대기→진행 · 좌석 byz-harness-nano-r24-tmm-bash32-lowercase#0
- 2026-10-08 — ★반송 r1 (arch#8 · HOLD 1회)★ — 나노 3b534a71e6 은 카드 범위대로 했고 시험도 통과하지만, arch 재검에서 카드 전제가 틀린 것 2개가 나왔다:
  ①tmm 은 `cmd_rows()` 에서 연관 배열 `declare -A ST`(332행)·`declare -A EP MD CA CE CM KEY`(343행)를 쓴다 → bash 3.2 에선 피커·목록 본 경로가 아예 못 돈다(test_tmm_group 은 cat_of 만 봐서 못 잡음). 소문자 6곳만 고쳐서는 «3.2 에서 tmm 이 돈다»가 성립하지 않는다.
  ②`$(_lc …)` 는 호출마다 서브셸+tr 이라 느리다 — 실측(bash5 · 이름 150개 cat_of): 새판 1.66 s vs 설치판 0.53 s(3배 · 371행이 좌석마다 부름).
  재작업 범위(같은 나노 · 2파일):
  1. `scripts/harness-install/tmm/tmm`: 6곳을 원래 `${x,,}` 로 되돌리고 `_lc` 삭제. 파일 맨 위(셔뱅·주석 다음)에 bash 4 가드: `BASH_VERSINFO[0] < 4` 이면 후보 `${TMM_BASH4_CANDIDATES:-/opt/homebrew/bin/bash /usr/local/bin/bash}` 중 실행 가능한 첫 것으로 `exec "$b" "$0" "$@"`(단 `$1 = __lib` 로 source 될 때는 exec 하지 않음) · 후보가 없으면 `tmm: bash 4 이상 필요 (지금 $BASH_VERSION) — brew install bash` 를 stderr 에 내고 `return 1 2>/dev/null || exit 1`(조용한 진행 0).
  2. `tests/harness/test_tmm_group.sh`: 3.2 묶음을 «cat_of 통과»가 아니라 «가드 동작»으로 바꾼다 — /bin/bash 3.x 로 `TMM_BASH4_CANDIDATES=/nonexistent bash tmm doctor` → rc≠0 + 문구 `bash 4 이상 필요` · 후보에 이 Mac bash5 경로를 주면 rc=0(doctor). 정적 검사 `,,}` 0건 줄은 삭제.
  결론(원장 R24 답): tmm 은 bash 4+ 전용으로 명시하고, byzs-mac-mini 는 homebrew bash 설치(원격 쓰기 = 아침 사람). 키트 fable-team 은 3.2 실패 0(하네스 시험 32개 실측).
- 2026-10-08 — 반송 r1 재작업 통과 (arch#9 재현 · 판정서 §42 초안) — 나노 2f6562f17e: base 대비 가드 13줄 추가·삭제 0 · bash5·/bin/bash 3.2 시험 rc=0 · 음성 대조(가드 없는 base → 시험 FAIL) · cat_of 150개 0.84 s(base 0.86 s).
세트: 2f6562f17e98fade1c9333914108f85b880edc8e · 시험: bash tests/harness/test_tmm_group.sh rc=0 · 이슈: 0
- 2026-10-08 01:55 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§42
