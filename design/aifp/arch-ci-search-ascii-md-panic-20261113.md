# 설계 1쪽 — ci search ASCII 질의 markdown probe panic (aifp-ft-arch-pi#3 · 2026-11-13)

> 발주: aifp-ft-master-pi#9 aifp 4307 · 발주서 `.fable-team/state/team-main/aifp-ft/orders/ci-search-ascii-md-panic-20261113.md` · 요청 harness#242 aifp 4306 · 발견 harness arch#337 BYZ 296913·296914 · 하드 룰 12·16
> 카드: `design/aifp/indices/대기/ci-search-ascii-md-panic.md` · 앞 카드: `design/aifp/indices/완성/ci-search-nonascii-panic.md`(착지 a9ab9b3c · 설계 `design/aifp/arch-ci-search-nonascii-panic-20261113.md`)

## 1. 실측 (2026-11-13 21:3x · 팩 origin/main 36509bff · 설치본 `~/.local/bin/ci` = 팩 판 심링크 · probe-code 0.6.0)

cwd = BYZ `.worktrees/harness-ops-m175`(39ae549f3c · md 15975 · 전체 34712) · `--max 3` · `/usr/bin/time -p timeout 25`

| 명령 | rc | real | stderr | stdout |
|---|---|---|---|---|
| `ci search "request register" .` (ASCII) | 0 | 6.79초(sys 54.83) | `[warn] probe panic rc=134 (src/language/markdown.rs:240:69:) → rg 폴백 · 부분 출력 2줄 버림` | 7줄 · 폴백 표지 + rg 결과 |
| `ci search "요청 register" .` (비ASCII · md 를 probe 에서 뺌) | 0 | 2.89초(sys 15.35) | `[info] 비ASCII 질의 → markdown 은 rg 로 분리 검색` | 141줄 · probe 결과 + md 절 |

- 팀장 재현(21:3x): 같은 명령 real 7.07초 · `timeout 7` 이면 rc 124.
- panic 자리 = `src/language/markdown.rs:240` = probe 의 markdown 청커(입력 단계). 앞 카드의 자리(`search_output.rs:2566` · 출력 단계)와 다르다.
- 원인 1줄: ci 는 비ASCII 질의만 md 를 probe 에서 뺀다(`ci` search 갈래 «1단계» if). ASCII 질의는 md 를 probe 에 넘기고, 다중 바이트 글자가 든 md 를 청커가 바이트로 잘라 panic 한다. 그래서 질의 문자와 상관없이 리포에 그런 md 가 있으면 죽는다.
- 시간: panic 전에 probe 가 md 까지 다 읽느라 sys 55초(병렬)·real 7초 근처다. md 를 빼면 2.9초다.

## 2. 길 선택지

| 길 | 내용 | panic | 7초 | 버린 줄 | 잃는 것 |
|---|---|---|---|---|---|
| (가) 추천 | 질의 종류와 상관없이 probe 는 늘 `-i '*.md'` · md 는 rg 절로 따로(지금 비ASCII 갈래를 모든 질의로 넓힘) | 0(청커가 md 를 안 봄) | 실측 2.89초 | 0 | ASCII 질의의 md 결과가 probe 순위 대신 rg 순서(파일당 1줄)가 된다 · ASCII 정상 호출 stderr 에 `[info]` 1줄 · md 절이 붙는다(앞 카드 C6 «ASCII 정상 호출 그대로» 를 이 범위만 바꿈) |
| (나) | probe panic 때 이미 받은 줄을 남기고 나머지만 rg | 경고 남음 | 안 줄어듦(6.8~7.1초 · panic 까지 다 읽음) | 0 | panic 난 프로세스의 부분 출력을 믿어야 함 · 앞 카드 C2(DA APPROVE 9c2002b6 · «panic 이면 부분 stdout 0») 을 뒤집음 |
| (다) | panic 이면 `-i '*.md'` 로 probe 1회 더 + md rg | 경고 남음 | 넘음(6.8 + 2.9 ≈ 9.7초) | 0 | 앞 카드 D5 가 지운 «md 뺀 재시도» 를 되살림 · 시간 두 배 |

- 추천 = (가). 이유: panic 원인(md 청커)을 아예 부르지 않는다. 시간이 실측으로 7초 안이다. 이미 착지한 비ASCII 갈래 코드와 시험을 그대로 넓히는 일이라 새 경로가 없다.
- 범위 밖: probe 판 올리기(upstream markdown.rs 고침 · 별건).

## 3. 설계 ((가) 기준 · 구현 = 나노)

- E1 1단계 probe 호출은 질의 종류와 상관없이 `_probe_search "$q" "$path" "$max" 1 -i '*.md'` 하나로 한다 · `md_excl=1` 고정. `nonascii` 갈림(1단계 if)을 지운다.
- E2 md 절(rg)은 모든 질의에 돈다. 지금 비ASCII 조건(`[ "$nonascii" = 1 ]`) 두 곳(md 결과 확보 · md 절 내기)을 지운다. 자리·순서는 앞 카드 D8 그대로(probe 출력 뒤 · md 결과는 OR 재시도 앞에 확보 · 결과가 있으면 rc 1→0).
- E3 md rg 질의 = 글자 그대로. 지금 `md_pat`(공백을 `|` 로 바꾼 정규식)을 쓰지 않고, 폴백과 같은 꼴 `read -ra` 낱말 분리(glob 확장 0) → `-F` + 낱말마다 `-e` 로 부른다. ASCII 질의에 `(`·`.`·`[` 가 흔해서 정규식이면 rg rc 2 로 md 결과가 조용히 0 이 된다.
- E4 md rg 도 `RG_BIN` → `_resolve rg` 경로(앞 카드 C7)와 상한 min(CI_RG_TIMEOUT, 25)을 쓴다. md rg 가 rc ≥ 2 또는 124 이면 md 절을 내지 않고 stderr `[warn] markdown rg 실패 rc=<N>` 1줄 · probe 결과와 rc 는 그대로(md 는 보조 절이라 판정 불가로 올리지 않는다).
- E5 `[info]` 문구 = `[info] markdown 은 rg 로 분리 검색(probe panic 회피)` 1줄 · 모든 질의 공통.
- E6 probe 단계 상한(하드 룰 12 · 로컬 하네스 25초): `_probe_search` 의 probe 호출을 GNU `timeout <pt>` 로 감싼다. `pt` = min(CI_TIMEOUT, 25) · 정수 아니면 25. probe 가 124 로 끝나면 그 단계 출력 버림 · stdout 0줄 · stderr `판정 불가 ci search: probe 시간 초과 rc=124 — scope 를 좁히세요` · rc 124. probe `--timeout` 인자도 같은 `pt` 로 맞춘다(지금 기본 90 은 25 상한 위반).
- E7 panic 판정은 앞 카드 C1 그대로. `timeout` 으로 감싼 뒤에도 probe 의 134·133·101 이 그대로 보여야 한다(아래 반례 A6).
- E8 그대로 두는 것: panic 폴백 C2·C3·C4·C8 · OR 재시도 조건(D6) · `_cut160` · outline/sym/ast 갈래 · SKILL.md.

## 4. 반례 (동결 · 시험 = 기존 `feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` 에 덧붙임 · 가짜 probe · 실 probe 0 · sleep 0)

| 번호 | 입력 | 기대 |
|---|---|---|
| A1 | ASCII 질의 + md 히트(doc.md 에 다중 바이트 줄) · 가짜 probe 정상 hit | probe 인자에 `-i '*.md'` 있음(인자 기록) · stdout = probe 출력 → 빈 줄 → `== markdown (rg 폴백 · probe panic 회피) ==` 절 · panic 경고 0 · rc 0 |
| A2 | 비ASCII 질의(기존 P1·P10·P18) | 기존 기대 그대로 PASS(md 절 1번 · 폴백 절에 md 0) |
| A3 | md 없는 fixture · ASCII 질의 · 정상 hit | md 절 없음 · stdout = probe 출력 그대로 · rc 0 |
| A4 | 가짜 probe 정상 nohits rc 1 · ASCII 한 낱말 · md 히트 0 | rc 1 · 표지 0 · md 절 없음(기존 P8 의 stdout 그대로) |
| A5 | 가짜 probe panic rc 134(md 빠진 probe 의 출력 단계 panic) | 앞 카드 C2 폴백 그대로 · rg 에 `-g '!*.md'` · md 절은 따로 1번 · 겹침 0 |
| A6 | 가짜 probe 가 스스로 `kill -ABRT` · `timeout` 감싼 뒤 | panic 판정 1 · 폴백(rc 134 그대로 내보냄 0) |
| A7 | 가짜 timeout(PATH 앞 · 인자 기록 + 즉시 rc 124) · probe 단계 | stdout 0줄 · stderr `판정 불가 … probe 시간 초과 rc=124` · rc 124 · 기록된 상한 = 25(CI_TIMEOUT=300 일 때) |
| A8 | ASCII 질의 `a.b(` · md 에 글자 그대로 `a.b(` 있음 | md 절에 그 줄 1개(정규식이면 rg rc 2 로 0줄 · 기준판 FAIL) |
| A9 | md rg 대역 rc 2 | md 절 0 · stderr `[warn] markdown rg 실패 rc=2` 1줄 · probe 결과·rc 그대로 |

- 변이(나노가 잡혀야 함): W1 E1 if 되살림(ASCII 에 `-i` 빠짐 → A1 FAIL) · W2 E3 정규식 되돌림(A8 FAIL) · W3 E6 상한 90(A7 FAIL) · W4 E4 실패 무시(A9 FAIL).
- 바뀌는 기존 기대: P7(정상 hit)·P8(정상 nohits) 은 fixture 에 doc.md 가 있으면 md 절·`[info]` 가 붙는다. 나노는 기대값을 E2·E5 대로 고치고, 고친 줄을 끝선에 적는다(기대 삭제 0).
- 파일 이름 줄바꿈·탭 = 범위 밖(하드 룰 18).

## 5. 닫는 증거 (발주서 ② 그대로)

1. 재현 명령 `cd ~/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops-m175 && ci search "request register" . --max 3` → panic 경고 0 · 버린 줄 0 · real 7초 안 · rc 정직(0 결과 / 1 0건).
2. 같은 명령 `| head -1` 의 `PIPESTATUS[0]` ≠ 134.
3. 비ASCII 회귀 `ci search "판정 불가" feature-pack/fable-team/ft2/core --max 3`(팩 루트) → 앞 카드 끝 기준 그대로.
4. 시험 rc 0 · 기준판(origin/main ci) A1·A3·A7·A8·A9 FAIL · 변이 W1~W4 4/4 FAIL · 회귀 3파일 rc 0.

## 6. 범위 밖

- probe 바이너리(외부 · upstream) · 부른 쪽 파이프의 `$?` · sym/refs/outline/ast 갈래 · SKILL.md 문구
- rg md 결과의 순위 품질(파일당 1줄 · rg 순서) — 바꾸려면 새 카드
