# r961 증거 — 설치 검사 키트 경로를 HARNESS_ROOT «자기» 체크아웃 최상위 기준으로

카드: BYZ `design/harness/indices/진행/r961-install-check-kit-path-from-harness-toplevel.md` · 좌석 byz-harness-nano-r961-install-check-kit-path-from-harness#0 · base 팩 origin/main fd3125e1

## 사건 (실측)

라이브 HARNESS_ROOT = `~/.claude/fable-team/live/1.1.252/HARNESS_ROOT` = `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/land-r938/feature-pack/fable-team/harness` (팩 리포 안 착지 워크트리). `ft-merge-land` 마지막 INSTALL 단계(`--range M..Q --ref Q --repo <팩 공용 루트>`)가 매번 ERROR → 설치를 손으로 (PR 332·333 2회).

원인 = `resolve_kit` 이 키트 상대 경로를 `relpath(<HARNESS_ROOT>/kit, realpath(--repo))` 로 만든다 → 공용 루트 기준이라 `.worktrees/land-r938/` 접두가 붙고, 그 이름은 커밋 트리에 없다 → `git show <ref>:<지도>` 실패.

## 고친 곳 (짝 사본 bin ↔ kit/fable-team/bin cmp0)

| # | 파일 | 무엇 |
|---|---|---|
| 1 | ft_live_install_check.py `kit_rel`·`git_toplevel` (신규) · `resolve_kit` | 키트 상대 경로 = `relpath(<HARNESS_ROOT>/kit, <HARNESS_ROOT 의 show-toplevel>)`. 하네스 루트 최상위가 `--repo` 밖(다른 리포)이면 종전대로 «밖» → `outside_repo` (fail-closed 유지) · 하네스 루트가 git 리포가 아니면 옛 기준(`repo`)으로 폴백(7초 상한 · 실패를 삼키지 않고 «밖» 판정으로 흘림) |
| 2 | ft_live_install_check.py 짝 사본 | `cmp bin/… kit/fable-team/bin/…` rc0 |
| 3 | tests/test_install_check_hr_worktree.sh (신규) | ⓐ~ⓓ · 임시 팩 리포 + 같은 리포 추가 워크트리 `.worktrees/land-x` · mktemp 만 |

## 판정 (실측 2026-10-26)

ⓐ 빨강 먼저(고침 전 코드 · 라이브 1.1.254 그대로) — 워크트리 HARNESS_ROOT + 공용 루트 `--repo`:

```
ERROR git show <sha>:.worktrees/land-x/feature-pack/fable-team/harness/kit/LIVE-MAP.tsv 실패: fatal: path '…' exists on disk, but not in '<sha>'
```

고친 판 = `PASS ⓐ 워크트리 HARNESS_ROOT → OK n=1 rc0` · `PASS ⓐ 대조 경로에 .worktrees 접두 0`

ⓑ 공용 체크아웃 HARNESS_ROOT → 결과 줄이 ⓐ 와 바이트 같다 (`OK n=1 skip=0` 둘 다 · 회귀 0)
ⓒ HARNESS_ROOT 가 다른 리포(팩 밖) → `ERROR 하네스 루트(…)가 --repo(…) 밖 — --kit 를 준다` rc3 (조용한 통과 0 유지)
ⓓ 빈 범위 `C1..C1` → `OK n=0 skip=0` rc0
ⓔ git 리포 밖 HARNESS_ROOT → 폴백 기준으로 `ERROR … 밖` rc3 (조용한 통과 0)
ⓕ 변이 — `kit_rel` 의 기준을 `repo` 로 되돌리면 ⓐ·ⓑ·ⓓ FAIL 4 (원복 뒤 재실행 ALL PASS)

## 실사건 재현 (실 라이브 배치 · 읽기 전용 · FT_BIN = BYZ `.fable-team/LIVE_BIN`)

| 명령 | 옛 판(1.1.254) | 이 가지 |
|---|---|---|
| `--range fd3125e1^..fd3125e1 --ref fd3125e1 --repo <팩 공용 루트>` (ft-merge-land 꼴) | `ERROR git show fd3125e1:.worktrees/land-r959/…/LIVE-MAP.tsv` | `OK n=0 skip=0` |
| `--range eec7dee4^..eec7dee4 --ref eec7dee4 --repo <팩 공용 루트>` | (같은 ERROR) | `OK n=1 skip=0` |
| `--all --repo <팩 공용 루트>` | 같은 ERROR | `ERROR plist-env … LIVE_BIN 없음(팩/.fable-team/LIVE_BIN)` — 키트 경로 단계는 통과 · 팩 리포를 «프로젝트» 로 본 결과(호출부가 `--project` 를 줘야 하는 자리 · 카드 범위 밖) |

## 시험

- `/bin/bash`(3.2.57) · bash 5.3.9 둘 다 `test_install_check_hr_worktree.sh` == ALL PASS == (7 PASS)
- 회귀 rc0: test_install_check_repo_outside(9) · test_live_install_check(52) · test_live_install_check_tip(14) · test_live_install_check_shim(15) · test_live_install_check_bin_row_shim(7) · test_live_install_check_plist_env(39) · test_index_move_install_harness_repo(7) · test_index_move_landed_repo(36) · test_index_move_canon_landed(18)
- 기존 실패(이 단위 밖 · base fd3125e1 에서 같은 수): `test_harness_root.sh` FAIL ⓔ «600/300 있음» · `test_merge_land_pack_repo.sh` FAIL ⓐ2·ⓐ3 «base/ft-merge-deny.sh 없음»

## 범위 밖 (카드 3)

- HARNESS_ROOT 를 어디에 둘지(설치기 정책) · ft-merge-land 의 INSTALL 단계 순서 · 팩 리포를 프로젝트로 볼 때의 `--project` 기본값

## r2 (DA⑥ r1 HOLD 1 · 2026-10-26)

반송서 = BYZ `design/harness/evidence/r961-da6/REWORK-r961-r2.md` · 반례 = «같은 리포의 등록 워크트리인데 막힘»
(r1 은 «같은 리포» 를 `relpath` 디렉터리 포함 관계로 판정 — 공용 루트 «밖» 에 등록한 워크트리는 포함 관계가 끊긴다).

| # | 파일 | 무엇 |
|---|---|---|
| 1 | ft_live_install_check.py `kit_rel` · `git_common_dir`·`git_rev`(신규) | «같은 리포» 판정 = 두 쪽 `git rev-parse --git-common-dir` 의 실제 경로가 같음. 같으면 키트 상대 경로 = `relpath(<HR>/kit, <HR 의 show-toplevel>)` · 다르면 «..» 를 돌려 `outside_repo`(rc3). git 호출 7초 상한 · 실패는 ERROR(조용한 통과 0) |
| 2 | 짝 사본 | `cmp bin/… kit/fable-team/bin/…` rc0 |
| 3 | tests/test_install_check_hr_worktree.sh | ⓕ 공용 루트 밖 등록 워크트리 → OK n=1 rc0 (픽스처가 두 체크아웃 `git-common-dir` 같음을 함께 확인) · ⓖ 같은 내용 다른 리포 클론 → «밖» rc3 |

### 판정 (실측 2026-10-26)

- ⓕ 빨강 먼저(r1 코드 = 8a95694a 그대로) — 공용 루트 밖 등록 워크트리 HARNESS_ROOT + 공용 루트 `--repo`:
  `ERROR 하네스 루트(…/outside-wt/…/harness)가 --repo(…/fx) 밖 — --kit 를 준다 · 범위에 하네스 파일 1` rc3 (= DA⑥ 반례 그대로)
- 고친 판 = `PASS ⓕ 공용 루트 밖 등록 워크트리 HARNESS_ROOT → OK n=1 rc0` · `PASS ⓕ 대조 경로에 outside-wt 접두 0`
- ⓖ 같은 내용 다른 리포 클론 → `ERROR … 밖` rc3 (공용 git 폴더가 다르므로 막힘 · 조용한 통과 0)
- ⓐ~ⓔ 그대로 PASS (회귀 0) · 변이 ⓐ «포함 관계 판정 되돌림» → ⓕ FAIL 2 · 변이 ⓑ «common-dir 비교 생략» → ⓒ·ⓖ FAIL 2 (원복 뒤 ALL PASS)

### 실사건 재현 (실 팩 리포 · 읽기 전용 · FT_BIN = BYZ `.fable-team/LIVE_BIN`)

HARNESS_ROOT = `/private/tmp/r957-pack/feature-pack/fable-team/harness` — 팩 리포에 등록된 워크트리인데 공용 루트 밖
(`git rev-parse --git-common-dir` = `/Users/yoonhwan/Project/ai-feature-pack/.git` 양쪽 같음 · 실측).

| 명령 | 옛 판(1.1.255) | 이 가지 |
|---|---|---|
| `--range eec7dee4^..eec7dee4 --ref eec7dee4 --repo <팩 공용 루트>` | `ERROR 하네스 루트(…/r957-pack/…)가 --repo(…) 밖` rc3 | `PENDING n=1` rc1 (키트 경로 단계 통과 · 라이브 미적용 = MISSING 1 그대로) |
| `--range fd3125e1^..fd3125e1 --ref fd3125e1 --repo <팩 공용 루트>` (라이브 HARNESS_ROOT 1.1.255 = `.worktrees/land-r765/…`) | — | `OK n=0 skip=0` rc0 |

### 시험

- `/bin/bash`(3.2.57) · bash 5.3.9 둘 다 `test_install_check_hr_worktree.sh` == ALL PASS == (12 PASS)
- 회귀 rc0: test_install_check_repo_outside(9) · test_live_install_check(52) · test_live_install_check_tip(14) · test_live_install_check_shim(15) · test_live_install_check_bin_row_shim(7) · test_live_install_check_plist_env(39) · test_r948_live_all_project(15)
- ruff check rc0

## 알려진 한계 (범위 밖 선언 · 오빠 결정 10-27 · R2)

- 폴더 이름 «끝에 공백» 이 있는 경로(예: `shared-main `)를 HARNESS_ROOT 로 쓰면 대조가 rc3(«밖»)로 막힌다. 이 판은 끝 공백을 떼지 않고 realpath 값만 비교하기 때문이다. 실사용 0건이라 범위 밖으로 선언한다. 바꾸려면 새 카드.

## r5 (DA⑥ r5 HOLD [수용] 1 · 2026-10-27)

반송서 = BYZ `design/harness/evidence/r961-da6/REWORK-r961-r5.md` · 반례 = «끝 공백 git 폴더 두 리포 → 조용한 통과»
(`git_rev()` 의 `out = r.stdout.strip()` 이 경로 끝 공백을 지워, 이름만 다른 두 공용 git 폴더가 «같은 리포» 로 보였다 — ft_live_install_check.py:141)

| # | 파일 | 무엇 |
|---|---|---|
| 1 | ft_live_install_check.py `git_rev` | 돌려주는 값 = git 출력 끝 «개행 1개만» 뗀다(`r.stdout[:-1] if endswith("\n")`). 경로 값은 다듬지 않는다 — r2 가 도입한 «같은 리포 = common-dir 값 비교» 계약 그대로 |
| 2 | 짝 사본 | `cmp bin/… kit/fable-team/bin/…` rc0 |
| 3 | tests/test_install_check_hr_worktree.sh | ⓗ 끝 공백 git 폴더(`metadata` vs `metadata `) 두 리포 → «밖» ERROR rc3 · ⓘ 같은 리포 두 워크트리(공백 없는 이름) → OK n=1 rc0 · ⓙ 변이 `.strip()` 되살림 → ⓗ FAIL |

### 판정 (실측 2026-10-27)

- ⓗ 빨강(= 이 고침 전 판정): 변이 판(`.strip()` 되살림) = `OK n=1` rc0 — DA⑥ 원문과 같은 꼴의 «조용한 통과» 재현
- 고친 판 = `ERROR 하네스 루트(…/sepb/…)가 --repo(…) 밖 — --kit 를 준다 · 범위에 하네스 파일 1` rc3
- ⓘ = `OK n=1 skip=0` rc0 (ⓐ·ⓕ 회귀 0) · ⓙ = 변이 판 rc=0 → ⓗ FAIL 확인(원복 뒤 ALL PASS)
- ⓐ~ⓖ 그대로 PASS (12 → 17 PASS)

### 시험

- `/bin/bash`(3.2.57) · bash 5.3.9 둘 다 `test_install_check_hr_worktree.sh` == ALL PASS == (17 PASS · ⓐ~ⓙ)
- 회귀 rc0: test_install_check_repo_outside(9) · test_live_install_check(52) · test_live_install_check_tip(14) · test_live_install_check_shim(15) · test_live_install_check_bin_row_shim(7) · test_live_install_check_plist_env(39) · test_r948_live_all_project(15)
- `cmp bin/… kit/fable-team/bin/…` rc0 · ruff check rc0
- 범위 밖(동결): «폴더 자체 이름 끝 공백»(R2)이 이 고침으로 어떻게 되는지는 시험하지 않는다(계약 위반 아님) · R3·R4 그대로

## r6 (DA⑥ r6 HOLD [수용] 1 · 오빠 결정 1번 · DA 호출 0 · 2026-10-27)

반송서 = BYZ `design/harness/evidence/r961-da6/REWORK-r961-r6.md` · 반례 = «CR/LF git 폴더 두 리포 → 조용한 통과»
(`subprocess.run(…, text=True)` 의 universal newlines 가 CR 을 LF 로 바꿔, 이름만 다른 두 경로가 같은 값이 됐다 — ft_live_install_check.py:135)

| # | 파일 | 무엇 |
|---|---|---|
| 1 | ft_live_install_check.py `git_rev` | 출력을 bytes 로 받는다(`text=True` 제거) · 끝 `b"\n"` 1개만 떼고 `os.fsdecode()`(surrogateescape) · stderr 도 같은 꼴로 디코드. CR·탭·비ASCII 어떤 바이트도 바꾸지 않는다. 호출자(`git_toplevel`·`git_common_dir`) 변경 0 |
| 2 | 짝 사본 | `cmp bin/… kit/fable-team/bin/…` rc0 |
| 3 | tests/test_install_check_hr_worktree.sh | ⓚ git 폴더 이름 특수문자 5꼴(끝 공백 · CR · LF · 탭 · 한글) 각각 «서로 다른 이름 두 리포» → «밖» ERROR rc3 · «같은 리포 두 워크트리» → OK n=1 rc0 · ⓛ 변이 `text=True` 되살림 → ⓚ[CR] FAIL |

### 판정 (실측 2026-10-27)

- ⓛ 변이 판(=`text=True` 되살림) = ⓚ[CR] `OK n=1 skip=0` rc0 — DA⑥ r6 원문과 같은 꼴의 «조용한 통과» 재현
- 고친 판 = ⓚ 5꼴 전부 다른 이름 두 리포 → `ERROR … 밖` rc3 · 같은 리포 두 워크트리 → `OK n=1 skip=0` rc0
- 짝 사본을 안 고친 중간 상태에서 ⓚ[CR]·[LF]·[한글] 이 rc0 로 FAIL 했다(시험이 kit 사본을 실행하므로) — 고친 뒤 29 PASS. 변이 ⓛ 이 그래서 «빈 말 아님» 을 함께 보인다
- 기존 ⓐ~ⓙ 그대로 PASS (17 → 29 PASS)

### 시험

- `/bin/bash`(3.2.57) · bash 5.3.9 둘 다 `test_install_check_hr_worktree.sh` == ALL PASS == (29 PASS · ⓐ~ⓛ)
- 회귀 rc0: test_install_check_repo_outside(9) · test_live_install_check(52) · test_live_install_check_tip(14) · test_live_install_check_shim(15) · test_live_install_check_bin_row_shim(7) · test_live_install_check_plist_env(39) · test_r948_live_all_project(15)
- `cmp bin/… kit/fable-team/bin/…` rc0 · ruff check rc0
- 범위 밖(동결): R2(체크아웃 폴더 이름 끝 공백)·R3·R4 그대로 · samefile 교체 0 · 계약 문장·새 기준 0
