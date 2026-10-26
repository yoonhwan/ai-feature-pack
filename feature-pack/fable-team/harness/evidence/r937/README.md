# r937 증거 — ft-index-move 착지 sha 리포 판정 1곳 · 설치·정본·close-landed 세 게이트가 같은 리포를 본다

카드 = `design/harness/indices/진행/r937-index-move-landed-sha-repo-resolve-both-gates.md`
브랜치 = `nano/r937-index-move-landed-sha-repo-resolve-` · base = `63ae5209`(origin/main) · push 0(master).

## 고친 자리 3 + 공용 함수 1 + 짝 사본

| 파일 | 무엇 |
|---|---|
| `feature-pack/fable-team/harness/bin/ft-team-lib.sh` (`ft_landed_repo` · `_ft_landed_git`) | **ⓐ 리포 판정 1곳.** sha 를 카드 리포·팩 리포에서 `rev-parse`(각 7초 상한) → 한 곳에만 있으면 그 리포 · 둘 다 = 판정문 표식 줄(`main(팩)` = 팩 · `main` = 카드 리포) · 둘 다 없음 = `REJECT 착지 sha 를 어느 리포에서도 못 찾음` · 표식과 실제가 어긋나면 `REJECT … 표식 오기(숨김 0)` · 앞자리(7~39)는 그 리포에서 유일할 때만, 두 리포가 **다른** 커밋을 가리키면 표식 필수 · 팩 리포를 못 풀면 카드 리포만 본다 |
| `…/bin/ft-index-move-install.sh` | 설치 게이트가 `ft_landed_repo` 값을 씀 — 팩 착지 = 지금처럼 `--range` 대조 · **카드 리포 착지 = `--all`(«설치 파일 = 라이브» 전수)** — 그 sha 를 팩에서 찾지 않는다(ⓑ) · 하네스 루트를 못 풀면 REJECT(후퇴 0 · ⓓ) |
| `…/bin/ft-index-move-canon.sh` | 정본 게이트의 조상·diff 검사가 판정 리포(카드/팩)와 그 리포의 `FT_LAND_REF`(기본 `origin/main`)를 씀 · 표식 줄은 §절 본문에서 «닫힘 … main …» 줄로 뽑는다(헤더 줄 `## §N 닫힘: <카드>` 는 표식이 아니다 — main 글자 없음) |
| `…/bin/ft-index-close-landed.sh` | 판정문 행 꼴에 `main(팩) `<40hex>`` 를 더 읽고(행마다 `pack|card`), 조상 검사도 같은 리포·같은 ref 로 · 못 찾은 sha = `LANDED-INVALID not-found` · dry-run 표 6칸 그대로 |
| `…/bin/ft-index-move.sh` | 완성 이동 «전»에 그 카드의 «닫힘 — <카드> — main…» 줄을 `FT_LANDED_MARKER` 로 export — 정본·설치 게이트가 같은 표식을 쓴다 |
| `…/bin/ft_da_hold_gate.py` (`landed_repo` · `landed_check`) | **2b(범위 넓힘 · arch 145).** 착지 검사도 `ft_landed_repo`(bash 단일 출처 호출)로 리포를 정하고 그 리포의 `FT_LAND_REF` 로 조상 검사 · 판정문 행 «닫힘 — <카드> — main(팩) `<40hex>`» 도 읽음 · 표식과 실제가 어긋나면 `LANDED-INVALID marker-mismatch` · 어느 리포에도 없으면 `LANDED-INVALID not-found` |
| `feature-pack/fable-team/harness/bin/ft-team-lib.sh` (`ft_git_capped` · `_ft_git_retry`) | **r2 T1·T2.** git 조회 1회를 7초 상한으로 감싼다 — `timeout`/`gtimeout` 이 있으면 그것, 없거나 `FT_GIT_CAP_BUILTIN=1` 이면 bash 내장(백그라운드 + 7초 뒤 kill · bash 3.2). 시간 초과만 재시도 1(총 ≤ 14초) · rc 137→124 정규화 · rc 규약 = 0 있음 / 1 «그 리포에 없음» / 그 밖 = «조회 실패» |
| `…/kit/fable-team/bin/{위 6개}` | 짝 사본 cmp0 |
| `…/tests/test_index_move_landed_repo.sh` | 새 시험(ⓐⓑⓒⓓⓔ). `SRC=<bin>` 으로 옛 판·변이를 같은 시험으로 돌린다 |
| `…/tests/test_index_move_install_harness_repo.sh` | 시험 사본 목록에 `ft-harness-root.sh` 추가(설치 게이트가 하네스 루트를 직접 푼다) |

## 시험

```
cd feature-pack/fable-team/harness && bash tests/test_index_move_landed_repo.sh
```

| 파일 | 무엇 | rc |
|---|---|---|
| `before.txt` | 고치기 전 판(`origin/main` 의 bin 10개)으로 새 시험 → 22 빨강 · 초록 3(ⓓ 설치: 없음 = 지금 통과하던 길 · ⓕ 오염 0 · «표식 main 인데 옛 판이 카드 리포만 봐서 우연히 랜딩 안 됨» 1건) = 이 카드가 메우는 구멍 그대로 | 1 |
| `after.txt` | 고친 판 → 24/24 PASS · `ALL PASS`(조상 검사 상한·조회 실패 구분·bash 3.2 칸 포함) | 0 |
| `mutate1-landed-repo-off.txt` | 변이 1 = «리포 판정 끔(카드 리포 고정)» → **ⓑ 팩 착지·정본 게이트 빨강 + ⓔ 보류 가드 3건 빨강**(+ⓐ 표식 4건) — 판정 함수 하나를 끄면 네 게이트가 같이 흔들린다 | 1 |
| `mutate2-marker-off.txt` | 변이 2 = «표식 대조 끔» → **ⓒ 빨강 + ⓔ 표식 오기 빨강** + ⓑ 표식이 리포를 가르는 시험 빨강 | 1 |
| `mutate3-git-cap-off.txt` | 변이 3 = «상한 함수 우회(7초 없는 git)» → **ⓕ·ⓖ·ⓗ 빨강** | 1 |
| `mutate4-lookup-fail-as-absent.txt` | 변이 4 = «조회 실패를 객체 없음으로 복귀» → **ⓗ 빨강**(다른 리포로 넘어가 통과) | 1 |

회귀(같은 커밋에서 다시 돌린 기존 시험 12개): `test_index_move_canon_landed` · `test_index_move_install_harness_repo` · `test_da_hold_gate_landed` · `test_index_move_canon_route` · `test_index_move_canonize` · `test_index_move_rule_line` · `test_index_move_slack` · `test_live_install_check` · `test_live_install_check_tip` · `test_install_check_repo_outside` · `test_nano_close_pack_wt` — 전부 rc0.
(`test_team_literal_paths2.sh` 는 이 카드 전에도 같은 자리(`ft_ledger_fill.py:336` 줄 길이 lint)에서 rc1 = 선행 결함 · 이 커밋과 무관.)

## DA⑥ r1 반송(r2) — 7초 상한 · 조회 실패 구분 · bash 3.2

| 반례(DA 원문) | 고침 | 시험 |
|---|---|---|
| ① 조상 검사 상한 없음(merge-base 8초 → 게이트가 8초 넘게 통과) | canon·close-landed·`ft_da_hold_gate.py` 의 merge-base 도 `ft_git_capped`(7초 · 재시도 1)로 · 초과 = «조회 실패» REJECT | ⓕ 3칸(정본·보류 가드·close-landed · 각 ≤ 16초) |
| ② `timeout`/`gtimeout` 이 없으면 무제한 | bash 내장 경로(백그라운드 + «초» 뒤 kill -9 · 감시자 stdio 닫음 · bash 3.2) · `FT_GIT_CAP_BUILTIN=1` 로 그 경로를 고정해 시험 | ⓖ |
| ③ 한 후보 시간 초과를 «객체 없음» 으로 읽어 다른 리포로 넘어감 | `ft_landed_repo`: rc 0 있음 / 1 없음 / 그 밖(124·128) = «조회 실패» → **리포 판정 자체를 안 한다**(REJECT «<리포> 조회 실패 … 통과 0») | ⓗ · 변이 4 |
| ④ `/bin/bash`(3.2) 에서 `ft-index-close-landed.sh` 문법 오류(선행 결함 · `$( )` 안 heredoc 의 백틱) | 판정문 행 정규식의 백틱을 `\x60` 로 씀 · 고친 파일 6개 `/bin/bash -n` rc0 · 이 시험도 `/bin/bash` 로 1회 돌려 초록 확인 | ⓘ |

정본 게이트의 조상·ref·정본 blob 조회는 `gq`(허용 rc 초과 = REJECT)로 묶었고, `rej` 가 `$( )` 안에서 돌면 거절이 출력만 되고 통과하던 함정을 피하려고 `gq` 는 결과를 `GQ_OUT`/`GQ_RC` 로 넘긴다(ⓕ 첫 칸이 그 함정을 잡는다).

## 범위 넓힘(2b) 뒤

`ft_da_hold_gate.py` 의 착지 검사도 같은 판정을 쓴다(arch 145 · master#114 #169175) — 팩 착지 카드는 이제 `ft-index-move.sh` 보류 가드에서 `LANDED-CLOSE` 로 통과하고,
표식이 실제와 어긋나면 `LANDED-INVALID marker-mismatch` 로 막힌다(시험 ⓔ 3건). 이 카드로 설치·정본·close-landed·보류 가드 **네 게이트가 한 값을 본다**.
