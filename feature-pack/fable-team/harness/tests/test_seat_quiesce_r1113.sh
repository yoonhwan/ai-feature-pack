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
# DA① 반례 5 (r1113 재작업 · 반례 집합 그대로 · 구현만 교체)
da1() { local s="$1" t="D1$2" c; tree "$t" 0 "node /x/@anthropic-ai/claude-code/cli.js" basedpyright; c="$(pid_of "$t" "node /x/@anthropic-ai/claude-code/cli.js")"; rss "$c" 400
  q "$s" "$t" --mode done; rc_is 0 && live "$c" && dead "$(pid_of "$t" basedpyright)"; }
da2() { local s="$1" t="D2$2" p; tree "$t" 0 basedpyright; p="$(pid_of "$t" basedpyright)"; echo 0 > "$TMP/reuse.n"
  printf 'n=$(cat "%s"); echo $((n+1)) > "%s"\ncase " $* " in *" -axww "*) [ "$n" -ge 1 ] && { bash "%s" "$@" | awk -v p=%s '"'"'$1==p {$7="Mon";$8="Jan";$9="1";$10="00:00:00";$11="2001"} {print}'"'"'; exit; };; esac\nexec bash "%s" "$@"\n' \
    "$TMP/reuse.n" "$TMP/reuse.n" "$TMP/fake/ps" "$p" "$TMP/fake/ps" > "$TMP/fake/ps-reuse"
  FT_PS="$TMP/fake/ps-reuse" q "$s" "$t" --mode done; rc_is 0 && live "$p"; }
da3() { local s="$1" t="D3$2" k; tree "$t" 0 spawner
  q "$s" "$t" --mode close; local ok=1
  rc_is 0 && has "new=1" && has "남은 자식 0" && [ -z "$(kid r1113-newkid | while read -r x; do alive "$x" && echo "$x"; done)" ] && ok=0
  kid r1113-newkid | xargs kill -9 2>/dev/null; return $ok; }   # 변이 칸이 남긴 새 자식이 다음 칸의 «새로 생긴 고아» 로 섞이지 않게
mids() { /bin/ps -axo pid=,command= | awk '/mid\.sh r1113-mid/ { print $1 }'; }
sweep_kids() { { kid r1113-newkid; mids; } | xargs kill -9 2>/dev/null; return 0; }   # 칸이 남긴 새 자식·손자가 다음 칸에 섞이지 않게
da3g() { local s="$1" t="D3g$2" ok=1; tree "$t" 0 spawner2   # DA② 반례 3 — TERM 중 자식(mid) → 그 자식도 TERM 중 손자(newkid)
  q "$s" "$t" --mode close
  rc_is 0 && has "new=2" && has "round=2" && has "남은 자식 0" && [ -z "$( { kid r1113-newkid; mids; } | while read -r x; do alive "$x" && echo "$x"; done)" ] && ok=0
  sweep_kids; return $ok; }
da3lim() { local t=D3lim ok=1; tree "$t" 0 spawner2   # 상한 1회 → 손자는 «남은 것» · rc 1
  FT_QUIESCE_RESCAN_MAX=1 q "$Q" "$t" --mode close
  rc_is 1 && has "quiesce-rescan-limit 1" && has "left=1" && has "남은 자식 1" && ok=0
  sweep_kids; return $ok; }
da3_link() { local t=D3L p fns line; tree "$t" 0 basedpyright; p="$(pid_of "$t" basedpyright)"
  printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$TMP/fake/reap-ok"
  fns="$(awk '/^_seat_reap\(\) \{/,/^\}/; /^_seat_quiesce\(\) \{/,/^\}/' "$BIN/ft-nano-close.sh")"; line="$(grep -m1 '^_seat_reap || { echo "CLOSE-FAIL reap' "$BIN/ft-nano-close.sh" | tail -1)"
  FT_QUIESCE_NOSIGNAL="$p" FT_SEAT_REAP_BIN="$TMP/fake/reap-ok" FT_SEAT_QUIESCE_BIN="$Q" SEAT="$t" HERE="$BIN" bash -c "_wtarg=(); $fns
$line
echo NOT-FAILED" > "$TMP/last" 2>&1; echo $? > "$TMP/rc"
  rc_is 1 && has "CLOSE-FAIL reap left=1(자식) rc=1 — $t" && ! has NOT-FAILED; }
da4() { local s="$1" t="D4$2" pp c; tree "$t" 0 "nest:crew-parent:r1113-lchild"; pp="$(pid_of "$t" crew-parent)"; echo "$pp" >> "$TMP/launchd"; sleep 0.3; c="$(/bin/ps -axo pid=,ppid= | awk -v pp="$pp" '$2 == pp { print $1; exit }')"
  q "$s" "$t" --mode close; rc_is 0 && has "quiesce-keep pid=$pp why=launchd" && [ -n "$c" ] && live "$pp" "$c"; }
da5() { local s="$1" a="D5a$2" b="D5b$2" c="D5c$2" p; tree "$a" 0 basedpyright; tree "$b" 0; tree "$c" 0; p="$(pid_of "$a" basedpyright)"
  q "$s" "$a" --mode handover --to "$b" && q "$s" "$b" --mode handover --to "$c"; rc_is 0 && has "inherited=1" && [ ! -e "$TMP/state/handover/$b.tsv" ] && [ "$(cut -f1 "$TMP/state/handover/$c.tsv")" = "$p" ] && live "$p" || return 1
  q "$s" "$c" --mode close; rc_is 0 && has "term=1" && has "남은 자식 0" && dead "$p"; }
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
ck "DA①1 R4 node …/claude-code/cli.js 400MB = 본체 보호 · basedpyright 만 내림" da1 "$Q" ""
ck "DA①2 TERM 직전 시작 시각 대조 — pid 재사용(시작 시각 바뀜) → 신호 0" da2 "$Q" ""
ck "DA①3 R3 TERM 중 새 자식 → 재조회로 잡아 내림 · new=1 · 남은 자식 0" da3 "$Q" ""
ck "DA②3 R3 TERM 중 자식 → 그 자식이 또 손자 → 재조회 반복으로 둘 다 내림 · new=2 · 남은 자식 0" da3g "$Q" ""
ck "DA②3 R3 재조회 상한(1회) 넘으면 손자 = 남은 것 · rc 1" da3lim
ck "DA①3 R3 남은 자식≠0 → nano-close 의 CLOSE-FAIL 줄·rc 1 (실제 함수·호출 줄 추출)" da3_link
ck "DA①4 R7 launchd 등록 pid 와 그 밑 자식 전부 보호(kill 0)" da4 "$Q" ""
ck "DA①5 R8 A→B→C 재승계 = 표 이어받음 · C close 가 인계 pid 내림" da5 "$Q" ""
T1=$(date +%s)
sed 's/sig(p, signal.SIGKILL)/pass/' "$Q" > "$TMP/m1.sh"; sed 's/^HEAVY_NAME = {/HEAVY_NAME = set() and {/' "$Q" > "$TMP/m2.sh"
sed 's/^AGENT_CMD = re.compile(r"/AGENT_CMD = re.compile(r"(?!x)x" if 1 else r"/' "$Q" > "$TMP/m3.sh"
sed 's/        if same(now, cand, p): sig(p, signal.SIGTERM)/        sig(p, signal.SIGTERM)/' "$Q" > "$TMP/m4.sh"
sed 's/            new, keeps2 = guard(T2,/            new, keeps2 = ({}, []) if 1 else guard(T2,/' "$Q" > "$TMP/m5.sh"
sed 's/    keep = lp | desc(t, lp)/    keep = lp/' "$Q" > "$TMP/m6.sh"
sed 's/    if mode == "close": return tree | set(inh)/    if mode == "close": return tree/' "$Q" > "$TMP/m7.sh"
sed 's/        for rnd in range(RESCAN + 1):/        for rnd in range(1):/' "$Q" > "$TMP/m9.sh"
for m in 3 4 5 6 7 9; do cmp -s "$Q" "$TMP/m$m.sh" && echo "WARN 변이 m$m 이 원본과 같음(sed 불일치)"; done
ck "ⓜ1 KILL 제거 → R2 FAIL" eval '! r2 "$TMP/m1.sh" m'
ck "ⓜ2 이름 집합 비움 → R6 FAIL" eval '! r6 "$TMP/m2.sh" m'
ck "ⓜ3 런타임 꼴 본체 보호 제거 → DA①1 FAIL" eval '! da1 "$TMP/m3.sh" m'
ck "ⓜ4 TERM 직전 대조 제거 → DA①2 FAIL" eval '! da2 "$TMP/m4.sh" m'
ck "ⓜ5 종료 뒤 재조회 제거 → DA①3 FAIL" eval '! da3 "$TMP/m5.sh" m'
ck "ⓜ6 launchd 하위 나무 보호 제거 → DA①4 FAIL" eval '! da4 "$TMP/m6.sh" m'
ck "ⓜ7 close 의 인계 표 무시 → DA①5 FAIL" eval '! da5 "$TMP/m7.sh" m'
ck "ⓜ9 재조회 1회만(반복 제거) → DA②3 손자 칸 FAIL" eval '! da3g "$TMP/m9.sh" m'
echo "단계별 초: 본 시험 $((T1 - T0)) · 변이 $(( $(date +%s) - T1 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
