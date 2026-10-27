# r959 증거 — 인덱스 이동 실패 사유 + 정본 게이트 착지 리포

카드: `design/harness/indices/진행/r959-index-move-mv-fail-reason-and-landed-repo.md` (harness-ops · arch#147 · master#116 #170071·#170104)
브랜치: `nano/r959-index-move-mv-fail-reason-and-lande` · base `331eb013fc25088eee76b3aea0ea86ae3a6ba51b` (r948 착지판 · 그 위로 rebase)

## 고친 곳 (4파일 + 짝 사본)

| 파일 | 줄 | 무엇 |
|---|---|---|
| `bin/ft-index-move.sh` | 이동 실행 | git·mv 의 stderr **첫 줄을 REJECT 줄 «안»에** 붙인다 (`REJECT 이동 실패: A → B — fatal: destination exists, …`). git mv 는 `git -C "$IDX_ROOT"` 로 실행(카드 리포 기준 · 되돌리기 포함) |
| `bin/ft-index-move.sh` | 표식 줄 | `FT_LANDED_MARKER` = **«닫힘 — <카드> — main…» 정확한 모양만** — 절 헤더 `## §32 <카드> — 닫힘 (CLOSE)` 를 표식으로 오인하지 않는다(카드 이름에 «main» 이 들면 카드 리포로 잘못 풀린다) |
| `bin/ft-index-move-canon.sh` | 표식 줄 | 같은 파싱 고침 |
| `bin/ft-index-move-canon.sh` | 착지 리포 | 표식이 «main»(카드 리포)인데 sha 가 **팩에만** 있으면 `WARN 표식 오기(팩 착지)` 1줄 + 팩 리포로 계속 판정(팩 origin/main 조상이면 통과 · 두 리포 어디에도 없으면 지금처럼 REJECT) |
| `bin/ft-team-lib.sh` | `ft_landed_repo` **기본 동작** | **DA⑥ r2 반송(재설계)**: «표식 오기(팩 착지)» 보정을 `ft_landed_repo` **안으로** 넣었다 — 표식 «main» 인데 sha 가 카드 리포에 없고 팩에 있으면 WARN 1줄 + **이미 받은 cs·ps 로** 판정만 바꾼다(재조회 0 · 상한 보존). 표식 main(팩) 어긋남은 보정하지 않는다(숨김 0). 별칭 `ft_landed_repo_marked` 는 없앴다 — 호출 넷(정본·설치·DA 보류 가드·close-landed)이 자동으로 같은 판정을 받는다 |
| `kit/fable-team/bin/…` | — | 네 파일 짝 사본 cmp0 |
| `bin/ft-index-move-install.sh` | 설치 게이트 | **④(r426 rc3)**: `--range` 갈래(팩 착지 sha)에도 `--project <카드 리포 공용 루트>` 를 넘긴다 — plist-env 렌더도 프로젝트 루트가 필요하다. CROOT 은 한 번만(7초 상한) 풀고 `--all` 갈래·install-pending 자리까지 같은 값을 쓴다(중복 git 호출 0) |

## 파일

| 파일 | 무엇 |
|---|---|
| `after.txt` · `after-bin-bash32.txt` | 새 시험 `tests/test_index_move_mv_fail_reason.sh` **ALL PASS 17행**(bash · /bin/bash 3.2) |
| `before-r959.txt` | 같은 시험을 **origin/main 판**(= r948 착지판) bin 으로 = FAIL 13행 — 이 시험이 고침을 실제로 잡는다 |
| `mutate1-reason-off.txt` | 변이: 사유 붙이기 끔 → ⓐ 2행 FAIL |
| `mutate2-marker-old-parse.txt` | 변이: 표식 파싱 옛 판(절 헤더 오인) → ⓑ·ⓒ 3행 FAIL |
| `mutate3-landed-repo-off.txt` | 변이: 정본 게이트가 팩 리포를 안 봄(`PACK=""`) → ⓑ·ⓒ 4행 FAIL |
| `mutate4-range-project-off.txt` | 변이: `--range` 갈래에서 `--project` 뺌 → **ⓕ FAIL** (`ERROR plist-env … LIVE_BIN 없음`) |
| `mutate5-install-old-marker.txt` | 변이: 설치 게이트만 팩 리포를 안 봄(`PACK=''`) → **ⓒ2·ⓒ3·ⓕ FAIL** |
| `mutate6-correction-out-of-lib.txt` | 변이: 보정을 기본 함수에서 빼고 옛 REJECT 로 → **ⓒ·ⓒ2·ⓒ3·ⓒ4·ⓒ5 FAIL** (DA r2 반례 그 자리) |
| `probe-r426-range-project.txt` | **④ 실사건**(읽기 전용): 같은 검사기로 `--range` 만 주면 `ERROR plist-env … LIVE_BIN 없음(팩/.fable-team/LIVE_BIN)`, `--project <카드 리포>` 를 더하면 plist-env ERROR 0 |
| `real-7-before.txt` / `real-7-after.txt` | **실사건** — harness-ops 진행/ 카드 7장에 정본 게이트 직접(쓰기 0): 옛 판 = r462·r560·r756·r888·r911 **REJECT «랜딩 안 됨»/«표식 오기»**, 새 판 = **7/7 OK** |
| `run-real-7.sh` | 위 실사건 재현 스크립트(읽기 전용) |

## 기존 시험 (회귀 0)

**DA⑥ r2 r3 고침 (재설계)** — r1 은 설치 게이트, r2 는 DA 보류 가드가 보정 없는 함수를 불렀다 = «부르는 쪽마다 보정을 붙이는» 구조가 두 번 샌 것. 보정을 `ft_landed_repo` 기본 동작으로 옮겨 호출 넷(정본·설치·보류 가드·close-landed)이 같은 판정을 받는다. 시험 ⓒ3(보류 이력 카드) · ⓒ4(close-landed) · ⓒ5(호출 자리 안전망 — 우회 호출 0) 추가, 변이 mutate6(보정 제거)이 ⓒ3·ⓒ4 를 떨어뜨린다. 계약 ③ WARN 관측 = 이동 명령 전체 출력에 1회 이상(보류 가드 경로는 WARN 을 따로 요구하지 않는다 — ft_git_capped 가 stderr 를 버린다).

**DA⑥ r1 r2 고침** — 설치 게이트가 «표식 오기» 판정을 옛 판정(`ft_landed_repo`)으로 다시 해 정본 게이트의 WARN+통과 보정을 못 받았다(설치: 있음 카드가 정본은 통과·설치에서 REJECT). 보정을 `ft-team-lib.sh` 의 `ft_landed_repo_marked` 한 곳으로 옮겨 두 게이트가 같은 판정을 쓴다. 시험 ⓒ2 = 설치: 있음 + 표식 main + 팩 착지 → 두 게이트 통과(WARN 1줄) · 변이 mutate5(설치 게이트만 옛 판정) 가 ⓒ2 를 떨어뜨린다.

**예외 2 (기존 시험 기대를 고침)** — `tests/test_index_move_landed_repo.sh` ⓐ «표식 main 인데 카드 리포에 없음 → REJECT(표식 오기 숨김 0)»: r959 ③ 계약이 «WARN 1줄 + 팩 조상이면 통과» 로 바뀌었으므로 그 행의 기대를 WARN + 팩 리포로 고쳤다(파일에 r959 표기 주석). 표식 main(팩) 어긋남 행은 그대로 REJECT — 숨김 0 유지.

**예외 1 (기존 시험 기대를 고침)** — `tests/test_r948_live_all_project.sh` ⓑ: r948 당시 기대가 «`--range A..B` 그대로(--project 추가 0)» 였는데, ④ 가 `--range` 갈래에도 `--project` 를 붙이는 것이 의도된 변경이라 기대를 «`--range A..B --project <카드 리포 공용 루트>`» 로 고쳤다(그 파일 머리 주석 + ⓑ 라벨에 r959 ④ 표기). 옛 판 bin 으로는 ⓑ 가 FAIL, 고친 판은 PASS — 시험이 여전히 가른다. 나머지 기존 시험은 기대 변경 0.

**base 대조 2줄 (arch ⓑ4)**
- `LC_ALL=C.UTF-8 bash tests/test_index_move_landed_repo.sh` = **FAIL 5행** — 이 워크트리와 `origin/main` 사본이 **같은 5행**(ⓖ·ⓗ·ⓙ×2·ⓚ)이고 사유도 같다(로케일 경고 + 타이밍 초). 즉 r959 로 새로 나빠진 행 0. 기본 로케일에서는 ALL PASS.
- `bash tests/test_live_install_check_plist_env.sh` = **ALL PASS(0F)**, `LC_ALL=C.UTF-8` 에서도 0F — DA r2 격리에서 본 1F 는 이 워크트리에서 재현되지 않는다(그 시험 파일은 r959 가 건드리지 않았다 · `git diff origin/main -- tests/test_live_install_check_plist_env.sh` = 0행).

```
test_r948_live_all_project.sh         fail=0        (ⓑ 기대 1줄만 r959 ④ 로 고침 — 위 예외)
test_index_move_landed_repo.sh        ALL PASS      (ⓐ 1행 기대를 «WARN + 팩 리포» 로 r959 ③ 계약에 맞춤 — 위 예외 2)
test_index_move_canon_landed.sh       fail=0
test_index_move_canon_route.sh        fail=0
test_index_move_canonize.sh           fail=0        (키트 cmp 2행 포함 — 사본 갱신 뒤)
test_index_move_install_harness_repo.sh ALL PASS
test_index_move_rule_line.sh          fail=0
test_index_move_slack.sh              REAL-STATE-GUARD PASS
test_da_hold_gate_landed.sh           fail=0
test_da_hold_gate.sh                  fail=7  ← 기존 RED (spawn dry-run 5 · 홈 문서 드리프트 2) — 고친 두 파일 무관(bash -n·키트 cmp 통과). origin/main 판에서도 같은 5행이 같은 사유로 FAIL
```

## 남은 축

없음 — 카드 범위 1·2·3(①②③④) 전부 이 카드에서 끝났다. r948 착지판(`331eb013`) 위로 rebase 해서 마무리했다.

## ④(r426 rc3) 재현 · 고침

```
$ FT_BIN=<live> ft-live-install-check.sh --range f7b77800^..f7b77800
ERROR plist-env com.hermes.byz-mbox-slack-mirror: LIVE_BIN 없음(<팩>/.fable-team/LIVE_BIN) — …--project <프로젝트 루트> 를 준다   (rc3)
$ … --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
  → plist-env ERROR 0
```

고침 = `ft-index-move-install.sh` 의 `--range` 갈래 `CARG` 에 `--project "$CROOT"`. 시험 ⓕ 는 **실 검사기**(ft-live-install-check)로 돈다 — 키트 템플릿을 바꾼 팩 범위 + 렌더된 설치본을 만들어 `RC=0 · OK 설치 확인`, `--project` 를 빼면 `ERROR plist-env … LIVE_BIN 없음` 으로 떨어진다.
