# r456 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r456-landed-card-close-path-da-hold-gate` push → PR (나노 push 금지) → 병합 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `fec5d3b3`(origin/main · PR #83 착지 뒤). 변경 = 키트 3(`ft_da_hold_gate.py` · `ft-index-move.sh` · 새 `ft-index-close-landed.sh`) bin·kit 짝 cmp0 + 시험 1 새(`tests/test_da_hold_gate_landed.sh`) + 기존 시험 1줄 기대 문구(`test_da_hold_gate.sh` §7 «REJECT DA 보류 가드: HOLD events=2») + 이 증거 폴더.
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(r410 규약) — 착지 순서대로 master 가 번호를 붙인다. 문안 = 아래 «CHANGES 절».
2. 되돌림 준비(설치 전): LIVE_BIN `ft_da_hold_gate.py`·`ft-index-move.sh` `cp -p … .bak-r456` (새 도구는 제거로 되돌림).
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → `cmp <키트>/bin/<3파일> <LIVE_BIN>/<3파일>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
4. 실사건(닫는 증거): feature 문서 줄기 워크트리(지금 `.worktrees/feature-docs-land`)에서
   `bash .fable-team/bin/ft-index-close-landed.sh design/teams/feature/DA-CLOSE-progress-batch-20261019.md --team feature` 1회
   → 결과 표(`MOVED N · REJECT 원문 M · SKIP K` + `TOTAL …` 줄)를 feature master 에 relay · 카드 `- 실사건:` 줄.
   사전 관측(나노 · `--dry-run` 쓰기 0 · `feature-dry-run.txt`): 판정문 «main» 행 26 = 진행/ 9장 예상 `LANDED-CLOSE`(UNPARSED 8 + events=4 F-1458-note-growth 1) · 완성/ 17 = SKIP.
   진행/ 15장 중 나머지 6장은 이 도구 대상 밖: ①F-concierge-a2z-fill·F-hybrid-rag-design-stage2 = 판정문 행이 «feature-main `<sha>`»(main 착지 아님 · 판정기 UNPARSED 그대로 — 옛 표기 교정 또는 feature 팀 판단) ②F-1509·리서치 가격표 3장 = 보류 가드는 이미 통과(events=0) — 거절 원인은 다른 게이트(arch 100 Issue ③).
   ★dry-run 의 «예상» 은 보류 가드 칸만이다 — 실행 때 정본·규칙 줄·설치 게이트가 카드별로 따로 거절할 수 있다(REJECT 원문 그대로 표에 남는다).★
5. BOOT 40 끝 1줄(착지 뒤 · arch 손 · 카드 §정본): «착지 카드(main 조상 sha + DA 닫힘 판정문 행)는 `ft-index-close-landed.sh` 로 닫는다 — 재설계 해제 쪽지 불요(r456)».

## CHANGES 절 (착지 번호를 붙여 머리에)
## 2026-10-19 — 이미 main 에 착지한 카드는 «착지 증거» 로 완성 이동한다: 보류 가드 `--closing` 세 번째 증거 종류 + 이동 거절 문구 = 판정기 첫 줄 + 판정문 1장 일괄 닫기 `ft-index-close-landed.sh` (1.1.N)

카드 r456 · master 112100 · feature master 31 요청 112092 · 판정 2349. feature 진행/ 15장이 main 착지 뒤에도 닫히지 못했습니다 — 10장은 옛 표기(`DA r1 HOLD`)라 판정기가 UNPARSED rc3 인데 `ft-index-move` 가 rc≠0 을 전부 «REJECT DA 보류 2회 — 재설계 해제 …» 고정 문구로 찍어 보류 가드로 오독됐고, 재설계 해제 쪽지는 `DESIGN r<N>` 필수라 착지 카드엔 «숫자 지어 쓰기» 외 길이 없었습니다.

- **`ft_da_hold_gate.py`**(bin·kit 짝 cmp0): 인자 `--landed <sha>`·`--da <판정문#§N>`. `--closing` 에서만 ①카드 «## 상태» `- 착지: <sha>`(또는 `--landed` · 둘 다면 일치) ②`merge-base --is-ancestor <sha> origin/main` rc0 ③판정문 §N 절에 «닫힘 — <카드 stem> — main `<같은 sha>`» 행 — 셋 다 참이면 첫 줄 `LANDED-CLOSE sha=<sha> da=<…>` rc0. 하나라도 빠지면 기존 판정 불변 + `LANDED-INVALID <unknown-sha|mismatch|not-ancestor|no-da|da-missing|no-da-row>` 줄. `--entry`·`--lint` 변경 0(DA 발주 입장 우회 0).
- **`ft-index-move.sh`**: 보류 가드 호출에 `--da`·`--landed` 전달 · 거절 문구 = `REJECT DA 보류 가드: <판정기 첫 줄> — 해제 = <옛 표기 교정 | 재설계 해제 쪽지> 또는 착지 증거(…)`. `--landed` 착지 줄은 같은 줄이 이미 있으면 다시 쓰지 않는다.
- **새 `ft-index-close-landed.sh <판정문> [--team <팀>] [--dry-run]`**: 판정문 행 전수 → 팀 폴더(`ft_team_root`) 대기/·진행/ 카드 → 조상 검사 → 착지 줄 없으면 «## 상태» 끝 1줄 → `ft-index-move … 완성 --da <판정문>#§N --landed <sha>` · 결과 1줄/카드(MOVED · REJECT 원문 · SKIP 카드 없음|이미 완성) + `TOTAL` 줄. `--dry-run` = 표만(쓰기 0). 조상 아닌 sha·카드 없는 행은 쓰기 0.
- **시험**: 새 `test_da_hold_gate_landed.sh` 32 PASS rc0(ⓐ~ⓕ). 기존 `test_index_move_canon_landed`·`_canonize`·`_rule_line`·`_slack` rc0. `test_da_hold_gate.sh` 96 PASS · FAIL 2 = §8c staged-r387 사본 ↔ 홈 BOOT·governance 비교(origin/main fec5d3b3 export 에서도 같은 FAIL 2 — 이 단위 변경 무관 · 아래 «범위 밖»).
- **범위 밖(새 카드 후보)**: `test_da_hold_gate.sh` §8c — 홈 `COMM-GUIDE-BOOT.md`·`main-team-governance.md` 가 staged-r387 사본 뒤로 바뀌어 «홈 대비 삭제 4·3 줄»(판정 1395: 고침 단위 필요) · 옛 표기 카드 손 정규화 · r435(거절 모아 보고).

## 관측
- 고치기 전(origin/main 라이브 1.1.16 · arch 100 실측): UNPARSED 10 · HOLD events=4 1 → `ft-index-move` 출력 «REJECT DA 보류 2회 — …»(feature 원문 112092).
- 고친 뒤: 시험 원문 `test.txt` · 실카드 dry-run `feature-dry-run.txt`(진행/ 9장 `LANDED-CLOSE` · feature-docs-land 쓰기 0 확인).
- 실카드 판정기 단독(착지 증거 없이 `--closing`): UNPARSED 10 · HOLD events=4 1 · events=0 4 — arch 100 분포 10/1/4 와 같음.
