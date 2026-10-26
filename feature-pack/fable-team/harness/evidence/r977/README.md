# r977 증거 — 비밀 판정의 «낱말 경계» 를 한 벌로 (ft_secret_shapes 3사본 + autonomy_scope_secret 2사본)

카드: `design/harness/indices/진행/r977-secret-shapes-one-boundary-all-copies.md` (harness-ops · arch#2 · master #170875 · 좌석 nano pi deepseek flash)
브랜치: `nano/r977-secret-shapes-one-boundary-all-copi` · 팩 base `1545012e` (origin/main) · push 금지(착지는 master)

## 원인 (한 줄)

비밀 «경계» 를 정하는 글자 집합이 파일 두 곳에 따로 있고 사본이 다섯이라, 한 곳만 고치면 다른 곳과 갈린다 —
r949 r3 가 `\b` → `(?<![A-Za-z0-9_-])` 로 바꾸자 `-github_pat_` 를 놓쳤고(하이픈이 덩어리 안이 됨), hooks 템플릿 사본은 안 고쳐 «사본 동일» 시험이 깨졌다.

## 고친 곳 (2 lib + 사본 3 · 한 커밋)

| 파일 | 무엇 |
|---|---|
| `bin/ft_secret_shapes.py` | `EDGE_CHARS = "A-Za-z0-9_"` 하나로 경계를 정의하고 `EDGE_L = (?<![A-Za-z0-9_])` / `EDGE_R = (?![A-Za-z0-9_])` 를 만든다. **하이픈·한글·문장부호는 경계**(base 의 `\b` 는 한글 뒤를 놓쳤고, r949 판은 하이픈 뒤를 놓쳤다). `token-prefix` 규칙이 이 두 상수만 쓴다. |
| `bin/ft_secret_shapes.py` (경계 밖 1줄) | `NOT_IN_CHUNK`(jwt 전용 «시작 제한»)은 **손대지 않았다** — 그것은 비밀 경계가 아니라 제곱 시간을 막는 성능 장치다. 여기에 하이픈을 허용하면 1MB 적대 입력(`"eyJaaaa-"*131072`)이 200ms 상한을 넘는다(실측 0.217s). |
| `bin/autonomy_scope_secret.py` | `SECRET_SHAPE` 의 `\b` 를 **같은 글자 집합**(`EDGE_CHARS = "A-Za-z0-9_"` · `EDGE_L`/`EDGE_R`)으로. 정의 중복은 남기되 집합은 한 벌(import 구조 변경은 카드 범위 밖). |
| `kit/fable-team/bin/ft_secret_shapes.py` · `kit/fable-team/templates/hooks/ft_secret_shapes.py` · `kit/fable-team/bin/autonomy_scope_secret.py` | 같은 커밋 · 바이트 동일(cmp0). |

`git diff` = 6파일 +90 −8 · 새 토큰 꼴 0(목록 확장 없음) · 가림 출력 글자·hook fail-open 정책 변경 0.

## 시험 (ⓐ~ⓔ · `tests/scripts/test_ft_secret_shapes.py` 에 추가 · 기존 칸 그대로)

| 축 | 무엇을 단언하나 | 값 |
|---|---|---|
| ⓐ | 4위치(공백 앞 · 한글 바로 뒤 · 괄호 안 · 하이픈 바로 뒤) × 꼴 6종(ghp_·gho_·github_pat_·xoxb-·sk-·AIza) → `mask` 가 `token-prefix` 1건 + 값 잔여 0 | base: `korean-*` 6건 FAIL(빨강) → 고침 뒤 142/142 PASS. `hyphen-github_pat_` 은 base 에서도 잡힘(회귀 0) |
| ⓑ | `SECRET_SHAPE` 가 같은 4위치 × 꼴 5종(ghp·xoxb·sk·AKIA·PEM)에서 True · **두 lib 의 `EDGE_CHARS`/`EDGE_L`/`EDGE_R` 문자열이 같다** | base: `korean-*` 4건 + 집합 비교 FAIL → 고침 뒤 PASS |
| ⓒ | 사본 5벌(3 + 2) sha256 동일 · `test_kit_copy_is_byte_identical` 포함 | `5591bf859ce01b93` ×3 · `1144d1bd2555e23a` ×2 |
| ⓓ | 소비자 4종(`test_secret_scan` · `test_secret_output_mask` · `test_evidence_inject_scan` · `test_flag_off_scan`) 셸 시험 rc0 을 pytest 가 직접 돌린다 | base rc=0/0/0/0 → 고침 뒤 rc=0/0/0/0 (`before-base-consumers.txt` · `after-consumers.txt`) |
| ⓔ | 변이 3종이 실제로 FAIL 하는가 | M1 경계 집합에 하이픈 → 11 FAILED(ⓐ hyphen-* 6 · ⓑ hyphen-* 5) · M2 hooks 사본 미반영 → 2 FAILED(ⓒ·kit_copy) · M3 autonomy 쪽만 고침 → 1 FAILED(경계 집합 비교) |

`python3.11 -m pytest tests/scripts/test_ft_secret_shapes.py -q` → **142 passed**(base 91 passed + 새 51) · 19.3s(1MB 적대·제곱 시간 상한 시험 포함).

## 곁들여 확인 (내 카드 밖 · 회귀 0 확인용)

| 시험 | 값 |
|---|---|
| `tests/test_kit_bin_sync.sh` | rc=0 ALL PASS |
| `tests/test_autonomy_scope.sh` · `_fp_r909` · `_plain3_r658` · `_pack` | rc=0 전건 |
| `tests/test_autonomy_scope_classify.sh` | rc=0 이지만 `FAILED 5` — **base 1545012e 에서도 같은 5건 FAIL**(remote URL 해석 실패 · 이 sparse 워크트리에서 원격 owner/name 이 안 풀림). 내 변경과 무관 · base 동일 |

## 파일 목록

| 파일 | 무엇 |
|---|---|
| `before-base-pytest.txt` | base 판 시험 결과(91 passed) |
| `before-base-consumers.txt` | base 판 소비자 4종 rc(전건 0) |
| `after-pytest.txt` | 고침 뒤 시험 결과(142 passed) |
| `after-consumers.txt` | 고침 뒤 소비자 4종 rc(전건 0) |
| `mutate1-edge-drops-hyphen.txt` | 변이 1 — 경계 집합에 하이픈(11 FAILED) |
| `mutate2-hooks-copy-lag.txt` | 변이 2 — hooks 사본 미반영(2 FAILED) |
| `mutate3-autonomy-only.txt` | 변이 3 — autonomy 쪽만 고침(1 FAILED) |
| `after-r2-pytest.txt` | r2 고침 뒤 시험(148 passed) |
| `after-r2-consumers.txt` | r2 고침 뒤 소비자 4종 rc(전건 0) |
| `mutate4-drop-value-not-eq-colon.txt` | 변이 4 — `(?![=:])` 삭제(ⓕ 2 FAILED) |
| `mutate5-pem-inside-edge.txt` | 변이 5 — PEM 을 EDGE 안으로(ⓖ 1 FAILED) |
| `r2-space-variant.txt` | 공백 앞 같은 꼴 base 대조 실측(남는 위험 1) |
| `after-r3-pytest.txt` | r3 보강 뒤 시험(148 passed) |
| `after-r3-consumers.txt` | r3 보강 뒤 소비자 4종 rc(전건 0) |
| `r3-both-masked.txt` | r3 두 입력(한글 앞·공백 앞) base ↔ r3 출력 대조 |
| `mutate4-named-masked-name-dropped.txt` | 변이 4(r3) — named 의 `***` 이름 허용 삭제(ⓕ'·ⓘ 2 FAILED) |
| `after-r4-pytest.txt` | r4 반송 처리 뒤 시험(150 passed) |
| `after-r4-consumers.txt` | r4 반송 처리 뒤 소비자 4종 + kit_bin_sync rc(전건 0) |
| `r4-diff-1000.txt` | r4 판 ④' 차분(1000입력) — 남는 위반 20건 원문 |
| `r4-variant-compare-1000.txt` | 같은 1000입력으로 r2·r3·r4 ④' 위반 수 대조 |
| `r4-mutate1-edge-drops-hyphen.txt` | 변이 M1 — 왼쪽 경계 집합에 하이픈(10 FAILED) |
| `r4-mutate2-hooks-copy-lag.txt` | 변이 M2 — hooks 사본 미반영(2 FAILED) |
| `r4-mutate3-autonomy-right-edge.txt` | 변이 M3 — autonomy 만 오른쪽 경계 되살림(1 FAILED) |
| `r4-mutate4-named-masked-name-restored.txt` | 변이 M4 — named `***` 이름 되살리기(3 FAILED) |
| `r4-mutate5-pem-inside-edge.txt` | 변이 M5 — PEM 을 EDGE 안으로(1 FAILED) |
| `r4-perf-standalone-3x.txt` | 1MB 상한 시험 단독 3회(15 passed ×3 · 부하 15) |
| `after-r4b-pytest.txt` | r4b(순서 교체) 뒤 시험(150 passed) |
| `after-r4b-consumers.txt` | r4b 뒤 소비자 4종 + kit_bin_sync rc(전건 0) |
| `r4b-diff-1000.txt` | r4b ④' 차분 — 집합 A(arch 정의) 0건 · 집합 B(이름 꼬리 2회) 239건 원문 |
| `r4b-perf-timings.txt` | 1MB × 8종 base ↔ r4b 시간 대조(최대 173ms) |
| `r4b-mutate1..6-*.txt` | r4b 변이 6종 — 각각 의도한 축에서 FAIL |

## press

press 필요 없음 — 라이브 오디오 경로와 무관한 정적 판정기(파일·단위 시험만으로 닫힌다). 나노는 쏘지 않는다(ft-press-gate ⑦).

## BTS 4축 정리

| 축 | 값 |
|---|---|
| 무엇이 바뀌나 | 출력 가림·비밀 판정의 «토큰 시작 경계». 한글 바로 뒤·하이픈 바로 뒤 토큰도 이제 잡힌다(가림 누락 0 쪽으로만) |
| 무엇이 안 바뀌나 | 가림 출력 글자(`***`), 자리표시자 예외, hook fail-open 정책, 토큰 꼴 목록, 소비자 코드(전부 «공용 판정 그대로» 호출) |
| 회귀 위험 | 늘어난 가림 = 오탐 가능성. 기존 평범한 출력 20건·자리표시자 11건 통과 유지, 소비자 4종 rc0 유지로 닫음 |
| FE Next.js 이슈(에러 오버레이·console.error) | 해당 없음 — 웹·FE 변경 0 |

## r2 (DA⑥ r1 HOLD 2 반송 · 2026-10-27) — 경계를 넓힌 대가로 새던 입력 2건만 되돌림

DA⑥ r1 원문 `design/harness/evidence/r977-da6/da-20261026-234331-51648.out`(astra high) HOLD 2 · 반송문 `REWORK-r977-r2.md` · 경계 글자 집합(`EDGE_CHARS = "A-Za-z0-9_"`)은 그대로.

| 반례 | 원인 | 고침 |
|---|---|---|
| 1 `한ghp_`+A30+`_API_TOKEN=`+B30 → base 는 named 가 B 를 가렸는데 현재판은 token-prefix 가 «이름 꼬리» 까지 삼켜 B 30자 노출 | `token-prefix` 값 글자 집합이 `_API_TOKEN` 을 포함 | 값 그룹 뒤에 `(?![=:])` — 끝 다음이 `=`·`:` 면 그 길이로는 안 맞고 역추적 → token-prefix 0 · named-secret 이 `이름=값` 을 가린다(출력 = base 와 바이트 동일) |
| 2 `note-----BEGIN RSA PRIVATE KEY-----` → base SECRET_SHAPE True · 현재판 False | PEM 머리말까지 EDGE 로 감쌈 | PEM 을 EDGE **밖** 별도 분기(base 구조 복원) · 나머지 4꼴(AKIA·gh·sk-·xox)만 EDGE 안 |

## 시험 r2 (ⓕ~ⓗ · 기존 ⓐ~ⓔ 그대로)

| 축 | 무엇을 단언하나 | 값 |
|---|---|---|
| ⓕ | DA 반례 1: 출력이 base `1545012e` 와 **바이트 동일** · 종류 = `named-secret` · B 30자 잔여 0 | PASS · 변이 4(`(?![=:])` 삭제) → **2 FAILED** |
| ⓖ | DA 반례 2: `SECRET_SHAPE` True · `reason()` = «추가 줄에 비밀 꼴» | PASS · 변이 5(PEM 을 EDGE 안으로) → **1 FAILED** |
| ⓗ | base 대조 전수 **89건**(기존 시험 입력 + 4위치 24) 에서 base 가 가린 값이 현재판 출력에 남지 않는다 · base True 인 SECRET_SHAPE 입력은 현재판도 True | PASS |

`python3.11 -m pytest tests/scripts/test_ft_secret_shapes.py -q` → **148 passed**(r1 142 + 새 6) · 72.7s · 소비자 4종 rc=0/0/0/0 · `test_kit_bin_sync`·`test_autonomy_scope` 4종 rc=0 · 사본 5벌 sha `45a080d9…`×3 · `1237b466…`×2.

## r2 남는 위험 — DA 판단 요청 1건 (r3 에서 닫힘 · 아래 r1 부터 남는 2건은 그대로)

1. **(r3 에서 닫힘)** **공백 앞 같은 꼴**(`" ghp_"+A30+"_API_TOKEN="+B30`): base = `token-prefix` 가 `ghp_A…_API_TOKEN` 를 가리고 **B 를 노출**, 현재판 = named 가 **B 를 가리고** `ghp_A…_API_TOKEN` 글자가 남는다(`r2-space-variant.txt`). 값 노출은 없어졌으나 «base 가 가린 글자 ⊆ 현재판» 이 이 입력 하나에서 성립하지 않는다. `(?![=:])` 를 무조건 걸면 두 경우가 함께 바뀌므로(문맥 없는 정규식), ⓕ 계약(base 와 바이트 동일 · 종류 named-secret)을 지키는 쪽으로 두었다. 한 줄 대안 = named 규칙이 `***=값` 도 이름=값으로 보게 하는 것(범위 밖 · DA 판정 대상).

## r3 (arch 답 · DA 전 보강 · 2026-10-27) — r2 가 남긴 «공백 앞» 반례를 둘 다 가려 닫음

r2 의 「남는 위험 1」에 대한 arch 답(`design/harness/evidence/r977-da6/REWORK-r977-r3.md`): r2 고침 1(`(?![=:])` 앞보기)은 «토큰 글자를 버리고 값을 가리는» 자리 바꿈이었다. 둘 다 비밀 꼴이므로 **둘 다 가린다** — 그러면 base 출력의 상위집합이 되어 ④'(base ⊆ 현재판)가 모든 입력에서 선다.

| 고침 | 무엇 |
|---|---|
| 1 | `token-prefix` 에서 r2 가 넣은 `(?![=:])` 앞보기를 **뺀다**(r1 꼴) — 토큰 글자는 base 와 같은 자리에서 가린다 |
| 2 | `_named`(named-secret)가 «이미 가려진 `***`» 도 이름으로 받는다(`MASKED_NAME = "***"` · 이름이 `***` 면 NAME 낱말 검사 건너뜀) — `***=값` 도 삼켜 값까지 가린다 |

경계 글자 집합(`EDGE_CHARS`)·PEM 분기(r2 고침 2)·소비자 코드는 **그대로**. 바뀐 파일은 `ft_secret_shapes.py` 3사본뿐(`autonomy_scope_secret.py` 2사본 무변경 · sha `1237b466…` 유지).

| 입력 | base `1545012e` | r3 |
|---|---|---|
| `한ghp_`+A30+`_API_TOKEN=`+B30 (DA⑥ r1 반례 1) | `한ghp_A…_API_TOKEN=***` — 토큰 글자 남음 | `한***=***` — 토큰+값 둘 다 |
| `" ghp_"`+A30+`_API_TOKEN=`+B30 (r2 판단 요청) | ` ***=B…` — **값 30자 노출** | ` ***=***` — 토큰+값 둘 다 |

| 축 | 무엇을 단언하나 | 값 |
|---|---|---|
| ⓕ' | DA 반례 1 → 출력 `한***=***` · hits = `token-prefix` 1 + `named-secret` 1 · B·`ghp_` 잔여 0 · base 가 가린 글자 ⊆ 현재판 | PASS · 변이 4(`***` 이름 허용 삭제) → **2 FAILED** |
| ⓘ | 공백 앞 같은 꼴 → 출력 ` ***=***` · 같은 hits · base 가 가린 글자 ⊆ 현재판 | PASS · 같은 변이 4 → **FAILED** |
| ⓗ | base 대조 전수 89건 그대로(누출 0) | PASS |
| ⓖ | PEM 그대로 | PASS · 변이 5 → **1 FAILED** |

`python3.11 -m pytest tests/scripts/test_ft_secret_shapes.py -q` → **148 passed**(r2 와 같은 수 — ⓕ 2건을 ⓕ'·ⓘ 로 바꿔 넣었다) · 사본 5벌 sha `c056a487…`×3 · `1237b466…`×2 · 소비자 4종 rc=0/0/0/0 · `test_kit_bin_sync`·`test_autonomy_scope` rc=0.

## r4 (오빠 결정 1번 · DA 호출 0 · 2026-10-27) — 범위 줄이기: 왼쪽 경계만 남기고 r2~r3 에서 넓힌 부분을 base 로 되돌림

반송문 `REWORK-r977-r4.md` · 같은 가지 `d5a53fff` 위 amend. DA r2 원문(`da-20261027-014004-32984.out`) 반례 ①·② 는 **둘 다 «넓힌 부분»** 에서 나왔다 → 넓힌 부분만 되돌린다.

| 되돌림/유지 | 무엇 | 결과 |
|---|---|---|
| 되돌림 ⓐ | named-secret 의 «이미 가려진 `***` 도 이름»(r3 고침 2) 삭제 — 이름은 `[A-Za-z_]+` 만 | DA r2 반례 ① `***: SERVICE_CUSTOMER_API_TOKEN=B30` → base 와 **바이트 동일** |
| 되돌림 ⓑ | «오른쪽» 경계(EDGE_R · `_EDGE_R`) 삭제 — base 꼴(AKIA 만 `\b`) | DA r2 반례 ② `ghs_AAAA…_` → SECRET_SHAPE **True**(base 와 같음) |
| 유지 | «왼쪽» 경계 한 벌(EDGE_L · `EDGE_CHARS = "A-Za-z0-9_"`) · PEM 머리말 EDGE 밖 · 5사본 같은 커밋 cmp0 · r2 앞보기 `(?![=:])` 없음 |

### 시험 (칸셈 바뀜: ⓕ'·ⓘ 를 base 기대값으로 · ⓙ 추가 · 알려진 한계 1칸)

| 축 | 무엇을 단언하나 | 값 |
|---|---|---|
| ⓕ' | DA r2 반례 ① → base 와 바이트 동일 · 종류 `named-secret` · B 잔여 0 | PASS · 변이 4(`***` 이름 되살리기) → **FAIL** |
| ⓘ | 공백 앞 `ghp_A…_API_TOKEN=B…` → base 와 바이트 동일(` ***=`+B30 · 값 잔존은 base 의 같은 한계) | PASS · 변이 4 → **FAIL** |
| ⓙ | DA r2 반례 ② 끝 밑줄 토큰 → SECRET_SHAPE True (base 도 True) | PASS |
| 알려진 한계 | `한ghp_A…_API_TOKEN=B…` → `한***=`+B30 · base 가 가린 B30 이 남는다(④' 위반 1건을 **시험으로 박아 둔다**) | PASS(그 상태를 단언) |
| ⓑ | 왼쪽 글자 집합 두 lib 동일 · 오른쪽 경계 상수 없음 · AKIA 만 `\b` | PASS · 변이 3(autonomy 만 오른쪽 경계 되살림) → **FAIL** |

`python3.11 -m pytest tests/scripts/test_ft_secret_shapes.py -q` → **150 passed**(r3 148 → ⓕ'·ⓘ 를 base 기대값 칸으로 바꾸고 ⓙ·알려진-한계 칸 2개 추가) · 소비자 4종 rc=0/0/0/0 · `test_kit_bin_sync` rc=0 · 사본 sha `31213303…`×3 · `8302dae6…`×2.

### ④' 차분 실측 — 같은 1000 입력으로 세 판본 비교 (`r4-variant-compare-1000.txt`)

| 판본 | ④' 위반(base 가 가린 글자 ⊆ 그 판본) |
|---|---|
| r2 `4eeec0e4` | 816 / 1000 |
| r3 `d5a53fff` | 36 / 1000 |
| **r4(현재)** | **20 / 1000** |

⇒ r4 가 세 판본 중 가장 작다. 남는 20건은 **한 꼴**이다(`r4-diff-1000.txt`): 왼쪽 경계로 토큰이 처음 잡히는 자리(한글·문장부호 바로 뒤)에서 token-prefix 가 `_API_TOKEN`·`TOKEN:` 같은 **이름 꼬리를 삼켜** base 의 named-secret 이 가리던 값을 놓친다. «왼쪽 경계를 넓힌 대가» 이며, r4 결정(새 설계 0 · DA 0) 밖이다 → **arch 판단 요청 1건**(고칠지/알려진 한계로 착지할지).

### 변이 5종 (r4 판) — `r4-mutate*.txt`

| 변이 | 결과 |
|---|---|
| M1 왼쪽 경계 집합에 하이픈 | 10 FAILED(ⓐ hyphen-* 6 · ⓑ hyphen-* 4) |
| M2 hooks 사본 미반영 | 2 FAILED(ⓒ·kit_copy) |
| M3 autonomy 만 오른쪽 경계 되살림 | 1 FAILED(ⓑ) |
| M4 named 의 `***` 이름 되살리기 | 3 FAILED(ⓕ'·ⓘ·알려진 한계) |
| M5 PEM 을 EDGE 안으로 | 1 FAILED(ⓖ) |

1MB 상한 시험은 부하 15 에서 전체 실행 때 1회 넘겼고(`named-spaced`), 단독 3회 연속 15 passed(`r4-perf-standalone-3x.txt`) — DA r2 가 적은 «부하 흔들림» 과 같은 현상.

## r4b (arch 판단 반송 #171942 · 2026-10-27) — 적용 순서 교체: «이름=값 → 토큰 꼴» · 집합·계약 변경 0

arch 판단: 남은 20건은 알려진 한계 착지 금지 · 계약 ④' 위반이므로 고침은 «구현 교체»(적용 순서)로 한다.

| 고침 | 무엇 |
|---|---|
| 1줄 | `_line` 에서 `_named`(이름=값)를 `RULES` **앞**으로 옮김 — 토큰 꼴이 `_API_TOKEN=` 이름 꼬리를 삼키기 전에 값부터 가린다. 규칙 집합·경계 글자 집합·PEM 분기·앞보기 0 모두 그대로. |
| 결과 | `토큰은ghp_A30_API_TOKEN=B30` → `토큰은***=***`(hits = named-secret → token-prefix) · base 가 가린 값도 포함 |

### 시험 (150 PASS 유지 · 칸 교체)

| 축 | 값 |
|---|---|
| ⓘ 공백 앞 | ` ***=***` · hits `[named-secret, token-prefix]` · base 가 가린 글자 ⊆ 현재판 (바이트 동일 기대는 폐기 — 가림이 늘어난 것이므로 반례 아님) |
| ⓘ 새 칸 = r4 차분 첫 입력 | `토큰은AIza`+`A1b2`×8+`API_TOKEN=`+B21 → `토큰은***=***` · B·AIza 잔여 0 · base 가 가린 값 잔존 0 |
| ⓗ 89건 | «알려진 한계 예외»를 지우고 전건 대조로 복귀 — 통과 |

### ④' 차분 재실행 (`r4b-diff-1000.txt`)

| 집합 | ④' 위반 |
|---|---|
| A. 이름 꼴 **1회**(arch 정의 — 토큰 꼴 × 4위치 × 이름 꼴 6 × 꾸밈 4, 1000건) | **0 / 1000** |
| B. 이름 꼬리 **2회** 이어붙인 적대 집합(내 생성기, 1000건) | 239 / 1000 |

B 는 «이름=값» 이 한 줄에 두 번 겹친 모양이다(`… _API_TOKEN=B20TOKEN:…`). 여기서는 **base 도 첫 값을 그대로 노출**한다(둘 다 한 값을 놓친다). 둘 다 가리려면 r3 의 «이미 가려진 `***` 를 이름으로 받기» 가 필요하고, 그것이 DA⑥ r2 반례 ① 이라 금지됐다. ⇒ arch 가 정한 집합 A 에서는 목표한 0 이고, B 는 범위 밖이다(arch 판단 대상).

### 시간 상한 (`r4b-perf-timings.txt` · 부하 27 · 1MB × 8종)

base 최대 156ms / r4b 최대 **173ms** — 200ms 아래지만 여유가 base 보다 17ms 쫓아졌다(순서 교체로 가린 뒤 본문을 한 번 더 읽는다).

### 변이 6종 (r4b 판) — `r4b-mutate*.txt`

M1 하이픈 10 FAILED · M2 사본 미반영 2 FAILED · M3 autonomy 오른쪽 경계 1 FAILED · M4 named `***` 이름 되살리기 1 FAILED(ⓕ') · M5 PEM 1 FAILED · **M6 순서를 base 꾸로 되돌림 3 FAILED**(ⓘ·새 칸·ⓗ).




1. `NOT_IN_CHUNK`(jwt 시작 제한)에 하이픈이 남아 `-eyJ…` 는 여전히 놓친다 — base 와 같은 거동이며, 카드가 «다른 규칙 변경 0» 으로 닫아 두었다. jwt 를 같은 경계로 옮기려면 제곱 시간을 푸는 별 카드가 먼저다(1MB 0.217s 실측).
2. `SECRET_SHAPE` 는 `github_pat_` 꼴을 모른다(목록 확장 = 별 카드). ⓑ 는 SECRET_SHAPE 가 아는 꼴 5종으로 단언했고, `github_pat_` 4위치는 ⓐ 가 덮는다.
