# r911 실 리포 dry-run 표 — 판정기 옛 판 vs 새 판 (반송 r3 재설계 뒤 재측정 · 읽기 전용 · 삭제·이동 0)

- 측정 2026-10-25 15:2x · 리포 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` · 기준 ref `origin/main` · 표본 = `refs/heads/nano/*` 최신순 **12개**
- 옛 판 = `origin/main:.../ft-finished-check.sh`(E1f 없음) · 새 판 = 이 카드(r3) · 재현 `OLD=<옛 판> NEW=bin/ft-finished-check.sh bash evidence/r911/dry-run-real.sh`
- ★전수 아님(표본 12)★ — 판정기 1회가 38~58초(카드 탐색·lsof)라 2307 가지 전수는 20시간급 · 부하 보호. 전수 표는 master/planner 몫.

## 값 (표본 12)

| 축 | 옛 판 | 새 판 |
|---|---|---|
| FINISHED | 0 / 12 | **4 / 12** |
| ACTIVE | 6 | 6 |
| ORPHAN | 6 | 2 |
| EMPTY | 0 | 0 |
| 판정이 바뀐 가지 | — | **4** (아래) |
| E1f ok(내용 같음) 를 본 가지 | 갈래 없음 | 5 / 12 |

### 새로 FINISHED (옛 판은 ORPHAN = 카드가 없어 영원히 «안 끝남»)

| 가지 | E1f | E0 | E3 | 폴더 |
|---|---|---|---|---|
| `nano/m5-solo-release-await-psid-recheck` | ok files=1 | ok 폴더 없음 | ok 좌석 0 | 없음 |
| `nano/c-brain-k12-wire-plan-json` | ok files=9 | ok 폴더 없음 | ok 좌석 0 | 없음 |
| `nano/m5-solo-hook-unmount-reset-press-release-r2` | ok files=23 | ok 폴더 없음 | ok 좌석 0 | 없음 |
| `nano/ccu-redis-commandstats-capture` | ok files=7 | ok 폴더 없음 | ok 좌석 0 | 없음 |

- 전문 = `evidence/r911/caught-*.txt`.
- ★표본은 살아 있는 값이다★ — 표를 만든 직후 재확인에서 `g2309-stt-selector-no-external-names` 는 좌석이 살아 E3 거짓으로 ACTIVE 로 돌아갔고 `m5-solo-hook-unmount-reset-press-release-r2` 는 그 사이 이미 `refs/archive` 로 옮겨져 «가지 없음» 이 됐다(다음 sweep 이 자동 수행 · 삭제 0).

## 가지별 (표본 시점)

| # | 가지 | 옛 판 | 새 판 | E1f 근거 |
|---|---|---|---|---|
| 1 | `nano/loom-1017-b-job-scheduler-dev-r2` | ACTIVE nano/loom-1017-b-job-scheduler-dev-r2 | ACTIVE nano/loom-1017-b-job-scheduler-dev-r2 | no files=7 first=design/teams/knowledge/evidence/EVIDENCE-loom-1017b-plan-20261025.md (ahead=10) |
| 2 | `nano/m5-solo-release-await-psid-recheck` | ORPHAN nano/m5-solo-release-await-psid-recheck | FINISHED nano/m5-solo-release-await-psid-recheck | ok files=1 (ahead=1) |
| 3 | `nano/l61-chunk-post-timeout-vs-gateway-queued` | ACTIVE nano/l61-chunk-post-timeout-vs-gateway-queued | ACTIVE nano/l61-chunk-post-timeout-vs-gateway-queued | no files=0 (ahead=0 — E1f 대상 아님) (ahead=0) |
| 4 | `nano/c-brain-k12-wire-plan-json` | ORPHAN nano/c-brain-k12-wire-plan-json | FINISHED nano/c-brain-k12-wire-plan-json | ok files=9 (ahead=5) |
| 5 | `nano/m7-lst-runtime-child-exception-accountin` | ACTIVE nano/m7-lst-runtime-child-exception-accountin | ACTIVE nano/m7-lst-runtime-child-exception-accountin | no files=4 first=tests/worker/unit/test_m7_lst_runtime_child_exception_accounting.py (ahead=1) |
| 6 | `nano/g2309-stt-selector-no-external-names` | ACTIVE nano/g2309-stt-selector-no-external-names | ACTIVE nano/g2309-stt-selector-no-external-names | ok files=8 (ahead=4) |
| 7 | `nano/m5-solo-hook-unmount-reset-press-release-r2` | ORPHAN nano/m5-solo-hook-unmount-reset-press-release-r2 | FINISHED nano/m5-solo-hook-unmount-reset-press-release-r2 | ok files=23 (ahead=10) |
| 8 | `nano/ccu-redis-commandstats-capture` | ORPHAN nano/ccu-redis-commandstats-capture | FINISHED nano/ccu-redis-commandstats-capture | ok files=7 (ahead=10) |
| 9 | `nano/ccu-research-schema-dump-set` | ORPHAN nano/ccu-research-schema-dump-set | ORPHAN nano/ccu-research-schema-dump-set | no files=1 first=design/teams/ccu/plans/RESEARCH-schema-dump-set-20261025.md (ahead=1) |
| 10 | `nano/r897-scratch-repo-auto-done-single-fail-` | ACTIVE nano/r897-scratch-repo-auto-done-single-fail- | ACTIVE nano/r897-scratch-repo-auto-done-single-fail- | no files=0 (ahead=0 — E1f 대상 아님) (ahead=0) |
| 11 | `nano/loom-1017-b-job-scheduler-dev` | ACTIVE nano/loom-1017-b-job-scheduler-dev | ACTIVE nano/loom-1017-b-job-scheduler-dev | no files=7 first=design/teams/knowledge/evidence/EVIDENCE-loom-1017b-plan-20261025.md (ahead=6) |
| 12 | `nano/ccu-step0-input-sheet` | ORPHAN nano/ccu-step0-input-sheet | ORPHAN nano/ccu-step0-input-sheet | no files=1 first=design/ccu/tools/job_round.sh (ahead=7) |
