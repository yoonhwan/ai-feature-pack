#!/usr/bin/env bash
# test_seat_reap_name_tree_r2317.sh — r2317: 승계(retire) 때 옛 좌석 틱이 «ppid 1 래퍼(bash -c) 아래 자식» 꼴이어도, argv 낱말에 옛 좌석 이름이 정확히 든 고아 나무를 옛 좌석 것으로 찾아 같은 reap 길에 올린다(④).
#   ① 래퍼(ppid 1) → 틱 → timeout ft-desk-tick <옛> → 손자 · --orphans-only --dry-run → 후보 4개 via=④(기준판 = 0 → Red)
#   ② 같은 나무 argv 가 새 좌석 이름 → 0  ③ ‹<옛>0› 부분 글자 → 0  ④ 나무 자손에 살아 있는 pane → 0 · why=root-pane
#   ⑤ 사슬 중간이 남의 FT_SEAT(보이는 것) → 0  ⑥ 나무 안 보호 exe(침묵) · 서비스 2종 → 지금처럼 거름(reap-skip 줄)
#   ⑦ --defer-press + press 진행 → ④ 후보도 미룸 파일 1줄씩 · 신호 0  ⑨ run-shell 꼴(pane 자손) → why=root-pane
#   ⑩ launchd 잡 뿌리 → why=root-protect · 가짜 launchctl rc 1 → rc 20 · 신호 0  ⑪ 뿌리+자손 10 → why=tree-large n=10
#   ⑫ ssh 꼴(sshd [priv] uid 0) · ⑬ iTermServer+login 꼴(login uid 0) → why=root-uid · ⑭ iTermServer 직접 셸(tty 있음) → why=root-tty
#   변이 M1~M10(사본에서 1곳만) — 변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조
#   입력 = 가짜 ps 표(FT_PS) · 가짜 tmux(PATH) · 가짜 lsof(FT_LSOF) · 가짜 launchctl(FT_LAUNCHCTL) · 신호 0 = --dry-run · 실 프로세스 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BIN="${R2317_REAP_DIR:-$HERE/../bin}"; BIN="$(cd "$BIN" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/r2317.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
U="$(id -u)"; SEAT="r2317t#219"; NEW="r2317t#220"; LS="Fri Nov 20 01:13:31 2026"
mkdir -p "$TMP/fake" "$TMP/defer" "$TMP/permit"
cat > "$TMP/fake/ps" <<'EOS'
#!/bin/bash
case " $* " in
  *" -axEww "*) awk -F'\t' '{n = split($1, a, " "); c = ""; for (i = 10; i <= n; i++) c = c (i > 10 ? " " : "") a[i]; printf "%s %s%s\n", a[1], c, ($2 == "" ? "" : " FT_SEAT=" $2)}' "$FPS";;
  *"pid=,tty="*) awk -F'\t' '{split($1, a, " "); printf "%s %s\n", a[1], ($3 == "" ? "??" : $3)}' "$FPS";;
  *) awk -F'\t' '{print $1}' "$FPS";;
esac
EOS
cat > "$TMP/fake/tmux" <<'EOS'
#!/bin/bash
[ "$1" = list-panes ] || exit 0
[ -s "$FTAB" ] && cat "$FTAB" || { echo "no server running on /tmp/tmux-501/none" >&2; exit 1; }
EOS
cat > "$TMP/fake/lsof" <<'EOS'
#!/bin/bash
case " $* " in
  *" -sTCP:LISTEN "*) [ -s "$FLIS" ] && { while read -r p; do [ -n "$p" ] && echo "p$p"; done < "$FLIS"; }; exit 0;;
  *) exit 1;;
esac
EOS
cat > "$TMP/fake/launchctl" <<'EOS'
#!/bin/bash
[ -f "$LFAIL" ] && { echo "launchctl: Could not find service" >&2; exit 1; }
printf 'PID\tStatus\tLabel\n'
[ -s "$LPIDS" ] && while read -r p; do case "$p" in ''|-) ;; *) printf '%s\t0\tcom.byz.r2317fake%s\n' "$p" "$p";; esac; done < "$LPIDS"
exit 0
EOS
chmod +x "$TMP/fake/"*
export PATH="$TMP/fake:$PATH" FT_PS="$TMP/fake/ps" FT_LSOF="$TMP/fake/lsof" FT_LAUNCHCTL="$TMP/fake/launchctl"
export FPS="$TMP/ps.txt" FTAB="$TMP/tmux.txt" FLIS="$TMP/listen.txt" LPIDS="$TMP/launchd.txt" LFAIL="$TMP/launchd.fail"
export FT_REAP_NOSIGNAL=1 FT_REAP_TERM_WAIT=0 FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permit" FT_BG_FINITE_LEDGER="$TMP/bg.tsv"
export FT_PRESS_PS_SNAPSHOT="$TMP/press.txt" FT_PRESS_RUNNER_RE="r2317press"
unset TMUX_PANE FT_SEATS_JSON
: > "$TMP/ps.txt"; : > "$TMP/tmux.txt"; : > "$TMP/listen.txt"; : > "$TMP/launchd.txt"; : > "$TMP/press.txt"; rm -f "$LFAIL" "$TMP"/defer/* 2>/dev/null
row() { printf '%s %s %s %s %s %s\t%s\t%s\n' "$1" "$2" "$1" "${6:-$U}" "$LS" "$3" "${4:-}" "${5:-}" >> "$FPS"; }   # row pid ppid cmd [env좌석] [tty] [uid]
tbl_reset() { : > "$FPS"; : > "$FTAB"; : > "$FLIS"; : > "$LPIDS"; : > "$TMP/press.txt"; rm -f "$LFAIL" "$TMP"/defer/* 2>/dev/null; }
pane() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$TMP" "$TMP" >> "$FTAB"; }                        # pane 세션 pane_pid cwd 세션경로
reap() { ( cd "$TMP" && bash "$BIN/ft-seat-reap.sh" "$SEAT" "$@" 2>&1 ); }
n() { grep -c "$1" <<< "$2"; }
tail1() { tail -1 <<< "$1" | sed "s/^reap $SEAT //"; }

case1() {  # ① 이름 나무 4개 — 래퍼 100 · 틱 101 · timeout 102 · 손자 103
  tbl_reset
  row 4291100 1 "/bin/bash -c sed 's/#218/#219/g' /tmp/desk218-tick.sh > /tmp/desk219-tick.sh && nohup bash /tmp/desk219-tick.sh &"
  row 4291101 4291100 "bash /tmp/desk219-tick.sh"
  row 4291102 4291101 "timeout 30 bash .fable-team/bin/ft-desk-tick.sh $SEAT"
  row 4291103 4291102 "bash .fable-team/bin/ft-mbox.sh ring $SEAT"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "① 후보 4개 via=④(--orphans-only · env·pane·cwd 안 보임)" "$(n '^reap-cand pid=429110[0-3] via=④ ' "$o")" 4
  chk "① 끝 줄 found=4" "$(tail1 "$o")" "found=4 dry-run rc=0"
}
case2() {  # ② argv 가 새 좌석 이름 → 옛 좌석 후보 0
  tbl_reset
  row 4291200 1 "/bin/bash -c nohup bash /tmp/tick.sh $NEW &"
  row 4291201 4291200 "timeout 30 bash .fable-team/bin/ft-desk-tick.sh $NEW"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "② 새 이름 나무 → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case3() {  # ③ 부분 글자(#2190) = 0
  tbl_reset
  row 4291300 1 "/bin/bash -c nohup bash /tmp/tick.sh ${SEAT}0 &"
  row 4291301 4291300 "timeout 30 bash .fable-team/bin/ft-desk-tick.sh ${SEAT}0"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "③ «${SEAT}0» 부분 글자 → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case4() {  # ④ 나무 자손에 살아 있는 pane → 0 · why=root-pane
  tbl_reset; pane "$NEW" 4291402
  row 4291400 1 "/bin/bash -c while :; do sleep 5; done"
  row 4291401 4291400 "bash /tmp/desk-tick.sh $SEAT"
  row 4291402 4291401 "zsh -i"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "④ pane 자손 → 후보 0 · root-pane 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4291400 why=root-pane ' "$o")" "0 1"
}
case5() {  # ⑤ 사슬 중간이 남의 FT_SEAT(보이는 env) → 0
  tbl_reset
  row 4291500 1 "/bin/bash -c while :; do sleep 5; done"
  row 4291501 4291500 "bash /tmp/desk-tick.sh $SEAT" "byz-other-team#7"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑤ 남의 FT_SEAT 사슬 → 후보 0 · root-* 줄 0" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=.* why=root-' "$o")" "0 0"
}
case6() {  # ⑥ 나무 안 보호 exe(침묵) · 서비스 2종 → 지금처럼 거름(reap-skip 줄)
  tbl_reset; echo 4291602 > "$FLIS"
  row 4291600 1 "/bin/bash -c while :; do sleep 5; done"
  row 4291601 4291600 "bash -c 'uvicorn app:app' $SEAT"
  row 4291602 4291600 "node /tmp/srv.js $SEAT"
  row 4291603 4291600 "python3 /tmp/keeper.py $SEAT"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑥ 나무 전체 거름 → 후보 0" "$(n '^reap-cand ' "$o")" 0
  chk "⑥ 서비스 2종 reap-skip(지금 그대로) · 보호 exe 침묵" "$(n '^reap-skip pid=4291601 why=service-cmd ' "$o") $(n '^reap-skip pid=4291602 why=service-listen ' "$o") $(n 'pid=4291603' "$o")" "1 1 0"
}
case7() {  # ⑦ --defer-press + press 진행 → ④ 후보도 미룸(신호 0)
  tbl_reset; echo "4291900 $U python3 /tmp/r2317press.py" > "$TMP/press.txt"
  row 4291700 1 "/bin/bash -c while :; do sleep 5; done"
  row 4291701 4291700 "timeout 30 bash .fable-team/bin/ft-desk-tick.sh $SEAT"
  local o; o="$(reap --orphans-only --defer-press)"   # 미룸 분기는 --dry-run 보다 앞이 아니다(dry 면 dry-run 줄) — 신호 0 = FT_REAP_NOSIGNAL
  chk "⑦ ④ 후보 2개 미룸 · 신호 0" "$(n '^reap-defer pid=429170[01] why=press-active ' "$o") $(n '^reap-kill ' "$o") $(wc -l < "$TMP/defer/$SEAT.jsonl" | tr -d ' ')" "2 0 2"
  chk "⑦ 끝 줄 deferred=2" "$(tail1 "$o")" "stopped=0 left=0 deferred=2 rc=0"
}
case9() {  # ⑨ run-shell 꼴 — 뿌리 tmux 서버 아래 pane 셸 → root-pane(④ 0 · pane 셸 후보 0)
  tbl_reset; pane "$NEW" 4291902; pane "$NEW" 4291903
  row 4291900 1 "tmux -L r2317 new-session -d -s $NEW"
  row 4291901 4291900 "sh -c 'nohup bash /tmp/desk-tick.sh $SEAT &'"
  row 4291902 4291900 "zsh -i"
  row 4291903 4291900 "bash -i"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑨ run-shell 꼴 → 후보 0 · why=root-pane 1줄(root-protect 0)" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4291900 why=root-pane ' "$o") $(n 'why=root-protect' "$o")" "0 1 0"
}
case10() {  # ⑩ launchd 잡 뿌리 → root-protect · 가짜 launchctl rc 1 → rc 20
  tbl_reset; echo 4291000 > "$TMP/launchd.txt"
  row 4291000 1 "bash /tmp/keeper-loop.sh"
  row 4291001 4291000 "bash .fable-team/bin/ft-mbox.sh ring $SEAT"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑩ launchd PID 칸 → 후보 0 · why=root-protect 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4291000 why=root-protect ' "$o")" "0 1"
  : > "$LFAIL"
  o="$(reap --orphans-only --dry-run)"; local rc=$?
  chk "⑩' 가짜 launchctl rc 1 → rc 20 · left=? · 신호 0" "$rc $(tail1 "$o") $(n '^reap-kill ' "$o")" "20 stopped=0 left=? rc=20 0"
}
case11() {  # ⑪ 뿌리+자손 10 → tree-large n=10
  tbl_reset
  row 4291800 1 "/bin/bash -c while :; do sleep 5; done"
  local i; for i in 1 2 3 4 5 6 7 8 9; do
    if [ "$i" = 5 ]; then row "$((4291800 + i))" 4291800 "bash .fable-team/bin/ft-mbox.sh ring $SEAT"
    else row "$((4291800 + i))" 4291800 "bash /tmp/w$i.sh"; fi
  done
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑪ 나무 10개 → 후보 0 · tree-large n=10 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4291800 why=tree-large n=10 ' "$o")" "0 1"
}
case12() {  # ⑫ ssh 꼴 — 사슬에 남 uid(sshd [priv]) → root-uid
  tbl_reset
  row 4292000 1 "sshd: yoonhwan [priv]" "" "" 0
  row 4292001 4292000 "sshd: yoonhwan"
  row 4292002 4292001 "-zsh" "" ttys005
  row 4292003 4292002 "tmux attach -t $SEAT" "" ttys005
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑫ ssh 꼴 → 후보 0 · root-uid 1줄(root-tty 0)" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4292000 why=root-uid ' "$o") $(n 'why=root-tty' "$o")" "0 1 0"
}
case13() {  # ⑬ iTermServer+login 꼴 — login(uid 0) → root-uid
  tbl_reset
  row 4292100 1 "iTermServer"
  row 4292101 4292100 "login" "" "" 0
  row 4292102 4292101 "-zsh" "" ttys006
  row 4292103 4292102 "tail -f /tmp/r2317.log $SEAT" "" ttys006
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑬ iTermServer+login 꼴 → 후보 0 · root-uid 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4292100 why=root-uid ' "$o")" "0 1"
}
case14() {  # ⑭ iTermServer 직접 셸 — uid 전부 나 · 제어 tty 있음 → root-tty
  tbl_reset
  row 4292200 1 "iTermServer"
  row 4292201 4292200 "-zsh" "" ttys007
  row 4292202 4292201 "tail -f /tmp/r2317.log $SEAT" "" ttys007
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑭ 사람 셸 나무(tty) → 후보 0 · root-tty 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4292200 why=root-tty ' "$o")" "0 1"
}
mutb() {  # mutb <이름> <옛 글자> <새 글자> — bin 통째 사본 + ft-seat-reap.sh 1곳만 치환
  local d="$TMP/mb/$1"; mkdir -p "$d"; cp -R "$BIN/." "$d"/
  python3 - "$d/ft-seat-reap.sh" "$2" "$3" <<'PY'
import sys
p, o, nw = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mutb: «{o[:60]}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, nw))
PY
}
xrun() { R2317_CASE="$1" R2317_REAP_DIR="$2" bash "$SELF" > "$TMP/x.out" 2>&1; }
mcheck() {  # mcheck <변이> <반례번호> <옛> <새> — 원본 PASS · 변이 FAIL 이면 ok
  local out_b="$TMP/x-base-$2.out" out_m="$TMP/x-m$1-$2.out"
  R2317_CASE="$2" R2317_REAP_DIR="$BIN" bash "$SELF" > "$out_b" 2>&1; local rb=$?
  if ! mutb "$1" "$3" "$4"; then bad "$1 사본 치환 실패"; return; fi
  R2317_CASE="$2" R2317_REAP_DIR="$TMP/mb/$1" bash "$SELF" > "$out_m" 2>&1; local rm=$?
  chk "$1 → 반례 $2 대조: 원본 PASS · 변이 FAIL" "$rb $rm" "0 1"
  [ "$rm" -eq 0 ] && grep '^FAIL' "$out_m" | head -2
}

if [ -n "${R2317_CASE:-}" ]; then
  case "$R2317_CASE" in
    1) case1;; 2) case2;; 3) case3;; 4) case4;; 5) case5;; 6) case6;; 7) case7;; 9) case9;; 10) case10;; 11) case11;;
    12) case12;; 13) case13;; 14) case14;;
    *) echo "FAIL 알 수 없는 사례 $R2317_CASE"; exit 1;;
  esac
  [ "$fail" -eq 0 ] && { echo "CASE $R2317_CASE PASS"; exit 0; }
  echo "CASE $R2317_CASE FAILED $fail"; exit 1
fi

T0=$SECONDS
bash -n "$BIN/ft-seat-reap.sh" && ok "bash -n ft-seat-reap.sh" || bad "bash -n ft-seat-reap.sh"
cmp -s "$BIN/ft-seat-reap.sh" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"
for c in 1 2 3 4 5 6 7 9 10 11 12 13 14; do
  echo "== ④ 사례 $c"
  R2317_CASE="$c" R2317_REAP_DIR="$BIN" bash "$SELF" 2>&1 | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=$((fail + 1))
done
BASE="${R2317_BASE:-}"
echo "== 기준판(옛 ft-seat-reap.sh) Red — ① 이 0 이어야 한다"
if [ -n "$BASE" ] && [ -f "$BASE" ]; then
  mkdir -p "$TMP/base"; cp -R "$BIN/." "$TMP/base"/; cp "$BASE" "$TMP/base/ft-seat-reap.sh"
  R2317_CASE=1 R2317_REAP_DIR="$TMP/base" bash "$SELF" > "$TMP/base.out" 2>&1
  grep -q '^PASS ① 후보 4개' "$TMP/base.out" && bad "기준판이 ① 을 통과(Red 아님)" || ok "기준판 ① Red(후보 0) — $(grep -m1 '^FAIL' "$TMP/base.out" | cut -c1-70)"
else bad "기준판 없음 — R2317_BASE=<옛 bin/ft-seat-reap.sh> 로 다시"; fi
echo "== 변이 M1~M10(사본 · 원본 대조)"
mcheck M1 1 'for pid, (v, lst, c) in sorted(four.items()):' 'for pid, (v, lst, c) in []:'
mcheck M2 3 'seat not in r[4].split()' 'seat not in r[4]'
mcheck M3 4 'if tree & pane_pids: skip[root] = ("root-pane", cmd); continue' 'if False: pass'
mcheck M4 5 'if any(q in anc or (t[q][5] is not None and t[q][5] != seat) for q in chain): continue' 'if any(q in anc for q in chain): continue'
mcheck M5 7 'if defer and cand and press():' 'if defer and {p: v for p, v in cand.items() if v[0] != "④"} and press():'
mcheck M6 10 'if os.path.basename((cmd.split() or [""])[0]) in PROTECT or root in launchd_pids(): skip[root] = ("root-protect", cmd); continue' 'if False: pass'
mcheck M7 9 'if tree & pane_pids: skip[root] = ("root-pane", cmd); continue' 'if False: pass'
mcheck M8 11 'if len(tree) > TREE_CAP: skip[root] = (f"tree-large n={len(tree)}", cmd); continue' 'if False: pass'
mcheck M9 12 'if any(t[q][2] != me for q in tree): skip[root] = ("root-uid", cmd); continue' 'if False: pass'
mcheck M10 14 'if any(tty[0].get(q, "??") not in ("?", "??") for q in tree): skip[root] = ("root-tty", cmd); continue' 'if False: pass'
Q=$((SECONDS - T0))
chk "시간 $Q 초 ≤ 70" "$([ "$Q" -le 70 ] && echo ok)" ok
echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS ($Q 초)"; exit 0; else echo "FAILED $fail"; exit 1; fi
