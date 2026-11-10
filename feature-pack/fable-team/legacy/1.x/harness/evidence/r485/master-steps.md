# r485 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 가지 `nano/r485-goal-check-ledger-key-and-state-sin` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 = origin/main(3ca1e15f · r479·r478d 착지 뒤) 위. CHANGES 머리 + manifest 1.1.40 은 이 가지에 넣었다 — 다른 가지가 먼저 착지하면 번호만 다음으로 올린다.
   파일 = bin·kit 짝(cmp 0) 1: `ft-goal-check.sh` (+ 시험 `test_goal_check_ref.sh` 절 추가 · CHANGES · manifest).
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft-goal-check.sh{,.bak-r485}`. 상태 파일은 지우지 않는다(옛 v6-realtime-live 쪽 `goal-read-ledger.json` = 이력 · 삭제 0).
3. 착지 뒤 `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>` → `cmp <키트>/ft-goal-check.sh <LIVE_BIN>/ft-goal-check.sh` = 0 (+ 같은 LIVE_BIN 의 `ft-harness-root.sh` 실재 — 새로 source 한다) · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK. plist·틱 재시작 0(틱이 매번 새로 부름).
4. 1회 이행(v65 master 손): 설치 직후 자기 워크트리에서 `.fable-team/bin/ft-goal-check.sh '<좌석>' --touch "<원장 닫는 증거 복붙 20자+>"` 1회 →
   출력 `GOAL-READ … ref=<sha> state=<공용 루트>/.fable-team/state/goal-read-ledger.json OK` 의 state 가 공용 루트인지 확인. 옛 꼴 행(ref_sha 없음)은 첫 틱에 REREAD «옛 꼴 행 — 다시 touch» 1회가 정상.
5. 실사건 1(닫는 증거): 다음 goal-tick 2회 연속 `tick quiet … rc=0`(`/tmp/ft-tick.log`) 또는 좌석 pane «GOAL-OK» · REREAD 0 · 쪽지 번호.
6. 뒤 일(arch 손 · 착지 뒤): `COMM-GUIDE-BOOT.md` 14 자리 규칙 줄에 «골 원장 판정 키 = ref origin/main sha · 상태 = 공용 루트 `state/goal-read-ledger.json` 1개(r485)».

## 동작 요약 (카드 §구현 범위 대조)
- 1 상태: `DATA="${FT_ROOT:-$(ft_repo_root "$HERE")}"` · 못 풀면 `ERROR seat=… 공용 루트를 못 풂` exit 4(cwd 에 조용히 쓰기 0) · `STATE=$DATA/.fable-team/state/goal-read-ledger.json`.
- 1 키: `LSHA`·`SSHA` = `git log -1 --format=%h $REF -- <명단 꼴 경로>` 두 분기 공통 · `REF_SHA=$(git rev-parse --short $REF)` 를 touch 행 `ref_sha` 에 저장(`head_sha` 칸 유지) · `ref_sha` 없는 행 = REREAD «옛 꼴 행 — ref_sha 없음 · 다시 touch» · 경과 = `rev-list --count <ref_sha>..$REF`.
- 1 출력: GOAL-READ 에 `ref=<sha> state=<경로>`. ROOT(cwd 루트)는 cited grep · NEXT 행 읽기 · 명단 WARN 에만.
- ⓕ 훅: `scripts/git-hooks/v65-goal-commit-msg.sh`(BYZ) 는 상태 파일을 직접 읽지 않고 `$root/.fable-team/bin/ft-goal-check.sh "$FT_SEAT"` 를 부른다(:36 `SEAT_CHECK` · :175-179) → 상태 경로 상수 없음 · 변경 0.

## 편차 (나노 판단 · 근거)
- ① 판정 키 경로 = ref 의 «명단 꼴 폴더»(`ft_team_cands_ref` 첫 후보) — 체크아웃 폴더 경로로 ref 이력을 재면 공용 루트(옛 꼴 `design/v65` 실재 · origin/main 은 `design/teams/v65`)에서 이동 커밋에 sha 가 고정돼 «원장 갱신됨» 감지를 잃는다(= 판정 완화). ref 에 그 원장이 없으면 `ERROR … 골 원장이 <ref> 에 없다` exit 4(추측 0).
- ② 상태 자리 못 풂 = ERROR exit 4(옛: `$ROOT/.fable-team/` 를 만들어 씀). 실 공용 루트는 `.fable-team/` 가 늘 있다 · 시험 픽스처 R 에 `.fable-team/` 를 둔 이유.

## 시험
- `bash harness/tests/test_goal_check_ref.sh` → fail=0 rc=0 (34 PASS = r479 기존 22 + r485 ⓪ 1 · 픽스처 1 · ⓐ 2 · ⓑ 1 · ⓒ 1 · ⓓ 2 · ⓔ 4). 픽스처 = mktemp 리포 3(P=origin 판 · Q=공용 루트 clone · W·X=Q 워크트리) · 원장 sha 셋 다름 실측 · 외부 호출 0 · GIT_* env 0.
- 기존: `test_goal_table_gate.sh` rc0 · `test_kit_bin_sync.sh` rc0 · `bash -n` 2 · 짝 cmp 0.
- ★팩 안에서 RED(이 가지 무관 · ft-goal-check 참조 0)★: `test_goal_hook_merge.sh` rc2 · `test_goal_hook_adoption_archive.sh` rc7 — 둘 다 `HOOK=$HERE/../../scripts/git-hooks/v65-goal-commit-msg.sh`(BYZ 리포 경로)를 팩 트리에서 찾아 «No such file». 시험 위치/경로 고침 단위 필요(master 판단).
