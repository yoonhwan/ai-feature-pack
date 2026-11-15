# 인덱스: ci-search-test-files — 끝: ci search 가 시험 파일을 기본으로 찾는다 · 끄는 인자는 `--no-tests` 하나 · 모르는 `--` 인자는 path 로 삼키지 않고 rc 2 로 멈춘다(scope 밖 결과 0)
<!-- ledger: feature-pack/fable-team/legacy/1.x/harness/design/harness/GOAL-harness.md -->
- Issue: #8653 (byz-agents · 팀장 aifp-ft-master-pi#20 등록 BYZ 311538) — 발견 나노 aifp 5650 · 팀장 재현·발주 aifp-ft-master-pi#20 aifp 5656 · 하드 룰 16(코드 찾기 = ci 우선 · ci 불가 = 결함)
- 제안서: 없음 — 결함 복구 · 설계는 이 카드 «계약»·«반례 표» 가 전부(발주 상한 = 카드 1파일)
- 근거: 실측 2026-11-16 04:42(aifp-ft-arch-pi#20 · 팩 origin/main f01ce9f2 · probe-code 0.6.0 · cwd feature-pack/fable-team) — 아래 «실측» 절 8줄
- 원인 1줄: 래퍼 feature-pack/code-intel/skill/scripts/ci search 갈래가 probe 에 `--allow-tests` 를 주지 않아 probe 기본값(시험 파일·시험 블록 제외)이 그대로 걸린다 · 인자 파싱 `*) path="$1"` 이 모르는 `--` 인자를 path 로 삼켜 probe 는 그것을 옵션으로 읽고 path 는 cwd 로 떨어진다
- 앞 카드: design/aifp/indices/완성/ci-search-yaml-panic.md(착지 14ef74ac · PR #1096) · ci-search-ascii-md-panic · ci-search-nonascii-panic — 이 카드는 그 카드들의 L1~L6(목록 · rg 절 · panic 폴백 · 출력 보류 · 상한 25초)을 바꾸지 않는다
- 상태: 대기
- 착지: cf0d405248d7ba40cde46ae4daf741bf65f0c6aa(팩 main · PR #1332 squash · DA#11 APPROVE-IMPL BYZ 311592 · 세트 12840fa9 = PR head · 뺄 커밋 0)
- 설치: 있음 — ~/.local/bin/ci = 루트 checkout feature-pack/code-intel/skill/scripts/ci 심링크(착지 뒤 루트 main 반영 = 설치) · 사본 2곳 ~/.claude/skills/code-intel/scripts/ci · ~/.agents/skills/code-intel/scripts/ci ← 팩 판 cmp0
- 선행: 없음(팩 origin/main f01ce9f2)
- 시험 입력: 기존 시험 fixture + 새 fixture(src/mod.py · src/test_mod.py · tests/helper.py · src/a.spec.ts · src/lib.rs 의 `#[cfg(test)]` 블록) · 가짜 probe(PROBE_BIN · 받은 인자 기록 · 정상 hit/nohits/panic) · RG_BIN 대역 · sleep 0 · HOME·TMPDIR 격리 · 네트워크 0 · 실 probe 0
- 기준값: 재현 명령 `ci search prereq ft2/tests` = 결과 파일 0 → 목표 = 결과 파일 1 이상(test_keeper_next_prereq_line_r2027.py 포함) · path 밖 파일 0
- 규칙: 없음 — 하드 룰 16 문구와 훅은 그대로 둔다(래퍼가 룰에 맞게 돌아오는 것)
- 대상: 팩 feature-pack/code-intel/skill/scripts/ci(search 갈래 인자 파싱 · probe 호출 2곳 인자 · panic 폴백 rg 경고 1줄 · usage 1줄) · 시험 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh(덧붙임)
- 정본 영향 없음: code-intel 래퍼 search 갈래 내부 동작과 usage 1줄 · 스킬 문서(SKILL.md)·정본 문서 변경 0
- 배정: 좌석 aifp-ft-nano-ci-search-test-files#0

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
6 — 하네스 운영 정리. 하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」. 골의 축: A(모니터·요청 — 모든 하네스가 쓰는 코드 탐색 도구 ci 가 시험 파일도 찾는다). 이 카드의 증거 = 착지 sha + 시험 rc0 + 설치 cmp0 + 재현 명령 원문.

## 배경 (한 단락)
하드 룰 16 은 코드 찾기를 ci 로 하라고 한다. 좌석이 하는 일의 큰 몫은 시험 파일 읽기·고치기다. 그런데 `ci search` 는 시험 파일을 결과에서 뺀다. 좌석은 «No results» 를 «없다» 로 읽고 틀린 판정을 하거나 rg 로 돌아간다. `ci sym` 과 `ci ast` 는 시험 파일을 이미 본다(실측 ⑦·⑧). search 만 다르다. 또 좌석이 `--allow-tests` 를 직접 붙이면 path 가 cwd 로 바뀌어 scope 밖 결과가 나온다(실측 ⑤). 두 결함을 한 카드에서 고친다. 둘 다 같은 인자 파싱·같은 probe 호출 줄이다.

## 실측 (2026-11-16 04:42 · cwd feature-pack/fable-team · T = ft2/tests · F = test_keeper_next_prereq_line_r2027.py · rg 로 본 prereq 줄 = F 1파일)
| # | 명령 | 결과 |
|---|---|---|
| ① | `ci search prereq T` | rc 0 · 결과 파일 0 · «No results found.» |
| ② | `ci search prereq T/F` | rc 0 · 결과 파일 0 |
| ③ | `probe search prereq T --max-results 5 --timeout 25` | rc 0 · 결과 파일 0 |
| ④ | `probe search prereq T … --allow-tests` | rc 0 · 결과 파일 1(F) |
| ⑤ | `ci search prereq T --allow-tests` | rc 0 · 결과 파일 5 · 전부 path 밖(legacy/1.x/harness/…) · stderr `[warn] markdown·yaml rg 실패 rc=2` |
| ⑥ | `ci search prereq --allow-tests T` | rc 0 · 결과 파일 0(뒤 인자 T 가 path 를 덮어 써 `--allow-tests` 가 사라짐) |
| ⑦ | `ci sym test_prereqzz_two --scope <fixture>` | src/test_mod.py 정의 1건(시험 파일을 본다) |
| ⑧ | `ci ast 'def $F(): $$$B' <fixture> -l python` | test_mod.py · tests/helper.py 줄 있음(시험 파일을 본다) |

fixture(/tmp · 6파일 · 같은 낱말)에서 probe 가 기본으로 빼는 것: `test_*.py` · `tests/` 폴더 안 파일(이름이 helper.py 여도) · `*.spec.ts` · `.rs` 안 `#[cfg(test)]` 블록. 빼지 않는 것: conftest.py · 일반 파일. `--allow-tests` 를 주면 6파일 전부 나온다.

⑤ 의 까닭: 파싱이 `--allow-tests` 를 path 에 넣는다 → probe 호출이 `search prereq --allow-tests …` 가 되어 probe 는 옵션으로 읽고 path 인자는 없다고 보아 cwd 를 찾는다. rg 절은 `-- --allow-tests` 를 파일 경로로 받아 rc 2.

## 판정 (arch · 이유 1줄씩)
- 시험 파일 포함이 기본이다. 이유: sym·ast 와 같은 기본 · 좌석 일의 대상이 시험 파일 · «없다» 오판이 «많다» 보다 비싸다.
- 끄는 인자 = `--no-tests` 하나. `--allow-tests` 는 받아서 기본과 같게 둔다(좌석이 이미 쳐 본 인자 · 거부하면 다시 헷갈린다).
- 모르는 `-` 로 시작하는 인자 = rc 2 + usage 1줄 · probe·rg 호출 0. path 로 삼키지 않는다.
- 부작용 1개: `--max` 5칸을 시험 파일이 차지할 수 있다. 본 코드만 볼 때는 `--no-tests` 를 쓴다(usage 에 1줄).

## 계약
- T1 search 갈래의 probe 호출 2곳(1단계 · OR 재시도)은 기본으로 `--allow-tests` 를 준다
- T2 `--no-tests` 를 주면 두 호출 모두 `--allow-tests` 를 주지 않는다 · 인자 자리는 질의 뒤 어디든(path 앞·뒤 · `--max` 앞·뒤)
- T3 `--allow-tests` 는 받는다 · 동작은 기본과 같다 · path 에 들어가지 않는다 · `--no-tests` 와 함께 오면 뒤에 온 것이 이긴다
- T4 질의 뒤 인자 중 `-` 로 시작하고 `--max`·`--no-tests`·`--allow-tests` 가 아닌 것 = stderr `ci search: 모르는 인자 <글자> — ci search "<query>" [path] [--max N] [--no-tests]` 1줄 · rc 2 · probe·rg 호출 0 · stdout 0줄
- T5 path 는 그대로 probe 와 rg 에 간다 · 옵션이 path 를 덮어 쓰지 않는다 · path 를 안 주면 `.`(지금과 같음) · path 2개면 뒤 것(지금과 같음)
- T6 `--no-tests` 인데 panic 폴백을 타면 stderr 에 `[warn] rg 폴백은 시험 파일을 가르지 않는다` 1줄을 더 낸다(rg 로 probe 의 시험 판정을 흉내 내지 않는다)
- T7 usage 의 search 줄 = `ci search "<query>" [path] [--max N] [--no-tests]      의미/키워드 검색 (BM25 + AST 블록 · 시험 파일 포함이 기본)`
- T8 그대로: 앞 카드 L1~L6(뺄 확장자 목록 · rg 절 · panic 판정·폴백 · 출력 보류 · 상한 25초 · OR 조건) · `--max` 뜻 · rc 규칙 · doctor·bench 의 probe 호출 · 다른 갈래

## 반례 표
| # | 입력 | 기대 | 지금(기준판) |
|---|---|---|---|
| C1 | `ci search w <fx>` | 가짜 probe 가 받은 인자에 `--allow-tests` 1개 · path = `<fx>` | `--allow-tests` 0 |
| C2 | `ci search w <fx> --no-tests` | 받은 인자에 `--allow-tests` 0 · path = `<fx>` · rc 0 | path = `--no-tests` |
| C3 | `ci search w --no-tests <fx>` | C2 와 같음 | 우연히 같음(뒤 path 가 덮음) |
| C4 | `ci search w <fx> --allow-tests` | `--allow-tests` 1개 · path = `<fx>` · rg 절 path = `<fx>` · `[warn] … rg 실패` 0 | path = cwd · rg rc 2 |
| C5 | `ci search w <fx> --no-tests --allow-tests` · 순서 바꾼 것 | 뒤 것이 이김(앞 = 1개 · 뒤 = 0개) | — |
| C6 | `ci search w <fx> --bogus` | rc 2 · stderr 1줄(T4 글자) · 가짜 probe·RG 호출 기록 0 · stdout 0줄 | probe 호출됨 · path = `--bogus` |
| C7 | `ci search w -x <fx>` | C6 와 같음(짧은 옵션) | path = `<fx>`(`-x` 사라짐) |
| C8 | `ci search "a b" <fx>` + 가짜 probe 1단계 rc 1 | OR 재시도 호출에도 `--allow-tests` 1개 · `--no-tests` 면 0개 | 0개 |
| C9 | `ci search w <fx> --max 3` · `--max 3 <fx>` · `--no-tests --max 3 <fx>` | `--max-results 3` · path = `<fx>` · 시험 인자는 T1·T2 대로 | — |
| C10 | `ci search w <fx> --no-tests` + 가짜 probe panic | 앞 카드 폴백 출력 그대로 + T6 경고 1줄 · `--no-tests` 없으면 T6 경고 0 | — |
| C11 | `ci search w`(path 없음) | path = `.` · `--allow-tests` 1개 | path = `.` |
| C12 | `ci search w <fx> --max`(값 없음) | rc 2 · stderr 1줄 · probe 호출 0 | set -u 로 죽거나 빈 값 [확인 필요: 나노가 기준판 rc 를 적는다] |
| C13 | 앞 카드 검사 전부(235) | 기대 글자 그대로 통과 · 고칠 곳 = 가짜 probe 인자 비교에 `--allow-tests` 가 더해진 줄뿐 | — |

범위 밖 입력(하드 룰 18·19): 줄바꿈·탭이 든 path · `-` 로 시작하는 실제 폴더 이름(쓰려면 `./-이름`).

## 변이 (각각 지정 반례가 FAIL 해야 한다)
| # | 변이 | 잡는 반례 |
|---|---|---|
| X1 | 1단계 호출에서 `--allow-tests` 빼기 | C1 |
| X2 | OR 재시도 호출에서만 빼기 | C8 |
| X3 | `--no-tests` 를 무시(늘 줌) | C2 |
| X4 | 모르는 인자를 다시 path 로 삼키기 | C6 · C7 |
| X5 | `--allow-tests` 를 path 로 삼키기 | C4 |

## 구현 범위 (나노 1 · 팩 base origin/main)
1. feature-pack/code-intel/skill/scripts/ci search 갈래 — 인자 파싱(T2~T5) · probe 호출 2곳 인자(T1·T2) · 폴백 경고(T6) · usage 1줄(T7) · 다른 갈래 손 0
2. 시험 덧붙임 feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh — C1~C13 · 변이 X1~X5 · 기준판 = origin/main 판 ci · 재진입 가드 · ulimit -u + timeout 70 · 100644 · 시험 1개 70초 · sleep 0(룰 22)
3. 회귀: feature-pack/code-intel/tests/ 의 나머지 5파일 rc0

## 완료 조건
1. [~] 나노: 시험 전체(앞 카드 235 + C1~C13) rc0 · 검사 수 · 걸린 초 — rc0 아님: 나노 = `bash feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh` rc=1 · 294 검사 중 284 ok · 11초(aifp 5681) · DA 직접 = 새 판 294 검사 실패 10 · 기준판 235 검사 실패 10 · 실패 열 줄이 글자까지 같음(P7·P8·A1·A2·A3·A9·B1·B2·B3·B6 의 «기준판 … 통과 — FAIL 이어야») · 기능 새 실패 0 · 신규 C1~C12 통과(BYZ 311592 «두 전체 suite rc1 을 rc0 으로 주장하지 않는다») · 까닭 = 시험의 «기준판 대조» 블록이 BASE_SHA 를 origin/main 으로 잡는다(시험 파일 659줄) → 앞 카드가 착지한 뒤로는 기준판 = 고친 판 · ★착지 뒤 지금 main 에서 다시 돌린 값(aifp-ft-arch-pi#20 · 2026-11-16 05:09 · 루트 checkout 읽기 · 1회): rc=1 · 294 검사 · 실패 16 · 11초 · 기준판 = c419684f · 16줄 전부 «기준판 대조» 블록(위 10 + C1·C2·C4·C6·C7·C8) · 그 밖 FAIL 0★ = 이 카드도 착지하자 같은 꼴로 6줄이 더 늘었다 · 이 칸을 [x] 로 닫으려면 기준판 sha 를 결함이 있던 커밋으로 고정하는 fixture 보수(새 카드 · DA 311592 «별도 회귀 fixture 보수») 뒤 rc0 을 다시 잰다
2. [x] 나노: 기준판(origin/main ci) C1·C2·C4·C6·C7·C8 FAIL 원문 — 나노 = C1·C2·C4·C6·C7·C8 FAIL 각 1·2·2·3·3·1건(aifp 5681 · 원문 줄은 쪽지에 없음) · arch 재실행(aifp-ft-arch-pi#20 · 2026-11-16 05:09 · 기준판 ci = `git show 823d371f:feature-pack/code-intel/skill/scripts/ci` 를 /tmp 에 꺼내 `CI_UNDER_TEST=` 로 같은 시험 1회 · 11초): `FAIL C1 --allow-tests 1개 — 기대[1] 얻음[0]` · `FAIL C2 path = fx(--no-tests 가 path 아님)` · `FAIL C2 probe 에 --no-tests 0 — [--no-tests] 있으면 안 됨` · `FAIL C4 path = fx` · `FAIL C4 rg 절 path = fx`(rg 인자 끝 `-- --allow-tests`) · `FAIL C6 rc — 기대[2] 얻음[0]` · `FAIL C6 stderr 글자(T4)` · `FAIL C6 stdout 0줄` · `FAIL C7 rc — 기대[2] 얻음[0]` · `FAIL C7 stderr 글자` · `FAIL C7 stdout 0줄` · `FAIL C8 두 호출 --allow-tests 2개 — 기대[2] 얻음[0]` = 건수가 나노 값과 같다(기준판에서는 C10a·C11·C12 도 FAIL)
3. [x] 나노: 변이 X1~X5 각각 지정 반례 FAIL(5/5) — 나노 «변이 X1~X5 5/5 잡힘»(aifp 5681) · DA «T-X1~T-X5 검출»(311592) · 변이별 원문 줄은 두 원문에 없다
4. [x] 나노: 회귀 5파일 rc0 · 시험 파일 100644 · C12 기준판 rc 실측 1줄 — 나노 = 회귀 5파일 rc=0 · 시험 파일 100644 · C12 기준판 rc=1(`$2` unbound) → 새 판 rc=2(aifp 5681) · DA = 다른 회귀 5파일 모두 rc0(ast 0.99초 · refs 4.17초 · lsp-crash 2.64초 · lsp-visible 0.85초 · outline 2.43초) · arch 확인 = cf0d4052 의 시험 파일 mode 100644 · 기준판 재실행에서 `FAIL C12 rc — 기대[2] 얻음[1]`
5. [x] master: 착지 sha → 설치(루트 main 반영 · 사본 2곳 cmp0 · bash -n rc0) — 착지 = PR #1332 squash cf0d405248d7ba40cde46ae4daf741bf65f0c6aa(head 12840fa9 · gh pr view 로 대조) · arch 읽기 확인(aifp-ft-arch-pi#20 · 2026-11-16 05:09): 루트 checkout main = c784c409(cf0d4052 는 그 조상 · rc 0) · ~/.local/bin/ci · ~/.claude/skills/code-intel/scripts/ci · ~/.agents/skills/code-intel/scripts/ci 세 곳의 실제 대상 = 모두 루트 checkout feature-pack/code-intel/skill/scripts/ci(~/.agents/skills/code-intel → ~/.claude/skills/code-intel → 팩 skill 폴더 심링크) · 세 곳 모두 cf0d4052 판과 cmp 0 · bash -n rc 0
6. [x] master: 재현 명령 원문 3줄(cwd feature-pack/fable-team) — `ci search prereq ft2/tests` 결과에 test_keeper_next_prereq_line_r2027.py 있음 · `ci search prereq ft2/tests --no-tests` 결과 파일 0 · `ci search prereq ft2/tests --allow-tests` 결과가 전부 ft2/tests 아래 + rg 실패 경고 0 · 각 rc·real(7초 안) — arch 실측(aifp-ft-arch-pi#20 · 2026-11-16 05:09 · 설치본 ci · cwd = 팩 루트 · path = feature-pack/fable-team/ft2/tests · 팀장 발주 aifp 5711 의 명령): `ci search prereq <path> --max 3` rc 0 · real 0.19초 · `Found 2 search results` · 결과 파일 = ft2/tests/test_keeper_next_prereq_line_r2027.py(결함 보고 aifp 5650 때는 0건) / `… --max 3 --no-tests` rc 0 · real 0.06초 · 결과 파일 0 / `… --max 3 --allow-tests` rc 0 · real 0.12초 · 결과 파일 1 = 같은 파일(ft2/tests 아래 · path 밖 0) · stderr warn 줄 0 / 덧: `… --bogus` rc 2 · stderr `ci search: 모르는 인자 --bogus — ci search "<query>" [path] [--max N] [--no-tests]` · stdout 0줄 · 네 발주와 다른 곳 = 카드는 cwd feature-pack/fable-team 을 적었고 나는 팩 루트에서 전체 경로로 돌렸다(같은 폴더)
7. [x] master: 발견 나노(aifp 5650)와 하드 룰 16 을 쓰는 팀에 1통(«ci search 가 시험 파일을 본다 · 끄기 = --no-tests») — 팀장 aifp-ft-master-pi#21 알림 2통(팀장 aifp 5720): 발견 나노 aifp-ft-nano-ft2-prereq-unreadable-once#0 앞 aifp 5718(05:11:01 · «고침 착지 — main cf0d4052(PR #1332) · ci search 가 시험 파일을 기본으로 본다 · 끄기 = --no-tests» · arch 가 우편함 기록에서 원문 대조) · planner 앞 BYZ 311680(팀장 인용 · 원문 대조 안 함)
- 나노 끝선(5줄 이내): 바꾼 줄 범위 · 시험 결과 줄·초 · 기준판·변이 FAIL 목록 · 기대 글자 고친 검사 줄 · 설계와 다르게 한 점(없으면 «없음»)

## 계약↔시험 대응표
| 계약 | 시험 |
|---|---|
| T1 기본 포함 | C1 · C8 · C11 · X1 · X2 |
| T2 `--no-tests` | C2 · C3 · C8 · C9 · X3 |
| T3 `--allow-tests` 받음 | C4 · C5 · X5 |
| T4 모르는 인자 rc 2 | C6 · C7 · C12 · X4 |
| T5 path 유지 | C2 · C4 · C9 · C11 |
| T6 폴백 경고 | C10 |
| T7 usage | C6(stderr 글자) |
| T8 앞 카드 그대로 | C13 |

## 범위 밖
- probe 바이너리 수정 · probe 의 시험 판정 규칙(무엇을 시험 파일로 보는가)
- sym·outline·refs·ast·doctor·bench 갈래 · SKILL.md·하네스 상시 블록 문구(usage 1줄만 고친다)
- 후속 카드 감 1(카드 0 · 팀장 판단): 실 probe 0.6.0 은 0건일 때 rc 0 을 낸다(실측 `probe search zzzqqqxxnone ft2/tests` rc 0). 래퍼의 OR 재시도와 «rc 1 → 0 보정» 은 rc 1 일 때만 돈다. 그래서 실 probe 에서는 OR 재시도가 돌지 않고 0건도 rc 0 이다. 앞 카드 시험은 가짜 probe 의 rc 1 로만 이 길을 쟀다.

## 상태
- base_sha: 823d371f2736196c8391dcb9845a7c244a202b81 (recheck-auto 2026-11-16 · 겹침 0)
- 2026-11-16 04:44 · 대기 — aifp-ft-arch-pi#20 작성(aifp 5656 · 실측 ①~⑧) · 다음 = 팀장 PR → DA 사전검증 → 나노 1석
- 2026-11-16 04:48 · DA#11 APPROVE-DESIGN(BYZ 311517 · aifp 5668 · 사본 .fable-team/state/team-main/aifp-ft/DA-ci-tests-design-approve-311517/verdict.md) → 배정 줄 풂 · 팀장 aifp-ft-master-pi#20
- 2026-11-16 04:49 — 대기→진행 · 좌석 aifp-ft-nano-ci-search-test-files#0
- [배정 불명] 불명(scope 표 없음 opengateway/deepseek/deepseek-v4.1-flash-ultrafast)
- 2026-11-16 05:09 · aifp-ft-arch-pi#20 착지 줄 씀(팀장 aifp 5711) · 조건 2~6 [x] · 조건 1 [~](시험 전체 rc 1 = 기준판 대조 블록만 실패 · 착지 뒤 16줄) · 조건 7 = 팀장 몫(알림 1통)
- 알려진 한계: 시험 test_ci_search_nonascii_panic.sh 전체 rc 는 1 이다 — «기준판 대조» 블록이 origin/main 을 기준판으로 잡아, 고침이 착지한 뒤에는 «기준판 … 통과 — FAIL 이어야» 가 난다(앞 카드 몫 10줄 + 이 카드 몫 6줄) · 기능 검사 실패 0 · 고침 = 결함이 있던 커밋 sha 고정(별도 fixture 보수 카드 · DA 311592) · 그 밖 한계(DA) = --no-tests 에서 panic rg 폴백은 시험 파일을 가르지 않고 경고만 낸다 · 실 probe 0건 rc 0 이라 OR 재시도가 돌지 않는 것은 범위 밖 그대로
- DA 판정: APPROVE-IMPL 311592(사본 .fable-team/state/team-main/aifp-ft/DA-ci-tests-impl-approve-311592/verdict.md) · 승인 sha 12840fa9 · 수용 반례 0 · C1~C12 통과 · T-X1~T-X5 검출 · 회귀 5파일 rc0 · 전체 suite rc1(같은 10줄) 을 rc0 으로 주장하지 않음
- 2026-11-16 05:13 · aifp-ft-arch-pi#20 조건 7 [x](팀장 aifp 5720) · 조건 1 = 팀장 판단(하드 룰 21) «알려진 한계» 로 받아 DA 닫힘 판정으로 닫는다 · 보수 = 별도 카드 대기/ci-test-base-sha-pin
- 세트: 12840fa95f419d372f2329ef788d01a2fba3ef80 · 시험: bash feature-pack/code-intel/tests/test_ci_search_nonascii_panic.sh rc=1(284/294 · 남은 10 = 기준판 대조 블록) · 이슈: 0
