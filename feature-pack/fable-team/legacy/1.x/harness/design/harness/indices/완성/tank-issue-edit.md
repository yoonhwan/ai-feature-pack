# 인덱스: Tank 래퍼 — Issue 본문·제목 수정(edit) 동작 추가 + 수정 전 원문 보관
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의). 핵심 한 줄: 원장 R10 — issues 오케(byz-issues-master-claude#1 · #58849)가 Issue 848 의 골좌표 약어를 «본문 수정»으로 정정하려 했으나 래퍼에 edit 동작이 없고 직접 gh issue edit 은 가드가 막아 정정 댓글로 대체했다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 추적본 `scripts/fable-team-bin/ft-gh-as-tank.sh`(128행) + 키트 `scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh`(지금 같은 바이트 · 둘 다 같이 고친다). 래퍼 구조: 동작별로 gh 인자를 CMD 배열에 만들고(40~92행 case) · 기본 dry-run 은 그 배열을 출력만 · --apply 때 토큰 → `gh api user` 로 byz-tank 확인 → 실행. 지금 동작 = create·comment·label·close·reopen·pr-comment·pr-create — 본문·제목 수정이 없다. 가드 `gh-issue-author-guard.sh` 는 직접 `gh issue edit` 를 이미 차단(4·220행) → 래퍼가 유일한 길. 본문 덮어쓰기는 되돌릴 수 없으므로(GitHub 웹 이력은 있으나 좌석이 못 읽는다) 수정 «전» 원문을 파일로 보관해야 한다. 시험 `tests/harness/test_gh_as_tank.sh` 는 PATH 맨 앞 가짜 gh(호출을 STUB_LOG 에 기록)로 실제 GitHub 호출 0.

## 구현 범위 (이 셋만 — 닫힌 목록)
1. `scripts/fable-team-bin/ft-gh-as-tank.sh`(+ 키트 사본 같은 바이트): 동작 `edit <번호> [--title <제목>] [--body-file <파일>]` 추가.
   - 둘 다 없으면 exit 2 · 번호 정수 아님 exit 2 · --body-file 파일 없음 exit 2 · --title 빈 문자열 exit 2 · 알 수 없는 인자 exit 2.
   - CMD=(issue edit <번호> -R $REPO [--title T] [--body-file F]) — dry-run 출력도 이 배열 그대로(기존 규약).
   - --apply: 작성자 확인(기존) 뒤, 실행 «전» 현재 제목·본문을 Tank 토큰으로 `gh issue view <번호> -R $REPO --json title,body` 해서 보관 폴더에 `<번호>-<UTC YYYYmmddTHHMMSSZ>.body.md` · `.title.txt` 두 파일로 저장. 보관 폴더 = FT_ISSUE_EDIT_BAK_DIR 또는 git common dir 루트의 `.fable-team/state/issue-edit-bak/`(ft-plan-handoff.sh 의 COMMON 계산과 같은 방식). ★보관 실패(조회 실패·빈 응답·쓰기 실패)면 수정 시도 0 + exit 1★(#0 RULE).
   - 성공 출력 1줄 끝에 `bak=<본문 파일 경로>` · 되돌림 = 같은 래퍼로 `edit <번호> --body-file <bak 본문> --title "$(cat <bak 제목>)" --apply`(이 줄을 출력에 그대로 1줄 찍는다).
   - 머리 주석 «동작» 목록·usage 문자열에 edit 추가. 다른 동작 무변화.
2. `tests/harness/test_gh_as_tank.sh`: 가짜 gh 에 `issue view` 분기(STUB_VIEW_JSON 반환 · STUB_VIEW_RC 로 실패 재현) 추가 + 사례: 옵션 없음 exit 2 · 번호 아님 exit 2 · 없는 본문 파일 exit 2 · dry-run 제목만/본문만/둘 다 출력이 기대 문자열과 일치 · --apply 성공 시 보관 두 파일 실재 + 내용 = 가짜 view 의 값 + STUB_LOG 에서 `issue view` 가 `issue edit` 보다 먼저 · view 실패 시 exit 1 + STUB_LOG 에 `issue edit` 0건 · 토큰 주인 불일치 시 exit 1(기존 규약 재사용).
3. 가드 시험 무변화 확인만(가드 파일 수정 0) — `gh issue edit 5 --body x` 직접 호출이 여전히 차단되는 사례 1개를 test_gh_as_tank.sh 의 block 목록에 추가.
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN·~/.claude/hooks 쓰기 · PR 본문 수정(pr edit — PR 쓰기 가드 확장은 별건) · 보관 없이 수정하는 우회 옵션 · 기존 동작 출력 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_gh_as_tank.sh` rc=0 · `bash tests/harness/test_kit_bin_sync.sh` rc=0 · `bash tests/harness/test_tank_verify.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0 · 두 사본 `bash -n` OK · `cmp` 두 사본 동일.
- RESULT 에 dry-run 실제 출력 3줄(제목만·본문만·둘 다) 복붙.
- 라이브 설치(FT_BIN 교체)와 Issue 848 실제 수정은 master 집행 — 카드 범위 밖.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b61099d2592b6c4bb629f07ab83831d5af19ff69 (spawn 2026-10-07)
- base: 최신 origin/main(래퍼 마지막 변경 = gh-guard-scope-main-prcreate 랜딩판).
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#6 · 원장 R10 · issues #58849).
- 정본 영향 없음: 하네스 래퍼·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 18:29 — 대기→진행 · 좌석 byz-harness-nano-tank-issue-edit#0
- 2026-10-07 — 증거(나노 byz-harness-nano-tank-issue-edit#0 · 골 축 6-b 요청 R10):
  - 커밋 sha(브랜치 nano/tank-issue-edit, push 0): 00a120c510426a284dff1a9058abda70bed276a6
  - 시험: `bash tests/harness/test_gh_as_tank.sh` fail=0 rc=0 · `bash tests/harness/test_tank_verify.sh` rc=0 · 두 사본 `bash -n` OK · `cmp` 동일
  - dry-run 3줄:
    - `DRY as=byz-tank gh issue edit 848 -R SecondWindStudio/byz-agents --title 새제목`
    - `DRY as=byz-tank gh issue edit 848 -R SecondWindStudio/byz-agents --body-file /tmp/claude-501/b.md`
    - `DRY as=byz-tank gh issue edit 848 -R SecondWindStudio/byz-agents --title 새제목 --body-file /tmp/claude-501/b.md`
  - 실패 3종(test_kit_bin_sync · test_regress_pack · test_branch_candidates)은 base 재현 — 이 변경과 무관(master·arch#6 판정)
- 2026-10-07 18:52 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§28
- 세트: 00a120c510426a284dff1a9058abda70bed276a6 · 시험: bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0
