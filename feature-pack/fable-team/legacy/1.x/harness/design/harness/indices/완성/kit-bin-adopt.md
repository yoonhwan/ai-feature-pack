# 인덱스: 도구 사본 드리프트 채택 — 키트 bin 을 단일 원본으로 (라이브·추적본·키트 3열 표 + 채택 커밋)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「RELEASE-<ver>.md 1장 + 머신별 「반영됨 <machine> <sha>」 행 전부」.
골의 축: C(업그레이드·커밋·push·배포 발행·반영). 핵심 한 줄: 좌석이 쓰는 라이브 도구 폴더와 리포 사본 두 곳이 갈라져 있어 설치(install.sh)를 돌리면 퇴행한다 — 키트 `scripts/harness-install/fable-team/bin/` 을 단일 원본으로 맞춰야 이 Mac·byzs-mac-mini 설치(오빠 값 10-07: 명단 = 이 Mac + byzs-mac-mini · FT_BIN 전환 승인)가 가능하다. 출처: arch 58611 · master 발주 58634.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
사본 3곳: ①라이브 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/bin/`(gitignored · 지금 좌석이 실제로 씀 · `.bak*` 파일은 대상 아님) ②추적본 `scripts/fable-team-bin/` ③키트 `scripts/harness-install/fable-team/bin/`(install.sh 가 복사하는 원본). arch 실측(origin/main 0304b966f7 기준 · 파일 73개): 셋 다 같음 16 · 라이브=키트(추적본 없음) 13 · 키트만 11(ft-tmux-*.sh·ft-mbox.* 등) · 추적본만 24(ft-gh-as-tank.sh·ft-harness-info.sh·ft-name-lint.sh·ft-land.sh·mbox-v2.sh 등 오늘까지 추가된 하네스 도구) · 셋이 다름 9. 다른 9 중 7(ft-blocked-on-master.sh·ft-index-move.sh·ft-nano-close.sh·ft-nano-slots.sh·ft-nano-spawn.sh·ft-news-tick.sh·ft-tick.sh)은 «라이브 = 키트» 이고 추적본만 뒤처짐. 셋 다 다른 것은 2: ft-role-spawn.sh(라이브에 10-07 이름 접두 수정 a~d 가 들어 있음 · arch 58449 판정) · ft-news-tree.py. 라이브 파일은 읽기만 한다.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. RESULT `design/teams/harness/RESULT-kit-bin-adopt-20261007.md`: 73 파일 3열 sha 표(라이브·추적본·키트 · 없음은 -) + 파일마다 «채택본·이유 1줄». 채택 규칙: 라이브에 있으면 라이브 채택(실사용 중) · 셋 다 다른 2개는 diff 를 읽고 라이브 채택 + 라이브에 없는 다른 사본의 변경이 있으면 그 줄을 RESULT 에 적는다(합치지 말고 보고만) · 추적본만 있는 24는 그대로 채택.
2. 채택 커밋(한 커밋 · [structure]): 키트 bin(`scripts/harness-install/fable-team/bin/`) 에 ⓐ추적본만 있던 24 파일 추가(추적본 바이트) ⓑ셋 다 다른 2 파일(`scripts/harness-install/fable-team/bin/ft-role-spawn.sh` · ft-news-tree.py)을 라이브 바이트로. 추적본 bin(`scripts/fable-team-bin/`) 에 ⓒ다른 9 파일을 키트(=채택본) 바이트로 맞춤. 키트만 있는 11 · 이미 같은 파일은 손대지 않는다. 결과 = «추적본에 있는 모든 파일은 키트에도 있고 바이트가 같다».
3. 시험 `tests/harness/test_kit_bin_sync.sh`(신규 · 리포 안만 봄): 추적본 bin 의 모든 파일이 키트 bin 에 있고 cmp 같음(아니면 그 파일 이름과 함께 fail) · 실행 비트 동일. 이 시험이 앞으로 두 사본의 재분기를 잡는다.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 폴더 쓰기(전환은 별도 단계 · 오빠 승인 범위로 master 가 집행) · 추적본/키트 «합치기»(폴더 하나로 정리 — 다음 단위) · 키트만 있는 11 삭제 · 파일 내용 수정(바이트 복사만 — 기능 변경 0) · install.sh·templates/ 수정(옆 카드 kit-hooks-install-check 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_kit_bin_sync.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0(키트 경로를 쓰는 시험 포함).
- RESULT 표 73행 · 셋 다 다른 2 파일의 diff 요약.
- 키트로 빈 HOME 설치 dry-run: `bash scripts/harness-install/fable-team/install.sh --home <mktemp>` 의 files= 값이 RESULT 에 적힌 키트 파일 수와 같다.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 828b243ab2070bd12d3537703f2d8d8cd1da8e76 (spawn 2026-10-07)
- base: 최신 origin/main(0304b966f7 이후).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master 발주 58634). 옆 카드 kit-hooks-install-check 와 파일 겹침 0 → 동시 진행 가능.
- 정본 영향 없음: 하네스 도구 사본 정렬·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 12:52 — 대기→진행 · 좌석 byz-harness-nano-kit-bin-adopt#0
- 2026-10-07 13:33 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§25
- 세트: 7889dec52559ae19c672d71dbedc8617f2d85bc3 · 시험: bash tests/harness/test_kit_bin_sync.sh rc=0 · 이슈: 0
