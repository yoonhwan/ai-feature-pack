# r1398 증거 — 카드 이력 사전을 spawn ① «앞» 에서 1회 만들고 ⑥ 까지 넘긴다

- 카드: `design/harness/indices/대기/r1398-nano-spawn-lint-map-once-before-open.md` (Issue #7628)
- 팩 가지: `nano/r1398-nano-spawn-lint-map-once-before-op` (base `origin/main` 2cc6068f)
- 끝: ⑥ 이동의 lint 가 git 을 다시 부르지 않는다 → 부하 35~41 에서도 «좌석은 떴는데 카드는 대기» 0 · 같은 워크트리 #1 재개설 0

## 바뀐 것 (3파일)

| 파일 | 변경 |
|---|---|
| `harness/bin/ft-nano-spawn.sh` · `kit/fable-team/bin/ft-nano-spawn.sh` | ① lint «앞» 블록 1개 = 사전 생성(`--map-only` 1회 · 상한 초과 = 재시도 1) → `export FT_CARD_ADDED_MAP_FILE` → 실패 = 부작용 0 REJECT · `_ON_EXIT` 정리 1줄 |
| `harness/bin/ft_card_map_lint.py` · `kit/...` | 카드 이력 git 상한 7초 → 25초(판정 4114 ⓐ · 세 곳 한 함수 `git_sec()` · env `FT_CARD_MAP_GIT_SEC` 는 시험 손잡이) · 문구 «git log 25초 상한 초과» |
| `harness/tests/test_nano_spawn_lint_map_once_r1398.sh` (신규) | S1~S7b · 44 PASS |
| `harness/tests/test_card_map_lint_r984.sh` | 옛 8초 지연 두 칸에 `FT_CARD_MAP_GIT_SEC=7` — 기본이 25 로 올라가도 «상한 넘김» 을 같은 값으로 잰다(문구·판정 불변) |

## 새 시험 (rc0 · 48초 · 44 PASS)

```
fail=0
```

## 기준판(origin/main) — FAIL

같은 시험 파일을 origin/main 사본에 돌린 결과(팩 사본 = `git archive origin/main feature-pack/fable-team/harness`):

```
FAIL S1 map_lint 호출 0
FAIL S1 호출이 --map-only + 카드 경로
FAIL S1 ① lint 는 export 된 사전을 물려받는다(빈 값 아님)
FAIL S3 호출 0
FAIL S4 rc=0
FAIL S4 REJECT 문구(좌석·워크트리·명부 0)
FAIL S4 ① lint 진입 0(부작용 0)
FAIL S2 사전 블록 추출 0 — ft-nano-spawn.sh 에 r1398 블록이 없다
FAIL S2 ① 앞 블록이 사전을 만든다
FAIL S2 ⑥ 이동 rc0(8초 지연 git log 를 안 탄다)
FAIL S2 이동 출력 MOVED
FAIL S2 카드 이동 0
FAIL S7 12초 rc=3 / S7 문구 = git log 25초 상한 초과 / S7 상한 함수 없음
FAIL S7b rev-list 3초 rc=0 / S7 기본 상한 상수 없음/다름
```

## 변이 6종 — 전부 빨강

| 변이 | FAIL |
|---|---|
| ① 앞 사전 블록 삭제 | 9 (S1·S2·S3·S4) |
| 재시도 0(`for _mapf_try in 1`) | 3 (S3) |
| 실패를 WARN 으로 넘김 | 3 (S4) |
| 정리 줄(`_ON_EXIT+=(_mapf_cleanup)`) 삭제 | 5 (S5·S6) |
| `GIT_SEC_DEFAULT = 7` 복귀 | 8 (S7 · S2) |
| `:175`(rev-list)만 `timeout=7` | 1 (S7b) |

## 기존 시험 (기준판과 같은 집합)

| 시험 | 이 가지 | origin/main |
|---|---|---|
| `test_card_map_lint_r984.sh` | FAIL 3 (실데이터 BAD 2 · 새 카드 스위치) | FAIL 3 (같은 3건) |
| `test_da_hold_gate.sh` | FAIL 10 | FAIL 10 (같은 10건) |
| `test_card_assign_watch_spawn_r1224.sh` | FAIL 4 | FAIL 4 (같은 4건) |
| `test_card_cap_gate_r1292.sh` | FAIL 5 | FAIL 5 (같은 5건) |
| `test_card_flow_r954.sh` | 150초 상한 초과 | 같음 |
| `test_nano_spawn_default_pi_r1385.sh` · `test_nano_spawn_disk_warn_r1078.sh` · `test_nano_spawn_tier.sh` · `test_nano_spawn_reopen_r1335.sh` · `test_nano_close_step_timing_r938_a.sh` · `test_acct_pause_r1214.sh` | rc0 | rc0 |

`ft-test-reentry-lint.sh tests/test_nano_spawn_lint_map_once_r1398.sh` = rc0(백그라운드 두 줄은 `# bg-ok:` 이유 + `wait` 회수).
