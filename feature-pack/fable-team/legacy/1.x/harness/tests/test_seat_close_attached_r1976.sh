#!/usr/bin/env bash
# test_seat_close_attached_r1976.sh — r1976: 사람 화면 attached N 이어도 NOTE 1줄 뒤 닫는다 · 판정 불가 HELD · 승계 마무리 전 REJECT 그대로 (카드 반례 ① ③ ⑤ · 변이 M1 M2).
#   대역만(r1839 꼴): 가짜 tmux(`=이름:` 에만 attached 숫자) · reap 스텁 · close-check 스텁 · 임시 명부. 실 tmux·명부 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT INT TERM
S="r1976s-$$#0"; mkdir -p "$TMP/wt" "$TMP/resume" "$TMP/cf" "$TMP/fake"; git -C "$TMP/wt" init -q
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
printf '#!/bin/sh\necho "reap left=0"\n' > "$TMP/reap.sh"; chmod +x "$TMP/fake/tmux" "$TMP/reap.sh"
export PATH="$TMP/fake:$PATH" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
run() {  # run <attached 출력> <rc> <close-check rc> [bin 폴더] → out rc kills
  rm -f "$TMP/killed"; : > "$TMP/tmux.log"; printf '%s\n' "$1" > "$TMP/att"; echo "$2" > "$TMP/attrc"
  printf 'import sys\nprint("close-check stub")\nsys.exit(%s)\n' "$3" > "$TMP/mbox.py"
  printf '{"_master": "M#1", "M#1": {"role": "master"}, "%s": {"role": "tester", "agent": "claude", "tick": null}}' "$S" > "$TMP/cf/seats.json"
  out="$(cd "$TMP/wt" && bash "${4:-$BIN}/ft-seat-close.sh" "$S" --reason "r1976 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?
  kills="$(grep -c '^kill-session' "$TMP/tmux.log")"; }
c1() { run 1 0 0 "$@"; chk "① 승계 끝 · attached=1 → NOTE 1줄 → kill 1 → CLOSED-SESSION rc0" "$rc $kills $(grep -c "^NOTE $S 사람 화면 attached=1 — 오빠 지시로 닫음$" <<<"$out") $(grep -c "^CLOSED-SESSION $S" <<<"$out")" "0 1 1 1"; }
c3() { run "" 1 0 "$@"; chk "③ attached 읽기 실패 → HELD 판정 불가 rc3 · kill 0 · NOTE 0" "$rc $kills $(grep -c "^HELD $S 판정 불가 attached" <<<"$out") $(grep -c '^NOTE' <<<"$out")" "3 0 1 0"; }
c5() { run 1 0 1 "$@"; chk "⑤ attached=1 · 승계 [레디] 없음(close-check rc1) → REJECT rc1 · kill 0" "$rc $kills $(grep -c "^REJECT $S 승계 마무리 전" <<<"$out")" "1 0 1"; }
echo "== 반례"; c1; c3; c5
echo "== 변이(사본) — 잡히면 PASS"
mut() {  # mut <이름> <옛> <새> <사례>
  local d="$TMP/mb/$1" f0="$fail"; mkdir -p "$d"; cp "$BIN"/* "$d"/ 2>/dev/null
  python3 -c 'import sys;p,o,n=sys.argv[1:4];s=open(p).read();assert s.count(o)==1,o;open(p,"w").write(s.replace(o,n))' "$d/ft-seat-close.sh" "$2" "$3" || { chk "$1 치환" x ok; return; }
  "$4" "$d" >/dev/null; local n=$((fail - f0)); fail="$f0"; chk "$1 → $4 FAIL" "$n" 1; }
mut M1 'attached*) echo "NOTE $SEAT' 'attached*) finish 3 "HELD $SEAT' c1
mut M2 '*) finish 3 "HELD $SEAT 판정 불가 attached' '*) echo "HELD $SEAT 판정 불가 attached' c3
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
