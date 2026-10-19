# r462 master-steps — 착지 → 설치 → 실사건 1

가지 `nano/r462-approve-merge-equiv-head-with-main-`(ai-feature-pack) · 카드 BYZ `design/harness/indices/진행/r462-approve-merge-equiv-head-with-main-merge-only.md`

## 1. 착지 전
- 팩 PR 1개(master). 바뀐 파일: 훅 `kit/fable-team/templates/hooks/autonomy-merge-guard.sh` · `bin/ft-autonomy.sh` = `kit/fable-team/bin/ft-autonomy.sh`(cmp0) · 새 시험 `tests/test_autonomy_merge_equiv.sh` · 시험 2곳 단언(`test_autonomy_kinds_1675.sh` · `test_merge_land_off_approval.sh`) · `CHANGES.md` 1절.
- 시험 rc: `tests-rc.txt`.

## 2. 설치 (홈 훅)
1. 되돌림 사본: `cp ~/.claude/hooks/autonomy-merge-guard.sh ~/.claude/hooks/autonomy-merge-guard.sh.bak-r462`
2. `install.sh --apply --project <BYZ 공용 루트>` (워크트리 아님 · r457)
3. 확인: `cmp <팩>/harness/kit/fable-team/templates/hooks/autonomy-merge-guard.sh ~/.claude/hooks/autonomy-merge-guard.sh` → 0 · LIVE_BIN `ft-autonomy.sh` cmp0 · LIVE_BIN 에 `ft_approval_equiv.py` 실재(훅이 `ft-autonomy.sh` 옆에서 찾는다 — 없으면 EQUIV 0 · 글자 일치만).
- 참고: 설치 전 홈 훅은 키트 원본과 44행 주석 1줄이 이미 달랐다(`tests/harness/…` ↔ `$FT_HARNESS_ROOT/tests/…`) — 설치로 키트 글자로 맞춰진다.

## 3. 실사건 1
- 오빠가 `approve-merge <A>` 한 PR 에서 가지에 main 을 병합해 head 가 H 로 바뀐 뒤, 재승인 없이 `gh pr merge <N> --squash --match-head-commit <H>` 가 통과.
- 증거: `~/.claude/logs/autonomy-hooks.log` 의 `autonomy-merge-guard: EQUIV <A> -> <H> (EQUIV approve=… mode=merge|rebase …)` 1줄 + 쪽지 번호 → 카드 `- 실사건:` 줄.
- 주의: 판정기는 로컬 git 만 본다 — 병합 전 그 리포에서 `git fetch origin` (head 객체 · origin/main 최신). main 이 head 의 main 병합 뒤로 더 나갔으면 rebase 모드가 NOT-EQUIV 를 낸다(«PR head 도 지금 main 위가 아님») → main 을 한 번 더 병합하고 같은 승인으로 다시.

## 4. 정본 1줄 (착지 뒤 · arch 손)
- `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 33 끝: «approve-merge 승인은 같은 변경 집합(승인 sha 위 main 병합만 더한 head · ft_approval_equiv EQUIV)에도 유효 — 훅이 EQUIV 로 통과(r462)»
