# r989 증거 — ft-role-spawn.sh `--add` (같은 역할 «추가 좌석»)

카드: `design/harness/indices/진행/r989-role-spawn-add-second-seat.md` (harness-ops · arch#151 · planner #171504)
브랜치: `nano/r989-role-spawn-add-second-seat` (팩 `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/r989-role-spawn-add-second-seat` · base `origin/main` `4aebbddb`)
좌석: `byz-harness-nano-r989-role-spawn-add-second-seat#0` (pi · deepseek flash)

## 왜

역할 좌석 도구는 «갈아 끼우기» 만 안다. 같은 역할의 좌석을 하나 더 열려 하면 현역 좌석을 `stop-ready` 로 닫고 새 좌석에 `_replaces` 를 적는다. 그래서 arch 를 두 세트로 굴리려 하면 도구가 한 세트를 없앤다. `--add` 는 «더하기» 만 한다.

## 고친 곳 (도구 1벌 = kit/bin 짝 2 · 시험 1 · 증거 1)

| 파일 | 무엇 |
|---|---|
| `kit/fable-team/bin/ft-role-spawn.sh` · `bin/ft-role-spawn.sh` (cmp0) | 플래그 `--add` 하나 추가. ① 교체 대상(`OLD`) 계산 건너뜀 ② R437 `_<역할>` REJECT 검사 건너뜀 ③ 명부 쓰기에서 `old = []` — 기존 행에 `_replaced_by`·`stop-ready`·`tick=None` 0 · `_<역할>` 키 이동 0 · 새 행 `_replaces=[]` · `tick` = 역할 기본값(구 좌석에서 물려받지 않음) ④ retire 칸은 «구 좌석 있음» 조건이라 자동으로 안 붙음 ⑤ PLAN 에 `mode=add` |
| `tests/test_r989_role_spawn_add.sh` | 새 시험 1 (가짜 tmux/tmuxc·가짜 송신·임시 명부 — 실 좌석 0). ⓐ~ⓔ + ⑥ |
| `evidence/r989/` | 이 README + 채집물 |

`--add` 없는 호출의 코드 경로는 그대로다(`ADD=0` 기본 · 같은 줄 그대로 실행). 기존 시험 2종 ALL PASS 로 확인했다.

## 계약 ↔ 시험 (카드 대응표 그대로)

| 계약 | 시험 | 값 |
|---|---|---|
| ① `--add --dry-run` PLAN = `replaces=[<없음>] mode=add` · 기존 현역 행 불변 | ⓐ | `PLAN … replaces=[<없음>] mode=add` · dry-run 뒤 명부 `cmp0` |
| ② 실전 모의: 새 행 1 추가 · 기존 arch 행 `_replaced_by` 0 · `role` 그대로 · `tick` 그대로 · `_arch` 키 불변 | ⓑ | 구 #3 `role=arch tick=None _replaced_by=없음` · 새 #4 `_replaces=[]` · `_arch`=`#3` · 현역 arch 2 |
| ③ `--add` 첫 발주문에 retire 문구 0 | ⓒ | `--add` BODY 에 `retire=` 0 · 없는 호출엔 있음 |
| ④ `--add` 없는 호출은 지금과 같다(교체 · retire 문구 있음 · 기존 시험 PASS) | ⓓ | 구 #3 → `stop-ready`·`_replaced_by=#4`·`tick=None` · `_arch` = `#4` · `test_role_spawn_name.sh`·`test_role_spawn_team.sh` ALL PASS |
| ⑤ 변이: `--add` 가 old 를 닫도록 되돌림 → ⓑ FAIL | ⓔ | 변이본이 구 #3 에 `_replaced_by` 를 찍어 ⓑ 가 FAIL |
| ⑥ kit 짝 cmp0 · /bin/bash 3.2 | ⑥ | `cmp0` · `GNU bash 3.2.57` 로 시험 ALL PASS 15행 |

## 채집물

| 파일 | 무엇 |
|---|---|
| `after.txt` · `after-bin-bash32.txt` | 새 시험 ALL PASS 15행 — `bash` · `/bin/bash 3.2.57` |
| `plan-and-roster.txt` | `run-r989.sh` 출력 — dry-run PLAN 두 꼴 + 명부 전후(--add = 행 1개 추가·구 행 불변 / 없음 = 구 행 닫힘) |
| `mutate-close-old.txt` | `run-mutate.sh` 출력 — 변이본(`old = [] if add else …` → `old = …`)이 구 #3 을 닫는다 = ⓑ FAIL 재현 |
| `diff-kit.txt` | `git diff origin/main -- kit/fable-team/bin/ft-role-spawn.sh` |

## press

press 필요 없음 — 이 카드는 도구 한 벌이라 관측점이 PLAN 줄·명부 JSON 이고, 위 채집물이 그 값이다. 라이브 음성 경로를 건드리지 않는다.

## 남은 것 (master 소관)

- 착지 → 설치 `cmp0` → 실사건 `ft-role-spawn.sh arch --team harness --add` 로 세트2 arch 개설 1회(명부 두 arch 행 현역).
- 이 도구는 `_<역할>` 키를 «옮기지도 채우지도» 않는다(더하기만). 그래서 `_arch` 는 세트1 을 계속 가리킨다 — `ft-teamset-check.sh` 는 `_arch` 하나만 보므로 세트2 가 그 검사를 대표하지 않는다(R437 검사도 `--add` 에서는 건너뛴다 — 카드 §구현 범위 ②).
