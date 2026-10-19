# Changes

## 2026-10-19 — 틱 데몬 자리 규칙 3줄(코드 = LIVE_BIN · 데이터 = 공용 루트 · 정본 = ref origin/main): comm 을 공용 루트로 · shim 폴더 옛 사본 자가 검사 · 골·뉴스 틱 정본 ref 읽기 · 설치기 comm 동기화 + RESTART 줄 (r459 · 1.1.30)

카드 r459 · master 112539·112636 · arch 101 실측 · 골 6(메인 골 1 팀장 v65 master 가 틱 없이 36시간). 메인 틱이 10-18 09:53 부터 `skip … 에이전트 판정 불가(<v6>/.fable-team/comm/ft-agent-alive.sh 실행 실패)` 839회 — `ft_comm_dir` 가 데이터 루트 = LIVE_ROOT(옛 라이브 워크트리 v6-realtime-live)의 comm 으로 풀렸는데 거기엔 판정기가 없었습니다(진짜 우편함·판정기 = 공용 루트 comm). 10-19 09:04 shim 교체 뒤엔 «먼저 기동한» 틱 6개가 메모리의 옛 사본으로 shim 폴더의 `.py` 를 python3 로 읽어 SyntaxError 를 반복했고, goal-tick 은 글자 ROOT(v6)·뉴스 틱은 체크아웃 명단으로 v65 폴더를 못 풀어 ERROR(112632).

- **ft-harness-root.sh** `ft_comm_dir`: ①env `FT_MBOX_DIR`(comm 폴더 그 자체) ②env `FT_ROOT` ③`*/.fable-team/bin` 이면 `git -C` 공용 루트 ④cwd 공용 루트 — LIVE_ROOT 분기 제거 · comm 없음 = ERROR 그대로. `ft_data_root` 는 state 용 그대로(주석 «comm 은 쓰지 않는다»).
- **ft-tick.sh · ft-tick-team.sh**: 기동 1회 자가 검사 — 형제 `ft_raised.py` 첫 3줄에 `ft-root-bin-shim` 마커가 있으면 `ERROR shim 폴더에서 실행 — launchctl kickstart 로 LIVE_BIN 재기동` exit 3(옛 통째 사본이 조용히 돌지 못한다). MBOX·AGENT_ALIVE 기본 = 공용 루트 comm(ft_comm_dir).
- **ft-team-lib.sh** `ft_team_doc_ref <루트> <팀> <파일> [<ref>]`: 명단 = ref(origin/main) · 후보 폴더 중 실재 정확히 1개면 그 경로 · 0 이면 `git show <ref>:<명단 꼴 폴더>/<파일>` 본문을 임시 파일로(정리 = 부르는 쪽 · `ft_team_doc_tmp`) · 2+·ref 못 읽음·ref 에도 없음 = ERROR rc1. 읽기 전용(원장처럼 쓰는 파일은 `ft_team_file_ref`).
- **ft-goal-tick.sh**: 글자 ROOT 제거 → ROOT = `ft_repo_root`(env `FT_GOAL_TICK_ROOT` 시험용 유지) · 틱 프롬프트 = `ft_team_doc_ref` + trap 정리. **ft-news-tick.sh**: 글자 ROOT 제거(env `FT_NEWS_ROOT` → `ft_repo_root`) · NEWS-TREE.md = `ft_team_doc_ref`(`FT_NEWS_TREE` 우선 그대로). **ft-nano-close.sh**: 원장 0·2+ REJECT 문구를 헬퍼 ERROR 꼴(«실재 후보 N개 — 정확히 1개여야 한다(명단 … · 후보 …)») 하나로.
- **ft-tick-install.sh · ft-tick.plist**: 메인 plist `WorkingDirectory` = git 공용 루트 + env `FT_TICK_MBOX`·`FT_MBOX_DIR`·`FT_TICK_AGENT_ALIVE`(공용 루트 comm · `__COMM__`) — 팀 plist 와 같은 틀 · 공용 루트 comm 없음 = REJECT · dry-run + `FT_TICK_PRINT_PLIST=1` = 렌더본 출력.
- **install.sh**: ⓐ `comm_sync` — 팩 `harness/comm` 최상위 일반 파일(제외 = `mailbox*.jsonl`·`.mbox-seq`·`.mbox-guard.json`·`queues.conf`·`*.pyc` · 폴더 `bodies/`·`relay/` 는 대상 밖)을 `<공용 루트>/.fable-team/comm/` 에 cp -p · 덮기 전 `.bak-<버전>`(첫 원본 보존) · 삭제 0 · dry-run = `COMM <dst> <- <src>` 줄 + `COMM copied=N same=M` · 워크트리 `--project` = `SKIP comm`. ⓑ apply 끝 `ft_live_install_check.py --restart-scan` — 판정식 `restart_due`(R245 plist_items 에서 뽑은 함수 하나)로 «기동 < 스크립트(shim 이면 LIVE_BIN 지도·라이브 도구까지) mtime» 인 적재 데몬마다 `RESTART <label> — launchctl kickstart -k gui/<uid>/<label>` 줄(실행 0 · master 집행).
- **시험**: `test_harness_root.sh` r459 ⓐ~ⓔ 추가 · 새 `test_tick_shim_guard.sh` ⓐ~ⓒ · `test_nano_close_fail_closed.sh` ⓑⓒ 문구 갱신. 실 머신 읽기만: `install.sh --dry-run --project <BYZ 루트>` rc0 · `COMM copied=24 same=8`(루트 mbox.sh·ft_seat_bind.py 는 팩보다 뒤 — r408 미설치) · `--restart-scan` = 팀 틱 4 + 슬랙 수신 2 RESTART. 증거 `harness/evidence/r459/`.
- 범위 밖: state 폴더 통합(v6 ↔ 루트) · r458(뉴스 폴더 = 원장 리포 TEAMS.md · 뉴스 틱의 `WT=<루트>/.worktrees/v6-realtime-live` 도구 경로) · 루트 체크아웃 당기기.

## 2026-10-19 — 원장 뉴스가 «원장 정본 한 곳»(FT_LEDGER_REPO + 경로)에서만 sha·경로·뉴스 폴더를 푼다 + 뉴스·매거진 골 표 뒤 «팀별 완성 진행» 블록 (r458 · 1.1.29)

카드 r458 · master 112887·112904·112907·113018 · arch 101 실측. 10-18 08:43 뒤 뉴스 발행 0: 원장 경로는 원장 리포(LIVE_ROOT) 명단으로, 뉴스 폴더는 공용 루트(로컬 main 2만 커밋 뒤 · TEAMS.md 없음) 명단으로 풀어 `ERROR 팀 명단 없음` 2671회. 임시 처방(h182 · 원장 리포를 c-level-planning 으로) 뒤엔 `git show 실패: path design/teams/planner/… not in c7b4a5db8b` — 기준선(last.sha)은 옛 경로 리포 판, 경로는 새 경로라 «출처 2개».

- **출처 1개**: 뉴스 폴더 = `<루트>/<원장 경로의 폴더>/news`(원장 경로 = FT_LEDGER_PATH › 원장 리포 TEAMS.md 의 planner 폴더) · 폴더 없음 = `ERROR 뉴스 폴더 없음 <경로>`(폴백 0) · FT_NEWS_DIR 우선 그대로. 골 표·팀별 진행이 읽는 원장도 같은 값(FT_GOAL_A6_LEDGER › FT_LEDGER_REPO+FT_LEDGER_PATH › 원장 리포 planner 폴더).
- **기준선 판 검사**: 기준선 sha 판에 «같은 리포·같은 경로» 원장이 없으면 `기준선 <sha10> 판에 원장 정본 <경로> 이 없다 … 옛 경로 후퇴 0` ERROR(발행 0) — 옛 경로(design/planner/)·쌍둥이 경로로 읽지 않는다(#0 RULE · master 113018). 복구 = 원장을 정본 경로로 커밋 → 기준선을 그 판으로.
- **팀별 완성 진행**: `ft-goal-table.sh teams` = 원장 `## 팀별 완성 진행` 첫 표(팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것) → 마커 `★팀별 완성 진행 (<원장 sha10>)★ … ★/팀별 완성 진행★`(≤1600B · «지금» 칸 24→16→8자). 표 없음·예산 초과·도구 실패 = 빈 글 + WARN — ★새 거절 게이트 0★(골 표 check 불변). 뉴스 첫 판 = 머리 → 골 표 → 팀별 진행 → lead(3500B 계산 포함 · 이어진 판엔 없음) · 매거진 뿌리 글·HTML 절 골 표 바로 뒤.
- **시험** `tests/test_goal_table_gate.sh` r458 16 PASS(ⓐ 루트 명단 없음 → 원장 리포 명단 · 폴더 없음 ERROR ⓑ FT_NEWS_DIR 우선 ⓒ teams 블록·표 없음 WARN rc0·check 불변 ⓓ 첫 판 순서·3500B·이어진 판 0 ⓔ 매거진 뿌리 글·HTML·무장이어도 거절 0 ⓕ 옛 경로 기준선·다른 리포 sha = 명확한 ERROR · 정본 판끼리 발행 · FT_LEDGER_PATH 한 값) · 전체 fail=0. RED: origin/main 판 10 FAIL · `check_base` 만 빼면 ⓕ 2 FAIL(실 오류 `exists on disk, but not in` 그대로 재현). ⓚ 픽스처 `tests/fixtures/goal_table/AUTONOMY-GOAL-A6-20261018.md` 가 팩에 없어 기존부터 FAIL → BYZ origin/main 판 복사.
- **범위 밖**: 원장을 새 경로 판으로 옮기기(planner 몫 · master 요청) · 공용 루트 main 당기기 · 세션 상태 스냅샷 낡음(ERROR 로그 · 발행은 막지 않음) · 팀 틱 «지금 하는 것» 자동 수집.

## 2026-10-19 — 자율 ON 병합 훅이 «오빠 승인 sha 위에 main 병합만 더한 head»(같은 변경 집합)를 재승인 없이 통과시킨다 (r462 · 1.1.28)

카드 r462 · ops master 33 [HIL] 112442 → planner 112456 → master 78 발주 112459. 훅 `autonomy-merge-guard.sh` 는 승인 파일 이름 == `--match-head-commit` sha 글자 일치만 봐서, 착지 직전 표준인 main 병합으로 head 가 바뀌면 «승인한 변경 집합은 그대로» 인데도 매번 오빠 재승인을 요구했습니다(ops PR 1960 왕복).

- **판정기 = 이미 있는 것 하나**: `ft_approval_equiv.py`(R247 ft-merge-land · r411 scope-approve CODE_EQUIV 가 쓰는 같은 판정기). 카드 처방의 새 `autonomy_equiv.py` 는 만들지 않았다 — 같은 판정식이 이미 함수(파일)로 빠져 있어 새 파일 = 중복.
- **훅**: 글자 일치 실패 시 승인 폴더의 sha 들(파일 1줄 == autonomy.log 줄 검사를 먼저 통과한 것만 · 최신순 · 7초 × 3 마감) 중 판정기 `EQUIV` rc0 인 것이 있으면 통과 + 훅 로그 `EQUIV <승인> -> <head>`. 없으면 기존 deny 사유 + `재승인 필요 — 승인 sha 와 같은 변경 집합 아님: <판정기 사유 원문>`(판정기를 못 돌렸으면 EQUIV 안내 1줄). 판정기 없음·rc3·시간 초과 = 통과 0(판정 1675 «병합 = 오빠 값» 불변).
- **`ft-autonomy.sh approve-merge`**: stdout `APPROVED …` 줄은 그대로, stderr 에 `EQUIV 허용 범위: …` 1줄(200줄 한도 안 · bin·kit cmp0). 기존 시험 2곳(`test_autonomy_kinds_1675` ⓑ OFF · `test_merge_land_off_approval` ④)의 `2>&1` 글자 일치 단언을 «첫 줄 == APPROVED …» 로 바꿈(1675 쪽은 EQUIV 줄 존재도 단언).
- **ops 실사건 실측**(BYZ 리포): 승인 45cd3c302b 는 head 6f66271305 의 조상이 «아니다»(가지를 89c8e21f13 로 다시 만든 뒤 main 병합) — 카드 Issue ③ «45cd 위» 와 다름. 그래도 판정기 rebase 모드 조건(main 6d4ccce32c ⊂ head · 자기 변경 diff 동일 · `merge-tree(45cd, 6d4c)` = head 트리 8b87f3a161)이 그 당시 main 기준으로 전부 참 → 이 훅이면 EQUIV 통과였다. 지금은 main 이 더 나가 같은 head 는 NOT-EQUIV(«PR head 도 지금 main 위가 아님») — main 을 한 번 더 병합하면 다시 EQUIV.
- **시험** `tests/test_autonomy_merge_equiv.sh`(새 · 13 PASS): ⓐ A 위 main 병합 → 통과 + 로그 ⓑ +가지 새 커밋 → deny(«일반 커밋 1») ⓒ A 를 조상으로 안 둔 다른 변경 → deny ⓓ H == A → 통과 · EQUIV 로그 0 ⓔ 승인 파일만(log 줄 없음) → H·A 둘 다 deny + 판정기 없음 → H deny · A 통과 + approve-merge stdout 불변·stderr 1줄. 고치기 전 훅(origin/main)으로 같은 시험 = fail 4(ⓐ·ⓑ·ⓒ·ⓓ로그).
- **범위 밖**: 자율 OFF 경로 · scope-approve code-max · PR 1960 착지 · 판정기 rebase 모드의 «지금 main ⊂ head» 조건 완화(ft-merge-land 와 공유라 따로).

## 2026-10-19 — 설치기 plist 교체가 «절반 상태» 로 멈추지 않는다 — bootstrap 재시도 · 실패면 직전 plist 원복 · LIVE_BIN 전환 뒤로 (r464 · 1.1.27)

카드 r464 · master 112557 카드A · 1.1.25 설치 실사고(1.1.25 폴더만 생기고 LIVE_BIN 1.1.24 · 슬랙 미러 bootout 된 채 · master 손 bootstrap pid 89173). `bootout` 은 launchd 가 프로세스 종료를 기다리는 비동기 동작이라 바로 `bootstrap` 하면 실패할 수 있고, 설치기는 그 실패를 `exit 1` 로 받아 «plist 는 새 것 · 미러는 내려감 · LIVE_BIN 은 옛 것» 을 남겼다 — 되돌림은 안내 글자뿐이었다.

- **교체**: 덮기 전 직전 사본 `<plist>.bak-<version>`(매 교체 · `.bak-r426` 첫 원본은 그대로) → bootout → bootstrap 1초 간격 최대 3회(7초 안) → kickstart → `PLIST applied <label> (retry=<n> · 되돌림 = <plist>.bak-<version> · kickstart)`.
- **실패**: bootstrap 3회 또는 kickstart 실패 → 직전 사본 원복 + bootstrap(같은 재시도) → `PLIST RESTORED <label> — 새 렌더본 적용 실패(<launchctl 출력 1줄>)` · 원복본 bootstrap 도 실패면 `ERROR: plist 원복본 bootstrap 도 실패 … 손 복구 = launchctl bootstrap gui/<uid> '<plist>'`.
- **순서**: plist 단계는 LIVE_BIN 전환·githooks «뒤». 실패해도 코드 전환은 끝나 있고 마지막 줄 `INSTALLED <version> · PLIST ERROR …` + rc1. 성공은 `INSTALLED <version> · PLIST ok`. dry-run 출력 불변.
- **시험** `tests/test_live_install_check_plist_env.sh` r464ⓐ~ⓔ 7줄 추가(39 PASS): ⓐ 1회 실패 뒤 retry=1 ⓑ 3회 실패 → 원복 cmp0 · RESTORED · rc1 · LIVE_BIN 새 버전 · `.bak-r426` 보존 ⓑ' 원복도 실패 → ERROR ⓒ 같음 → launchctl 0 ⓓ 되돌림 기준 = 직전 사본 ⓔ 재시도 ≤7초. 가짜 launchctl 스위치 `FT_FAKE_BOOTSTRAP_FAIL=<n>`. RED = 옛 설치기 위 5 FAIL.
- **범위 밖**: plist 템플릿 내용 · r457 공용 루트 분기.

## 2026-10-19 — 병합 줄 대조(`ft_merge_lines.py`)가 «다른 폴더로 옮긴 파일» 을 옮긴 곳에서 센다 — D 인데 같은 이름 1개면 이동 · 옛 경로 글자 1쌍 치환 (r461 · 1.1.26)

카드 r461 · master 112578·112657 · loom master 36 결정 요청 112574. 보호 집합의 키가 «파일 경로» 라서, 작은 카드를 다른 폴더로 옮기며 경로 글자 줄을 바꾸면 `diff -M` 유사도가 50% 밑으로 떨어져 «D(삭제) + A(새 파일)» 로 갈라지고 «S 가 삭제» 로 거절됐다. git 이 R 로 잡아도 main 이 더한 «옛 경로 글자 줄» 이 새 경로 글자로 바뀌면 «사라짐» 이었다.

- **규칙**(소실 판정 «전»): ①D 면 S 트리(`ls-tree -r`)에서 같은 basename 을 찾아 **정확히 1개**일 때만 그 파일을 옮긴 곳으로 본다 — 0개 = 기존 «S 가 삭제» · 2개 이상 = `S 가 삭제 · 같은 이름 후보 N개(추측 0)` ②옮긴 파일(R 또는 ①)은 main 줄마다 «그대로» 와 «옛 경로 → 새 경로 1쌍 치환» 중 많은 쪽으로 센다 ③포함 안 되면 `<새 경로> 로 이동했으나 main 이 더한 줄 N 개 없음` ④바이너리 D·R 은 기존 거절 그대로 · 같은 경로 줄 소실은 기존 «사라짐» 그대로.
- PASS 줄 = `PASS 보호 집합 N 파일 · F=… · 이동 인정 K; MOVED a -> b …(3개 + 외 N)`(한 줄 · ft-merge-gate 가 `ALLOW … · $OUT` 로 싣는다). DENY 첫 단어 불변.
- **시험** `tests/test_merge_lines_moved.sh`(새 · 13 PASS): 전제 2(ⓐ 가 실제 D+A · ⓕ2 가 실제 R) · ⓐ 3장·48장 이동 PASS · ⓑ 진짜 삭제 · ⓒ 이동+줄 2개 소실 · ⓓ 같은 이름 2개 · ⓔ 바이너리 이동 = DENY · ⓕ 큰 카드 R(같은 내용·경로 줄 치환) PASS · 같은 경로 줄 소실 «사라짐» 그대로. RED = `FT_MERGE_LINES=<옛 판>` 으로 6 FAIL(ⓐ·ⓐ48·ⓒ·ⓓ·ⓕ·ⓕ2).
- **실사건 실측(loom PR 1959 head 39a6d47bc0 · M=30cef9026e = 17:53 거절 당시 origin/main · 읽기만)**: 옛 판 DENY 15건(R 13 + D 2) → 새 판 DENY 14건. 살린 것 1(`대기/loom-789-u2b…` D → `완성/` 같은 내용). ★남은 14건은 경로 글자가 아니라 카드 본문 줄(base_sha·선행·상태·시험 줄)이 main 판과 다르다★ — main 이 F 이후 고친 카드 내용을 S 의 옮긴 카드가 안 가졌다(loom ⓐ «origin/main 판 복원» 이 같은 경로 파일만 덮어서 옮긴 카드는 빠짐). 이건 이동 규칙이 덮을 일이 아니라 진짜 «main 이 더한 줄 소실» 이다 → loom 쪽 처리 필요(아래 master-steps).
- **범위 밖**: `-M` 유사도 인자 · ft-merge-gate 다른 검사 · 병합 훅(r462).

## 2026-10-19 — `pipefail` 아래 `… | grep -q` 가 64 KB 넘는 입력에서 SIGPIPE(141)로 «찾았는데 실패» — 목록은 변수로 받은 뒤 here-string 으로 grep (1.1.25)

카드 r453 · master 111789·112300 · arch#99 실측(BYZ 루트 워크트리 308개 · porcelain 59,129 B · `ft-nano-close.sh --plan-only` 가 등록 워크트리를 «아니다» 로 REJECT → 판정 2367 정리 2곳 막힘). grep 이 찾고 먼저 닫으면 왼쪽(git·printf)이 아직 쓰는 중이라 SIGPIPE 를 받고 `pipefail` 이 141 을 파이프 결과로 올린다. 입력이 파이프 버퍼(실측 60 KB rc0 · 66 KB rc141)를 넘을 때만 나서 워크트리가 적을 땐 시험이 못 잡았다.

- **처방 편차**: 카드 처방 `printf '%s\n' "$_wl" | grep -qxF` 도 같은 141 이다(실측 300 KB · 3/3 rc141 · 시험 ⓐ 에 단언) — `printf` 도 파이프 왼쪽에서 쓰다가 SIGPIPE 를 받는다. 그래서 `grep … <<<"$변수"`(here-string · 파이프 0). 캡처 실패 = 빈 목록 = 기존 REJECT 그대로(fail-closed · 판정 기준 불변).
- **전수 린트**(키트 bin · `set -o pipefail` 파일 안 `| grep -q` · bin·kit 짝 cmp0):

| 파일:줄 | 왼쪽 입력 | 141 이면 | 처치 |
|---|---|---|---|
| `ft-nano-close.sh:376` `--plan-only` | `git worktree list --porcelain` | 등록 워크트리 REJECT(오판) | 고침 — `_wl` 캡처 + here-string |
| `ft-nano-close.sh:398` `--shared-wt` ⓑ | `git worktree list --porcelain` | ⓑ bad «등록 아님»(오판) | 고침 — here-string |
| `ft-nano-close.sh:410` `--wt` ⓐ | `printf "$_porc"`(같은 목록) | ⓐ bad «등록 아님»(오판) | 고침 — here-string |
| `ft-landed-check.sh:14` | `printf "$ch"`(`git cherry` · 가지 커밋 수에 비례) | `!` 로 뒤집혀 **미착지가 cherry(착지)** 로 읽힘 — fail-open | 고침 |
| `ft-index-move-canon.sh:107` | `printf "$CHANGED"`(`git diff --name-only` 범위) | 정본 있는데 «없음» REJECT | 고침 |
| `ft-scratch-repo.sh:65` | `printf "$cwds"`(`lsof` 전 프로세스 cwd · 실측 25,950 B) | **쓰는 중인 tmp 를 삭제 후보로** 올림 — fail-open | 고침 |
| `ft-launchd-check.sh:27` | `launchctl print-disabled`(실측 1,762 B) | — | 유지(작음) |
| `ft-resource-reclaim.sh:35-36` | 인자 문자열 `ONREJ` | — | 유지(인자 크기) |
| `ft-scratch-repo.sh:60` | tmux 세션 이름(실측 1,479 B) | — | 유지(작음) |
| `ft-wt-sweep.sh:189` | `.deleting` 표식 첫 줄들 | — | 유지(작음) |
| `ft-nano-close.sh:330` | `printf "$tmux_out" \| awk …exit` | rc 미사용(값만 씀) | 유지(무해) |

- **시험** `tests/test_nano_close_worktree_list_pipe.sh`(새 · 18 PASS): 임시 리포 + 긴 이름 등록 워크트리 452개(porcelain 162,697 B) · ⓐ 옛 꼴 git 파이프·printf 파이프 rc141 · here-string rc0 ⓑ `--plan-only` 목록 앞(v65-aaa)·맨 뒤(v65-zzz) → `PLANNED` ⓒ 미등록 → 기존 REJECT · 계획 0 ⓓ `--shared-wt` 등록 공유 워크트리(목록 앞) → ⓑ 오판 0 · 미등록 cwd → ⓑ bad 1줄. 고치기 전 `ft-nano-close.sh`(origin/main) 로 같은 시험 = FAILED 3(ⓑ v65-aaa REJECT · ⓓ 오판) — 맨 뒤 v65-zzz 는 옛 판도 통과(결함은 «앞쪽에서 찾을 때만»).
- **범위 밖**: 워크트리 수 줄이기(r444 sweep · 판정 1920) · `pipefail` 끄기. 라이브 BYZ porcelain 은 지금 62,091 B(경계 바로 아래 — 다시 넘으면 옛 판은 재발).

## 2026-10-19 — 설치기가 launchd plist(쪽지→슬랙 미러)를 git 공용 루트 설치에서만 갱신한다: 워크트리 `--project` 는 `SKIP plist-env` (r457)

카드 r457 · master 112171 · arch#100 실측. r426 의 plist 갱신이 `--project` 글자를 그대로 FT_ROOT·`--mailbox` 로 렌더해, r413 STALE-COPY 안내대로 워크트리(`.worktrees/v6-realtime-live`)를 `--project` 로 설치하자 미러 plist 가 우편함 없는 워크트리 경로로 교체됐습니다(1.1.24 설치 실사고 · master 복원). 설치기의 «프로젝트» 가 두 뜻(shim 을 둘 폴더 = 워크트리 가능 · launchd 가 볼 루트 = 공용 루트만)이었습니다.

- **install.sh**: `PROJECT` 확정 직후 `git rev-parse --path-format=absolute --git-common-dir` 로 공용 루트(`pwd -P` 정규화). `plist_sync` 첫 줄 — `--project` ≠ 공용 루트면 `SKIP plist-env <라벨> (--project 가 git 공용 루트 아님: 루트=<경로> — plist 는 루트 설치에서만)` 1줄 · 렌더·교체·launchctl 0(dry-run 같음). shim·훅·githooks 설치는 그대로. git 밖은 기존 흐름(렌더기 ERROR).
- **ft_plist_env.py** render(이중 방어 · 외부 호출 0): 루트에 `.git` 폴더가 없으면 `RenderError 루트가 git 공용 루트 아님(워크트리|.git 없음)` rc3. bin·kit 짝 cmp0.
- **ft_live_install_check.py**: `plist_root`(공용 루트 · git 밖이면 그대로) — plist-env 대조와 `HINT plist-env … --project` 둘 다 공용 루트. STALE-COPY HINT 는 워크트리 그대로. bin·kit 짝 cmp0.
- **시험**: `test_live_install_check_plist_env.sh` 픽스처 프로젝트를 git 리포로 + r457ⓐ~ⓔ(ⓐ 루트 OK 그대로 ⓑ 워크트리 dry-run·apply SKIP 1줄 · plist cmp 불변 · launchctl 0 · shim 설치 됨 ⓒ 렌더기 워크트리 rc3 · 루트 rc0 ⓓ install-check 워크트리 → 대조·HINT 공용 루트 ⓔ git 밖 install.sh rc1 · install-check rc3) — 32 PASS. 실 머신 dry-run(읽기만): 루트 `OK plist-env` · v6-realtime-live `SKIP plist-env` · plist cksum 불변. 증거 `harness/evidence/r457/`.
- 범위 밖: 템플릿 `--project __PROJECT__` 자리 · 미러 스크립트 · r413 HINT 문구. base 에서도 빨강인 `test_live_install.sh`·`test_live_install_check.sh` ⑥·`test_live_install_check_tip.sh` ⓕ 는 master-steps 에 기록(새 단위 후보).

## 2026-10-19 — 루트 3분리(r385 r3)·명부 폴더 raise(R231a) 뒤 빨강이던 팩 시험을 픽스처로 초록 · `ft-harness-info.sh seats` 는 comm 을 못 풀어도 목록·팀 명부 절을 찍는다 (1.1.23)

카드 r455a · master 111909 · arch#100 실측 · 판정 1395(«기존 RED» 변명 0). 도구 계약이 바뀌었는데(데이터 루트 = FT_ROOT → `.fable-team/LIVE_ROOT` → 옛 설치 꼴 · comm 폴더 필수 · 명부 폴더 없음 = raise · close 가 `ft-seat-reap.sh` 호출) 그 계약을 쓰는 시험 픽스처가 같은 단위에서 안 바뀌어 첫 줄 ERROR 로 끝나고 있었습니다.

- **키트 `ft-harness-info.sh` seats**(bin·kit 짝 cmp0): `ft_comm_dir` 실패 → `exit 1` 대신 `ALIVE` 비움 = ⚠ NOAGENT 표시 0(머리 주석 «판정기 없거나 판정 불가면 표시 0» 그대로) · 세션 목록·팀 명부 절은 그대로 찍는다. 다른 절 변경 0. 옛 판: comm 없는 git 리포에서 rc1 `ERROR` 1줄 · 새 판: rc0 명부 절 출력.
- **픽스처(단언 약화 0 · env·mkdir·스텁만)**: `test_role_spawn_name` `FT_ROOT=<임시 리포>` + `.fable-team/comm` · `test_graphics_install` ⑥ `FT_ROOT` + comm + 임시 ROOT 에 `origin/main` ref(R400 r3 명단 읽기) + 팩엔 `design/graphics/` 가 없어 조용히 실패하던 GOAL 복사를 «설치된 골 3줄로 시험용 GOAL» 로 · `test_graphics_690` ② 스텁 ALIVE 유/무 2케이스(무 = 외부 FT_ROOT·ALIVE 를 지워 판정 불가 경로 강제 · ERROR 줄 0 단언) · `test_proposal_gate_wiring` 14 create-pair 계약(FT_ROOT+comm · FT_ME · FT_ISSUES_SEATS) + 14c `FT_MBOX_CMD` 스텁 · `test_board_publish`·`_tick` `mkdir -p $T/ft/.fable-team` · `test_nano_team_env` 임시 bin 에 `ft-seat-reap.sh` 스텁(r448 · 실기계 프로세스 0).
- **`test_autonomy_preflight`**: 머리 주석 1줄(소요 ≈ 4분 · 120초 상한이면 rc=124 — 빨강 아님). 코드 0.
- **결과**(팩 루트 · GIT_* 0): role_spawn_name · proposal_gate_wiring · board_publish · board_publish_tick · nano_team_env · autonomy_preflight(600 s · 113 checks fail=0) · harness_info(덤 · 옛 rc2) rc0. 남은 빨강 = `test_graphics_install` ⑦ · `test_graphics_690` ⑦(라이브 governance·harness-map 정본이 staged 판으로 승격된 적 없음 — 카드 «판정 요청» · 시험 결함 아님) · `test_planner_nano_path` 하위 `test_nano_spawn_body_press`(r455b).
- **범위 밖(새 카드 후보)**: `test_team_literal_paths`(같은 comm 계약 + 골 표 정본 파일 없음) · `test_agent_alive_fg_judge`(BYZ 경로 목록 · 이식 누락) — 둘 다 base(ed8e118e)에서도 rc1.

## 2026-10-19 — `ft-inbox mark <seq>` 가 큐에 없는 쪽지도 우편함 파일(현행·로그·회전본)에서 찾아 적재 뒤 표시한다 (1.1.23)

카드 r430 · planner 증거 ②(110829) · EVAL I3 · arch#96. planner 가 `mark 110726` 류를 치면 `REJECT 대상 못 찾음(좌석 …)` 이 났습니다. ★실측(10-19): 원인은 카드 가정(«mark 가 mailbox.jsonl 만 본다»)이 아니었습니다 — 쪽지 조회 `mail_files()` 는 이미 현행 → `mailbox.log.jsonl` → 회전본(숫자 순)을 다 보고, mark 는 우편함이 아니라 «좌석 큐»(`state/inbox/<계보>.jsonl`)만 봅니다. 110726·110770·110796 은 send 때 큐 적재가 빠져(planner 큐 5994행에 없음 · 원본은 `mailbox.log.jsonl`) 큐에 행이 없었습니다★ — 같은 seq 를 임시 루트에서 `ingest` 하면 바로 들어갑니다.

- **`ft_inbox_core.find_seq(seq)`**(새): `mail_files()` 순서 첫 1건 → (파일 경로, 행) · 글자 선거름(`"seq": N`) 뒤에만 json 해석 — 5MB 회전본 끝 행 0.09 s. `find_mail` 은 그 래퍼(ingest 그대로).
- **`ft-inbox.py` locate**(mark·report 공통): 좌석 큐에 없는 숫자 seq 는 우편함 파일에서 찾아 ①수신 계보 = 호출 좌석 계보면 `ingest`(같은 행 꼴 · `INGEST …` 줄) 뒤 대상으로 삼고 ②남의 계보 앞 쪽지면 기존대로 REJECT(남의 큐·내 큐 쓰기 0) ③어디에도 없으면 기존 줄 뒤에 ` · 대상 못 찾음 seq=<n> (<N> 파일 조회)` rc1(조용한 통과 0).
- **mark 출력**: 기존 `OK <큐> seq=…` 다음에 숫자 대상이면 `MARKED seq=<n> file=<쪽지 원본 우편함 파일 이름>`(큐에만 있으면 `file=없음(큐만)`). 표식 저장 위치는 기존 그대로(좌석 큐 행 `mark`).
- **시험**: 새 `test_inbox_mark_rotated.sh` 23 PASS(ⓐ mailbox.jsonl ⓑ log.jsonl ⓒ 회전본 `.2`·`.10` 숫자 순 ⓓ 없음 rc1 + 문구 + 큐 불변 ⓔ 5MB ≤1 s ⓕ 600/300 0 ⓖ 남의 계보 앞 쪽지 rc1 · 재표시 적재 0) · 옛 코드에서 15 FAIL. 기존 `test_inbox*`·`test_ft_mbox_inbox_ingest`·`test_proposal_approve_inbox` rc0.
- **범위 밖**: send 때 적재가 왜 빠졌는지(적재 실패는 `WARN` 만 stderr · 실패 경로 관측은 실사건 때) · recv/peek 조회 범위 · 회전 정책 · stall-scan d 판정.

## 2026-10-19 — arch 가 죽은 «arch 상시» 팀의 교대 교착을 푼다: `ft-role-spawn --team <팀>` + arch 없음 REJECT·ERR 문구가 «있는 길» 명령 1줄을 적는다 (1.1.24 · 묶음 가지에 재적용)

카드 r437 · master 110967 · planner 110961(판정 2346). feature master#30 교대가 `REJECT 그 팀 arch 좌석 없음 — 먼저 arch 를 열어라(ft-role-spawn arch)` 로 막혔는데, 안내가 가리킨 `ft-role-spawn.sh` 는 v65 명부(seats.json)·v65 폴더에 고정돼 feature arch 를 못 열었습니다(CFO 선례와 같은 뿌리). 죽은 arch 의 자기 교대(successor-open)는 게이트가 이미 통과시키므로, 도구가 그 길을 정확히 적게 합니다. 게이트 판정 기준(R342)은 불변 · master 교대 예외 0.

- **ft-role-spawn.sh**: `--team <팀>`(기본 v65 = 동작 불변). 팀이면 명부 `seats-<팀>.json` · 인박스·README = `ft_team_in "$WT" <팀>` 폴더 · 이름 `byz-<팀>-<역할>-<에이전트>#N`(계보 하나) · 페널티 게이트 팀 = 그 팀. 명단 밖 팀·폴더 칸 오류·명부 없음·`<팀> SEATBELT-README.md 없음: <경로>`·인박스 없음 = REJECT(v65 로 조용한 대체 0 · #0 RULE). 명부 `_<역할>` 이 교체 대상 밖 좌석(죽은 arch · 행 없음)을 가리키면 REJECT + successor-open 명령 안내(두 arch 0). 빈 역할 키(`_master`·`_arch`·`_da`·`_tester`)는 새 좌석으로 채운다(팀 모드만).
- **ft_teamset.py** `arch_open_hint`(판정기 하나): arch 없음 사유 끝에 `→ 열기: …` 1줄 — 명부 `_arch` 에 이름 있음 = `ft-successor-open.sh '<그 arch>' <팀 워크트리> --name '<베이스>#N+1' --agent … --model … --body-file …` · 비었음 = `ft-role-spawn.sh arch --team <팀>`. 같은 문자열이 `ft-successor-open` REJECT(arch-live NO 줄)와 `ft-teamset-check` ERR 줄 둘 다에 실린다.
- **ft-successor-open.sh**: REJECT 머리 `먼저 arch 를 열어라(ft-role-spawn arch)` → `(아래 «→ 열기» 명령 · R437)`. **ft-teamset-check.sh**: 머리 주석에 ERR arch 줄 형식 1줄(동작 불변). bin·kit 짝 cmp0.
- **시험**: `test_role_spawn_team.sh` ⓐ~ⓖ ALL PASS(ⓐ 실제 명부 쓰기 = seats-feat.json·_arch 채움·seats.json 쓰기 0 · ⓑ v65 불변 · ⓒ README 없음 REJECT · ⓓ 명단 밖·_arch 충돌 REJECT · ⓔ successor-open 문구 2꼴 · arch 자기 교대 통과 불변 · ⓕ teamset-check ERR 2꼴 · ⓖ 600/300 0). 증거 `harness/evidence/r437/`.
- 범위 밖(기록만): 팀 폴더 SEATBELT-README 생성(`ft-team-upgrade` 몫 — feature 폴더엔 아직 없음 → 그때까지 feature arch 는 successor-open 경로) · 명부 `_arch` 가 죽은 좌석을 가리키는 행 자동 보정.

## 2026-10-19 — 정지 감시기가 정지 중인 팀에 «지금 spawn» 을 독촉하지 않는다: 명부 stop-ready 판정 · 정지 판정 실패를 정지 없음으로 읽지 않음 (1.1.23 묶음: r426·r427·r428·r429)

카드 r428 · 쪽지 110864(v65 «대기 카드 85장 · 지금 spawn»)·110865 · arch#96 실측 · EVAL I17. 오빠가 «정지 레디·팀장 하나만»(판정 2341·2342)을 건 v65 에 stall a 독촉이 나갔습니다. 실측: 정지는 쪽지 문장으로만 걸려 정지 파일 0(`hold=none`), 명부 master 행은 `role=stop-ready` 였는데 감시기는 master 의 role 을 보지 않았습니다. (감시기 파이썬은 R320b 부터 SPAWN_HOLD 를 `status --check` 로 이미 읽는다 — arch 실측의 «grep 0» 은 래퍼 `ft-stall-scan.sh` 만 본 값.)

- **ft_stall_detect.py**: `load_teams` 가 팀마다 `master_stop`(명부 `_master` 행 `role=stop-ready` · ft-seat-close R297 표기)을 싣는다. `policy_stop` — 유효 정지 글 = `SPAWN_HOLD 유효 · 정지 중(hold=<번호>) · 독촉 0` · 판정 불가 글은 모두 `ERROR` 로 시작 · ★`--check` 가 측정 실패(status rc4 «ERROR hold …»)를 rc3 으로 감싸 돌려주던 것을 «정지 없음» 으로 읽어 a 를 내던 구멍을 막는다(본문에 `ERROR hold` 가 있으면 판정 실패)★.
- **ft_stall_scan.py**: master 가 살아 있고 stop-ready 이며 유효 정지가 없으면 그 팀 a 대신 c 1건(`정지 레디(명부 role=stop-ready)인데 정지 파일 0 — ft-spawn-hold.sh set 필요 · 독촉 0`) + planner 쪽지 `[정지 파일 0] <팀> master <좌석> …` 1통(팀당 하루 1회 · 표식 `state/stall-scan.stopready-<YYYYMMDD>` · urgent 아님). 판정 실패면 출력에 `ERROR SPAWN_HOLD 판정 실패 … — a 독촉 0` 1줄. b·d·페널티·RESOURCE_FREEZE 무변경. bin·kit 짝 cmp0.
- **시험**: `tests/scripts/test_ft_stall_scan.py` r428 ⓐ~ⓔ(ⓐ 진짜 `ft-spawn-hold.sh set` 정지 파일 → a 0·c 1·master 쪽지 0·로그 `act=c … hold=2341`·파일 유지 ⓑ stop-ready → c 1·planner 1통·같은 날 2회째 0 ⓒ 정지 없음 → a 그대로(r409 선행 미판정 포함) ⓓ 해제 조건 측정 실패 → a 0·ERROR 1줄 ⓔ 600/300 0) — base 코드로 ⓐⓑⓓ RED · 53 passed. 증거 `harness/evidence/r428/`.
- 범위 밖: 정지 파일 자동 생성(정지는 사람·planner 의 `set`) · r409 선행 줄 판정 · b·d.

## 2026-10-19 — 승계 은퇴가 «모든 명부»의 라우팅 칸(`_hil_route`…)을 후계로 바꾼다 — planner 교대 뒤 손 갱신 0

카드 r429 · planner 증거 ① · EVAL I2 · arch#96 실측. `ft-seat-retire <구> <후계>` 는 «옛 이름이 값인 `_*` 칸 전부» 를 바꾼다고 돼 있었지만 고치는 파일은 자기 팀 명부 하나뿐이었습니다. planner master 이름은 모든 팀 명부의 `_hil_route`(사람 판정 요청이 가는 곳)에 들어 있어, planner 가 승계할 때마다 나머지 명부를 손으로 고쳐야 했고 그동안 [HIL] 쪽지가 은퇴 좌석에 쌓였습니다(mbox-guard forward 로 겨우 구제).

- **ft-seat-retire.sh**: 자기 팀 명부 은퇴 뒤 같은 폴더(루트 `.fable-team`)의 다른 `seats*.json` 전부에서 값이 <구> 인 «라우팅 칸»(`ROUTE` = `_hil_route`·`_planner`·`_desk_route` + 이름이 `_route` 로 끝나는 칸)만 <후계> 로 · 역할 칸(`_master`·`_arch`…)은 자기 팀 명부만. 전부 검증 뒤 쓰기 — 명부 하나라도 JSON 손상이면 `ERROR 명부 JSON 손상 [<파일>]` rc1 · 쓰기 0. 바뀐 파일마다 `.bak-retire-<ts>` · tmp→교체. 출력 첫 줄 끝에 ` files=<N> routes=[<파일>:<칸>…]`(앞부분 `RETIRED <구> -> <후계> file=… keys=[…]` 그대로).
- **R282 ② 판정 개정**: 옛 행이 어느 명부에도 없을 때의 «다른 명부에서 현역» REJECT 는 역할 칸만 본다(라우팅 칸에 옛 이름이 있는 건 이번에 바뀔 대상 — 막지 않음).
- **시험**: 새 `test_seat_retire_rosters.sh` ⓐ~ⓔ(files=3 · 남의 `_master` 불변 · R282 ② · 손상 1개 = 전부 0 · 600/300 0) · `test_seat_retire.sh` ③⑨ 첫 줄 기대값에 ` files=1 routes=[]`.
- 범위 밖(이름만): 명부 칸 이름 표준화 · `ft-tick-team.sh retarget_seat` 통합 · NOOP(이미 은퇴) 재실행 때 남은 라우팅 칸 쓸기.

## 2026-10-19 — tmux 세션이 이미 없는 «죽은 좌석» 명부 행을 `--verdict` 가 닫는다(CLOSED-DEAD) · 재개 기록은 보존 · `--reopen` 으로 되살린 좌석 복원

카드 r427 · master 증거 ⑫(110863) · EVAL I16 · planner 판정 2344. «팀장 하나만»(판정 2341)으로 feature 팀 13석을 `ft-seat-close --verdict` 로 닫으려 했더니 전부 `HELD … NORECORD 조회 불가: pane 식별 조회 불가` 였습니다. 그 좌석들은 tmux 세션이 이미 없어 pane 에서 대화 uuid 를 뽑을 수 없는데, 닫기 도구는 «살아 있는 좌석» 길만 있었고, 기록 실패 처리에서 기존 재개 기록을 `.stale-<ts>` 로 «무효화» 해 지웠습니다(byz-feature-da-codex#2).

- **ft-seat-close.sh**: `--verdict` 에서 `tmux has-session` 0 이면 죽은 좌석 분기 — `ft-seat-retire --record-only --verdict <번호> --keep-existing` → 명부 행 stop-ready + `_closed.dead=true`(role 은 stop-ready 그대로 — ft-tick resume_rows·seats-lint·stall 이 이 값으로 «재개 0» 을 판정하므로 새 role 값을 만들지 않음) · 그 좌석 값인 `_*` 칸 "" · kill 0 → `CLOSED-DEAD <좌석> record=<kept|new|NORECORD> handoff=<칸들|->` rc0 · 비운 칸이 있으면 «교대 0 · planner 1줄» 안내. NORECORD 여도 닫는다(죽은 좌석은 kill 할 것 0). 살아 있는 좌석 경로(HELD rc3)는 그대로.
- **ft-seat-close.sh --reopen <좌석>**: zombie-clean resume 으로 되살린 좌석(세션 있어야 함 · 없으면 REJECT)의 행을 role=`_closed_role`(없으면 active)·tick=`_closed_tick` 로 되돌리고 `_closed*` 제거 · 닫을 때 `_closed_from`(파일:칸) 에 적어 둔 칸이 지금도 "" 면 다시 그 좌석으로(그새 교대된 칸은 덮지 않음) → `REOPENED <좌석> roles=<칸들> role=<role>`. 재개 기록은 그대로.
- **ft-seat-retire.sh**: `--keep-existing`(`--record-only` 전용) — 기존 기록 있으면 새 시도 0 → `RESUME kept <경로>` · 없고 세션도 없으면 대화 기록 탐색 1회(`~/.claude/history.jsonl` 의 그 좌석 이름 줄 → project·sessionId → 그 jsonl 머리 64KB 에 `"agentName":"<좌석>"` «정확히 1개» · binding.source=`dead-agent-name`). 기록 실패(NORECORD)는 옛 기록을 건드리지 않는다(무효화 0 — 닫기 판정은 zombie-clean 이 binding `--expect` 로 다시 본다 · DA⑥ H1 개정) · 새 기록 «성공» 때만 옛 것을 `<경로>.prev-<ts>` 로.
- **시험**: `test_seat_close.sh` r427 ⓐ~ⓓ·ⓖ·ⓕ(진짜 retire · 가짜 tmux·HOME) · 새 `test_seat_retire_keep.sh` ①~⑧ · `test_seat_retire.sh` ⑨H1·⑩ⓓstale 기대값을 «보존» 으로 개정.
- 범위 밖(이름만): zombie-clean resume 이 `--reopen` 을 자동 호출 · 죽은 좌석 자동 수거 · `_*` 칸 교대 자동 선정(planner 결정) · codex 좌석의 죽은 뒤 기록 탐색(rollout).

## 2026-10-19 — 설치기가 쪽지→슬랙 미러 launchd plist 의 환경(FT_ROOT · inbox 경로)까지 템플릿에서 갱신하고, install-check 가 `PENDING plist-env` 를 센다 (버전 = master 착지 순)

카드 r426 · EVAL-new-harness-overnight-20261019 §3 I1 · arch#96 실측 · planner 판정 2344. 10-19 00:35~08:22 미러(`com.hermes.byz-mbox-slack-mirror`)가 FT_ROOT 없이 옛 워크트리 bin(`v6-realtime-live/.fable-team/bin/ft-inbox.sh`)을 불러 1분마다 exit1(917회) — 오빠 슬랙 수신 7시간 47분 정지. 설치기는 bin·hermes 스크립트만 바꾸고 plist 환경은 그대로였고, install-check 는 Label 적재만 봐서 «OK» 였다(사람이 08:22 손 수정 `.bak-ftroot-20261019`).

- **`kit/slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template`**: `EnvironmentVariables` 에 `<key>FT_ROOT</key><string>__ROOT__</string>` 1줄. `slack-mirror/install.sh` 는 `__ROOT__ = BYZ_ROOT` 치환 1칸 추가(처음 설치 경로도 같은 렌더).
- **`kit/fable-team/bin/ft_plist_env.py`(새 · bin 짝)**: 설치기 관리 라벨 표 `MANAGED`(지금 = 미러 1) · `render` = 템플릿 + 설치된 plist 의 머신별 값(`__PY__`·`--project/--seat/--channel/--mention/--repo`) 보존 + `__ROOT__`=프로젝트 루트 · `__INBOX_BIN__`=`<LIVE_BIN>/ft-inbox.sh` · `__MAILBOX__`=`<루트>/.fable-team/comm/mailbox.log.jsonl`. 루트·LIVE_BIN·설치값 없음 · 자리표시 잔재 · plist 해석 실패 · 렌더본 FT_ROOT≠루트 = `ERROR` rc3(조용한 통과 0).
- **`harness/install.sh`**: plist 절 — «설치된 것만» 렌더본과 cmp → 다르면 `--apply` = `.bak-r426`(첫 원본 보존) + 교체 + `launchctl bootout`·`bootstrap`·`kickstart -k`(변경 때만) · 같으면 쓰기 0 · `--dry-run` 은 `PENDING plist-env <라벨>` 줄만(rc0) · 미설치 = `SKIP`(새로 깔지 않음 · 처음 설치는 slack-mirror/install.sh). launchctl = `FT_LAUNCHCTL`(시험 주입).
- **`bin/ft_live_install_check.py`**(bin·kit 짝 cmp0): plist 행 중 관리 라벨은 설치본 = 렌더본 바이트 대조 → 아니면 `PENDING plist-env <라벨> (… FT_ROOT=<루트>)` + `HINT plist-env bash <하네스>/install.sh --apply --project <루트>`. 루트 = `--project` 또는 리포 공용 루트(shim 대조와 같음) · LIVE_BIN 없음 = ERROR rc3(`--project` 를 주라는 안내). `LIVE-MAP.tsv` 머리 설명 1줄 갱신.
- **카드 편차 2**: ①템플릿을 `kit/launchd/` 새 파일로 만들지 않고 이미 있던 `kit/slack-mirror/…plist.template` 을 고쳤다(arch 실측이 `kit/launchd/` 만 봄 · 같은 라벨 템플릿 2개 = 두 정본) · 자리표시는 기존 `__X__` 꼴 ②설치 적용은 `kickstart` 만으로는 launchd 가 plist 를 다시 읽지 않아 `bootout`→`bootstrap`→`kickstart -k`(slack-mirror/install.sh 와 같은 순서).
- **시험**: `tests/test_live_install_check_plist_env.sh` ⓐ~ⓔ 24 PASS(임시 HOME·가짜 launchctl · 실 등록 0). 기존 `test_live_install_check.sh`·`test_live_install_check_tip.sh` 는 base 에서 각 18·12 FAIL(r385 뒤 `--kit` 미전달 · shim 시험 r413 이 고친 것과 같은 꼴) → `chk()` 에 `--kit "$KD"` 1칸으로 1·2 FAIL 로 — 남은 3건은 이 카드 밖(아래). 증거 `harness/evidence/r426/`.
- **base 부터 남은 FAIL 3(기록만 · 고침 단위 필요)**: ①`test_live_install_check.sh` 린트 ⑥ «구현 범위가 scripts/harness-install/ 언급 + 없음 → REJECT» — `ft-index-lint.sh` 가 옛 키트 경로 언급을 더는 안 센다 ②③`test_live_install_check_tip.sh` ⓕ 2건 — `ft-index-move-install.sh` 가 검사 도구에 `--kit` 없이 `--repo` 만 넘겨 임시 리포 픽스처에서 «하네스 루트가 --repo 밖» ERROR.
- **master 절차**(착지 뒤): ①`bash <팩>/feature-pack/fable-team/harness/install.sh --dry-run --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` → `PENDING plist-env com.hermes.byz-mbox-slack-mirror` 1줄 확인(나노 실측 10-19: 의미 차이 = `--inbox-bin` 옛 워크트리 bin → `~/.claude/fable-team/live/<버전>/bin/ft-inbox.sh` 하나 · FT_ROOT 는 손 수정본과 같음) ②`--apply` → `PLIST applied …` · `~/Library/LaunchAgents/com.hermes.byz-mbox-slack-mirror.plist.bak-r426` 실재 ③`launchctl print gui/$UID/com.hermes.byz-mbox-slack-mirror` state=running ④`~/.hermes/logs/byz_mbox_slack_mirror.err` 꼬리 1분 관측 — 새 줄 0(특히 «FT_ROOT 없음»·ft-inbox 오류) ⑤`ft-live-install-check.sh --range <병합 전 main>..<착지 sha> --project <BYZ 루트>` → OK ⑥실사건 = 다음 planner 쪽지가 슬랙 채널에 미러됨(`.out` 1행). 되돌림 = `cp -p <plist>.bak-r426 <plist>` + bootout·bootstrap.

## 2026-10-19 — BYZ 리포 안 1Password(op) 볼트 명령은 develop 볼트 + develop 토큰 꼴만 — 홈 훅 `op-vault-develop-gate.sh` (1.1.22)

카드 r451 · master 111771 · desk 111757 · 오빠 «op 볼트는 무조건 develop 사용하라고 강력지침» «kskill은 슬랙 자동화용이다». 기본 `OP_SERVICE_ACCOUNT_TOKEN` 은 kskill(슬랙 자동화 전용) 볼트만 보여, 좌석이 그냥 `op item create` 를 치면 kskill 에 들어갔습니다(컨시어지 시연 계정 8개). 지침 줄(전역 하드 룰 15)은 이미 있어 이 단위는 «막는 장치» 입니다.

- **새 `kit/hooks/op-vault-develop-gate.sh`**(PreToolUse:Bash · 홈 훅): 명령을 구분자(`; && || | 개행 $( \``)로 나눠 실행 낱말이 `op` 이고 하위 명령이 `item create|edit|get|list|delete` · `document …` 이면 `--vault develop`/`--vault=develop`, `read` 면 모든 `op://` 참조의 볼트가 develop — 그리고 명령 글자에 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"` 대입(앞 대입·`export`·`env` 꼴)이 있어야 통과. 아니면 exit 2 + stderr `REJECT op 볼트 = develop 만 — kskill 은 슬랙 자동화 전용(오빠 10-19) · 꼴: … (빠진 것: …)`. `op vault list`·`whoami`·`signin`·`account`·`--version`·`--help`·`item move` 등 볼트 선택이 아닌 명령은 통과. `bash -c "…"` 문자열 안도 검사, 따옴표 안 글자·grep 인자·커밋 메시지는 실행 아님.
- **범위 = BYZ 리포 안만**: `FT_ROOT`(있으면) 또는 cwd 의 origin URL 이 `…/byz-agents(.git)` 이거나 최상위에 `.claude/skills/byz-keys/`. ★공용 루트 체크아웃(옛 main)에는 byz-keys 가 없고 팩 리포에도 `.fable-team` 이 있어(10-19 실측) 파일 표식 하나로는 못 가린다 — origin URL 이 주 판별★. BYZ 밖(hermes 슬랙 자동화)은 통과.
- **fail-open**: 입력 JSON 못 읽음·파이썬 예외 = 통과 + stderr `WARN`(다른 홈 훅과 같은 꼴 · 거절만 하는 훅). 외부 호출 0(위반 후보일 때만 로컬 git 2회 · 각 5 s). ★토큰 값은 읽지도 찍지도 않는다(OP_* 환경값 접근 0 · 명령 글자만)★.
- **`harness/install.sh`** HOME_HOOKS 에 `op-vault-develop-gate.sh` 1토큰(→ `~/.claude/hooks/` cp -p → cmp) · **`templates/settings-hooks.snippet.json`** PreToolUse `Bash` 1항(`$HOME/.claude/hooks/op-vault-develop-gate.sh` — 홈 settings.json 등록 꼴 그대로 · 실제 등록은 master).
- **시험**: 새 `test_op_vault_develop_gate.sh` 49 PASS(ⓐ kskill 생성 REJECT + 안내 원문 ⓑ develop 볼트인데 토큰 0·기본 토큰 대입 REJECT ⓒ 올바른 꼴·`--vault=`·export·env·`op read op://develop` 통과 / op://kskill·document kskill REJECT ⓓ 볼트 인자 0 REJECT · 볼트 선택 아닌 7 명령 통과 ⓔ BYZ 밖·git 밖 통과 · 표식 없는 origin byz-agents 리포 REJECT · FT_ROOT=BYZ REJECT ⓕ `&&`·`;`·`|`·`$( )`·`bash -c`·절대경로 op REJECT · 따옴표/grep/커밋 메시지·tool≠Bash·못 읽음·빈 입력 통과 ⓖ 600/300 0 · 가짜 op 호출 0 · OP_ 환경값 접근 0 · 가짜 토큰 값 출력 0 · install/스니펫/권한/bash -n). 기존 `test_old_team_path_deny`·`test_install_hook_check`·`test_harness_freeze_gate` rc0.
- **범위 밖**: kskill 에 이미 생긴 시연 계정 8개의 develop 이전(ops · `op item move` 는 막지 않음) · hermes 쪽 op · 토큰 교체 · `skill/templates/settings-hooks.snippet.json`(이미 키트 사본과 다른 쌍둥이 · 이 단위 손대지 않음).

## 2026-10-19 — planner 앞 쪽지가 «조용히 아무도 안 받는» 상태를 소리 나게 한다: quiet 는 세션 안 감시와 한 쌍 (1.1.21)

카드 r408 · desk 110229 실측 · planner 110234 · master 110237 · arch#94. 판정 876 으로 planner `_master` 는 doorbell 을 받지 않고 세션 안 감시(`ft-inbox-watch.sh` + Monitor)로 받는데, 승계(#71→#72) 뒤 감시가 안 걸려도 send 는 `doorbell=quiet` 만 찍어 큐가 3~5분씩 쌓였습니다(수동 깨움 5회).

- **판정기 하나 `ft-mbox.sh watch-alive <좌석>`**(rc0 `OK watch` / rc3 `NO watch`): 감시 실체 = `ft-inbox-watch.sh` 가 exec 한 `python3 -u - <bin> <좌석>`(셸 이름은 프로세스에 안 남는다) · 끝 인자 정확 일치 ∧ `<bin>/ft-inbox-watch.sh` 실재 · 목록 `FT_PGREP`(시험) 또는 `pgrep -lf`.
- **send/relay**(키트 `ft-mbox.sh` · 좌석들이 쓰는 `comm/mbox.sh`): user_facing 좌석에 감시가 없으면 `doorbell=quiet(WATCH 없음)` + 하네스 master(`seats-harness.json` `_master`) 앞 `[긴급 · planner watch 없음] <좌석> · 감지 HH:MM · 계기 쪽지 #N · 시작: Monitor → bash <루트>/.fable-team/bin/ft-inbox-watch.sh <좌석>` 1통 · 같은 좌석 10분 1회(표식 `state/planner-watch-missing.<좌석>`) · 판정 불가 `quiet(WATCH 판정 불가)` · 오빠 pane 주입 0(876 불변) · 명시 `ring` 불변.
- **ft-teamset-check**: planner 팀 `_master` 감시 없음 → `ERR planner watch 없음(ft-inbox-watch.sh <좌석>)` rc1(`FT_TEAMSET_WATCH` 시험 대체).
- **시험**: `test_inbox_watch.sh` r408 절(ⓐ~ⓔ · comm·키트 두 경로 · 미끼 3 = 접두 좌석·시작 명령 실은 send·다른 bin) · 옛 코드에서 20 FAIL. 픽스처 2: `test_ft_mbox_inbox_ingest.sh` 변이 줄 글자 · `test_arch_required_gate.sh` 감시 판정 가짜.

## 2026-10-19 — design/ 아래 증거 로그(.log·.out·.nohup·guard/poller 로그)는 커밋도 착지도 안 된다 · 이미 들어간 614개는 index 에서만 뺀다 (1.1.20)

카드 r449 · master 111666 · 오빠 «아니 이 무의미한 파일을 왜 커밋하는데? 관리도 안되고 무식하게 아래로만 커지는 로그성파일인데». `.gitignore` 의 `*.log` 를 `git add -f` 가 뚫어 BYZ origin/main `design/` 아래에 로그성 파일이 쌓였습니다(실측 643bf03512: 판정식 614개 303.2 MB). add 단계는 `-f` 로 무력이라 index 단계·착지 단계 두 곳에 섭니다.

- **판정식 한 곳 `ft-evidence-lib.sh`**(새 · POSIX · source 전용): `design/` 아래 ①끝이 `.log·.out·.nohup·.stdout·.stderr·.pid` ②이름에 `guard·poller` 가 들고 끝이 `.jsonl·.jsonl.gz·.txt`. md·json·py·sh 는 이름에 guard·poller 가 있어도 아님(설계 문서 203·poller_intent.json 등 보존). 카드 문구의 «이름에 guard/poller 든 것 전부»는 md·py 까지 잡아 범위를 좁혔습니다 — 아래 «편차».
- **`kit/fable-team/githooks/pre-commit`**(새 · BYZ `.fable-team/githooks/pre-commit` 2307 B 를 키트로 올림 · v6 공유 index 차단·beads 위임 그대로): «증거 로그» 절 — `git diff --cached --name-only -z --no-renames --diff-filter=AM -- design` 중 판정식 → stderr `EVIDENCE-LOG-GATE: 증거 로그 <n> staged — git rm --cached <목록 ≤10> · 요약은 SUMMARY-*.md` exit 1. `commit --only`(임시 index)도 같다. 예외 = `BYZ_EVIDENCE_LOG_OK=<사람 승인 번호>` ∧ `<공용 루트>/.fable-team/state/evidence-log-ok.<번호>` 표식 둘 다. 판정식은 `<훅 폴더>/../LIVE_BIN` 의 bin(없으면 `../bin`) — 못 찾으면 design/ 이 staged 일 때만 REJECT(조용한 통과 0 · design/ 밖 커밋은 통과).
- **`ft-merge-land.sh`**: main 확인 직후 가지 diff(`M...S --diff-filter=AM --no-renames -- design`) 에 판정식 → `REJECT 증거 로그 <n> — git rm --cached 뒤 다시: <파일명…> (착지 0)`. 판정식 lib 못 읽으면 rc2 실행 0. 113줄(≤120).
- **`ft-evidence-untrack.sh [--dry-run] <리포 루트>`**(새): `git ls-files -z -- design | 판정식` → `git --literal-pathspecs rm --cached --pathspec-file-nul`(디스크 보존 · 이력 재작성 0 · 커밋은 부른 쪽) · 출력 `UNTRACK n=<n> MB=<m> dry=<0|1>`(크기 = index blob) · 미커밋 tracked 변경 있으면 REJECT «[wip] 먼저».
- **`harness/install.sh`**: `--apply` 가 LIVE_BIN 연결 «뒤» 에 `kit/fable-team/githooks/*` → `<프로젝트>/.fable-team/githooks/` cp -p → cmp(덮기 전 `<파일>.bak-<버전>` · 출력 `GITHOOKS copied= same=`) · dry-run `GITHOOK` 줄 · `core.hooksPath` 가 다른 곳이면 WARN. **LIVE-MAP**: `fable-team/githooks/*` skip 행(설치 = install.sh · 대조 = cmp 명령).
- **시험**: `test_evidence_log_gate.sh` 54 PASS(판정식 단위 18 · ⓐ add -f 5개 REJECT·커밋 0 · ⓐ' commit --only · ⓑ md·sh 통과 · ⓒ env/표식 4조합 · lib 없음 REJECT/design 밖 통과 · ⓓ 가지 diff z.out REJECT 1줄·요약 md 착지·untrack(D) 착지·lib 없는 설치 rc2 · ⓔ untrack dirty REJECT·dry-run 목록 = 판정식·적용 n=8·디스크 보존·.gitignore 뒤 status 0·D 커밋 훅 통과·멱등·usage · ⓔ' sparse-checkout 워크트리(cone 밖 포함 · BYZ 실측 첫 적용이 59/614 에서 실패 → `rm --cached --sparse`) · ⓖ install githooks cmp0·.bak·멱등·WARN · ⓕ 600/300·외부 호출·GIT_* env 0). `test_merge_land_state_dir.sh` 설치 묶음에 `ft-evidence-lib.sh`·`ft-harness-root.sh` 추가(base 에서 6 FAIL 이던 r385 뒤 누락 → ALL PASS). 증거 `harness/evidence/r449/`.
- **편차·범위 밖**: 판정식 614/303 MB vs 카드 955/361 MB — 차이 = 이름에 guard·poller 든 md·json·py·sh(설계 문서·도구 · 지우면 안 됨)와 이름 없는 `*.jsonl`(results·values 측정표 202개 — 원장이 가리킴). `test_live_install_check.sh`·`_tip.sh` 실패 19·13 은 base 와 같음(r385 뒤 픽스처 옛 경로 · 별 카드).

## 2026-10-19 — 좌석을 닫으면 그 좌석이 띄운 백그라운드 루프도 멈춘다(reap left=0 · 못 멈추면 CLOSE-FAIL) · 감시 루프는 상한·stop-file 래퍼 없이는 착지 0 · tmuxc 가 좌석 표식 FT_SEAT 를 심는다 (버전 = 착지 순서대로 master · r447 뒤) (1.1.19)

카드 r448 · master 111691 · 오빠 «이렇게 무식하고 멍청하게 쌓고있는건데». v65 tester67 이 띄운 `while … sleep 5 … >> guard.log` 루프 5개가 좌석 소멸 뒤 ppid 1 고아로 06:00~13:19 각 ~4,600줄을 쌓았습니다. 닫기 3종은 세션 kill 만 했고, 유출 안전망(ft-leak-reap)은 CPU ≥30 s 만 잡아 sleep 루프는 영원히 남았습니다.

- **새 `ft-seat-reap.sh <좌석> [--dry-run] [--wt <워크트리>] [--orphans-only]`**: 후보(내 uid) = ①tmux 세션 pane 자손 ②env `FT_SEAT=<좌석>`(ppid 무관) ②b argv `ft-bg-loop.sh --seat <좌석>` ③env 안 보임 ∧ ppid 1 ∧ cwd ⊂ 좌석 워크트리(`.git` 있는 폴더 · 안쪽 다른 워크트리 제외 · 다른 라이브 세션이 같은 워크트리를 쓰면 ③ 생략 `cwd=shared`) ∧ 명령에 sleep·while · 후보의 자식(via=자손). 제외 = 남의 FT_SEAT · 보호 exe(`ft-leak-reap.sh` PROTECT_EXE 를 그대로 읽음) · 자기 조상 · 다른 세션 pane 나무. TERM → 3 s → (시작 시각 같을 때만) KILL → 1 s → 재조사 2회전. 끝 줄 `reap <좌석> stopped=<n> left=<n> rc=<n>` · 조사 실패 rc 20(ft-leak-reap ① 계약) · 외부 호출 각 7 s.
- **닫기 3종**: `ft-seat-close.sh`(kill 앞 · 세션이 없어도) · `ft-nano-close.sh`(세션 kill·ABSENT 종료 앞 · `--wt <좌석 워크트리>`) · `ft-seat-retire.sh`(은퇴 뒤 `--orphans-only` — 살아 있는 옛 에이전트는 zombie-clean 몫) — left≠0 ∨ rc≠0 = `CLOSE-FAIL reap left=<n> rc=<n>` + exit 1(세션 보존) · 성공 줄 끝 `reap left=0 rc=0` · 상세 줄은 stderr · `FT_SEAT_REAP_BIN` 주입. bin·kit 짝 cmp0.
- **tmuxc `create_tmux_session`**: `tmux new-session … -e "FT_SEAT=<세션명>"` 1줄 — 카드의 «spawn 3종 뒤 `tmux set-environment`» 는 이미 뜬 셸·에이전트에 안 닿아(실측 `X=none` · `-e` 는 `X=<이름>`) spawn 3종 대신 세 경로가 모두 거치는 tmuxc 한 곳에 심었다(spawn 3종 변경 0).
- **새 `ft-bg-loop.sh --seat <좌석> --max-sec <n> --stop-file <경로> -- <명령>`**: 둘 다 필수 · 명령은 자기 프로세스 그룹 · 끝 줄 `bg-loop end reason=max-sec|stop-file|cmd-exit|signal sec=<n> rc=<n>` · TERM·INT·HUP 이면 그룹 정지.
- **새 `ft-bg-loop-lint.sh <파일|폴더>… | --range <A..B> [--repo]`**: `while` 루프(짝 done 줄까지) 안에 `sleep`+`>>` 가 있는데 앞에 `ft-bg-loop` 가 없으면 `ERR <파일>:<줄>` · `--range` = 가지가 추가·수정한 `design/**`·`tests/e2e/**` `*.sh` 만(옛 증거 범위 밖). **ft-merge-land.sh** 착지 게이트 1줄(ERR = 착지 0).
- **한계(기록)**: macOS 는 `/bin/sh`·`/bin/zsh`·`/bin/sleep` 같은 플랫폼 바이너리의 env 를 ps 로 숨긴다(brew bash·python·node 는 보임). 10-19 사건의 guard.sh 는 `#!/bin/zsh` + 공유 루트(v6-realtime-live) cwd 라 ②·③ 로는 안 잡힌다 — 그 꼴은 래퍼(②b argv)+린트로 막는다.
- **시험**: 새 `test_seat_reap_left0.sh` 55 PASS(3회 연속 · 실 tmux 세션 2 + 표식 고아 루프 · 끝에 잔존 프로세스·세션 0) · `test_nano_close_fail_closed.sh` ⓖ(reap left=1 → CLOSE-FAIL · kill 0 · --wt 전달) · 기존 닫기 시험은 reap 스텁. 기존 `test_seat_close`·`test_nano_close_*` 5·`test_merge_land*` 3·`test_leak_reap`·`test_successor_open`·`test_nano_spawn_reuse_info` rc0 · `test_seat_retire`(5 FAIL)·`test_merge_land_state_dir`(6 FAIL)·`test_role_spawn_name`(22 FAIL)는 origin/main 기준선과 같은 실패. 증거 `harness/evidence/r448/`.

## 2026-10-19 — 미완·정지 나노를 닫는 길: `ft-nano-close.sh --suspended "<사유>"` — ⑥ 만 면제 · 카드 «중단» 끝줄 · 브랜치 보존 (1.1.18)

카드 r450 · master 111726 · loom master 111718 «미완 나노 닫는 길이 있나». 팀 정지(판정 2365)로 구현 중 멈춘 loom #1442 나노는 시험 rc=1 이라 ⑥ 증거 줄로 못 닫고, 대체 카드가 없어 `--superseded-by` 도 못 써서 세션·워크트리를 쥔 채 멈춰 있었습니다(거짓 rc=0 금지).

- **ft-nano-close.sh**: 인자 `--suspended "<사유>"`(빈 값·여러 줄·`--superseded-by`·`--cherry-override` 동시 = usage 2) · ⑥ 자리 = 새 검사 · 실작업물 미커밋은 먼저 `[wip] nano close <좌석>` 커밋(실패 = REJECT) · ⑤ 에 `--override "suspended: <사유>"` · 원장 행 `suspended=1 reason=… set=…` · 출력 `CLOSED <좌석> suspended=1 reason=<사유> set=<HEAD>` · 브랜치 삭제 0 · 인자 없으면 동작 불변. bin·kit 짝 cmp0.
- **ft-nano-suspended-check.sh**(새): `<카드> --wt <워크트리> --reason "<사유>" [--apply]` — HEAD(브랜치 위 40hex)·미커밋 0 · `--apply` 면 카드 «## 상태» 끝에 `중단: <사유> · 세트 <HEAD> · <날짜> · 재개 = planner 발주 뒤 새 세션(브랜치 <이름> 보존)`(같은 세트면 0 · 멱등) · 출력 `SUSPENDED-OK card=… set=…`.
- **시험**: `test_nano_close_suspended.sh` ⓐ~ⓖ ALL PASS rc0(옛 close 로 돌리면 FAILED 17 — `evidence/r450/red-old-close.txt`) · 기존 `test_nano_close_*.sh` 5 rc0. 증거 `harness/evidence/r450/test.txt`.

## 2026-10-19 — 팀 폴더 옛 경로 재발 방지: 쌍둥이 공존이면 리졸버는 새 꼴 + WARN · 카드·문서 옛 글자 md 린트 · 옛 위치 카드는 spawn·lint·move·착지 REJECT · ft-team-move 쌍둥이 병합 이동 (1.1.17)

카드 r447 · master 111463 ②·111467 · arch#98 보고 `REPORT-team-path-oldpath-audit-20261019.md` §1·§2. main 은 팀 폴더를 `design/teams/<팀>/` 로 옮겼지만 concierge-main 은 이동 커밋을 받고도 옛 `design/concierge/`(37) 에서 계속 일해 새 폴더(45)와 공존했고, 경로 린트는 `*.sh *.py` 만 봐 카드·문서의 옛 글자와 옛 위치 카드는 아무도 막지 않았습니다.

- **`ft-team-lib.sh`**: `ft_team_root` 가 명단 새 꼴 ∧ 옛 꼴 폴더에 파일 실재면 새 꼴 반환 + stderr `WARN 옛 꼴 잔존 <N>파일 — ft-team-move.sh --apply <팀>` (`--alt` 불변 · 쌍둥이를 일부러 세는 `ft_team_cands*` 와 stderr 를 값으로 받는 `ft-team-map-lint.sh` 는 `FT_TEAM_TWIN_WARN=0`). 새 함수 `ft_old_form_team <경로>` · `ft_card_location_ok <카드>`(명단 = 카드가 든 리포 TEAMS.md · 명단 없으면 판정 생략) · `ft_old_form_added <리포> <base> <head>`(`diff -z` — 한글 경로 원문).
- **`ft-team-path-lint.sh --md <팀 폴더|파일>`**: `*.md` 본문 전부(주석·코드 블록 포함)에서 옛 꼴 `design/<팀>/` 글자 — 명단 새 꼴 팀 = `ERR <파일>:<줄>: …` rc1 · 전환 중(명단 옛 꼴) 팀 = INFO · 꼴3 팀 대상 아님. 기존 bin 검사 모드 불변.
- **`ft-index-lint.sh`·`ft-nano-spawn.sh`·`ft-index-move.sh`**: 카드 위치 옛 꼴(명단 새 꼴 팀) → `REJECT 카드 위치 옛 경로 — ft-team-move.sh --apply <팀> 뒤 다시` 1줄(nano-spawn 은 쌍둥이 해석 뒤 검사) · **`ft-merge-land.sh`**: 가지가 옛 꼴 위치에 새 파일을 만들면 착지 0. 넷 다 lib 이 있을 때만(lib 없이 복사해 쓰는 기존 시험 30여 개 · nano-spawn 116행 관례 · 설치본은 lib 항상 있음).
- **`ft-team-move.sh --plan|--apply <팀>`** + 새 **`ft_team_move_twin.py`**: 명단 새 꼴인데 옛 폴더에 추적 파일 남은 팀 = `PLAN-TWIN` 1줄 · `--apply` 가 병합 이동(유일본 `git mv` · 같은 이름 다른 내용 = 옛 쪽 내용 승 `git mv -f` · 본문 치환 뒤 같은 내용 = 옛 삭제) + 새 폴더 본문 옛 글자 치환 + 한 커밋 + 저장 참조 재작성 → `TWIN-MERGED <팀> MOVED <N> OVERWROTE <M> DROPPED-SAME <K>` · 미커밋 = `REJECT … [wip] 먼저` · `--revert` 로 원본 sha 복원 · `--verify` 에 쌍둥이 잔존 WARN.
- **시험**: 새 `test_team_path_oldpath_md.sh` ⓐ~ⓕ 63 PASS · `test_team_literal_paths2.sh` ⓔ 리졸버 값 캡처를 `2>/dev/null`(WARN 은 stderr) — 나머지 관련 29개 FAIL·PASS 개수 main 과 동일.
- **master 단계**: ①착지(r444 뒤) → `install.sh --apply` → LIVE_BIN cmp0 ②planner 1줄 뒤 concierge master 가 concierge-main 에서 `ft-team-move.sh --plan concierge` → `--apply concierge` 1회 → `git ls-tree HEAD design/concierge` 0 ③린트 실사건 1건(`ft-team-path-lint.sh --md <팀 폴더>` ERR 줄) ④arch: COMM-GUIDE-BOOT 14 «팀 폴더 경로» 절 1줄.
- 범위 밖(기록만): 팀 가지 main 병합·전환 집행(팀 master · planner 순번) · `ft-index-lint` 에 md 본문 검사 배선 · BYZ main 명단 기준 `ft-team-path-lint` «전환 끝 · 쌍둥이 후보 잔존(ft-nano-close·ft-nano-spawn)» ERR(이 카드 전부터 있음).

## 2026-10-19 — claude 좌석 전부 증류 경고 550k · 차단 600k 로 통일 (홈·BYZ 이원화 끝 · 승계 recv 차단선 550k 같이 이동) (1.1.16)

카드 r445 · master 111389 · 오빠 «전부 550k경고 600k 차단으로 가자. 1/3 줄이고». Fable 1M 창에서 400k 경고·450k 차단(키트==홈 훅)과 프로젝트 훅은 창의 절반도 못 쓰고 승계를 불렀습니다.

- **context-distill-gate.sh**(키트 템플릿): `WARN_DEFAULT, BLOCK_DEFAULT = 550_000, 600_000` · `RECV_DEFAULT = 550_000`(후계 도달 전 recv 차단선 = 경고선과 같이 이동) · 머리 주석 R445 1줄. 판정·allowlist·메시지 코드 불변(메시지는 값에서 계산).
- **ft-successor-open.sh**: 주석 6·104 «400k» → «550k»(값을 읽지 않음 · 동작 불변) · bin·kit 짝 cmp0.
- **문서 템플릿**: `templates/rules/orchestration.md` 증류 절 550k/600k + «전 프로젝트 공통» 1줄 · `CLAUDE.orchestration.snippet.md` 16행 550k/600k.
- **범위 밖**: codex(`~/.codex/config.toml` auto_compact 780k)·opencode(`opencode.json` compaction auto) 설정 변경 0 · `ft-mbox-bridge.sh:6`·`ft-index-gate.sh:12` 역사 수치 불변.
- **시험**: `test_distill_gate_550_600.sh`(인자 없이 호출 · ⓐ540k warn 0 ⓑ560k 경고 «550k·600k» ⓒ590k block 허용 ⓓ610k block exit2 ⓔ hard recv 560k 도달 파일 없음 차단/있음 허용·540k 허용·610k 일반 도구 차단 ⓕ BYZ 사본 cmp0 + 같은 케이스 ⓖ 600/300 s·codex/opencode 참조 0) ALL PASS rc0 · 옛 훅 RED 7 · 기존 `test_distill_recv_gate.sh`·`test_successor_open.sh` rc0. 증거 `harness/evidence/r445/`.

## 2026-10-19 — 공유 루트에서 나노를 닫으면 꼬리에 남던 «팀 명단 없음» ERROR·WARN 을 없앤다: 빈 석 계산도 명단 = ref · 폴더 = 그 루트 (1.1.15)

카드 r416 · v65#211 쪽지 110851 · master 110852 · arch#96 실측. v65 가 공유 루트 v6-realtime-live 에서 나노를 닫으면 닫기는 통과하는데 꼬리에 `ERROR v65 은 팀 명단(TEAMS.md)에 없다` · `ERROR v65 팀 폴더를 못 풀었다(design/TEAMS.md)` · `WARN ft-nano-slots 실패(rc=1) — 빈 석을 손으로 세라` 3줄이 남았습니다. 세 줄 전부 닫기 끝에 부르는 `ft-nano-slots.sh` 가 cwd 사본 `design/TEAMS.md`(옛 8행 · v65 행 없음)로 팀 폴더를 풀던 한 곳에서 나왔습니다.

- **ft-nano-slots.sh**: `ft_team_cands "$WT" v65` → `ft_team_cands_ref "$WT" v65 "${FT_TEAMS_REF:-origin/main}"`(R400 r3 nano-close · R406 spawn·lint 와 같은 함수). ref 못 읽음 = `ERROR v65 명단(<ref>:design/TEAMS.md)을 못 읽음` rc1 — cwd 명단으로 되돌아가지 않는다(#0 RULE). 실패 줄에 ref·루트를 적는다. `FT_INDEX_DIR` 주입 경로는 불변. bin·kit 짝 cmp0.
- **시험**: `test_nano_slots.sh` 케이스 4(ⓐ 옛 사본 + ref 명단 v65 → rc0·빈 석·v65 카드 후보 ⓑ ref 없음 → ERROR rc1·SLOTS 0 ⓒ FT_INDEX_DIR → 명단 호출 0 ⓓ FT_TEAMS_REF 로 ref 선택) · `test_nano_close_named_wt.sh` 통과 케이스에 꼬리 SLOTS 줄 있음·WARN·cwd 명단 ERROR 0 — 옛 코드로 돌리면 둘 다 RED(꼬리 3줄 재현). 증거 `harness/evidence/r416/`.
- 범위 밖(기록만): cwd 명단(`ft_team_in`/`ft_team_cands`)을 쓰는 나머지 라이브 도구 17개 — 공유 루트에서 같은 꼴이 관측되면 도구 하나 = 카드 하나.

## 2026-10-19 — 워크트리 «옛 bin 통째 사본» 을 알아보고 설치 명령을 말한다: drift-check 메시지 · install-check STALE-COPY 행 · seat-close REJECT 에 --verdict 경로 (1.1.14)

카드 r413 · v65 쪽지 110777 · master 110781 ②·110801 ③. 공유 루트 `v6-realtime-live/.fable-team/bin` 이 shim 이 아닌 옛 통째 사본(418 파일 · LIVE_BIN·해석기 없음)이라 그 cwd 의 nano-close 입구 drift-check 가 BYZ 옛 키트 경로를 찾다 «ERROR ref 에 경로가 없음 → main 키트와 다르다» 로 막혔고, 받는 쪽은 무엇을 할지 몰랐습니다.

- **`ft-live-bin-drift-check.sh`**: 해석기 호출 «앞» 에 `--bin` 이 `*/.fable-team/bin` ∧ `../LIVE_BIN` 없음 ∧ `ft-harness-root.sh` 없음 ∧ shim 표식 파일 0 ∧ 일반 파일 ≥1 이면 `ERROR 옛 설치 사본(shim 아님 · LIVE_BIN 없음): <bin> — bash <하네스>/install.sh --apply --project <루트>` rc3(하네스 = `FT_HARNESS_ROOT` · `../HARNESS_ROOT` · 못 풀면 `<하네스>/harness` 글자). 그 밖은 바이트 불변 · drift REJECT 우회 0.
- **`ft-live-install-check.sh` / `ft_live_install_check.py`**: `--project`(기본 리포 공용 루트)와 그 `.worktrees/*` 의 `.fable-team/bin` 중 LIVE_BIN 없음 ∧ shim 0 ∧ 파일 ≥1 → `STALE-COPY <bin> files=<n>` + `HINT <bin> bash <하네스>/install.sh --apply --project <워크트리>` · PENDING rc1(`--range` 도 같음 · 읽기만).
- **`ft-seat-close.sh`**: 현역 역할 좌석 REJECT 문구 끝에 ` · 후계 없이 닫으려면 --verdict <판정번호>(R400 · 사람 승인 1건)` (동작 불변).
- **시험**: `test_live_install_check_shim.sh` 새 절 r413ⓐ~ⓒ + 픽스처를 r385 뒤 인자(`--kit`·`--path`)로 갱신(base 에서도 9 FAIL 이던 기준선) · `test_seat_close.sh` ③ 에 문구 단언. 증거 `harness/evidence/r413/test.txt`·`test-r2.txt` · base 동일 실패 5종 `preexisting-fails.txt`.

## 2026-10-19 — 범위 분류기 «전역 규칙» 이 옛 라이브 설치 사본 경로 `scripts/harness-install/` 도 FORBID 한다 (1.1.13)

카드 r412 · arch#95 재현 · 판정 1395(떨어지는 시험 = 고침 단위). 팩 이전 때 «전역 규칙» 정규식에 새 경로 `harness/kit/` 만 넣고 옛 경로가 빠져, 머리 주석(「옛·새 경로 어느 쪽이든 맞으면 FORBID」)과 어긋났고 팩 시험 절 «scripts/harness-install/ → FORBID» 가 base 부터 FAIL 1(`rc=0 out=CLASS code`)이었습니다. r411 이 code 종류를 연 뒤에는 옛 설치 경로를 다시 들여오는 세트가 code 로 대리 승인될 수 있어 실사건 전에 막습니다.

- **`autonomy_scope_classify.py`**(bin·kit 짝 cmp0): `PATH_RULES` «전역 규칙» 같은 줄에 `|(^|/)scripts/harness-install/` 1 토큰 · 줄 수 200 불변. `src/x.py` → code 그대로(오탐 0).
- **시험**: 본문 변경 0 — `test_autonomy_scope_classify.sh` ALL PASS rc0 · `test_autonomy_scope.sh` fail=0 rc0. 증거 `harness/evidence/r412/test.txt`.

## 2026-10-19 — desk 보고 스레드 뿌리 ts 를 도구가 소유한다: `reply --thread <이름>` + 승계 본문 ts 손 복사 REJECT (1.1.12)

카드 r414 · master 110781 ① · desk#20 110779(오빠 «여기는 왜 매새지 안오냐» · «다음 증류 땐 자동으로»). 뿌리 ts(10-16)가 인계서 13장에 손으로 복사돼 이어졌고, 3일 된 스레드 답글은 채널 본문에 안 보였다.

- **`kit/slack-mirror/thread_post_update.py`**: `reply --thread <이름>` — 등록부 `<FT_ROOT>/.fable-team/state/slack-threads.json`(env `FT_SLACK_THREADS`) `{"<이름>": {channel, root_ts, date, history[]}}`. 없음 ∨ 날짜(KST) ≠ 오늘 ∨ 채널 다름 → 채널에 뿌리 글 `[<이름> 보고 <날짜>]` 1건 + 등록(옛 뿌리 history) → 답글. 본문 post_guard 검사는 뿌리 글 «전»(걸리면 뿌리·등록부 불변). 등록부 손상 = raise.
- **`thread_post_args.py`**: `--ts`·`--thread` 배타 필수(둘 다·둘 다 없음 = usage rc2) · `--thread` 는 `--channel` 생략 시 등록부 채널 · `--ts` 만 = 기존 동작(기본 채널) 불변.
- **`ft-successor-open.sh` ⓐ'**: 후계 이름 `*-desk-*`|`*-planner-*` 이고 본문에 `--ts <10자리>.<6자리>` → `REJECT 본문에 슬랙 ts 손 복사(--ts …) — byz_thread_post.py reply --thread <이름> 으로(r414)` · 열기 0.
- **카드 편차 2**: reply 인자는 실제 위치인 `thread_post_args.py` 를 고쳤다(설치 `~/.hermes/scripts` 3 파일) · 시험 가짜 전송은 `FT_SLACK_POST` 주입 대신 기존 `--slack-base` 로컬 가짜 서버(제품 코드에 시험 전용 경로 0).
- **시험** `tests/test_thread_reply_named.sh` ⓐ~ⓔ 11 PASS · 기존 `test_successor_open.sh`·`test_index_move_slack.sh` rc0 · pytest thread_post·post_guard 62 passed. 증거 `harness/evidence/r414/test.txt`.

## 2026-10-19 — 범위 사전 승인에 종류 code 를 연다: 시험 통과 세트만 · code-max 안 (1.1.11)

카드 r411 · 판정 2326(오빠 «자율 개선두건 진행») · planner 110362 · master 110379 ②. 자율 ON 중 코드 세트 병합이 «앞 착지가 main 을 옮김 → 다음 PR head 바뀜 → 승인 sha 어긋남 → 오빠 재승인 h» 로 줄줄이 멈췄습니다(#1933→#1934 · h104). `approve-scope` 종류가 docs·ff·revert 뿐이라 코드 세트는 매 sha 오빠 손 1줄이었습니다.

- **approve-scope**(오빠 `!` 전용 그대로): `--classes …,code --code-max <1~max>` — code 가 있으면 `--code-max` 필수(없음·0·max 초과 = REJECT) · code 없이 `--code-max` = REJECT · grant 줄·grants.audit·슬랙 1줄·출력에 `codemax=` 칸. 옛 grant 줄(codemax 없음)은 그대로 읽힘(code 0 = 닫힘). 기본값 불변(h119 code_merge=off) — 오빠가 code 를 적을 때만 열린다.
- **scope-approve `--card <카드.md>`**: 분류기가 `CLASS code` 면 ①카드 마지막 `세트: <A> · 시험: … rc=0 · 이슈: 0` ②`ft-nano-evidence-check.sh <카드> --repo ROOT --ancestor-of <sha>` rc0 ③A≠sha 면 `ft-approval-equiv.sh A <sha>` EQUIV — 셋 다일 때만 승인 줄(`approve-merge <sha> <A> <epoch>` 불변)을 쓴다. 그 밖 = `SCOPE-REJECT`(쓰기 0). code 건수(docs 와 별개) 도달 = 기존 «건수 도달» 과 같은 정지. 원장 5번째 칸 `evidence=<카드>@<A>` · 출력 `code=n/max`(+ `equiv=<A>`). 새 `ft-autonomy-scope-code.sh`(source 전용). 분류기 FORBID(DDL·배포·키·과금·의존·전역 규칙)는 code 에도 그대로.
- **시험**: `test_autonomy_scope.sh` 새 절 ⓐ~ⓔ(임시 origin+clone 실 git · 실 evidence-check·approval-equiv · 분류기만 스텁) + 기존 절 갱신(code REJECT → code-max 검사 · tamper 꼴) — 134 PASS.

## 2026-10-19 — freeze 훅이 «병합이 가져온 그대로» 인 하네스 파일은 세지 않는다: harness-freeze-gate MERGE_HEAD 대조 (1.1.10)

판정 2323 · 카드 r407 · v65 master#209 [HIL] 110183. 옛 가지에 origin/main 을 병합할 때 충돌을 손으로 풀고 `git commit` 하면, main 이 r386 에서 지운 하네스 877 파일이 staged «이름»으로 잡혀 REJECT 됐습니다(우리 손 0). 충돌 없는 병합은 git 이 커밋까지 끝내 훅을 안 타므로 같은 병합이 충돌 유무로 갈렸습니다.

- **`harness/kit/hooks/harness-freeze-gate.sh`**: MERGE_HEAD 가 있으면 HIT 경로마다 staged 상태(stage 0 블롭)와 MERGE_HEAD 상태를 대조해 같으면 제외 — 같은 블롭 · ★둘 다 없음(main 의 삭제 그대로)★ 포함. 작업 트리 diff(`-a` 등)에 든 경로 · 미해소(stage≠0) · git 을 못 읽음 = 제외 0(그대로 REJECT). 남은 HIT 만 «건드린 파일 N개» · 메시지 끝 `(병합 중 MERGE_HEAD 와 같은 상태(블롭·삭제) M개 제외)`. MERGE_HEAD 없으면 출력 바이트 불변. freeze 표식·4폴더 목록 불변.
- **카드 편차 1**: 카드는 «둘 다 못 읽으면 제외 0» 이었으나 실제 사건(110183)의 877 파일이 전부 main 쪽 삭제(D)라 그 규칙으로는 그대로 REJECT — 삭제는 «둘 다 없음 = 같은 상태» 로 제외한다. 손 삭제(MERGE_HEAD 에는 있는 파일)는 REJECT(시험 ⓓ).
- **시험** `test_harness_freeze_gate.sh` 새 절: ⓐ 충돌 손 해소 뒤 commit(추가·삭제 그대로) 통과 ⓑ 손댄 하네스 파일 1개만 REJECT + 제외 표기 ⓑ' 작업 트리만 손댐 + `-am` REJECT ⓓ 손 삭제 REJECT ⓒ MERGE_HEAD 없음 = 고치기 전 훅과 stderr 바이트 동일. 증거 `harness/evidence/r407/test.txt`(실사건 재현: 현행 훅 877개 REJECT → 새 훅 rc0).

## 2026-10-19 — 공유 루트 cwd 에서 v65·lecture 카드 spawn 이 «팀 명단 없음» 으로 끊기던 것을 고친다: 명단 = ref · 폴더 = 호출 워크트리 실재 1개 (1.1.9)

카드 r406 · planner 판정 2318 · master 110115 · arch#94 재현(`ERROR v65 은 팀 명단(TEAMS.md)에 없다 / REJECT … 선언된 정본 없음: /GOAL-LEDGER-v65.md`). 팀 폴더 전환은 main 에만 착지했는데 lint·spawn 이 «호출 워크트리의 design/TEAMS.md» 를 읽어, 명단이 옛 것인 공유 루트(feat/v6-realtime-live)에서 spawn 이 3회 REJECT 됐습니다.

- **lib**: `ft_team_file_ref <루트> <팀> <파일> [<ref>]` — `ft_team_cands_ref`(R400 r3) 후보 폴더 중 <파일> 이 «실재하는 정확히 1개» · 명단 못 읽음·후보 0·2+ = stderr ERROR(ref·후보 경로) rc1. `ft_team_has_ref` — `ft_team_has` 를 ref 명단으로(못 읽음 rc2). ref 기본 = `FT_TEAMS_REF` 또는 `origin/main`. `ft_team_in` 의미는 그대로(다른 도구 영향 0).
- **ft-index-lint.sh**: 기본 골 원장(`default_ledger`) = `ft_team_file_ref <ROOT> v65 GOAL-LEDGER-v65.md` (`FT_GOAL_LEDGER` 명시가 먼저) · 판정 원장 pathspec = ref 명단의 planner 꼴 + 쌍둥이(루트 상대).
- **ft-nano-spawn.sh**: 발주 본문 SEATBELT-README = `ft_team_file_ref <WT> v65 SEATBELT-README.md` (`FT_SEATBELT_README` 명시가 먼저 · 실재 0·2+ = REJECT) · planner 빈 카드 판정 = `ft_team_has_ref`.
- **시험**: 새 `test_team_roster_ref.sh`(ⓐ공유 루트 꼴 dry-run PLAN·lint OK ledger=꼴1 ⓑref 못 읽음 ⓒ후보 0 ⓓ후보 2 → REJECT ⓔ보통 워크트리 불변·명시 env 우선 · 옛 코드에서 13 FAIL). 픽스처 갱신: origin/main ref 없는 임시 리포는 `FT_TEAMS_REF=HEAD`, 발주 README 실재(dead_seat_resume·raised_seat·planner_nano_path·team_literal_paths2·nano_spawn_base_sha·branch_collision·rollback) · `test_nano_spawn_teamset_cap.sh` 픽스처에 `FT_ROOT`·comm 폴더(main 에서도 9 FAIL 이던 기준선).

## 2026-10-19 — 라이브 bin 의 ft-mbox 가 우편함을 못 찾던 것을 고친다: cwd 리포 루트 comm · doorbell 이 우편함을 명시 (1.1.8)

카드 r403 · master 109989(급) · planner 109978 · desk 109974. r385 라이브 bin 전환 뒤 `~/.claude/fable-team/live/<v>/bin/ft-mbox.sh` 는 스크립트 조상에 `.fable-team` 이 없어 어느 cwd 에서 불러도 `NO_MAILBOX_ROOT` rc2 였고, doorbell 이 그 경로로 `recv` 줄을 주입해 받는 좌석도 같은 실패가 났습니다.

- **루트 순서(`ft-mbox.py` · `ft-mbox.sh` `_mbox_dir`/`_seats_json` 같은 걸음)**: ①`FT_MBOX_DIR` ②스크립트 조상 `.fable-team`(옛 설치 꼴 · 불변) ③cwd `git rev-parse --git-common-dir` 부모의 `.fable-team/comm` 이 «이미 실재» 할 때만 ④`NO_MAILBOX_ROOT` rc2 + 「cwd 공용 루트 <경로> 에도 comm 없음」. 우편함 생성은 ①② 만(F4).
- **doorbell**: `[발주 #N] FT_MBOX_DIR=<이 send 가 쓴 comm 절대경로> bash <bin>/ft-mbox.sh recv <to> — …` — 받는 좌석 cwd 무관 · 머리 `[발주 #N]` 첫 토큰 불변(ft-send-verified 영향 0).
- **시험**: 새 `test_mbox_root_resolve.sh`(ⓐ명시 env ⓑcwd 워크트리→리포 루트 comm·sh/py 같은 루트 ⓒ/tmp→rc2·생성 0 ⓓdoorbell 줄 글자·/tmp 실행 READ ⓔ옛 꼴 불변).

## 2026-10-19 — 팀 폴더 이동 뒤 옛 경로에 새 파일을 만들지 못하게 막는다: old-team-path-new-file-gate (1.1.7)

판정 2294 ⓑ(planner 쪽지 109888 «옛 경로 새 파일 DENY») · 카드 r402. 12팀 폴더가 `design/teams/<팀>/`(꼴2)로 옮겨진 뒤에도 쌍둥이 역호환이 «읽기» 뿐 아니라 «쓰기» 까지 열려 있어, 옛 `design/<팀>/` 에 만든 카드·발주서가 두 폴더로 흩어졌습니다.

- **새 훅 `harness/kit/hooks/old-team-path-new-file-gate.sh`**(PreToolUse:Write|Edit|Bash): 대상 경로 = Write·Edit `file_path` · Bash 의 `>`·`>>` 대상과 `cp|mv|install|tee|touch` 마지막 인자(따옴표 밖). 대상이 «없는 파일» 이고, 그 경로가 속한 git 루트의 `design/TEAMS.md` 에서 그 팀 칸이 꼴2 이면 deny + `바른 경로: design/teams/<팀>/…` 1줄. 기존 파일 편집·읽기·리포 밖·꼴1 팀·꼴3 팀·명단 밖 폴더는 통과. 입력 파싱 실패·명단 없음·`ft-team-lib.sh` 못 찾음 = 허용 + stderr WARN 1줄(fail-open). 팀 이름 글자 0(`ft_team_rel` · `$FT_BIN` → `~/.claude/fable-team/live/*/bin` 최신).
- **설치**(`harness/install.sh`): 홈 훅 목록 `HOME_HOOKS`(harness-freeze-gate · old-team-path-new-file-gate)를 `<home>/.claude/hooks/` 로 cp -p → cmp(같으면 건너뜀) · dry-run 에 `HOOK` 줄 · apply 에 `HOOKS copied= same=` 줄. settings.json 등록은 별도(master).
- **시험**: 새 `test_old_team_path_deny.sh`(카드 ⓐ 6절 + 리포 밖·꼴3·절대경로·명단 밖 · Bash `>`/`>>`/tee/touch/mv deny · 읽기·따옴표 글자·옛→새 cp·기존 덮어쓰기·`>&2` 통과 · fail-open 3 · live 최신 lib).

## 2026-10-19 — 좌석 닫기 도구가 «못 닫고 CLOSED» 를 찍지 않는다: 원장 명단은 origin/main · 명부·원장 fail-closed · 다른 리포 좌석 안내 (1.1.6)

판정 2307 ①② · planner 109823(v65·lecture 나노 닫기가 원장 워크트리의 옛 TEAMS.md 때문에 REJECT) · 109839(airag 옛 판 nano-close 가 명부·원장 없이 «CLOSED» 출력 · 세션 잔존 — 1.1.4 도 같은 네 자리) · master 109876(다른 리포 좌석 닫기가 «NOROW ↔ 원장 루트 못 풂» 순환).

- **기본 원장 = «명단은 ref · 폴더는 원장 워크트리»**(`ft-nano-close`): `FT_NANO_LEDGER` 가 없으면 팀 명단을 `FT_TEAMS_REF`(기본 `origin/main`)의 `design/TEAMS.md` 에서 읽고, 명단 꼴·쌍둥이 후보 중 원장 파일이 실재하는 «정확히 1개» 만 씁니다(`INFO 원장 ← <경로> (명단 <ref>)`). 0개·2개·명단 못 읽음은 REJECT(후보 목록). 새 함수 `ft-team-lib.sh` `ft_team_cands_ref <루트> <팀> [<ref>]` — `ft_team_in`·`ft_team_cands` 변경 0.
- **fail-closed 4곳**(`ft-nano-close`): ①명부 파일 없음 ②원장 없음/쓰기 불가 → 입구 REJECT(tmux 조회·변경 전) ③명부 pop 실패 → REJECT(사건 원장 abort) ④원장 append 실패 → FAIL — 어느 경우도 «CLOSED» 줄 0. ★원장은 이미 있는 파일만 씁니다(첫 append 로 만들지 않음).★
- **다른 리포 좌석 안내**(`ft-seat-close`·`ft-seat-retire`): NOROW·원장 루트 실패·«행 없음» 안내에 `FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json` 한 줄(지금 인자로 채움 · 자동 탐색 0 · 동작 변경 0).
- **시험**: 새 `test_nano_close_fail_closed.sh`(ⓐ 명단 origin/main + 쌍둥이 1곳 → CLOSED ⓑ 후보 2 ⓒ 0 ⓓ ref 없음 ⓔ 명부 없음 ⓕ 명부 쓰기 실패 — 고치기 전 코드는 9 FAIL) · `test_seat_close.sh` ⓖ(FT_ROOT + --seats 다른 리포 → CLOSED-ROLE · 원장 그 루트) ⓗ(--seats 없이 → 안내 · rc3) · `test_nano_team_env.sh` 픽스처에 원장 파일 미리 생성 + 옛 이름 좌석 2회 원장 명시.

## 2026-10-19 — 판정 번호로 역할 좌석을 닫는다: ft-seat-close --verdict · ft-seat-retire --record-only --verdict (1.1.5)

planner 판정 2304(오빠 승인 1건)가 현역 역할 좌석 17석을 «재개 기록 → 명부 칸 비우기 → kill» 로 닫으라 했는데, 기존 도구로는 0석이었습니다(master #109747).
`ft-seat-close` 는 `_*` 칸 값(현역)을 거절했고, `ft-seat-retire --record-only` 는 `_replaced_by` 가 있어야만 기록했고, 다른 리포 좌석은 이 리포 명부에 행이 없었습니다.

- **`ft-seat-retire <구> --record-only --verdict <번호>`**: `_replaced_by`·R296 ⓑⓒ 없이 결속(`ft_seat_bind`)만으로 재개 기록(`retired_by = verdict <번호>`) · 행 없음은 R296 ⓐ(`_*` 칸 값이면 REJECT)만 · 명부 쓰기 0 · 출력 꼴 그대로(`RESUME ok` | `NORECORD`).
- **`ft-seat-close <좌석> --verdict <번호> --reason …`**: ⓪실행 세션 자신 REJECT ①재개 기록 실패 = `HELD` rc 3(명부 쓰기 0 · kill 0) ②행 있음 → stop-ready 표기 + `_closed.verdict` + 어느 명부든 값 == 좌석인 최상위 `_*` 칸을 `""`(파일마다 `.bak-close-<ts>` · tmp→mv) · 행 없음 = `NOROW` rc 3(kill 0 · 그 리포 루트에서 다시) ③계보 검사 건너뜀 → 태그 해제 → kill → `CLOSED-ROLE … kill=ok` + 원장 `<데이터 루트>/.fable-team/state/seat-close-verdict.log` 1행.
- **codex 좌석 재개 기록**(master #109793 — 실측 da-codex#4 «세션 파일 0개» HELD): 결속 판정기 `ft_seat_bind.bind` 가 claude 세션 파일이 0개일 때 pane 자손(깊이 ≤4) 중 실행 주체 codex 가 연 `~/.codex/sessions/**/rollout-*.jsonl` «정확히 1개» 로 결속(첫 줄 session_meta id == 파일명 끝 · 시작시각 ≤ mtime) · 기록 `engine=codex` · model = argv `-c model=` → rollout `turn_context` · `resume_cmd = codex <원래 인자> resume <id>`(zombie-clean resume 은 claude 기록만 받는다 — 변경 0 · `--expect` 변경 0).
- **`ft-nano-close` 카드 탐색**(master #109792 — r385#0 «⑥카드 못 찾음»): 명부 index 경로에 카드가 없으면 같은 `indices` 뿌리의 형제 폴더(대기·진행·완성)에서 같은 파일명이 정확히 1개일 때만 그 카드 + `INFO 카드 위치 ← <경로>` · 0·2+ 는 REJECT 그대로(`형제 N개`) · 명부 쓰기 0.
- `--verdict` 없는 호출은 동작 그대로 · **시험**: `test_seat_close.sh` ⓑ~ⓕ·usage(가짜 tmux · retire 스텁) · `test_seat_retire.sh` ⑮(현역 행·행 없음·`_*` 칸·결속 실패·usage) · ⑯(가짜 codex 트리: 정상·rollout 2개·0개·id 불일치) · `test_nano_close_named_wt.sh`(형제 1개 → CLOSED · 2개 → REJECT).

## 2026-10-19 — 설치본에서 보드 루트를 풀고, 하네스가 리포 밖일 때 범위 대조를 통과시킨다 (1.1.4)

1.1.3 설치본으로 전환한 뒤 실제 실행에서 두 곳이 막혔습니다(master #109675).
나노 닫기·spawn 이 «사건 원장 prepared 실패» 로 거절됐고(`ft_board_env.ft_root` 가 `git -C <설치본 bin>` — git 밖), 카드 완성 이동·착지가 `INSTALL ERROR` 로 막혔습니다(`ft-live-install-check --range … --repo <BYZ>` 가 «하네스 루트가 --repo 밖» 이면 항상 ERROR).

- **보드 루트**(`ft_board_env.ft_root`): `FT_ROOT`(그 값 그대로) → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 `git -C <bin>` 공용 루트 → RuntimeError(사유에 cwd·경로). 호출 12곳 변경 0.
- **범위 대조**(`ft_live_install_check.resolve_kit`): 하네스 루트가 `--repo` 밖이고 `--kit` 가 없을 때 — `--range A..B` 가 건드린(ACMR) 옛 하네스 경로(`scripts/fable-team-bin/` `scripts/harness-install/` `tools/comm-canonical/` `tests/harness/` `kit/` · 팩 꼴 `**/harness/kit/**`) 파일이 0 이면 `OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)` rc0, 1개라도 있으면 ERROR(파일 목록) rc3. `--all` 은 ERROR 그대로.
- **시험**: `test_installed_root.sh` ⓔ 절(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · 설치본 `ft-sheet-events.sh` git 밖 ERROR · spawn 경로 key+prepare rc0 · 임시 HOME 쓰기 0) · 새 `test_install_check_repo_outside.sh`(하네스 0 → OK · `^..`·`--ref` 호출 꼴 · 하네스 1 → ERROR+파일명 · 팩 꼴 키트 1 → ERROR · 삭제만 → OK · `--all` → ERROR).

## 2026-10-19 — 설치본에서 «파일 위치 조상 탐색» 없이 루트·comm 을 푼다 (1.1.3)

1.1.2 설치본(`~/.claude/fable-team/live/1.1.2/bin` · git 밖)으로 LIVE_BIN 을 바꾸자 골 표가 «루트 없음» 으로 멈춰 쪽지 가드가 발주·보고를 막았고, LIVE_BIN 을 되돌렸습니다.
골 표 루트(`ft_goal_ledger.find_root`)와 형제 `../comm` 이 «이 파일 위치의 조상» 에 기대고 있었는데, 설치본은 `<버전>/{bin,templates,HARNESS_ROOT}` 뿐이라 둘 다 없었습니다.
(1.1.1 데이터 루트 해석기 · r386 팀 경로 지도 fallback 과 같은 «설치본 루트» 묶음입니다.)

- **골 표 루트**(`ft_goal_ledger.find_root`): `FT_ROOT` → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 파일 위치 조상 → ERROR.
- **comm**: 해석기에 `ft_comm_dir`(= `$(ft_data_root)/.fable-team/comm` · 옛 설치 꼴이면 옛 `$HERE/../comm` 과 같은 곳 · 없으면 ERROR) 1함수 추가 — 기존 함수 변경 0.
  쓰는 곳 17: harness-info · hil-ask · hil-answer · mbox-bridge(mbox·mbox-v2) · plan-handoff · tick · disk-alarm · issue-create-pair · launchd-check · magazine-check ·
  resource-reclaim · seat-live · secret-scan · spawn-hold · tick-team · send-verified · context-monitor(각 도구의 env 가 먼저).
- **데이터 루트 `../..`**: install-pending · seat-handover → `ft_data_root` · `ft_penalty.root` → 리포 공용 루트 순서(ft_repo_root 와 같음) · `ft_op_token.secrets_dir` → env → 옛 꼴 → cwd 리포의 `.fable-team/secrets` → ERROR.
- **시험**: `harness/tests/test_installed_root.sh`(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · tick·hil-ask mbox 경로 · git 밖 ERROR + 임시 HOME 쓰기 0 · 실제 BYZ cwd 골 표 rc0).

## 2026-10-19 — 설치·실행 위치 전환 준비: 팩에서 바로 설치하고 BYZ 하네스 폴더를 얼린다 (1.1.2)

1.1.1 로 도구가 git 밖 설치본에서도 데이터 루트를 풀게 됐지만, 키트 글자·설치 입구는 아직 BYZ 리포 안 옛 위치(`scripts/fable-team-bin` 등)를 전제했습니다.
이 판은 팩 하네스만으로 설치·대조가 되게 하고, 전환 동안 BYZ 쪽 하네스 커밋을 막는 장치를 더합니다(카드 r385 · LIVE_BIN 1줄 전환은 master).

- **경로 글자**: `harness/bin`·`harness/kit` 의 `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical` → `harness/bin`·`harness/kit`·`harness/comm`(주석·안내문 포함 0건).
- **설치**(`harness/install.sh --apply --project <루트>`): `--project` 필수(cwd 추론 0 · 없으면 rc2 쓰기 0) · 키트 `bin`·`templates` 를
  `<home>/.claude/fable-team/live/<version>/` 에 cp+cmp · `<version>/HARNESS_ROOT` 1줄(= `ft_harness_root` ② 지도) · 설치본 shim 으로 프로젝트 `LIVE_BIN`·`LIVE_ROOT`(있으면 보존) ·
  2회째 복사 0 · 끝에 «되돌림 1줄»(LIVE_BIN 이전 값) 출력.
- **대조**: `ft-live-install-check.sh --kit/--project` · 하네스 bin launchd 항목에 `WorkingDirectory`·`FT_ROOT` 없으면 `NOROOT` · shim·live-install `--repo/--path` 기본 = 하네스 코드 루트.
- **freeze 가드**(`harness/kit/hooks/harness-freeze-gate.sh` · PreToolUse:Bash): 대상 저장소 공용 루트에 `.fable-team/state/harness-freeze` 가 있으면
  `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical`·`tests/harness` 를 건드리는 커밋을 REJECT(카드 `design/harness` 는 r386 이전까지 BYZ 에서 커밋 — 막지 않음)(staged · `-a`/pathspec 이면 작업 트리도) · 표식 없으면 통과.
- **홈 훅 5**(autonomy-interview-gate · autonomy-merge-guard · gh-issue-author-guard · merge-head-gate · tracked-bin-call-gate): 옛 위치 후보 대신 루트 shim · LIVE_BIN · `$FT_HARNESS_ROOT/bin`.
  홈 적용분은 `harness/evidence/r385/home-hooks.patch`(+ freeze 가드 새 파일 · dry-run 원문 같은 폴더) — 적용은 master.
- **시험**: `harness/tests/test_harness_freeze_gate.sh`(표식 없음 통과 · staged/-a/--all/cd/-C/워크트리 REJECT · 4폴더 밖·메시지 글자 통과 · 해제).

## 2026-10-19 — 데이터 루트 해석기 2종: 설치본이 git 밖이어도 루트를 조용히 잘못 풀지 않는다 (1.1.1)

라이브 설치본을 `~/.claude/fable-team/live/<version>/bin`(git 밖)으로 옮기면, 키트 도구 35곳이 «자기 위치»(`git -C $HERE` 공용 루트 · `$HERE/../..`)로
데이터 루트를 풀다 `~/.claude/fable-team/live` 로 풀렸습니다 — 자율 상태·spawn 정지 파일·자원 표·press 허가를 못 보는 회귀입니다.
실측해 보니 루트가 두 종류였습니다: 리포 공용 루트(BYZ 메인 `.fable-team/state`)와 라이브 루트(`LIVE_ROOT` · v6 `.fable-team/state`).

- **해석기**(`harness/bin/ft-harness-root.sh` · 키트 짝 같음): `ft_repo_root` = 옛 설치 꼴(`*/.fable-team/bin`)이면 `git -C $HERE` 공용 루트(없으면 `$HERE/../..`)
  → cwd git 공용 루트(`.fable-team/` 있을 때) → ERROR · `ft_data_root` = `FT_ROOT` → cwd git 공용 루트의 `.fable-team/LIVE_ROOT` 1줄 → 옛 설치 꼴 `$HERE/../..` → ERROR.
  어느 쪽도 못 풀면 rc≠0 로 멈춥니다(조용한 후퇴 0). 각 도구의 기존 env(`FT_RES_ROOT`·`FT_SECRET_SCAN_ROOT`·`FT_ROOT`)는 그대로 우선.
- **리포 공용 루트 묶음**: spawn-hold · resource-gate/watch/sample/cause/reclaim · disk-alarm · disk-census · scratch-repo · secret-scan · fp-run ·
  issue-close-check · weekly_review · board-publish · sheet-publish/verify · gh-tank-comment-edit · gh-tank-edit-bak · idle-wake · measure-net ·
  seat-request · seat-live · seats-lint · tick-line · successor-open(자원 문지기 루트).
- **라이브 루트 묶음**: autonomy · autonomy-start · proxy-decide · resume-cmd · resume-attempt · press-gate · press-permit.
- **드리프트 입구**(nano-spawn · nano-close · tick): 설치 꼴에 `*/fable-team/live/*/bin` 추가 · `--repo` 생략 → drift-check 기본 = 하네스 코드 루트(`FT_HARNESS_ROOT` · `<버전>/HARNESS_ROOT`)의 키트.
- **launchd 템플릿** weekly-review · secret-scan: `WorkingDirectory` 로 cwd 루트를 준다.
- **시험**: `harness/tests/test_harness_root.sh`(git 밖 설치본 + cwd git 밖 → ERROR · 임시 HOME 쓰기 0 / cwd 워크트리 → 공용 루트·LIVE_ROOT / env · 옛 설치 꼴 회귀 0).

## 2026-10-18 — harness 합류: BYZ 하네스 6경로를 이력째 팩으로 (1.1.0)

하네스 실행 도구·키트·통신·카드 원장·시험·옛 증거가 BYZ-Agents 리포에만 있어 패치·버저닝·산출물 관리가 두 레포로 갈렸습니다.
6경로를 커밋 이력째 `harness/` 로 옮겼습니다(판정 2270 · BYZ 711199fd62 기준 · BYZ 삭제는 다음 단계).

- **레이아웃**(`harness/`): `bin/`(←`scripts/fable-team-bin` 227) · `kit/`(←`scripts/harness-install` 459) · `comm/`(←`tools/comm-canonical` 31) ·
  `design/harness/`(←`design/teams/harness` 756 · 옛 `design/harness` 이력 포함) · `tests/`(←`tests/harness` 224 + `tests/scripts` 하네스 시험·도우미 47) ·
  `evidence/state-v6/`(←`.fable-team/state/v6-*` 88). `skill/` 은 그대로 — 규칙·참조는 skill, 실행 도구는 harness.
- **버전**: `manifest.json` `version` 이 유일한 출처 — 이 절부터 0.1.0·1.0.3 어긋남을 1.1.0 으로 통일. 팀 폴더 틀 버전(`harness/kit/fable-team/templates/team/VERSION` 1.0.0)은 별개 의미라 그대로.
- **설치 입구**(`harness/install.sh`): manifest version 을 읽어 `~/.claude/fable-team/live/<version>/` 와 프로젝트 `LIVE_BIN`·`LIVE_ROOT` 계획을 출력(지금은 `--dry-run` 만 · 실제 설치는 다음 단계).
- **재배치 대조**(`harness/tests/test_pack_relocation.sh`): 경로 표 5행마다 BYZ 기준 sha 와 팩의 파일 수·sha256 목록이 같고 표 밖 파일 0 · 이력 커밋 수 대조.

## 2026-10-02 — 단일 세트 · 나노 생애 · 오래된 나노는 루트부터 (1.0.3)

BYZ-Agents v65 에서 09-25 카드를 재대조 없이 10-02 코드에 집행하고, 옛 sha worker 로 돌린 A/B 를 근거로 HEAD 를 덮어쓸 뻔했습니다(미랜딩 nano 277/590 · 나노 브랜치 221커밋 뒤처짐).

- **규칙**(`references/SEATBELT.md` §6-3): 단일 세트 시험 · 나노 생애 ①~⑤(최신 루트 병합→시험→이슈 확인→squash) · 랜딩 = 라이브 1회까지 · 방치 0.
- **스크립트** `scripts/ft-nano-freshness.sh`(읽기 전용): base·루트 뒤처짐·겹침 파일·미랜딩 패치·dirty → FRESH/STALE/STALE-OVERLAP/LANDED.

## 2026-10-02 — 워크트리 위생: Serena project.yml 커밋 금지

BYZ-Agents 의 모든 워크트리에서 Serena 가 `.serena/project.yml` 을 자동 갱신해 세션마다 modified 로 떴습니다.
추적 해제 + gitignore 를 BYZ 가 적용했고(4305b6925), 같은 규칙을 팩의 플레이북에 넣었습니다.

- **규칙**(`references/orchestration-playbook.md` «워크트리 위생»): project.yml 커밋 금지 · Serena 는 본인 워크트리 절대경로로 활성화.

## 2026-10-01 — checkpoint 계약: 시험·press 를 돌린 워커가 그 회차의 tester·checker

BYZ-Agents v65 에서 과금 랜딩이 폴리싱·완료 말풍선을 끊는 회귀를 냈는데, 측정 워커가 자기 측정 조건만 보고
6회차를 VALID 로 넘겼고 사용자가 화면을 보고 잡았습니다. 수정 범위가 넓고 시스템이 커서 «한 곳을 고치면 다른 곳이
끊기는» 일이 잦기 때문에, 랜딩마다 BTS 4축 + poller 고정 칸을 도구로 확인하는 계약을 팩에 넣었습니다.

- **계약**(`references/SEATBELT.md` §6-2): 시험·press 를 돌린 워커 = 그 회차 tester·checker. 회차마다 프로젝트가 선언한
  checkpoint 를 돌려 고정 칸 표를 보고에 첨부 · 경보(exit 3)면 VALID/완료 보고 금지 → 4축 정리 → arch(+DA) 처방 →
  같은 워커 수정 → 재실행.
- **도구**(`scripts/ft-checkpoint.sh`): 프로젝트 `.fable-team/checkpoint.json`(명령·경보 exit·필수 칸)을 실행 ·
  exit 0 정상 / 3 경보 / 4 표·칸·명령 실패 / 5 미설정(무음 통과 금지).
- **닫기 조건**(`scripts/ft-nano-close.sh` ④): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no. 미설정 프로젝트는 경고만.
- **적용**(`references/update.md`): 프로젝트별 checkpoint.json 예시 3줄.

## 2026-09-30 — 승계 6단계 + 지시 원장 트리 + 누락 전수 점검

사용자 지시(BYZ-Agents v65 master#86 작업 방법 공유)를 베이스에 반영했습니다. 승계 때 후계에 상태·할 일이
안 넘어가고, 범위 한정으로 닫힌 행 아래의 사용자 지시가 통째로 누락되던 문제(16건 중 8건)에 대한 규율입니다.

- **승계 6단계**: 스냅샷 커밋 → 후계 스폰 → 상태·할 일·컨텍스트 요약 mbox 재송신 → 후계 응답(골 대조) recv →
  뉴스·크론이 후계로 가는지 확인 → 구 좌석 유휴. 후계 발주문에도 6단계를 적습니다.
- **트리 = 골 원장 행 + 사용자 지시 원장 열린 항목**: 행을 범위 한정으로 닫을 땐 하위 지시 항목의 완성 전/후 이관 줄 필수.
- **승계 첫 일 누락 전수 점검**: 지시 × 카드 × 닫힘 sha 대조, «카드 없음 + 증거 없음» 맨 위.
- **설명은 사용자가 겪는 일로**, **아키텍처 영향 사건은 즉시 아키텍처 원장에 기록**.

반영 위치: `skill/SKILL.md`(운영 규율 5~7), `skill/templates/rules/orchestration.md`(컨텍스트 증류 절 — 프로젝트로 복사되는 정본),
`skill/references/context-management.md`(§2.5 승계 6단계).

## 2026-07-28 — 문제해결 표준 체인 + checker 4축 실측 규칙

역할 경계를 두 군데 조였습니다. 출처는 BYZ-Agents v6-realtime-live 커밋 `2216ffdc`(FB_Master#88 규율 업데이트).

- **문제해결 표준 체인**: `checker → 오케(Master) → architect → (DA) → 오케(Master) → impl`.
  checker는 실측·정리만 하고 판정을 붙이지 않습니다. 오케(Master)는 checker 정리에 의심 방향을 얹어
  architect에 넘기되 **그것이 관찰이지 판정이 아님을 명시**합니다. 원인 규명·설계 판정은 architect가
  하고 **DA 소환 여부도 architect가 정합니다**(DA는 architect에 회신). 최종본 라우팅은 다시 Master.
  - 오케(Master)가 **하지 않는 것 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환.
  - **DA 상시 대기 금지** — `DA approve loop` / `DA review`로 필요할 때만. 대기 유지 자체가 왕복과
    조건 증식을 만듭니다(실증: 조건 7항 증식 → 라이브 지연).
- **checker 4축 실측**: FE 콘솔 / poller·DOM / worker(서버 로그) / durable 저장소를 전부 봅니다.
  FE 미확인 전 "처리 실패" 판정 금지, poller·DOM 미확인 전 "출력 없음" 판정 금지, 복수 호출은 전부
  나열하고 실패 지표가 몇 번째인지 명시. **사용자가 눈으로 본 것과 분석이 어긋나면 분석이 틀린 것**
  — 그때는 안 본 축부터 봅니다.

반영 위치: `skill/SKILL.md`, `skill/references/rapid-iteration-loop.md`(정본 — 역할 체인·4축·안티패턴 11~13),
`skill/templates/rules/orchestration.md`, `skill/templates/session-prompts/{checker,architect,da-codex,da-cursor}.md`,
`skill/references/agent-templates/{ft-checker,ft-architect,ft-da,ft-da-cursor,ft-da-claude}.md.tpl`.

## 2026-07-11 — v3 업그레이드 (tmux 기반 전면 개편)

fable-team이 각 에이전트를 tmux 세션으로 직접 띄우고, 서로 메시지를 주고받고, 작업이 끝나면 스스로
정리하도록 구조를 전면 교체했습니다. 여기에 더해 세션 압축(증류) 시 모델의 확장 컨텍스트(1M)/추론
강도 설정이 유실되던 문제 수정, 전문가(fable-5) 브레인의 전체 구현 재검토, 대규모 동작 검증(23개
시나리오) 중 실측으로 발견한 버그 다수를 함께 처리했습니다.

- 요약 문서: [docs/artifact/2026-07-11-v3-upgrade-summary.html](docs/artifact/2026-07-11-v3-upgrade-summary.html)
- 설계 원문: [.fable-team/designs/roster-v3-design.md](.fable-team/designs/roster-v3-design.md)
- 구현 전체 검토 보고서: [.fable-team/state/v3-upgrade-design/implementation-review-fable5.md](.fable-team/state/v3-upgrade-design/implementation-review-fable5.md)
- 진행 원장(전 과정 기록): [.fable-team/state/state.md](.fable-team/state/state.md)
