#!/usr/bin/env bash
# test_tmux_option_target_r1742.sh — r1742: 좌석 닫기·승계의 tmux 옵션 명령 5줄이 `-t "=<좌석>:"` 로 실제 세션 옵션에 닿는다 (카드 반례 ① ② · 변이 M1 M2).
#   대역만: 실 꼴 가짜 tmux(옵션 명령 = `=<이름>:` 만 성공 · `=<이름>` = «no such session» rc1 · 세션 대상 명령은 둘 다 성공) · reap·close-check 스텁 · 임시 명부·장부. 실 tmux·좌석 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; trap 'rm -rf "$T0"' EXIT INT TERM
S="r1742s-$$#0"; OLD="r1742h-$$#2"; NEW="r1742h-$$#3"
mkdir -p "$TMP/wt" "$TMP/resume" "$TMP/cf" "$TMP/fake" "$TMP/root/.fable-team/state"; git -C "$TMP/wt" init -q
cat > "$TMP/fake/tmux" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$TMP/tmux.log"
sub="\$1"; shift; tgt=""; key=""; val=""; un=0
while [ \$# -gt 0 ]; do case "\$1" in -t) tgt="\$2"; shift 2;; -u) un=1; shift;; -*) shift;; @*) key="\$1"; val="\${2:-}"; shift \$#;; *) shift;; esac; done
case "\$sub" in
show-option|show-options|set-option)
  case "\$tgt" in =*:) ;; *) echo "no such session: \$tgt" >&2; exit 1;; esac
  f="$TMP/opt.\$(printf '%s' "\${tgt#=}" | tr -c 'A-Za-z0-9' _)\$key"
  if [ "\$sub" != set-option ]; then [ -f "\$f" ] && cat "\$f"; elif [ "\$un" = 1 ]; then rm -f "\$f"; else printf '%s\n' "\$val" > "\$f"; fi;;
has-session) [ -f "$TMP/killed" ] && exit 1;;
list-sessions) echo "${S%#*}#1"; echo "${S%#*}#2";;
display-message) echo 0;;
kill-session) : > "$TMP/killed";;
esac
exit 0
EOS
printf '#!/bin/sh\necho "reap left=0"\n' > "$TMP/reap.sh"; printf 'import sys\nsys.exit(0)\n' > "$TMP/mbox.py"; chmod +x "$TMP/fake/tmux" "$TMP/reap.sh"
export PATH="$TMP/fake:$PATH" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
c1() {  # c1 [bin 폴더] — 세션 옵션 @zc_v65_active=1 · CLOSED-SESSION 갈래
  rm -f "$TMP"/opt.* "$TMP/killed"; : > "$TMP/tmux.log"; tmux set-option -t "=$S:" @zc_v65_active 1; : > "$TMP/tmux.log"
  printf '{"_master": "M#1", "M#1": {"role": "master"}, "%s": {"role": "tester", "agent": "claude", "tick": null}}' "$S" > "$TMP/cf/seats.json"
  out="$(cd "$TMP/wt" && bash "${1:-$BIN}/ft-seat-close.sh" "$S" --reason "r1742 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?
  chk "① CLOSED-SESSION rc0 · set-option -t =<좌석>: -u @zc_v65_active 1회" "$rc $(grep -c "^CLOSED-SESSION $S" <<<"$out") $(grep -cxF "set-option -t =$S: -u @zc_v65_active" "$TMP/tmux.log")" "0 1 1"; }
c2() {  # c2 [bin 폴더] — handover 완료 → 옛 좌석 캐시 · status option= 칸
  local e="$TMP/err" o2; ho() { FT_ROOT="$TMP/root" FT_HANDOVER_LEDGER="$TMP/ledger.jsonl" FT_SEATS_JSON="$TMP/seats.json" bash "${D:-$BIN}/ft-seat-handover.sh" "$@"; }; D="${1:-$BIN}"
  rm -f "$TMP"/opt.* "$TMP/killed" "$TMP/ledger.jsonl"; : > "$TMP/tmux.log"; printf '{"_master": "%s"}' "$NEW" > "$TMP/seats.json"
  ho snapshot "$OLD" "$NEW" >/dev/null 2>&1; out="$(ho apply "$OLD" "$NEW" 2>"$e")"; rc=$?
  printf '{"_master": "%s"}' "${OLD%#*}#9" > "$TMP/seats.json"; o2="$(ho status "$OLD" 2>/dev/null)"   # 명부만 비켜 MISMATCH 갈래 = option= 칸이 보인다
  chk "② HANDOVER rc0 · set-option -t =<옛>: 1회 · WARN 0 · status option=<새>" "$rc $(grep -cxF "set-option -t =$OLD: @handed_over_to $NEW" "$TMP/tmux.log") $(grep -c '캐시 설정 실패' "$e") ${o2##* }" "0 1 0 option=$NEW"; }
echo "== 반례"; c1; c2
echo "== 변이(사본) — 원본 PASS 뒤 사본 FAIL 이면 PASS"
mut() {  # mut <이름> <파일> <옛> <새> <사례>
  local d="$TMP/mb/$1" f0="$fail"; mkdir -p "$d"; cp "$BIN"/* "$d"/ 2>/dev/null
  python3 -c 'import sys;p,o,n=sys.argv[1:4];s=open(p).read();assert s.count(o)==1,o;open(p,"w").write(s.replace(o,n))' "$d/$2" "$3" "$4" || { chk "$1 치환" x ok; return; }
  "$5" "$d" >/dev/null; local n=$((fail - f0)); fail="$f0"; chk "$1 → $5 FAIL" "$n" 1; }
mut M1 ft-seat-close.sh 'show-options -qv -t "=$SEAT:"' 'show-options -qv -t "=$SEAT"' c1
mut M2 ft-seat-handover.sh 'set-option -t "=$old:"' 'set-option -t "=$old"' c2
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
