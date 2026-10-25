# r897 r10 — ft-scratch-repo «지우는 길» 한 곳 게이트 (증거)

- 설계: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/DESIGN-r897-r10-reframe-20261025.md` (r10.2)
- 사전 DA 마감: `evidence/r897-da/VERDICT-r897-predesign-r10-r11.md` (r10·r11 = 핵심 질문 ①②④⑤ 발견 없음)
- 사거리: `feature-pack/fable-team/harness/bin/ft-scratch-repo.sh` + kit 짝 사본(cmp0) + 새 시험 1 + 기존 시험 1칸(계약 변경)

## 무엇이 바뀌었나 (설계 §해결 설계 1~6)
1. `cwd_holder` = 물리 경로 비교(`pwd -P`) · 경로를 못 읽으면 «붙잡음»(지우기 0).
2. 주인 대조 = `grep -Fxq`(rc≥2 = 건너뜀 + WARN).
3. 2720 빠른 길 `fast()` = 이름꼴 ∧ HEAD=sha8 ∧ detached ∧ `judged` rc0 — 예산(`FT_SCRATCH_JUDGE_BUDGET`) 안에서만, 아니면 24시간 규칙.
4. 지우기 직전 `recheck()` — 주인 생김/붙잡음 = 건너뜀 · 못 읽음 = 남은 항목 전부 0 · 70초 초과 = 남은 항목 다음 정리.
5. `--done` = 주인 자신만 · 정확 대조(ENVIRON) · lsof 실패·붙잡음 rc4 · 탭·개행 경로 rc2(불변식 r10.2).
6. 헤더 계약 2줄(사본은 일회용 · `--done` 은 주인 자신).

## 시험
- `tests/test_scratch_repo_r897_r10.sh` — 30 PASS (`after-green.txt` 원문)
  - V0 대역 아님: 실제 lsof 가 `/private/var/…` 를 내고 기준판 글자 비교는 «붙잡음 0»(빨강) · 고친 판은 붙잡음(초록)
  - ⓐ 물리 경로·경로 못 읽음 ⓑ `seat[` ⓒ 빠른 길 4조건 ⓓ 재확인 3꼴 ⓔ `--done` 8칸 ⓕ 기존 4종 + kit cmp0
  - 변이 5 전부 빨강: `pwd -P` 제거 → V0 · `-F` 제거 → ⓑ · detached 조건 제거 → ⓒ · recheck 제거 → ⓓ · 주인 대조 제거 → ⓔ
- `before-red-v0.txt` — 변이 1(`pwd -P`→`pwd`) 판에서 V0 가 빨강인 원문(= 기준판 cwd 보호 사망 재현)

## 실측 근거
- macOS `lsof -w -d cwd -Fpcn` 은 `/private/var/folders/…`, 등록부는 `/var/folders/…` → 글자 비교 불일치(10-24 sweep 로그 `held=0`).
- 실 등록부 293줄 전부 3칸(탭 든 경로 0) → r10.2 불변식(탭·개행 경로 rc2)이 정상 경로를 막지 않는다.

## r10.3 — DA⑥ r1 반송 r2 반영 (반송서 `evidence/r897-da/REWORK-r897-r2.md`)

DA⑥ r1 = HOLD 2(좁음). 핵심 ①③④ 는 닫혔고, «못 읽음을 지우는 길» 두 곳이 남았다.

1. **빠른 길 ③ detached 판정은 rc=1 «만»** — 옛 판은 `git -C p symbolic-ref -q HEAD >/dev/null 2>&1 && return 1` 이라 rc128(git 오류)도 «detached» 로 읽혀 1시간 사본이 빠른 길 후보가 됐다(기준판 0회 · 이 판 1회). 고침 = `r=$?` → `[ "$r" = 1 ] || return 1`(rc0·rc≥2 둘 다 «빠른 길 아님») + ④ `judged` 도 rc0 만 참(`judged p || return 1`).
2. **재확인 tmux·lsof 호출 상한** — 옛 판은 재확인 호출이 무제한(71초 실측)이고 마감 검사가 호출 «전» 에만 있어, 늘어진 호출 뒤에 그 항목을 그대로 지웠다. 고침 = `remtmo()`(남은 예산 = min(7초, 마감-지금) · 0 이하면 호출 자체를 안 함 → 남은 항목 지우기 0 + WARN) + `tmux_sessions_tmo`·`bounded` 로 호출을 감싸고 + 호출 «뒤» `overbudget()` 마감 검사(넘었으면 그 항목 지우기 0 + WARN · 남은 항목 다음 정리).

| 증거 파일 | 무엇 |
|---|---|
| `before-red-r2.txt` | 새 케이스 ⓤ·ⓥ 를 «고치기 전 판(f365f4ba)» 에 돌린 원문 = 빨강(반례 실재) |
| `after-green-r2.txt` | 고친 판 전체 시험 37 PASS · ALL PASS (기존 4종 + kit cmp0 포함) |
| `mutants-r2.txt` | 변이 8 전부 빨강 — 6-rc128 → ⓤ · 7-overbudget → ⓥ · 8-tmo(bounded 제거) → ⓥ |

- ⓤ = 가짜 `git` 이 `symbolic-ref` 에 rc128 · 새 사본(이름꼴·HEAD=sha8·detached·judged rc0·주인 없음) → 후보 0 · 삭제 0. 대조: 가짜 git 제거하면 같은 사본은 지운다(«못 읽음» 만 다르게 취급).
- ⓥ = ① 주인 없는 25시간 사본 + 재확인 tmux 가 8초 멈춤 → 7초 예산에 잘려 그 항목 삭제 0 + `WARN 재확인 못 읽음`(옛 판은 8초 뒤 그대로 삭제). ② 시계 대역으로 «호출은 빨리 끝났는데 마감을 넘은» 순간을 만들어 그 항목 삭제 0 + `WARN 재확인 마감 초과`.
- 변이 8-tmo 는 ⓥ① 만 잡고(호출 상한 제거 → 8초 뒤 삭제), 변이 7-overbudget 은 ⓥ② 만 잡는다 — 고침 두 조각이 각각 시험으로 묶여 있다.

## r4 (DA⑥ r3 HOLD → 하드 룰 14 재설계 · r10.5 · Opus 나노)

DA⑥ r3 반례 4건(cut rc 미검사 · date rc 미검사 · origin/main 확인 실패 = main 으로 후퇴 · 시험 주입 칸 빠짐/변이 9 가 사본 생성 실패로 빨강)은 모두 «빠른 길 아래 어딘가의 `$(…)` 가 rc 를 안 봄» 한 계열이다. 손 전수 표를 더 고치지 않고 **rc 를 안 보는 꼴을 쓸 수 없게** 바꿨다.

1. **`cap 변수 명령…`** 하나 — 출력은 변수로, rc 는 그대로. 지우는 길 함수(fast·judged·main_ref·orphans·cwd_holder·recheck·remtmo·overbudget·sweep_run·done_run)와 그 도우미에서 `$(`·백틱·파이프 0(시험 ⓨ 가 함수 이름으로 범위를 잘라 기계로 센다). `--sweep`·`--done` 본문은 범위를 자를 수 있게 `sweep_run`·`done_run` 함수로 옮김(동작 같음).
2. **외부 명령 줄이기** — 이름꼴 = 셸 정규식(cut 0) · 주인 대조 = `has_line`(셸 안 정확 대조 · grep·here-string 0) · lsof 해석 = `cwd_parse`(파이프 1개 · pipefail → cap 으로 rc 검사).
3. **시계(date +%s)** — orphans·판정 예산·judged·sweep 시작·루프·remtmo·overbudget 8곳 전부 rc0 ∧ 숫자일 때만. 못 읽음 = 그 실행 삭제 0(orphans) · 즉시 후보 0(예산) · 판정 안 끝남(judged) · 남은 항목 0(sweep·재확인).
4. **«A 실패면 B» 후퇴** — `main_ref`: origin/main 확인 rc1(정말 없음)일 때만 main · rc≥2 = 판정 안 끝남. 판정 기준 트리 확인(`--git-dir`)을 ref 확인보다 먼저(트리 없는 환경 = 조용히 «안 끝남», 기존 시험 그대로).
5. **tmp.* 목록** — `id`·`find` rc 검사(실패 = tmp.* 삭제 0) · 줄 단위 + `$TD/tmp.<이름>` 꼴만(옛 `for d in $(find)` 는 공백 든 TMPDIR 경로를 조각내 삭제 함수에 넘길 수 있었다 — 부수 봉인).

| 증거 파일 | 무엇 |
|---|---|
| `before-red-r4.txt` | 새 칸 ⓧ·ⓨ 를 «고치기 전 판(a12e197c)» 에 돌린 원문 = 21칸 빨강(date 10 · awk 4 · origin/main 2 · cut 호출 5회 · 기계 검사 3) |
| `after-green-r4.txt` | 고친 판 전체 시험 103 PASS · ALL PASS(기존 4종 + kit cmp0 포함 · 5분5초) |
| `mutants-r4.txt` | 변이 16 전부 «기대한 칸만» 빨강 — 다른 FAIL 이 섞이면 검출로 안 센다(변이 9 = merge-base rc≥2 처리 삭제 → ⓦ mergebase 1칸 · 변이 5 = ⓔ 안 연쇄만 허용) |
| `CALLTREE-r897-r4.md` | 지우는 길의 cap 호출 전수 — 시험 ⓨ 가 자동 생성(손 표 0 · `FT_CALLTREE_OUT`) |

- ⓧ = 대역 하나(`inj`)를 git·date·awk·cut·tmux·lsof 이름으로 깔고, 대조(주입 0) 실행에서 호출 자리별 횟수를 잰 뒤 «N번째 맞는 호출만» 실패시킨다 — 자리마다 «진짜 출력 + rc128» / «빈 출력 + rc128» 두 꼴 · 주입이 실제로 걸렸는지(`inj.fired`)도 본다(빈 칸 = FAIL). judged 안 `rev-parse HEAD` 재호출은 #2 로 따로 검증.
- 대조: 주입 0 = 같은 사본을 빠른 길로 지운다 · origin/main 없음(rc1) = main 기준으로 지운다 — «지우기 0» 이 다른 이유가 아님.
