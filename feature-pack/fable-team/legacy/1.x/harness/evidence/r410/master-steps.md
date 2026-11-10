# r410 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r410-proxy-decide-wt-clean-kind-and-morn` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `81afaacf`(origin/main · 1.1.9). 파일 겹침: r407·r408·r409 와 0 — 이 가지 = `ft-proxy-decide.sh`·`autonomy_classify.py`(bin·kit 둘 다 · cmp 0) + `comm/mbox_guard.sh`(2줄) + 새 `comm/mbox_guard_morning.sh` + 시험 `tests/test_proxy_decide_r188.sh` 새 절 + 픽스처 `fixtures/r410/wt-clean-plan.sh.hil`(실 계획 사본 · plan-ver 만 시험이 바꿔 굽는다).
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★ — r407·r408 가지가 이미 1.1.10 을 쓴다(머리 충돌). 착지 순서대로 다음 번호를 master 가 붙인다. CHANGES 절 문안 = 아래 «CHANGES 절».
   카드의 «skill/scripts/ 짝» 은 이 두 파일엔 없다 — 짝은 `harness/bin/` ↔ `harness/kit/fable-team/bin/`(시험 첫 절이 cmp 0 확인).
2. 되돌림 준비(설치 전): 라이브 bin 의 `ft-proxy-decide.sh`·`autonomy_classify.py` 와 BYZ `.fable-team/comm/mbox_guard.sh` `cp -p … .bak-r410`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 키트 2 파일 `cmp <키트>/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
   → ★쪽지 가드는 install.sh 가 안 나른다★: `cp harness/comm/mbox_guard.sh harness/comm/mbox_guard_morning.sh <BYZ>/.fable-team/comm/` + `cmp` 0 두 파일(새 파일 빠지면 아침 묶음 머리가 «본체 없음» fail-closed REJECT).
4. 닫는 증거(실사건): 자율 ON 중 planner 가 끝난 나노 워크트리 1건을
   `ft-proxy-decide.sh --kind wt-clean --plan <BYZ>/.fable-team/state/wt-clean/<좌석>.sh.hil --q … --choice 실행 --why … --undo "git worktree add <경로> <브랜치>"` → `PROXY 판정 N` rc0 → `bash <계획>` rc0 → 아침 큐엔 결과 1줄.
   후보: h97~h99 계획 3개(`ft-v65-temp-m7-port-mic-track-ended-f16d0a0522-to-ma#0` · `…-test-schema-drift-endpoint-unobservab#0` · `…-test-open-wait-dl-retire-b1-flake-und#0`) — plan-ver `dbd51854168b…` = 지금 팩 `ft-nano-close.sh` blob 과 같다(시험 ⓑ 원문의 «생성기 dbd5185…»). 좌석 tmux 세션이 남아 있으면 ④ QUEUE.
   또는 `[아침 묶음` 쪽지 1통이 `결정 N: … 대리=PROXY <번호>` 칸으로 통과(가드 로그 `state/mbox-guard-morning.log` 에 REJECT 0).

## CHANGES 절 (착지 번호를 붙여 머리에)
## 2026-10-19 — 자율 ON 중 «끝난 나노 워크트리 정리» 를 대리할 수 있게 하고, 아침 묶음 «결정» 줄은 대리 시도 칸을 강제한다 (1.1.N)

카드 r410 · planner 판정 2326 · master 110379 ① · 실사건 #110310(결정 1 = h97~h99 워크트리 정리 · 결정 2 = 아침 음성 시험 — 둘 다 대리 없이 오빠 결정으로 올라감).

- **autonomy_classify.py**: 대리 종류 `wt-clean` 추가(5종) · `--plan-text` = 계획 본문의 «실행 줄»(주석 줄 제외)만 같은 제외 어휘 표로 본다 — 단 [삭제] 는 계획 자신의 일(임시 파일 rm · 브랜치 보존 정리 = 09-25 표준승인)이라 세지 않는다 · 표는 그대로.
- **ft-proxy-decide.sh**: `--plan <상태>/wt-clean/<좌석>.sh.hil` · `wt_clean_check` = ①경로가 상태/wt-clean 폴더(실경로 비교 · `..` 차단) ②`# plan-ver:` = 라이브 `ft-nano-close.sh` blob(다르면 STALE QUEUE) ③«브랜치는 지우지 않는다» 글자 ④`SEAT=` 좌석 tmux 세션 0(`FT_TMUX_BIN` · tmux 없으면 QUEUE) ⑤실행 줄 제외 어휘. 계획 실행은 하지 않는다(PROXY 뒤 호출자). `push-merge` QUEUE 고정 불변.
- **쪽지 가드 문 ⑤**(`comm/mbox_guard_morning.sh`): 머리 `[아침 묶음` 쪽지(본문 + relay 첨부)의 `결정 N:` 줄마다 `대리=PROXY <번호>` 또는 `대리=QUEUE <사유>` — 없으면 REJECT rc3(큐 0) · 결정 줄 없는 묶음은 영향 0 · 본체 파일 없으면 아침 묶음 머리 fail-closed.
- **시험**: `test_proxy_decide_r188.sh` 새 절 R410 ⓐ~ⓓ(27 PASS 추가 · 기존 절 그대로) · `test_autonomy_kinds_1675.sh` 그대로 rc0.

## 관측 (실행→나온 것 · 원문 test.txt · test-kinds-1675.txt)
- 판정기를 BYZ `state/wt-clean/` 실 계획 41개에 돌림: PROXY 33 · QUEUE 8(전부 손으로 쓴 옛 계획 — plan-ver 없음 7 + 좌석 이름에 «drop» 이 든 1). 손 계획 7개는 plan-ver 가 없어 ② 에서도 QUEUE.
- 이 «drop» 1건(`byz-loom-nano-loom-1643-env-layer-drop-raise#0`)은 이름 글자 오탐 — QUEUE(안전한 쪽)라 그대로 둔다.

## 범위 밖 · 기존 실패(이 가지와 무관 · 별도 고침 단위 필요)
- origin/main 81afaacf 그대로에서도 FAIL: `test_mbox_guard.sh` 25 · `test_boot_report_gate.sh` 7 · `test_da_hold_gate.sh` 1 · `test_goal_table_gate.sh` 1 — 이 가지와 FAIL 줄이 같다(`preexisting-fails.txt`). 대부분 «WARN 미등록 … — 전송»(명부 픽스처가 지금 수신자 판정과 안 맞음).
