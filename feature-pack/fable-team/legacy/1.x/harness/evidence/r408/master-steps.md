# r408 — master 단계 (나노 산출 · 실행 0)

1. 팩 PR: 브랜치 `nano/r408-planner-quiet-needs-live-inbox-watc` push → PR (나노 push 금지) → 병합은 `gh pr merge <N> --match-head-commit <가지 HEAD 40자>`.
   가지 base = origin/main `81afaacf`(r403 1.1.8 · r406 1.1.9 착지 뒤). manifest 1.1.10 — 다른 카드가 먼저 1.1.10 을 착지하면 번호를 다음으로(CHANGES 머리·manifest 둘 다).
2. 되돌림 준비(설치 전): 라이브 bin `ft-mbox.sh` · `ft_teamset.py` · `ft-teamset-check.sh` 와 BYZ `.fable-team/comm/mbox.sh` 를 `cp -p … .bak-r408`.
3. 착지 뒤 harness-live ff → `bash <팩>/feature-pack/fable-team/harness/install.sh --apply --project <BYZ 루트>`
   → 키트 3 파일 `cmp <키트>/bin/<f> <LIVE_BIN>/<f>` = 0 · `ft-live-install-check.sh --range <병합 전 main>..<착지 sha>` OK.
   ★install.sh 는 comm 을 안 건드린다★ — `cp -p <팩>/feature-pack/fable-team/harness/comm/mbox.sh <BYZ>/.fable-team/comm/mbox.sh` → cmp 0 (좌석들이 쓰는 send 경로는 이쪽).
4. 닫는 증거: 실제 planner `_master` 앞 send 1회 원문(감시 있으면 `doorbell=quiet` · 없으면 `doorbell=quiet(WATCH 없음)` + 하네스 master 쪽지 #N)
   + `bash <BYZ>/.fable-team/bin/ft-teamset-check.sh planner` 1줄 → 카드 `- 실사건:` 줄.
   (판정만 먼저 보려면 쓰기 0: `bash <LIVE_BIN>/ft-mbox.sh watch-alive 'byz-planner-master-claude#72'`)

## 관측 (실행→나온 것 · 원문 test.txt)
- 라이브 판정(키트 사본 · 쓰기 0): planner#72 감시(Monitor zsh → Python pid 60861 `-u - ~/.claude/fable-team/live/1.1.9/bin byz-planner-master-claude#72`) → `OK watch` · `#7`·`#71` → `NO watch`.
- 카드 원안 `pgrep -f "ft-inbox-watch.sh <좌석>"` 은 감시가 exec 뒤 python 이라 Monitor 셸 래퍼가 없으면(직접·nohup 기동) 0건 — 판정을 python 실체 꼴로 바꿨다.
- 카드 «구현 범위» 는 키트 2 파일이었으나 좌석들이 실제로 쓰는 send 는 `comm/mbox.sh`(BYZ 사본 = 팩 `harness/comm/mbox.sh` cmp 0) — 같은 분기를 넣어야 닫는 증거(planner 앞 send 원문)가 나온다.
- 새 시험 46 PASS ×3 · 옛 코드 20 FAIL. 기존 5 시험(teamset_check 6 · teamset_gitref 4 · mbox_guard 25 · mbox_lineage 10 · mbox_v2_guard 12 FAIL)은 origin/main 기준선과 FAIL 수 같음 — 이 단위가 만든 실패 0.

## 끝선 뒤 (범위 밖 · 손 0)
- COMM-GUIDE-BOOT 2 부팅 보고 칸 `watch=<pid>`(planner 한정) 1줄 — 카드 §5 대로 끝선 뒤 기록.
- 위 기존 실패 5 시험 — 빨강 그대로(판정 1395: 기존 RED 도 고치는 단위 필요).
- 나노가 만든 기준선 비교용 detached 워크트리 `…/scratchpad/base408`(팩 리포 · origin/main 81afaacf) — `git worktree remove` 가 block-destructive 훅에 막혀 남김. 정리 = master 손(`git -C <팩> worktree remove <경로>`).
