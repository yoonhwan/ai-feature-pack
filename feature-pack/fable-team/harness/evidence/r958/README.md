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
| `tests/test_cherry_gate_batch_r958.sh` (신규) | ⓐ~ⓗ (ⓖ·ⓗ = r2 반송 고침 · rename 무변경 · cherry 상한) |
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

## 알려진 한계·범위 밖 (DA 판정용)
1. 경로는 **줄 단위**로 해석한다(탭·개행이 든 파일명은 종전의 비-z `paths` 파싱과 같은 한계). 모자라면 «차단» 쪽으로 떨어져 조용한 통과는 없다.
2. `nmiss` 상한 20 에서 멈추는 규칙은 유지했지만, 경로 분류와 이력 대조를 나눠 돌리므로 **미스 20개를 넘는 입력**에서는 WARN·INFO 줄의 «개수 숫자» 가 종전과 다를 수 있다. **판정(REJECT/PASS)과 차단·WARN 커밋 목록은 같다**(시험 ⓑ 가 전문 대조).
3. `--squashed-pr` 경로가 쓰는 `ft-nano-cherry-pr.sh` 는 아직 경로마다 git 을 부른다 — 이 카드 범위 밖(카드 §구현범위 4).
4. 게이트가 `ft_git_capped.py` 를 같은 폴더에서 찾는다(없으면 `WARN` 1줄 + 상한 없이 1회). 런타임 bin 에는 함께 설치된다.

## 재현
```bash
bash feature-pack/fable-team/harness/evidence/r958/red-70s.sh        # ⓐ (약 75초 · 옛 판 70초 대기)
bash feature-pack/fable-team/harness/tests/test_cherry_gate_batch_r958.sh   # ⓐ~ⓗ (약 80초)
bash feature-pack/fable-team/harness/evidence/r958/rework-r2-repro.sh         # r2 반례 2건 재현+고침+변이 (약 30초)
```
