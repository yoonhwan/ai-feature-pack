# 설계 1쪽 — ci search 결과 줄 probe panic 감지·rg 폴백 (aifp-ft-arch-pi#2 · 2026-11-13)

> 발주: aifp-ft-master-pi#7 aifp 4187 · 발주서 `.fable-team/state/team-main/aifp-ft/orders/ci-search-nonascii-panic-20261113.md` · planner#286 aifp 4186 · harness#235 BYZ #295172 · 하드 룰 16
> 카드: `design/aifp/indices/대기/ci-search-nonascii-panic.md`

## 1. 실측 (2026-11-13 · origin/main a7f459c5 · 설치본 `~/.local/bin/ci` = 팩 판 심링크 · probe-code 0.6.0)

| 명령 (cwd = 팩 루트 · path = feature-pack/fable-team/ft2/core · --max 3) | rc | stderr panic 줄 |
|---|---|---|
| `ci search "판정 불가"` | 134 | 1 · `src/search/search_output.rs:2566:31 end byte index 30 is not a char boundary; it is inside '·'` · stdout 앞 40줄만(마지막 File = reopen.py) |
| `ci search "판정"` | 134 | 1 |
| `ci search "reopen"` (ASCII) | 134 | 2 (첫 호출 + `-i '*.md'` 재시도도 panic) |
| `ci search "verdict"` (ASCII) | 0 | 0 |
| `ci search "판정 불가" … 2>/dev/null \| head -3` | `$?`=0 · `PIPESTATUS[0]`=134 | — |

- 원인 자리: probe 가 결과 줄을 **출력할 때** 바이트로 자른다(search_output.rs:2566). 파일 종류(.py)와 질의 문자(ASCII)를 가리지 않는다. 결과 줄에 다중 바이트 글자(`·`·한글)가 잘림 자리에 걸리면 난다.
- 지금 래퍼(`feature-pack/code-intel/skill/scripts/ci` search 갈래 :127~174)의 가정 «markdown AST 청커 panic» 은 이 경우에 맞지 않는다. 비ASCII 갈래는 md 만 빼고, ASCII 갈래의 134 재시도도 md 만 뺀다. 그래서 둘 다 다시 panic 하고 rc 134 와 부분 stdout 이 그대로 나간다.
- harness rc=0 관측 = 부른 쪽 파이프의 마지막 명령 rc 다(`| head`). 래퍼 자체 rc 는 134 로 정직하다. 래퍼가 부른 쪽 파이프 rc 를 바꿀 수는 없다. 그래서 stdout **첫 줄**에 폴백 표지를 찍어 파이프로 읽는 쪽도 보게 한다.

## 2. 설계 (r2 · DA REJECT aifp 4189 R1~R3 보정)

- D1 한 함수 `_probe_search <q> <path> <max> [probe 추가 인자…]` — search 갈래의 probe 호출 3곳(비ASCII `-i '*.md'` 호출 · ASCII 호출 · OR 재시도)을 모두 이 함수로 바꾼다. 이 함수는 **아무것도 stdout 에 쓰지 않는다**. probe stdout·stderr 를 단계별 임시 파일(`${TMPDIR}` · trap 정리)에 받고, rc 와 panic 여부만 돌려준다.
- D1a 출력 보류(R1): search 갈래는 OR 재시도 여부가 정해질 때까지 **모든 단계의 출력을 보류**한다. 단계 = 첫 probe → (조건이 맞으면) OR probe. 다 끝난 뒤 한 번에 낸다.
  - 어느 단계든 panic 이면: 모든 단계의 probe stdout(첫 probe 의 `No results found` 포함)을 버리고 D3 폴백만 낸다. 그래서 폴백 표지가 언제나 전체 stdout 첫 줄이다.
  - panic 이 없으면: 지금과 같은 순서로 낸다(첫 probe stdout → OR 이면 `[hint]` stderr + OR stdout).
  - 비ASCII 갈래의 md rg 절은 그 뒤에 이어서 낸다(지금과 같은 자리).
- D2 panic 판정 = rc ∈ {134, 133, 101} (stderr 가 비어 있어도) **또는** stderr 에 `panicked at` 이 있음(rc 가 0 이어도). 아니면 그 단계 stderr 를 그대로 `>&2` 로 내고 rc 를 그대로 쓴다(지금 동작).
- D3 폴백(panic 이면 1회):
  - stderr 1줄: `[warn] probe panic rc=<N> (<panicked at 위치 또는 «stderr 없음»>) → rg 폴백 · 부분 출력 <k>줄 버림`.
  - rg 실행: `timeout <T> "$RG" -n --no-heading --color never -F -m 1 -e <낱말1> [-e <낱말2>…] -g '!**/.git/**' [-g '!*.md'] <path> > <임시 파일>` · **rg 원래 종료값 `rgrc` 를 이 자리에서 바로 받는다**(파이프 0 · R2). 여러 낱말은 OR · `-F` = 글자 그대로.
  - `-g '!*.md'` 는 panic 난 probe 호출에 `-i '*.md'` 가 있었을 때만 준다(비ASCII 갈래 md 절과 겹침 0).
  - `<T>` = `CI_RG_TIMEOUT` 이 1 이상 정수면 `min(CI_RG_TIMEOUT, 25)`, 아니면 25 (로컬 하네스 25초 상한 · 하드 룰 12 · R3).
  - 결과 제한: `rgrc` 를 받은 **뒤** 임시 파일에서 앞 `<max>` 줄만 읽는다(`head -n <max> <파일>` · rg 와 파이프로 잇지 않는다 → SIGPIPE 0 · 상한 절단은 실패가 아니다).
  - 결과 꼴 = 지금 md 절과 같다: `파일:줄` 다음 줄 `  <본문 앞 160자>`. 자르기는 **문자 단위**다(바이트 자르기 금지 · 출력 전체가 UTF-8 유효).
- D4 rc 규칙 (panic 이 났을 때 · **실패가 먼저** · 134/133/101 을 그대로 내보내는 일 0):

| 순서 | 경우 | rc | stdout |
|---|---|---|---|
| 1 | rg 없음(RG 빈 값·실행 불가) · `rgrc` = 124(시간 초과) · `rgrc` ≥ 2 | 3 | **0줄**(rg 가 실패 전에 낸 줄도 버림 · 비ASCII 갈래 md 절도 내지 않음 = stdout 전체 0줄) · stderr `판정 불가 ci search: probe panic rc=<N> · rg 폴백 실패(<사유> rc=<rgrc>)` |
| 2 | `rgrc` = 1 (0건) | 1 | 표지 + `(0건)` |
| 3 | `rgrc` = 0 | 0 | 표지 + 앞 `<max>` 결과 |

- D5 ASCII 갈래의 «134/133 이면 `-i '*.md'` 로 probe 재시도» 를 지운다. panic 자리가 md 청커가 아니라 출력 단계라서 재시도가 다시 panic 한다(실측 reopen 2회). panic 은 D3 하나로만 처리한다.
- D6 OR 재시도 조건 = 지금처럼 «첫 단계 rc 1 + 질의에 공백» 이고 첫 단계가 panic 이 아닐 때만. 첫 단계가 panic 이면 OR probe 를 부르지 않는다(폴백 rg 가 이미 OR). OR 단계가 panic 이면 D1a 대로 첫 단계 출력까지 버리고 폴백.
- D7 rg 경로 = `RG="${RG_BIN:-$(_resolve rg || true)}"` · RG_BIN 이 있으면 PATH 의 rg 보다 먼저 쓴다(PROBE_BIN·TILTH_BIN 과 같은 꼴 · 시험 대역 주입 자리).
- D8 그대로 두는 것: 비ASCII 질의의 md rg 절 · 결과가 있을 때 `rc 1 → 0` 보정(폴백 rc 3 은 보정하지 않는다) · probe `--timeout` · outline/sym/ast 갈래.

## 3. 반례 (시험 `feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` · 가짜 probe · 실 probe 0)

가짜 probe = 단계마다 꼴을 고른다(FAKE_PROBE_1·FAKE_PROBE_2: `panic`(부분 stdout 2줄 FAKE_PARTIAL + stderr `panicked at src/search/search_output.rs:2566:31` + rc) · `rconly`(stdout·stderr 0 + rc) · `nohits`(`No results found` + rc 1) · `hit`(결과 1줄 FAKE_HIT + rc 0) · `errpanic`(stderr panicked + rc 0)). fixture `core/a.py` 에 `판정 불가 · x`.

| 번호 | 입력 | 기대 | 기준판(origin/main ci) |
|---|---|---|---|
| P1 | 비ASCII 질의 · panic rc 134 + stderr | rc 0 · stdout 첫 줄 폴백 표지 · `a.py:<줄>` · FAKE_PARTIAL 0 · stdout UTF-8 유효 | FAIL(rc 134) |
| P2 | ASCII 질의 `reopen` · 같은 panic | P1 과 같음 | FAIL(rc 134) |
| P3a | rconly rc 134 (stderr 0) | 폴백 · rc 0 | FAIL |
| P3b | rconly rc 133 (stderr 0) | 폴백 · rc 0 | FAIL |
| P3c | rconly rc 101 (stderr 0) | 폴백 · rc 0 | FAIL |
| P4 | errpanic (rc 0 + stderr `panicked at`) | 폴백 · rc 0 | FAIL |
| P5 | panic · 질의 낱말이 fixture 에 없음 | rc 1 · 표지 + `(0건)` | FAIL |
| P6 | panic · `RG_BIN=/없는/경로` · PATH 에 rg 없음 | rc 3 · stdout 0줄 · stderr `판정 불가 ci search` | FAIL |
| P7 | 정상 hit (rc 0 · 결과 1줄) | stdout 그대로 · 표지 0 · rc 0 (회귀) | PASS |
| P8 | 정상 nohits rc 1 · 한 낱말 | rc 1 · 표지 0 (회귀) | PASS |
| P9 | panic · fixture 한 줄 = 다중 바이트 400자 | 결과 본문 ≤160자 · UTF-8 유효 | FAIL |
| P10 | 비ASCII 질의 panic · fixture `doc.md` 에도 낱말 | md 절 1번 · 폴백 절에 `doc.md` 0 (겹침 0) | FAIL |
| P11 | P6·P1 을 `set -o pipefail` 아래 `\| head -1` 로 | P6 `PIPESTATUS[0]` = 3 · P1 head 1줄 = 폴백 표지 | FAIL |
| P12 | 다중어 질의 · 1단계 nohits rc 1 → 2단계(OR) panic (R1) | stdout 첫 줄 = 폴백 표지 · `No results found` 0 · FAKE_PARTIAL 0 · rc 0 | FAIL |
| P13a | panic · RG_BIN 대역 = 결과 1줄 낸 뒤 rc 2 (R2) | rc 3 · stdout 0줄(대역 줄 0) | FAIL |
| P13b | panic · 실제 rg · path = 없는 폴더(rg rc 2) | rc 3 · stdout 0줄 | FAIL |
| P14 | panic · PATH 앞 가짜 `timeout` = 받은 인자 기록 후 rg 를 부르지 않고 즉시 rc 124 (sleep 0) (R2·R3) | rc 3 · 사유 rc=124 · stdout 0줄 · 기록된 인자에 RG 경로 | FAIL |
| P15 | panic · fixture 10파일 모두 hit · `--max 3` (R2) | rc 0 · 결과 정확히 3개 · stderr 에 SIGPIPE·판정 불가 0 | FAIL |
| P16 | panic · RG_BIN = 인자 기록 대역 · PATH 에 실제 rg 있음 (R3) | 대역이 불림(기록 1줄) · 결과 = 대역 줄 | FAIL |
| P17 | panic · `CI_RG_TIMEOUT=300` · PATH 앞 가짜 `timeout`(첫 인자 기록 후 나머지 실행) (R3) | 기록된 상한 = 25 | FAIL |

- 변이(원본 대조): V1 panic 판정 제거 → P1·P2 FAIL · V2 stderr `panicked` 조건 제거 → P4 FAIL · V3 rc-only 판정 제거(stderr 만 봄) → P3a·P3b·P3c FAIL · V4 rg 실패를 rc 0 으로 → P6·P13b FAIL · V5 바이트 자르기(`cut -b`) → P9 FAIL · V6 `-g '!*.md'` 제거 → P10 FAIL · V7 출력 보류 제거(단계마다 바로 출력) → P12 FAIL · V8 rg 를 `| head` 파이프로 잇고 파이프 rc 사용 → P13a FAIL · V9 25초 상한 제거 → P17 FAIL · V10 RG_BIN 무시 → P16 FAIL.
- 시험 안전선: 임시 폴더 · HOME·TMPDIR 격리 · 네트워크 0 · 재진입 가드 · `ulimit -u` + `timeout 70` · sleep 0(하드 룰 22 · 시간 초과는 가짜 timeout 의 rc 124 로만 만든다) · 100644.

## 4. 닫는 증거 (발주서 그대로)

1. 실 명령 `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3` → panic 이 새지 않음 · 폴백 표지 + 결과 · rc 정직(`PIPESTATUS[0]` ≠ 134)
2. 반례 시험 1개 rc 0 · 기준판 FAIL · 변이 10/10 FAIL
3. 착지 경로·sha → planner#286 1통

## 5. 범위 밖

- probe 바이너리 수정(외부 · upstream 신고는 별건).
- 부른 쪽 파이프 rc(`… | head` 의 `$?`) — 래퍼가 바꿀 수 없다. 표지 첫 줄과 `PIPESTATUS` 로만 보인다.
- outline/sym/ast 갈래(정상 · ast 는 r1706 에서 따로 처리됨).
