# r444 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r444-finished-cleanup-auto-sweep-refs-ar` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(fd304397 · r443 착지 뒤) 위. 파일 = bin·kit 짝(cmp 0) 7: `ft-wt-sweep.sh` · `ft-scratch-repo.sh` · `ft-nano-spawn.sh` · `ft-nano-close.sh` · `ft-index-move.sh` + 새 `ft-finished-check.sh` · `ft-branch-archive.sh`
   + 새 `kit/launchd/com.byz.ft-wt-sweep.plist.template` + 새 시험 `tests/test_finished_cleanup_auto.sh` + 고친 시험 `tests/test_scratch_repo.sh`(ⓞ·ⓟ — 나이 문턱 0·tmux 실패 sweep 출력) · `tests/test_wt_clean_two_stage.sh`(ⓔ 껍데기 경보 문구 = 팀별 `seat=` 꼴) + 증거 `evidence/r444/`.
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(병행 가지 충돌 방지) — 착지 순서대로 master 가 다음 번호. 문안 = 아래 «CHANGES 절».
2. 되돌림 준비(설치 전): LIVE_BIN 7 파일 각각 `cp -p <LIVE_BIN>/<f>{,.bak-r444}`(새 파일 2 는 없음 = 되돌림 시 삭제) · launchd 되돌림 `launchctl bootout gui/$UID/com.byz.ft-wt-sweep`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 7 파일 `cmp <키트>/fable-team/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` (새 plist 는 적재 전 `NOTLOADED com.byz.ft-wt-sweep` PENDING — 4 뒤 OK).
4. plist 렌더·적재(1개 — 아래 «편차 ①»):
   `sed -e "s|__FT_BIN__|<LIVE_BIN>|g" -e "s|__BYZ_ROOT__|<BYZ 루트>|g" <키트>/launchd/com.byz.ft-wt-sweep.plist.template > ~/Library/LaunchAgents/com.byz.ft-wt-sweep.plist`
   → `plutil -lint` OK → `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.byz.ft-wt-sweep.plist` → `launchctl kickstart gui/$UID/com.byz.ft-wt-sweep`(첫 실행 = 계획 20장 + 끝난 가지 재확인 200).
   ★매일 04:15 자동 · 사람 h 0★. 표준승인 범위 그대로(nano/* · 세션 없음 · [wip] 먼저 · 브랜치 «이동» 만 · `-D` 0).
5. 실사건 3(닫는 증거):
   ⓐ `<BYZ>/.fable-team/state/wt-sweep.log` 끝 줄 `cleaned=N`(N≥1) + `ls <BYZ>/.fable-team/state/wt-clean/*.sh | wc -l` 이 5,497 에서 줄어듦.
   ⓑ 임시 사본: resource-watch(이미 launchd) → disk-alarm 하루 1회 `--sweep` 이 새 tmux 해석으로 돈다 — 바로 보려면 표준승인 경로 1회 `FT_RES_ROOT=<BYZ> bash <LIVE_BIN>/ft-scratch-repo.sh --sweep` → `<BYZ>/.fable-team/state/scratch-sweep.log` 끝 줄 `swept=N owner-dead=N`(주인 죽은 등록 사본 10행 → 0).
   ⓒ 완성 이동 1건을 `ft-index-move.sh <진행 카드> 완성 --da … --landed <착지 sha>` 로 → 카드 끝 `- 착지: <sha>` + 출력 `ARCHIVED nano/<slug> <sha> restore: …` → `git rev-parse refs/archive/nano/<slug>` 있음 · `git branch --list nano/<slug>` 0.
6. 뒤 일(arch 손 · 착지 뒤): BOOT 37 끝 1절 «닫기 계획·임시 사본은 launchd sweep 이 지운다(사람 h 0) · 끝난 가지는 refs/archive 로 옮긴다(r444)» · 전역 하드 룰 2 판정 2354 줄에 `강제 = ft-branch-archive.sh`.

## 편차·범위 밖 (나노 판단 · 근거)
- ① plist 2 → 1: 임시 사본 sweep 은 이미 `com.byz.ft-resource-watch`(60s) → `ft-disk-alarm.sh` 하루 1회로 launchd 에서 돈다. «생략» 원인 = 그 plist 에 PATH 가 없어 homebrew `tmux` 를 못 찾음(`disk-alarm.log` «tmux 목록 실패» 3줄 · plist env = FT_ROOT·FT_RES_ROOT 뿐 실측). 도구가 tmux 를 `FT_TMUX_BIN → PATH → /opt/homebrew/bin → /usr/local/bin` 으로 풀게 고쳤다 — 두 번째 plist 를 만들면 같은 sweep 이 하루 2회.
- ② `ft_live_install_check.py` plist-env 행 2: r426(설치기 plist env 갱신 · `nano/r426-installer-updates-launchd-plist-env`)가 origin/main 미착지 — 카드 «선행» 대로 r426 r2 로 넘긴다. 새 plist 적재 여부는 기존 `*/*.plist.template` 행(NOTLOADED)이 이미 잡는다.
- ③ spawn 여유 검사 → 회수 호출: r440 미착지 — 카드대로 «REJECT [HIL] 1줄»(spawn 0) · r440 뒤 연결.
- ④ sparse 범위: 남의 팀 `design/teams/<남>/` 만 뺀다. 자기 팀 증거 폴더·`design/evidence` 는 체크아웃 — 실측: sparse 밖 경로의 새 파일 `git add` 가 rc1(«outside of your sparse-checkout definition») → 증거를 쓰는 나노가 막힌다. 그래서 v65 나노(자기 팀 1.1G 대부분이 증거)는 거의 그대로 · 하네스·다른 팀 나노는 v65 1.1G 를 안 받는다. 끄기 `FT_NANO_SPARSE=0` · 되돌림 `git -C <워크트리> sparse-checkout disable`.
- ⑤ `ft-branch-archive` 가지 빼기: `git branch -d`(합쳐진 가지) → 거절(squash 착지)이면 `git update-ref -d refs/heads/<가지> <sha>`(보관 ref 가 같은 sha 로 «먼저» 확인된 뒤에만 · old-value 검사) — 판정 2354 «이동»의 뒷반쪽. `-D` 0.
- ⑥ E1 착지 줄: `ft-index-move` 가 지금까지 `착지:` 줄을 안 썼다 → `완성 --landed <sha>` 일 때 `- 착지: <sha>` 를 쓰게 했다. 그 전 완성 카드(착지 줄 없음)의 가지는 FINISHED 가 아니다(ACTIVE · 이동 0 · fail-closed) — 기존 적체 가지는 이 단위로 안 줄어든다.
- ⑦ `ft-team-path-lint.sh`: 팩에서 `OK 하드코딩 0`. BYZ 명단(`FT_REPO_ROOT=<BYZ>`)으로 돌리면 ② `ERR 쌍둥이 후보 남음: ft-nano-close.sh ft-nano-spawn.sh` — base(fd304397)에서도 같은 ERR(이 단위 이전 `ft_index_twin` 호출). 걷어내면 `test_team_move_roundtrip.sh ⓑ'`(쌍둥이 동작 시험)이 깨져 되돌렸다 — 후속 카드 1장.
- 기존 실패(이 단위와 무관 · base fd304397 에서 같은 수): `test_team_literal_paths2.sh` fail=18 · `test_team_move_roundtrip.sh` fail=2 · `test_ft_wt_sweep_route_timeout.sh` fail=1(ⓕ 머리 순서 가드) — `evidence/r444/test.txt`.

## CHANGES 절 (착지 번호를 붙여 머리에)
## 2026-10-19 — 끝난 것이 자동으로 지워지게: wt-sweep launchd 일 1회 · 임시 사본 sweep 이 launchd 에서 tmux 를 읽음(주인 죽으면 즉시) · 판정기 ft-finished-check · 끝난 가지 refs/archive 이동 · 나노 sparse 체크아웃 (1.1.N)

카드 r444 · 판정 2354·2355 · planner 111324·111349 · master 111351·111367·111370·111426 · 오빠 10-19 «완전히 끝났으면 정리 삭제하는 룰이 없이 쌓아두는 게 문제». 닫기 계획 5,497장이 실행 경로(launchd) 없이 쌓였고, 임시 사본 sweep 은 launchd PATH 에 tmux 가 없어 «판정 생략», 끝난 가지는 지우는 룰 없이 2,297개, 나노 하나가 남의 팀 design 까지 1.5Gi.

- **`ft-wt-sweep.sh --launchd`** + **`kit/launchd/com.byz.ft-wt-sweep.plist.template`**(매일 04:15): FT_ROOT 필수 · sweep 1회(MAX 20) → [HIL] 을 팀 master 로(ft-tick 과 같은 규칙) → 끝난 가지 재확인(nano/* 최신 200) → `state/wt-sweep.log` `cleaned=N wait=N hil=N … archived=N`. 껍데기 경보는 폴더 주인 팀마다 `seat=byz-<팀>-wt-shell`(팀 = .worktree-info purpose · 못 정하면 harness — v65 로 몰리던 것 #111412).
- **`ft-scratch-repo.sh`**: tmux = `FT_TMUX_BIN → PATH → /opt/homebrew/bin → /usr/local/bin`(+`FT_TMUX_SOCKET`·`FT_TMUX_TMPDIR`) · 못 읽으면 `--sweep` stdout `ERROR tmux unreadable`(→ disk-alarm 이 planner 쪽지) + 삭제 0 · 등록 사본은 주인 세션 죽으면 즉시(24h 문턱 제거) · 로그 `swept=N owner-dead=N tmp=N` · 같은 sha·주인 사본 재사용.
- **새 `ft-finished-check.sh <폴더|브랜치>`** → `FINISHED|EMPTY|ACTIVE|ORPHAN` + E0(porcelain 0)·E1(카드 `착지:` ⊂ origin/main)·E2(indices/완성/)·E3(tmux·명부·cwd 좌석 0 · tmux 못 읽으면 ACTIVE).
- **새 `ft-branch-archive.sh`**: FINISHED 만 `refs/archive/<이름>` 새로 만들기(덮기 0) → 확인 → 가지 목록에서 뺌(`-d` → squash 면 old-value 검사 `update-ref -d`) · 실패면 가지·폴더 그대로 SKIP · 공백 → `_` · 로그 되살림 명령. `ft-index-move … 완성 --landed` 가 `- 착지:` 줄을 쓰고 1회 호출.
- **`ft-nano-spawn.sh`**: 새 워크트리 전 디스크 여유 < 40Gi(`FT_NANO_MIN_FREE_GI`) 면 REJECT [HIL](spawn 0 · 측정 실패도) · sparse(남의 팀 `design/teams/<남>/` 제외 · 자기 팀 통째 · `FT_NANO_SPARSE=0` 끔).
- **`ft-nano-close.sh` ⑥**: 카드 = 팀 폴더 리졸버(`ft_team_cands_ref`) 진행→완성→대기 먼저 — 옛 `design/<팀>/indices/대기` 사본이 실제 카드를 가리던 L6b(#111324).
- **시험** `tests/test_finished_cleanup_auto.sh` ⓐ~ⓛ ALL PASS · `test_scratch_repo.sh` ⓞ·ⓟ 갱신. 증거 `harness/evidence/r444/`.
