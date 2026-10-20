# Changes

## 2026-10-20 — 시험 임시 bin 짝 누락(r516 묶음 ⑥) 5개 고침: 키트 bin 통째 복사 도우미 `tests/lib/kit_bin_copy.sh` + 부작용 스텁 (r536 · 1.1.87)

- 사건: r535 나노 보고 — `test_wt_clean_plan_self_check.sh` 가 팩 origin/main 에서도 FAIL 13(`harness/evidence/r535/preexisting-self-check-origin-main.txt`). arch 107 실측 = 시험이 임시 bin 에 생성기 `ft-nano-close.sh` 와 형제 몇 개만 손으로 복사하는데 생성기가 그 뒤 `ft-seat-reap.sh`·`ft-team-lib.sh` 등을 더 부르게 바뀌어 «No such file · CLOSE-FAIL reap left=? rc=127». 같은 꼴 = r516 분류표 묶음 ⑥ 5개.
- 새 `harness/tests/lib/kit_bin_copy.sh <임시 bin>`: 키트 `kit/fable-team/bin` 일반 파일 전부(설치와 같은 집합) cp -p → 부작용 도구 9개(`ft-seat-reap` · `ft-opencode-reap` · `ft-leak-reap` · `ft-docker-test-reap` · `ft-seat-retire` · `ft-tmux-kill|spawn|send|distill`)를 새 `harness/tests/stubs/kit-side-effect.sh` 로 덮음(호출 1줄 로그 · `left=0 rc=0` · exit 0 · 실제 kill·tmux·reap 0) · 출력 `KIT-BIN-COPY files=N stubbed=…`.
- 시험 5: `test_wt_clean_plan_self_check`·`test_nano_succession_index`·`test_autonomy_hooks_layout`·`test_evidence_inject_scan` = 손 복사 줄 → 도우미(각 시험의 기존 가짜 tmux·cherry·lint 스텁은 그대로 · self_check 는 «스텁 reap 호출 ≥1» 단언 추가) · `test_fake_resource_env` = 파이썬 모듈 경로 `$REPO/tests/scripts` → `$HERE/scripts`(모듈은 `harness/tests/scripts/`) · `test_evidence_inject_scan` 8 = BYZ 리포에만 있던 위반 실례(#887 run.py)를 바이트 그대로 사본 `harness/fixtures/inject_scan/run-887.py`(BYZ 554e5a4873 · blob a50d41b0) 로.
- 시험: 고치기 전 5개 rc=1(FAIL 7·4·13·6·2 · `harness/evidence/r536/before-fix.txt`) → 고친 뒤 5개 rc=0(`after-fix.txt`) · 전체 셸 전·후 비교 `compare.txt`.
- 설치: 없음 — 시험·픽스처만(키트·LIVE_BIN·홈·launchd 0). 되돌림 = 이 커밋 revert.
- 범위 밖: 다른 묶음(①~⑤·⑦·⑧) · r535 시험 · 키트 코드.

## 2026-10-20 — 닫힌 나노 정리 계획이 밀리지 않게: sweep 시간 상한 안 여러 건 · 옛 판 계획 재생성 · 지운 크기·등록 없는 폴더 목록 (r535 · 1.1.86)

- 사건: 10-19 12:09~10-20 09:53 새 `.worktrees` 88개 ≈83GiB(planner 83 쪽지 119683). arch 107 읽기 전용 실측 — 대기 계획 18(막는 프로세스 0 이 17) · sweep 이 pass 당 1건(`FT_WT_SWEEP_MAX` 기본 1)이라 «이월 18~21» 상주 · 하네스 재설치마다 생성기 판이 바뀌어 옛 판 계획이 `.stale` 로 빠지고 다시 안 만들어짐(177) · `.hil` 57 · 등록 없는 폴더 59.
- `ft-wt-sweep.sh`: ①pass 1회 = 시간 상한 `FT_WT_SWEEP_BUDGET_SEC`(기본 90 · launchd 300 · 계획 1건 상한 120s 그대로) 안에서 막히지 않은 계획을 차례로 · 넘으면 «이월» · `FT_WT_SWEEP_MAX` 는 명시할 때만 건수 상한(기본 0 = 없음 · WAIT 는 안 셈) ②옛 판 계획 = 거부 전에 옆 생성기 `ft-nano-close.sh <seat> --replan <옛 계획>` 로 같은 좌석·같은 WT 새 계획 → 옛 파일 `.replanned` · `REPLAN` 1줄 · 같은 pass 에 실행(가드는 새 계획이 다시 건다) · 계보 세션 살아 있음·tmux 조회 실패 = WAIT(제자리) · 불가(WT 없음 · 가지 nano/* 아님 · --wt/--branch 계획) = 지금처럼 `.stale` + 사유 1줄 ③실행 직전 WT `du -sk`(`FT_WT_DU_SEC` 5 상한 · 그룹째 TERM · 넘김 = `?` · `<계획>.kb` 캐시) → cleaned 면 `.done` 끝 `# freed_kb=` · `<state>/wt-sweep.log` 폴더별 `freed seat= kb= wt=` + pass 줄 `… freed_kb=<합>` ④등록 없는 폴더(`<SCAN_ROOT>/.worktrees/*` 실폴더 중 `git worktree list` 에 없음) → `<state>/wt-orphans.tsv`(이름·mtime·KB · `FT_WT_ORPHAN_SCAN_SEC` 3600 간격 · du 합계 60s) 목록만 · 삭제 0 ⑤`.sh.hil` 수 → 요약 `hil_files N` · 처리 0. 요약 줄 꼬리 `freed_kb · replanned · hil_files · orphans`(값 있을 때만) · `--launchd` 로그 줄에 `replanned= hil_files= orphans= freed_kb=` 추가.
- `ft-nano-close.sh`: `--replan <옛 계획>` 진입점 — 굽힌 값 줄(SEAT·KEY·WT·PREFIX·LEDGER·FT_NANO_WIP·PLAN_ONLY·MAINREF)만 읽고 몸통은 지금 생성기 · 팀 env·드리프트·원장 해석·명부·종료조건·kill 전부 건너뜀 · rc 0 `PLANNED` · 4 WAIT · 1 REJECT 사유 1줄. 다른 경로 동작 0 변경.
- 시험 새 `test_wt_sweep_budget_replan_r535.sh`(임시 리포·워크트리 · 가짜 tmux·lsof·du·baton · 외부 호출 0 · GIT_* 0) ⓐ~ⓖ — 고치기 전 FAIL 30(`harness/evidence/r535/before-fix.txt`) · 고친 뒤 ALL PASS 50(`after-fix.txt`). `test_ft_wt_sweep_route_timeout.sh` ⓒ = MAX=1 명시 때 1건 · 기본 = 전부 · `test_wt_clean_two_stage.sh` ⓓ = 옛 판 → REPLAN(옛 몸통 실행 0 · 새 plan-ver 실행) + 재생성 불가 → STALE(변이 2 여전히 검출). 기존 시험 13개 rc0(`existing-tests.txt`) · `test_wt_clean_plan_self_check.sh` 는 팩 origin/main 코드에서도 FAILED 15(기존 RED · `preexisting-self-check-origin-main.txt` · 별도 단위 요청).
- 설치: 키트 2(`ft-wt-sweep.sh` · `ft-nano-close.sh` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · launchd 0 변경(`com.byz.ft-wt-sweep` 그대로) · 홈 0 · 되돌림 = `.bak-r535`.
- 범위 밖: 등록 없는 폴더·`.hil` 지우기(사람 경로) · 부모 잃은 시험 셸 끄기(kill = HIL) · 브랜치 삭제(HIL) · 보관본 크기 규칙(r443) · 디스크 측정(r534).

## 2026-10-20 — 오빠 큐 줄 = 번호·팀·보여준 시각 칸 + `ft-queue.sh shown|due|take|remind` · 틱이 보여준 지 1시간 넘은 대기 줄을 그 팀 master 에 [재질문] (r529 · 1.1.85)

- 사건: 오빠 큐 줄이 «언제 오빠께 보였는지» 기록이 없어 한 번 묻고 나면 아무도 다시 안 묻고, 오빠 값이 와도 그 팀이 줄을 꺼내 재개하는 길이 없다(오빠 09:2x «각팀 마스터 팀장이 큐를 보게하고 내결정 노출시간이 한시간 이상 지나면 다시 물어보고 팀장이 꺼내서 다시 진행가능해야함» · desk 26 쪽지 119482 → master 83 발주 119484 카드 ②).
- 큐 칸 셋 = 상태 칸 «뒤» `번호 | 팀 | 보여준 시각`(머리 이름으로 찾음 · 옛 7칸 줄은 셋 다 `-` 로 읽음 · 옛 줄 고쳐 쓰기 0 · 옛 머리 큐에 새 줄을 쓰면 머리·구분 행만 10칸으로). 파서 `ft_queue_state.py` 무변경(r528 시험 «상태 뒤 칸이 늘어도 그대로»).
- 새 `ft-queue.sh`(본체 `ft_queue.py` · `ft_queue_remind.py` — 200줄 한도로 나눔): `shown <qN> [--at]` 그 줄 «보여준 시각» 칸만 · `due [--team] [--min 60]` = 대기 ∧ (보여준 시각 ≤ 지금−60분 ∨ -) · 보류 ∧ 재확인 시각 지남(tag=재확인) · 끝줄 `QUEUE-DUE n= old=`(번호 없는 열린 옛 줄은 대상 밖 · 셈만) · `take <qN> --value --by --verdict` = 상태 `진행 — <master>` · 사유 끝 `오빠 값: … (판정 N)` · 출력 `RESUME <qN> team= kind= → …` · 대기·보류 줄만(이미 진행·완료 = REJECT) · `remind --rosters --mbox` = due 줄마다 그 팀 명부(`seats-<팀>.json` · `seats.json` 은 `_master` 의 `byz-<팀>-`) `_master` 에 `[재질문] qN · 보여준 지 N분 · <질문 첫 60자> · desk [인터뷰 요청] 로 다시` 1통 · 팀 `-`·명부 없는 팀 = planner `_master` · 같은 줄(번호·보여준 시각·tag) 60분 안 다시 0(`<상태>/queue-reask.json`) · 자율 ON = 쪽지 0 · `<상태>/queue-reask-morning.md` 아침 묶음 1줄(r291). 쓰기 줄 = ft-proxy-decide 와 같은 락(`<상태>/.proxy.lock`) · 한 번에 한 줄 · 같은 폴더 임시 파일 → rename · 실패 = ERROR rc≠0(조용한 통과 0) · mbox send 7초 + 재시도 1회.
- `ft-proxy-decide.sh`: QUEUE 줄 쓰기 = `ft-queue.sh add` 하나(번호 q<최대+1> · 팀 = `--team`(새 인자) → `--card` 경로 `design/[teams/]<팀>/indices/` → `-` · 보여준 시각 `-`) · 출력 `QUEUE … · 큐 줄 qN · 큐 파일 …`.
- `ft-tick.sh`: `queue_watch`(매 루프 `ft-queue.sh remind --rosters <명부 폴더> --mbox <MBOX>`) + `pass()` 호출 1줄 · `FT_TICK_QUEUE=0` 끔 · `FT_TICK_QUEUE_MIN`(60) · --dry-run = `DRY kind=queue-reask` 1줄.
- 시험 새 `test_queue_reask_r529.sh`(임시 큐·명부·가짜 mbox · `FT_NOW` · 외부 호출 0 · GIT_* 0) ⓐ~ⓗ — 고치기 전 FAIL 43(`harness/evidence/r529/before-fix.txt` · 같은 최종 시험을 팩 origin/main 코드에) · 고친 뒤 ALL PASS 52(`after-fix.txt`). `test_queue_state_r528.sh` ⓔ 기대 꼴 = 10칸 · 상태 칸 대기(7칸 단정을 r529 꼴로). 기존 시험 9개 rc0 · pytest decision_count 2파일 33 passed · ruff·shellcheck 0(`existing-tests.txt`). 정본 큐 사본 읽기 전용 미리 보기 `QUEUE-DUE n=0 old=30`(`real-queue-due-preview.txt` — 열린 옛 줄 30 은 번호가 없어 재질문 대상 밖 · 새 줄부터 적용).
- 설치: 키트 5(`ft-queue.sh` · `ft_queue.py` · `ft_queue_remind.py` · `ft-proxy-decide.sh` · `ft-tick.sh` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 5 · 틱 launchd kickstart 1회(plist 0) · 홈 0 · 되돌림 = `.bak-r529`.
- 범위 밖: desk 질문 도구가 `shown` 을 부르는 연결(desk 쪽 1줄 · master 가 설치 때 알림) · 묶음 질문(r165 — «답 반영» = `take`) · 열린 옛 줄 30 에 번호 붙이기·일괄 정리(r530 · 인터뷰 때 줄마다).
## 2026-10-20 — 일괄 보류 금지: 한 커밋에서 큐 줄·카드 상태를 2개 이상 «보류» 로 바꾸면 커밋 REJECT (r530 · 1.1.84)

- 사건: 10-18 전팀 정지 뒤 오빠 큐(`AUTONOMY-QUEUE.md`) 23줄에 같은 문장 «보류 — 10-18 전팀 정지(판정 2253) 뒤 오빠 대기 아님 · 재개 때 팀별 재확인» 이 한 커밋(BYZ d575bb1ace)으로 붙고 아무도 다시 안 꺼냄. 오빠 결정(desk 쪽지 119482) «일괄 보류 절대금지» → master 83 발주 119484 · 카드 r530.
- 새 `kit/fable-team/bin/ft_queue_bulk.py bulk-check --staged [--worktree] | --range A..B [--repo <dir>]`(harness/bin 짝 cmp0): 대상 = 큐(이름 `AUTONOMY-QUEUE.md`) 상태 칸(옛 «처리됨») + `design/**/indices/**/*.md` 카드 «- 상태:» 줄. 옛 값(없으면 새 줄) → 새 값이 «보류» 인 것만 셈 · ≥2 = rc1 `REJECT 일괄 보류 N줄(<큐>:<줄>,<카드>.md…) — 보류는 한 번에 한 줄 · 줄마다 사유·재확인 시각 · 전팀 정지는 줄 대신 ft-spawn-hold.sh 정지 파일(«일시정지»)` · 아니면 rc0 `OK 일괄 보류 <n>줄` · git 실패·인자 오류 = stderr ERROR rc2. 큐 칸 판정 = r528 `ft_queue_state.parse` 그대로(import) · 줄 짝 = 상태 칸 밖 칸 묶음 · 카드 이동(git mv · `-M`)은 옛 경로와 비교 · 풀기(보류 → 대기·진행·완료)는 안 셈. 읽기만.
- `kit/hooks/harness-freeze-gate.sh` 규칙 1 추가(새 홈 훅 0 · settings 등록 변경 0): 이미 잡은 «git commit 대상 저장소 + 대상 파일(스테이징 · -a 꼴이면 작업 트리도)» 에 큐·`/indices/` 가 있으면 `bulk-check --staged [--worktree]` → rc1 = exit 2 + stderr `🚫 [harness-freeze-gate] REJECT 일괄 보류 …` 1줄 · freeze 표식 유무와 무관(규칙별 독립). 판정기 = env `FT_QUEUE_BULK` · 아니면 대상 저장소 → JSON cwd 저장소 공용 루트 `.fable-team/LIVE_BIN`. 못 찾음·rc2 = 통과 + stderr WARN(fail-open) · 입력 JSON 깨짐 = 통과 + WARN(전엔 조용한 통과).
- BOOT 조항 43 1줄(스테이징 `harness/design/harness/staged-r530/COMM-GUIDE-BOOT.md` = 홈 BOOT + 1줄 · diff 1): 큐 상태 4 + 정지 종류 3 · 보류는 한 줄씩 · 일괄 보류 = 훅 REJECT · 대기 줄 1시간 재질문 `ft-queue.sh take`(r529).
- 시험 `test_queue_bulk_r530.sh`(새 · 임시 git 리포 · 큐 md + 카드 2장 · PreToolUse JSON · 외부 호출 0 · GIT_* 0) ⓐ 큐 2줄 → REJECT(줄 번호) ⓑ 1줄 → OK ⓒ 새 줄 2개 처음부터 보류 → REJECT ⓓ 카드 2장 → REJECT · 1장 → OK · 큐 1 + 카드 1 → REJECT ⓔ 풀기 3줄·카드 2장 → OK · 보류 카드 2장 git mv → OK ⓕ 훅 commit/cd/-a → exit 2 · 비커밋·따옴표 글자·1줄 → 0 · 판정기 없음·JSON 깨짐 → 0 + WARN ⓖ `--range` 같은 판정 · 없는 rev rc2 · 기존 `test_harness_freeze_gate.sh` rc0. 고치기 전 FAIL 27(`harness/evidence/r530/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`) · 뮤테이션 5종 전부 RED(`mutation.txt`) · 기존 5파일 rc0(`existing-tests.txt`) · BYZ 큐 이력 읽기 전용 재생: 사건 커밋 d575bb1ace = `REJECT 일괄 보류 23줄` · 나머지 OK(`real-queue-history.txt`).
- 설치: 키트 1(`ft_queue_bulk.py`) + 홈 훅 1(`harness-freeze-gate.sh`) → `install.sh --apply --project <루트>` → HOOKS bad=0 · 홈 훅 cmp0 · LIVE_BIN cmp0 1 · settings 변경 0 · BOOT = staged-r530 을 홈 `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 로 cp+cmp(master) · 되돌림 = `.bak-r530`.
- 범위 밖: 지금 큐 23줄 풀기(desk 인터뷰 때 줄마다) · Edit/Write 단계 차단 · 정지 파일 자동 생성 · 훅 이름 바꾸기(r532).

## 2026-10-20 — 오빠 큐 상태 칸 = 대기·진행·보류·완료 넷 + 정지 종류 셋 · 어휘 정본 1장 + 린트 + 새 줄 «대기» (r528 · 1.1.83)

- 사건: 오빠 큐(`AUTONOMY-QUEUE.md`) 끝 칸 «처리됨» 이 손글 자유 문장 — 91줄 중 빈 칸 30 · «보류 — 10-18 전팀 정지(판정 2253) 뒤 … 재확인» 23줄 등 보류·대기·진행·완료가 섞여 읽힘(arch 107 실측). 오빠 결정(desk 쪽지 119482) «보류와 대기 진행 완료를 명확히 구분 … 일시정지·구현중정지·대기중정지» → master 83 발주 119484.
- 새 `kit/fable-team/bin/queue-states.tsv`(어휘 정본): 상태 4(대기 · 진행 — 누가 · 보류 — 사유 + «재확인 YYYY-MM-DD HH:MM» · 완료 — «판정 N» 또는 착지 sha) + 정지 종류 3(일시정지 — hold 번호 · 진행·대기에 · 구현중정지 — 멈춘 단계 · 진행에 · 대기중정지 · 대기에). 칸 꼴 `<상태>[ · <정지>][ — <덧말>]`.
- 새 `ft_queue_state.py parse|lint <큐>`: 판정기 하나 · parse = 행마다 JSON(줄 번호 · 머리 이름별 칸 · 상태 · 정지 · 덧말 · 재확인) — 칸이 늘어도 수정 0 · lint = 어휘 밖 줄 `ERR <줄> <사유> :: <칸>` + 끝줄 `QUEUE-STATE ERR=<n> OK=<m>` · rc 0/1 · 큐·어휘 읽기 실패 = stderr ERROR rc 2. 머리 «상태»·옛 «처리됨» 둘 다 같은 칸(이름 바꾸기 0). 읽기만.
- `ft-proxy-decide.sh`: QUEUE 새 줄 7칸 · 끝 칸 `대기` · 새 큐 파일 머리 7칸(`상태`).
- `ft_decision_count.py` autonomy_open: 상태 칸(옛 처리됨) 의 «열린 줄» = 빈 칸(옛) 또는 상태 «대기» — 안 고치면 새 줄의 `대기` 가 «처리됨 값 있음 = 닫힘» 으로 세여 결정 수가 줄어든다(카드 Issue ③ 같은 큐 읽는 도구).
- 시험 `test_queue_state_r528.sh`(새 · 임시 큐·FT_ROOT · 외부 호출 0 · GIT_* 0) ⓐ~ⓕ — 고치기 전 FAIL 23(판정기 파일 없음 · `harness/evidence/r528/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`). 기존: proxy-decide r188·queue_card_resolve·team_literal_paths2·decision_count_tables_ref rc0 · pytest decision_count 2파일 33 passed · `test_autonomy_core` FAIL 1 = BYZ `shared/config/external_call.py` 대조(r516 분류 ④ · 바탕 같음)(`existing-tests.txt`). 정본 큐 읽기 전용 미리 보기 `QUEUE-STATE ERR=89 OK=0`(`real-queue-lint-preview.txt`).
- 설치: 키트 4(`queue-states.tsv` · `ft_queue_state.py` · `ft-proxy-decide.sh` · `ft_decision_count.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 4 · launchd 0 · 홈 0 · 되돌림 = `.bak-r528`.
- 범위 밖: 지금 큐 줄 고쳐 쓰기(desk 인터뷰 때 줄마다) · 하네스 카드 «- 상태:» 어휘 · 시각·재질문(r529) · 일괄 보류 차단(r530).

## 2026-10-20 — 정지 스캔 종류 e = 명부 루프가 안 보는 tmux 라이브 좌석(교대 표시·명부 밖)의 조용한 정지 알림 (r525 · 1.1.82)

- 사건: 팀 개명(concierge→chatbot) 뒤 concierge master 6 행이 `role=stop-ready`·`_replaced_by` 로 표시됐는데 세션은 tmux 에 살아 이관 일을 쥔 채 컨텍스트 100% 로 멈춤 → 12시간+ 아무 틱도 못 봄(desk 26 쪽지 119421 · 오빠 «왜 자꾸 조용한 침묵 정지를 하냐고»). 원인 = `ft_stall_scan` 이 `load_teams` 현역 행만 훑음.
- `ft_stall_detect.py`: `off_roster_live(root, live, teams)` = tmux 라이브 − (현역 행 ∪ 팀 master) → (좌석, 계보 현역 master, `교대 표시인데 라이브`|`명부 밖`) · 계보 = `_replaced_by` 사슬 끝 좌석이 있는 명부의 `_master`(못 찾으면 처음 명부 · 자기 자신이면 None) · `agent_sessions(tmux, ps)` = ps 1회 + list-panes 1회로 pane 자신+자손에 claude|codex 가 도는 세션 · `ctx_pct` = `ft-claude-context.sh <좌석>` 7초 상한(실패·숫자 아님 = None · 추측 0) · `run(..., timeout=)` 인자.
- `ft_stall_scan.py`: 종류 e = 위 후보 ∧ agent 실행 중 ∧ IDLE ≥ `FT_STALL_E_IDLE_MIN`(기본 30) ∧ (ctx ≥ 90 ∨ [완료·휴식] 없음) → planner `_master` + 계보 현역 master(같으면 1통)에 `[정지] <좌석> 쉬는 <N>분 · <꼬리표> · 열린 일 · ctx <p>%|ctx ? · 깨우기/닫기/인계는 받는 쪽 판단` · 서명(좌석 → IDLE 시작 시각 · `state/stall-scan.e.json`)이 같으면 다음 실행 쪽지 0 · 로그 `act=e seat=… notify=…`(`to=` 꼴 아님 — 10분 가드가 받는 이 좌석을 막지 않게) · 요약 줄 `d=` 뒤 `e=` 칸(뉴스 `stall_cell` 은 앞 5칸만 — 무변경) · `stall=N` 에 e 포함. env 시험용 `FT_PS` · `FT_CTX_CMD`.
- 경계: 깨우기(Escape·ring)·kill·명부 쓰기·페널티(ft-penalty) 대상에 e 넣기 0 · attached·페널티 정지 중에도 알림은 감(알림만이라).
- 시험 새 `tests/scripts/test_ft_stall_scan_off_roster.py`(가짜 명부·tmux(pane_pid)·ps·ctx 스텁 · 외부 호출 0 · GIT_* 0) ⓐ 교대 표시 라이브 IDLE 45 → e 1 · planner+계보 master 2통 ⓑ 명부 밖 ctx 93 → planner 만 ⓒ 같은 서명 다음 실행(11분 뒤) 쪽지 0 · 요약 줄 e=1 ⓓ IDLE 25 → 0 ⓔ [완료·휴식] ∧ ctx 40 → 0 · ctx 95 → e 1 ⓕ 빈 셸 0 · 명부 밖 나노(codex) → e 1 «ctx ?» ⓖ send-keys·kill 0 · ring 0 · dry-run 쪽지 0. 고치기 전 7 FAIL → 7 passed · stall 관련 기존 6파일 72 passed(`test_summary_line…` 기대 꼴에 `e=0` 칸). 증거 `harness/evidence/r525/`(red-before · green-after · live-dry-run · live-candidates · install-dry-run · master-steps).
- 라이브 dry-run(쓰기·쪽지 0): `stall=1 … e=1 seats=43` · `e byz-planner-desk-claude#23 768 교대 표시인데 라이브 · 열린 일 · ctx 14%` · 후보 8(agent 6) — concierge 6·airag 8 은 [완료·휴식] ∧ ctx < 90 이라 0.
- 설치: 키트 2(`ft_stall_scan.py` · `ft_stall_detect.py` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · launchd `com.byz.ft-stall-scan` kickstart 1회(plist 0) · 홈 0 · 되돌림 = `.bak-r525`.

## 2026-10-20 — 홈 훅 `bg-cpu-burner-gate.sh` = 시간 상한 없는 백그라운드 CPU 소모기 거절 (r523 · 1.1.81)

- 사건: 10-19 23:27Z v65 나노가 부하 재현 스크립트 `loadrep.sh` 안에서 `nice -n 19 yes > /dev/null &` 여러 개를 띄우고 정리는 `trap EXIT` 뿐 → 강제 종료로 trap 이 안 돌아 `yes` 고아 → CPU 100 · 오빠 손 kill(v65 215 쪽지 119303 → desk 119305 → master 83 발주 119306). «burner 0» 은 메모리 글뿐이라 못 막음.
- 새 홈 훅 `kit/hooks/bg-cpu-burner-gate.sh`(PreToolUse:Bash · 모든 리포 · `op-vault-develop-gate.sh` 꼴 = python3 본문 · fail-open): 명령 글자 + 그 명령이 실행하는 스크립트 파일 1단계(`bash|sh|zsh|dash|source|.` 다음 인자 · 첫 낱말이 경로 · cwd 기준 · ≤256KB · 바이너리 생략)를 따옴표·주석·heredoc 본문을 가린 뒤 조각낸다. 소모기 = 감싸개(env·nohup·nice·stdbuf·command·exec·time) 벗긴 첫 낱말 `yes` · `cat /dev/zero|/dev/urandom` · `dd if=/dev/zero|/dev/urandom`(count= 없음) · `while true|:|[ 1 ]|(( 1 ))` 루프(본문 sleep 이면 아님 — r448 영역). 백그라운드 = 파이프라인 끝 단독 `&`(`done &` 포함 · `2>&1`·`&>` 는 재지정) 또는 `run_in_background: true`. 면제 = burner 바로 앞 `timeout|gtimeout N` · N ≤ 600초 하나뿐(바깥 `timeout … bash x.sh` 는 안의 `&` 고아를 못 끄므로 면제 아님). 거절 = exit 2 + stderr `REJECT bg-cpu-burner <파일:줄|명령> — …` 1줄. 거절만 — kill·renice·실행 0 · 외부 프로세스 0.
- 등록: `settings-hooks.snippet.json` PreToolUse `Bash` 1항목(`$HOME/.claude/hooks/bg-cpu-burner-gate.sh`). 설치기는 kit/hooks 전부를 복사(r491) — settings 등록은 master.
- 시험 `test_bg_cpu_burner_gate.sh`(새 · 임시 폴더 · 실제 burner 실행 0 · 가짜 kill/pgrep/ps/pkill · GIT_* 0) ⓐ~ⓙ 65건 — 고치기 전 FAIL(훅 파일 없음 · `harness/evidence/r523/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`) · mutation 10종 전부 RED(`mutation.txt`) · 실제 스크립트 745개(kit·bin·tests·홈 훅·BYZ scripts)를 `bash <파일>` 로 넣어 거절 0(`real-scripts-scan.txt`).
- 기존 시험 1: `test_op_vault_develop_gate.sh` 의 «install.sh HOME_HOOKS 1토큰» 검사가 r491(HOME_HOOKS = kit/hooks find 목록) 뒤 base 에서도 FAIL 1 → 지금 꼴(find 목록 + 훅 파일 실재)로 고침 · rc0(`existing-tests.txt`).
- 설치: 키트 훅 1 → `install.sh --apply --project <루트>` → 홈 `~/.claude/hooks/bg-cpu-burner-gate.sh` cmp0 · settings.json PreToolUse Bash 등록 1 · LIVE_BIN 0 · launchd 0 · 되돌림 = `.bak-r523`.
- 범위 밖: 이미 떠 있는 burner 끄기(r522 = 사후 기록 · 끄기는 사람) · CPU 실측 · python/node 안 무한 루프 · 2단계 이상 스크립트 · `( … ) &`·`{ …; } &` 묶음 · `cat /dev/zero | gzip &` 처럼 burner 가 파이프라인 끝이 아닌 꼴.

## 2026-10-20 — 하네스 시험 «밖 RED» 셸 62 · pytest 104 를 원인 8묶음으로 분류 · 가장 큰 묶음(pytest 79) + 픽스처 미이관 묶음 고침 (r516 · 1.1.80)

- 사건: r509 끝선 «기존 시험 전체 rc0» 이관분 — 팩 main 에도 있는 밖 RED(셸 62 · pytest 104)가 나노 증거마다 «기존 RED 제외» 로 깔려 새 실패를 가렸다(harness master 83 발주 118693 · arch 106 카드화 · 판정 1395).
- 분류(바탕 9af3b78a · 셸 253 · pytest tests/scripts 직렬): ① slack 수신 시험 KIT 경로 이중 pytest 79 ② BYZ `tests/fixtures` 미이관 10 ③ 공용 루트·comm·팀 명단 전제 34 ④ BYZ 리포 전용 파일 전제 16(시험 자리 결정 = arch) ⑤ 옛 BYZ 배치 경로 6 ⑥ 시험 임시 bin 짝 누락 5(2개 r515 가 닿음) ⑦ 홈·라이브 실물 대조 7 ⑧ 낡은 대조·환경·개별 9 — 표 `harness/evidence/r516/red-buckets.md`.
- 시험(4 · 도구 0): ①`test_byz_slack_mbox_inbound.py`·`test_inbound_humans_and_install.py` `KIT = HERE.parents[1]/"harness"/kit` → `parents[1]/kit`(r386 이전 글자 치환이 harness/ 를 한 번 더 붙임) ②`test_team_literal_paths` goal_table = `fable-team/tests/fixtures`(test_goal_table_gate 와 같은 사본) · 가려 있던 2건: `test_mbox_guard` hold_env 에 `ft-harness-root.sh` 짝 · `test_issue_close_canon` 임시 리포 `.fable-team`(⑧ close-reason-check 가 cwd 리포를 공용 루트로).
- 픽스처(89 · 내용 0 변경): BYZ origin/main `6c22cefe01` 의 `tests/fixtures/{deferral,issue_classify,issue_close,seat_request,magazine}` → `harness/fixtures/`·`harness/tests/fixtures/magazine` · `mbox_guard` → `fable-team/tests/fixtures/`(시험이 읽는 자리 그대로).
- 시험: 같은 바탕 전·후 셸 실패 62→55 · pytest 104→23 failed · 후에만 실패 pytest 0 · 셸 «후에만» 1(`test_inbox_watch` = 두 판 단독 재실행 같은 RED · 팩 공용 루트 실물) · 흔들림 `test_cherry_gate_identical_head` ④ 1건(두 판 단독 재실행 없음) — 원문 `harness/evidence/r516/compare.txt`·`bucket-before-after.txt` · 합친 판(1.1.79 병합)에서 고친 시험 재확인 ② 7개 rc0 · pytest 4파일 109 passed. `test_deferral_lint` 남은 34 = ④(BYZ `.claude/hooks/deferral-lint-gate.sh`) · `test_team_literal_paths` 남은 4 = ③. 설치: 키트 diff 0(시험·픽스처·증거만) · 홈 0 · plist 0 · 되돌림 = 이 PR revert.

## 2026-10-20 — `ft-hil.sh --pending` = 파이썬 한 번의 훑기 · 같은 결과를 1초 안에 · 읽기 실패 rc 3 (r521 · 1.1.79)

- 사건: `--pending` 이 `/tmp/h<N>` 880개를 파일마다 `plan_of`(sed·head)·`done_rc`(grep)·`age_min`/`since_min`(stat·date) 하위 프로세스로 훑어 부하 17 에서 2.8~3.2초 · 부하 26~30 에서 4.35~4.68초 → `ft-decision-count` 1회 예산 5.0초(R303)에 붙어 rc4 «ft-hil.sh TimeoutExpired» 2회(§74 r517 · §77 r337 편차 · arch 106 실측).
- 새 `ft_hil_pending.py <HIL_DIR> [--each]`: 옛 pending() 과 같은 규칙 — 이름 h<숫자> · 일반 파일(링크 0) · 첫 `# ft-hil-entry plan=` 줄 값 있음 · `.superseded` 없음 · `.ran` 에 `^rc=[0-9]* ` 행 = 끝 · 없으면 중단/실행 중(1행 epoch · 숫자 아니면 `.ran` mtime) · `.ran` 없음 = 미실행(mtime) · 분 = 0 쪽으로 버림(셸 산술과 같음) · 이름순. 출력 꼴 바이트 같음(요약 1줄 · `--each` = `h<N> <분>` · 0개·폴더 없음 = 출력 0 rc 0).
- `ft-hil.sh` pending() 본문 → 같은 폴더 `ft_hil_pending.py` 호출 1줄. `plan_of`·`age_min`·`since_min`·`done_rc` 셸 함수는 목록·`--add` 가 그대로 쓴다.
- 바뀐 것 1: 읽기 실패(폴더·h 파일·`.ran` 권한 등) = stdout 0 · stderr `ERROR ft-hil --pending 읽기 실패: <경로>: <이유>` 1줄 · rc 3(옛 판은 그 파일을 건너뛰거나 0개로 조용히 rc 0). 결정 셈은 rc≠0 을 ReadError 로 드러낸다.
- 시험 `test_hil_pending_single_pass.sh`(새 · 임시 HIL_DIR · 외부 호출 0 · GIT_* 0) ⓐ 900개 1초 안 ⓑ 6종(미실행·실행 끝·실행 중·대체됨·옛 링크·표식 없음) + 가장자리 꼴 9종(1행 숫자 아님·`rc= `·`rc=0` 공백 없음·미래 시작 -2분·빈 표식·끝 개행 없음·폴더 h<N>·깨진 대체 링크·숫자 아닌 꼬리/0 앞자리) 과 900개에서 요약·`--each`·다른 인자가 옛 판(시험 안 복사본)과 바이트 같음 ⓒ 0개·폴더 없음 = 출력 0 rc0 ⓓ 권한 0(h 파일·`.ran`·폴더) = stdout 0 · stderr 1줄 · rc 3 — 고치기 전 FAIL 7(ⓐ 3.54초 · ⓓ 6건 조용한 0 · `harness/evidence/r521/before-fix.txt`) · 고친 뒤 ALL PASS(ⓐ 0.139초 · `after-fix.txt`) · 실 `/tmp`(h 363개) 읽기 전용 옛 판 대비 diff 0 · 1.54초 → 0.08~0.10초(`real-tmp-readonly.txt`).
- 기존 시험 픽스처 1: `test_tick_team_msg.sh` 가 가짜 bin 에 `ft-hil.sh` 만 복사 → 짝 `ft_hil_pending.py` 도 복사(고치기 전 ⓔ FAIL 2 → rc0). 운영 루트 shim 은 LIVE_BIN 사본을 `exec` 하므로 짝을 찾는다. 기존 시험 결과·base 대조 = `existing-tests.txt`.
- 설치: 키트 2(`ft-hil.sh` · 새 `ft_hil_pending.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r521`.
- 범위 밖: 오래된 h 파일 지우기·옮기기(삭제 = 사람 판단) · 결정 셈 예산 5.0초(R303) · 7초 룰 변경 0.

## 2026-10-20 — nano-close reap 실패 뒤 «같은 close 재실행» 이 실제로 이어지게 + reap 1회 재시도 (r520 · 1.1.78)

- 사건: r519 나노 닫기 1차에서 reap 이 left=1(그 순간 돌던 `git status` 1개)로 CLOSE-FAIL — 안내는 «명부는 삭제됨 · 같은 close 재실행» 인데, 재실행은 RERUN 판별(명부에 좌석 없음 · 원장 닫힘 행 있음)에 닿기 «전» 카드 찾기(명부 index)에서 «카드 못 찾음»(팩 경로는 ⓐ 문구) REJECT → 그 좌석을 닫을 도구 경로 0(harness master 83 발주 119095 ① · arch 106 실측).
- `ft-nano-close.sh` 조기 재실행: 인자·명부·원장 결정 직후, 카드 찾기 «앞» — 명부에 행 없음(`jq has` rc 1 만) ∧ 원장에 «`<좌석>` 닫힘(ft-nano-close)» 행 1개 이상이면 «재실행 — 명부에 없고 원장 닫힘 행 있음: 검사 건너뛰고 남은 정리(reap·회수·태그·kill)만» → 카드·증거·cherry 검사 0 · reap(재시도 포함) → 세션 있으면 태그 해제 + kill → opencode 회수 → `CLOSED <좌석> (재실행 · 세션 kill|세션 없음 · 원장 행 그대로 · append 0)`. 명부·원장 쓰기 0 · 워크트리·브랜치 손대기 0. 워크트리 인자 = `--wt` › 원장 행 `wt=<절대경로>`(pack-wt·named-wt 꼴) › 없음(--shared-wt 는 늘 없음). tmux 조회 실패(서버 없음 외) = REJECT(fail-closed). 원장 행이 없는 좌석(처음 보는 좌석)은 이 길로 오지 않는다 — 기존 검사 그대로. `--plan-only` 대상 아님.
- reap 1회 재시도(`_seat_reap`): left≠0 ∨ rc≠0 이면 `FT_REAP_RETRY_SLEEP`(기본 3)초 뒤 1회만 다시 · 두 번째 결과로 판정 · 출력 «reap 재시도 1 — 1회째 left=… rc=…». 그래도 남으면 지금처럼 CLOSE-FAIL(무한 재시도 0). 정상 경로·재실행 경로 공용.
- 구조 이동(별 커밋): `_oc_close`·`OC_BIN`/`OC_PF` 정의를 위로(본문 그대로). 아래 옛 RERUN 분기(`RERUN=1 ∧ 원장 행` → append 생략)는 조기 재실행이 먼저 잡아 사실상 닿지 않지만 방어로 남김.
- 시험 `test_nano_close_rerun_early.sh`(새 · test_nano_close_pack_wt 꼴 픽스처 + 가짜 reap 모드 파일 · 외부 호출 0 · GIT_* env 0) ⓐ 1차 CLOSE-FAIL → 2차 재실행 CLOSED(원장 행 1 그대로 · 태그 해제·kill) · ⓐ' 세션도 없음 → CLOSED kill 0 · ⓑ 1회째 left=1·2회째 left=0 → 1차 CLOSED(reap 2회) · ⓒ 늘 left=1 → reap 정확히 2회 뒤 CLOSE-FAIL · ⓓ 명부·원장 행 둘 다 없음 → REJECT(재실행 0 · reap 0) · ⓔ 명부 행 있음 = 기존 경로(증거 검사 · reap 1회 · append 1) — 고치기 전 FAIL 14(`harness/evidence/r520/before-fix.txt` · ⓐ 2차 «카드 못 찾음» REJECT 재현) · 고친 뒤 ALL PASS(`after-fix.txt`) · 기존 nano-close 시험 9 + seat_reap_left0·opencode_reap·nano_team_env·pack_nano_worktree_place rc0(`existing-tests.txt`).
- 설치: 키트 1(`ft-nano-close.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r520`.
- 범위 밖: 명부 삭제와 reap 의 순서 바꾸기 · `ft-seat-close.sh` NOROW 동작 · 손 tmux kill.

## 2026-10-20 — 결정 인터뷰 N = 현역 좌석·도구가 보낸 «질문 표식» 미닫힘만 · 통보 0 · planner 답장 자동 닫힘 · 묵은 칸 (r337 · 1.1.77)

- 사건: planner 보고 첫 줄 「결정 인터뷰 N건」(판정 1804)의 분모가 «인박스 ②③ 분류 미닫힘» 이라 [완료]·[정지 레디]·[수령]·[회신] 통보가 섞이고, planner 가 쪽지로 답해도(`ft-inbox mark` 안 함) 원쪽지가 안 닫혀 하루 종일 28~31(10-17 22:1x · 실제 질문 [결정] 4). 팀 대기도 같은 꼴 — 07:33 라이브 1.1.75 「팀 대기 43건(가장 오래 byz-planner-arch-claude#7 1071분)」 의 가장 오래 = [완료·휴식] 통보(r2 ㉠) · 「(AUTONOMY-QUEUE 파일 없음)」 메모 매번(r2 ㉡).
- `ft_decision_kind.py`(새 · 분류 1곳): 본문 첫 줄 «머리»(앞 대괄호 묶음) → 질문표식 = `[결정]`·`[HIL]`·`[인터뷰 요청]`(«·» 변형 포함 · `[결정 대기 경보]` 같은 이름 겹침 제외) 또는 `[긴급]` + 첫 줄 «?»·«예/아니오»·«①…②» / 통보 = 통보 머리(`[완료…]`·`[정지 레디]`·`[수령]`·`[회신…]`·`[보고]` — 물음표가 있어도 0) 또는 표식 없음 / 묵음 = 24시간 넘은 질문. 본문 못 읽음 = ReadError rc4(분류 지어내기 0).
- `ft_inbox_core.obligation_closed(line, answered=frozenset())` 정본 술어 확장 + `answered_seqs(seat)`: 큐 주인 계보가 보낸 쪽지(mail_files 전부 · 계보 글자 선거름)의 «#N 확인/회신/수령/적용/답» 참조 seq = 닫힘 · 남의 좌석(desk·팀장) 참조 0(R326 «자기 큐만» 과 같은 방향) · 인자 없이 부르면 옛 식 그대로(test_inbox_waive ⓕ 전 조합 0). «답» 은 카드 4낱말 밖 — 실 planner 발신 «#117757 답» 꼴 실측으로 넣음.
- `ft_decision_count.py`: N = 질문표식 중 죽은 '#' 좌석이 아닌 것(죽은 좌석 질문 = «옛 좌석 미닫힘» 메모 · 실측 07:4x 37건 중 32건이 tmux 없는 좌석) · 팀 대기 = 현역 다른 팀 좌석 질문만 · ` · 묵은 M건`(M>0 일 때만 · 첫 줄 머리 «결정 인터뷰 N건 · 스크립트 M건» 불변 = planner-decision-line 훅·ft_news_ledger 그대로) · `--detail` = 현역 다른 팀 미닫힘 전부 + 이유 낱말(질문표식 → 묵음 → 통보 순) · AUTONOMY-QUEUE 자리에 파일 없음 = 0행 메모 0(리졸버 실패만 rc4). 199줄.
- 시험 `tests/scripts/test_decision_count_truth.py`(새 · 7) — 표본 10건(새 질문 3 · planner 옛 세대 회신 닫힘 1 · 25시간 질문 1 · 통보 5) 「결정 인터뷰 3건 · … · 묵은 1건」 · desk 회신 = 닫힘 아님 · [완료·휴식] 팀 대기 0 · 죽은 좌석 질문 메모 · 큐 파일 없음 메모 0 · 본문 없음 rc4 · 로그 3만 줄 + 900행 ≤ 2.5 s. 고치기 전 7 FAIL(`harness/evidence/r337/before.txt`). 기존 `test_decision_count.py` 고정물: row() 기본 본문 = [결정] 질문 · put() 이 본문 파일을 씀 · make_env 분리 — 단언 변경 0.
- 실 공용 루트 읽기 전용(`real-root-smoke.txt`): 라이브 1.1.76 「팀 대기 1건(가장 오래 byz-planner-desk-claude#26 0분) (옛 좌석 미닫힘 37) (AUTONOMY-QUEUE 파일 없음)」 → 이 판 「팀 대기 0건 · 묵은 8건 (옛 좌석 미닫힘 1)」 (desk [틱] 통보) · 2.6~3.4 s(예산 5 s).
- 설치: 키트 3(`ft_decision_count.py` · `ft_inbox_core.py` · `ft_decision_kind.py` 새) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 3 · 홈 0 · plist 0 · 되돌림 = `.bak-r337`.
- 범위 밖(따로 단위): `test_flag_off_scan.sh` ⓜ(ft-land → ft-sheet-events 루트 풀이 · 팩 체크아웃에 `.fable-team/LIVE_BIN` 없음) FAIL 3 — origin/main 77efe21b 판 파일로도 같음(`flag-off-scan-base-origin-main.txt`).

## 2026-10-20 — 상향 좌석 «▶내릴 것» 카드 상태 = 데이터 루트 · 공용 루트 · ref origin/main 세 자리 중 가장 앞선 것 (r518 · 1.1.76)

- 사건: 틱 `raised_watch` 의 판정기 `ft_raised.py card_state` 가 카드 실재를 `--root`(= 공용 루트 · 체크아웃 main 51881ba2e4 · 2026-09-23 · `design/teams/` 없음) 한 곳에서만 찾아, v6 라이브 워크트리 «진행» 에만 있는 v65 카드 2장의 상향 좌석을 «(카드 없음)» → master 에 «▶내릴 것» 오탐(v65 master 쪽지 119019 · 틱 쪽지 119017 · harness master 83 발주 119026 ② · arch 106 실측). r515·r517 과 같은 뿌리(공용 루트 체크아웃 옛 판을 정본처럼 읽음).
- `ft_raised.py card_state(root, card, data)`: 자리 3 = 데이터 루트(`ft_team_lib.data_root` · r515 — FT_ROOT → 공용 루트 LIVE_ROOT 1행 → 공용 루트) 체크아웃 · `root` 체크아웃 · ref `origin/main`(`git -C root cat-file --batch-check` 1회 · 7초 상한) · «완성 > 진행 > 대기» 중 처음 맞는 것 · 셋 다 0 = «없음». «내릴 것» 기준(완성·없음) 변경 0 · `ft-tick.sh` 호출 인자·출력 꼴 변경 0.
- 못 읽음 = rc2(조용한 «없음» 0): ref 못 읽음(리포 아님·origin 없음·7초 초과·batch-check 실패) · LIVE_ROOT 가 절대경로 폴더 아님 · `ft_team_lib` import 실패. LIVE_ROOT 파일 없음(FT_ROOT 도 없음) = 데이터 루트 = 공용 루트(r515 규칙)로 판정하고 «▶내릴 것» 줄 끝에 « · 못 본 자리: 데이터 루트(LIVE_ROOT 없음 <경로>)» — 카드 시험 입력 ⓓ 의 «경고 1줄» 을 stderr 가 아니라 줄 꼬리로 낸 편차: 틱이 `2>&1` 로 받고 rc0 이면 출력 전체를 목록으로 세므로(rc0 stderr 경고 = 가짜 좌석 1건 · 서명 흔들림) 목록이 없을 때는 표기도 0.
- `ft_team_lib` import 는 `check` 경로 안(지연) — `is-raised` 만 부르는 spawn 시험들의 임시 bin(ft_raised.py 만 복사)은 그대로 동작.
- 시험 `test_raised_card_state_three_places.sh`(새 · 임시 공용 루트 C(카드 폴더 없음) + LIVE_ROOT = 임시 데이터 루트 D + 임시 bare origin · 외부 호출 0 · GIT_* env 0) ⓐ~ⓕ 38 PASS(ⓕ = 틱 실경로 쪽지 0 · 진짜 완성 경보 1) · 고치기 전 FAIL 16(`harness/evidence/r518/before-fix.txt` · ⓐ 오탐·틱 쪽지 1 재현) · 변이(데이터 루트 자리 제거) FAIL 2(`mutation-no-data-root.txt`). 기존 시험 보정 1: `test_raised_seat.sh` — 판정 폴더 3곳(ck·dup·td)에 빈 커밋 + origin/main ref(ref 트리 0 → 판정은 디스크 그대로) · 임시 bin 에 `ft_team_lib.py` 복사 · 단언 변경 0. 실 공용 루트 읽기 전용: 라이브 1.1.74 «▶내릴 것 ft-v65-temp-m5-1943-r7a-fix3-r8-ghost-verdict-notice#0 … (카드 없음)» 1줄 → 이 판 0줄(`real-root-smoke.txt`).
- 설치: 키트 1(`ft_raised.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0(틱은 다음 실행부터 새 판) · 되돌림 = `.bak-r518`.
- 범위 밖: 공용 루트 체크아웃 갱신 · 명부 «카드 워크트리» 칸 · 같은 꼴(공용 루트 체크아웃을 정본처럼 읽는) 도구 전수 스캔(arch 제안 후보).

## 2026-10-20 — 하네스 팩 나노 작업 폴더 자리 = <팩>/.worktrees/<키> (r519 · 1.1.75)

- 사건: 팩 작업 폴더 자리를 정한 곳이 없어 r517 나노가 세션 스크래치(`/private/tmp/…/scratchpad/afp`)에 팩 워크트리를 만들었고, `ft-nano-close.sh` 팩 모드(r508 · `--wt` = 팩 `.worktrees/` 아래만)가 2회 REJECT(harness master 83 발주 119026 ①). 닫기 기준을 넓히지 않고 «만드는 자리» 를 정한다(arch 106).
- `ft-nano-spawn.sh`: `pack_wt_line <카드> <키> <브랜치>`(새) — 카드에 `- 설치: 있음`(하네스 카드)이면 첫 발주문 끝에 «★팩 작업 폴더 = `${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}/.worktrees/<키>` (`git -C <팩> worktree add … -b <브랜치> origin/main` · 세션 스크래치 0 — 닫기 = `nano-close --wt … --branch …`)★» 1줄 · dry-run 에도 `BODY+` 로 출력 · 그 밖 카드 = 출력 0.
- `ft-nano-close.sh`: `_pack_move_hint`(새) — ⓐ REJECT 대상 `--wt` 가 팩 «등록» 워크트리인데 표준 자리 밖이면 같은 REJECT 줄 끝에 « · 표준 자리 밖 — `mkdir -p <팩>/.worktrees && git -C <팩> worktree move <옛> <팩>/.worktrees/<키>` 뒤 같은 명령(--wt …)» (키 = `--branch` 의 `nano/` 뒤) · 판정(REJECT)·닫기 기준 변경 0 · 팩 미등록 폴더는 덧말 0. `mkdir -p` 는 팩 `.worktrees/` 가 없으면 `worktree move` 가 실패해서(시험 ⓓ 실측).
- 시험 `test_pack_nano_worktree_place.sh`(새 · 임시 리포 2개 + 가짜 tmux · spawn 은 함수 추출 · 외부 호출 0 · GIT_* env 0) ⓐ 하네스 카드 줄·기본 팩 경로 ⓑ 제품 카드 0줄 ⓒ 스크래치 꼴 등록 워크트리 REJECT 그대로 + 덧말 · 미등록 폴더 덧말 0 ⓓ 덧말 명령 «그대로» 실행 → 같은 명령 CLOSED(mode=pack-wt) = ALL PASS · 고치기 전 FAIL 10(`harness/evidence/r519/before.txt` · ⓓ CLOSED 는 그때도 PASS = 팩 모드 그대로).
- 설치: 키트 2(`ft-nano-spawn.sh` · `ft-nano-close.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r519`.

## 2026-10-20 — 결정 셈 planner 표(MERGE-QUEUE·FLAG-DECISIONS) = ref origin/main 명단 + ref 본문 (r517 · 1.1.74)

- 사건: `ft-decision-count.sh` 가 planner 표 자리를 «루트(공용 루트) 체크아웃의 `design/TEAMS.md`» 로 풀어, 공용 루트 체크아웃(main 51881ba2e4 · 2026-09-23 · 명단 없음)·v6 어느 cwd 에서 불러도 `ERROR … 팀 명단 없음 … design/TEAMS.md` rc4(planner 쪽지 118922 · harness master 83 발주 118925 · arch 106 실측). 발주의 «실패인데 rc 0» 은 재현 0 — 도구 rc = 4 · 0 은 `| tail` 파이프 끝 rc.
- `ft_team_lib.team_doc_ref(root, team, name, ref)` (새 · 셸 `ft_team_doc_ref` 의 ref 쪽 · 임시 파일 0): ref 명단 후보(`_cands_ref` · 명단 꼴 먼저)마다 `<ref>:<후보>/<name>` 이 ref 트리(`ls-tree`)에 있으면 `git show` 본문 · 모두 없음 = None · 명단 못 읽음·팀 없음·git 실패·리포 밖 후보(꼴3) = TeamPathError(조용한 None 0 · 체크아웃 명단·옛 경로 후퇴 0).
- `ft_decision_count.table()`: 자리 = env 파일(그대로) → `at`(AUTONOMY-QUEUE · r515 `planner_queue` 그대로) → 카드 워크트리 디스크(그 워크트리에 명단이 있을 때 · 미착지 최신 행 · 먼저) → ref 본문(`FT_TEAMS_REF` · 기본 origin/main). 표 «내용» 판정 규칙(칸·대기 셈·손상 rc4) 변경 0 · 못 읽음 = ReadError rc4 그대로. 파일 200줄 그대로(test_flag_off_scan 상한).
- 시험 `test_decision_count_tables_ref.sh`(새 · 임시 리포 체크아웃 = 옛 커밋(명단 없음) · origin/main = 새 꼴 명단 + `design/teams/planner` 표 · 외부 호출 0 · GIT_* env 0) ⓐ 공용 루트·다른 리포 cwd rc0 + 대기 1 · ⓐ2 카드 워크트리 표 먼저 ⓑ FLAG-DECISIONS ref 본문 · 머리 손상 변이 rc4 ⓒ ref 에 표 없음 = 메모 + rc0 ⓓ origin 없음 = rc4 «명단 ref 못 읽음» ⓔ env 지정 = 그 파일 = 17 PASS · 고치기 전 FAIL 12(`harness/evidence/r517/before-fix.txt`). 기존 시험 2개 보정(git 밖 임시 루트 → 표 자리 env 고정): `tests/scripts/test_decision_count.py` run() `FT_DECISION_FLAG_DECISIONS` · `test_flag_off_scan.sh` count() `FT_DECISION_MERGE_QUEUE`·`FT_DECISION_FLAG_DECISIONS`. 실 공용 루트·v6 cwd 읽기 전용 실행: 라이브 1.1.73 rc4 → 이 판 rc0(`harness/evidence/r517/real-root-smoke.txt`).
- 설치: 키트 2(`ft_decision_count.py` · `ft_team_lib.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r517`.
- 범위 밖: 셈 분모(r337 — 실 MERGE-QUEUE 27행 중 «대기» 로 시작하는 행 0 · 상태값 «⏳ 아침 큐» 등) · 공용 루트 체크아웃 갱신 · `seats-planner.json` 위치 · 원장 VERDICTS 읽기.

## 2026-10-20 — 오빠 큐 자리 리졸버 1개 + card-start 카드 상대경로 cwd → ref 읽기 (r515 · 1.1.73)

- 사건: `ft-proxy-decide.sh` 가 오빠 큐(AUTONOMY-QUEUE) 줄을 «데이터 루트(LIVE_ROOT = v6-realtime-live 워크트리) 체크아웃의 옛 명단» 으로 푼 `design/planner/AUTONOMY-QUEUE.md` 에 씀(정본 = main `design/teams/planner/` · v6 가지엔 새 폴더 없음) · `--card` 상대경로를 cwd 에서만 찾아 «카드를 못 읽음» 으로 QUEUE(planner 쪽지 118583 · 05:55 loom l3c card-start 2회 · `v6-realtime-live/design/planner/AUTONOMY-QUEUE.md:63`) · 같은 큐를 읽는 `ft-autonomy.sh`·`ft_decision_count.py` 도 같은 옛 자리.
- `ft-team-lib.sh` `ft_planner_queue <루트>` (새 · 파이썬 짝 `ft_team_lib.planner_queue`): `FT_PLANNER_DIR` 있으면 그 폴더 · 없으면 ref(`FT_TEAMS_REF` · 기본 origin/main) 명단 꼴 planner 폴더가 루트에 실재하면 그 폴더 · 실재 0(이동 전 가지 체크아웃)이면 공용 루트 `.fable-team/state/planner/AUTONOMY-QUEUE.md` · ref 명단 못 읽음·공용 루트 못 풂 = ERROR rc1(옛 체크아웃 꼴·쌍둥이 후퇴 0 — `ft_team_in_ref` 는 실재 쌍둥이 1개면 옛 꼴을 돌려주므로 쓰지 않고 «명단 꼴 후보 1번» 만 본다). 파이썬 `ft_team_lib.data_root`(새 · 셸 `ft_data_root` 짝: FT_ROOT → 공용 루트 LIVE_ROOT 1행(절대경로 폴더 아니면 ERROR) → 공용 루트).
- 사용처 3: `ft-proxy-decide.sh` QUEUE = 리졸버(폴더는 쓸 때 만든다 · 판정 원장 VERDICTS 읽기는 그대로) · `ft-autonomy.sh` `queue_file` = 리졸버(status·off 의 큐 수·경로) · `ft_decision_count.py` AUTONOMY-QUEUE = `planner_queue(data_root(R))`(env `FT_DECISION_AUTONOMY_QUEUE` 우선 그대로 · 카드 워크트리 후보 0 · MERGE-QUEUE·FLAG-DECISIONS 그대로).
- card-start 카드: 절대경로 = 그 파일만(지금과 같음) · 상대경로 = cwd 에 있으면 그 파일 · 없으면 `git -C <루트> show <ref>:<경로>` 본문(임시 파일 0 · 변수) · 둘 다 없으면 QUEUE «카드를 못 읽음: <cwd 경로> · <ref>:<경로>».
- 시험 `test_proxy_decide_queue_card_resolve.sh`(새 · 임시 리포 main 새 꼴 + 옛 꼴 가지 워크트리 = 데이터 루트 · 외부 호출 0 · GIT_* env 0) ⓐ~ⓖ 31 PASS · 고치기 전 FAIL 10(`harness/evidence/r515/before-fix.txt` · ⓐ 옛 자리 쓰기 재현). 기존 시험 2개 보정: `test_team_literal_paths2.sh` 자율 3종(FT_TEAMS_REF=HEAD — 픽스처 origin/main ref 0) · `test_flag_off_scan.sh` 결정 셈(FT_DECISION_AUTONOMY_QUEUE — git 밖 루트).
- 설치: 키트 5(`ft-team-lib.sh` · `ft-proxy-decide.sh` · `ft-autonomy.sh` · `ft_decision_count.py` · `ft_team_lib.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 5 · 홈 0 · plist 0 · 되돌림 = `.bak-r515`.
- 범위 밖: v6 라이브 가지에 main 병합 · 옛 `design/planner/AUTONOMY-QUEUE.md` 기존 줄 이관(planner 손) · 큐 묶음 질문(r165) · 자율 중 질문 0(r291) · 셈 분모(r337) · nano-reopen 카드 읽기(cwd 그대로).

## 2026-10-20 — 하네스 시험 RED 8개를 «기존 RED» 로 두지 않고 원인 분류 → 시험 7 + 도구 1줄 (r509 · 1.1.72)

- 사건: 팩 origin/main 에서 RED 인 시험 8개(셸 6 · pytest 2)가 나노 증거마다 «기존 RED 제외» 로 밀려 왔다(harness master 82 발주 117070 · arch 105 분류 · 판정 1395). 분류 실측: 픽스처 누락 1 · 리포 분리·ref 명단 뒤 환경·배치 전제 5 · 낡은 대조 1 · 도구 결함 1.
- 시험(7 · 도구 0): ①`test_tick_line` — BYZ `tests/fixtures/tick_line/` 18파일을 `harness/fixtures/tick_line/` 로(시험 FX 경로 그대로 · `git show` · 내용 0 변경) · 픽스처에 가려 있던 14개 = 임시 bin 에 `ft-seat-status.sh` 만 복사(r504 판정 본문 `ft_seat_turn.py` → `ft_api_outage_util` 짝 누락) → `*.py` 같이 복사 ②`test_team_literal_paths2` 22개 — 린트 명단 = 시험이 만든 «전환 중» 명단(`FT_TEAMS_MD` · 팩엔 design/TEAMS.md 0) · 픽스처 리포에 origin/main ref · `FT_TEAMS_REF=HEAD`(R416 slots · r495 close 원장) · 제안서 판정 원장 = ref 트리(r492 — 옛 «v6 워크트리 폴더» 기대 폐기 · 두 꼴에 원장 = 추측 0 REJECT 단언 추가) · close 의 `ft-seat-reap.sh`(r448) 대역 · drift 키트 경로 = 팩 배치 · fail-closed 문구 = «ref 못 읽음» ③`test_ft_tick_master_seat` — `FT_TICK_RESUME=0`(죽은 좌석 감시는 R27 밖 · 실 tmux·자율 상태 읽기 0) ④`test_harness_root` ⓒ — 뉴스 틱 ⑥ 은 r484 부터 같은 bin 실 렌더러 → 가짜 렌더러 삭제 · 픽스처 `🔄` 줄 + `.fable-team/seats.json` · «ERROR 0» 단언이 Traceback 도 잡게 ⑤`test_news_tree_root` 대조 — «옛 판» = r489 직전 `86257c17` 고정(origin/main 은 이미 새 판) ⑥`test_team_tick_unify` ⓖ H2 = **시험** — r385 글자 치환이 `ft-tick-install.sh` 거부 패턴만 `harness/bin`·`harness/kit/fable-team/bin` 으로 바꾸고 시험은 옛 `scripts/fable-team-bin`(BYZ main 에도 없음) → 새 두 경로 거부 단언 ⑧`test_news_status_section.py` KIT = `harness/kit/fable-team/bin`.
- 도구(1줄): ⑦`ft_news_publish.py` `_KIT` = `harness-install/slack-mirror`(r385 뒤 없는 폴더) → `kit/slack-mirror`(bin·kit cmp0) · 설치본 없는 시험·개발 판에서 magazine_slack 못 찾던 결함 · 라이브는 `~/.hermes/scripts` 로 찾아 동작 변경 0.
- 시험: 대상 8개 고치기 전 FAIL 1·84·1·1·22·4 + pytest 2 → 뒤 전부 rc0(origin/main 93f3dcca 병합 판) · 원문 `harness/evidence/r509/tests-rc-target8.txt` · 기존 시험 전체(셸 246 + pytest · 부하로 85번째 뒤 정지 → 이어 실행) = 이 단위 밖 RED 셸 64개 중 62개 main 93f3dcca 와 같은 rc·FAIL 수 · 2개(goal_table_gate·wt_clean_two_stage)는 병합 판 재실행 rc0 · pytest 104 failed 전부 main 에도 있음(main 106 = 104 + 이 단위가 고친 2) · 내 판에만 있는 실패 0 — 원문 `harness/evidence/r509/baseline-compare.txt`·`tests-rc-all.txt` · 밖 RED 는 r481(7) 과 별도 고침 단위 후보. 설치: LIVE_BIN 키트 1(`ft_news_publish.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r509`).

## 2026-10-20 — 범위 분류표: 낱말 금지(과금·키)는 문서 줄 아래 · 경로로 지정한 문서 금지만 위 (r514 · 1.1.71)

- 사건: 자율 범위 분류기 BYZ 내장표(`autonomy_scope_rules.py` · 위에서부터 첫 일치)에서 낱말 금지 줄(과금 `billing|credit|payment|pricing|toss|subscription` · 키 `credential`)이 문서 줄 `^(design|docs)/.*\.md$` 위에 있어, 이름에 그 낱말이 든 문서만 바꾼 PR 이 FORBID — BYZ PR 2143(`docs/architect/CFO_BILLING_SOVEREIGNTY_ARCHITECTURE.md` 1파일) → `SCOPE-REJECT FORBID kind=billing`(planner 쪽지 118375 · master 82 발주 118379 · arch 106 실측: BYZ origin/main design·docs 아래 .md 중 같은 꼴 398개).
- `kit/fable-team/bin/autonomy_scope_rules.py`(bin cmp0): billing 줄 → 경로 `^docs/architect/COST_BASE_TABLE\.md$`(문서 줄 위 그대로) + 낱말(문서 줄 아래 · code 줄 위) · key 줄 → 경로 `^secrets/|….env…|\.cred$`(위 그대로) + 낱말 `credential`(문서 줄 아래). ddl·deploy·deps·global-rule·docs·code 순서·정규식 그대로 · 분류기·팩 표 tsv 변경 0. 코드 파일은 문서 줄에 안 맞으니 지금처럼 낱말 줄에 걸린다.
- 시험 `test_scope_classify_keyword_docs.sh`(새 · 임시 리포 · 외부 호출 0 · GIT_* env 0): ⓐ 낱말 문서 → CLASS docs ⓑ `gateway/billing/x.py`·`design/billing/x.py`·`docs/payment.sh` → FORBID billing ⓒ 문서+코드 → FORBID billing(코드 경로) · 변이(문서만) → docs ⓓ COST_BASE_TABLE.md → billing · CLAUDE.md·`.claude/`·COMM-GUIDE → global-rule ⓔ `design/x/credential-rotation.md` → docs · `shared/credential_store.py`·`secrets/a.json`·`docs/x.cred` → key + 분류표 순서 검사 = 19 PASS · 고치기 전 FAIL 6(`harness/evidence/r514/before-fix.txt`). 기존 `test_autonomy_scope_classify.sh` f5(`design/billing-notes.md` → FORBID) 는 이 변경이 바꾸는 꼴 그대로라 f5 = 코드 경로 FORBID + f5b = 문서 docs 로 나눔. 실데이터 = BYZ origin/main 낱말 문서 398 → docs 398 · 그 밖 낱말 경로 1747 → code 0(`byz-main-paths.txt`).
- 설치: 키트 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r514`(분류표 줄 순서 원복).
- 범위 밖: «*.md 전부 docs»(원가 정본·규칙 문서까지 풀림) · 루트 *.md(지금처럼 code) · `.env` 경로 줄이 `x.environment.md` 같은 문서 이름에 맞는 꼴(실측 0 · 별 카드 후보) · 학습 키(--learned).

## 2026-10-20 — DA 용 codex 래퍼: 헤드룸 «건너뛰기» 헤더로 본문 접힘 0 (r513 · 1.1.70)

- 사건: codex 는 전역 `~/.codex/config.toml` `model_provider = "headroom"`(127.0.0.1:8790)을 타고, 헤드룸 0.33.0 은 큰 `/v1/responses` 요청 본문을 «캐시 참조»로 접는다(`proxy.log:3664` 1093262→934768 bytes). 원문 조회 `headroom_retrieve` 는 DA 의 `approval_policy = "never"` 가 거부(«MCP tool call requires approval, but approval policy is never») → DA 가 본문 대조 0 으로 «검증 불가» HOLD · 라운드 1회 소진(ops org-pick DA② r3 · arch 106 실측 · master 82 발주 118143).
- `kit/fable-team/bin/ft-da-codex.sh`(새): `--cwd <폴더> --prompt-file <파일> --out-dir <폴더> [--model gpt-6.1-sol] [--effort high]` → `codex exec --skip-git-repo-check -C <cwd> -c model=… -c model_reasoning_effort=… -c 'model_providers.headroom.http_headers={"x-headroom-bypass"="true"}' "<머리말>\n<프롬프트>" < /dev/null` 전경 실행(백그라운드 0). 경로(8790→8317)·계정 회전·모델 그대로 · 헤드룸은 `Responses passthrough reason=bypass_header mutation=disabled`(arch 106 실행 시험 `proxy.log:3677`). 출력 = `<out-dir>/da-<YYYYmmdd-HHMMSS>-<pid>.out` 실행마다 새 이름(있으면 `-<n>` 덧붙임 · 덮어쓰기 0 — 10-20 chatbot «판정 파일 덮어씀» 계열 차단) · stdout+stderr 함께(실행 헤더 `model:`/`provider:` 두 줄 보존) · 끝줄 `OUT <경로> rc=<n>` · rc = codex rc. 머리말 1줄 «파일은 sed -n 으로 400줄 이하씩 나눠 읽는다 · 본문을 못 봤으면 HOLD 대신 «검증 불가 — <파일:줄>» 로 적는다»(codex 자체 도구 출력 잘림 — 216 KB cat 중간 줄 UNREADABLE, 헤드룸과 무관). 프롬프트 파일 없음·빈 파일·`--cwd`/`--out-dir` 없음·모르는 인자 = rc2 + 사유(codex 0 · 출력 파일 0).
- 시험 `test_da_codex_wrapper.sh`(새 · PATH 앞 가짜 codex · 외부 호출 0 · 헤드룸 0 · GIT_* env 0): ⓐ 인자(bypass 헤더 · sol · high · `--skip-git-repo-check` · `-C` · stdin 0 바이트) ⓑ 새 파일 이름·두 번 실행 = 파일 2개·헤더 두 줄·끝줄 ⓒ 머리말 첫 줄 + 원문 둘째 줄 ⓓ `--model`/`--effort` 덮어쓰기 · 없음/빈 파일/`--cwd` 없음 rc2 ⓔ codex rc7 → 래퍼 rc7 + 파일 남김 · `&` 0 · 느린 codex 끝난 뒤 래퍼 종료 = 25 PASS(bash5 + /bin/bash 3.2) · 고치기 전 FAIL(`harness/evidence/r513/before-fix.txt`) · shellcheck rc0(래퍼) · tmp-trap-lint PASS.
- 설치: 키트 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0(지침 1줄 = 착지 뒤 arch 손) · plist 0 · 되돌림 = 래퍼 대신 옛 `codex exec` 1줄.
- 범위 밖: 헤드룸 설정·기동 인자 · 전역 `~/.codex/config.toml`(일반 codex 작업은 압축 그대로) · 승인 정책 완화 · 시간 상한 추가·변경 · DA 좌석 정의 파일.

## 2026-10-20 — 공용 루트 설치가 등록 워크트리의 연결 파일(shim) LIVE_BIN 도 새 판으로 (r512 · 1.1.69)

- 사건: `install.sh --apply --project <공용 루트>` 는 공용 루트 `.fable-team/LIVE_BIN` 만 바꾸고, 연결 파일은 «자기 워크트리 ../LIVE_BIN» 1줄을 읽어 자기 LIVE_BIN 을 가진 워크트리는 옛 판으로 돌았다(arch 106 실측 04:2x · 16곳 중 12곳 1.1.49~1.1.64 · v6-realtime-live 는 설치마다 master 손 보충 · master 82 발주 117810).
- `harness/install.sh`: 공용 루트 shim 단계 «뒤» `wt_shim_refresh` — `git worktree list --porcelain` 중 공용 루트 아님 ∧ `<wt>/.fable-team/LIVE_BIN` 실재 ∧ bin 에 머리 2줄 `# ft-root-bin-shim:` 파일 1개 이상인 워크트리마다 같은 설치본 `ft-root-bin-shim.sh --root <wt> --live <새 bin> --repo --path --ref`(같은 키트 트리) → LIVE_BIN 갱신 + 새 도구 이름 연결. 줄 = `REFRESHED wt-shim <wt> <옛> -> <새> · SHIM …` / `OK wt-shim <wt> (같음)` / `SKIP wt-shim <wt> (shim 아님|폴더 없음)` / `ERROR wt-shim <wt> rc=<n>: …` · 끝줄 `WT-SHIM refreshed=N skip=M fail=K` · K>0 = 다음 워크트리 계속 + 끝 `INSTALLED <v> · WT-SHIM ERROR — LIVE_BIN 전환은 끝났다 …` rc1(조용한 통과 0). dry-run = `PLAN wt-shim <wt> <옛> -> <새>` + `WT-SHIM plan=N skip=M` · 쓰기 0. 워크트리 `--project` 설치 = 순회 0. 옛 통째 사본 bin 은 손대지 않는다(이동 0 · install-check STALE-COPY 그대로).
- 카드와 다른 점 1: `--live-root` 는 워크트리에 LIVE_ROOT 파일이 «없을 때만» 공용 루트로 준다(있으면 인자 0 = 보존) — shim 도구는 인자가 없으면 라이브 bin/../.. 를 데이터 루트로 적기 때문.
- 시험 `test_install_worktree_shim.sh`(새 · 임시 리포 C + W1 shim · W2 옛 사본 · W3 없음 · 임시 HOME · 가짜 launchctl): ⓒ dry-run PLAN 1줄·쓰기 0 ⓐ W1 LIVE_BIN = B · 새 이름 연결 · LIVE_ROOT 보존 · `refreshed=1 skip=1 fail=0` ⓑ W2 바이트 그대로·stale 0·W3 변화 0 ⓔ 두 번째 `refreshed=0`·쓰기 0 · `--project W1` 순회 0 ⓕ 폴더 없는 워크트리 SKIP ⓓ W1 bin 읽기 전용 → `ERROR wt-shim W1 rc=3` + 끝 rc1 · 공용 루트 전환 끝 = 34 PASS(bash5 + /bin/bash 3.2) · 고치기 전 FAIL 16(`harness/evidence/r512/before-fix.txt`). 기존 install 시험 6 rc0 · `test_live_install.sh`·`test_harness_root.sh` ⓒ 는 base(origin/main) install.sh 로도 같은 FAIL(이 변경과 무관 · 원문 `tests-rc.txt`). 실 공용 루트 dry-run = `WT-SHIM plan=18 skip=0` · 옛 판 11(`dry-run-common-root.txt`).
- 설치: 설치기 1(키트 밖) → 다음 `install.sh --apply --project <공용 루트>` 부터 · LIVE_BIN 지도 cmp 대상 0 · 홈 0 · plist 0 · 되돌림 = 설치기 이전 판 + 워크트리 LIVE_BIN 1줄(REFRESHED 줄의 «옛» 값).
- 범위 밖: 옛 통째 사본 워크트리 정리 · 연결 파일이 공용 루트 LIVE_BIN 을 직접 읽게 바꾸기(별 카드 후보) · 다른 리포 루트.

## 2026-10-20 — nano-close --wt 팩 경로: 하네스 팩 나노의 ⑥·⑤·미커밋을 팩 리포 기준으로 대조 (r508 · 1.1.68)

- 사건: 하네스 팩 나노(작업 = `ai-feature-pack/.worktrees/<…>` · 카드 «세트:» = 팩 커밋)는 `ft-nano-close.sh` ⑥ 이 BYZ 쪽 같은 이름 워크트리(spawn base) HEAD 와 대조해 병합 뒤 항상 REJECT · `--wt` 명시 모드도 BYZ 등록 워크트리만 받아 팩 경로 거절 → 매번 `--suspended` 우회(r499·r502·r466 실사건 · harness master 82 발주 116983 · arch 105 실측).
- `ft-nano-close.sh`(kit↔bin cmp0): `--wt` ⓐ — BYZ 조건이 아니면 `FT_PACK_ROOT`(기본 `$HOME/Project/ai-feature-pack`)의 `.worktrees/` 아래 ∧ 그 리포 `worktree list` 등록이면 대조 리포 `SEAT_REPO` = 팩 · 카드 해석 뒤 머리 `- 설치: 있음`(하네스 카드) 아니면 지금 ⓐ REJECT 문구 + 덧말 «팩 경로는 하네스 카드(- 설치: 있음)만». ⓑ 브랜치·ⓔ 미커밋·⑥ 증거 줄(`--repo` = 팩 워크트리)·⑤ cherry(`--repo` = 팩 리포 · origin/main 재대조·fetch 포함)·feat fetch·base sha 조상 = `SEAT_REPO`(기본 `$ROOT` — 다른 경로 변화 0) · 팩 모드 feat 기본 = origin/main. 정리 계획 0 + `INFO 팩 워크트리 정리 = 별 경로` 1줄 · 원장 `mode=pack-wt wt=… branch=… repo=…`.
- 카드와 다른 점 2(실사건 꼴): ①pane cwd(ⓒ)는 BYZ 쪽 같은 좌석 표준 워크트리라 «--wt 또는 그 표준 워크트리» 를 받는다 ②spawn 이 BYZ 쪽에 같은 이름 워크트리를 만들어 «표준 전용 워크트리가 따로 있다» REJECT 가 늘 걸린다 — 팩 모드만 그 검사를 건너뛴다. `_fetch_remote_feat` 는 `${SEAT_REPO:-$ROOT}`(함수만 떼어 쓰는 `test_nano_feat_remote_ref.sh` 호환).
- 시험 `test_nano_close_pack_wt.sh`(새 · 임시 리포 R·P + P bare 원격 · 외부 호출 0) ⓐ 팩 경로 CLOSED(고치기 전 FAIL 8 · 뒤 PASS) ⓑ 제품 카드 → ⓐ REJECT ⓒ 미등록 폴더 → REJECT ⓓ 팩 미커밋 → ⓔ REJECT ⓔ 인자 없음 → BYZ HEAD 대조(변경 0) · 기존 `test_nano_close_*.sh` 8 rc0 · 관련 시험 7 = base 대비 새 FAIL 0(기존 RED 그대로). 증거 `harness/evidence/r508/`.
- 설치: 키트 1(`ft-nano-close.sh`) → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r508`.

## 2026-10-20 — push 게이트 새 가지 range = merge-base(origin/main, tip)..tip · 훅이 처음 키트에 들어옴 (r511 · 1.1.67)

- 사건: 문서 3파일 새 가지 첫 push 가 `PUSH_DENIED «range 에 제품코드»` → `FT_PUSH_DA6_OK` 우회 기록(v65 쪽지 117396 → planner 117419 → harness master 82 발주 117428). 원인: `pre-push:27-28` 새 가지(remote_sha 0)면 `range="$local_sha"` — `git diff --name-only <커밋>` 은 «그 커밋 ↔ 작업 트리» 라 미커밋 변경을 잡고(오탐) 올라가는 제품 커밋은 놓친다(누락 — 작업 트리가 깨끗하면 제품 커밋 가지도 통과). `:33` `2>/dev/null` 이 diff 실패를 «hits 없음 = 통과» 로 삼켰다.
- 훅이 처음 키트에 들어옴: `kit/fable-team/githooks/pre-push`(새 · 출발점 = 공용 루트 손 설치본 09-09 바이트 그대로 → 구조 커밋) — 설치하면(`install.sh --apply` GITHOOKS 줄) 공용 루트 판을 덮고 `pre-push.bak-<버전>` 을 남긴다. 정본 위치 = 팩 키트.
- 고침: 새 가지 `base=$(git merge-base origin/main "$local_sha")` · 비면 `PUSH_DENIED — 새 가지 기준(merge-base origin/main) 못 구함 — 거부 유지` rc1 · 있으면 `range="$base..$local_sha"` · diff rc≠0 = `PUSH_DENIED — range diff 실패 — 거부 유지` rc1(조용한 통과 0). 기존 가지 `remote..local`·`FT_PUSH_DA6_OK` 우회 기록·GATE_BRANCH·PRODUCT_PATHS 그대로.
- 시험 `test_pre_push_range.sh`(새 · 임시 bare origin + 클론 · stdin 직접 · push 0 · 가짜 bd): ⓐ 새 가지 문서 + 미커밋 gateway → 통과 ⓑ 새 가지 gateway 커밋 → 거부 + `range: <mb>..<tip>` · 우회 기록 ⓒ 기존 가지 문서 통과·제품 거부 ⓓ origin/main 없음·diff 실패 → 거부 ⓔ GATE_BRANCH 아님 → 검사 0 = 11 PASS(bash5 + /bin/bash 3.2) · 변이(옛 설치본) FAIL 7. shellcheck -S warning = 옛 줄 `:24` SC2034(local_ref·remote_ref) 만. 원문 = `harness/evidence/r511/tests-rc.txt`(고치기 전 = `before-fix.txt`). 기존 `test_evidence_log_gate.sh` ⓖ 기대값 = 키트 githooks 2개(`GITHOOKS copied=2`·2회째 `same=2`) + pre-push cmp0·실행 비트 1줄 · 병합 HEAD 재실행 = `merge-head-rc.txt`.
- 범위 밖: 다른 githooks(commit-msg·post-*·prepare-commit-msg) 키트 이관(같은 «손 설치» 꼴 — 별 카드 후보) · GATE_BRANCH 확장 · `--no-verify` 차단.

## 2026-10-20 — 뉴스 갈래 상한의 CLI 기동 고정비 = 잠정 3.5초 → 실측 p90 · 지도 실패 연속 3틱 = 고정 문구 «뉴스 지연» 1번 (r510 · 1.1.65)

- 사건: 부하 48~52 에서 뉴스 HTML 이 02:08 뒤 발행 0 — `/tmp/byz-ft-news-planner.log` «ERROR 지도 만들기 실패 — 발행 0: opencode run summary 실패(…): summary 상한 24s 초과(총 마감 70s)» 8회 연속(arch 105 자체 발견 · master 82 117315). 원인: 갈래 시도당 상한 `min(FIXED_S 3.5 + 7 × ceil(단위), 70)` 의 CLI 기동 고정비 3.5초가 «잠정값» — 부하 50 에서 `opencode run --standalone` 기동이 그보다 훨씬 길어 1차·재시도 둘 다 첫 출력 전에 상한 도달(성공 판에도 갈래 40~52초 = 재시도 성공이 이미 섞여 있었다).
- `ft_news_html_render.py`(kit↔bin cmp0): ①`_once` 가 stdout 첫 바이트 시각을 잰다(파이프 2개 읽기 스레드 · 프로세스가 끝나도 손주가 파이프를 쥐면 상한까지만 · 넘으면 묶음째 kill 그대로) ②시도마다 기동 기록 `<루트>/.fable-team/state/news-cli-startup.tsv`(env `FT_NEWS_STARTUP_LOG`)에 `시각\t갈래\t첫 출력까지 초` 1줄 · 시간 초과(출력 0) = `>상한`(하한값 — 다음 틱이 올려 잡는다) · 최근 20줄 · 쓰기 실패 = `WARN 기동 기록 못 씀 — 발행은 계속` ③`fixed_s()` = env `FT_NEWS_FIXED_S` › 기록 p90(nearest-rank) › 기록 3개 미만 = 잠정 3.5 · `cap_s(prompt, part, fixed)` = `min(fixed + 7 × ceil(단위), 70)` · 갈래 4개가 같은 값(호출 1회에 한 번 셈) ④`fixed ≥ 70` = stderr `WARN 기동 고정비 p90 <n>s ≥ 천장 70s — 갈래 상한 = 천장`. 천장 70초·재시도 1회(첫 출력 전만)·총 마감 70초 그대로(하드 룰 12 «CLI 기동 고정비를 따로 더하되 천장은 같다» 안 — 잠정값을 실측으로).
- `ft_news_html.py`(kit↔bin cmp0): «만듦» 줄에 `fixed=<값>s` · 틱의 지도 만들기 실패(모델 갈래 실패)가 연속 `FT_NEWS_DELAY_TICKS`(기본 3)틱이면 `publish_line` 으로 고정 문구 1번 «뉴스 지연 — 사유: <첫 실패 줄 120자> · 마지막 판 HH:MM(<직전 판 링크>) · 부하 <load1>»(정지 1건당 1번 · 발신 실패면 다음 틱 재시도 · 모델·판단·요약 0 · 상태 `<state>/news-delay.json`) · 다음 지도 발행 때 «뉴스 복구 HH:MM · 지연 N분»(N = 직전 판부터) · 지연 글을 안 냈던 짧은 정지는 조용히 지움. «재시도 대기» 틱은 셈 밖(시도 0).
- 시험: `test_news_html_cli_startup.py`(새) ⓐ 기록 0·2개 = 3.5 ⓑ 기록 10개 p90 = 4.5 · `FT_NEWS_FIXED_S=3.5` 이면 느린 갈래 두 시도 초과 · 실측 고정비면 성공 ⓒ p90 ≥ 70 = 상한 70 + WARN · 만듦 줄 `fixed=70.0s` ⓓ 시도마다 1줄·최근 20·시간 초과 `>1.8` 2줄·쓰기 실패 WARN + 발행 계속 ⓔ 고정비 60 이어도 총 마감 3초 안 · 재시도 0 ⓕ 실패 3틱 → 지연 글 1 · 4틱째 0 · 성공 → 복구 줄 1 · 2틱 정지 = 조용 = 9 passed · 변이(origin/main 판 2파일) FAIL 7. 기존 `test_news_html.sh`·`test_ledger_repo_sync.sh` rc0(픽스처 `oc` 에 기동 기록 tmp 격리 · 상한 대역 lambda 인자 1 추가). 원문 = `harness/evidence/r510/tests-rc.txt`.
- 설치: LIVE_BIN 키트 2(`ft_news_html_render.py` · `ft_news_html.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r510` 또는 env `FT_NEWS_FIXED_S=3.5`(옛 상한 · 지연 글은 `FT_NEWS_DELAY_TICKS` 를 크게).

## 2026-10-20 — 완성 이동의 정본 갱신 요청 쪽지 = 카드 팀 명부의 `_arch` 로(기본 v65 명부 고정 0) (r487 · 1.1.64)

- 사건: loom 카드 완성 이동(`design/teams/loom/indices/완성/loom-canon-plan-l1-l3.md`)의 «정본 갱신 요청» 쪽지 114386 이 v65 arch 264 에게 갔다(v65 arch 264 요청 114392 → harness arch 103 카드). 원인: `ft-index-move.sh:161` `SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"` — 주석은 «팀 현역 arch» 인데 env 가 없으면 기본 명부(= v65 `_label`)로 고정.
- `ft-index-move.sh`(kit↔bin cmp0): 쪽지 직전에 팀 해석 — 명단(카드 워크트리 `design/TEAMS.md`) 팀마다 `ft_team_has <팀> <카드 indices 폴더>/ indices/`(쌍둥이 둘 다) · 정확히 1팀 = 그 팀 · 명부 = `seats-<팀>.json`(v65 = `seats.json`) · `FT_SEATS_JSON` 명시가 이김. 0·2+ 팀 = `INFO 정본 쪽지 생략 — 팀 못 정함(명단 팀 N개 · <카드>)` · 명부 파일 없음 = `INFO 정본 쪽지 생략 — 팀 명부 없음(<팀>)` · 출력 `NOTIFIED 정본 갱신 요청 → <arch> (팀 <팀>[ · 명부 FT_SEATS_JSON])` · INFO(_arch 없음)·WARN(발신 실패) 줄에도 팀 글자. 이동·원장·종료코드 변경 0(게이트 아님) · 명부 쓰기 0 · v65 카드 수신자 그대로.
- 시험: `test_index_move_canon_route.sh`(새) ⓐ 팀 a 카드 → `seats-a.json` `A#1` · `V#1` 0 ⓑ `FT_SEATS_JSON` 명시 → `V#1` ⓒ 팀 b(명부 없음) → 쪽지 0 + INFO · 이동 rc0 ⓓ v65 카드 → `seats.json` `V#1` = 5 PASS(bash5 + /bin/bash 3.2) · 변이(origin/main 판) FAIL 4. 기존 `test_index_move_canon_landed.sh` 18·`canonize` 22·`rule_line` 17·`slack` 14 rc0 · shellcheck -S warning rc0. 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · 되돌림 = 설치본 `.bak-r487`. 원문 = `harness/evidence/r487/tests-rc.txt`.

## 2026-10-20 — nano-close --never-started: 발주를 한 번도 처리 못 한 나노(산출 0)를 «한 일 0» 4값으로 닫는다 (r506 · 1.1.63)

- 사건: loom g5a·g5b 정본 나노 #0 — 발주 116731 을 받고 처리 0 · `ft-nano-close.sh` 가 ①`--result` ②`--recv` ⑥증거 줄을 요구해 닫을 경로가 없었다(산출·회수 seq·증거 줄이 원래 없다). 좌석이 자원을 쥔 채 남는다(골 6).
- `ft-nano-never-started-check.sh`(새): ⓐ턴 0 — claude = 좌석명 jsonl 의 assistant(`<synthetic>` 제외) · opencode = opencode.db(`FT_OPENCODE_DB`) 읽기 전용 · session.directory == 워크트리 실경로(또는 아래) ∧ time_created ≥ `.worktree-info.json` created_at 의 assistant 메시지 · 세션→메시지 2단 질의 + 진행 처리기 7초 상한(통째 join 은 실 db 5GB 에서 7.3초 실측) · db 없음·잠김·스키마 다름·그 밖 에이전트 = 확인 못 함 ⓑbase(--base › 카드 base_sha › info base_sha) 위 커밋 0 ⓒ미커밋 0(`status -uall` · 노이즈 `.worktree-info.json`·`next-env.d.ts`·`tsconfig.json`·`.serena/project.yml` 제외) ⓓ발신 쪽지 0(mailbox.log.jsonl + .1) · `--successor-auto`(설계 r2 규칙 2·3): 같은 계보 더 큰 번호 좌석이 tmux 생존 ∧ pane toplevel == 워크트리 ∧ 명부 행 실재·`_replaced_by` 없음 → `SUCCESSOR <이름>` · ⓑⓒ 생략 · 못 셈 = `SUCCESSOR unknown` → 4값 전부.
- `ft-nano-close.sh --never-started "<사유>"`: ①② 면제 · ⑥ 자리 = 위 검사기 · ③ jsonl 없을 때 워크트리 mtime 후퇴 끔(공유 워크트리 후계 편집이 섞인다 · 유휴는 턴 0 이 대신) · 후계 있으면 ⑤ cherry·정리 계획 0 · 출력 `CLOSED <좌석> never-started «<사유>»` / `CLOSED <좌석> never-started (공유 워크트리 → 후계 <이름> · 워크트리 정리 0)` · 원장 ①② 칸 = 면제 표기 · 빈·여러 줄 사유·`--superseded-by`·`--suspended`·`--shared-wt` 동시 = usage 2 · 인자 없으면 불변 · 브랜치 삭제 0.
- 카드와 다른 점 1: 노이즈에 `.serena/project.yml` 추가(nano-close 기존 노이즈 · Serena activate 가 매번 고친다). 2: 검사기 인자 `--card`·`--comm`·`--seats` 추가(base_sha 출처 · 우편함 · 후계 명부).
- 시험 `test_nano_close_never_started.sh`(새) ⓐ~ⓝ(155 PASS) + 셀 수 없음 4 + usage 7 + 불변 · 기존 `test_nano_close*.sh` 7개 rc0 · `test_nano_close_suspended.sh` 숫자 검사의 `grep -n` 줄 번호(600) 오탐 제거(기대값 변경 0).
- 개정 r3 규칙 2b(`--landed-auto`): 후계가 없고 센 커밋이 0 이 아니면 `ft-landed-check.sh <리포> ${FT_NEVER_MAIN_REF:-origin/main} <가지> <키>`(7초 · perl alarm) rc0(ancestor·cherry·card)일 때 `LANDED <근거>` · 커밋 수만 생략(미커밋·턴·발신 그대로) · 같은 닫기(⑤·정리 계획 0) · 출력 `CLOSED <좌석> never-started (착지 가지 <근거> · 워크트리 정리 0)` · grep·no·판정 실패 = 적용 0. 0 커밋 가지는 늘 ancestor 라 2b 를 타지 않는다(기본 닫기·정리 계획 그대로).
- 실사건 실측(읽기 전용 검사기): loom #0 → r2 만으로는 `SUCCESSOR none`(후계 #1 이 먼저 닫힘) · `REJECT never-started: 커밋 8` → r3 뒤 `SUCCESSOR none · LANDED cherry · NEVER-STARTED ok turns=0 commits=skip(landed cherry) dirty=0 sent=0` rc0(1초).
- 설치: 키트 2(`ft-nano-close.sh` · `ft-nano-never-started-check.sh` 새) → LIVE_BIN cmp0 2 · 홈 0 · plist 0.

## 2026-10-20 — ft-tick shellcheck RED 고침: renamed_watch 명부 인자 = 배열+glob(ls 파싱 0) · SC1091 source 지시 (r507 · 1.1.62)

- 사건: 팩 시험 `test_ft_tick_passes_shellcheck`(shellcheck rc0 단정)가 RED 인 채로 r478·r479·r503 증거에 «기존 RED» 로 적혀 왔다(harness master 82 발주 116983 · arch 105 실측). 원인 2: ①`ft-tick.sh:444` `renamed_watch` 의 `$(ls "$(dirname "$SEATS")"/seats-*.json 2>/dev/null)` 따옴표 없는 명령 치환(SC2046 warning · r468 95fe73bb 가 넣은 줄 — 공백 있는 명부 이름이 쪼개진다) ②`:42` `. "$HERE/ft-harness-root.sh"` 의 SC1091(info) — info 도 shellcheck rc1 이라 ①만 고치면 시험이 계속 RED(카드 ⓐ 조건 실측).
- `ft-tick.sh`(kit↔bin cmp0): ①`local … f seatfiles=()` · `for f in "$(dirname "$SEATS")"/seats-*.json; do [ -e "$f" ] && seatfiles+=("$f"); done` → `"$RENAMED" watch "$MBOX" "$SEATS" ${seatfiles[@]+"${seatfiles[@]}"}`(bash 3.2 + `set -u` 빈 배열 안전 · 0개면 인자 0 — glob 글자 안 넘어감) ②`MBOX=…` 줄을 둘로 나눠 `[ -n "$MBOX" ] || { . …; }` 앞에 `# shellcheck source=/dev/null`(지시는 «다음 명령» 에만 걸려 한 줄 `a; b || {…}` 에선 `.` 에 안 닿음 · `source=ft-harness-root.sh` 는 -x 없이 여전히 SC1091 — 실측). 동작 변경 0.
- 시험: `test_ft_tick_renamed_args.sh`(새) — renamed_watch 함수만 떼어 가짜 RENAMED(argv JSON) · 명부 2개(`seats-a.json`·`seats-b c.json`) → 인자 2개 정확히 · 0개 → 인자 0 · bash5 + /bin/bash 3.2 = 6 PASS · 변이(origin/main 판) FAIL 3. `shellcheck ft-tick.sh` rc0 · `test_ft_news_ledger.py` 24 passed(shellcheck 시험 포함) · 틱 시험 `test_team_rename.sh` 86·`test_tick_shim_guard.sh` 26·`test_tick_team_msg.sh` 32·`test_board_publish_tick.sh` 14 rc0. origin/main 에서도 같은 수로 RED 인 시험 3(이 단위 밖 · 고침 단위 후보로 master 에 보고): `test_ft_tick_master_seat.sh` FAIL 4(dead_seat_watch `ERROR autonomy mode unreadable (none)`) · `test_tick_line.sh` FAIL 84(픽스처 `fixtures/tick_line/` 없음) · `test_team_tick_unify.sh` FAIL 1(ⓖ H2 `wt/scripts/fable-team-bin` 거부 안 됨). 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r507`. 원문 = `harness/evidence/r507/tests-rc.txt`.

## 2026-10-20 — 승계 은퇴 reap 이 press 서비스(gateway·worker)를 죽이던 결함 — reap 후보에서 서비스 나무 제외 (r505 · 1.1.61)

- 사건: v65 tester 72 은퇴 02:07:34 → 02:07:49 gateway·worker 동시 SIGTERM · tester 73 보고 «reap stopped=2 left=0» · press 회차 nf1·nf2 무효(v65 master 214 쪽지 116837). `ft-seat-retire.sh` 가 부르는 `ft-seat-reap.sh <구> --orphans-only` 의 후보 = uid 같음 ∧ ppid 1 ∧ exe ∉ PROTECT_EXE ∧ env FT_SEAT==좌석(②) — run.command 서비스는 nohup·& 로 떠 ppid 1 + 좌석 env 상속, venv 실행 파일 이름 `python` 은 PROTECT_EXE(`python3`) 밖이라 «감시 루프» 와 같은 모양으로 걸렸다.
- `ft-seat-reap.sh`: 조사마다 «서비스 나무» 를 만든다 — ⓐ`lsof -nP -iTCP -sTCP:LISTEN -Fp`(7 s 상한 · 실패 = rc 20 «조사 실패», rc 1 + stderr 0 만 LISTEN 0) 의 pid + 그 조상(ppid 사슬 · pid 1 앞까지) + 자손 → `service-listen` ⓑ명령 꼴 `SERVICE_RE`(`uvicorn|gunicorn|hypercorn` · `-m worker|gateway` · `next dev|start` · `next-server` · `run.command` · env `FT_REAP_SERVICE_RE` 로 덮기 · 정규식 오류 = rc 20) + 자손 → `service-cmd`. 후보(①②②b③)·자손 루프에서 서비스 나무는 빼고 앞 줄 `reap-skip pid=<n> why=service-listen|service-cmd cmd=<앞 100자>`(첫 조사에서 1회 · stopped·left 에 안 셈 · 끝 줄 형식 그대로). 모든 모드(은퇴 `--orphans-only` · seat-close · nano-close) 공통 — 서비스 정지는 `scripts/server/stop.command` 몫.
- 보호 exe 목록에 이름을 더하는 길은 안 썼다(venv 마다 python·python3·Python 으로 다시 샌다 · `ft-leak-reap.sh` PROTECT_EXE 변경 0). 파괴 경계: kill 대상을 줄이기만 한다(새 kill 0) · r448 루프 회수 그대로.
- 시험 `test_seat_reap_services.sh`(실프로세스 · 표식 r505fx-<pid> 고아만 · tmux 0): ⓐ venv python LISTEN 서비스(ppid 1 · FT_SEAT) 생존 + `why=service-listen` ⓑ LISTEN 없는 `python -m worker.x` 생존 + `why=service-cmd` ⓒ `bash -c 'while :; do sleep 1; done'` 정지 `stopped=1 left=0 rc=0` ⓓ 서비스 자식(bash sleep · FT_SEAT 상속) 닫기 경로에서도 생존 ⓔ `FT_REAP_SERVICE_RE` 덮기 → ⓑ 다시 후보 · 가짜 lsof rc2 → rc 20 + 아무것도 안 죽임 — 고치기 전 판 FAIL 9(서비스 `via=②` 로 정지 · 사건 재현) → 후 ALL PASS. 기존 `test_seat_reap_left0`·`test_seat_retire_keep`·`test_seat_retire_rosters`·`test_seat_close`·`test_nano_close_fail_closed` rc0 · `test_seat_retire` ⑧(`test_ft_tick_master_seat.sh` ft-tick ERROR 4)은 base 10a6a36b 에서도 같은 4 FAIL — 이 변경 무관(따로 보고). 증거 `harness/evidence/r505/`.

## 2026-10-20 — 좌석 턴 판정기 하나(`ft_seat_turn.py`) · 뉴스 HTML·지도 = 좌석별 하위 프로세스 0 (r504 · 1.1.60)

- 사건: 02:07 뉴스 지도에서 실좌석이 일하는 4팀(실통역·방·강의·계획)이 «확인 불가» — `ft_news_html.live_teams` 가 좌석마다 `bash ft-seat-status.sh turn <좌석>`(7초 · 재시도 1 · 풀 32)·`ft-news-tree.py seat_turn` 이 좌석마다 같은 셸(10초)을 부르고, 셸은 다시 좌석마다 폴더 jsonl 전부의 머리 1MB 를 읽고 파이썬을 띄웠다 → 부하 15~56 에서 상한 초과 + 동시 하위 프로세스 수십 개가 부하를 더 올림(arch 105 실측 · master 116770).
- `ft_seat_turn.py`(신설 · 122줄): `turn_of_file(path, tail_bytes, tail_start, master, status_only)` = `ft-seat-status.sh` heredoc 판정 본문을 그대로 옮김(동작 변경 0 · 판정 정본 = jsonl 턴 경계 그대로 · BOOT 18 덧말 0 — 판정기 위치만 모듈로) · `turns(seats, tmux, projects)` = r497 `find_jsonls` 1회(tmux list-panes 1회) + 좌석마다 꼬리만 읽기 · 못 찾음 = («?», «jsonl 없음») · 읽기 실패 = («?», «읽기 실패») · CLI `python3 ft_seat_turn.py <jsonl>` = 탭 5칸(env FT_SEAT_TAIL_BYTES·FT_SEAT_TAIL_START·MASTER·NEED_ENDS).
- `ft-seat-status.sh turn_of_file`: heredoc 대신 `python3 "$(dirname "$0")/ft_seat_turn.py"` — 출력 바이트 같음(시험 ⓔ: origin/main 판과 40석 × 5 플래그 바이트 대조).
- `ft_news_html.py live_teams`: `_turn`·`_turn_once`·ThreadPool·`SEAT_POOL` 삭제 → `_turns()` = `ft_seat_turn.turns` 1회(env `FT_TMUX`·`FT_CLAUDE_PROJECTS` = ft_model_swap 과 같음) · tmux list-panes 7초 초과 = 전 좌석 («?», «tmux 시간 초과») · 사유 칸 = «jsonl 없음 N석 · 읽기 실패 N석»(r490 `unknown_reason` 꼴 · «확인 불가 ≠ 쉼» 유지) · 298→281줄.
- `ft-news-tree.py seat_state`: 지도 1회에 `turns()` 한 번(살아 있는 명부 좌석 전부) 캐시 · UNKNOWN 과 «?»(jsonl 없음 — codex 등) 만 기존 `one` pane 판정(옛 turn 의 jsonl 없음 → pane 경로와 같음 · 10초 상한 그대로).
- 시험 `test_seat_turn_batch.py`(새) ⓐ~ⓔ + tmux 시간 초과 6 passed · 변이 1(PENDING→IDLE) = FAIL 3 · 기존 `test_ft_news_html.py` 38 · `test_ft_seat_turn_window.py` 8 · `test_ft_seat_codex.py` 10 · `test_kit_bin_sync.sh` · `test_news_html.sh` rc0. 기대 변경: `test_ft_news_html.py` r478c·r490 a·b 가 `_turn`(가짜 셸) 대신 `_turns` 를 바꿔치기 · r490 d(풀 32 시험) 삭제 — 풀이 없어졌다(대신 ⓑ «40석 < 7초 · list-panes 1 · seat-status 0»). 기존 실패(origin/main 과 같음): 셸 시험 5(tick_line 84 등) · pytest 3 — 원문 `harness/evidence/r504/tests-rc.txt`.
- 설치: LIVE_BIN 키트 4(`ft_seat_turn.py` 새 · `ft-seat-status.sh` · `ft-news-tree.py` · `ft_news_html.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r504`). 범위 밖: `find_jsonls` 규칙 · 다른 호출처(틱·stall·reclaim)의 좌석별 `turn` 호출 · 판정 규칙 · `skill/scripts`·`comm` 의 옛 ft-seat-status 사본(이미 kit 와 다름).

## 2026-10-20 — 뉴스·매거진이 읽는 원장 사본을 매 회 origin/main 으로 전진 · 매거진 기본 원본 = 뉴스와 같은 사본·새 경로 (r503 · 1.1.59)

- 사건: desk 116740 → harness master 81 발주 116754 — 뉴스 사본 `.worktrees/news-ledger-main`(detached) 은 fetch·전진 주체가 없어 main 뒤 71커밋 · 01:50 원장 착지를 못 보고 «변화 없음» 3회(02:08 master 손 전진). 08:00 매거진은 기본값 `.worktrees/v6-realtime-live`(가지 위 · main 뒤 223) 의 옛 경로 `design/planner/PLAN-oppa-ledger.md`(마지막 10-19 18:55)를 읽는다 — 어느 쪽도 «낡았다» 신호 0. arch 105 실측(카드 Issue ①~⑤).
- `ft-ledger-repo-sync.sh <사본>`(새): 가지 위(symbolic-ref 성공) → `ERROR ledger 사본이 가지 <이름> 위 — 전진 0` rc3 · 추적 파일 미커밋 수정(`status --porcelain -uno`) → `ERROR ledger 사본 미커밋 추적 변경 N — 전진 0 (<첫 경로>)` rc3(미추적 = 뉴스 html 등은 깨끗함) · fetch = `fm_fetch`(ft-merge-lib · 7초 + 재시도 1) 실패 → `ERROR ledger 사본 fetch 실패: <첫 줄>` rc4 · 같으면 `SYNC up-to-date <10자>` · 아니면 `checkout --detach origin/main` → `SYNC <옛 10자>..<새 10자>` rc0 · 출력 1줄 · 삭제 0 · 되돌림 = `git -C <사본> checkout --detach <옛 sha>`.
- `ft_news_ledger.py`: `sync_repo()` — env `FT_LEDGER_REPO` 로 «명시된» 사본만 부름(기본 LIVE_ROOT 공용 체크아웃은 옮기지 않음) · 같은 틱 1회(`FT_LEDGER_SYNCED=1` · 자식도 물려받음) · `FT_LEDGER_SYNC` 로 대역 · 성공 = INFO `SYNC …` · 실패 = ERROR 로그 + `FT_LEDGER_SYNC_ERROR` · `_run` 시작에서 부르고 판 머리(lead) 앞에 «원장 사본 갱신 안 됨 — <사유>» · 발행은 지금 판으로 계속. `ft_news_html.py`: `tick` 이 그 사유를 지도 글 머리(`FT_NEWS_HEAD` 뒤)와 «변화 없음» 줄 꼬리에 싣는다 · CLI(`build`/`run`) 의 `_ledger_args` 도 `sync_repo()`.
- `magazine_from_news.sh`: 기본 `REPO=$ROOT/.worktrees/news-ledger-main` · `REL=design/teams/planner/PLAN-oppa-ledger.md`(뉴스와 같은 사본·경로) · 시작에서 `${FT_LEDGER_SYNC:-<LIVE_BIN>/ft-ledger-repo-sync.sh}` · 실패 → `ERROR magazine_from_news: 원장 사본 갱신 실패 — <출력>` exit 6(낡은 매거진 발행 0) · `FT_LEDGER_SYNCED=1` 이면 건너뜀.
- 시험: `test_ledger_repo_sync.sh`(새 · 임시 bare origin) ⓐ~ⓔ + usage + 공용 config 불변 rc0 · `test_ft_news_ledger.py` r503 4건(뉴스 sync rc3 → 발행 계속 + 머리 ERROR 줄 · 틱 1회·명시 사본만 · 매거진 sync rc3 → exit 6 / rc0 → 진행 · 매거진 기본값 = news-ledger-main + 새 경로) · `test_ft_news_html.py` r503 1건(지도 머리·«변화 없음» 줄 꼬리). 기존 기대 변경: 픽스처 원장 리포(가지 위 임시 리포)는 `FT_LEDGER_SYNCED=1` · 매거진 시험은 옛 경로 픽스처라 `FT_LEDGER_PATH` 명시 · `test_goal_table_gate.sh` 뉴스 호출 `FT_LEDGER_SYNCED=1`. 기존 RED 1(이 단위 밖): `test_ft_tick_passes_shellcheck` = SC2046 `bin/ft-tick.sh:444`(origin/main 과 diff 0). 설치: LIVE_BIN 키트 3 cmp0 + 홈 `~/.hermes/scripts/magazine_from_news.sh` cp+cmp 1 · plist 0(매거진 plist env 2칸은 카드 «지금 할 1줄») · 되돌림 = 설치본 `.bak-r503`. 범위 밖: `ft-weekly-review` 의 `FT_PLANNER_REPO=v6-realtime-live` · 사본 자동 생성. 원문 = `harness/evidence/r503/tests-rc.txt`.

## 2026-10-20 — 선제 회수가 launchd PATH 에서 tmux 를 못 찾아 «후보 0» 으로 조용히 끝나던 결함 (r502 · 1.1.58)

- 사건: harness arch 105 실측 01:5x — `.fable-team/state/reclaim.log` PREVENTIVE 줄 220개가 전부 `candidates=0` · 같은 시각 대화 셸 손 실행은 `candidates=23`. launchd `com.byz.ft-resource-watch`(plist env = `FT_RES_ROOT`·`FT_ROOT` 뿐)가 기본 PATH `/usr/bin:/bin:/usr/sbin:/sbin` 로 돌아 `/opt/homebrew/bin/tmux` 를 못 찾고, `tmux list-sessions … 2>/dev/null` 빈 출력을 «세션 0» 으로 읽었다 — 골 6 장치(압력 때 끝난 좌석 회수 · r500 압력 티어)가 설치 뒤 한 번도 자동으로 안 돌았다.
- `ft-resource-reclaim.sh`: ①머리(--on-reject 통과 분기 뒤)에서 `PATH="$PATH:${FT_RECLAIM_EXTRA_PATH:-/opt/homebrew/bin:/usr/local/bin}"` · `command -v tmux` 없으면 `ERROR tmux 없음(PATH=…)` rc4 ②`reclaim_core` 후보 수집: `tmux list-sessions` rc≠0 이면 stderr 를 다시 받아 `no server running` 만 세션 0 · 그 밖 `ERROR tmux list-sessions rc=<rc>: <stderr 첫 줄>` rc4(요약줄 0 → `ft-resource-preventive.sh` 가 stamp 0 + resource-watch.log `ERROR preventive rc=4 …` · 다음 틱 재시도). 닫기 직전 재확인(`fresh_att` 등)의 tmux 실패는 «후보 탈락» 그대로.
- `ft-resource-watch.sh`: set 직후 같은 PATH 덧붙임 1줄 — 표본·문지기·선제 회수 하위 호출 전부 같은 도구. plist(키트 밖 손 생성물) 수정 0.
- 카드와 다른 점 1: 카드는 PATH «머리» 에 붙이라 했으나 «끝» 에 덧붙인다 — 머리에 붙이면 대화 셸·시험에서 앞선 PATH 를 덮어(시험 가짜 `tmux`·`sysctl` 대역 폴더보다 `/opt/homebrew/bin` 이 먼저 → 시험이 실 tmux 서버를 부른다 · launchd 에서도 `/usr/bin` 의 python3·git 이 홈브루 것으로 바뀐다). 끝에 붙이면 없는 도구만 채운다(tmux·timeout/gtimeout). 시험 ⓓ 는 «PATH 끝 = EXTRA» 로 단언.
- 시험 `test_resource_reclaim_preventive.sh` r502 ⓐ(PATH=/usr/bin:/bin + EXTRA=가짜 tmux 폴더 → candidates=12)·ⓐ'(tmux 없음 → rc4)·ⓑ(list-sessions rc1 → ERROR rc4 · 요약줄·닫기 0 · 잠금 해제)·ⓑ'(preventive 보조 stamp 0 + ERROR 1줄)·ⓒ(no server running → candidates=0 rc0)·ⓓ(`env -i PATH=/usr/bin:/bin` tick → 선제 회수·표본이 받은 PATH 끝 = EXTRA · 미설정 = 홈브루 기본) + 변이 2(tmux 실패=세션 0 FAIL 5 · PATH 덧붙임 제거 FAIL 3) — 87 PASS · 기존 `test_resource_reclaim.sh` 107 · `_pressure.sh` 28 · `test_resource_watch.sh` 75 rc0. 설치: LIVE_BIN 키트 2 cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r502` 2 또는 `FT_RECLAIM=0`. 범위 밖: 다른 launchd 작업(ft-tick·뉴스·매거진) PATH 점검 · 회수 정책값 · r500 판정식. 원문 = `harness/evidence/r502/tests-rc.txt`.

## 2026-10-20 — 회수 압력 티어: swap ≥85% 면 착지 나노 idle 문턱 30→5분 · «병합 끝 나노» = 가지 착지 나노만 (r500 · 1.1.57)

- 사건: harness master 81 실측 115983 — swap 92% 인데 `ft-resource-reclaim` 이 «병합 끝 나노» 9~10석을 idle 30분 가드로 전부 SKIP(RECLAIMED 0) · spawn 문지기가 swap·rate 로 새 좌석을 막아 팀이 섰다. 같은 표에 방금 spawn 된 ops O3·O4(가지 미착지)도 «병합 끝 나노» 로 들어갔다 — 분류가 이름(`*-nano-*#0`)뿐. planner 80 대리 결정 115991.
- `ft-resource-reclaim.sh`: ①`measure_pressure`(한 실행 1번 · `FT_SWAPUSAGE`(시험) 또는 `sysctl -n vm.swapusage` used/total ≥ `FT_RECLAIM_PRESSURE_SWAP_PCT`(기본 85) · 측정 실패 = 압력 아님 + `WARN swap 측정 실패` 1줄) ②`idle_min_for`: 병합 끝 나노 ∧ (카드 완성/ ∨ 압력) → `DONE_IDLE_MIN`(5) ③분류: 이름 `*-nano-*#0` = «나노»(판정 전) → idle(착지 가정 문턱)·attached·보호 1차 거르기 통과분만 `landed_nano` — 가지 `nano/<키>` 또는 가장 큰 `-r<N>` · BYZ 루트와 팩 리포(`FT_PACK_ROOT`) 중 «가지가 있는 리포 전부» 가 `timeout 7 ft-landed-check.sh … origin/main` rc0 이어야 «병합 끝 나노» · 그 밖(grep·no·가지 없음·시간 초과·timeout 도구 없음) = «미병합 나노» → 닫기 0 · idle ≥ 30분이면 표 `HIL(승인 범위 밖: 미병합 나노 — 착지 판정 <근거>)` ④요약 줄 `RECLAIMED N …`·`PREVENTIVE …` 꼬리 `pressure=0|1 swap=<pct>%`(뉴스·감시자 파서는 앞머리만 읽어 영향 0). kit↔bin cmp0.
- 카드와 다른 점 1: 카드 §2 는 «BYZ 에 가지가 있으면 BYZ» 였으나, 하네스 나노는 BYZ 에 커밋 0 인 같은 이름 가지가 있어(이 좌석 실측: BYZ `nano/r500-…` = base c251017221 = main 조상) BYZ 만 보면 늘 ancestor(=착지) 로 읽힌다 → 두 리포 모두 rc0 일 때만 착지(fail-closed) · 시험 ⓖ.
- 시험 `test_resource_reclaim_pressure.sh`(새) ⓐ~ⓖ 28 PASS · 변이 2(압력 티어 제거 FAIL 3 · 착지 판정 제거 FAIL 8) · 기존 `test_resource_reclaim.sh` 107 · `_preventive.sh` 65 · `test_nano_spawn_teamset_cap.sh` 18 rc0. 기대 변경 2: attached 나노 표 종류 «병합 끝 나노» → «나노»(착지 판정 전에 거름) · PREVENTIVE 요약 줄 꼬리. 가짜 세계에 가짜 팩 리포(나노 a~h 가지 = main 조상) · `FT_SWAPUSAGE` 기본 10%(실 sysctl 0). 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0(선제 감시 600초) · 되돌림 = 이 커밋 revert(설치본 `.bak-r500`) 또는 env `FT_RECLAIM_PRESSURE_SWAP_PCT=101`. 범위 밖: 직전 세대·쉬는 역할 좌석 문턱 · `ft-resource-gate.sh` · nano-close 게이트. 원문 = `harness/evidence/r500/tests-rc.txt`.

## 2026-10-20 — 역할 좌석 모델 한도 → 틱이 대체 모델 후계를 자동으로 연다 + R146 모델별 복구 (r497 · 1.1.56)

- 사건: 00:12 harness arch 104(Fable 5.1) 가 «All credentials for model claude-fable-5-1 are cooling down … rate_limit_error» 합성 오류 턴(0초)으로 섰고 master 손 교대(arch 105 · Opus 5.5 · 쪽지 115865)까지 역할이 비었다. 같은 때 R146 은 ①복구 판정이 모델을 안 봐 다른 모델 좌석 하나가 일하자 «장애 끝 00:12 · 약 0분»(115762) + [재개](115763 — 같은 한도에 다시 막힘) ②감시가 틱 명부 1개뿐이라 seats-harness 등은 장애 쪽지 0.
- `ft_model_swap.py`(신설 · 180줄): 명부 «전체»(seats*.json)의 역할 칸(`_master`·`_arch`·`_desk`·`_da`·`_tester` … · `_hil_route` 제외) 현역 claude 좌석 ∧ tmux 생존 → jsonl 을 R146 `analyze` 로 판정(stuck ∧ rate_limit). jsonl 찾기 = `find_jsonls`(tmux pane cwd 인코딩 폴더 · 최근 2일 수정 파일만 · 머리 1MB 를 «한 번» 읽어 전 좌석 agentName/customTitle 대조) — 카드의 `ft-seat-status.sh jsonl`(좌석마다 폴더 jsonl 5989개 머리 전부)은 부하 30 실측 1회 10초라 7초 상한이면 역할 좌석 6석을 못 봤다 · 새 조회 = 실측 2.1초 · 역할 좌석 21/21 찾음 · arch 105 경로 seat-status 와 같음. 정지 < 3분(`FT_MODEL_SWAP_MIN`) 또는 `retry after` 해제 예상 ±3분 = WAIT · 오류 뒤 «같은 바탕 모델» 정상이 어느 좌석에든 있으면 RECOVERED(R146 [재개] 몫) · 이미 교대한 uuid·같은 계보 30분 = NOOP · 그 밖 = 대체 모델(`model-fallback.tsv` 다음 칸 · 그 모델도 최근 10분 같은 한도면 그다음 · 끝 = HIL) 로 `ft-successor-open.sh <구> <cwd> --name <베이스>#(최대+1) --agent claude --model <새> --ctx 1m --effort high --body-file <f>` 분리 실행(1회 1건 · 틱 안 막음 · 로그 `state/model-swap/<후계>.log`). 본문 첫 3줄 = 계보 최신 도달 파일(`state/successor/<베이스>#*.json` reached_at) seq 의 발주 본문 첫 3줄(골 원문) — 없으면 `HIL 골 원문 출처 없음`(교대 0 · fail-closed). 교대 직후 그 명부 `_master`·`_hil_route` 에 `[자동 교대] <구> -> <후계> · <구 모델> -> <새 모델> · 사유 한도`(오류 원문 0) · HIL 쪽지는 같은 uuid 1통. 상태 `state/model-swap/state.json`(손상 = ERROR · 교대 0). 옛 좌석 kill 0 · 원래 모델 복귀 0.
- `model-fallback.tsv`(신설): `claude-fable-5-1 → claude-opus-5-5[1m]` · `claude-opus-5-5 → claude-sonnet-5-5[1m]`(바탕 id = `[1m]` 떼고 비교).
- `ft_api_outage.py`: Cut 에 `model`(문구 `for model <id>`)·`eta`(retry after) · 정상 = (시각, 바탕 모델) — «장애 끝» 은 가장 최근 오류의 모델이 돌아온 때만(모델 미상 = 지금과 같음) · [재개] 는 제 모델이 돌아온 좌석만(아니면 stdout `SKIP 재개 … 복구 전`) · ft_model_swap 이 교대한 uuid(`--swap-state` · 기본 `<상태 폴더>/../model-swap/state.json`) 는 [재개] 0. 200줄 한도로 jsonl 읽기·판정 함수(`records`·`is_error`·`is_normal`·`epoch`)와 r497 보조(`model_of`·`eta_of`·`base_model`·`fallback_table`·`goal_source`·`jsonl_cwd`·`find_jsonls`·`next_name`·`read_table`)를 `ft_api_outage_util.py` 로. `CAUSES` rate_limit 에 «temporarily limiting requests|are cooling down» 추가.
- `ft-tick.sh`: `outage_watch` 뒤 `model_swap` — 명부가 `<루트>/.fable-team/seats.json` 일 때만(팀 틱 seats-<팀>.json 은 건너뜀 · 중복 교대 0) · PLAN·HIL·BUSY 줄은 틱 로그 · 실패 = ERROR 1줄 틱 계속 · `FT_MODEL_SWAP=0` 으로 끔 · `--dry-run` = `DRY kind=model-swap`.
- 시험: `test_model_swap.py` ⓐ~ⓘ + ⓑ2(jsonl 찾기: 3일 전 파일 무시 · 최신 파일 우선) + 틱 dry-run(공용 seats.json 만) + kit↔bin · `test_ft_api_outage.py` 틱 시험 2건 RED 수리(r459 뒤 comm 폴더 없는 임시 루트 → `FT_TICK_MBOX` 지정 · 기대값 변경 0). 설치: LIVE_BIN 키트 4(+ util 1) cmp0 · 홈 0 · plist 0(ft-tick 이 매번 부름) · 되돌림 = `.bak-r497` 또는 `FT_MODEL_SWAP=0`. 범위 밖: 원래 모델 복귀 · 옛 좌석 kill · 나노/codex/opencode 교대 · cliproxy 해제 시각 조회 · 팀 틱 5개 감시 통일. 원문 = `harness/evidence/r497/tests-rc.txt`.

## 2026-10-20 — 승계 후계 행이 옛 행의 `stop-ready` 를 물려받던 사슬을 끊음 (r499 · 1.1.55)

- 사건: harness master 81 발주 115727 — v65 arch 265 · chatbot arch 5 행이 현역(`_arch` 값)인데 role=stop-ready. arch 105 실측: `ft-seat-retire.sh` 가 후계 행을 «옛 role 글자» 로 만들어, 옛 행이 승계 «전에» 이미 stop-ready 였으면 후계도 stop-ready 로 태어난다(`_retired_role` 은 바꿀 때만 적어 비어 있음 → 다음 승계도 같은 값). v65 262→264→265 사슬 · master 손 정정 뒤 265→266 은 정상. 지금 명부 13 전수: loom `_arch`=arch 59 · ops `_arch`=arch 38 이 같은 꼴.
- `ft_roster_lib.py` 신설 3: `succ_role(o, cells, name)` = 옛 role(stop-ready 아니면 그 값) → 옛 `_retired_role` → 옮기는 역할 칸(`_master·_arch·_desk·_da·_tester·_pm` · keys 순) 이름 → 이름 토큰(`byz-<팀>-<역할>-<에이전트>#N`) · 다 없으면 stop-ready 그대로(추측 0) · `held_roles` · `fix_role`.
- `ft-seat-retire.sh`: 후계 행 생성·상속 모두 도출값 · 기존 후계 행이 stop-ready(∧ `_replaced_by` 없음)이면 도출값으로 고침 · 옛 행 `_retired_role` 은 지금처럼 «원래 role 이 stop-ready 가 아닐 때만»(없는 값 만들지 않음). 재실행(NOOP 자리)도 후계가 «역할 칸 값 ∧ role=stop-ready ∧ `_replaced_by` 없음» 이면 `.bak-retire-<ts>` 뒤 고치고 `FIXED <구> -> <후계> file=… … role stop-ready-><역할>` 1줄 rc0 · 그 밖은 출력 그대로. 승계 출력(RETIRED/FIXED) 첫 줄 꼬리에 ` role stop-ready-><역할>` 가 붙을 수 있다(정상 승계는 0). 200줄 상한 유지.
- 시험: `test_seat_retire_rosters.sh` r499ⓖ~ⓙ(+ ⓘ 대조 · ⓙ nano 음성) · 기존 ⓐ~ⓕ·r465 · `test_seat_close.sh` · `test_seat_retire_keep.sh` rc0. `test_seat_retire.sh` rc1 = ⑧ `test_ft_tick_master_seat.sh` 1건 — 변경 전 main(5779acde)과 PASS/FAIL 목록 동일(이 단위 밖). 설치: LIVE_BIN 키트 2(`ft-seat-retire.sh` · `ft_roster_lib.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r499`. 범위 밖: 역할 칸이 빈 값이 된 원인 · stop-ready 표기 주체(`ft-seat-close.sh`) · 역할 칸 값이 아닌 과거 행. 원문 = `harness/evidence/r499/tests-rc.txt`.

## 2026-10-20 — 뉴스 린트: 확인 불가 팀 «쉼» 판정이 부정 꼬리(«…지 않»·«아니»·«지 못») 문장은 통과 (r498 · 1.1.54)

- 사건: planner 뉴스 틱 발행 0(요청 115673) — `/tmp/byz-ft-news-planner.log` 2913~2915 «ERROR 린트 위반 2건 — 발행 0 (확인 불가 팀 lecture 에 쉼 단정 «lecture·planner·room은 상태를 확인할 수 없어서 쉰다거나 멈췄다고 단정하지 않습니다»)». r490 `unknown_problems` 가 «팀 이름 + 쉬·멈·정지·대기 글자» 만 봐서, 지시대로 «단정하지 않는다» 고 쓴 문장이 거꾸로 걸렸다.
- `ft_news_html_lint.py`: `NEGATED_TAIL`(24자 안 `지 않`·`지 못`·`아니`·`아닙`·`않습니다`·`않는다`·`않음`) · `CLAUSE_END`(`,`·`，`·`.`·줄바꿈·`며 ` — «고 » 로는 자르지 않는다: «멈췄다고 단정하지 않» 의 «다고» 가 잘린다) · `_rest_asserted(s)` = 쉼 글자 매치마다 «뒤» 같은 절에 부정 꼬리가 없으면 단정(하나라도 단정 = 위반). `unknown_problems` 는 `REST_SAID.search` → `_rest_asserted` 1곳만 · 출력 문구 그대로. kit↔bin 짝 cmp0.
- 시험 `test_ft_news_html.py` r498 ⓐⓑ 3문장 위반 0 · ⓒⓓ 4문장(부정이 쉼 글자 «앞» 다른 말·다른 절에 붙음) 위반 1씩 — `test_news_html.sh` 39 passed(기존 32 + 7) · 옛 판 ⓐⓑ 3/3 REJECT. 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0(틱이 매번 부름) · 되돌림 = 이 커밋 revert(설치본 `.bak-r498`). 범위 밖: 프롬프트 문구 · `ALL_STOP`·`APPROVAL_WAIT` · 갈래 시간 상한(important 50.6초 = 1차 상한 초과 + 재시도 성공 · 총 마감 70초 안 · 정상). 원문 = `harness/evidence/r498/tests-rc.txt`.

## 2026-10-20 — 팀 폴더 쌍둥이(옛 꼴 `design/<팀>/` + 새 꼴 `design/teams/<팀>/`)를 ERROR 대신 ref 트리로 가름 (r495 · 1.1.53)

- 사건: v65 master 213(요청 115538)이 뒤처진 체크아웃 `v6-realtime-live`(origin/main 뒤 192커밋 · `design/v65` tracked 17661 + `design/teams/v65` tracked 2)에서 `ft-goal-check` → «ERROR … v65 폴더 실재 후보 2개 — 정확히 1개여야 한다» rc4 · v65 골 틱이 섰다. ref(origin/main)는 `design/v65` 0 · `design/teams/v65` 13583 — 어느 쪽이 팀 폴더인지 이미 말하는데 판정기가 ref 트리를 안 봤다.
- `ft_team_lib.py team_in_ref` · 셸 `ft_team_in_ref <루트> <팀> [ref]`(신설 · 같은 규칙 · 같은 글자): 실재 1 = 그대로 · 쌍둥이 2 = `git ls-tree -d <ref> -- <후보>` 가 비어 있지 않은 쪽 — 1개 = 그것 + stderr `WARN TWIN-STALE <버린 후보> (ref 에 없음 · 체크아웃 ref 뒤 N커밋)` · 2개 = 명단 꼴 + `WARN TWIN-BOTH …` · 0개 = 기존 ERROR « (ref 에 둘 다 없음)» · 실재 0 = 기존 ERROR(SPARSE-HIDDEN 먼저). 읽기만(ls-tree·rev-list) — 폴더 이동·쓰기 0.
- `ft-goal-check.sh`: HITS 재구현 삭제 → `ft_team_in_ref` 1줄(«실재 0» 만 기존 ref 본문 경로 · 그 밖 실패 = ERROR rc4). 고른 폴더에 없는 정본은 그 파일만 `<ref>:<명단 꼴>/<파일>` 본문 + 출력 «끝» `NOTE 정본 = <ref> 본문(체크아웃 ref 뒤 N커밋): <파일…>` 1줄(첫 줄 = 판정 그대로) · ref 에도 없을 때만 REJECT 정본 부재. (`ft_team_doc_ref` 를 안 쓴 이유: 쌍둥이에서 «옛 꼴 실재 1개» 를 골라 옛 체크아웃 파일을 돌려준다.)
- `ft-nano-close.sh`: 원장은 «쓰는» 파일이라 ref 본문 대체 0 — 기존 «원장 파일 실재 정확히 1개» 규칙 유지(뒤처진 체크아웃 `v6-realtime-live` 는 지금도 옛 꼴 `design/v65/…/NANO-LEDGER` 에 쓴다 · 새 꼴엔 원장 0 → 카드 §4 대로 폴더 먼저 고르면 운영 닫기가 REJECT) · 원장이 쌍둥이 «둘 다» 에 있을 때만 `ft_team_in_ref` 로 가름(ref 에 둘 다 없음 = 기존 REJECT 후보 2개).
- 시험 기대 변경: `test_goal_check_ref.sh` ⓐ8 «쌍둥이 → ERROR»(r479) → «ref 한쪽 → GOAL-OK + WARN TWIN-STALE» — 이유: 전환기엔 뒤처진 체크아웃의 쌍둥이가 «정상 상태» 라 ERROR 는 v65 골 틱을 세웠고, 가름 근거(ref 트리)는 추측이 아니라 정본 조회다. ⓔ3(골 표 planner 쌍둥이)도 같은 판정기라 «ref 쪽 + WARN TWIN-STALE · 빈 새 꼴 = ERROR rc1» 로 바뀐다(옛 꼴 후퇴 0). 신규 ⓐ8b(TWIN-BOTH)·ⓐ8c(ref 둘 다 없음 ERROR)·ⓐ8d(새 꼴 원장 없음 → ref 본문 + NOTE) · `test_team_lib_twin.py` ⓐ~ⓓ(kit·bin · 셸·파이썬 같은 글자) · `test_nano_close_fail_closed.sh` ⓑ2. 설치: LIVE_BIN 키트 4 cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r495`). 범위 밖: 폴더 실제 이동(planner) · `ft_goal_ledger` 골 표의 ref 본문 대체. 원문 = `harness/evidence/r495/tests-rc.txt`.

## 2026-10-20 — 새 워크트리 `.fable-team/bin` 첫 설치 길 = shim `--init` (r494 · 1.1.52)

- 사건: chatbot#8 tester 실음성 시험(P3)이 홈 훅 `press-runner-gate.sh` 의 «게이트가 없다 chatbot-main/.fable-team/bin/ft-press-gate.sh fail-closed(R106c)» deny 로 멈췄다(요청 115353). shim(`:25` 루트 bin 없음 ERROR)·설치기(`:42` REJECT)·훅(설치 안내 0) 셋 다 «bin 이 이미 있다» 전제라 새 워크트리는 어느 길로도 bin 을 못 얻는다 — 실측 `.worktrees/*/.fable-team` 313 중 bin 없음 306. master 손(`mkdir bin` + shim)으로 임시 해소.
- `ft-root-bin-shim.sh --init`: bin 없음 ∧ 루트가 «설치된 리포(공용 루트 `.fable-team/LIVE_BIN` 실재)의 git 워크트리 최상위» → 모든 검사 뒤 `mkdir` + `INIT <bin> (새 워크트리 · 공용 루트 …)` 줄 + 기존 흐름. LIVE_ROOT 기본 = 공용 루트 경로 그 자체(공용 루트 LIVE_ROOT 파일 값 복사 0 · master 115441). 공용 루트 자체·git 밖·워크트리 최상위 아님·설치 안 된 리포 = `ERROR --init 불가 — <사유>` rc3 · 생성 0. `--init` 없이 bin 없음 = 기존 ERROR + « (새 워크트리면 --init)». `--dry-run` = `PLAN init` 줄 · 쓰기 0. bin 있는 루트는 지금 흐름 그대로.
- `install.sh`: bin 없음 ∧ `--project` 가 git 워크트리 → dry-run `PLAN shim-init <워크트리>` · apply = 설치본 shim `--init`(LIVE_ROOT 기본 = 공용 루트 · rc≠0 = 그 자리에서 멈춤). 공용 루트·git 밖 bin 없음 = REJECT rc2 그대로. 프로젝트 폴더 없음 = REJECT rc2(쓰기 0).
- 홈 훅 `press-runner-gate.sh`: 게이트 없음 deny 문구 끝에 « · 설치(master) = bash <LIVE_BIN>/ft-root-bin-shim.sh --root <toplevel> --live <LIVE_BIN> --init»(LIVE_BIN = `git-common-dir` 부모의 `.fable-team/LIVE_BIN` 1줄 · 못 읽으면 글자 `<LIVE_BIN>`) · 판정 변경 0.
- `ft-nano-spawn.sh`: `git worktree add`(sparse 는 checkout 뒤) 직후 shim `--init` — 성공 = `SHIM n · MOVED m · UNKNOWN k (shim-init <워크트리>)` 1줄 · 실패 = `NOTE shim-init 실패: <사유>`(spawn 계속 · 조용한 통과 0) · dry-run `PLAN shim-init`.
- 시험 `harness/tests/test_root_bin_shim.sh` r494 절 ⓐ~ⓔ(임시 «설치된 리포» + `git worktree add` + git 밖 폴더 + 공용 루트 사본 + 설치 안 된 리포 · 외부 호출 0 · GIT_* 0) rc0 · 옛 shim 대입 19 FAIL. 설치: LIVE_BIN 키트 2(shim·nano-spawn) cmp0 + 홈 훅 1(`templates/hooks/press-runner-gate.sh` → `~/.claude/hooks/` cp+755) · 되돌림 = 이 커밋 revert(설치본 `.bak-r494`). 범위 밖: 기존 306 워크트리 일괄 설치(master 별 h) · baton wt-create 배선. 원문 = `harness/evidence/r494/tests-rc.txt`.

## 2026-10-20 — 공유 역할 좌석 승계: 은퇴가 «모든 명부»의 역할 칸(`_arch`·`_master`…)까지 후계로 · 재실행 보정 · 빈 역할 칸 채우기 (r465 · 1.1.51)

- 사건(v65 master 211 · 112532): 공유 arch 262→263 은퇴 뒤 `seats-lecture.json _arch` = 262 그대로 → `ft-seat-close 262` 가 «현역 역할 좌석» REJECT · retire 재실행은 NOOP · 명부 손 편집 0 이라 갈 길 0. 사례 2(112813): `close --verdict` 가 `_arch` 를 "" 로 비운 뒤 resume 한 좌석은 retire 가 `keys=[]` 로 끝나 칸이 빈 채 남음(planner 손 채움).
- **ft-seat-retire.sh**: 같은 폴더 다른 명부의 «값이 <구> 인 최상위 `_*` 문자열 칸 전부»(역할 + 라우팅)를 후계로(옛 r429 = 라우팅만). 출력 첫 줄 `… keys=[…] files=N roles=[<파일>:<칸>…] routes=[…]`(`roles=` 칸 추가). R282 ② «다른 명부에서 현역 → REJECT» 삭제(그 칸도 이번에 바뀐다) · close 의 현역 판정은 불변.
- **재실행(이미 은퇴)**: 남은 칸이 있으면 보정 `FIXED <구> -> <후계> file=… keys=[…] files=N roles=[…] routes=[…]` · 없으면 옛 `NOOP` 그대로(멱등).
- **빈 역할 칸 채우기**: 자기 명부에 옛 이름 칸 0 · 후계 행 실재 · 후계 이름의 역할 칸(`_master`·`_arch`·`_da`·`_tester`)이 "" 또는 없음 → 후계로 채우고 첫 줄 끝 ` FILLED <명부>:<칸>` · 그 칸이 살아 있는(tmux) 다른 좌석이면 `REJECT` rc1 쓰기 0 · 죽은 다른 좌석이면 채우지 않음(추측 0).
- 그대로: 전부 검증 뒤 쓰기(명부 하나 손상 = `ERROR` rc1 · 쓰기 0) · 바뀐 파일마다 `.bak-retire-<ts>` · tmp→교체 · 바꾸는 값 = «옛 → 후계» 치환뿐(행 삭제 0).
- **ft_roster_lib.py**(bin/kit 짝 cmp0): `scan_cells`·`apply_cells`(→ roles/routes 나눔)·`role_cell` 추가.
- **시험**: `test_seat_retire_rosters.sh` r465ⓐ~ⓕ(공유 arch files=3 · FIXED 보정·NOOP 멱등 · 손상 ERROR · 기존 REJECT 그대로(lint·rc3) · close «현역» REJECT 대조 1→0 · FILLED/살아 있는 좌석 REJECT/죽은 좌석 채우기 0) + 옛 ⓐⓑⓒ' 기대값을 새 계약으로(남의 `_master` 도 후계) · `test_seat_retire.sh` ③⑨⑬ 기대값(`roles=` 칸 · ⑬ REJECT→RETIRED). `test_seat_retire.sh` ⑧ 의 `test_ft_tick_master_seat.sh` rc4 는 origin/main 0051effd 에서도 같은 FAIL 4줄(선재 · 은퇴 도구 참조 0).
- 설치 뒤 실사건: 다음 공유 역할 좌석 승계 1건 → 모든 명부에서 값이 <옛 이름> 인 `_*` 칸 0 + `ft-seat-close <옛>` 통과.

## 2026-10-20 — 제안서 게이트 판정 원장 = ref(origin/main) 트리 · 표 행 꼴도 읽는다 (r492 · 1.1.50)

- 사건: feature#31 F-1509(main RED 수정) 카드 spawn 이 `REJECT 1509 ⓑ planner 원장 「1637 오빠 인터뷰」 줄에 … issues/1509 없음` — planner 는 링크를 main 에 올렸는데(33d5b75186) 게이트가 옛 라이브 체크아웃(`.worktrees/v6-realtime-live` · main 뒤 186커밋)에서, 줄머리 `N 오빠 인터뷰` 꼴로만 원장을 읽었다(실제 행 = 표 행 `| 1637 | 23:0x | (오빠 인터뷰 4) …`).
- `ft-proposal-gate.sh`: `GATE_VROOT` → `GATE_ROOT=${BYZ_ROOT:-<리포 루트>}` · `GATE_REF=${FT_TEAMS_REF:-origin/main}`. 원장 = 명단 `<ref>:design/TEAMS.md` 후보(명단 꼴·쌍둥이 · `_cands_ref`) 중 `<ref>` 트리에 `VERDICTS-planner-*.md` 가 있는 폴더 정확히 1개를 `git ls-tree`·`git show` 로 읽는다(체크아웃 파일 0 · 7초). 0·2+ 개·명단 못 읽음·`git show` 실패 = REJECT(후퇴 0). `FT_PLANNER_VERDICTS_DIR` 지정 시에만 폴더 파일 직접(시험용 그대로).
- 행 판정: 줄머리 `^N 오빠 인터뷰` 또는 표 행 `^| N | … (오빠 인터뷰` · 링크 검사·REJECT 문구 그대로.
- 카드 설계와 다른 점: 카드는 `team_in_ref`(디스크 실재 후보 1개)였지만 라이브 루트 체크아웃엔 옛 쌍둥이 `design/planner` 만 있고 ref 원장은 `design/teams/planner` 에만 있어(ref 의 design/planner 원장 0) 그대로면 실사건이 계속 REJECT — 폴더 선택도 ref 트리로 한다.
- 시험 `harness/tests/test_proposal_gate.sh` 새 절 ⓐ~ⓓ+ⓓb(임시 리포 + bare origin · 체크아웃은 원장 이전 커밋) 포함 ALL PASS rc0 · 옛 게이트 대조 4 FAIL · 실사건 읽기 전용 `--issue 1509` 새 `OK #1509 승인 ⓑ 판정 1637` / 옛 REJECT. 되돌림 = 이 커밋 revert(설치본 `.bak-r492`). 원문 = `harness/evidence/r492/tests-rc.txt`.

## 2026-10-20 — sparse 나노에서 남의 팀 폴더 = «SPARSE-HIDDEN <경로>» 로 원인을 말한다 + 발주문 광역 pytest 1줄 (r486 · 1.1.49)

- 사건: 나노 워크트리는 r444 ⑤ 로 자기 팀 design 만 체크아웃한다. 다른 팀 폴더를 읽는 시험(BYZ `test_v65_m5_lst_runaway*` → `team_in(root,'v65')`)이 그 안에서 «실패 10 + 수집 오류 2» 로 보여 chatbot K1 나노·arch·v65 arch 가 ~1시간(r468 에 이어 2회째 · 요청 114385).
- `ft_team_lib.py`: `SparseHidden(TeamPathError)` · 판별 = 디스크 없음 ∧ `core.sparseCheckout=true` ∧ `git ls-files --error-unmatch <상대경로>` rc0 · `team_root`(alt·꼴3 아님)·`team_in`·`team_in_ref`(실재 0) 에서. 메시지 `SPARSE-HIDDEN <경로> — 이 워크트리는 자기 팀 폴더만 체크아웃(r444) · 전체 사본 = ft-scratch-repo.sh <base> 에서 돌려라`. `team_cands_ref` 는 «실재 여부 무관» 그대로.
- `ft-team-lib.sh`: `ft_team_root` 같은 분기 · stderr 같은 글자 1줄 · rc1. `ft_team_cands`·`ft_team_cands_ref` 는 `FT_TEAM_SPARSE_CHECK=0`(→ `ft_team_doc_ref` 의 ref 본문 후퇴 그대로).
- `ft-nano-spawn.sh`: 발주문(BODY) 끝에 «★광역 pytest 금지 — … ft-scratch-repo.sh <base> 사본에서 · 도구는 SPARSE-HIDDEN <경로> 로 말한다(r486)★» · dry-run 은 PLAN 뒤 `BODY+…` 줄.
- BYZ 쪽: BYZ 시험은 팩 키트가 아니라 `tests/shared/ft_team_lib.py`(r405 사본)를 import 한다 — 같은 분기를 BYZ 가지 `nano/r486-nano-sparse-checkout-hides-other-te` 671b53b4 에 따로 둠(착지는 master 판단).
- 시험 새 `harness/tests/test_team_lib_sparse.py` 13 passed(옛 코드 대조 9 failed) · 기존 team/nano/goal 시험 11종 rc0 · 빨강 4종은 origin/main 과 실패 줄 동일(선재). 되돌림 = 이 절 커밋 revert(설치본 `.bak-r486`). 원문 = `harness/evidence/r486/tests-rc.txt`.

## 2026-10-20 — 홈 훅 설치 = kit/hooks 전부 + 실행 비트 · settings 등록 훅 전수 점검 (r491 · 1.1.48)

- 사건: 손으로 cp 한 홈 훅(`autonomy-merge-guard.sh`)이 664 로 들어와 전 좌석 매 Bash 마다 `/bin/sh: …: Permission denied`. 설치기는 홈 훅 3개만 복사하고 `cp -p → cmp`(내용)만 봐서 실행 비트를 확인하는 경로가 없었다.
- `harness/install.sh`: 홈 훅 목록 = `kit/hooks/` 일반 파일 전부(고정 3 → 자동 10) · 복사 뒤(또는 내용 같아도) 실행 비트 없으면 `chmod +x` + `HOOK <경로> chmod +x` 줄 · 요약 `HOOKS copied= same= chmod=` · dry-run HOOK 줄 `(exec)`. 새 `audit_registered_hooks <settings.json> <home>`(apply·dry-run 끝 둘 다): 등록 명령의 `…/hooks/…` 경로(`$HOME`·`${HOME}`·`~` 확장) 실재 + 명령 첫 낱말로 직접 실행되는 경로는 실행 비트 → `HOOKS registered=N ok=N bad=M` · 문제 = apply `ERROR HOOK-EXEC <경로> <없음|실행 비트 없음>` rc1 / dry-run `PENDING HOOK-EXEC …` rc0 · settings 없음 = registered=0 · JSON 깨짐 = rc1. `bash <경로>`·가드(`if [ -x …`) 로 부르는 경로는 실재만(644 여도 돈다 — 과차단 0). settings 쓰기 0 · 키트 밖 훅 chmod 0.
- `ft_live_install_check.py`(bin/kit 짝 cmp0): `hooks/*` 행 라이브 파일 실행 비트 없으면 `EXEC-BIT`(키트 모드 644 여도 · 옛 `MODE` 는 키트 100755 일 때만 봤다).
- 시험 `harness/tests/test_install_hook_check.sh` r491ⓐ~ⓔ 25칸(옛 판 15 빨강) · 실 홈 dry-run `HOOKS registered=29 ok=29 bad=0`. 기존 `test_live_install.sh`·`test_live_install_check.sh`·`test_live_install_check_tip.sh`·`test_harness_root.sh` 의 빨강은 origin/main 그대로(개수·문구 동일 — 선재). 원문 = `harness/evidence/r491/tests-rc.txt`.

## 2026-10-20 — 뉴스 지도: «확인 불가»(turn 시간 초과·실패) ≠ «쉬는 팀» · turn 재시도 1 · 풀 = 좌석 수 (r490 · 1.1.47)

- 22:04 뉴스(load 25~31)에서 chatbot 5석의 `ft-seat-status.sh turn` 이 7초 상한을 넘어 «?» 가 됐는데 `facts`·`bucket` 이 일하는 0 인 팀을 전부 «쉬는 팀» 에 넣어 일하는 챗봇팀이 «쉼» 으로 나갔다(오빠 «챗봇팀은 왜쉬어?»).
- `ft_news_html.py`: `_turn` = 첫 출력 전 실패 1회 재시도(7초 룰 · 시간 초과는 프로세스 묶음째 kill) · 풀 = min(좌석 수, 32) · 팀 칸 `unknown_reason` · `facts` 3분류(일하는 · 확인 불가 · 쉬는). `ft_news_html_render.py`: 3분류 bucket + «확인 불가» 블록 · 프롬프트 1줄. 틀 `news-team-map.html`: H2 «확인 불가» + chip. `ft_news_html_lint.py`: H2 5개 · 확인 불가 팀 이름 + 쉬/멈/정지/대기 단정 = 위반.
- 시험 `test_news_html.sh` 32 passed(새 ⓐ~ⓓ · 옛 판 RED 4) · 되돌림 = 이 절 커밋 revert(설치본 `.bak-r490`) · 단계 = `harness/evidence/r490/master-steps.md`.

## 2026-10-20 — 뉴스 ⑥ 트리: 루트·팀 폴더는 부르는 쪽이 넘긴다 — ref 임시본에서 git 128 고침 (r489 · 1.1.46)

- r484 뒤에도 ⑥ 트리가 비었다 — 공용 루트 체크아웃엔 v65 `NEWS-TREE.md` 가 없어 `ft_team_doc_ref` 가 `$TMPDIR/ft-team-doc.*` 임시본을 주는데, `ft-news-tree.py` 가 리포 루트(`git -C <트리 폴더> rev-parse`)·카드 폴더(`tree.parent/indices`)를 트리 파일 위치에서 유도해 `CalledProcessError 128`(arch 103 실측).
- `ft-news-tree.py`: `--root`·`--team-dir`(env `FT_NEWS_ROOT`·`FT_NEWS_TEAM_DIR`) · 카드 폴더 = `<팀 폴더>/indices` 실재 → ref(`FT_TEAMS_REF` · 기본 origin/main) 같은 상대 경로 `ls-tree` → 둘 다 없으면 줄에 `?(폴더 없음)`(rc0 · 말단 줄에 `?N`). 인자 없으면 옛 유도 그대로(출력 바이트 같음).
- `ft-news-tick.sh:56` = `--root "$ROOT" --team-dir "$(ft_team_cands_ref "$ROOT" v65 | head -1)"`(lib source 를 53행 앞으로 · 56행 위치 유지 = r484 린트·시험 그대로) · `ft-news-tick-cfo.sh:38` = `--team-dir "$CFO_DIR"`. 임시본 삭제 trap 그대로.
- 시험 새 `harness/tests/test_news_tree_root.sh` ⓐ~ⓓ + 틱 ⑥ 재현 + 옛 판 CalledProcessError 대조 23 PASS · 기존 4종 rc0 · 공용 루트 cwd ⑥ 절(새 키트 사본) rc0 62줄 Traceback 0. 원문 = `harness/evidence/r489/tests-rc.txt`.

## 2026-10-20 — 자율 ON 인터뷰 1회(기간 + 레벨 full|mid|each)로 범위 승인까지 함께 걸기 · 레벨 재발급 · 종류 학습 · 자율 상태 가드 (r466 · 1.1.45)

- `ft-autonomy.sh on --for <기간> --level <full|mid|each>` 한 줄(h)이 범위 승인까지 걸어 OFF 까지 병합 질문을 줄인다. 새 `ft-autonomy-level.sh`·`ft-autonomy-interview.sh`(인터뷰 답 → h 1줄) · 분류기를 표(`autonomy_scope_rules.py`·`scope-classes-pack.tsv`·`scope-ddl-record.tsv`)로 · 카드 이동(R100·이름 같음·양쪽 docs)은 docs 로 통과 · 첫 OFF 도달은 틱이 desk 에 [자율 인터뷰] 1통.
- 홈 훅 `autonomy-state-guard.sh`: 자율 ON = approve-merge 허용+로그 · OFF = deny · on/off 는 항상 deny. 시험 새 2 · 기존 15개 머리에 `FT_AUTONOMY_LEVEL=each`(--level 생략=full 이면 on 이 실 슬랙 게시라서).
- 되돌릴 땐 자율 OFF 상태에서(옛 판은 level 칸 승인 줄을 위변조로 읽음). 단계 = `harness/evidence/r466/master-steps.md`.

## 2026-10-20 — 키트 ft-mbox send/relay 도 보관 로그 mailbox.log.jsonl 에 1행 + send 자가 점검 WARN (r488 · 1.1.44)

- 라이브 `ft-mbox.sh send`(키트 단일 파일 `ft-mbox.py`)는 보낸 행을 `mailbox.jsonl` 에만 써서, recv 가 소비하면 그 쪽지의 레코드가 어디에도 남지 않았다(bodies 만) → `ft_da_hold_gate find_record` 등이 «쪽지 없음» 판정(실측 114380~114490 중 6건). 루트 모듈판 `mbox_guard._log_sent` 규칙 그대로 `ft-mbox.py send`(relay 는 send 경유)가 `_save` 직후 같은 잠금 안에서 `mailbox.log.jsonl` 에 1행 append · `FT_MBOX_LOG_MAX_BYTES`(기본 5MB) 초과 시 `.1` 회전 · 기록 실패는 stderr WARN(전송 rc 불변).
- `ft-mbox.sh` send/relay 끝에 그 seq 행이 로그에 정확히 1행인지 `grep -c` — 아니면 stderr `WARN sent-log <n> seq=<N> file=<경로>`(fail-open). skill/scripts 사본 2 동기화(cmp 0). 큐 꼴·recv 소비 규칙·루트 untracked 정본 변경 0.
- 시험 `harness/tests/test_ft_mbox_sent_log.sh` ⓐ~ⓕ(변이 포함) · 되돌림 = 이 절 커밋 revert(설치본은 `.bak-r488`).

## 2026-10-19 — 병합 줄 대조가 «팀 폴더 옛 꼴 글자만 바꾼 줄» 을 같은 줄로 센다 (r477 · 1.1.43)

- `ft_merge_lines.py` 가 줄 비교 전에 «main 이 더한 줄» 의 팀 폴더 옛 꼴(`design/<팀>/`)을 새 꼴(`design/teams/<팀>/`)로 정규화 — 명단 = `ft_team_lib.team_rows_ref`(`FT_TEAMS_REF` · 기본 origin/main) · 꼴2 팀만 · 한 방향(옛→새) · 접두 글자 치환만 · PASS 줄에 `PATHSUBST <n>줄`(0 = 칸 생략).
- 정규화는 main 이 더한 줄에만 적용한다 — 후보 줄까지 정규화하면 «새 꼴 → 옛 꼴» 역방향(카드 ⓓ 거절)이 통과한다(시험이 못 박음). 명단 못 읽음 = `WARN 명단 ref 못 읽음 — PATHSUBST 0` 1줄(stderr) + 옛 동작(정규화 0 · 추측 0 · 합성 픽스처는 WARN 0).
- 시험 새 `tests/test_merge_lines_pathsubst.sh` ⓐ~ⓕ ALL PASS · 기존 merge·land 시험 9종 ALL PASS(선재 빨강 2종은 origin/main 그대로) · 옛 판 RED(ⓐ → DENY) · 실사건: loom PR 1976 head 280b041aa5(M=75b386) 옛 판 DENY 83파일 → 새 판 DENY 2파일 + PATHSUBST 155줄(남은 2 = 명단 밖 `concierge` 재명명 팀 — 추측 0 규칙대로 거절 · `harness/evidence/r477/master-steps.md`).

## 2026-10-19 — 뉴스 HTML: top 갈래를 요약·중요한 일 2갈래로 쪼갬 · 상한 초과 = 첫 출력 전 실패 재시도 1 (r478e · 1.1.42)

- 첫 자동 틱이 부하(load 25~50)에서 `opencode run top 상한 38s 초과` — top(요약+중요한 일+근거) 한 호출이 max/high 에서 흔들림. 7초 룰대로 top → summary(요약+근거) · important(중요한 일) 2갈래로 쪼개 4갈래 병렬 · 시도당 상한 크기 비례 그대로 · 시도당 상한 초과 = 첫 출력 전 실패로 보고 총 마감 70초 안 재시도 1회.
- 시험 `test_news_html.sh` 28 passed(새 2: 한 갈래 부하 지연 → 전체 발행 0 · 초과 재시도 1). 실측(같은 입력 · load 15~50): high 최대 갈래 26.4/20.9초 · base 27.9/29.2초 · max 는 22~62초로 흔들림 → 권장 effort=high. 단계 = `harness/evidence/r478e/master-steps.md`.

## 2026-10-19 — 골 원장 판정기: 판정 키 = ref origin/main sha · 상태 = 공용 루트 1개 · 경과 = ref 기준 (r485 · 1.1.41)

- v65 master 가 자기 워크트리에서 `--touch` 해도 다음 틱(공용 루트 cwd)이 `REREAD-REQUIRED` — 원장 sha·상태 파일·커밋 경과를 전부 «cwd 의 git 루트» 에서 잡아 틱과 좌석이 다른 파일에 다른 키를 썼다.
- `ft-goal-check.sh`: 상태 = `${FT_ROOT:-ft_repo_root}/.fable-team/state/goal-read-ledger.json`(못 풀면 ERROR exit 4) · 원장·정본 sha = `$REF` 의 명단 꼴 경로 이력(체크아웃이 옛 꼴 폴더여도 같은 값 · ref 에 원장 없으면 ERROR) · touch 행에 `ref_sha` · 경과 = `rev-list <ref_sha>..$REF`(좌석 로컬 커밋은 안 셈) · `ref_sha` 없는 옛 꼴 행 = REREAD «다시 touch» · GOAL-READ 에 `ref= state=`. 체크아웃은 cited grep·NEXT 에만. 판정 세 조건(원장 갱신·TTL·경과)은 그대로.
- 시험 `test_goal_check_ref.sh` r485-⓪·ⓐ~ⓔ 12 + 기존 22 = fail=0. 이행·되돌림 = `harness/evidence/r485/master-steps.md`.

## 2026-10-20 — 뉴스 틱 ⑥ 완성 트리 복구: 도구는 $HERE(LIVE_BIN) 형제를 부른다 · shim 은 exec 만 (r484 · 1.1.40)

- 1.1.37 부터 뉴스 ⑥ 트리가 비었다 — `ft-news-tick.sh:56` 이 옛 라이브 워크트리 자리 `ft-news-tree.py` 를 `python3` 에 넘겼는데 그 자리는 r413 뒤 bash shim 이라 `SyntaxError: unmatched ')'`(v65 master 212 #114311).
- `ft-news-tick.sh` 도구 호출 8줄 + `ft-news-tick-cfo.sh:22` → `$HERE/…` · `WT` 는 제품 커밋 조회에만. 새 린트 `ft-shim-exec-lint.sh`(키트 bin 에 `python3|bash|sh "$X/.fable-team/bin/…"` 꼴 0 · `test_kit_bin_sync.sh` 가 부름). shim 생성기 변경 0.
- 시험 `test_root_bin_shim.sh` r484 ⓐ~ⓓ + 옛 꼴 SyntaxError 재현 대조 · 같은 파일 기존 RED 11건(r385 뒤 키트 기본 변경)도 `--repo·--path` 명시로 rc0. 단계 = `harness/evidence/r484/nano-steps.md`.

## 2026-10-19 — 뉴스 HTML: 일하는 팀 = 골 위 그림 카드 · 요약이 코드 판정(일하는 팀·자율)을 따른다 (r478d · 1.1.39)

- 오빠 2차 반려(«챗봇이 아래에 텍스트만») — 일하는 팀(라이브 좌석 실측)을 골 카드와 같은 그림 카드로 «골 6개» 위에 · 쉬는 팀은 맨 아래 목록.
- desk 실측 거짓 요약(«모든 팀 멈춤 · 승인 기다림») — 프롬프트에 코드 판정 facts(일하는/쉬는 팀 · `ft-autonomy.sh mode`) · 린트가 «일하는 팀 ≥1 인데 모두 멈춤» · «자율 OFF 아닌데 승인 기다림» 을 발행 0 으로 막는다.
- 시험 `test_news_html.sh` 26 passed. 단계 = `harness/evidence/r478d/master-steps.md`.

## 2026-10-19 — 뉴스 HTML «일하는 팀» = 라이브 좌석 실측 · 일하는 팀이 위 (r478c · 1.1.38)

- 오빠 반려(일하는 chatbot 이 쉬는 팀에) — 일하는/쉬는 팀 판정을 LLM 에서 코드로: 명부 팀별 tmux 좌석 + `ft-seat-status.sh turn` WORKING 수로 나누고 일하는 좌석 많은 순으로 위에 · LLM 은 팀별 설명 한 문장만. 라이브 좌석 판정이 없으면 발행 0.
- 시험 `test_news_html.sh` 24 passed · 라이브 1회: chatbot 일하는 팀 188행 < 쉬는 팀 195행. 단계 = `harness/evidence/r478c/master-steps.md`.

## 2026-10-19 — r479 골 읽기 판정기·골 표 원장도 «명단 = ref origin/main · 폴더 = 그 루트에 실재» (r479 · 1.1.37)

- `ft-goal-check.sh` 가 v65 폴더를 체크아웃 `design/TEAMS.md` 가 아니라 ref 명단(`FT_TEAMS_REF` · 기본 origin/main)으로 풀고, 그 루트에 실재하는 후보 1개를 쓴다(0개 = ref 본문 · 2개+ = ERROR). 공유 루트에 명단 파일이 없어 v65 master 에 매 틱 REJECT(rc=4)가 가던 일이 끝난다.
- `ft_goal_ledger.planner_dir`(골 표 원장 · 쪽지 가드 · 뉴스 골 표) 도 같은 규칙 — LIVE_ROOT 의 명단을 새 판으로 갈아도 옛 판 그대로여도 같은 원장을 찾는다.
- `ft_team_lib` 에 ref 판 3(`team_rows_ref` · `team_cands_ref` · `team_in_ref`) — 셸 `ft_team_cands_ref` 와 같은 규칙 · 기존 함수 동작 그대로. 단계 = `harness/evidence/r479/master-steps.md`.

## 2026-10-19 — 뉴스 HTML 모드 호출 쪼개기: 갈래 3개 병렬 · 크기 비례 상한 · stdin 차단 (r478b · 1.1.36)

- 첫 실제 틱이 `opencode run 총 마감 70s 초과`(max) — 원인 = 한 호출에 출력 전부(3~4.4K자) × max 생각 시간(실측 65.6초·130초+). 7초 룰대로 top·goals·teams 3갈래를 «그 갈래 입력만» 넣어 병렬 호출 · 시도당 상한 = 크기 비례(≤70) · stdin=/dev/null.
- 실측(같은 입력): base 30~44초 → 17.9초 · max 65.6~130초+ → 30.5초 · 린트 OK.
- 파일: `ft_news_html_render.py`·`ft_news_html.py`(bin·kit 짝) + 시험 `test_ft_news_html.py` · 단계 = `harness/evidence/r478b/master-steps.md`.

## 2026-10-19 — opencode 좌석 모델 = 세션 env `OPENCODE_CONFIG_CONTENT`: `--model` 플래그 0 · tmuxc 0.4.1 (r476 · 1.1.35)

카드 r476 · cfo 113325(정본화 나노 opencode 기동 실패 → claude 대체) · master 79 발주 113358 ①. opencode 2.0.32 TUI 최상위 플래그엔 `--model` 이 없고(`opencode run` 전용) tmuxc 가 `opencode --auto --model <ID>` 로 띄워 «Unrecognized flag: --model» 로 첫 줄에서 죽었습니다 — 정본화·리서치·검색 나노(opencode)가 전 팀에서 못 열렸습니다.

- **tmuxc 0.4.1**(`feature-pack/tmuxc`): `resolve_opencode_cmd`·`resolve_opencode_fork_cmd` 에서 `--model` 제거 · 새 `opencode_session_env` = `OPENCODE_CONFIG_CONTENT={"model":"<ID>"}`(python json 이스케이프 · `#variant` 글자 그대로) · `create_tmux_session` 이 추가 env 를 `new-session -e`(FT_SEAT 옆)로 심음 — open·fork 의 opencode+모델일 때만 · `--dry-run` 에 `env=` 줄 · 모델 미지정 = env 0(opencode 기본값) · 다른 agent 경로 변경 0 · 글로벌 `~/.config/opencode/opencode.json`·워크트리 파일 0.
- **ft-nano-spawn.sh**(bin·kit 짝): PLAN 줄에 `via=OPENCODE_CONFIG_CONTENT`(opencode 만).
- **시험** 새 `tmuxc/test/test_tmuxc_opencode_model.sh` ⓐ~ⓔ(가짜 opencode·tmux · 실 opencode·외부 호출 0) · `tmuxc/test/verify.sh` 의 opencode fork «`--model` 통과» 단언을 env 계약으로 교체.
- **실측**: 실 opencode 2.0.32 `run --standalone`(플래그 없이 env 만) → 세션 model 칸 = deepseek-v4.1-flash-free · 대조 glm-5.3-flash-free 도 일치(env 가 모델을 정함) · `#max`/`#high` 는 rc0 이나 variant 기록 0 → base ID 권고.
- **master 할 일**: `harness/evidence/r476/master-steps.md` — ★tmuxc `install.sh` 를 그대로 돌리지 않는다(팩 COMM-GUIDE-BOOT.md 가 라이브보다 옛 판 → 스킬 링크가 옛 판으로 바뀜)★ · 버전 폴더 복사 설치 + current 전환 · 실사건 opencode 좌석 1석.
- 범위 밖: tmuxc restore 스냅샷 opencode 분기(`--model` 합성 · 이제 argv 에 모델 없음 → 기본 모델로 복원) · 팩 COMM-GUIDE-BOOT.md 역반영.

## 2026-10-19 — 뉴스 HTML 모드: 팀 지도 HTML + 한 줄 · opencode 딥식 무료 비대화 1회 (r478 · 1.1.34)

카드 r478 · 오빠 확정 10-19 19:3x(desk 113404·113411·113414 «내용 좋다 html 만 발급 · 슬랙 한 줄 시간과 적정한 반복 · 스크립트로 agent-cli · 결과물·속도로 effort 결정 · 요약과 html 아웃풋»).

- `FT_NEWS_MODE=html` 이면 뉴스 틱이 원장·골 표·보드 스냅샷·[긴급] 머리·main 커밋을 묶어 `opencode run --standalone`(딥식 무료 · 70초 총 마감 · 첫 출력 전 실패만 재시도 1)에 넘기고, 내용 JSON 을 고정 틀(`templates/news-team-map.html` · 기준본과 같은 CSS·절)에 넣어 HTML 을 만든 뒤 린트 통과분만 슬랙 최상위 글 «[뉴스 HH:MM] 팀 지도 — 요약» + 요약 2줄 + HTML 첨부로 올린다. 변화 0 = 30분마다 한 줄(`FT_NEWS_REPEAT_MIN`) · 하루 첫 틱 = 지도 · 첨부 실패 = 글만 + rc3 + 다음 틱 재첨부.
- 새(bin·kit 짝): `ft_news_html.py`(build·run·publish·tick) · `ft_news_html_render.py`(프롬프트·호출·파싱·틀) · `ft_news_html_lint.py`(절 5·중요한 일 ≤7·골 6·번호 각주만·요약 ≤3줄·600B·시크릿 0) · `ft-news-effort-test.sh`(변형 비교표) · 틀 1 · `magazine_slack.upload_file(thread_ts=None, comment=)`.
- 모드 없음 = 옛 판 경로 그대로 · 되돌림 = plist env 줄 제거. 시험 새 `tests/test_news_html.sh` ⓐ~ⓗ · 증거 `harness/evidence/r478/`.

## 2026-10-19 — opencode 나노 = 읽고 모으기 · 쓰면 매번 완전히 닫기: `ft-opencode-reap.sh`(left=0) · nano-close 회수 · spawn `--tier search` · 나노 기본 모델 Sonnet 5.5 · Bash 직접 사용 알림 훅 (r286 · 1.1.33)

카드 r286 · 오빠 하네스 뉴스(desk#7 #100242 · master#56 #100251) · 판정 2035(opencode 정리 kill 표준승인 · 전역 하드 룰 2). Sonnet 5.5 가 Opus·sol 보다 처리 능력이 낫고, opencode 의 DeepSeek V4.1 Flash Free 가 1M 컨텍스트를 무료로 준다 — 단 opencode 는 메모리 문제가 있어 쓰면 매번 완전히 닫아야 합니다. 실측: opencode 가 `opencode serve` 자식(400MB+)을 띄우고 tmux 세션만 지우면 부모를 잃고 남으며, `serve --service` 는 ppid 1 · cwd $HOME 으로 뜨기도 합니다(공유 서비스 가능).

- **새 `ft-opencode-reap.sh <좌석> [--wt] [--record [--since]] [--apply] | --pid-file F [--apply]`**(bin·kit 짝): 대상 = ①좌석 pane 나무 안 opencode ③ppid 1 ∧ cwd ⊂ 좌석 워크트리(안쪽 다른 워크트리 제외) · pid 파일(`~/.claude/state/opencode/<좌석>.pids` · 시작 시각 lstart 같을 때만 — pid 재사용 오살 0) · `--record --since` 뒤 새로 뜬 부모 잃은 serve(new — 닫을 때 다른 opencode 가 살아 있으면 공유로 보고 `oc-skip`) · 그 자손 전부. 내 uid · 다른 tmux 세션 나무 · 자기 조상 제외. `--apply` = TERM → 3 s → (같은 lstart 만) KILL → 재조사 2회전 → `REAPED <좌석> n= left= rc=`(rc 0 = left 0 · 1 = 남음 · 20 = 조사 실패). 외부 호출 각 7 s.
- **ft-nano-close.sh**: 명부 agent=opencode 또는 pid 파일이 있으면 명부를 지우기 «앞» `--record` · 세션 kill «뒤» `--apply`(ABSENT 경로 포함) → `OC-REAPED <좌석> reap left=0 rc=0` · left≠0 ∨ rc≠0 = `CLOSE-FAIL … exit 1`(재실행 = pid 파일로 다시 회수). 리서치 닫힘 줄(R387)은 같은 결과(함수 `_oc_close` 하나).
- **ft-nano-spawn.sh**: `--tier search` = opencode + `${FT_OC_MODEL:-opencode/deepseek-v4.1-flash-free}` · `--agent opencode` 모델 없으면 같은 기본(옛 REJECT 대신) · impl 기본 `FT_IMPL_MODEL:-claude-sonnet-5-5[1m]` · checker/tester sonnet 칸 `claude-sonnet-5-5[1m]` · opencode 좌석은 열린 뒤 `--record --since` · 검색 나노 발주 문단(코드 수정·커밋 0).
- **새 홈 훅 `kit/hooks/opencode-reap-check.sh`**(PostToolUse · Bash): opencode 가 «명령 자리»에 있을 때만(echo·grep 인자·따옴표·heredoc 제외 · bash -c 재귀) 660 s 안에 시작한 부모 잃은 opencode 를 찾아 pid 파일 + `ft-opencode-reap.sh --pid-file … --apply` 1줄 알림 · kill 0 · 깨진 입력 = rc 1 + ERROR.
- **정본 사본** `harness/design/harness/staged-r286/`: 홈 `orchestration.md` 로스터(구현·추론·테스트 = claude-sonnet-5-5[1m] · 대량 서치 = opencode 나노 · arch·DA 행 변경 0) · `COMM-GUIDE-BOOT.md` 41항.
- **시험** 새 `tests/test_opencode_reap.sh` 50 PASS(남의 opencode 3종 생존 · TERM 무시 KILL · 신호 0 left=2 rc1 · pid 재사용 가드 · 공유 serve oc-skip · 훅 실행 자리 8종) · 새 `tests/test_nano_spawn_tier.sh` 25 · `test_nano_close_fail_closed.sh` ⓗ(record→apply 순서 · CLOSE-FAIL · pid 파일 재실행) · `test_nano_team_env.sh` 기대값 2(의도된 기본 모델) · `test_da_hold_gate.sh` 8b 추출 = `_oc_close`. 회귀 59 새 FAIL 0. 증거 `harness/evidence/r286/`.
- **master 할 일**: `evidence/r286/master-steps.md` — LIVE_BIN 3 cmp0 · 홈 훅 + settings PostToolUse 1줄 · 홈 정본 2 cp · 실사건 = `--tier search` 나노 1석 열고 닫아 `OC-REAPED … left=0` + ps 에 그 좌석 opencode 0.
- 범위 밖: 전역 CLAUDE.md «오케스트레이션» 절 모델 줄 · BYZ `.claude/rules/orchestration.md` · 공유 serve 자체의 메모리.

## 2026-10-19 — 팀 «이름» 바꾸기 도구 `ft-team-rename.sh`: 명단·폴더·명부·env·저장 참조를 한 번에 + 스냅샷 되돌림 + 옛 계보 우편 감시 (r468 · 1.1.32)

카드 r468 · master 78 발주 112808(오빠 «컨시어지 이름 잔존 없도록») · arch 101 실측 · 계획 `design/harness/PLAN-team-rename-concierge-to-chatbot-20261019.md` §3·§6. 기존 `ft-team-move.sh` 는 «같은 이름의 폴더 이동»(design/<팀> → design/teams/<팀>)만 알아, 팀 이름을 바꾸려면 명단 2·폴더·명부·env·틱 표·카드 본문·저장 참조 7종을 손으로 고쳐야 했고 되돌림 스냅샷이 없었습니다.

- **새 `ft-team-rename.sh` + `ft_team_rename.py`**(bin·kit 짝): 이동 도구의 Ctx·점유 판정·Snap·revert·명부 기준 워크트리(store_base)·walk/dump_like/write_text 를 import(복제 0 · 이동 파일 변경 0).
  - `--plan <옛> <새>` = 명단 2행 · 팀 폴더 파일 수 · 본문 치환 예상(패턴 2) · 명부 칸 4·행 수 · REF4~7 · env 파일 · 워크트리 받음/미전환 · BLOCK → `PLAN-END blockers=<n>` · 쓰기 0.
  - `--apply` = 선검사(새 이름 명단에 없음 · 옛 이름 있음 · 폴더 칸 `design/teams/<옛>/` 꼴 · 쌍둥이 `design/<옛>/` 잔존 = `REJECT 먼저 ft-team-move` · 목적지·새 명부·새 env 없음 · 스테이징 비움 · 작업 트리 깨끗 · pane cwd·lsof 점유 0 — 하나라도 걸리면 쓰기 0) → 스냅샷 `.fable-team/state/team-rename/<ts>-<옛>-<새>/` → `git mv` + TEAMS/TEAMSET 행(첫 칸) + 본문 치환 «`design/teams/<옛>/` · `byz-<옛>-`» 둘뿐 + TEAMS 각주 «옛 이름 <옛> → <새>(개명 <날짜> · 좌석 계보 byz-<옛>-* 는 은퇴)» → 한 커밋 → 명부 `seats-<옛>.json` → `seats-<새>.json`(+`.bak-rename-<ts>` · `_name`·`_label` 대소문자 따라 · 경로 칸 · `_doc` · `_renamed_from`·`_renamed_at` · 행 이름·`_master` 등 좌석 이름 불변 · 못 받은 워크트리 기준 행 = `_move_pending`) → nano-card-base·worktree-info·baton·추가 파일 → env `bin-<옛>/` → `bin-<새>/`(파일 이름 + 값: 명부 파일·나노 접두·워크트리 접두·활성 태그·원장 경로 새 꼴·틱 라벨 · 권한 유지) → `AFTER 옛 자리 잔여 <n>`.
  - 같은 `--apply` 를 개명 뒤 다시 = `RESYNC`(head-sync 로 받은 워크트리의 `_move_pending` 행·worktree-info 만 · git 변경 0).
  - `--verify <새>` = 명단·폴더·map-lint·명부 index·카드 기준선·팀 집합 + 옛 폴더·옛 명부·옛 env·옛 명단 행 잔존 = ERR · 잔여 «<옛>» 글자 = WARN 목록(각주·옛 좌석 이름 제외 · 다른 팀 이력 문서는 1줄 요약 · 제품 코드 폴더는 훑지 않음) → `VERIFY ERR=<n> WARN=<m>`.
  - `--revert <스냅샷>` = 만든 파일(새 명부·.bak-rename·새 env) 지움 → 이동 도구 revert(바이트 복원 sha256 + `git revert`).
- **ft-tick.sh** `renamed_watch`: 명부 `_renamed_from` 이 7일 안이면 옛 계보(byz-<옛>-* 최신 번호 좌석) `peek`(소비 0) → pending>0 이면 그 명부 `_master` 에 `[개명 우편]` 1줄 · 1시간 1번(`FT_TICK_RENAMED_SEC`) · 목록이 바뀔 때만(`renamed.sig`) · `FT_TICK_RENAMED=0` 으로 끔. 주석 1(R324 목록 concierge → chatbot).
- **team-tick-env.tsv**: concierge 행 → chatbot(명부·STATE_DIR·PIDFILE·STAMP) · 팀 틱 전 행 끌 감시에 `FT_TICK_RENAMED`(전 명부 스캔은 메인 틱 1개).
- **시험** 새 `tests/test_team_rename.sh` ⓐ~ⓖ 86 PASS(plan 쓰기 0 · REJECT 4종 쓰기 0 · 쌍둥이/옛 꼴 REJECT · apply 한 커밋·명부·env·저장 참조 · RESYNC · verify ERR 0·WARN 목록·변이 ERR · revert 뒤 파일·폴더 manifest 원본 동일 · watch 7일·중복 0 · 600/300 0) · `tests/test_team_tick_unify.sh` concierge → chatbot.
- 실 리포 읽기만: origin/main(a608fea5a0) 사본에서 `--plan concierge chatbot` = 폴더 71파일 · 본문 치환 예상 82+66 · 명부 행 17 · nano-card-base 12 · worktree-info 2 · env 6(이름 4) · `PLAN-END blockers=0`. 증거 `harness/evidence/r468/`.
- 범위 밖: 제품 코드·UI 글자 · 가지·워크트리 이름(보존) · 좌석 교대(successor-open) · launchd 팀 틱 신규 설치.

## 2026-10-19 — 슬랙 보고 도구 인자: reply 의 `--channel` 기본값(None)이 다른 서브명령 7개로 새던 것을 막는다 (r474 · 1.1.31)

카드 r474 · master 79 발주 113237·113489 · arch 102 실측. r414 의 `rpl.set_defaults(channel=None)` 은 reply 만 노렸지만, argparse `parents=[common]` 는 부모의 Action «객체» 를 자식이 공유하고 `set_defaults` 는 그 Action 의 `.default` 를 고치므로 start·progress·result·check·repair·update·attach 의 기본 채널까지 None 이 됐습니다 → 홈 설치(10-19 09:24) 뒤 뉴스 발행 `conversations.history channel_not_found` · 임시 우회 = 뉴스 plist env `FT_NEWS_POST_ARGS=--channel C0C6MJGRR89`. 기존 시험은 매 호출에 `--channel C1` 을 명시해 기본값을 못 봤습니다.

- **kit/slack-mirror/thread_post_args.py**: `--channel` 을 `common` 에서 빼 두 부모로 — `chan`(기본 CHANNEL · 서브명령 7개) / `chan_reply`(기본 None · reply). Action 공유가 없어져 `set_defaults` 삭제 · reply ∧ `--ts` ∧ None → CHANNEL 되돌림 줄 유지 · 그 밖 변경 0.
- **시험** 새 `tests/scripts/test_thread_post_args.py`(`PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest …`): ⓐ 서브명령 7개 기본 channel == CHANNEL ⓑ reply --thread = None ⓒ reply --ts = CHANNEL ⓓ 명시 `--channel C1` 9경우 전부 C1 · 같은 프로세스 reply 뒤 update 도 CHANNEL. RED = origin/main 판 8 FAIL(ⓐ 7 + 누수 1 · 전부 `channel=None`) → 고친 판 19 passed · 기존 `test_thread_post.py`·`test_thread_post_attach.py` 포함 45 passed · `tests/test_thread_reply_named.sh`(r414) ALL PASS.
- **master 할 일**: 착지 → `install.sh --apply --project <루트>` → 홈 `~/.hermes/scripts/thread_post_args.py` cmp0 → 실사건 1 = plist env 없이 뉴스 발행 1회(`conversations.history` ok · 뉴스 틱 로그 줄) → `com.byz.ft-news-planner.plist` 의 `FT_NEWS_POST_ARGS` 줄 제거(되돌림 = 줄 복구 · 파일 되돌림 = `.bak-r474`).
- 범위 밖: 등록부(r414) · 뉴스 발행 본체(r458) · 다른 kit 파일.

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
