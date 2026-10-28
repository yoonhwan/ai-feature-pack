#!/usr/bin/env bash
# test_finished_cleanup_auto.sh — r444 끝난 것 자동 정리: ⓐⓑ wt-sweep --launchd · ⓒ scratch sweep(tmux 주입·즉시) · ⓓ ft-finished-check · ⓔⓚ ft-branch-archive
#   ⓕ branch -D 0 · ⓖ spawn sparse 패턴 · ⓗ spawn 여유 검사 · ⓘ nano-close ⑥ 팀 폴더 리졸버 · ⓙ 600/300·외부 호출 0 · ⓛ 껍데기 경보 팀 라우팅
# 픽스처 = 임시 리포 + 가짜 tmux·mbox · 실제 워크트리·세션·우편함 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
B="$(cd -- "$HERE/../bin" && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 공용 픽스처: 리포 R(팀 명단 3) · origin/main · 가짜 tmux · 가짜 mbox · 명부 ──
R="$T/R"; mkdir -p "$R/design/teams/lecture/indices/완성" "$R/design/teams/lecture/indices/진행" "$R/.fable-team/state" "$T/bin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | h | 현역 |\n| lecture | `design/teams/lecture/` | l | 현역 |\n| v65 | `design/teams/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
echo r > "$R/README"; echo a > "$R/a.txt"
git -C "$R" init -q -b main && G "$R" add design README a.txt && G "$R" commit -qm base
git -C "$R" update-ref refs/remotes/origin/main HEAD; MAIN="$(git -C "$R" rev-parse HEAD)"
printf '#!/bin/sh\n[ -f "%s/tmuxfail" ] && exit 1\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"; : > "$T/sessions"
printf '#!/bin/sh\necho "$@" >> "%s/mbox.log"\n' "$T" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '{"_master":"byz-v65-master-claude#1","byz-v65-master-claude#1":{"role":"master"}}\n' > "$R/.fable-team/seats.json"
printf '{"_master":"byz-lecture-master-claude#2","byz-lecture-master-claude#2":{"role":"master"}}\n' > "$R/.fable-team/seats-lecture.json"
printf '{"_master":"byz-harness-master-claude#76","byz-harness-master-claude#76":{"role":"master"}}\n' > "$R/.fable-team/seats-harness.json"
export FT_TMUX_BIN="$T/bin/tmux"
WC="$R/.fable-team/state/wt-clean"; mkdir -p "$WC"
sweep_ld() { OUT="$(cd "$T" && env FT_ROOT="$R" FT_MBOX_SH="$T/mbox.sh" FT_WT_ARCHIVE="${ARCH:-0}" FT_WT_SHELL_SCAN_SEC=0 bash "$B/ft-wt-sweep.sh" --launchd 2>&1)"; RC=$?; }

# ⓐ 계획 3장 + 세션 없음 → launchd 1회에 3장 · 로그 cleaned=3
for s in s1 s2 s3; do printf '#!/bin/bash\necho cleaned\n' > "$WC/$s.sh"; done
sweep_ld
L="$(tail -1 "$R/.fable-team/state/wt-sweep.log" 2>/dev/null)"
{ [ "$RC" = 0 ] && printf '%s' "$L" | grep -q 'cleaned=3 ' && [ -f "$WC/s1.sh.done" ] && [ -f "$WC/s3.sh.done" ]; } \
  && ok "ⓐ wt-sweep --launchd: 계획 3장 실행(기본 MAX 20) · 로그 cleaned=3" || bad "ⓐ rc=$RC log=[$L] out=${OUT:0:300}"
# ⓑ 계획 1장 + 좌석 살아 있음 → WAIT(제자리) · 로그 wait=1
printf '#!/bin/bash\necho "skipped:좌석 byz-x#0 살아 있음"\n' > "$WC/w1.sh"; sweep_ld
L="$(tail -1 "$R/.fable-team/state/wt-sweep.log")"
{ printf '%s' "$L" | grep -q 'wait=1 ' && [ -f "$WC/w1.sh" ] && printf '%s' "$OUT" | grep -q '^WAIT w1'; } && ok "ⓑ 좌석 살아 있음 → WAIT · 계획 제자리 · 로그 wait=1" || bad "ⓑ log=[$L] out=${OUT:0:300}"
rm -f "$WC/w1.sh"
OUT="$(env -u FT_ROOT bash "$B/ft-wt-sweep.sh" --launchd 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q 'FT_ROOT'; } && ok "ⓐ' --launchd FT_ROOT 없음 → ERROR rc2" || bad "ⓐ' rc=$RC $OUT"

# ⓒ scratch: 주인 tmux 죽음 → 즉시 swept=2(나이 문턱 0) · tmux 못 읽음 → ERROR tmux unreadable + 삭제 0
SR="$T/SR"; SCR="$T/scr"; mkdir -p "$SR/.fable-team/state" "$SCR"; date +%s > "$SR/.fable-team/state/scratch-sweep.armed"
sc() { OUT="$(env FT_RES_ROOT="$SR" FT_SCRATCH_DIR="$SCR" TMPDIR="$T/td" FT_SCRATCH_OWNER="${OWN:-dead-owner}" bash "$B/ft-scratch-repo.sh" "$@" 2>&1)"; RC=$?; }
mkdir -p "$T/td"; G "$R" commit -q --allow-empty -m c2; S2="$(git -C "$R" rev-parse HEAD)"
sc "$MAIN" --repo "$R"; C1="$OUT"; sc "$S2" --repo "$R"; C2="$OUT"; sc "$MAIN" --repo "$R"; C1b="$OUT"
[ "$C1" = "$C1b" ] && ok "ⓒ 같은 sha·같은 주인 사본은 재사용(새로 안 만듦)" || bad "ⓒ 재사용 아님 $C1 vs $C1b"
touch "$T/tmuxfail"; sc --sweep
{ printf '%s' "$OUT" | grep -q '^ERROR tmux unreadable' && [ -d "$C1" ] && [ -d "$C2" ]; } && ok "ⓒ tmux 못 읽음 → stdout ERROR tmux unreadable 1줄 + 삭제 0" || bad "ⓒ unreadable [$OUT]"
rm -f "$T/tmuxfail"; sc --sweep
{ [ ! -d "$C1" ] && [ ! -d "$C2" ] && grep -q 'swept=2 owner-dead=2' "$SR/.fable-team/state/scratch-sweep.log"; } && ok "ⓒ 주인 tmux 죽음 → 즉시(생성 직후) swept=2 owner-dead=2" || bad "ⓒ swept [$OUT] $(tail -2 "$SR/.fable-team/state/scratch-sweep.log")"

# ⓓ ft-finished-check — 가지 4종(끝남·착지 아님·카드 없음·변경 0) + 좌석 살아 있음
mkbr() { G "$R" branch "$1" "$MAIN"; git -C "$R" worktree add -q "$T/wt-$2" "$1"; G "$T/wt-$2" commit -q --allow-empty -m "w $2"; git -C "$R" worktree remove "$T/wt-$2"; }
mkbr nano/r1-done d1; mkbr nano/r2-notland d2; mkbr nano/r3-nocard d3; G "$R" branch nano/r4-empty "$MAIN"
printf '## 상태\n- 착지: %s\n' "$MAIN" > "$R/design/teams/lecture/indices/완성/r1-done.md"
printf '## 상태\n- 착지: %s\n' "$(git -C "$R" rev-parse nano/r2-notland)" > "$R/design/teams/lecture/indices/완성/r2-notland.md"
printf '## 상태\n' > "$R/design/teams/lecture/indices/진행/r4-empty.md"
fc() { OUT="$(bash "$B/ft-finished-check.sh" "$1" --repo "$R" 2>&1)"; RC=$?; V="${OUT%%$'\n'*}"; V="${V%% *}"; }
fc nano/r1-done;    [ "$V" = FINISHED ] && ok "ⓓ E0~E3 전부 참 → FINISHED" || bad "ⓓ r1 [$OUT]"
fc nano/r2-notland; [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1 no' && ok "ⓓ 착지 sha 가 origin/main 조상 아님 → ACTIVE(E1 no)" || bad "ⓓ r2 [$OUT]"
fc nano/r3-nocard;  [ "$V" = ORPHAN ] && ok "ⓓ 카드 없음 → ORPHAN" || bad "ⓓ r3 [$OUT]"
fc nano/r4-empty;   [ "$V" = EMPTY ] && ok "ⓓ main 대비 변경 0 → EMPTY" || bad "ⓓ r4 [$OUT]"
echo 'byz-lecture-nano-r1-done#0' > "$T/sessions"; fc nano/r1-done
[ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E3 no tmux' && ok "ⓓ 좌석(tmux) 살아 있음 → ACTIVE(E3 no)" || bad "ⓓ live [$OUT]"
touch "$T/tmuxfail"; fc nano/r1-done; [ "$V" = ACTIVE ] && ok "ⓓ tmux 못 읽음 → ACTIVE(«세션 0» 으로 안 셈)" || bad "ⓓ tmuxfail [$OUT]"
rm -f "$T/tmuxfail"; : > "$T/sessions"

# ⓔ ft-branch-archive — FINISHED 만 refs/archive 로 · ACTIVE/ORPHAN 이동 0 · 되살림 로그
ba() { OUT="$(env FT_ROOT="$R" bash "$B/ft-branch-archive.sh" "$@" --repo "$R" 2>&1)"; RC=$?; }
SHA1="$(git -C "$R" rev-parse nano/r1-done)"; ba nano/r1-done
{ [ "$RC" = 0 ] && [ "$(git -C "$R" rev-parse -q --verify refs/archive/nano/r1-done)" = "$SHA1" ] && ! git -C "$R" rev-parse -q --verify refs/heads/nano/r1-done >/dev/null \
  && ! git -C "$R" branch --list 'nano/r1-done' | grep -q . && grep -q "ARCHIVED nano/r1-done $SHA1 restore: git branch nano/r1-done refs/archive/nano/r1-done" "$R/.fable-team/state/branch-archive.log"; } \
  && ok "ⓔ FINISHED → refs/archive 생성 + refs/heads 제거(squash 착지 가지) + 되살림 명령 로그" || bad "ⓔ rc=$RC [$OUT]"
git -C "$R" cat-file -e "$SHA1^{commit}" && ok "ⓔ 커밋은 남음(보관 ref 가 쥠)" || bad "ⓔ 커밋 사라짐"
ba nano/r2-notland; { [ "$RC" = 1 ] && git -C "$R" rev-parse -q --verify refs/heads/nano/r2-notland >/dev/null && ! git -C "$R" rev-parse -q --verify refs/archive/nano/r2-notland >/dev/null; } && ok "ⓔ ACTIVE → 이동 0" || bad "ⓔ r2 rc=$RC [$OUT]"
ba nano/r3-nocard;  { [ "$RC" = 1 ] && git -C "$R" rev-parse -q --verify refs/heads/nano/r3-nocard >/dev/null; } && ok "ⓔ ORPHAN → 이동 0" || bad "ⓔ r3 rc=$RC [$OUT]"
ba nano/r4-empty;   { [ "$RC" = 1 ] && git -C "$R" rev-parse -q --verify refs/heads/nano/r4-empty >/dev/null; } && ok "ⓔ EMPTY(빈 가지) → 이동·삭제 0" || bad "ⓔ r4 rc=$RC [$OUT]"
# ⓔ' launchd 재확인 경로가 같은 판정기로 옮긴다(완성 이동 뒤 틱)
mkbr nano/r5-late d5; printf '## 상태\n- 착지: %s\n' "$MAIN" > "$R/design/teams/lecture/indices/완성/r5-late.md"
ARCH=1 sweep_ld; L="$(tail -1 "$R/.fable-team/state/wt-sweep.log")"
{ git -C "$R" rev-parse -q --verify refs/archive/nano/r5-late >/dev/null && printf '%s' "$L" | grep -q 'archived=1 '; } && ok "ⓔ' --launchd 재확인: FINISHED 가지 1 이동 · 로그 archived=1" || bad "ⓔ' log=[$L]"

# ⓕ 바뀐/새 도구에 `git branch -D` 호출 0(주석 줄 제외)
hits="$(grep -nE 'branch[[:space:]]+-D' "$B/ft-branch-archive.sh" "$B/ft-finished-check.sh" "$B/ft-wt-sweep.sh" "$B/ft-scratch-repo.sh" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
[ -z "$hits" ] && ok "ⓕ branch -D 호출 0" || bad "ⓕ $hits"

# ⓖ spawn sparse 패턴 — 남의 팀 design 없음 · 자기 팀 indices·증거 있음 · 루트 파일 있음
mkdir -p "$T/SP/design/teams/v65/evidence" "$T/SP/design/teams/lecture/indices/진행" "$T/SP/design/teams/lecture/evidence" "$T/SP/code"
echo 1 > "$T/SP/design/teams/v65/evidence/big"; echo 2 > "$T/SP/design/teams/lecture/indices/진행/c.md"; echo 3 > "$T/SP/design/teams/lecture/evidence/e"; echo 4 > "$T/SP/code/f"; echo 5 > "$T/SP/README"; echo 6 > "$T/SP/design/x.md"
git -C "$T/SP" init -q -b main && G "$T/SP" add design code README && G "$T/SP" commit -qm b
eval "$(grep -E '^sparse_patterns\(\)' "$B/ft-nano-spawn.sh")"
git -C "$T/SP" worktree add -q --no-checkout "$T/SPW" -b nano/sp HEAD
sparse_patterns lecture | git -C "$T/SPW" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 && git -C "$T/SPW" checkout -q 2>/dev/null
{ [ ! -e "$T/SPW/design/teams/v65" ] && [ -f "$T/SPW/design/teams/lecture/indices/진행/c.md" ] && [ -f "$T/SPW/design/teams/lecture/evidence/e" ] && [ -f "$T/SPW/README" ] && [ -f "$T/SPW/code/f" ] && [ -f "$T/SPW/design/x.md" ]; } \
  && ok "ⓖ sparse: 남의 팀(v65) design 없음 · 자기 팀 indices·증거·루트·코드 있음" || bad "ⓖ $(cd "$T/SPW" && find . -type f -not -path './.git' | sort | tr '\n' ' ')"
mkdir -p "$T/SPW/design/teams/lecture/evidence/n" && echo n > "$T/SPW/design/teams/lecture/evidence/n/f" && git -C "$T/SPW" add design/teams/lecture/evidence/n/f 2>/dev/null \
  && ok "ⓖ 자기 팀 새 증거 파일 git add 가능" || bad "ⓖ 자기 팀 새 증거 add 막힘"
grep -q 'sparse-checkout set --no-cone --stdin' "$B/ft-nano-spawn.sh" && grep -q 'worktree add --no-checkout' "$B/ft-nano-spawn.sh" && ok "ⓖ spawn 배선(--no-checkout → sparse set → checkout)" || bad "ⓖ spawn 배선 없음"

# ⓗ spawn 여유 검사 블록 — 38Gi(<40) → WARN 1줄 + 진행(r1078: REJECT 아님) / 측정 실패 → REJECT / 50Gi 통과
BLK="$(awk '/^# r1078: r444 ⑤ 디스크 여유 검사/{f=1} f{print} f&&/^fi$/{exit}' "$B/ft-nano-spawn.sh")"
run_blk() { OUT="$( WTDIR="$T/none" ROOT="$R" FT_DISK_FREE_GIB="$1" bash -c "$BLK"$'\n''echo PASSED' 2>&1)"; RC=$?; }
run_blk 38; { [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'WARN 디스크 여유 38Gi < 40Gi' && printf '%s' "$OUT" | grep -q PASSED && ! printf '%s' "$OUT" | grep -q REJECT; } && ok "ⓗ 여유 38Gi → WARN 1줄 + 진행(PASSED)" || bad "ⓗ 38 rc=$RC [$OUT]"
run_blk fail; [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '측정 실패' && ok "ⓗ 측정 실패 → REJECT(여유 미상 ≠ 충분)" || bad "ⓗ fail rc=$RC [$OUT]"
run_blk 50; printf '%s' "$OUT" | grep -q PASSED && ok "ⓗ 여유 50Gi → 통과" || bad "ⓗ 50 [$OUT]"

# ⓘ nano-close ⑥ — 옛 글자 경로(design/lecture/indices/대기)에 남은 사본보다 팀 폴더(design/teams/lecture/indices/진행) 카드를 먼저
mkdir -p "$R/design/lecture/indices/대기"; echo stale > "$R/design/lecture/indices/대기/l6b.md"; echo real > "$R/design/teams/lecture/indices/진행/l6b.md"
BLK6="$(awk '/^# r444 ⑥/{f=1} f{print} f&&/^fi$/{exit}' "$B/ft-nano-close.sh")"
OUT="$(cd "$R" && IDX="design/lecture/indices/대기/l6b.md" WT="$R" ROOT="$R" LEDGER_WT="$R" CARD="" bash -c ". '$B/ft-team-lib.sh'; $BLK6"$'\n''echo "CARD=$CARD"' 2>&1)"
printf '%s' "$OUT" | grep -qx "CARD=$R/design/teams/lecture/indices/진행/l6b.md" && ok "ⓘ ⑥ 카드 = design/teams/lecture/indices/진행 (옛 대기 사본 아님)" || bad "ⓘ [$OUT]"

# ⓙ 600/300 0 · 외부 호출 0 — 새 파일 전체 + 바뀐 파일의 «추가 줄»
NEWF="$B/ft-finished-check.sh $B/ft-branch-archive.sh $HERE/../kit/launchd/com.byz.ft-wt-sweep.plist.template"
MB="$(git -C "$HERE" merge-base "${FT_TEST_BASE:-origin/main}" HEAD 2>/dev/null)"
ADDED="$( [ -n "$MB" ] && git -C "$HERE/.." diff "$MB" -- bin/ft-wt-sweep.sh bin/ft-scratch-repo.sh bin/ft-nano-spawn.sh bin/ft-nano-close.sh bin/ft-index-move.sh | grep '^+' | grep -v '^+++')"
h6="$( { cat $NEWF; printf '%s\n' "$ADDED"; } | grep -nE "\b($((6*100))|$((3*100)))\b|curl |https?://[a-z]" | grep -v 'apple.com/DTDs' )"
{ [ -n "$MB" ] && [ -z "$h6" ]; } && ok "ⓙ 600/300 숫자 0 · 외부 호출 0(새 파일 + 추가 줄)" || bad "ⓙ mb=${MB:-없음} $h6"

# ⓚ 공백 든 분리 HEAD 폴더 — update-ref 실패 → 폴더·ref 그대로 + SKIP update-ref-failed · 성공 = 이름 `_` 치환
printf '#!/bin/sh\necho "FINISHED $1"\n' > "$T/fin-stub"; chmod 755 "$T/fin-stub"
git -C "$R" worktree add -q --detach "$T/tester14-repro 6e47" "$MAIN"; git -C "$R" worktree add -q --detach "$T/a b" "$S2"
git -C "$R" update-ref "refs/archive/detached/tester14-repro_6e47" "$S2"   # 다른 sha 로 이미 있음 → 새로 만들기(update-ref <ref> <sha> "") 실패
OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$T/fin-stub" bash "$B/ft-branch-archive.sh" "$T/tester14-repro 6e47" --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 1 ] && [ -d "$T/tester14-repro 6e47" ] && [ "$(git -C "$R" rev-parse refs/archive/detached/tester14-repro_6e47)" = "$S2" ] && grep -q 'SKIP .*update-ref-failed' "$R/.fable-team/state/branch-archive.log"; } \
  && ok "ⓚ update-ref 실패 → 폴더 제거 0 · 있던 보관 ref 덮기 0 · 로그 SKIP update-ref-failed" || bad "ⓚ fail rc=$RC [$OUT]"
OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$T/fin-stub" bash "$B/ft-branch-archive.sh" "$T/a b" --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(git -C "$R" rev-parse refs/archive/detached/a_b)" = "$S2" ] && [ -d "$T/a b" ]; } && ok "ⓚ 성공 = refs/archive/detached/a_b (공백 → _) · 폴더는 그대로" || bad "ⓚ ok rc=$RC [$OUT]"

# ⓛ 껍데기 경보 — lecture 팀 폴더 → [HIL] 수신자 = lecture master · 팀 미상 → harness master
for n in lec-shell odd-shell; do git -C "$R" worktree add -q --detach "$R/.worktrees/$n" "$MAIN"; rm -f "$R/.worktrees/$n/README" "$R/.worktrees/$n/a.txt"; done
echo .worktree-info.json >> "$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)/info/exclude"   # r832: 실 리포처럼 무시(안 하면 미커밋 1 → SKIP)
printf '{"branch":"nano/x","purpose":"nano · design/teams/lecture/indices/진행/x.md"}\n' > "$R/.worktrees/lec-shell/.worktree-info.json"
: > "$T/mbox.log"; rm -f "$WC/.shell-sig"; sweep_ld
{ printf '%s' "$OUT" | grep -q '^\[HIL\] seat=byz-lecture-wt-shell .*lec-shell' && printf '%s' "$OUT" | grep -q '^\[HIL\] seat=byz-harness-wt-shell .*odd-shell' \
  && grep -q '^send byz-lecture-master-claude#2 ft-wt-sweep \[HIL\]' "$T/mbox.log" && grep -q '^send byz-harness-master-claude#76 ft-wt-sweep \[HIL\]' "$T/mbox.log" \
  && ! grep -q '^send byz-v65-master' "$T/mbox.log"; } && ok "ⓛ 껍데기 경보: lecture 폴더 → lecture master · 팀 미상 → harness master · v65 로 0" || bad "ⓛ out=${OUT:0:400} mbox=$(cat "$T/mbox.log")"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
