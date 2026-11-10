# 인덱스: ft-nano-spawn — 슬랙 착수 답글 REJECT 때 세션·명부 롤백 + 장부 복구 경로 + 이미 생긴 고아 정리 (R81)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → R81(v65 master#160 쪽지 #71794 · master#25 이관 #71795 · master#26 발주 #71809)
- 상태: 대기
- 선행: 없음(판정 845 롤백 kill 표준승인 · 846 · 847 ③④ 실패만 kill) · R80 랜딩은 선행 아님(장부 복구 ⓐ 만 R80 뒤)
- 제안서: 없음 — 도구 결함 수정(R81)
- 시험 입력: 기존 스텁 픽스처(`tests/scripts/test_nano_spawn_base_sha.py` 의 tmux·tmuxc 셸 스텁 · `tests/harness/test_index_move_slack.sh` 의 byz_thread_post 스텁 rc 지정 · `tests/scripts/test_thread_post.py` 가짜 슬랙) — 실 슬랙·실 tmux 0
- 기준값: 지금 = 카드에 「- 슬랙: <ch> · 시도 <시각>」(뿌리 ts 없음) + 장부 키 없음 상태로 spawn 하면 ③tmuxc open ④태그 ⑤seats.json 등록까지 끝난 뒤 ⑥ft-index-move 가 「REJECT 슬랙 착수 답글 실패 — ThreadError: 장부 불명」 → spawn exit 1 · 세션 1 + 명부 행 1 잔존(2026-10-10 11:08·11:09 실측 2회 → 고아 2석) · `repair --card` = 「HUMAN 표식 글 0건」 rc 1(도구로 닫을 길 0)

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
골의 축: B 「메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의」 + C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행(슬랙) 수신해 반영」. v65 master#160 이 올린 도구 결함.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`ft-nano-spawn.sh` 는 ③세션 열기 → ④태그 → ⑤명부 등록 → ⑥카드 대기→진행(이동 «전» 슬랙 착수 답글) 순서다. 되돌릴 수 없는 일(슬랙 게시)을 맨 뒤에 두는 순서는 맞지만, ⑥이 실패하면 ③~⑤를 되돌리는 코드가 없어 매번 고아 좌석(세션+명부 행)이 남는다. 이번 실패 원인은 카드의 슬랙 줄이 «시도» 상태였기 때문이다: v65 가 승인 제안서를 `byz_proposal_publish.py --card <이 카드>` 로 올리려다 R80 결함(기록+rN 거부·원문 고정)으로 게시 전에 실패했고, 발행기는 게시 «전»에 `thread_unit.note_attempt` 로 「시도」 줄을 이미 써 둔 상태였다. 그 뒤 `byz_thread_post.py progress` 는 장부 키가 없어 「장부 불명」으로 실패하고, `repair` 는 카드 표식 첫 줄(`[<팀>/<카드>]`)로 채널을 찾는데 제안서 글은 첫 줄이 달라 0건 → 「HUMAN」 에서 멈춘다. 이 카드는 세 가지를 한다: ⓐspawn 이 부작용 «전»에 장부를 미리 확인하고(이번 실패는 여기서 0 부작용 REJECT), 그래도 ③④(세션 열기·태그)에서 실패하면 이 실행이 만든 세션을 되돌리고, ⑤⑥ 실패는 자동 정리 없이 사람 판정으로 넘긴다(판정 847) ⓑ`repair` 에 사람이 아는 뿌리 ts 를 주는 길(`--root <ts>`)을 만든다(검증 후 기존 `thread_unit.ensure_root` 재사용) ⓒ되돌리기 함수를 따로 불러 이미 생긴 고아도 같은 조건으로 정리한다.

## 사람 판정 (닫힘)
- 판정 845 ①: spawn 롤백 kill 표준승인 — 그 spawn 이 연 «명부 등록 전» 세션만 · 착수 0·mbox 0·브랜치 커밋 0 · 워크트리·브랜치 보존 · 이미 있던 고아·남의 세션은 대상 아님(전역 CLAUDE.md 반영됨).
- 판정 846 ⓐ: r2 채택 + DA 3차 1회 → 3차 HOLD #71889(⑥ 실패 ≠ 게시 0 — progress 는 게시 «뒤» 장부 갱신이라 게시 성공·장부 실패면 이름 공개됨).
- 판정 847 ①(최종): kill 은 ③④(세션 열기·태그) 실패만 · ⑤⑥ 실패 = kill 0 + 사람 판정 · DA 4차 0. 그래서 spawn 순서 변경(r2 의 ③④⑥⑤)은 필요 없다 — ③④ 는 원래 ⑤ 명부 등록 «전»이다.

## 사전검증
- 소환: 예 — byz-harness-da-codex#1 · 범위 = kill 조건이 «남이 쓰는 세션»을 절대 못 죽이는가 + 사전 확인이 기존 정상 spawn 을 막지 않는가(10+10분 · bounded_da_review)
- 1차 #71852: ②사전 확인 APPROVE · ①HOLD(--opened-now 면제 · pending 큐 0 ≠ 첫 발주 0 · 미커밋 실작업 · 검사~kill 틈) → r1 교정(구현 범위 1-③ⓓⓕⓖⓗ·④ 락+kill 직전 재검사 · 2-ⓑ `--owned`) → 재검토 1회
- 2차 #71860: r1 교정 3건 충족 · ②APPROVE 유지 · ①HOLD — 좌석 락이 발주 도구와 공유되지 않아 «마지막 재검사 → 남의 첫 발주 → kill» 경합이 남음. bounded 2 HOLD 로 리뷰 중단 → r2 제안 → 판정 846 채택(구현 범위 1-④·2-ⓑ 에 녹임) → DA 3차 1회.
- 3차 #71889: ⑤ 실패 kill 0·고아 .sh.hil = 845 일치 · ⑥ 분기 HOLD → 판정 847 로 ⑥ 도 kill 0 · 리뷰 종료.

## 조사 근거 (기준 = origin/main 추적본 · spawn blob d15699a04b · 라이브 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/bin/ft-nano-spawn.sh` 는 main 보다 옛 판(R77 게이트 없음 · 설치 때 drift)
- `scripts/fable-team-bin/ft-nano-spawn.sh`(= `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh` 바이트 동일 두 벌) `:172` dry-run 분기 · `:173` 카드 base_sha 기록 · `:187` worktree add · `:205`~`:206` ③ · `:211`~`:215` ④ · `:218`~`:224` ⑤(python 실패 검사 없음) · `:227` ⑥.
- `scripts/fable-team-bin/ft-index-move.sh:49`~`:72` 슬랙 단계 — 대기→진행 은 `progress` 만 부르고 장부 사전 확인 0.
- `scripts/harness-install/slack-mirror/byz_thread_post.py:133` `cmd_check`(rc 0 결과 있음/게시 대상 아님 · 1 결과 없음 · 3 장부 불명) · `:152` `cmd_repair`(시도 줄 + 표식 0건 = HUMAN rc 1) · 194줄.
- `scripts/harness-install/slack-mirror/thread_unit.py:21` `ensure_root`(카드 줄 + 장부 키 생성 · 다른 root 면 raise).
- `scripts/harness-install/slack-mirror/thread_post_args.py:41` repair 파서(인자 없음).
- `scripts/fable-team-bin/ft-nano-close.sh:403`~`:446` — 고아는 카드가 대기/ 에 있어 「⑥카드 못 찾음」 + 증거 줄 0 으로 REJECT → nano-close 로는 못 닫는다(그래서 ⓒ).
- 실측 고아(2026-10-10): 세션 `ft-v65-temp-m5-lst-loud-default-on-flag-removal#0`(11:08:38)·`#1`(11:08:55) · seats.json 두 행(index 진행/ 경로 · 카드 실물은 대기/) · 워크트리 `.worktrees/v65-m5-lst-loud-default-on-flag-removal` 1개 공유 · 브랜치 `nano/m5-lst-loud-default-on-flag-removal` base 585e1f8f41 이후 커밋 0 · 미커밋 `.serena/project.yml` 뿐 · 그 좌석 앞 mbox 0.
- 복구 대상 스레드: 발행기 상태 `v65/lst-loud-evidence-cap` root_ts = r0 `1791590350.306509` — v65 가 말한 r2 `1791595375.250729` 는 그 스레드의 «답글»이다(뿌리로 쓰면 안 됨).

## 구현 범위 (닫힌 목록 · 나노 브랜치는 origin/main 기준)
1. 새 파일 `scripts/fable-team-bin/ft-nano-spawn-undo.sh` (같은 바이트로 `scripts/harness-install/fable-team/bin/` 에도 · DA 1차 #71852 교정 r1 + 판정 846 r2) — 두 모드: «롤백 모드» `<좌석> --owned <pane_id>:<session_created> --card <대기 카드>`(spawn 만 부름 · kill) · «단독 모드» `<좌석> [--card <대기 카드>]`(이미 명부에 오른 고아 · kill 0 → 계획 파일):
   - ① 팀 env 로드는 spawn 과 같은 규약(좌석명 접두 `FT_NANO_PREFIX`) · 명부 = `FT_SEATS_JSON`.
   - ② 카드 = `--card` 또는 명부 행 `index` 의 `/진행/`→`/대기/`.
   - ③ 조건 — 하나라도 아니거나 «값을 못 읽으면»(정보 불명) REJECT(아무것도 안 함): ⓐ롤백 모드 = 명부에 좌석 행 «없음»(등록 전) · 단독 모드 = 행 있고 role=nano ⓑ좌석명이 `FT_NANO_PREFIX` 로 시작 ⓒ카드가 대기/ 에 실재하고 진행/ 같은 이름 없음(이동 0 = 착수 0) ⓓ그 좌석과 주고받은 쪽지 이력 0건 — 소비되면 지워지는 `mailbox.jsonl` 이 아니라 append 기록 `mailbox.log.jsonl`(+회전본 `.1`)·`bodies/` 에서 `"to"` 또는 `"from"` == 좌석 · 기록 파일이 없으면 불명 ⓔ좌석 브랜치(워크트리 `.worktree-info.json` branch)가 base 이후 커밋 0(`git rev-list --count <base>..<branch>` == 0) ⓕ워크트리 미커밋 실작업 0 — `git status --porcelain` 에서 `.serena/project.yml`·`.worktree-info.json` 을 뺀 줄 0 ⓖ사용자 턴 0 — 세션 pane 의 jsonl(`ft-seat-status.sh turn` 과 같은 해석)에 사용자 턴 0. jsonl 없음은 «불명»(REJECT) — 단 `--owned` 가 소유권 검증(ⓗ)을 통과하고 세션 생성 후 120초 이내일 때만 «턴 0» 으로 본다 ⓗ(롤백 모드 필수) 지금 그 이름의 세션 pane_id·`#{session_created}` 가 인자 값과 둘 다 같아야 한다(spawn 이 open 직후 tmux 에서 읽은 값 · 호출자 주장만으로 면제 0).
   - ④ 실행 — 롤백 모드: 좌석별 락(`mkdir <STATE>/spawn-undo/<좌석>.lock` · 실패 = REJECT) 안에서 ③ 전부 검사 → 태그(`FT_ACTIVE_TAG`) 해제 → «kill 직전» ⓐ(여전히 명부 행 없음)·ⓓ·ⓖ·ⓗ 재검사 — 하나라도 바뀌었으면 태그 복구 후 REJECT → `tmux kill-session`(pane_id 로 해석 — spawn `:211` 과 같은 이유) → `FT_NANO_LEDGER` 에 `spawn-undo <좌석> <사유>` 1행 → 락 해제. 단독 모드: 락 안에서 ③ 전부 검사 → kill 0 · `<STATE>/spawn-undo/<좌석>.sh.hil` 계획만 생성(내용 = 실행 시점 ⓓ·ⓖ·pane_id/session_created(③ 시점 값) 재검사 → 실패면 중단 · 통과면 태그 해제 → kill → 명부 행 삭제 → 원장 1행 · 사람 `!` 실행 — nano-close `--wt` 모드의 `.sh.hil` 과 같은 꼴). 두 모드 모두 워크트리·브랜치·카드 손대지 않음(재spawn 이 워크트리를 재사용한다 — spawn `:185`). 경합 근거(판정 847): 롤백 모드는 spawn 의 ③④ 실패에서만 불린다 — 명부 등록·카드 이동·슬랙 게시·첫 발주 전부 «전»이라 좌석 이름이 발주 경로 어디에도 없다.
   - ⑤ 출력 `UNDONE <좌석>`(롤백) / `PLANNED <좌석> <계획 경로>`(단독) / `REJECT <사유>` · exit 0/1/2.
2. `scripts/fable-team-bin/ft-nano-spawn.sh`(두 벌 동일):
   - ⓐ 사전 확인: `:172` dry-run 분기 «전»(카드 기록·워크트리·세션 전부 전)에 카드에 `- 슬랙:` 줄이 있으면 `byz_thread_post.py check --card` 를 부른다(도구 경로 = `FT_THREAD_POST` · ft-index-move 와 같은 기본값). rc 0·1 = 통과 · rc 3 = `REJECT 슬랙 장부 불명 — byz_thread_post.py repair --card <카드> (부작용 0)` · 그 밖·도구 없음 = REJECT. dry-run 도 같은 확인을 한다.
   - ⓑ 롤백(판정 847): 순서는 지금 그대로(③→④→⑤→⑥→⑦). ③ 세션이 뜬 직후 pane_id·`#{session_created}` 를 읽어 `OWNED=<pane_id>:<created>`(못 읽으면 「롤백 불가 — 고아: <좌석>」 출력 후 exit 1). ③ 실패 뒤(세션이 떠 있으면)·④ 실패 = `ft-nano-spawn-undo.sh "$NAME" --owned "$OWNED" --card "$IDX"` 출력 그대로 + exit 1(undo REJECT 면 「롤백 실패 — 고아: <좌석> (사유)」). ⑤·⑥ 실패 = kill 0 · undo 0 · `REJECT <단계> 실패 — 세션 <좌석> 떠 있음·명부 등록됨 — 사람 판정(ft-nano-spawn-undo.sh <좌석> 단독 모드로 계획 생성 가능)` + exit 1(자동 정리 0).
   - ⓒ ⑤ python 실패를 검사한다(지금은 실패해도 ⑥ 으로 넘어간다) — 실패 = ⓑ 의 ⑤·⑥ 실패 출력.
   - 롤백은 함수 1개(`fail_rb`)로 묶어 각 exit 경로를 그 함수 호출로 바꾼다 — spawn 순증 10줄 이하.
3. `scripts/harness-install/slack-mirror/byz_thread_post.py` `cmd_repair` + `thread_post_args.py:41`: `repair --root <ts>` — 카드 줄이 「시도」 이거나 없을 때만 받는다(뿌리 ts 가 이미 있으면 지금처럼). `conversations.replies`(channel, ts=<ts>, limit 1)의 첫 글 ts == <ts> 이고 `bot_id` 있음 ∧ (`thread_ts` 없음 또는 == <ts>)일 때만 `thread_unit.ensure_root(...)` 호출 → `repaired <uid> root_ts=<ts>`. 아니면 raise(「답글 ts 는 뿌리가 아니다」 등 · 쓰기 0). 194줄이 200줄을 넘으면 repair 를 `thread_unit.py` 로 옮긴다.
4. 시험:
   - spawn(`tests/scripts/test_nano_spawn_rollback.py` 새 파일 · `test_nano_spawn_base_sha.py` 픽스처 방식 복제): ①카드 시도 줄 + check 스텁 rc 3 → REJECT · tmuxc 호출 0 · 명부 변화 0 · 카드 바이트 동일 ②④태그 실패 → undo `--owned` 호출 1회 · kill-session 스텁 1 · 명부 파일 바이트 불변 ③tmuxc open 실패 + 세션은 떠 있음 → 같은 롤백 ④ft-index-move 스텁 exit 1(⑥) → kill 0 · undo 0 · 「사람 판정」 출력 ⑤명부 쓰기 실패(⑤) → kill 0 · undo 0 · 「사람 판정」 출력 ⑥정상 경로 = SPAWNED · 결과 명부·카드 지금과 같음 ⑦슬랙 줄 없는 카드 = check 호출 0.
   - undo(같은 파일 또는 `tests/harness/test_nano_spawn_undo.sh`): 롤백 모드 — 조건 ⓐ~ⓗ 각각 하나씩 깨면 REJECT · kill 0: ⓐ명부에 행 있음 ⓓ소비된 쪽지(mailbox.jsonl 0 · log 1건) ⓓ'기록 파일 없음 ⓔ브랜치 커밋 1개 ⓕ미커밋 실작업 1파일(.serena 만이면 통과) ⓖ사용자 턴 1 ⓖ'jsonl 없음 + 생성 120초 넘음 ⓗpane_id 다름·session_created 다름 · 재검사 단계에서 쪽지 1건이 생기면 REJECT + 태그 복구 · 락 선점 시 REJECT · 전부 충족 = UNDONE. 단독 모드 — kill 호출 0 · `.sh.hil` 1개 생성 · PLANNED 출력 · 계획 실행 시점에 쪽지 1건이 생겼으면 계획이 중단(kill 0).
   - repair `--root`(`tests/scripts/test_thread_post.py` 에 추가): 뿌리 ts → 카드 줄·장부 생성 ②답글 ts(thread_ts ≠ ts) → raise · 쓰기 0 ③카드에 이미 다른 뿌리 → 지금처럼 거부 ④봇 글 아님 → raise.
   - 기존 시험 전부 PASS.

커밋은 자기 브랜치, **push 금지**. **금지**: 워크트리 삭제·브랜치 삭제 · 카드 이동·되돌리기 · ft-index-move 순서 변경 · 실 슬랙·실 tmux · 라이브 `.fable-team/bin`·`~/.hermes/scripts` 직접 수정 · 발행기(`byz_proposal_publish.py`) 수정(R80 몫).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `python3 -m pytest tests/scripts/test_nano_spawn_rollback.py tests/scripts/test_nano_spawn_base_sha.py tests/scripts/test_nano_spawn_branch_collision.py tests/scripts/test_thread_post.py -q` rc=0 · `bash tests/harness/test_index_move_slack.sh` rc=0 · `bash -n` 새·바뀐 셸 · `ruff check` 변경 py 0 · 두 벌 `cmp` 동일 · 새 파일·slack-mirror 파일 200줄 이하 · spawn(지금 236줄)은 순증 10줄 이하.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: python3 -m pytest tests/scripts/test_nano_spawn_rollback.py tests/scripts/test_nano_spawn_base_sha.py tests/scripts/test_nano_spawn_branch_collision.py tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0`.
- 랜딩 뒤 master 집행(카드 밖): 라이브 `.fable-team/bin/{ft-nano-spawn.sh,ft-nano-spawn-undo.sh}` · `~/.hermes/scripts/{byz_thread_post.py,thread_post_args.py,thread_unit.py}` `.bak-r81-<날짜>` → 추적본 cp → cmp(라이브 spawn 은 main 보다 옛 판 — drift 검사가 함께 맞춰진다).
- 이미 생긴 고아(v65 몫 · 판정 845 대상 아님): ★고아는 유휴가 아니라 위험하다 — master 실측: #0·#1 은 발주 0 인데 카드를 직접 읽고 자가 착수(#1 RED 커밋 271b66abeb · 같은 워크트리 동시 편집)★. 그래서 #1 은 단독 모드도 REJECT(ⓔ 브랜치 커밋 · ⓖ 사용자 턴)가 정답이고 처리(산출물 회수·닫기)는 v65 master 판정 · 작업물 없는 좌석만 단독 모드 계획(PLANNED) → 사람 `!`. 장부 복구는 ⓐR80 랜딩 뒤 `byz_proposal_publish.py --revision r3 --card <M5 카드>`(발행기 `ensure_root` 가 root `1791590350.306509` 로 카드·장부를 채움) 또는 ⓑ`byz_thread_post.py repair --card <M5 카드> --root 1791590350.306509` 중 하나 → 그 뒤 재spawn. 결과 1줄 v65 master#160.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: a3cbe3ba92962dc91b1051d1c4c874716dbe4683 (spawn 2026-10-10)
대기 — 확정(판정 847) · master spawn 대기

## 결과
(닫을 때 증거 줄)
- 2026-10-10 11:38 — 대기→진행 · 좌석 byz-harness-nano-r81-spawn-reject-rollback#0
세트: 9dda97a61f58c67c131627422e630fb6965ef70f · 시험: python3 -m pytest tests/scripts/test_nano_spawn_rollback.py tests/scripts/test_nano_spawn_base_sha.py tests/scripts/test_nano_spawn_branch_collision.py tests/scripts/test_thread_post.py -q rc=0 · 이슈: 0
- 2026-10-10 — 나노 완료(커밋 50aa016de1[feature repair --root]+9dda97a61f[fix 롤백·undo]) · 마스터 재실행 61 passed · 변경 파일 ruff 0 · 라이브 5파일 main 동일(덮어쓸 차이 0) · 판정 849 랜딩 승인
- 2026-10-10 — 닫힘: 커밋 50aa016de1[feature]+9dda97a61f[fix] · 61 passed(마스터 재실행)·86 passed(묶음) · 라이브 설치 .bak-r81 + cmp OK(ft-nano-spawn.sh · 새 ft-nano-spawn-undo.sh · ~/.hermes 3파일) · 드리프트 OK · main 랜딩 PR 1183 ddcf90affc (판정 849)
