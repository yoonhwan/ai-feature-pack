# 인덱스: 나노 닫기 — 표준이 아닌 이름의 전용 워크트리·브랜치 좌석(--wt · --branch 명시)
<!-- ledger: design/teams/harness/GOAL-harness.md -->

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(오케 개선요청 접수·협의) · 원문 7. 핵심 한 줄: 원장 R8 보강 — 전용 워크트리는 있지만 이름이 표준(.worktrees/<접두><키> · nano/<키>)이 아닌 나노 좌석(실례 byz-cfo-nano-overdraft-u1#0 · 워크트리 cfo-overdraft-u1 · 브랜치 fix/cfo-overdraft-u1-verdict265 · PR 847 병합)을 표준 경로로 닫지 못한다. 출처: master#8 발주 58876 · 오빠 10-07(공유 워크트리 닫기 지시의 연장).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
대상은 키트 `scripts/harness-install/fable-team/bin/ft-nano-close.sh`(+ 추적본 scripts/fable-team-bin 같은 바이트 · test_kit_bin_sync 검사) — 선행 카드 nano-spawn-close-team-env(팀 env 자동 로드 · `--shared-wt`)가 랜딩된 판이 base. 지금 좌석 워크트리 해석(217행 근처 «한 곳»)은 «등록된 워크트리 ∧ $ROOT/.worktrees/ 아래 ∧ 브랜치 nano/<key>[-rN]» 만 후보로 보고, 없으면 ③(추측 금지)·⑤(브랜치 없음)로 REJECT 한다(DA607 H1 fail-closed). 전역 규칙(~/.claude/CLAUDE.md 하드 룰 2): 나노 «세션» kill 은 nano-close 경로 표준승인(10-02) · 나노 «워크트리» 자율 정리는 브랜치가 `nano/*` 일 때만(09-25) — 아니면 «정리 스크립트 생성 + 사람 ! 실행»으로 후퇴 · 브랜치 삭제는 언제나 HIL. 닫기에는 이미 `--cherry-override "<사유>"`(사람 우회 · 사유 필수)가 있다.

## 구현 범위 (이 둘만 — 닫힌 목록)
1. `scripts/harness-install/fable-team/bin/ft-nano-close.sh`(+ 추적본 같은 바이트): 명시 인자 `--wt <경로> --branch <이름>` 추가 — «둘 다» 주어졌을 때만 이 모드(하나만 있으면 usage exit 2) · `--shared-wt` 와 동시 사용 금지(exit 2) · 인자 없으면 지금 동작 그대로. 이 모드에서 «전부» 확인, 하나라도 아니면 REJECT:
   ⓐ`--wt` 가 이 리포에 등록된 워크트리(`git worktree list --porcelain`)이고 $ROOT/.worktrees/ 아래 ⓑ그 워크트리에 체크아웃된 브랜치 == `--branch` ⓒ좌석 세션이 살아 있으면 pane cwd 의 toplevel == `--wt` ⓓ다른 tmux pane 중 cwd 가 `--wt` 안인 것이 0(있으면 공유 워크트리 — 「--shared-wt 로 닫아라」) ⓔ`--wt` 미커밋 변경 0(이 모드는 WIP 자동 커밋을 하지 않는다 — 표준 브랜치가 아니라서) ⓕ기존 종료조건 3(--result 실재 · --recv seq · 유휴) · 카드 증거 줄(--repo = `--wt` · 현재 HEAD 일치 규칙 그대로) ⓖcherry 게이트는 `--branch` 기준 그대로 — 스쿼시 병합(PR)처럼 patch-id 가 안 맞으면 기존 `--cherry-override "<사유>"` 로만 통과(새 우회 0).
   통과하면: 세션 kill(표준승인 범위) · 명부 CLOSED · 원장 행 `mode=named-wt wt=<경로> branch=<이름>` · 워크트리는 «정리 계획 스크립트만 생성»(기존 .fable-team/state/wt-clean/<seat>.sh 생성 경로 재사용) + 출력에 「브랜치가 nano/* 가 아니라 자율 정리 범위 밖 — 사람 ! 실행」 1줄 · 자동 wt-clean 실행 0 · 브랜치 삭제 0.
2. 시험 `tests/harness/test_nano_close_named_wt.sh`(신규 · 임시 리포 + 가짜 tmux): `--wt` 만 → exit 2 · `--branch` 만 → exit 2 · `--shared-wt` 와 같이 → exit 2 · 등록 안 된 경로 → REJECT · 브랜치 불일치 → REJECT · pane cwd 불일치 → REJECT · 다른 pane 이 같은 워크트리 → REJECT(공유) · 미커밋 있음 → REJECT · 전부 맞음 → 통과 + 원장 행 mode=named-wt + wt-clean 계획 파일 생성 · wt-clean 실행 0(워크트리 그대로 실재) · 브랜치 그대로 실재 · 인자 없이 같은 좌석 → 지금처럼 REJECT(무변화).
커밋은 자기 브랜치, **push 금지**. **금지**: 라이브 FT_BIN 쓰기 · 자동 판별(반드시 두 인자 명시) · 이 모드에서 WIP 자동 커밋·wt-clean 실행·브랜치 삭제 · cherry 게이트 우회 신설 · 표준 경로 동작 변경.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_close_named_wt.sh` rc=0 · `tests/harness/test_kit_bin_sync.sh` rc=0 · `tests/harness/test_nano_team_env.sh` rc=0 · 기존 `tests/harness/test_*.sh` 전부 rc=0 · `bash -n` OK.
- 실례 좌석 대상 판정만(실제 kill 은 master 집행): byz-cfo-nano-overdraft-u1#0 에 이 모드를 `FT_NANO_CLOSE_DRY=1` 류 «판정만» 경로가 있으면 그것으로, 없으면 RESULT 에 «어느 확인까지 통과할지» 를 손 대조 표로.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: b61099d2592b6c4bb629f07ab83831d5af19ff69 (spawn 2026-10-07)
- base: nano-spawn-close-team-env(45a1ee516a) 랜딩 뒤 최신 origin/main.
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#5 · master#8 발주 58876 · 원장 R8 보강).
- 정본 영향 없음: 하네스 나노 도구·시험만 — docs/architect 제품 정본 변경 없음
- 2026-10-07 18:29 — 대기→진행 · 좌석 byz-harness-nano-nano-close-named-wt#0
- 세트: 0103bccf3e96539c5460aba6f3cf0b8bd9c37a03 · 시험: bash tests/harness/test_nano_close_named_wt.sh rc=0 · 이슈: 0
  - 부속(2026-10-07 nano 실측): named_wt 50P 0F · test_nano_team_env 34P 0F rc=0 · 키트 cmp 동일(scripts/harness-install/fable-team/bin ↔ scripts/fable-team-bin) · bash -n OK · 기존 harness test 23/26 rc=0 — 나머지 test_kit_bin_sync(ft-press-* drift)·test_regress_pack(issue_pack 2행)은 변경 전 HEAD 추출본에서도 동일 실패(내 변경 무관) · test_branch_candidates 는 공유 리포 브랜치 수 변동(1137→1138)으로 1회 FAIL — 동시 세션 영향.

### 완료조건 2 — byz-cfo-nano-overdraft-u1#0 판정만 표 (dry-run 경로 없음 → 손 대조 · 2026-10-07 읽기 전용 실측)
실측: 워크트리 `.worktrees/cfo-overdraft-u1` 은 `git worktree list` 에 없음(이미 정리) · 브랜치 `fix/cfo-overdraft-u1-verdict265` 만 실재(refs/heads) · tmux 세션 0 · seats-cfo.json/seats.json 행 0. 아래는 `--wt .worktrees/cfo-overdraft-u1 --branch fix/cfo-overdraft-u1-verdict265` 로 부를 때의 판정.

| 확인 | 판정 | 근거 |
|---|---|---|
| 인자 검증(둘 다·--shared-wt 없음) | 통과 | 두 인자 명시 |
| ⓐ 등록 워크트리 ∧ .worktrees/ 아래 | ★REJECT★ | 경로 없음 → 「ⓐ--wt 경로가 없다」 (등록 목록에도 없음) |
| ⓑ 체크아웃 브랜치 == --branch | 평가 안 됨 | ⓐ 실패 시 건너뜀 |
| ⓒ pane cwd toplevel | 해당 없음 | 세션 없음 |
| ⓓ 다른 pane cwd 0 | 통과 | `tmux list-panes -a` 에 u1 경로 pane 0 |
| ⓔ 미커밋 0 | 평가 안 됨 | 워크트리 없음 |
| ⓕ 종료조건 3·증거 줄 | 평가 안 됨 | 명부 행 0(index 못 찾음 → ⑥ REJECT 병기) |
| ⓖ cherry(--branch 기준) | 평가 안 됨 | — |
→ 결론: 이미 정리된 좌석이라 이 모드로 닫을 대상이 없다(REJECT 가 정답). 닫기 필요 상태가 되려면 워크트리·명부가 살아 있어야 한다. 이 모드의 통과 경로는 시험(전부 맞음 → CLOSED · 원장 mode=named-wt · 계획 .sh.hil)에서 검증됨.
- 2026-10-07 18:52 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§29
