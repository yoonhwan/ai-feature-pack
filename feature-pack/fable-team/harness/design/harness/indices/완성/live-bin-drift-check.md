# 인덱스: 라이브 도구 폴더 ↔ main 키트 드리프트 검사 — tick 경고 + 나노 spawn·close 입구 BLOCK (Issue 816 ②③)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: #816
- 상태: 대기
- 선행: RELEASE 0.4 라이브 bin 교체 완료(master#10 집행 · tar .fable-team/state/live-bin-pre-0.4-1007.tar) — 교체 전 spawn 금지
- 시험 입력: mktemp 리포(bare 원격 + 클론) + mktemp `<x>/.fable-team/bin` 설치 꼴 폴더 — 실제 리포·라이브 폴더·네트워크 0
- 기준값: 없음 → 대체 축 「교체 직후 라이브 bin ↔ 키트 diff -rq 0줄(.bak*·__pycache__ 제외)이 이후에도 유지되는가」 — 지금은 지켜 주는 장치 0(손 cp 로 5개가 옛판으로 뒤처진 10-04~10-07 실측)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 원문 1 C(배포·반영 — 라이브가 main 키트와 «같은 상태로 남는다») + 원문 5(머신 독립 배분 — 이 Mac 의 라이브 = 키트 sha 하나). 핵심 한 줄: Issue 816 범위 축소 승인(오빠 · planner #60527 · issues #60531 · master#10 #60537) — ⓪ 채택 단계 생략 · 덮어쓰기 1회 · ②③ 드리프트 검사 = 이 카드 · ⑤ FT_BIN 이전 = 완성 후. 안 = design/teams/harness/PLAN-release-0.4-and-816-20261007.md 「카드 후보」.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
팀 env 6장(`.fable-team/bin-<팀>/<팀>-env.sh` 11~15행)의 `FT_BIN` 과 launchd `com.byz.ft-tick`(ProgramArguments = 라이브 `ft-tick.sh` · 로그 /tmp/ft-tick.log)은 전부 라이브 폴더 `.worktrees/v6-realtime-live/.fable-team/bin` 을 쓴다. 이 폴더는 git 밖(`.gitignore:178 .fable-team/`)이라 main 키트(`scripts/harness-install/fable-team/bin`)가 랜딩돼도 master 가 손으로 cp 할 때만 바뀐다. 10-07 실측: 5개 파일(ft-nano-close·spawn·slots·evidence-check·role-spawn)이 옛판으로 남아 있었고 아무도 몰랐다. RELEASE 0.4 에서 한 번 1:1 로 맞췄으니, 이 카드는 «다시 어긋나면 바로 보이고, 어긋난 도구로 나노를 열고 닫지 않게» 한다. 비교 기준은 워크트리 체크아웃이 아니라 «git 의 ref»(`origin/main` 의 트리)다 — 리포 루트 체크아웃은 로컬 main 이라 약 18k 커밋 뒤다(R22 실측). 검사는 fetch 하지 않는다(그 ref 가 가리키는 sha 를 출력해 «무엇과 비교했나»를 남긴다). 운영 순서 영향: 키트 bin 을 바꾸는 나노는 «랜딩 → master 라이브 cp → 그 나노 close» 순서가 된다(cp 전 close 는 BLOCK — 의도된 동작).

## 사전검증
- 소환: 아니오
- 면제: 새 스크립트 1개 + 기존 3파일에 «입구 호출 블록» 각 1개다. 설치 꼴(`*/.fable-team/bin`)이 아닌 위치에서 실행되면 검사하지 않으므로 기존 시험·추적본 실행 동작은 무변화다. 되돌림 1커밋 revert + 라이브 cp. 최종 DA 는 완성 이동 때 1회. — arch 서명 byz-harness-arch-claude#8

## 조사 근거
- `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh:15` `HERE=` · 17행 `ROOT=`(git common dir) · 19–28행 팀 env 자동 로드(끝 `fi` = 28행) — 검사 블록은 28행 뒤(FT_BIN 이 팀 env 로 정해진 뒤).
- `scripts/harness-install/fable-team/bin/ft-nano-close.sh:37` `HERE=` · 39행 `ROOT=` · 40–50행 팀 env 자동 로드(끝 `fi` = 50행) — 검사 블록은 50행 뒤 · 206행 `bad=()` 보다 앞(입구 BLOCK).
- `scripts/harness-install/fable-team/bin/ft-tick.sh:22` `HERE=` · 24행 `ROOT=` · 43행 `WT_SWEEP` 끄기 env 꼴 · 247–259행 `sweep_wt()`(master 우편함 송신 꼴) · 261행 `pass()` · 265행 `sweep_wt` 호출(새 호출은 그 다음 줄).
- `tests/harness/test_kit_bin_sync.sh:7` 추적본 `scripts/fable-team-bin` ⊂ 키트 bin (바이트·실행 비트) — 새 파일은 두 사본 모두.
- `tests/harness/test_nano_team_env.sh:18` · `tests/harness/test_nano_close_named_wt.sh:17` — 기존 시험은 `$T/bin/` 에 복사해 돌린다(설치 꼴 아님 → 검사 건너뜀 → 무변화).
- `.gitignore:178` `.fable-team/` — 라이브 bin 은 git 밖.

## 구현 범위 (이 다섯만 — 닫힌 목록 · 추적본 + 키트 사본 같은 바이트)
1. `scripts/harness-install/fable-team/bin/ft-live-bin-drift-check.sh` 신규(+ `scripts/fable-team-bin/ft-live-bin-drift-check.sh` 같은 바이트 · 실행 비트 755).
   - 사용: `ft-live-bin-drift-check.sh --bin <폴더> [--repo <리포>] [--ref <ref>] [--path <트리 경로>]`. 기본 `--ref ${FT_DRIFT_REF:-origin/main}` · `--path scripts/harness-install/fable-team/bin` · `--repo` 없으면 `git -C <bin> rev-parse --path-format=absolute --git-common-dir` 의 상위. `--bin` 없음 = exit 2(usage — FT_BIN 을 추측하지 않는다).
   - 기준: `git -C <repo> ls-tree <ref> <path>/` 의 blob 행(모드·blob·이름). 비교: 라이브에 없음 → `MISSING <이름>` · `git hash-object --no-filters <파일>` ≠ blob → `DIFF <이름>` · 모드 100755 ↔ 실행 비트 불일치 → `MODE <이름>` · 라이브에만 있는 일반 파일(`*.bak*` 제외 · 폴더 제외) → `EXTRA <이름>`.
   - 출력·종료: 같으면 `OK ref=<ref>@<sha12> bin=<폴더> files=<N>` exit 0 · 어긋나면 첫 줄 `DRIFT n=<N> ref=<ref>@<sha12> bin=<폴더>` + 항목 줄 + 마지막 줄 `HINT master 라이브 cp 필요 — design/teams/harness/PLAN-release-0.4-and-816-20261007.md 집행 순서 2~4(tar 백업 → cp → diff 0줄)` exit 1(검사가 직접 cp 하지 않는다) · ref·repo 를 못 풀면 `ERROR …` exit 3(조용한 통과 금지 · #0 RULE).
2. `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh` 28행 뒤 입구 블록(+ 추적본 같은 바이트): `case "$HERE" in */.fable-team/bin|*/.fable-team/*/bin)` 일 때만 `"$HERE/ft-live-bin-drift-check.sh" --bin "$HERE" --repo "$ROOT"` 실행 → rc≠0 이면 출력 그대로 + `REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시` exit 1. 검사 스크립트가 없으면 같은 REJECT(설치 누락 = 드리프트). 설치 꼴이 아니면 `INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $HERE` 1줄. `--dry-run` 도 같은 검사(REJECT 사유를 미리 보여 준다).
3. `scripts/harness-install/fable-team/bin/ft-nano-close.sh` 50행 뒤 같은 블록(+ 추적본 같은 바이트) — `bad=()` 에 넣지 않고 입구에서 exit 1.
4. `scripts/harness-install/fable-team/bin/ft-tick.sh` (+ 추적본 같은 바이트): `drift_watch()` 1개 + `pass()` 의 `sweep_wt` 다음 줄 호출. 간격 `FT_TICK_DRIFT_INTERVAL`(600s · stamp `stamp_of _all drift`) · `FT_TICK_DRIFT=0` 으로 끔(WT_SWEEP 꼴). 설치 꼴이 아니면 아무것도 안 함. `--dry-run` = `DRY kind=drift bin=<HERE> rc=<rc>` 1줄(전송 0). 어긋남이면 `log "drift: n=<N> ref=<ref>@<sha12> <첫 3개>"` 매 회 1줄 · master 우편함 송신은 «어긋남 목록이 바뀐 때만» 1회(서명 = 항목 줄 sha 를 `$STATE_DIR/drift.sig` 에 · 같은 서명이면 송신 0) · 다시 OK 가 되면 서명 파일 삭제 + `log "drift: OK"`. exit 3 이면 stderr 1줄(송신 0 · 조용히 넘기지 않음). master 는 `sweep_wt` 와 같은 `master_seat "$(read_seats)"`.
5. 시험 `tests/harness/test_live_bin_drift_check.sh` 신규 — mktemp 만(실제 리포·라이브 폴더·네트워크 0).
   - mktemp bare 원격에 키트 꼴 트리(`scripts/harness-install/fable-team/bin/` 에 파일 2개 · 하나는 755) 커밋 → 클론 → `<x>/.fable-team/bin` 에 같은 바이트·모드 복사: `OK` exit 0.
   - 각각 따로: 바이트 1개 바꿈 → `DIFF` exit 1 · 하나 지움 → `MISSING` · chmod 644 → `MODE` · 새 파일 → `EXTRA` · `x.sh.bak-1007` 추가 → 여전히 OK(제외 확인) · `--ref nope/main` → exit 3 · `--bin` 없음 → exit 2.
   - spawn 입구: 설치 꼴 폴더에 spawn·검사 스크립트를 복사하고 어긋남을 만든 뒤 `--dry-run` → 출력에 `REJECT 라이브 도구가` · rc=1. 설치 꼴이 아닌 `$T/bin` 에서는 `INFO drift-check 건너뜀`(그 뒤 기존 사유로 끝나도 됨 — 검사 줄만 본다). close 입구도 같은 두 경우.
   - tick: `FT_TICK_SEATS`·`FT_TICK_STATE_DIR`·`FT_TICK_MBOX`(가짜 mbox — 인자를 파일에 적는 스크립트)를 mktemp 로 주고 `--once` 2회 → 송신 1회(같은 서명) · 어긋남을 하나 더 만들고 1회 → 송신 1회 추가 · `--dry-run` → `DRY kind=drift` 1줄. `FT_TICK_DRIFT_INTERVAL=0`.
   - 기존 시험 무변화 rc=0: `tests/harness/test_kit_bin_sync.sh` · `tests/harness/test_nano_team_env.sh` · `tests/harness/test_nano_close_named_wt.sh` · `tests/harness/test_nano_feat_remote_ref.sh` · `tests/harness/test_nano_slots.sh` · pytest `tests/scripts/test_nano_spawn_base_sha.py` `tests/scripts/test_nano_spawn_branch_collision.py` `tests/scripts/test_nano_close_evidence_wiring.py` `tests/scripts/test_nano_close_respawn_worktree.py` `tests/scripts/test_nano_close_cherry_override.py`(`timeout 300 uv run pytest <5파일> -q` · REDIS_PORT=9 · LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1).

커밋은 자기 브랜치, **push 금지**. **금지**: 검사 안에서 fetch · 어긋남을 자동 cp 로 고치기 · ref 를 못 풀 때 OK 처리(조용한 폴백) · 라이브 FT_BIN·팀 env·launchd plist 쓰기(설치는 master 집행) · 우회 env(어긋남인데 spawn/close 를 통과시키는 스위치 — 만들지 않는다. 끄는 스위치는 tick 경고 `FT_TICK_DRIFT=0` 하나뿐).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_live_bin_drift_check.sh` rc=0 · 위 기존 시험 전부 rc=0 · 다섯 파일 두 사본 `bash -n` OK · `cmp` 동일 · `tests/harness/test_kit_bin_sync.sh` PASS(새 파일 포함).
- RESULT 에 실제 출력 3줄 복붙: OK 1줄 · DRIFT 첫 줄 · spawn REJECT 줄.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_live_bin_drift_check.sh rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 bin 에 키트 4파일 cp(새 검사 + spawn·close·tick) → `ft-live-bin-drift-check.sh --bin <라이브 bin>` 이 `OK` · launchd ft-tick 다음 틱(10분 안) /tmp/ft-tick.log 에 `drift:` 줄 0(OK 면 로그 없음) · ★이 카드의 나노 자신은 «라이브 cp 뒤» close★(cp 전엔 BLOCK).
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 9b10aba7b21393512cc52851514b9543c6f89ae8 (spawn 2026-10-07)
- 2026-10-07 — 대기/ 생성 (byz-harness-arch-claude#8 · Issue 816 ②③ · master#10 #60537). 교체 전 spawn 금지.
- 정본 영향 없음: 하네스 키트 스크립트·시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-07 23:27 — 대기→진행 · 좌석 byz-harness-nano-live-bin-drift-check#0
- 2026-10-07 — 증거(나노 byz-harness-nano-live-bin-drift-check#0 · 골 축 원문 1 C·원문 5 · Issue 816 ②③ · master#10 독립 검증 #60568 · arch#8 재현):
  - 변경: ft-live-bin-drift-check.sh 신규(origin/main 트리 blob 대조 · MISSING·DIFF·MODE·EXTRA · fetch 0 · 자동 cp 0 · exit 0/1/2/3) · ft-nano-spawn.sh·ft-nano-close.sh 입구 블록(설치 꼴에서만 · 우회 스위치 0) · ft-tick.sh drift_watch(목록 바뀔 때만 master 송신 · FT_TICK_DRIFT=0 은 경고만 끔) — 추적본=키트 cmp 동일 · tests/harness/test_live_bin_drift_check.sh 신규 · 9파일.
- 세트: 66cee5fd68a061e7c36082e1fd5bf730b4530497 · 시험: bash tests/harness/test_live_bin_drift_check.sh rc=0 · 이슈: 0
- 추가 시험: test_kit_bin_sync ALL PASS · test_nano_feat_remote_ref fail=0 · test_role_spawn_name ALL PASS(master) · 실제 라이브 bin 에 새 검사 1회(읽기만) = `OK ref=origin/main@16201f18ea7c files=74`(arch#8).
- 정본 영향: 하네스 키트 스크립트 4개(추적본·키트)·시험만 — docs/architect 제품 정본 변경 없음 · 라이브 cp(새 검사 + spawn·close·tick)는 master 집행 · ★cp 는 origin/main 병합 + fetch 뒤에만★(ops/main-base 상태로 cp 하면 라이브 ≠ origin/main 이 돼 전 팀 spawn·close 가 BLOCK).
- 2026-10-07 23:33 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§39
