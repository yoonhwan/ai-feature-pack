# r926 증거 — 자율 인터뷰 명부 자리($ROOT 기준만) · 쌍둥이 경고가 «틀린 이동»을 시키지 않는가

카드 = `design/harness/indices/진행/r926-data-root-vs-repo-root-roster-and-twin-warn.md`
브랜치 = `nano/r926-data-root-vs-repo-root-roster-and-t` · base = `cbe218a5`(origin/main) · push 0(master).

## 고친 자리 2 + 짝 사본

| 파일 | 무엇 |
|---|---|
| `feature-pack/fable-team/harness/bin/ft-autonomy-level.sh` (`interview_note` + `_roster_common_root`) | 명부 자리 = **$ROOT 기준으로만** — ①`$ROOT/.fable-team/seats-planner.json` ②`$ROOT` 가 속한 리포의 공용 루트(`git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir` 의 부모 · 7초 상한) `/.fable-team/seats-planner.json`. cwd·설치 위치는 보지 않는다. 둘 다 없음 = WARN + rc1 |
| `feature-pack/fable-team/harness/bin/ft-team-lib.sh` (`_ft_team_twin_warn` + `_ft_team_branch_state`) | 루트 가지가 `origin/main` 을 품는지(`rev-list --count HEAD..origin/main` 1회, 7초 상한) 먼저 본다 — 안 품으면 «이동 0 · 원장은 ref 정본», 품으면 지금 문구 그대로, 못 물어보면 지금 문구 + «가지 확인 못 함». **timeout·gtimeout 이 둘 다 없으면 git 을 부르지 않고 unknown**(7초 상한 없는 git 금지) |
| `feature-pack/fable-team/harness/kit/fable-team/bin/{ft-autonomy-level,ft-team-lib}.sh` | 짝 사본 cmp0 |

### r2 반송(DA⑥ r1 HOLD 2) 고침 대조

| 반례 | 고침 | 시험 |
|---|---|---|
| 1. FT_ROOT=A · cwd=B 면 cwd 리포 명부로 감(`ft_repo_root "$HERE"` 가 cwd 를 봄) | 명부 후보를 `$ROOT` 기준 2곳으로만 좁힘(cwd·설치 위치 0) | ⓐ' ⓐ'' ⓐ''' |
| 2. timeout 도구가 없으면 7초 상한 없는 git 을 직접 부름 | `_ft_team_branch_state` 가 `command -v timeout/gtimeout` 둘 다 없으면 git 호출 0 = unknown | ⓓ' |

## 시험

```
bash feature-pack/fable-team/harness/tests/test_r926_root_roster_twin_warn.sh
python3 feature-pack/fable-team/harness/tests/mutate_r926_twin_warn.py
```

| 파일 | 무엇 | rc |
|---|---|---|
| `test-red.txt` | HEAD 판(고치기 전 = 5b3b492d) bin·kit 에 새 시험 → ⓐ' ⓐ'' ⓑ(둘) ⓓ' 빨강 5 fail(ⓐ'''·ⓒ 는 원래 초록 = 대조군) | 1 |
| `test-green.txt` | 고친 판 → 15 PASS · fail=0 | 0 |
| `mutation.txt` | 변이 4종(cwd 공용 루트 먼저 복귀 · 못 찾음 rc1→rc0 · timeout 없으면 git 직접 복귀 · 가지 검사 끔) 전부 빨강 = `MUTATION-ALL-RED` | 0 |
| `regress-autonomy-level.txt` | 기존 `tests/test_autonomy_level.sh`(interview-note 포함) 회귀 | 0 |
| `regress-team-lib-twin.txt` | 기존 `tests/test_team_lib_twin.py` + `test_team_lib_sparse.py` (21 passed · python3.11) | 0 |

새 시험이 보는 값 7개:
ⓐ' `FT_ROOT=A`(명부 desk-A) · cwd=B(명부 desk-B) → `desk-A` 로 발신, `desk-B` 0
ⓐ'' `FT_ROOT`=리포 안 작업 폴더(명부 없음) → 그 리포 공용 루트 명부(desk-R)로 발신, cwd 명부 0
ⓐ''' `FT_ROOT` 없음 · cwd 리포에 명부가 있어도 안 본다 → `WARN … 못 찾음(찾은 자리 2곳 …)` + rc1, 발신 0
ⓑ 명부가 어디에도 없음 → `WARN … planner 명부 못 찾음(찾은 자리 2곳: $ROOT/… · <공용 루트 못 풂>/…)` + rc1 (역호환: `$ROOT` 에만 있으면 그 명부로 발신)
ⓒ 쌍둥이 + 가지가 `origin/main` 을 품음 → 지금 문구(`ft-team-move.sh --apply …`)
ⓓ 쌍둥이 + 안 품음 → `데이터 루트 가지가 main 보다 1 뒤 · 이동 0 · 원장은 ref 정본` (`--apply` 0)
ⓔ `origin/main` 이 없음(못 물어봄) → 지금 문구 + `가지 확인 못 함`
ⓓ' PATH 에서 `timeout`·`gtimeout` 뺌 + `git` 대역(rev-list 만 8초) → **1초 안** «가지 확인 못 함» · `git.log` 에 rev-list 0

쌍둥이 시험(ⓒⓓⓔⓓ')은 stdout / stderr 를 따로 받아 **stdout = 경로 1줄**(`$T/w/design/teams/planner`)을 단언한다 — 15 PASS 중 `stdout = 경로 1줄` 단언 4건.

## 선행 기존 빨강(내 변경과 무관 — 고치기 전 HEAD 판에서도 같은 수)

`tests/test_team_move_roundtrip.sh` 4 fail · `tests/test_team_roster_ref.sh` 9 fail — 두 시험 다 되돌린 HEAD 판에서 fail 수가 같다(환경: 팩 체크아웃에 `harness/design/harness` 없음 · 임시 bin 에 `ft-resource-swap-lib.sh` 없음). 카드 범위 밖이라 손대지 않았다.

## 설치 대상(master 집행) — `LIVE_BIN` = `/Users/yoonhwan/.claude/fable-team/live/1.1.242/bin`

`ft-autonomy-level.sh` · `ft-team-lib.sh` 두 개 cp + cmp0.

## press

press 필요 없음(단위·격리 시험만 — 라이브 오디오 경로 0).
