# r414 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r414-desk-slack-thread-ts-owned-by-tool-` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = `cfb975e1`(origin/main). 이 가지 파일 = `kit/slack-mirror/thread_post_update.py`·`thread_post_args.py`·`byz_thread_post.py`(머리 1줄) + `ft-successor-open.sh`(bin·kit 둘 다 · cmp 0) + 새 시험 `tests/test_thread_reply_named.sh` + 증거 `evidence/r414/`.
   ★버전 번호·CHANGES 머리는 이 가지에 안 넣었다★(병행 가지와 머리 충돌 방지) — 착지 순서대로 다음 번호를 master 가 붙인다. 문안 = 아래 «CHANGES 절».
   카드 편차 2: ①카드는 reply 서브파서를 `byz_thread_post.py` 에 적었으나 실제 위치는 `thread_post_args.py`(분리 파일) — 거기를 고쳤다(파일 4 개). ②시험 가짜 전송은 카드의 `FT_SLACK_POST` 주입 대신 기존 `--slack-base` 로 로컬 가짜 서버를 가리켰다 — 제품 코드에 시험 전용 주입 경로 0.
2. 되돌림 준비(설치 전): `cp -p <LIVE_BIN>/ft-successor-open.sh{,.bak-r414}` · `~/.hermes/scripts/{thread_post_update.py,thread_post_args.py,byz_thread_post.py}` 각각 `.bak-r414`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → `cmp <키트>/fable-team/bin/ft-successor-open.sh <LIVE_BIN>/ft-successor-open.sh` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
   → ★`~/.hermes/scripts` 3 파일★(LIVE-MAP.tsv:17 `slack-mirror/*`): `cp -p kit/slack-mirror/{thread_post_update.py,thread_post_args.py,byz_thread_post.py} ~/.hermes/scripts/` + cmp 0 셋. 데몬 kickstart 불요(CLI 도구).
4. 닫는 증거(실사건): desk 다음 승계(#20→#21) 발주 본문 부팅 5번 줄을
   `cd ~/.hermes/scripts; timeout 9 python3 byz_thread_post.py reply --thread desk --channel C0C9GRFHJE5 --text-file <f>` 로(첫 호출만 `--channel` · 그 뒤는 등록부 채널) — ts 글자를 넣으면 successor-open 이 REJECT.
   첫 보고 출력 `root desk ts=<뿌리>` + `reply ts=<답글>` → 채널 본문에 `[desk 보고 <날짜>]` 글이 보임(오빠 확인 또는 slack ts 원문) · 등록부 `<BYZ>/.fable-team/state/slack-threads.json` 의 `desk.root_ts` = 그 뿌리.

## CHANGES 절 (착지 번호를 붙여 머리에)
## 2026-10-19 — desk 보고 스레드 뿌리 ts 를 도구가 소유한다: `reply --thread <이름>` + 승계 본문 ts 손 복사 REJECT (1.1.N)

카드 r414 · master 110781 ① · desk#20 110779(오빠 «여기는 왜 매새지 안오냐» · «다음 증류 땐 자동으로»). 뿌리 ts(10-16)가 인계서 13장에 손으로 복사돼 이어졌고, 3일 된 스레드 답글은 채널 본문에 안 보였다.

- **`kit/slack-mirror/thread_post_update.py`**: `reply --thread <이름>` — 등록부 `<FT_ROOT>/.fable-team/state/slack-threads.json`(env `FT_SLACK_THREADS`) `{"<이름>": {channel, root_ts, date, history[]}}`. 없음 ∨ 날짜(KST) ≠ 오늘 ∨ 채널 다름 → 채널에 뿌리 글 `[<이름> 보고 <날짜>]` 1건 + 등록(옛 뿌리 history) → 답글. 본문 post_guard 검사는 뿌리 글 «전»(걸리면 뿌리·등록부 불변). 등록부 손상 = raise.
- **`thread_post_args.py`**: `--ts`·`--thread` 배타 필수(둘 다·둘 다 없음 = usage rc2) · `--thread` 는 `--channel` 생략 시 등록부 채널 · `--ts` 만 = 기존 동작(기본 채널) 불변.
- **`ft-successor-open.sh` ⓐ'**: 후계 이름 `*-desk-*`|`*-planner-*` 이고 본문에 `--ts <10자리>.<6자리>` → `REJECT 본문에 슬랙 ts 손 복사(--ts …) — byz_thread_post.py reply --thread <이름> 으로(r414)` · 열기 0.
- **시험** `tests/test_thread_reply_named.sh` ⓐ~ⓔ 11 PASS · 기존 `test_successor_open.sh`·`test_index_move_slack.sh` rc0 · pytest thread_post·post_guard 62 passed. 증거 `harness/evidence/r414/test.txt`.
