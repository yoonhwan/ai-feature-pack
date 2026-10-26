# r958 증거 — ⑤ cherry 게이트 묶음 호출 + 7초 상한 + 진행 파일

카드: `design/harness/indices/진행/r958-nano-close-cherry-gate-7s-split.md` · Issue #3654 · planner #170097 · arch 147
브랜치: `nano/r958-nano-close-cherry-gate-7s-split` (base = 팩 origin/main `a1fccaf7`) · push 없음(master 몫)

## 무엇이 문제였나
`ft-nano-close.sh --suspended` 의 ⑤ cherry 게이트가 «71s/70s 시간 초과» 로 REJECT 2회(chatbot 나노 c-fix-k12-tool-results-slot-budget#0, main 병합 뒤 재시도도 같음). 원인 = 게이트가 **커밋 하나에 git 3회**(`log -1` · `diff-tree` · `diff-tree -z`), **경로 하나에 git 3회**(`ls-tree` ×2 · `log -- <경로>`) 부르는 구조라 외부 호출 수가 커밋·경로 수에 비례하고, 바깥 상한이 70초 한 덩어리였다(하드 룰 12 위반).

## 고친 것 — 파일 3 + 시험 2
| 파일 | 고친 자리 |
|---|---|
| `harness/bin/ft-nano-cherry-gate.sh` | 새 도구 `cg_git`·`cg_fail`·`cg_prog_get/put`·`cg_fetch`·`cg_cmd_commits`·`cg_cmd_hist`·`cg_py`(해석기) · 바뀐 본체 = «+» 커밋 분류 1블록(종전 커밋 루프) + 경로 분류·이력 대조 2블록(종전 경로 루프, `cg_maps` 포함) |
| `harness/bin/ft-nano-close.sh` | `nf_mult_batches()` 신설(121~127행) · ⑤ 호출부 배수 = 묶음 수(1139행, 종전 `nf_mult_commits`) |
| `harness/kit/fable-team/bin/…` | 위 두 파일 짝 사본 cmp0 |
| `tests/test_cherry_gate_batch_r958.sh` (신규) | ⓐ~ⓗ (ⓖ·ⓗ = r2 반송 고침 · rename 무변경 · cherry 상한) · **ⓘ~ⓚ = r3(꼴 경로 · 동사별 상한 · 안전망)** |
| `tests/test_cherry_gate_identical_head.sh` · `tests/test_nano_close_step_timing_r938.sh` | 줄 수 상한 200→340(게이트가 329줄) · ⓘ 대역을 «커밋당 1초» → «묶음당 1초»(r958 계약 = 작업량 ∝ 묶음 수) |

### 묶음 호출 규칙
| 축 | 값 |
|---|---|
| 커밋 묶음 | `git log --no-walk=unsorted --raw -m --root --format='C %H<TAB>%h %s' <sha…>` 1회 = 로그 줄 + 건드린 경로 + 모드/blob |
| 경로 분류 | `git ls-tree -r -t -z --full-tree <ref>` 를 tip·feat HEAD 각 1회 = 경로별 `ls-tree` 호출 0 |
| 이력 대조 | `git log <mbase>..<feat> --no-renames --format='C %h' --raw -- <경로 묶음>` 1회 = 경로별 `log` 호출 0 |
| 1회 상한 | `FT_CHERRY_LIM_S`(기본 7초) · `ft_git_capped.py` 가 프로세스 그룹째 정리 · 넘으면 그 묶음을 **반으로 쪼개 재시도 1** · 항목 1개까지 쪼개도 넘으면 `REJECT cherry 게이트 — <단계> 7초 초과(묶음 n · 마지막 <항목>)` |
| 진행 파일 | `FT_CHERRY_PROGRESS=<파일>` — 끝난 묶음의 출력을 남겨 다시 부르면 git 을 다시 묻지 않는다(같은 결과) |
| 묶음 크기 | `FT_CHERRY_BATCH`(기본 100) — 게이트와 닫기 쪽 상한 계산이 **같은 값**을 쓴다 |
| 바깥 상한 | `ft-nano-close.sh` ⑤ = `min(2.0 + 7×묶음 수, 70)` (묶음 수 = ceil(커밋/FT_CHERRY_BATCH)) |

## 실측 (이 맥 · 2026-10-26)
| 축 | 값 | 파일 |
|---|---|---|
| ⓐ 지금 판 · «+» 커밋 300 · 느린 git(호출당 0.08초) · 바깥 상한 70초 | **rc=124 · 70.0초 · 외부 호출 658회에서 잘림** → «⑤cherry 게이트 시간 초과 70s/70s» (실사건과 같은 꼴) | `red-70s.txt` |
| ⓐ 새 판 · 같은 리포·같은 느린 git | **rc=0 · 1.1초 · 외부 호출 6회** (WARN 300 통과) | `red-70s.txt` |
| 경로 2005개 · 커밋 4개(실 git) | rc=1(정상 REJECT) · **1.9초 · 외부 호출 30회** (종전 판 = 경로당 3회 ≈ 6000회) | 이 표 |
| ⓐ 호출 수 대조(시험) | 옛 판 903회 ≥ 3×300 · 새 판 6회 | `test-green.txt` |
| ⓑ 판정 대조 | small 리포(코드+문서+되돌림 5상황) **stdout 전문 동일** · big 리포(커밋 12·경로 300) 차단·WARN 목록 동일 · 호출 13회 | `test-green.txt` |
| ⓒ 상한 초과 | `FT_CHERRY_LIM_S=1` + 묶음 2초 대역 → `REJECT cherry 게이트 — 커밋 1초 초과(묶음 1 · 마지막 <sha>)` rc=1 | `test-green.txt` |
| ⓓ 진행 파일 | 재호출 결과 동일 · `--no-walk` 재호출 0 | `test-green.txt` |
| ⓔ 기존 시험 | identical_head · squash · r938 · kit_bin_sync ALL PASS · `/bin/bash` 3.2 통과 | `regress-existing.txt` |
| ⓕ 변이 | 묶음 대신 커밋마다 호출(FT_CHERRY_BATCH=1) → 303회로 ⓑ 단언 FAIL · 쪼개기 끔(`d -lt 0`) → «묶음 1» 이 아니라 ⓒ 단언 FAIL | `mutation.txt` |

## r2 반송 고침 (DA⑥ r1 HOLD 2 · 반송서 `design/harness/evidence/r958-da6/REWORK-r958-r2.md`)

| 반례 | 자리(고침 전 HEAD `b948b3a4`) | 고침 | 시험 칸 · 변이 |
|---|---|---|---|
| 1. rename 무변경 이동이 «통과» (`content_landed_then_superseded` rc0, base 판은 REJECT rc1) | `cg_cmd_commits` 가 rename 을 켜 둬 원시 줄이 `:…R100<TAB>옛경로<TAB>새경로` = **두 경로가 한 칸** → 없는 이름 하나가 `sup` 로 샘 | `--no-renames` 추가 = D 옛경로 + A 새경로 두 줄(base 판 `diff-tree --name-only` 와 같은 경로 목록 · `cg_cmd_hist` 와 같은 이유) | ⓖ (base 판 출력과 **전문 동일** · 차단 목록 같음) · 변이 = `--no-renames` 제거 → ⓖ FAIL(rc0 통과) |
| 2. `git cherry` 1회가 7초 상한 밖 → 9.22초 뒤 rc0 `OK(+ 0)` **조용한 통과** | `out="$(git -C "$REPO" cherry …)"` 가 상한 도우미를 안 거침 | `cg_git "$CG_LIM" cherry …` + rc 124 면 `cg_fail cherry` = `REJECT cherry 게이트 — cherry 7초 초과(묶음 1 · 마지막 <feat>..<nano>)` | ⓗ · 변이 = cherry 를 도우미 밖으로 → ⓗ FAIL |

같은 방법으로 ⑤ 안의 다른 외부 호출도 도우미 안으로 넣었다 — `merge-tree` · `merge-tree delta`(`diff-tree`) · `merge-base` (초과 시 각각 단계 이름 있는 REJECT).

### 실측 (이 맥 · 2026-10-26 · `rework-r2-repro.sh`)
| 축 | 값 |
|---|---|
| 반례 1 · base 판(`origin/main`) | REJECT rc=1 (`design/ 밖 변경 2개` · `app/a.py` · `app/b.py` 둘 다 미랜딩) |
| 반례 1 · 고침 판 | **base 판과 stdout 전문 동일 · rc=1** |
| 반례 1 · 변이(rename 검출 켬) | rc=0 통과 = 누출 재현 |
| 반례 2 · 변이(cherry 도우미 밖) | **rc=0 · 9초 — `OK cherry 게이트 — … (+ 0)`** (DA 실측 9.22초와 같은 꼴) |
| 반례 2 · 고침 판 | **rc=1 · `REJECT cherry 게이트 — cherry 7초 초과(묶음 1 · 마지막 main..nano/x)`** |
| 시험 ⓐ~ⓗ (신규 22줄 단언 16→18 PASS) | ALL PASS · `/bin/bash` 3.2 도 ALL PASS — `rework-r2-test.txt` · `rework-r2-test-bash32.txt` |
| 기존 시험 재확인 | identical_head · squash · r938 step_timing · kit_bin_sync · **nano_close_suspended · nano_close_fail_closed 모두 rc=0** (fail_closed 4F 없음 — HEAD·base 같은 판) |
| 페어 사본 | `harness/kit/fable-team/bin/ft-nano-cherry-gate.sh` cmp0 · 게이트 337줄 ≤ 340 |


## r3 반송 고침 (DA⑥ r2 HOLD 2 · 반송서 `design/harness/evidence/r958-da6/REWORK-r958-r3.md` · 같은 축 보류 2회 = 재설계)

축 = «git 호출·출력을 자리마다 따로 다룬다». r1 은 cherry·rename, r2 는 rev-parse·따옴표 경로를 하나씩 고쳤고 그래서 남은 자리(`merge-base` · `diff-tree` · `ls-tree` · 로그 줄)가 또 샜다. r3 는 **구조로 닫는다**.

| 반례 | 자리(고침 전 HEAD `88bbabb3`) | 고침(구조) |
|---|---|---|
| 1. 따옴표 경로(`a"b.py`) — base 판 REJECT 를 r2 판이 통과(`content_landed_then_superseded` rc0) | 경로를 **줄 단위**로 파싱 → 따옴표로 감싼 이름(`"a\"b.py"`)이 트리의 실제 이름과 안 맞아 «어디에도 없는 이름» 이 되고 그게 `sup` 로 샘 | 경로를 내는 출력은 전부 **`-z`(NUL)**: `log --raw -z`·`ls-tree -z`·`diff-tree --name-only -z`. 해석기는 NUL 프레임을 그대로 읽는다(따옴표 풀기 의존 0) |
| 2. `rev-parse` 1회가 7초 상한 밖 → 17초 뒤 rc0 `OK(+ 0)` **조용한 통과** | `git -C "$REPO" rev-parse` 들이 상한 도우미 밖 | **모든 호출이 한 함수 `G <단계> <출력목적지> <인자…>` 를 지난다** — 맨 호출은 `cg_git` 정의 안 1줄뿐(안전망 ⓚ). 시간 초과 = 그 동사 이름 있는 REJECT |

`G` 의 출력 목적지를 인자로 받는 이유 = 리다이렉트 사고 방지. `G … > 파일` 꼴이면 상한 초과 REJECT 가 그 파일로 새어 «사유 없는 종료» 가 된다.

### 실측 (이 맥 · 2026-10-26 · `rework-r3-repro.sh`)
| 축 | 값 |
|---|---|
| 반례 1 · base 판(`origin/main`) / r2 판(`88bbabb3`) / r3 판 | rc=1 REJECT / **rc=0 통과(누출)** / **rc=1 · base 판과 stdout 전문 동일** |
| 반례 2 · r2 판 | **rc=0 · 16초 — `OK cherry 게이트 — … (+ 0)`** (DA 실측과 같은 꼴) |
| 반례 2 · r3 판 | **rc=1 · `REJECT cherry 게이트 — rev-parse 7초 초과(묶음 1 · 마지막 refs/heads/main)`** |
| 성능 · «+» 300 커밋 · 경로 2000 · git 1회 0.08초 | base 판 **100초** → r3 판 **2초 · 외부 호출 6회** |
| 시험 ⓐ~ⓚ (단언 36 PASS) | ALL PASS · `/bin/bash` 3.2 도 ALL PASS — `rework-r3-test.txt` · `rework-r3-test-bash32.txt` |
| 변이 2종 | «rev-parse 통로 밖» → ⓙrev-parse·ⓚ FAIL · «커밋 묶음 `-z` 뺌» → ⓘ FAIL(rc 0 vs base 1) |
| 페어 사본 | `harness/kit/fable-team/bin/ft-nano-cherry-gate.sh` cmp0 · 게이트 399줄 ≤ 400 |

## 알려진 한계·범위 밖 (DA 판정용)
1. ~~경로는 줄 단위로 해석한다~~ → **r3 에서 닫힘**: 경로를 내는 출력은 전부 `-z`(NUL)로 받는다. 따옴표·공백·탭·한글·rename 경로가 «없는 이름» 으로 새지 않는다(시험 ⓘ · 안전망 ⓚ).
2. `nmiss` 상한 20 에서 멈추는 규칙은 유지했지만, 경로 분류와 이력 대조를 나눠 돌리므로 **미스 20개를 넘는 입력**에서는 WARN·INFO 줄의 «개수 숫자» 가 종전과 다를 수 있다. **판정(REJECT/PASS)과 차단·WARN 커밋 목록은 같다**(시험 ⓑ 가 전문 대조).
3. `--squashed-pr` 경로가 쓰는 `ft-nano-cherry-pr.sh` 는 아직 경로마다 git 을 부른다 — 이 카드 범위 밖(카드 §구현범위 4).
4. 게이트가 `ft_git_capped.py` 를 같은 폴더에서 찾는다(없으면 `WARN` 1줄 + 상한 없이 1회). 런타임 bin 에는 함께 설치된다.

## 재현
```bash
bash feature-pack/fable-team/harness/evidence/r958/red-70s.sh        # ⓐ (약 75초 · 옛 판 70초 대기)
bash feature-pack/fable-team/harness/tests/test_cherry_gate_batch_r958.sh   # ⓐ~ⓗ (약 80초)
bash feature-pack/fable-team/harness/evidence/r958/rework-r2-repro.sh         # r2 반례 2건 재현+고침+변이 (약 30초)
bash feature-pack/fable-team/harness/evidence/r958/rework-r3-repro.sh         # r3 반례 2건(r2 판 대조) + 성능 (약 130초)
```

---

# r4 재설계 (arch 151 · 2026-10-27) — 7초 쪼개기는 접고 «비교 기준» 한 자리만 고친다

r3(`a921dfe4`)는 DA⑥ HOLD 3 으로 멈췄다(묶음 조회가 git 이력을 바꿈 = 반례 R1~R3). 원인 실측(arch 149)이 뿌리를 바꿨다: ⑤ 시간 초과의 진짜 원인은 **비교 기준(feat)을 잘못 고른 것**이다 — `ft-nano-close.sh` 가 팀 env `FT_NANO_FEAT` 를 나노 자신의 `.worktree-info.json` base 보다 먼저 썼다.

## 고친 자리 (파일 2 = ft-nano-close.sh 짝 2 + 시험 2)
| 파일 | 고친 자리 |
|---|---|
| `harness/kit/fable-team/bin/ft-nano-close.sh` · `harness/bin/ft-nano-close.sh`(짝 cmp0) | base 정합 블록(856~875행): `_ENV_FEAT` 보관 → `.worktree-info.json` 의 base 를 **먼저** → base 가 있으면 env 는 안 쓴다 → 둘 다 있고 다르면 `WARN 비교 기준 = 좌석 .worktree-info base(<base>) · FT_NANO_FEAT=<env> 무시(둘 다 있고 다름)` **1줄**. base 가 없을 때만 env. R42(base 가 sha 면 랜딩 브랜치 정보 없음) 판정은 info 에서 온 값에만 걸고, 그때 env 가 있으면 env 로 후퇴(옛 규칙 유지) |
| `tests/test_nano_close_suspended.sh` | 시험 1칸 추가 — **ⓐ** base(`origin/main`)+env(`feat/old`, 뒤진 가지) → ⑤ 기준 `origin/main` · WARN 1줄(두 값) · `INFO feat=origin/main @`(fetch 도 base 하나) · «기준 REJECT» 0 / **ⓑ** base 없음 → env 그대로(회귀 0) · WARN 0 / **ⓐ-2** base == env → WARN 0 |
| `tests/test_nano_close_step_timing_r938.sh` | **계약 갱신(DA 판정용)**: 시나리오의 «기준 브랜치» 를 env(`FT_NANO_FEAT`)가 아니라 `.worktree-info.json` base 에 쓴다(`setbase()` 도우미 · 그 파일은 git exclude). 종전에는 `base:"main"` 고정 + env `feat/x` 로 ⑤ fetch 경로를 탔는데, r4 계약에서는 base 가 이기므로 같은 의도를 base 쪽으로 옮겼다 — 단언·기대값은 그대로 |

## 실측 (이 맥 · 2026-10-27)
| 축 | 값 | 파일 |
|---|---|---|
| 새 시험 1칸 (ⓐ·ⓑ·ⓐ-2 + 기존 ⓐ~ⓖ) | **ALL PASS** (100 PASS) · `/bin/bash` 3.2 도 ALL PASS | `rework-r4-test.txt` · `rework-r4-test-bash32.txt` |
| 변이 «env 우선 되살림»(= info base 안 읽음) | 변이판 **rc=1 · FAIL 4** — 「WARN 1줄」·「fetch 도 base ref」·「WARN 줄 수」가 죽는다 = 시험이 순서를 실제로 문다 | `rework-r4-mutation.sh` / `.txt` |
| 실사건 입력(chatbot 나노 c-fix-k12) | base `origin/main` → 11커밋·«+» **5** ↔ 팀 env `feat/chatbot-main` → 854커밋·«+» **848** (읽기만 · 쓰기 0) | `rework-r4-real-case.txt` |
| 기존 시험 회귀 | `test_cherry_gate_batch_r958` · `identical_head` · `squash` · `step_timing_r938` · `kit_bin_sync` · `nano_close_fail_closed` · `nano_close_suspended` 전부 rc=0 | 아래 재현 절 |

## 재현
```bash
bash feature-pack/fable-team/harness/tests/test_nano_close_suspended.sh        # ⓐ·ⓑ·ⓐ-2 포함 (약 40초)
/bin/bash feature-pack/fable-team/harness/tests/test_nano_close_suspended.sh   # bash 3.2 판
bash feature-pack/fable-team/harness/evidence/r958/rework-r4-mutation.sh       # 변이 — ⓐ 3단언 FAIL (약 40초)
```

## 범위 밖 (DA 판정용)
1. `--branch` 값이 정본 줄기(base)일 때 막는 자리(825행)는 여전히 `FT_NANO_FEAT` 를 본다 — r4 는 base 정합 블록 한 자리만 고쳤다(카드 §구현범위 1).
2. 7초 쪼개기 가지(`a921dfe4`)는 **보존만** — 되살리지 않았다(반례 R1~R3 미해결).
3. `test_nano_close_step_timing_r938.sh` 의 ⓗ(상한+유예 ≤3초)는 이 맥에서 가끔 4초로 흔들린다(2회 재실행 ALL PASS · 이 변경과 무관한 시각 경계).

---

# r5 — 오빠 결정 1번(구현만 한 번 더 · 반례 집합·계약 동결) · «쪼개기 접음» (2026-10-27)

## 무엇이 어긋나 있었나
r4 세트(`93bf3f06`)는 r3 쪼개기 커밋(`a921dfe4`) **위에** 쌓여 있었다. 카드 r4 절은 «쪼개기는 접고 비교 기준 한 자리만 · `a921dfe4` 는 보존만» 인데, 그대로 착지하면 쪼개기 코드가 같이 랜딩한다.
DA⑥ r3 반례 1(여러 경로를 한 번에 조회하면 git history simplification 이 판정을 바꾼다)은 **쪼개기 자체의 성질**이라, 쪼개기가 착지물에 남아 있는 한 동결된 반례 집합을 닫을 수 없다. 그래서 r5 는 r1~r3 의 게이트 변경을 되돌린다(커밋은 r4 세트 위 1개 · 가지·폴더 보존).

## 고친 자리 (되돌림 = 기준판 `a1fccaf7` 과 같게)
| 파일 | r5 뒤 |
|---|---|
| `bin/ft-nano-cherry-gate.sh` · `kit/fable-team/bin/ft-nano-cherry-gate.sh` | 기준판 그대로(차이 0) — 묶음 조회·`G` 통로·NUL 프레임 전부 제거 |
| `tests/test_cherry_gate_identical_head.sh` | 기준판 그대로(게이트 줄 수 상한 400 → 200) |
| `tests/test_cherry_gate_batch_r958.sh` | 삭제(쪼개기 전용 시험 · 기준판에 없는 파일) |
| `tests/test_nano_close_step_timing_r938.sh` | ⓘ «배수 = 커밋 수» 로 되돌리고 r4 `setbase()` 만 남김 |
| `bin/ft-nano-close.sh` · `kit` 사본 | `nf_mult_batches()` 삭제 · ⑤ 배수 = `nf_mult_commits()`(r938 그대로) |

남긴 것 = 카드 r4 §구현 범위 1~2: base 정합(좌석 `.worktree-info` base «먼저» · `FT_NANO_FEAT` 는 base 없을 때만 · 다르면 WARN 1줄) + 시험 ⓐ/ⓑ/ⓐ-2.

## 실측 (이 맥 · 2026-10-27)
| 무엇 | 값 |
|---|---|
| 게이트 2벌 · identical_head 시험 vs 기준판 | `git diff` 출력 0 (바이트 동일) |
| `cmp` bin ↔ kit (close · cherry-gate) | 둘 다 cmp0 |
| `grep -c nf_mult_batches` | 0 |
| 시험 6종(`rework-r5-test.txt`) | suspended · step_timing(115단언) · identical_head · squash · kit_bin_sync · fail_closed **전부 rc=0** |
| `/bin/bash` 3.2 판(`rework-r5-test-bash32.txt`) | 같음 — 전부 rc=0 |
| 변이 «묶음 수 배수 되살림»(`rework-r5-mut.txt`) | rc=1 · `FAIL [ⓘ]` = 시험이 «배수 = 커밋 수» 계약을 문다 |
| 실사건 입력(chatbot 나노 `origin/main` ← base · 읽기만) | `rc=0` · `0초` · `INFO … «+» 5개 … merge-tree delta design/ 밖 0 … 통과`(`rework-r5-realcase.txt`) |

## 재현
```bash
bash feature-pack/fable-team/harness/tests/test_nano_close_step_timing_r938.sh   # ⓘ 포함 115단언 (약 25초)
bash feature-pack/fable-team/harness/tests/test_nano_close_suspended.sh          # ⓐ·ⓑ·ⓐ-2 (약 40초)
bash feature-pack/fable-team/harness/tests/test_kit_bin_sync.sh                  # 짝 cmp0
```

## 알려진 한계 (DA 판정용 · 정직 고지)
1. 이 맥에서 `test_nano_close_step_timing_r938.sh` 가 부하가 높을 때 1회 `FAILED 2`(rc=1)로 흔들렸다. 곧바로 4회 재실행 = **115 PASS · FAIL 0 · rc=0**(3회 연속 포함). 흔들린 2단언의 이름은 그 실행의 꼬리 출력만 남아 확정하지 못했다 — 시각 경계(ⓗ ≤3초) 흔들림으로 본다(카드 r4 절 «알려진 한계 3» 과 같은 자리). 재현 스크립트는 위 6종 그대로다.
2. 쪼개기(큰 나노의 70초 초과)는 이 카드가 닫지 않는다 — 카드 r4 절대로 **별 카드 후보**다. 이 카드가 닫는 것은 «비교 기준을 잘못 골라 1,722커밋을 비교하던 것» 이다.
3. `--branch` 가 정본 줄기일 때 막는 자리(825행)는 여전히 `FT_NANO_FEAT` 를 본다(카드 §구현범위 1 범위 밖 · r4 기록 그대로).
