# Changes

## 2026-10-19 — 공유 루트 cwd 에서 v65·lecture 카드 spawn 이 «팀 명단 없음» 으로 끊기던 것을 고친다: 명단 = ref · 폴더 = 호출 워크트리 실재 1개 (1.1.9)

카드 r406 · planner 판정 2318 · master 110115 · arch#94 재현(`ERROR v65 은 팀 명단(TEAMS.md)에 없다 / REJECT … 선언된 정본 없음: /GOAL-LEDGER-v65.md`). 팀 폴더 전환은 main 에만 착지했는데 lint·spawn 이 «호출 워크트리의 design/TEAMS.md» 를 읽어, 명단이 옛 것인 공유 루트(feat/v6-realtime-live)에서 spawn 이 3회 REJECT 됐습니다.

- **lib**: `ft_team_file_ref <루트> <팀> <파일> [<ref>]` — `ft_team_cands_ref`(R400 r3) 후보 폴더 중 <파일> 이 «실재하는 정확히 1개» · 명단 못 읽음·후보 0·2+ = stderr ERROR(ref·후보 경로) rc1. `ft_team_has_ref` — `ft_team_has` 를 ref 명단으로(못 읽음 rc2). ref 기본 = `FT_TEAMS_REF` 또는 `origin/main`. `ft_team_in` 의미는 그대로(다른 도구 영향 0).
- **ft-index-lint.sh**: 기본 골 원장(`default_ledger`) = `ft_team_file_ref <ROOT> v65 GOAL-LEDGER-v65.md` (`FT_GOAL_LEDGER` 명시가 먼저) · 판정 원장 pathspec = ref 명단의 planner 꼴 + 쌍둥이(루트 상대).
- **ft-nano-spawn.sh**: 발주 본문 SEATBELT-README = `ft_team_file_ref <WT> v65 SEATBELT-README.md` (`FT_SEATBELT_README` 명시가 먼저 · 실재 0·2+ = REJECT) · planner 빈 카드 판정 = `ft_team_has_ref`.
- **시험**: 새 `test_team_roster_ref.sh`(ⓐ공유 루트 꼴 dry-run PLAN·lint OK ledger=꼴1 ⓑref 못 읽음 ⓒ후보 0 ⓓ후보 2 → REJECT ⓔ보통 워크트리 불변·명시 env 우선 · 옛 코드에서 13 FAIL). 픽스처 갱신: origin/main ref 없는 임시 리포는 `FT_TEAMS_REF=HEAD`, 발주 README 실재(dead_seat_resume·raised_seat·planner_nano_path·team_literal_paths2·nano_spawn_base_sha·branch_collision·rollback) · `test_nano_spawn_teamset_cap.sh` 픽스처에 `FT_ROOT`·comm 폴더(main 에서도 9 FAIL 이던 기준선).

## 2026-10-19 — 라이브 bin 의 ft-mbox 가 우편함을 못 찾던 것을 고친다: cwd 리포 루트 comm · doorbell 이 우편함을 명시 (1.1.8)

카드 r403 · master 109989(급) · planner 109978 · desk 109974. r385 라이브 bin 전환 뒤 `~/.claude/fable-team/live/<v>/bin/ft-mbox.sh` 는 스크립트 조상에 `.fable-team` 이 없어 어느 cwd 에서 불러도 `NO_MAILBOX_ROOT` rc2 였고, doorbell 이 그 경로로 `recv` 줄을 주입해 받는 좌석도 같은 실패가 났습니다.

- **루트 순서(`ft-mbox.py` · `ft-mbox.sh` `_mbox_dir`/`_seats_json` 같은 걸음)**: ①`FT_MBOX_DIR` ②스크립트 조상 `.fable-team`(옛 설치 꼴 · 불변) ③cwd `git rev-parse --git-common-dir` 부모의 `.fable-team/comm` 이 «이미 실재» 할 때만 ④`NO_MAILBOX_ROOT` rc2 + 「cwd 공용 루트 <경로> 에도 comm 없음」. 우편함 생성은 ①② 만(F4).
- **doorbell**: `[발주 #N] FT_MBOX_DIR=<이 send 가 쓴 comm 절대경로> bash <bin>/ft-mbox.sh recv <to> — …` — 받는 좌석 cwd 무관 · 머리 `[발주 #N]` 첫 토큰 불변(ft-send-verified 영향 0).
- **시험**: 새 `test_mbox_root_resolve.sh`(ⓐ명시 env ⓑcwd 워크트리→리포 루트 comm·sh/py 같은 루트 ⓒ/tmp→rc2·생성 0 ⓓdoorbell 줄 글자·/tmp 실행 READ ⓔ옛 꼴 불변).

## 2026-10-19 — 팀 폴더 이동 뒤 옛 경로에 새 파일을 만들지 못하게 막는다: old-team-path-new-file-gate (1.1.7)

판정 2294 ⓑ(planner 쪽지 109888 «옛 경로 새 파일 DENY») · 카드 r402. 12팀 폴더가 `design/teams/<팀>/`(꼴2)로 옮겨진 뒤에도 쌍둥이 역호환이 «읽기» 뿐 아니라 «쓰기» 까지 열려 있어, 옛 `design/<팀>/` 에 만든 카드·발주서가 두 폴더로 흩어졌습니다.

- **새 훅 `harness/kit/hooks/old-team-path-new-file-gate.sh`**(PreToolUse:Write|Edit|Bash): 대상 경로 = Write·Edit `file_path` · Bash 의 `>`·`>>` 대상과 `cp|mv|install|tee|touch` 마지막 인자(따옴표 밖). 대상이 «없는 파일» 이고, 그 경로가 속한 git 루트의 `design/TEAMS.md` 에서 그 팀 칸이 꼴2 이면 deny + `바른 경로: design/teams/<팀>/…` 1줄. 기존 파일 편집·읽기·리포 밖·꼴1 팀·꼴3 팀·명단 밖 폴더는 통과. 입력 파싱 실패·명단 없음·`ft-team-lib.sh` 못 찾음 = 허용 + stderr WARN 1줄(fail-open). 팀 이름 글자 0(`ft_team_rel` · `$FT_BIN` → `~/.claude/fable-team/live/*/bin` 최신).
- **설치**(`harness/install.sh`): 홈 훅 목록 `HOME_HOOKS`(harness-freeze-gate · old-team-path-new-file-gate)를 `<home>/.claude/hooks/` 로 cp -p → cmp(같으면 건너뜀) · dry-run 에 `HOOK` 줄 · apply 에 `HOOKS copied= same=` 줄. settings.json 등록은 별도(master).
- **시험**: 새 `test_old_team_path_deny.sh`(카드 ⓐ 6절 + 리포 밖·꼴3·절대경로·명단 밖 · Bash `>`/`>>`/tee/touch/mv deny · 읽기·따옴표 글자·옛→새 cp·기존 덮어쓰기·`>&2` 통과 · fail-open 3 · live 최신 lib).

## 2026-10-19 — 좌석 닫기 도구가 «못 닫고 CLOSED» 를 찍지 않는다: 원장 명단은 origin/main · 명부·원장 fail-closed · 다른 리포 좌석 안내 (1.1.6)

판정 2307 ①② · planner 109823(v65·lecture 나노 닫기가 원장 워크트리의 옛 TEAMS.md 때문에 REJECT) · 109839(airag 옛 판 nano-close 가 명부·원장 없이 «CLOSED» 출력 · 세션 잔존 — 1.1.4 도 같은 네 자리) · master 109876(다른 리포 좌석 닫기가 «NOROW ↔ 원장 루트 못 풂» 순환).

- **기본 원장 = «명단은 ref · 폴더는 원장 워크트리»**(`ft-nano-close`): `FT_NANO_LEDGER` 가 없으면 팀 명단을 `FT_TEAMS_REF`(기본 `origin/main`)의 `design/TEAMS.md` 에서 읽고, 명단 꼴·쌍둥이 후보 중 원장 파일이 실재하는 «정확히 1개» 만 씁니다(`INFO 원장 ← <경로> (명단 <ref>)`). 0개·2개·명단 못 읽음은 REJECT(후보 목록). 새 함수 `ft-team-lib.sh` `ft_team_cands_ref <루트> <팀> [<ref>]` — `ft_team_in`·`ft_team_cands` 변경 0.
- **fail-closed 4곳**(`ft-nano-close`): ①명부 파일 없음 ②원장 없음/쓰기 불가 → 입구 REJECT(tmux 조회·변경 전) ③명부 pop 실패 → REJECT(사건 원장 abort) ④원장 append 실패 → FAIL — 어느 경우도 «CLOSED» 줄 0. ★원장은 이미 있는 파일만 씁니다(첫 append 로 만들지 않음).★
- **다른 리포 좌석 안내**(`ft-seat-close`·`ft-seat-retire`): NOROW·원장 루트 실패·«행 없음» 안내에 `FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json` 한 줄(지금 인자로 채움 · 자동 탐색 0 · 동작 변경 0).
- **시험**: 새 `test_nano_close_fail_closed.sh`(ⓐ 명단 origin/main + 쌍둥이 1곳 → CLOSED ⓑ 후보 2 ⓒ 0 ⓓ ref 없음 ⓔ 명부 없음 ⓕ 명부 쓰기 실패 — 고치기 전 코드는 9 FAIL) · `test_seat_close.sh` ⓖ(FT_ROOT + --seats 다른 리포 → CLOSED-ROLE · 원장 그 루트) ⓗ(--seats 없이 → 안내 · rc3) · `test_nano_team_env.sh` 픽스처에 원장 파일 미리 생성 + 옛 이름 좌석 2회 원장 명시.

## 2026-10-19 — 판정 번호로 역할 좌석을 닫는다: ft-seat-close --verdict · ft-seat-retire --record-only --verdict (1.1.5)

planner 판정 2304(오빠 승인 1건)가 현역 역할 좌석 17석을 «재개 기록 → 명부 칸 비우기 → kill» 로 닫으라 했는데, 기존 도구로는 0석이었습니다(master #109747).
`ft-seat-close` 는 `_*` 칸 값(현역)을 거절했고, `ft-seat-retire --record-only` 는 `_replaced_by` 가 있어야만 기록했고, 다른 리포 좌석은 이 리포 명부에 행이 없었습니다.

- **`ft-seat-retire <구> --record-only --verdict <번호>`**: `_replaced_by`·R296 ⓑⓒ 없이 결속(`ft_seat_bind`)만으로 재개 기록(`retired_by = verdict <번호>`) · 행 없음은 R296 ⓐ(`_*` 칸 값이면 REJECT)만 · 명부 쓰기 0 · 출력 꼴 그대로(`RESUME ok` | `NORECORD`).
- **`ft-seat-close <좌석> --verdict <번호> --reason …`**: ⓪실행 세션 자신 REJECT ①재개 기록 실패 = `HELD` rc 3(명부 쓰기 0 · kill 0) ②행 있음 → stop-ready 표기 + `_closed.verdict` + 어느 명부든 값 == 좌석인 최상위 `_*` 칸을 `""`(파일마다 `.bak-close-<ts>` · tmp→mv) · 행 없음 = `NOROW` rc 3(kill 0 · 그 리포 루트에서 다시) ③계보 검사 건너뜀 → 태그 해제 → kill → `CLOSED-ROLE … kill=ok` + 원장 `<데이터 루트>/.fable-team/state/seat-close-verdict.log` 1행.
- **codex 좌석 재개 기록**(master #109793 — 실측 da-codex#4 «세션 파일 0개» HELD): 결속 판정기 `ft_seat_bind.bind` 가 claude 세션 파일이 0개일 때 pane 자손(깊이 ≤4) 중 실행 주체 codex 가 연 `~/.codex/sessions/**/rollout-*.jsonl` «정확히 1개» 로 결속(첫 줄 session_meta id == 파일명 끝 · 시작시각 ≤ mtime) · 기록 `engine=codex` · model = argv `-c model=` → rollout `turn_context` · `resume_cmd = codex <원래 인자> resume <id>`(zombie-clean resume 은 claude 기록만 받는다 — 변경 0 · `--expect` 변경 0).
- **`ft-nano-close` 카드 탐색**(master #109792 — r385#0 «⑥카드 못 찾음»): 명부 index 경로에 카드가 없으면 같은 `indices` 뿌리의 형제 폴더(대기·진행·완성)에서 같은 파일명이 정확히 1개일 때만 그 카드 + `INFO 카드 위치 ← <경로>` · 0·2+ 는 REJECT 그대로(`형제 N개`) · 명부 쓰기 0.
- `--verdict` 없는 호출은 동작 그대로 · **시험**: `test_seat_close.sh` ⓑ~ⓕ·usage(가짜 tmux · retire 스텁) · `test_seat_retire.sh` ⑮(현역 행·행 없음·`_*` 칸·결속 실패·usage) · ⑯(가짜 codex 트리: 정상·rollout 2개·0개·id 불일치) · `test_nano_close_named_wt.sh`(형제 1개 → CLOSED · 2개 → REJECT).

## 2026-10-19 — 설치본에서 보드 루트를 풀고, 하네스가 리포 밖일 때 범위 대조를 통과시킨다 (1.1.4)

1.1.3 설치본으로 전환한 뒤 실제 실행에서 두 곳이 막혔습니다(master #109675).
나노 닫기·spawn 이 «사건 원장 prepared 실패» 로 거절됐고(`ft_board_env.ft_root` 가 `git -C <설치본 bin>` — git 밖), 카드 완성 이동·착지가 `INSTALL ERROR` 로 막혔습니다(`ft-live-install-check --range … --repo <BYZ>` 가 «하네스 루트가 --repo 밖» 이면 항상 ERROR).

- **보드 루트**(`ft_board_env.ft_root`): `FT_ROOT`(그 값 그대로) → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 `git -C <bin>` 공용 루트 → RuntimeError(사유에 cwd·경로). 호출 12곳 변경 0.
- **범위 대조**(`ft_live_install_check.resolve_kit`): 하네스 루트가 `--repo` 밖이고 `--kit` 가 없을 때 — `--range A..B` 가 건드린(ACMR) 옛 하네스 경로(`scripts/fable-team-bin/` `scripts/harness-install/` `tools/comm-canonical/` `tests/harness/` `kit/` · 팩 꼴 `**/harness/kit/**`) 파일이 0 이면 `OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)` rc0, 1개라도 있으면 ERROR(파일 목록) rc3. `--all` 은 ERROR 그대로.
- **시험**: `test_installed_root.sh` ⓔ 절(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · 설치본 `ft-sheet-events.sh` git 밖 ERROR · spawn 경로 key+prepare rc0 · 임시 HOME 쓰기 0) · 새 `test_install_check_repo_outside.sh`(하네스 0 → OK · `^..`·`--ref` 호출 꼴 · 하네스 1 → ERROR+파일명 · 팩 꼴 키트 1 → ERROR · 삭제만 → OK · `--all` → ERROR).

## 2026-10-19 — 설치본에서 «파일 위치 조상 탐색» 없이 루트·comm 을 푼다 (1.1.3)

1.1.2 설치본(`~/.claude/fable-team/live/1.1.2/bin` · git 밖)으로 LIVE_BIN 을 바꾸자 골 표가 «루트 없음» 으로 멈춰 쪽지 가드가 발주·보고를 막았고, LIVE_BIN 을 되돌렸습니다.
골 표 루트(`ft_goal_ledger.find_root`)와 형제 `../comm` 이 «이 파일 위치의 조상» 에 기대고 있었는데, 설치본은 `<버전>/{bin,templates,HARNESS_ROOT}` 뿐이라 둘 다 없었습니다.
(1.1.1 데이터 루트 해석기 · r386 팀 경로 지도 fallback 과 같은 «설치본 루트» 묶음입니다.)

- **골 표 루트**(`ft_goal_ledger.find_root`): `FT_ROOT` → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 파일 위치 조상 → ERROR.
- **comm**: 해석기에 `ft_comm_dir`(= `$(ft_data_root)/.fable-team/comm` · 옛 설치 꼴이면 옛 `$HERE/../comm` 과 같은 곳 · 없으면 ERROR) 1함수 추가 — 기존 함수 변경 0.
  쓰는 곳 17: harness-info · hil-ask · hil-answer · mbox-bridge(mbox·mbox-v2) · plan-handoff · tick · disk-alarm · issue-create-pair · launchd-check · magazine-check ·
  resource-reclaim · seat-live · secret-scan · spawn-hold · tick-team · send-verified · context-monitor(각 도구의 env 가 먼저).
- **데이터 루트 `../..`**: install-pending · seat-handover → `ft_data_root` · `ft_penalty.root` → 리포 공용 루트 순서(ft_repo_root 와 같음) · `ft_op_token.secrets_dir` → env → 옛 꼴 → cwd 리포의 `.fable-team/secrets` → ERROR.
- **시험**: `harness/tests/test_installed_root.sh`(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · tick·hil-ask mbox 경로 · git 밖 ERROR + 임시 HOME 쓰기 0 · 실제 BYZ cwd 골 표 rc0).

## 2026-10-19 — 설치·실행 위치 전환 준비: 팩에서 바로 설치하고 BYZ 하네스 폴더를 얼린다 (1.1.2)

1.1.1 로 도구가 git 밖 설치본에서도 데이터 루트를 풀게 됐지만, 키트 글자·설치 입구는 아직 BYZ 리포 안 옛 위치(`scripts/fable-team-bin` 등)를 전제했습니다.
이 판은 팩 하네스만으로 설치·대조가 되게 하고, 전환 동안 BYZ 쪽 하네스 커밋을 막는 장치를 더합니다(카드 r385 · LIVE_BIN 1줄 전환은 master).

- **경로 글자**: `harness/bin`·`harness/kit` 의 `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical` → `harness/bin`·`harness/kit`·`harness/comm`(주석·안내문 포함 0건).
- **설치**(`harness/install.sh --apply --project <루트>`): `--project` 필수(cwd 추론 0 · 없으면 rc2 쓰기 0) · 키트 `bin`·`templates` 를
  `<home>/.claude/fable-team/live/<version>/` 에 cp+cmp · `<version>/HARNESS_ROOT` 1줄(= `ft_harness_root` ② 지도) · 설치본 shim 으로 프로젝트 `LIVE_BIN`·`LIVE_ROOT`(있으면 보존) ·
  2회째 복사 0 · 끝에 «되돌림 1줄»(LIVE_BIN 이전 값) 출력.
- **대조**: `ft-live-install-check.sh --kit/--project` · 하네스 bin launchd 항목에 `WorkingDirectory`·`FT_ROOT` 없으면 `NOROOT` · shim·live-install `--repo/--path` 기본 = 하네스 코드 루트.
- **freeze 가드**(`harness/kit/hooks/harness-freeze-gate.sh` · PreToolUse:Bash): 대상 저장소 공용 루트에 `.fable-team/state/harness-freeze` 가 있으면
  `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical`·`tests/harness` 를 건드리는 커밋을 REJECT(카드 `design/harness` 는 r386 이전까지 BYZ 에서 커밋 — 막지 않음)(staged · `-a`/pathspec 이면 작업 트리도) · 표식 없으면 통과.
- **홈 훅 5**(autonomy-interview-gate · autonomy-merge-guard · gh-issue-author-guard · merge-head-gate · tracked-bin-call-gate): 옛 위치 후보 대신 루트 shim · LIVE_BIN · `$FT_HARNESS_ROOT/bin`.
  홈 적용분은 `harness/evidence/r385/home-hooks.patch`(+ freeze 가드 새 파일 · dry-run 원문 같은 폴더) — 적용은 master.
- **시험**: `harness/tests/test_harness_freeze_gate.sh`(표식 없음 통과 · staged/-a/--all/cd/-C/워크트리 REJECT · 4폴더 밖·메시지 글자 통과 · 해제).

## 2026-10-19 — 데이터 루트 해석기 2종: 설치본이 git 밖이어도 루트를 조용히 잘못 풀지 않는다 (1.1.1)

라이브 설치본을 `~/.claude/fable-team/live/<version>/bin`(git 밖)으로 옮기면, 키트 도구 35곳이 «자기 위치»(`git -C $HERE` 공용 루트 · `$HERE/../..`)로
데이터 루트를 풀다 `~/.claude/fable-team/live` 로 풀렸습니다 — 자율 상태·spawn 정지 파일·자원 표·press 허가를 못 보는 회귀입니다.
실측해 보니 루트가 두 종류였습니다: 리포 공용 루트(BYZ 메인 `.fable-team/state`)와 라이브 루트(`LIVE_ROOT` · v6 `.fable-team/state`).

- **해석기**(`harness/bin/ft-harness-root.sh` · 키트 짝 같음): `ft_repo_root` = 옛 설치 꼴(`*/.fable-team/bin`)이면 `git -C $HERE` 공용 루트(없으면 `$HERE/../..`)
  → cwd git 공용 루트(`.fable-team/` 있을 때) → ERROR · `ft_data_root` = `FT_ROOT` → cwd git 공용 루트의 `.fable-team/LIVE_ROOT` 1줄 → 옛 설치 꼴 `$HERE/../..` → ERROR.
  어느 쪽도 못 풀면 rc≠0 로 멈춥니다(조용한 후퇴 0). 각 도구의 기존 env(`FT_RES_ROOT`·`FT_SECRET_SCAN_ROOT`·`FT_ROOT`)는 그대로 우선.
- **리포 공용 루트 묶음**: spawn-hold · resource-gate/watch/sample/cause/reclaim · disk-alarm · disk-census · scratch-repo · secret-scan · fp-run ·
  issue-close-check · weekly_review · board-publish · sheet-publish/verify · gh-tank-comment-edit · gh-tank-edit-bak · idle-wake · measure-net ·
  seat-request · seat-live · seats-lint · tick-line · successor-open(자원 문지기 루트).
- **라이브 루트 묶음**: autonomy · autonomy-start · proxy-decide · resume-cmd · resume-attempt · press-gate · press-permit.
- **드리프트 입구**(nano-spawn · nano-close · tick): 설치 꼴에 `*/fable-team/live/*/bin` 추가 · `--repo` 생략 → drift-check 기본 = 하네스 코드 루트(`FT_HARNESS_ROOT` · `<버전>/HARNESS_ROOT`)의 키트.
- **launchd 템플릿** weekly-review · secret-scan: `WorkingDirectory` 로 cwd 루트를 준다.
- **시험**: `harness/tests/test_harness_root.sh`(git 밖 설치본 + cwd git 밖 → ERROR · 임시 HOME 쓰기 0 / cwd 워크트리 → 공용 루트·LIVE_ROOT / env · 옛 설치 꼴 회귀 0).

## 2026-10-18 — harness 합류: BYZ 하네스 6경로를 이력째 팩으로 (1.1.0)

하네스 실행 도구·키트·통신·카드 원장·시험·옛 증거가 BYZ-Agents 리포에만 있어 패치·버저닝·산출물 관리가 두 레포로 갈렸습니다.
6경로를 커밋 이력째 `harness/` 로 옮겼습니다(판정 2270 · BYZ 711199fd62 기준 · BYZ 삭제는 다음 단계).

- **레이아웃**(`harness/`): `bin/`(←`scripts/fable-team-bin` 227) · `kit/`(←`scripts/harness-install` 459) · `comm/`(←`tools/comm-canonical` 31) ·
  `design/harness/`(←`design/teams/harness` 756 · 옛 `design/harness` 이력 포함) · `tests/`(←`tests/harness` 224 + `tests/scripts` 하네스 시험·도우미 47) ·
  `evidence/state-v6/`(←`.fable-team/state/v6-*` 88). `skill/` 은 그대로 — 규칙·참조는 skill, 실행 도구는 harness.
- **버전**: `manifest.json` `version` 이 유일한 출처 — 이 절부터 0.1.0·1.0.3 어긋남을 1.1.0 으로 통일. 팀 폴더 틀 버전(`harness/kit/fable-team/templates/team/VERSION` 1.0.0)은 별개 의미라 그대로.
- **설치 입구**(`harness/install.sh`): manifest version 을 읽어 `~/.claude/fable-team/live/<version>/` 와 프로젝트 `LIVE_BIN`·`LIVE_ROOT` 계획을 출력(지금은 `--dry-run` 만 · 실제 설치는 다음 단계).
- **재배치 대조**(`harness/tests/test_pack_relocation.sh`): 경로 표 5행마다 BYZ 기준 sha 와 팩의 파일 수·sha256 목록이 같고 표 밖 파일 0 · 이력 커밋 수 대조.

## 2026-10-02 — 단일 세트 · 나노 생애 · 오래된 나노는 루트부터 (1.0.3)

BYZ-Agents v65 에서 09-25 카드를 재대조 없이 10-02 코드에 집행하고, 옛 sha worker 로 돌린 A/B 를 근거로 HEAD 를 덮어쓸 뻔했습니다(미랜딩 nano 277/590 · 나노 브랜치 221커밋 뒤처짐).

- **규칙**(`references/SEATBELT.md` §6-3): 단일 세트 시험 · 나노 생애 ①~⑤(최신 루트 병합→시험→이슈 확인→squash) · 랜딩 = 라이브 1회까지 · 방치 0.
- **스크립트** `scripts/ft-nano-freshness.sh`(읽기 전용): base·루트 뒤처짐·겹침 파일·미랜딩 패치·dirty → FRESH/STALE/STALE-OVERLAP/LANDED.

## 2026-10-02 — 워크트리 위생: Serena project.yml 커밋 금지

BYZ-Agents 의 모든 워크트리에서 Serena 가 `.serena/project.yml` 을 자동 갱신해 세션마다 modified 로 떴습니다.
추적 해제 + gitignore 를 BYZ 가 적용했고(4305b6925), 같은 규칙을 팩의 플레이북에 넣었습니다.

- **규칙**(`references/orchestration-playbook.md` «워크트리 위생»): project.yml 커밋 금지 · Serena 는 본인 워크트리 절대경로로 활성화.

## 2026-10-01 — checkpoint 계약: 시험·press 를 돌린 워커가 그 회차의 tester·checker

BYZ-Agents v65 에서 과금 랜딩이 폴리싱·완료 말풍선을 끊는 회귀를 냈는데, 측정 워커가 자기 측정 조건만 보고
6회차를 VALID 로 넘겼고 사용자가 화면을 보고 잡았습니다. 수정 범위가 넓고 시스템이 커서 «한 곳을 고치면 다른 곳이
끊기는» 일이 잦기 때문에, 랜딩마다 BTS 4축 + poller 고정 칸을 도구로 확인하는 계약을 팩에 넣었습니다.

- **계약**(`references/SEATBELT.md` §6-2): 시험·press 를 돌린 워커 = 그 회차 tester·checker. 회차마다 프로젝트가 선언한
  checkpoint 를 돌려 고정 칸 표를 보고에 첨부 · 경보(exit 3)면 VALID/완료 보고 금지 → 4축 정리 → arch(+DA) 처방 →
  같은 워커 수정 → 재실행.
- **도구**(`scripts/ft-checkpoint.sh`): 프로젝트 `.fable-team/checkpoint.json`(명령·경보 exit·필수 칸)을 실행 ·
  exit 0 정상 / 3 경보 / 4 표·칸·명령 실패 / 5 미설정(무음 통과 금지).
- **닫기 조건**(`scripts/ft-nano-close.sh` ④): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no. 미설정 프로젝트는 경고만.
- **적용**(`references/update.md`): 프로젝트별 checkpoint.json 예시 3줄.

## 2026-09-30 — 승계 6단계 + 지시 원장 트리 + 누락 전수 점검

사용자 지시(BYZ-Agents v65 master#86 작업 방법 공유)를 베이스에 반영했습니다. 승계 때 후계에 상태·할 일이
안 넘어가고, 범위 한정으로 닫힌 행 아래의 사용자 지시가 통째로 누락되던 문제(16건 중 8건)에 대한 규율입니다.

- **승계 6단계**: 스냅샷 커밋 → 후계 스폰 → 상태·할 일·컨텍스트 요약 mbox 재송신 → 후계 응답(골 대조) recv →
  뉴스·크론이 후계로 가는지 확인 → 구 좌석 유휴. 후계 발주문에도 6단계를 적습니다.
- **트리 = 골 원장 행 + 사용자 지시 원장 열린 항목**: 행을 범위 한정으로 닫을 땐 하위 지시 항목의 완성 전/후 이관 줄 필수.
- **승계 첫 일 누락 전수 점검**: 지시 × 카드 × 닫힘 sha 대조, «카드 없음 + 증거 없음» 맨 위.
- **설명은 사용자가 겪는 일로**, **아키텍처 영향 사건은 즉시 아키텍처 원장에 기록**.

반영 위치: `skill/SKILL.md`(운영 규율 5~7), `skill/templates/rules/orchestration.md`(컨텍스트 증류 절 — 프로젝트로 복사되는 정본),
`skill/references/context-management.md`(§2.5 승계 6단계).

## 2026-07-28 — 문제해결 표준 체인 + checker 4축 실측 규칙

역할 경계를 두 군데 조였습니다. 출처는 BYZ-Agents v6-realtime-live 커밋 `2216ffdc`(FB_Master#88 규율 업데이트).

- **문제해결 표준 체인**: `checker → 오케(Master) → architect → (DA) → 오케(Master) → impl`.
  checker는 실측·정리만 하고 판정을 붙이지 않습니다. 오케(Master)는 checker 정리에 의심 방향을 얹어
  architect에 넘기되 **그것이 관찰이지 판정이 아님을 명시**합니다. 원인 규명·설계 판정은 architect가
  하고 **DA 소환 여부도 architect가 정합니다**(DA는 architect에 회신). 최종본 라우팅은 다시 Master.
  - 오케(Master)가 **하지 않는 것 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환.
  - **DA 상시 대기 금지** — `DA approve loop` / `DA review`로 필요할 때만. 대기 유지 자체가 왕복과
    조건 증식을 만듭니다(실증: 조건 7항 증식 → 라이브 지연).
- **checker 4축 실측**: FE 콘솔 / poller·DOM / worker(서버 로그) / durable 저장소를 전부 봅니다.
  FE 미확인 전 "처리 실패" 판정 금지, poller·DOM 미확인 전 "출력 없음" 판정 금지, 복수 호출은 전부
  나열하고 실패 지표가 몇 번째인지 명시. **사용자가 눈으로 본 것과 분석이 어긋나면 분석이 틀린 것**
  — 그때는 안 본 축부터 봅니다.

반영 위치: `skill/SKILL.md`, `skill/references/rapid-iteration-loop.md`(정본 — 역할 체인·4축·안티패턴 11~13),
`skill/templates/rules/orchestration.md`, `skill/templates/session-prompts/{checker,architect,da-codex,da-cursor}.md`,
`skill/references/agent-templates/{ft-checker,ft-architect,ft-da,ft-da-cursor,ft-da-claude}.md.tpl`.

## 2026-07-11 — v3 업그레이드 (tmux 기반 전면 개편)

fable-team이 각 에이전트를 tmux 세션으로 직접 띄우고, 서로 메시지를 주고받고, 작업이 끝나면 스스로
정리하도록 구조를 전면 교체했습니다. 여기에 더해 세션 압축(증류) 시 모델의 확장 컨텍스트(1M)/추론
강도 설정이 유실되던 문제 수정, 전문가(fable-5) 브레인의 전체 구현 재검토, 대규모 동작 검증(23개
시나리오) 중 실측으로 발견한 버그 다수를 함께 처리했습니다.

- 요약 문서: [docs/artifact/2026-07-11-v3-upgrade-summary.html](docs/artifact/2026-07-11-v3-upgrade-summary.html)
- 설계 원문: [.fable-team/designs/roster-v3-design.md](.fable-team/designs/roster-v3-design.md)
- 구현 전체 검토 보고서: [.fable-team/state/v3-upgrade-design/implementation-review-fable5.md](.fable-team/state/v3-upgrade-design/implementation-review-fable5.md)
- 진행 원장(전 과정 기록): [.fable-team/state/state.md](.fable-team/state/state.md)
