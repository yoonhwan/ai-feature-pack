# 인덱스: ft-role-spawn 기본 이름을 byz-v65- 로 — 두 계보(ft-v65-·byz-v65-) 번호 합산·교체를 항상
<!-- ledger: design/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: v65 역할 좌석은 이미 새 이름(byz-v65-…)인데 ft-role-spawn 기본 접두가 옛 ft-v65- 라, 접두 환경변수를 빠뜨리고 부르면 옛 계열로 떠 현역이 2개 된다 — v65 총괄 보고(arch 가 스스로 후계를 띄울 때 이름 중복 사고) · arch 58455 남은 위험 · 58640 ① 승인.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 키트 사본 `scripts/harness-install/fable-team/bin/ft-role-spawn.sh`(kit-bin-adopt 랜딩 뒤 라이브 바이트 = 10-07 수정 a~d 포함) · 추적본 scripts/fable-team-bin 은 같은 바이트로 같이(test_kit_bin_sync 검사). 지금 35~36행: `BASE_NAME="${FT_ROLE_BASE_PREFIX:-ft-v65-}$ROLE-$AGENT"` · `LEGACY_BASE="ft-v65-$ROLE-$AGENT"`. 번호(37~38행 awk)와 교체 대상(46행 PLAN 출력 · 82행 seats.json 갱신)은 «BASE_NAME 과 LEGACY_BASE» 두 계열만 본다 — 그래서 접두를 ft-v65- 로 주면 BASE=LEGACY 가 되어 byz- 계열을 못 보고, 기본값을 byz- 로만 바꾸면 반대로 ft- 를 명시할 때 byz- 현역이 남는다. 스크립트는 design/v65 경로를 하드코딩한 v65 전용이다(범용화 안 함). 정본 이름 규칙 = governance §1(`byz-<팀>-<역할>-<에이전트>#N` · 번호는 옛 이름에서 이어받음).

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/bin/ft-role-spawn.sh`(+ 추적본 같은 바이트): ⓐ기본 접두 `byz-v65-`(환경변수 FT_ROLE_BASE_PREFIX 로 바꿀 수 있음은 유지) ⓑ계보 상수 두 개 `NEW_BASE="byz-v65-$ROLE-$AGENT"` · `OLD_BASE="ft-v65-$ROLE-$AGENT"` 를 두고, 번호 계산·PLAN 의 교체 대상·seats.json 교체(_replaced_by) 세 곳 모두 «BASE_NAME · NEW_BASE · OLD_BASE» 를 같이 본다(접두를 무엇으로 주든 두 계보의 현역이 전부 교체되고 번호는 두 계보 최댓값+1). ⓒ주석 한 줄 갱신(기본 = 정본 이름 · 오빠 10-07). 그 밖 동작(모델 기본·astra low 가드·tick 승계·kill 안 함) 변경 0.
2. 시험 `tests/harness/test_role_spawn_name.sh`(신규): 임시 git 리포에 가짜 `.fable-team/seats.json`(arch 현역 `ft-v65-arch-claude#165` _replaced_by 찍힘 + `byz-v65-arch-claude#166` 현역 · 다른 트랙 `CFO_F_ARCH#14` 현역)·`design/v65/indices/inbox/arch/`·`design/v65/SEATBELT-README.md` 를 만들고 PATH 앞에 가짜 `tmux`(ls 는 빈 출력 · has-session 은 1)·`tmuxc`(--dry-run 이면 0)를 둬서 `--dry-run` 의 PLAN 줄을 본다. 케이스: 접두 없음 → seat=byz-v65-arch-claude#167 replaces=[byz-v65-arch-claude#166] · `FT_ROLE_BASE_PREFIX=ft-v65-` → seat=ft-v65-arch-claude#167 replaces=[byz-v65-arch-claude#166] · 어느 경우도 CFO_F_ARCH#14 는 replaces 에 없음 · seats.json 에 두 계보 모두 없을 때 → #0 · role 이 tester 일 때도 같은 규칙.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN 쓰기 · seats.json 실파일 쓰기(시험은 임시 리포만) · 실제 tmuxc open(시험은 --dry-run + 가짜 바이너리) · 범용화(팀 인자 추가 등).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_role_spawn_name.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0 · `bash -n` OK.
- 실 리포 v65 명부 대상 `--dry-run`(seats.json 쓰기 없음) PLAN 줄을 RESULT 에: 접두 없이 arch → byz-v65-arch-claude#<현재 최대+1> · replaces 에 byz-·ft- 현역만.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 1aca03ade2f098175548f1c549ed4be6b837ea6d (spawn 2026-10-07)
- base: kit-bin-adopt 랜딩 뒤 최신 origin/main. 옆 카드 nano-spawn-close-team-env 와 파일 겹침 0 → 2석 동시 가능.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master#8 발주 58707 · arch 58640 ①).
- 정본 영향 없음: 하네스 좌석 도구·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 13:32 — 대기→진행 · 좌석 byz-harness-nano-role-spawn-byz-default#0
- 2026-10-07 13:43 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§27
- 세트: 86d77d5f6ac70472f5db9d34a60309a20c7d5049 · 시험: bash tests/harness/test_role_spawn_name.sh rc=0 · 이슈: 0
