# 인덱스: `--base <sha>` 로 연 나노 좌석 닫기 막힘 — 닫기는 sha 를 «랜딩 브랜치» 로 환원하고, spawn 은 처음부터 브랜치를 기록 (R42 · v65 실례)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → R42(byz-v65-master-claude#148 #63775 보고 · master#16 접수 #63780 · 카드 요청 #63781 · 우선 보통)
- 상태: 대기
- 선행: 없음 — origin/main 최신에서 브랜치(대상 3파일은 ops/main-base 와 main 같은 바이트)
- 시험 입력: 임시 git 리포 + 가짜 좌석 워크트리(.worktree-info.json base=sha / base=브랜치) — 실제 좌석·tmux·원격 쓰기 0
- 기준값: `ft-nano-spawn.sh --base <sha>` → 좌석 `.worktree-info.json` 의 `"base"` 에 sha 문자열 → `ft-nano-close.sh` 가 그 값을 feat 기준(`_FEAT`)으로 씀 → cherry 게이트가 `refs/heads/`·`refs/remotes/` 만 받아 「브랜치 없음」 REJECT · 지금 우회 = 사람이 `FT_NANO_FEAT=<랜딩 브랜치>` 를 붙여 닫기

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(메인 오케 개선요청 접수 — v65 master 실례 R42) + C(반영). 핵심 한 줄: 닫기의 비교 기준은 «나노가 갈라진 점(sha)» 이 아니라 «산출이 랜딩된 브랜치» 다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
나노 닫기의 cherry 게이트는 «나노 커밋 내용이 랜딩 브랜치에 들어왔는가» 를 본다(`git cherry <feat> <nano>` + merge-tree). 그래서 기준 `feat` 는 반드시 랜딩 브랜치여야 한다. 그런데 `ft-nano-spawn.sh --base <ref>` 는 받은 값을 그대로 좌석 `.worktree-info.json` 의 `"base"` 에 쓰고, `ft-nano-close.sh` 는 `FT_NANO_FEAT` 가 없으면 그 `"base"` 를 기준으로 쓴다. `--base` 에 sha 를 주면 기준이 «갈라진 점» 이 되어 게이트가 「브랜치 없음」 으로 막는다. ★게이트가 sha 를 받게 하는 안(master 후보 1)은 기각★: sha 를 받아도 비교 기준이 갈라진 점이라 랜딩된 내용이 그 sha 에 없다 → squash 랜딩된 나노도 전부 «안 들어옴» 으로 REJECT(에러 문구만 바뀜). 채택 = 후보 2 를 두 곳에: ①close 는 `"base"` 가 ref 가 아니고 commit 이면 «정보 없음» 으로 보고 지금 있는 기본 사슬(`FT_NANO_FEAT` → 기본 `feat/v6-realtime-live`)로 랜딩 브랜치를 정하되, 그 sha 가 고른 브랜치의 조상인지 확인해 아니면 REJECT(「base 가 sha <x> 이고 <브랜치> 의 조상이 아니다 — FT_NANO_FEAT=<랜딩 브랜치> 로 다시」 · 조용한 추측 0) ②spawn 은 `--base` 가 sha 면 `"base"` 에 그 좌석의 랜딩 브랜치(`FT_NANO_FEAT` 또는 지금 브랜치 = 지금 `BASE_BRANCH` 계산과 같은 규칙)를 쓰고 sha 는 이미 있는 `"base_sha"` 칸에 둔다. 브랜치 이름 base 경로는 둘 다 무변경.

## 사전검증
- 소환: 아니오
- 면제: 닫기 기준 계산 1곳 + spawn 기록 1곳 · 게이트 무변경 · sha 가 조상 아니면 REJECT(추측 0) · 되돌림 1커밋 — arch 서명 byz-harness-arch-claude#15

## 조사 근거
- `scripts/fable-team-bin/ft-nano-close.sh:350` `_FEAT` 우선순위(FT_NANO_FEAT → info.base → 기본 `feat/v6-realtime-live` · :351~:352) · `scripts/fable-team-bin/ft-nano-close.sh:365` `_fetch_remote_feat` · `scripts/fable-team-bin/ft-nano-close.sh:448` cherry 게이트 호출(`_FEAT` 전달).
- `scripts/fable-team-bin/ft-nano-cherry-gate.sh:49` feat = `refs/heads/`·`refs/remotes/` 만(무변경 대상).
- `scripts/fable-team-bin/ft-nano-spawn.sh:133` `BASE_BRANCH="${BASE_REF:-…}"` · `scripts/fable-team-bin/ft-nano-spawn.sh:177` `.worktree-info.json` 기록(`"base"` = BASE_BRANCH · `"base_sha"` 칸 이미 있음).
- 실례: v65 master#148 #63775 → master#16 #63780(우회 = FT_NANO_FEAT 명시).

## 구현 범위 (닫힌 목록 · 정본 `scripts/fable-team-bin/` + 키트 사본 `scripts/harness-install/fable-team/bin/` 같은 바이트)
1. `scripts/fable-team-bin/ft-nano-close.sh`: `_FEAT` 계산 직후 — 값이 `refs/heads/<x>`·`refs/remotes/<x>` 둘 다 아니고 `rev-parse --verify -q <x>^{commit}` 이면: `_BASE_SHA=<x>` 로 두고 `_FEAT` 를 기본 사슬(FT_NANO_FEAT 가 명시면 그 값 · 아니면 `feat/v6-realtime-live`)로 다시 정한 뒤 `merge-base --is-ancestor $_BASE_SHA $_FEAT`(원격 ref 면 기존 `_fetch_remote_feat` 뒤) — 거짓이면 REJECT(위 배경 문구) · 참이면 `INFO base sha <짧은 sha> → 랜딩 브랜치 <_FEAT>` 1줄 후 지금 흐름 그대로.
2. `scripts/fable-team-bin/ft-nano-spawn.sh`: `--base` 값이 ref 가 아니고 commit 이면 `.worktree-info.json` 의 `"base"` = `FT_NANO_FEAT` 가 있으면 그 값 · 없으면 `git -C "$WT" rev-parse --abbrev-ref HEAD`(지금 브랜치) · `"base_sha"` = 그 sha(짧은 형). 워크트리 생성·카드 base_sha 대조(:90) 동작 무변경.
3. `scripts/fable-team-bin/ft-nano-cherry-gate.sh` 무변경.
4. 시험 `tests/harness/test_nano_close_sha_base.sh`(임시 리포 · tmux·실제 좌석 0): ①info.base=sha(랜딩 브랜치 조상) + 산출이 랜딩 브랜치에 squash 랜딩 → 닫기 게이트 통과(INFO 줄) ②info.base=sha 인데 랜딩 브랜치 조상 아님 → REJECT 문구 ③info.base=브랜치 → 지금과 같은 결과(무변경) ④FT_NANO_FEAT 명시 → 그 값 우선(무변경) ⑤spawn `--base <sha> --dry-run`(또는 info 기록 함수만) → `"base"` 가 브랜치 · `"base_sha"` 가 그 sha ⑥기존 `test_nano_close_named_wt.sh`·`test_cherry_gate_squash.sh`·`test_kit_bin_sync.sh` PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: cherry 게이트 완화 · `--cherry-override` 경로 변경 · 실제 좌석 닫기 · 이미 닫힌 좌석 정보 수정.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_nano_close_sha_base.sh` rc=0(①~⑥) · 사본 cmp · bash -n.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_nano_close_sha_base.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 FT_BIN cp 2파일 + cmp · v65 master 에 1줄(「--base <sha> 좌석도 FT_NANO_FEAT 없이 닫힘 · 랜딩 브랜치 조상 아니면 REJECT 문구대로」).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 6ef47f4063f79ecca4e691448abc8461b06c9e7c (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#15 · R42 · master #63781).
- 정본 영향 없음: 하네스 나노 개설·닫기 도구·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 18:21 — 대기→진행 · 좌석 byz-harness-nano-r42-nano-close-sha-base#0
세트: ce1d7da3dc28ae86ca4552a7f22a3154a047faff · 시험: bash tests/harness/test_nano_close_sha_base.sh rc=0 · 이슈: 0
- 2026-10-08 18:40 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§71
