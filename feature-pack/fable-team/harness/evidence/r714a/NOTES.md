# r714a 증거 — 골 하루 두 번 재조정 «회차 수집기»

- 설계 = `design/harness/DESIGN-goal-daily-readjust-20261022.md` r3 §1~§9 + ★오빠 10-22 정정(슬랙 1792637646 «하루 두번인데 내가 요청할때. 안할때는 그냥 넘어감»)★
- 산출 = `kit/fable-team/bin/{ft-goal-readjust.sh, ft_goal_readjust.py, ft_goal_readjust_measure.py, ft_goal_readjust_state.py}` + `kit/fable-team/bin/ft_goal_table.py`(render 머리 1칸 + «재조정» 칸) + `harness/bin` 짝 사본 + `tests/test_goal_readjust_r714.sh`
- 시험 = `bash tests/test_goal_readjust_r714.sh` → **66 PASS · fail=0** (`test-goal-readjust-r714.txt` · DA⑥ r1 HOLD 14건 처방 뒤)
- 회귀 = `regression.txt` — r668·gitref r545·procs r644·stale r600·goal check ref·mbox guard 2종·launchd render·plist r544·news html 전부 rc=0 · `test_goal_table_gate.sh` 만 fail=1 인데 **base(origin/main 65738ffd) 에서도 같은 1건**(`ⓕ r458 600/300 상한 등장` · 기존 실패 · 이 카드 무관 · 양쪽 원문 = `base-gate-fail.txt`)

## 오빠 정정 반영(범위 축소)

| 정정 | 반영 |
|---|---|
| ① launchd 07:35·19:35 자동 시계 0 — 요청할 때만 (수동 진입점 1개 · 하루 최대 2회 · 요청 없는 날 건너뜀) | launchd 템플릿·`install.sh --launchd-new` **넣지 않았다**. 수동 진입점 = `ft-goal-readjust.sh` 하나. `run = <YYYYMMDD>-<k>`(k = 그날 몇 번째 요청, 최대 2) · 오늘 2회 뒤 요청 = `SKIP 상한` 1줄 + rc0(쪽지 0 · 파일 0). 시험 ⓤ·ⓤ2·ⓤ3·ⓤ4 |
| ② 여러 골 변경은 묶음 쪽지 1통 | 쪽지 = run 당 1통(모든 행·닫힘 후보·정본 밖 골 파일·경보를 본문 1통에 묶음). 시험 ⓕ·ⓖ |
| ③ 이슈 팀장 회신 = 기본값 그대로 | 손대지 않음(사람 회신 유지 · 자동 세기 0) |

## 설계 r3 과 다르게 간 곳(DA 확인 요청)

1. **run 이름** = `<YYYYMMDD>-<k>`(요청 순번) — r3 의 `am|pm`(07:35/19:35 슬롯)은 자동 시계 전제라 정정 ① 로 성립하지 않는다. 「하루 최대 2회」가 run 번호와 1:1 이 된다.
2. **파일 1개 추가** = `ft_goal_readjust_measure.py` — r3 §9 는 py 2개였지만 한 파일이 697줄(AGENTS.md 200줄 규칙)이라 «측정»과 «발행»을 갈랐다(동작 변화 0 · 순수 이동). 결과 276 + 450줄.
3. **선택 입력 꼴을 잠정 지정**(r693·r702·r664·r708 미착지) — `<state>/goal-evidence.json` `{"rows":{"<n>":"✅ 전부"}}` · `goal-row-swap.json` `{"stale_rows":[n…]}` · `goal-landed.json`/`goal-live.json` 은 «있나» 만 본다. 각 카드 착지 때 그 카드가 꼴을 확정하면 이 장치는 «있나/값» 만 읽으므로 그대로 맞는다(바꿀 자리 = `ft_goal_readjust_measure._evidence`·`_stale_rows`).
4. **상태 자리** = `<루트>/.fable-team/state/goal-readjust/` — 루트 = `FT_ROOT` › 그 안 `.fable-team/LIVE_ROOT` 1행(설계 «LIVE_ROOT 아래» 와 같은 자리 · 형제 표식 `state/goal-numbering.tsv` 와 같은 규칙).
5. **기존 시험 3개를 기계적으로 고쳤다**(설계가 의도적으로 바꾼 것만): `test_goal_table_gate.sh`(머리 exact-match → «· 재조정 …» 허용 · 모듈 사본 4개), `test_goal_table_gitref_r545.sh`(머리 exact-match 2곳), `test_goal_table_procs_r644.sh`(ⓗ1 «render 바이트 동일» → «재조정» 1칸을 걷어낸 뒤 바이트 동일).

## 쓰기 허용 목록(설계 §0)

`<루트>/.fable-team/state/goal-readjust/` 아래(회차 파일·보고서·영수증·log·잠금) + `git fetch`(refs/remotes·FETCH_HEAD·objects) 뿐.
시험 ⓓ3 = `git status --porcelain`·`refs/heads/*`·HEAD 전후 동일 · 변이 ⓢ① = 정본 작업 파일에 1줄 쓰는 변이를 넣으면 그 검사가 FAIL 한다.

## DA⑥ r1 HOLD 14건 처방표 (arch 122 · `evidence/r714a-da6/SUMMARY-r714a-da6.md` · 가지 a265a1e4 → main 65738ffd 병합 위 추가 커밋)

| 항 | 무엇이 틀렸나 | 처방(코드) | 시험 |
|---|---|---|---|
| H1 | 보고서 .md 를 JSON 보다 먼저 쓰고 attempt 는 JSON 개수로 셈 → 중단 뒤 재실행이 같은 .md 를 덮음 | attempt = `_attempts()`(.json **과** .md 둘 다) + 1 · `_write(..., fresh=True)` = 이미 있는 이름에 쓰면 ReadjustError(덮어쓰기 0) | ⓥ1 |
| H2 | `_need()` 가 «마지막 attempt» 만 봄 → claimed 무영수증이 다음 attempt 에서 사라짐 | `_unresolved()` = 영수증 없는 claimed 을 **모든** 회차에서 모아 경보에 이어 붙임 · `_need()` 도 prior 전수 검사 | ⓥ2 |
| H3 | 26시간 뒤 머리에서 마지막 성공 run 이 빠짐 | 머리 = `재조정 없음 N시간 · ok=<run> <HH:MM> · 최근=…`(둘 다) | ⓥ3 |
| H4 | «기준» 라벨이면 조기 반환해 «·정본 바뀜» 생략 | 기준 행도 `·정본 바뀜` 을 붙인다(카드 수·대응 모름만 기준에서 생략) | ⓥ4 |
| H5 | 하네스 리포를 최상위로 올리는데 팀 경로는 `$FT_HARNESS_ROOT/` 만 뗌 · 하네스 fetch 0 | `_harness()` 가 **prefix**(리포 루트 → FT_HARNESS_ROOT)를 돌려주고 `_team_repo` 가 붙임 · `_fetch()` 7초·재시도 1 | ⓥ5 |
| H6 | 파일 출처는 작업 파일 직접 읽음 · 기본 경로는 가변 ref 재읽기 | `_read_input()` = 파일 출처도 리포 안이면 `commit:경로` 판 · 기본 정본·원장 경로를 `gitref:<고정 commit>:` 으로 박음(`_pin`) | ⓥ6 |
| H7 | 손상 표식·빈 파일이 «모름» 을 지움 · r714c·r701 «미착지» 글자 없음 | `_stale_rows()` = 손상/키 없음 구분 · `_option()` = 없음/손상/빈 파일 · `facts.unknown` = `모름(r714c 미착지)`·`모름(r701 미착지)`(착지 = 고정 commit 트리 글자로 판정) | ⓥ7·ⓥ7b |
| H8 | 송신 실패·planner 자리 없음에도 «OK … rc0» · 렌더가 영수증을 안 읽음 | rc3 = 송신 failed/unknown · `_need()` = mbox/명부 없으면 `state=failed` · 상태 모듈이 영수증(.sent/.send-failed)을 읽어 머리에 `·송신 실패`/`·송신 모름` | ⓥ8·ⓥ8b·ⓥ8c·ⓗ·ⓗ2 |
| H9 | 컴파일된 정규식에 `re.split(flags=)` → ValueError · 측정 예외가 ERROR 회차로 안 감 | `COORD_SECTION.split(...)` · `collect()` 가 `except Exception` 도 ERROR 회차 파일로 | ⓥ9·ⓥ9b |
| H10 | 예산 검사가 측정 전 1번뿐 · 래퍼 문구가 사실과 다름 | 측정 모듈이 `_budget()` 을 단계마다(측정 중 포함) 검사 · 래퍼는 «70초 초과로 끊겼다 · 회차 파일이 없을 수 있다» 로 사실대로 + rc1 | ⓥ10 |
| H11 | 래퍼가 `python3` 로 import → 설치 사본 bin 아래 `__pycache__` | 래퍼 `python3 -B` + `PYTHONDONTWRITEBYTECODE=1` · 시험이 bin 파일 목록 전후 비교 | ⓥ11 |
| H12 | `--request` 필수 아님 · 3번째 요청이 «SKIP 상한 rc0» | `--request "<출처>"` 필수(없으면/빈 값 usage rc2) · 회차 파일 `request` 칸 · 3번째 = `REJECT 오늘 2회 다 씀` rc2(파일 0 · 쪽지 0) | ⓥ12·ⓤ3·ⓤ5·ⓤ6 |
| H13 | 무효 LIVE_ROOT 를 조용히 FT_ROOT 로 대체 · 명부·mbox 를 LIVE_ROOT 에서 찾음 | `_root_check()` = 무효면 StatePathError → 회차 수집기는 ERROR rc1 · 렌더는 «재조정 기록 없음»(죽지 않음) · 명부·mbox = 공용 루트 규칙(FT_ROOT › git 공용 루트) | ⓥ13·ⓥ13b |
| H14 | 변이 2개가 원본에서도 통과 · 첫 공지 칸이 «표식 있음·6행» | ⓢ② = 원본 2파일/변의 1파일(덮어쓰기 금지로 갈림) · ⓢ④ = 원본은 «모름(판 다름)», 변이는 없음 · ⓣ = **표식 없음·5행** 정본 | ⓢ②·ⓢ④·ⓣ |

★rc 규약★ = 0 OK · 1 ERROR 회차 · 2 usage/REJECT(--request 없음 · 하루 상한 초과) · 3 회차는 끝났으나 송신 실패/모름.
★r3 과 다른 곳★ = 그대로 3가지(위 «r3 과 다르게 간 곳») + 이번에 `facts.unknown`(넘긴 3개 «모름» 글자 자리) 1칸 추가.

## press 필요

`press 필요: 라이브 설치(설치 cmp0) 뒤 오빠 요청 1~2회 → 회차 파일 2개 원문 + ft-goal-table.sh render 원문 + 회차 전/후 골 표 대상 행 본문 diff ≥1` — 나노는 press 를 쏘지 않는다(ft-press-gate ⑦).

## DA⑥ r2 HOLD «작은 고침 5개» 처방 (2회째 · 묶음 보고 `evidence/r714a-da6/PACKET-r714a-after-2hold.md` «남은 것» 1~5)

DA⑥ r2 판정: 닫힘 H1·H2(보존)·H3·H4·H5·H6(고정 commit)·H8(초회)·H9·H11·H12·H14 · 안 닫힘 H7·H10·H13 · 새 회귀 2(H2 이월 경보 순서 · H6 상대 경로).

| 항 | 무엇이 틀렸나 | 처방(코드) | 시험 |
|---|---|---|---|
| H7 | 손상·빈 표식의 «모름» 글자에 `r702` 가 없어 렌더가 «·대응 모름» 을 못 봄 | `ft_goal_readjust_state.row_cell` 판별 = `startswith("대응 유지 모름")` 접두(글자에 `r702` 없는 손상 표식도 같은 «모름») | ⓦ1 |
| H10 | `_budget()` 이 3곳뿐(측정 시작·BYZ 뒤·행 수집 뒤) · `_git()` 이 남은 예산을 안 받아 **호출당 7초 미만인 느린 git 이 합계로 70초를 넘기면 래퍼가 kill** → ERROR 회차 파일조차 못 남김 | `_budget_sec()`·`_remaining()` 추가 · `_git()`/`_git_ok()` timeout = `min(7, 남은 예산)`(남으면 «시간 초과» ReadjustError) · 카드 반복·행 반복 «안»에서 `_budget()`(마지막 사실 수집 전 검사는 그대로) | ⓦ2 |
| H13 | LIVE_ROOT «빈 값»은 FT_ROOT 로 조용히 대체 · «상대경로(.)» 허용 | `_root_check()` = 파일이 **있는데** 빈 값 → `LIVE_ROOT 값 비었음` · 상대경로 → `LIVE_ROOT 무효(상대경로 …)` · 실재 안 함 → 무효(그대로) — 셋 다 수집기는 ERROR rc1, 렌더는 «재조정 기록 없음» rc0. 파일 자체가 없으면 FT_ROOT(옛 설치본) | ⓦ3·ⓦ3b·ⓦ4 (+기존 ⓥ13) |
| 회귀 H6 | `FT_LEDGER_PATH` 상대 경로를 **cwd 기준**으로 해석 → 리포 밖 cwd 에서 «입력이 리포 밖» ERROR (옛 `ft_goal_ledger.ledger_spec` 은 리포 기준) | `_ledger_env(repo)` = 상대 경로를 `repo / 경로` 로 (절대 경로·`FT_GOAL_A6_LEDGER` 는 그대로) | ⓦ5 |
| 회귀 H2 | 이월 «송신 모름» 경보를 `_need()` **뒤**에 붙여 → 후보가 해소된 다음 날 회차는 `쪽지 0 · rc0 · 머리 표시 0`(경보가 조용히 묻힘) | 이월 경보(`_unresolved`)를 `_need()` **앞**으로 올려 `rec["alarms"]` 에 먼저 넣는다 → «알릴 사실 없음» 판정에 걸리지 않고 쪽지 1통·머리 표시 | ⓦ6 |

★빨강/초록 대조(요구값)★ = 새 7칸 전부 **r2 판(b8b15c86ff)에서 FAIL · 이번 판에서 PASS** — 원문 `r2-red.txt`(r2 판 실행 = `fail=7`, 나머지 66칸은 PASS 그대로) ↔ `test-goal-readjust-r714.txt`(`fail=0` · 73 PASS).
