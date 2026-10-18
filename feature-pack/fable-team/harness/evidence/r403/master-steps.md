# r403 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r403-mbox-live-bin-root` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   manifest 1.1.8 — 다른 카드가 먼저 1.1.8 을 착지하면 번호를 다음으로(CHANGES 머리·manifest 둘 다).
2. 되돌림 준비(설치 전): `cp -p ~/.claude/fable-team/live/1.1.7/bin/ft-mbox.sh{,.bak-r403}` · `ft-mbox.py` 도 같게.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → `cmp <키트>/bin/ft-mbox.sh <LIVE_BIN>/ft-mbox.sh` = 0 · `ft-mbox.py` 도 = 0 · `ft-live-install-check.sh --range 252ce484..<착지 sha>` OK.
4. 사후 검증 1회(실사건): 실제 좌석 1석에 `<LIVE_BIN>/ft-mbox.sh send <좌석> <나> "…" --urgent` → 그 pane 의 doorbell 줄
   `[발주 #N] FT_MBOX_DIR=<BYZ 루트>/.fable-team/comm bash <LIVE_BIN>/ft-mbox.sh recv <좌석> — …` 에서 명령부만 `(cd /tmp; FT_MBOX_DIR=… bash … recv <좌석>)` rc0 + `READ … #N`.
   → 카드 `- 실사건:` 줄.

## 관측 (실행→나온 것)
- 라이브 꼴 사본(`$T/live/bin` · 조상 `.fable-team` 없음): cwd=리포 워크트리 → 리포 루트 `.fable-team/comm` 사용(워크트리 안 생성 0) · cwd=/tmp → `NO_MAILBOX_ROOT` rc2 + 「cwd 공용 루트 (git 리포 아님) 에도 comm 없음」 · 새 comm 0.
- doorbell(가짜 tmux 로그) 줄이 위 꼴 글자 그대로 · 그 명령부를 cwd=/tmp 에서 실행 → `READ … #<seq>`.
- 옛 꼴(`<리포>/.fable-team/bin` 사본) cwd=/tmp → 조상 유도 그대로(send `file=<리포>/.fable-team/comm/mailbox.jsonl`).

## 끝선 뒤 카드 (범위 밖 · 손 0)
- `harness/tests/test_mbox_lineage.sh` 가 팩에서 rc=1 FAILED 9 — base 252ce484 도 같음. 픽스처 `feature-pack/fable-team/tests/fixtures/mbox_guard/` 가 팩에 없다(BYZ 루트 `tests/fixtures/mbox_guard` 도 없음). 고치는 단위 1장 필요(픽스처 이관 또는 경로 정정).
