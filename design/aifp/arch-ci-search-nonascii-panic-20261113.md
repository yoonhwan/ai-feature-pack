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

## 2. 설계

- D1 한 함수 `_probe_search <q> <path> <max> [probe 추가 인자…]` — search 갈래의 probe 호출 3곳(비ASCII `-i '*.md'` 호출 · ASCII 호출 · OR 재시도)을 모두 이 함수로 바꾼다. probe stdout·stderr 는 임시 파일(`${TMPDIR}` · trap 정리)에 받는다.
- D2 panic 판정 = rc ∈ {134, 133, 101} **또는** stderr 에 `panicked at` 이 있음. 아니면 stdout 을 그대로 내고 stderr 를 그대로 `>&2` 로 낸 뒤 probe rc 를 돌려준다(지금 동작).
- D3 panic 이면:
  - probe 부분 stdout 은 버리고 줄 수만 센다(잘린 블록을 결과로 보이지 않는다).
  - stderr 1줄: `[warn] probe panic rc=<N> (<panicked at 위치>) → rg 폴백 · 부분 출력 <k>줄 버림`.
  - stdout 첫 줄: `== rg 폴백 (probe panic rc=<N>) ==`.
  - rg 결과: `rg -n --no-heading --color never -F -m 1 -e <낱말1> [-e <낱말2>…] -g '!**/.git/**' <path>` → `head -n <max>`. 여러 낱말은 OR 다(지금 md 갈래 md_pat 과 같은 뜻). `-F` 라 정규식 글자는 글자 그대로 찾는다.
  - probe 호출에 `-i '*.md'` 가 있었으면 rg 에도 `-g '!*.md'` 를 준다(비ASCII 갈래의 md 절과 겹침 0).
  - 결과 꼴 = 지금 md 절과 같다: `파일:줄` 다음 줄 `  <본문 앞 160자>`. 자르기는 **문자 단위**다(바이트 자르기 금지 · 출력 전체가 UTF-8 유효).
  - rg 는 `timeout ${CI_RG_TIMEOUT:-25}` 안에서 돈다(로컬 하네스 25초 · 하드 룰 12).
- D4 rc 규칙 (panic 이 났을 때 · 134/133/101 을 그대로 내보내는 일 0):

| 경우 | rc | 출력 |
|---|---|---|
| rg 결과 1줄 이상 | 0 | 표지 + 결과 |
| rg 0건(rg rc 1) | 1 | 표지 + `(0건)` |
| rg 없음 · rg rc ≥2 · rg 시간 초과 124 | 3 | stderr `판정 불가 ci search: probe panic rc=<N> · rg 폴백 실패(<사유>)` · stdout 에 부분 출력 0 |

- D5 ASCII 갈래의 «134/133 이면 `-i '*.md'` 로 probe 재시도» 를 지운다. panic 자리가 md 청커가 아니라 출력 단계라서 재시도가 다시 panic 한다(실측 reopen 2회). panic 은 D3 하나로만 처리한다.
- D6 OR 재시도(:166~172)는 이번 호출이 이미 rg 폴백을 탔으면 건너뛴다(폴백이 벌써 OR 이다).
- D7 rg 경로 = `RG="${RG_BIN:-$(_resolve rg || true)}"`(PROBE_BIN·TILTH_BIN 과 같은 꼴 · 시험 대역 주입 자리).
- D8 그대로 두는 것: 비ASCII 질의의 md rg 절 · 결과가 있을 때 `rc 1 → 0` 보정 · probe `--timeout` · outline/sym/ast 갈래.

## 3. 반례 (시험 `feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` · 가짜 probe · 실 probe 0)

| 번호 | 입력 | 기대 | 기준판(origin/main ci) |
|---|---|---|---|
| P1 | 비ASCII 질의 · 가짜 probe = 부분 stdout 2줄(표지 FAKE_PARTIAL) + stderr `panicked at src/search/search_output.rs:2566:31` + rc 134 · fixture `core/a.py` 에 `판정 불가 · x` | rc 0 · stdout 첫 줄 폴백 표지 · `a.py:<줄>` · FAKE_PARTIAL 0 · stdout UTF-8 유효 | FAIL(rc 134) |
| P2 | ASCII 질의 `reopen` · 같은 panic | P1 과 같음 | FAIL(rc 134) |
| P3 | panic rc 101 | 폴백 · rc 0 | FAIL |
| P4 | rc 0 + stderr `panicked at` | 폴백 · rc 0 | FAIL |
| P5 | panic · 질의 낱말이 fixture 에 없음 | rc 1 · 표지 있음 | FAIL |
| P6 | panic · `RG_BIN=/없는/경로` · PATH 에 rg 없음 | rc 3 · stderr `판정 불가 ci search` · FAKE_PARTIAL 0 | FAIL |
| P7 | 정상 probe(rc 0 · 결과 1줄) | stdout 그대로 · 표지 0 · rc 0 (회귀) | PASS |
| P8 | 정상 probe rc 1(0건) · 한 낱말 | rc 1 (회귀) | PASS |
| P9 | panic · fixture 한 줄 = 다중 바이트 400자 | 결과 본문 ≤160자 · UTF-8 유효 | FAIL |
| P10 | 비ASCII 질의 panic · fixture `doc.md` 에도 낱말 | md 절 1번 · 폴백 절에 `doc.md` 0 (겹침 0) | FAIL |
| P11 | P6 을 `set -o pipefail` 아래 `\| head -1` 로 | `PIPESTATUS[0]` = 3 · P1 꼴이면 head 1줄 = 폴백 표지 | FAIL |

- 변이(원본 대조): V1 panic 판정 제거 → P1·P2 FAIL · V2 stderr `panicked` 조건 제거 → P4 FAIL · V3 rg 실패를 rc 0 으로 → P6 FAIL · V4 바이트 자르기(`cut -b`) → P9 FAIL · V5 `-g '!*.md'` 제거 → P10 FAIL.
- 시험 안전선: 임시 폴더 · HOME·TMPDIR 격리 · 네트워크 0 · 재진입 가드 · `ulimit -u` + `timeout 70` · 100644.

## 4. 닫는 증거 (발주서 그대로)

1. 실 명령 `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3` → panic 이 새지 않음 · 폴백 표지 + 결과 · rc 정직(`PIPESTATUS[0]` ≠ 134)
2. 반례 시험 1개 rc 0 · 기준판 FAIL · 변이 5/5 FAIL
3. 착지 경로·sha → planner#286 1통

## 5. 범위 밖

- probe 바이너리 수정(외부 · upstream 신고는 별건).
- 부른 쪽 파이프 rc(`… | head` 의 `$?`) — 래퍼가 바꿀 수 없다. 표지 첫 줄과 `PIPESTATUS` 로만 보인다.
- outline/sym/ast 갈래(정상 · ast 는 r1706 에서 따로 처리됨).
