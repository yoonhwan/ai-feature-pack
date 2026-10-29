#!/usr/bin/env bash
# test_seat_quiesce_r1113.sh — ft-seat-quiesce.sh 반례 R1~R8·R13 + 고아 + 호출 줄 4 + kit 짝 + 변이 2 (r1113 · 판정 2769·2770)
#   가짜 나무 = lib/r1113_fake_tree.sh(sleep 스텁 · 가짜 tmux·launchctl · ps 필터 = 띄운 pid 만) · 실 tmux·LSP·크롬·launchd 0 · 자기 재호출 0
#   변이: ⓜ1 KILL 단계 제거 → R2 FAIL · ⓜ2 이름 집합 비움 → R6 FAIL (임시 사본) · 시험 대상 = Q_SCRIPT(기본 리포 bin)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
Q="${Q_SCRIPT:-$BIN/ft-seat-quiesce.sh}"
TMP="$(mktemp -d)"; . "$HERE/lib/r1113_fake_tree.sh"; fake_init; trap fake_cleanup EXIT
pass=0; fail=0; T0=$(date +%s)
ck() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; sed 's/^/    | /' "$TMP/last" 2>/dev/null | tail -6; fail=$((fail+1)); fi; }
q() { local s="$1"; shift; bash "$s" "$@" > "$TMP/last" 2>&1; echo $? > "$TMP/rc"; }
rc_is() { [ "$(cat "$TMP/rc")" = "$1" ]; }
has() { grep -qF -- "$1" "$TMP/last"; }
dead() { local p; for p in "$@"; do ! alive "$p" || return 1; done; }
live() { local p; for p in "$@"; do alive "$p" || return 1; done; }

r1() { local s="$1" t="R1$2"; tree "$t" 0 node zsh basedpyright tsserver pi uvx; rss "$(pid_of "$t" basedpyright)" 900; rss "$(pid_of "$t" tsserver)" 1100
  q "$s" "$t" --mode close; rc_is 0 && has "kill=0 left=0" && has "남은 자식 0" && dead $(grep -v ' root$' "$TMP/tree-$t.pids" | cut -d' ' -f1) && live "$(pid_of "$t" root)"; }
r2() { local s="$1" t="R2$2"; tree "$t" 0 trap:tsserver node
  q "$s" "$t" --mode close; rc_is 0 && has "term=2 kill=1 left=0" && has "남은 자식 0" && dead "$(pid_of "$t" tsserver)"; }
r3() { local t=R3 p; tree "$t" 0 basedpyright; p="$(pid_of "$t" basedpyright)"
  FT_QUIESCE_NOSIGNAL="$p" q "$Q" "$t" --mode close; rc_is 1 && has "left=1" && has "남은 자식 1 $p basedpyright" && live "$p"; }
r4() { local t=R4; tree "$t" 0 basedpyright zsh "Google Chrome --remote-debugging-port=9333" "Google Chrome" git; rss "$(pid_of "$t" "Google Chrome")" 400; rss "$(pid_of "$t" git)" 300
  q "$Q" "$t" --mode done; rc_is 0 && has "남은 대상 0" && dead "$(pid_of "$t" basedpyright)" "$(pid_of "$t" "Google Chrome")" \
    && live "$(pid_of "$t" "Google Chrome --remote-debugging-port=9333")" "$(pid_of "$t" zsh)" "$(pid_of "$t" git)" "$(pid_of "$t" root)"; }
r5() { local t=R5; tree "$t" 0 basedpyright; echo '{"held": true}' > "$TMP/permits/device.json"
  q "$Q" "$t" --mode done; rm -f "$TMP/permits/device.json"; rc_is 0 && has "why=press-active" && has "term=0" && live "$(pid_of "$t" basedpyright)"; }
r6() { local s="$1" t="R6$2"; tree "$t" 0 lsp-daemon; rss "$(pid_of "$t" lsp-daemon)" 112
  q "$s" "$t" --mode done; rc_is 0 && has "term=1" && dead "$(pid_of "$t" lsp-daemon)"; }
r7() { local t=R7 k n; tree "$t" 0 crew-kid; k="$(pid_of "$t" crew-kid)"; echo "$k" >> "$TMP/launchd"
  bash -c 'exec -a "next dev" sleep 300' & n=$!; echo "$n" >> "$TMP/pids"; rss "$n" 600; sleep 0.3
  q "$Q" "$t" --mode close; rc_is 0 && has "quiesce-keep pid=$k why=launchd" && has "term=0" && live "$k" "$n"; }
r8() { local p; tree R8old 0 basedpyright; tree R8new 0; p="$(pid_of R8old basedpyright)"
  q "$Q" R8old --mode handover --to R8new; rc_is 0 && has "HANDOVER R8old -> R8new rows=1" && [ "$(cut -f1,5 "$TMP/state/handover/R8new.tsv")" = "$p	R8old" ] && live "$p" || return 1
  q "$Q" R8new --mode done; rc_is 0 && has "term=1" && dead "$p" && [ ! -e "$TMP/state/handover/R8new.tsv" ]; }
r13() { local t=R13 p; tree "$t" 0 basedpyright; p="$(pid_of "$t" basedpyright)"; printf 'echo boom >&2; exit 3\n' > "$TMP/fake/ps-bad"
  FT_PS="$TMP/fake/ps-bad" q "$Q" "$t" --mode close; rc_is 20 && has "QUIESCE-UNKNOWN R13 판정 불가" && [ "$(wc -l < "$TMP/last" | tr -d ' ')" = 1 ] && live "$p"; }
orph() { local a b; orphan basedpyright; a="$(cat "$TMP/orphan.pid")"; orphan tsserver; b="$(cat "$TMP/orphan.pid")"; echo "$b" >> "$TMP/launchd"
  q "$Q" --orphans; rc_is 0 && has "quiesce-keep pid=$b why=launchd" && dead "$a" && live "$b"; }
survey() { tree SV 7 basedpyright; rss "$(pid_of SV basedpyright)" 300
  q "$Q" --survey; rc_is 0 && grep -qE "^S	SV	7	300	300	1	" "$TMP/last" && grep -qE "^P	SV	$(pid_of SV basedpyright)	basedpyright	300	" "$TMP/last" && live "$(pid_of SV basedpyright)"; }
wiring() {
  grep -q '_seat_quiesce; return \$?' "$BIN/ft-nano-close.sh" && grep -q 'ft-seat-quiesce.sh}" "\$SEAT" --mode close' "$BIN/ft-nano-close.sh" \
  && grep -q -- '"\$OLD" --mode handover --to "\$NEW"' "$BIN/ft-seat-retire.sh" && grep -q 'ft-child-watch.sh' "$BIN/ft-stall-scan.sh" \
  && grep -q '\[ "\${FT_SEAT:-}" != "\$from" \].*--mode done' "$BIN/../comm/mbox.sh"; }
kit() { local f; for f in ft-seat-quiesce.sh ft-child-watch.sh ft-nano-close.sh ft-seat-retire.sh ft-stall-scan.sh; do cmp -s "$BIN/$f" "$KIT/$f" || { echo "kit 다름 $f" > "$TMP/last"; return 1; }; done; }

bash -n "$Q" || { echo "FAIL bash -n $Q"; exit 1; }
ck "R1 close 전부 TERM · 남은 자식 0 · kill=0 · 에이전트 본체 생존" r1 "$Q" ""
ck "R2 close TERM 무시 → KILL · kill=1 · 남은 자식 0" r2 "$Q" ""
ck "R3 close KILL 뒤 남음 → rc 1 · 남은 자식 1 <pid> <이름>" r3
ck "R4 done 무거운 것만(basedpyright·다른 크롬) · 9333·zsh·git 300MB·에이전트 생존" r4
ck "R5 done press 진행 → 건너뜀 · term=0" r5
ck "R6 done 이름 집합 lsp-daemon 112MB → 내림" r6 "$Q" ""
ck "R7 나무 밖 next dev 0 · launchd pid kill 0 + keep 줄" r7
ck "R8 handover kill 0 · 표 1행 · 후계 done 이 내림 · 표 정리" r8
ck "R13 ps 실패 → 판정 불가 1줄 rc 20 · 신호 0" r13
ck "고아 ppid1 basedpyright 내림 · launchd 고아 보호" orph
ck "조회 표 S·P 줄 · 신호 0" survey
ck "호출 줄 4(nano-close·seat-retire·stall-scan·mbox)" wiring
ck "kit 짝 cmp0 (5파일)" kit
T1=$(date +%s)
sed 's/sig(p, signal.SIGKILL)/pass/' "$Q" > "$TMP/m1.sh"; sed 's/^HEAVY_NAME = {/HEAVY_NAME = set() and {/' "$Q" > "$TMP/m2.sh"
ck "ⓜ1 KILL 제거 → R2 FAIL" eval '! r2 "$TMP/m1.sh" m'
ck "ⓜ2 이름 집합 비움 → R6 FAIL" eval '! r6 "$TMP/m2.sh" m'
echo "단계별 초: 본 시험 $((T1 - T0)) · 변이 $(( $(date +%s) - T1 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
