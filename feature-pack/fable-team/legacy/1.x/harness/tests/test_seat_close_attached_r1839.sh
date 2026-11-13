#!/usr/bin/env bash
# test_seat_close_attached_r1839.sh — r1839: 사람 화면이 붙은 세션은 kill 0 · reap 0 · HELD rc 3 (카드 반례 ① ② ③ ⑨ · 변이 M1 M2 M3 M7).
#   대역만: 가짜 tmux(PATH 앞 · 인자 기록 · `=이름:` 에만 attached 숫자 · `=이름` = rc0 빈 줄 = 실제 tmux 꼴) · reap 스텁 · 임시 명부. 실 tmux·명부 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT INT TERM
S="r1839s-$$#0"; mkdir -p "$TMP/wt" "$TMP/resume" "$TMP/cf" "$TMP/fake"; git -C "$TMP/wt" init -q
cat > "$TMP/fake/tmux" <<EOS
#!/bin/sh
echo "\$*" >> "$TMP/tmux.log"
case "\$1" in
has-session) [ -f "$TMP/killed" ] && exit 1;;
list-sessions) echo "${S%#*}#1"; echo "${S%#*}#2";;
display-message) case "\$*" in *"-t =$S: "*) cat "$TMP/att"; exit "\$(cat "$TMP/attrc")";; *) echo; exit 0;; esac;;
kill-session) : > "$TMP/killed";;
esac
exit 0
EOS
printf '#!/bin/sh\necho reap >> "%s/reap.log"\necho "reap left=0"\n' "$TMP" > "$TMP/reap.sh"; chmod +x "$TMP/fake/tmux"
printf 'print("CLOSE-OK stub")\n' > "$TMP/mbox.py"
export PATH="$TMP/fake:$PATH" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
run() {  # run <attached 출력> <rc> [bin 폴더] → out rc kills reaps tgt
  rm -f "$TMP/killed" "$TMP/tmux.log" "$TMP/reap.log"; printf '%s\n' "$1" > "$TMP/att"; echo "$2" > "$TMP/attrc"
  printf '{"_master": "M#1", "M#1": {"role": "master"}, "%s": {"role": "tester", "agent": "claude", "tick": null}}' "$S" > "$TMP/cf/seats.json"
  out="$(cd "$TMP/wt" && bash "${3:-$BIN}/ft-seat-close.sh" "$S" --reason "r1839 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?
  kills="$(grep -c '^kill-session' "$TMP/tmux.log")"; reaps="$(cat "$TMP/reap.log" 2>/dev/null | wc -l | tr -d ' ')"
  tgt="$(grep '^display-message.*session_attached' "$TMP/tmux.log" | awk '{print $4}')"; }
c1() { run 1 0 "$@"; chk "① attached=1 → rc3 · kill 0 · reap 0 · HELD 사람 화면" "$rc $kills $reaps $(grep -c "^HELD $S 사람 화면 attached=1" <<<"$out")" "3 0 0 1"; }
c2() { run "" 1 "$@"; chk "② display-message rc1 → rc3 · kill 0 · reap 0 · 판정 불가" "$rc $kills $reaps $(grep -c "^HELD $S 판정 불가 attached" <<<"$out")" "3 0 0 1"; }
c3() { run 0 0 "$@"; chk "③ attached=0 → reap → kill 1 → CLOSED-SESSION rc0 · ⑨ 대상 =<세션>:" "$rc $kills $reaps $(grep -c "^CLOSED-SESSION $S" <<<"$out") $tgt" "0 1 2 1 =$S:"; }
echo "== 반례"; c1; c2; c3
echo "== 변이(사본) — 잡히면 PASS"
mut() {  # mut <이름> <옛> <새> <사례>
  local d="$TMP/mb/$1" f0="$fail"; mkdir -p "$d"; cp "$BIN"/* "$d"/ 2>/dev/null
  python3 -c 'import sys;p,o,n=sys.argv[1:4];s=open(p).read();assert s.count(o)==1,o;open(p,"w").write(s.replace(o,n))' "$d/ft-seat-close.sh" "$2" "$3" || { chk "$1 치환" x ok; return; }
  "$4" "$d" >/dev/null; local n=$((fail - f0)); fail="$f0"; chk "$1 → $4 FAIL" "$n" 1; }
mut M1 '  ATT="$(seat_attached)"; case' '  reap; ATT="$(seat_attached)"; case' c1
mut M2 'else echo "unknown rc=$r' 'else echo free; : "' c2
mut M3 '[ "$o" -ge 1 ]' '[ "$o" -gt 1 ]' c1
mut M7 '-t "=$SEAT:" '"'"'#{session_attached}'"'" '-t "=$SEAT" '"'"'#{session_attached}'"'" c3
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
