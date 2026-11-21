#!/usr/bin/env bash
# test_mbox_followup_absent_done_r2378.sh — r2378: 후속 깨움 정리가 «세션 없는 좌석»의 기록을 예약·ring 전에 done/ 으로 닫는다
#  K1 세션 없음 = 닫기(① ② ③) · K2 판정 불가 = 지금 길(④ ⑤) · K3 옮김(⑥ ⑦) · K4 산 좌석·확장 좌석 그대로(⑧ ⑨ ⑩ ⑪) · K5 send 결과 줄(⑫)
#  변이 M1~M9 = 사본 한 곳만 바꿔 같은 사례가 FAIL 하는지(원본 대조 = 같은 사례를 변이 없이 한 번 더 돌린다 · 카드 «원본으로 같은 사례 1회 더»).
#  격리: 임시 박스(comm 사본·state·seats·mailbox.jsonl) · 임시 HOME(확장 파일 = ⑪ 에서만) · fakebin tmux(목록 꼴 `이름|%pane`·rc·send-keys 기록) ·
#        fake ps(본체) · peek 스텁(호출 수) · holder 스텁(rc 1 · 나머지는 진짜 mbox.py) · mv 스텁(rc 1, ⑥ 한정) · 실 우편함·실 pane·실 좌석 0.
#  기준판 Red = R2378_SRC=<기준판 comm 폴더> R2378_EXPECT=red R2378_CASES="1 2 12" 로 돌린다(하나라도 PASS 면 Red 아님).
#  R2378_CASES = 돌릴 시험 번호(기본 1~12) · R2378_BASE_WAKEGATE = ⑫ 에서 기준판 초를 같은 실행에서 함께 잴 때 그 파일.
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd -- "$HERE/../.." && pwd)"
SRC="${R2378_SRC:-$REPO/harness/comm}"
T="$(mktemp -d "${TMPDIR:-/tmp}/r2378.XXXXXX")"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
CASES="${R2378_CASES:-1 2 3 4 5 6 7 8 9 10 11 12}"; want() { case " $CASES " in *" $1 "*) return 0;; esac; return 1; }
npass=0; nfail=0; ok() { npass=$((npass + 1)); echo "PASS $1"; }; bad() { nfail=$((nfail + 1)); echo "FAIL $1${2:+ :: $2}"; }
NOW=1790000000; stamp() { date -r "$1" +%Y%m%dT%H%M%S 2>/dev/null || date -d "@$1" +%Y%m%dT%H%M%S; }

# ── 스텁 — tmux(목록 꼴 `이름|%pane` · rc · send-keys 기록 · 접두어 has-session) · ps(본체) · peek(호출 수) · holder(rc) · mv(rc 1) ──
mkdir -p "$T/bin" "$T/badmv"
cat > "$T/bin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  list-panes) if [ "${2:-}" = "-a" ]; then [ "${TMUX_RC:-0}" = 0 ] || exit "${TMUX_RC}"; i=0
                for s in ${TMUX_SESS:-}; do i=$((i+1)); printf '%s|%%%d\n' "$s" "$i"; done; exit 0; fi
              printf '%s\n' "${TMUX_PANE_PID:-900001}"; exit 0;;
  display-message) printf '%s\n' "${TMUX_FG:-node}"; exit 0;;
  send-keys|show-environment) exit 0;;
  has-session) s="${@: -1}"; for x in ${TMUX_SESS:-}; do case "$x" in "$s"*) exit 0;; esac; done; exit 1;;
esac
exit 1
EOF
printf '#!/bin/sh\nprintf "%%s\\n" "900001     1 S    /bin/zsh" "900002 900001 S    /usr/bin/claude --dangerously-skip-permissions"\n' > "$T/bin/ps"
printf '#!/bin/sh\necho "peek $1" >> "${PEEK_LOG:-/dev/null}"\nprintf "pending=%%s\\n" "${PEEK_N:-1}"\nexit 0\n' > "$T/bin/peek"
printf '#!/bin/sh\nexit 1\n' > "$T/badmv/mv"
chmod +x "$T/bin/tmux" "$T/bin/ps" "$T/bin/peek" "$T/badmv/mv"
cat > "$T/bin/mbox-py-stub" <<'EOF'
import os, sys
a = sys.argv[1:]
if a[:1] == ["holder"]:
    with open(os.environ.get("HOLDER_LOG", "/dev/null"), "a", encoding="utf-8") as f:
        f.write("holder %s\n" % (a[1] if len(a) > 1 else ""))
    sys.exit(int(os.environ.get("HOLDER_RC", "1")))
os.execv(sys.executable, [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "mbox.py.real")] + a)
EOF

new_box() {  # <이름> [변이] — 사본 박스 하나. HOME 까지 격리한다(확장 좌석 판정 = 실 HOME 손 0).
  BOX="$T/box-$1"; C="$BOX/.fable-team/comm"; SD="$BOX/.fable-team/state"
  rm -rf "$BOX"; mkdir -p "$C" "$SD/doorbell-held" "$BOX/seats" "$BOX/tmp" "$BOX/home"
  cp "$SRC"/mbox*.sh "$SRC"/mbox*.py "$SRC"/ft-agent-alive.sh "$C/"
  printf '{"other#1": {"agent": "claude"}, "self#1": {"agent": "claude"}}\n' > "$BOX/seats/seats.json"
  printf '{}\n' > "$BOX/seats/seats-planner.json"; : > "$C/mailbox.jsonl"
  for f in tmux peek holder; do : > "$BOX/$f.log"; done; : > "$BOX/err"
  export HOME="$BOX/home" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$SD" FT_SEATS_JSON="$BOX/seats/seats.json" \
         TMPDIR="$BOX/tmp" TMUX_LOG="$BOX/tmux.log" PEEK_LOG="$BOX/peek.log" HOLDER_LOG="$BOX/holder.log" \
         FT_MBOX_PEEK_CMD="$T/bin/peek" FT_MBOX_WAKE_SEAT_MAX=1000 FT_MBOX_WAKE_TEAM_MAX=1000
  unset FT_MBOX_WAKE_LOCK_TRIES PEEK_N HOLDER_RC TMUX_RC TMUX_FG FT_MBOX_WAKE_FOLLOWUP_SEC FT_MBOX_QUIET_MAX_SEC
  [ -z "${2:-}" ] || { mutate "$2" && : > "$BOX/.mutated"; }
}
rep() { python3 - "$C/mbox_wakegate.sh" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit("변이 대상이 1곳이 아님(%d) — %r" % (s.count(old), old[:60]))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
K1H='    if [ "$uw" = 0 ]; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat"; then fu='
K1Q='    if [ "$uw" = 0 ]; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat" quiet; then printf'
mutate() {  # 사본에서만 · 한 번에 한 곳
  case "$1" in
    M1) rep "$K1H" '    if false; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat"; then fu=';;                                   # held 판정 지움
    M2) rep "$K1Q" '    if false; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat" quiet; then printf';;                          # quiet 판정을 peek 뒤로
    M3) rep '_wg_session_has() { local s; while IFS= read -r s; do [ "${s%%|*}" = "$1" ] && return 0; done <<<"$_WG_SESS"; return 1; }' \
            '_wg_session_has() { tmux has-session -t "$1" 2>/dev/null; }';;                            # 접두어 대조
    M4) rep 'if [ "$rc" != 0 ]; then echo "판정 불가 tmux 목록 실패 — 기록 유지" >&2; _WG_SOK=0; return 1; fi' ':';;  # 목록 rc 안 봄
    M5) rep '_wg_seat_absent() { local h; h="$(_wg_holder_rc "$1")" || return 2;' '_wg_seat_absent() { local h; h="$1";';;  # holder rc 안 봄
    M6) rep '        continue                                                           # mv 실패도' '        :                                                           # mv 실패도';;  # mv 실패 뒤 지금 길
    M7) rep '  while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$d/$base-$n"; n=$((n + 1)); done
  if mv "$f" "$dest" 2>/dev/null && [ ! -e "$f" ] && [ -e "$dest" ]; then return 0; fi' \
            '  if mv -f "$f" "$dest" 2>/dev/null && [ ! -e "$f" ] && [ -e "$dest" ]; then return 0; fi';;  # 빈 이름 찾기 지움
    M8) rep '_wg_seat_absent() { local h; h="$(_wg_holder_rc "$1")" || return 2;' '_wg_seat_absent() { local h; h="$1";';;  # holder 건너뜀
    M9) rep "$K1H" '    if true; then
      _wg_list_once || true
      if [ "$_WG_SOK" = 1 ] && _wg_seat_absent "$seat"; then
        if _wg_close_record "$f" "$seat"; then fu=';;                                    # K1 을 nudge 갈래 앞에
    *) echo "FAIL 알 수 없는 변이 $1" >&2; return 1;;
  esac
}
run() {  # <mbox.sh 하위명령…> — 가짜 시계·스텁 PATH
  OUT="$(FT_MBOX_NOW="$NOW" PATH="$T/bin:$PATH" FT_PS_CMD="$T/bin/ps" bash "$C/mbox.sh" "$@" 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
}
ck() { [ "$2" = "$3" ] || { echo "    $1: 기대 '$3' 실제 '$2'"; r=1; }; }
ckin() { case "$2" in *"$3"*) ;; *) echo "    $1: '$3' 없음 :: $(printf '%s' "$2" | head -c 150)"; r=1;; esac; }
held() { printf 'held ts=%s reason=held window=1 seat=%s\nseq=1\n' "$2" "$1" > "$SD/doorbell-held/$1"; }
quiet() { mkdir -p "$SD/doorbell-quiet"; printf 'quiet ts=%s seat=%s last=0\n' "$2" "$1" > "$SD/doorbell-quiet/$1"; }
done_ls() { ls "$SD/doorbell-held/done" 2>/dev/null | tr '\n' ' '; }
budget_ls() { ls "$SD/wake-budget" 2>/dev/null | tr '\n' ' '; }
tsec() { python3 -c 'import time;print(time.time())'; }
fsec() { python3 -c "print('%.2f' % ($2 - $1))"; }
holder_sec() {  # ⑫ 몫 — holder 를 기록 수만큼 부르는 초(python3 1회/기록)
  local t0 t1 s; t0="$(tsec)"; for s in dead#a dead#b dead#c dead#d dead#e dead#f; do python3 "$C/mbox.py" holder "$s" >/dev/null 2>&1; done
  t1="$(tsec)"; fsec "$t0" "$t1"; }

case_1() { r=0; new_box c1 "${MUT:-}"; held dead#5 $((NOW - 600)); export TMUX_SESS=""
  run sweep; ck "rc" "$RC" 0; ck "원 자리" "$([ -f "$SD/doorbell-held/dead#5" ] && echo 남음)" ""
  ck "done 1개" "$(done_ls)" "dead#5-$(stamp "$NOW") "; ck "예약 0" "$(budget_ls)" ""
  ck "ring(send-keys) 0" "$(grep -c send-keys "$BOX/tmux.log")" 0; ck "peek 0" "$(grep -c . "$BOX/peek.log")" 0
  ckin "닫힘 구" "$OUT" "closed=dead#5 via=absent"; return $r; }
case_2() { r=0; new_box c2 "${MUT:-}"; quiet dead#6 $((NOW - 3600)); export TMUX_SESS=""
  run sweep; ck "rc" "$RC" 0; ck "원 자리" "$([ -f "$SD/doorbell-quiet/dead#6" ] && echo 남음)" ""
  ck "done = quiet 이름" "$(done_ls)" "dead#6-quiet-$(stamp "$NOW") "; ck "peek 0(닫기가 peek 앞)" "$(grep -c . "$BOX/peek.log")" 0
  ck "예약 0" "$(budget_ls)" ""; return $r; }
case_3() { r=0; new_box c3 "${MUT:-}"; held 'X#5' $((NOW - 600)); held 'X#52' $((NOW - 600))     # 5 는 52 의 접두어
  export TMUX_SESS="X#52" TMUX_FG=node; run sweep; ck "X#5 원 자리" "$([ -f "$SD/doorbell-held/X#5" ] && echo 남음)" ""
  ck "X#5 닫힘" "$(done_ls)" 'X#5-'"$(stamp "$NOW") "; ck "X#52 done/ 으로 안 감" "$(done_ls | grep -c 'X#52')" 0
  ck "X#52 는 지금 길(ring 주입 1회)" "$(grep -c 'send-keys -t %1 -l' "$BOX/tmux.log")" 1; return $r; }
case_4() { r=0; new_box c4 "${MUT:-}"; held dead#1 $((NOW - 600)); held dead#2 $((NOW - 600)); export TMUX_SESS="" TMUX_RC=1
  run sweep; ck "rc 0(비치명)" "$RC" 0; ck "기록 그대로" "$(ls "$SD/doorbell-held" | tr '\n' ' ')" "dead#1 dead#2 "
  ck "done 비었음" "$(done_ls)" ""; ck "지금 길(예약 함)" "$([ -n "$(budget_ls)" ] && echo 있음)" "있음"
  ck "stderr 1줄" "$(printf '%s' "$ERR" | grep -c '판정 불가 tmux 목록 실패')" 1
  ck "tmux 목록 호출 1회" "$(grep -c -- 'list-panes -a -F #{session_name}$' "$BOX/tmux.log")" 1; return $r; }
case_5() { r=0; new_box c5 "${MUT:-}"; held dead#7 $((NOW - 600)); export TMUX_SESS="" HOLDER_RC=1
  cp "$C/mbox.py" "$C/mbox.py.real"; cp "$T/bin/mbox-py-stub" "$C/mbox.py"
  run sweep; ck "rc 0" "$RC" 0; ck "기록 그대로" "$([ -f "$SD/doorbell-held/dead#7" ] && echo 있음)" "있음"; ck "done 비었음" "$(done_ls)" ""
  ck "stderr 1줄" "$(printf '%s' "$ERR" | grep -c '판정 불가 holder 실패')" 1; ck "holder 불렀다" "$([ "$(grep -c holder "$BOX/holder.log")" -ge 1 ] && echo 있음)" "있음"; return $r; }
case_6() { r=0; new_box c6 "${MUT:-}"; held dead#8 $((NOW - 600)); export TMUX_SESS=""
  PATH_SAVE="$PATH"; PATH="$T/badmv:$PATH"; run sweep; PATH="$PATH_SAVE"
  ck "sweep rc 0" "$RC" 0; ck "기록 그대로" "$([ -f "$SD/doorbell-held/dead#8" ] && echo 있음)" "있음"
  ck "stderr WARN 1줄" "$(printf '%s' "$ERR" | grep -c 'WARN 깨움 기록 닫기 실패')" 1
  ck "peek 0" "$(grep -c . "$BOX/peek.log")" 0; ck "예약 0" "$(budget_ls)" ""; ck "ring 0" "$(grep -c send-keys "$BOX/tmux.log")" 0; return $r; }
case_7() { r=0; new_box c7 "${MUT:-}"; held dead#9 $((NOW - 600)); export TMUX_SESS=""
  mkdir -p "$SD/doorbell-held/done"; printf 'old' > "$SD/doorbell-held/done/dead#9-$(stamp "$NOW")"
  run sweep; ck "앞 파일 내용 그대로" "$(cat "$SD/doorbell-held/done/dead#9-$(stamp "$NOW")" 2>/dev/null)" old
  ck "새 기록 = -1" "$(cat "$SD/doorbell-held/done/dead#9-$(stamp "$NOW")-1" 2>/dev/null)" "held ts=$((NOW - 600)) reason=held window=1 seat=dead#9
seq=1"
  ck "원 자리" "$([ -f "$SD/doorbell-held/dead#9" ] && echo 남음)" ""; return $r; }
case_8() { r=0; new_box c8 "${MUT:-}"; held live#1 $((NOW - 600)); export TMUX_SESS="live#1" TMUX_FG=node
  run sweep; ck "기록 지움(ring sent)" "$([ -f "$SD/doorbell-held/live#1" ] && echo 남음)" ""; ck "done 0" "$(done_ls)" ""
  ck "doorbell 주입 1회" "$(grep -c 'send-keys -t %1 -l' "$BOX/tmux.log")" 1
  ck "장부 followup 1줄" "$(grep -c 'seat=live#1 src=followup' "$SD/wake-budget/_ledger.log" 2>/dev/null)" 1; ckin "구" "$OUT" "followup=live#1"; return $r; }
case_9() { r=0; new_box c9 "${MUT:-}"; held live#2 $((NOW - 600)); export TMUX_SESS="live#2" TMUX_FG=zsh
  run sweep; ck "기록 보존(noagent)" "$([ -f "$SD/doorbell-held/live#2" ] && echo 있음)" "있음"
  ck "last_err=noagent 1줄" "$(grep -c '^last_err=noagent' "$SD/doorbell-held/live#2")" 1
  ck "환불 n=0" "$(sed -n 's/.*"n": *\([0-9]*\).*/\1/p' "$SD/wake-budget/live#2.json" 2>/dev/null)" 0
  ck "done 0" "$(done_ls)" ""; return $r; }
case_10() { r=0; new_box c10 "${MUT:-}"; held 'byz-held-pi#5' $((NOW - 600)); export TMUX_SESS="byz-held-pi#52" TMUX_FG=node
  printf '{"byz-held-pi#5": {"_replaced_by": "byz-held-pi#52"}, "byz-held-pi#52": {"agent": "claude"}}\n' > "$BOX/seats/seats-held.json"
  run sweep; ck "옮김 0(후계 산다)" "$(done_ls)" ""; ck "기록 지움(세션 있음 갈래)" "$([ -f "$SD/doorbell-held/byz-held-pi#5" ] && echo 남음)" ""
  ckin "후계 pane 으로 주입" "$(cat "$BOX/tmux.log")" "recv byz-held-pi#52"; return $r; }
case_11() { r=0; new_box c11 "${MUT:-}"; held ext#9 $((NOW - 600)); export TMUX_SESS=""
  mkdir -p "$HOME/.pi/agent/extensions"; : > "$HOME/.pi/agent/extensions/ft-mbox-wake.ts"
  printf '{"_master": "pl-master#1", "_desk": "ext#9"}\n' > "$BOX/seats/seats-planner.json"
  run sweep; ck "옮김 0" "$(done_ls)" ""; ck "기록 지움" "$([ -f "$SD/doorbell-held/ext#9" ] && echo 남음)" ""
  ck "nudge 1개" "$(ls "$SD/pi-wake" 2>/dev/null | tr '\n' ' ')" "ext#9.nudge "; return $r; }
case_12() { r=0; new_box c12 "${MUT:-}"; export TMUX_SESS="other#1" TMUX_FG=node; local s t0 t1 fixed_s base_s
  for s in dead#a dead#b dead#c; do held "$s" $((NOW - 600)); done
  for s in dead#d dead#e dead#f; do quiet "$s" $((NOW - 3600)); done
  t0="$(tsec)"; run send other#1 self#1 "[질문] r2378 ⑫"; t1="$(tsec)"
  ck "결과 줄 1줄" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 1; ckin "QUEUED" "$OUT" QUEUED; ckin "doorbell=" "$OUT" "doorbell="; ckin "gate=" "$OUT" "gate="
  ck "기록 6개 닫힘" "$(done_ls | wc -w | tr -d ' ')" 6
  ck "held 자리 비었음" "$(ls "$SD/doorbell-held" | grep -vc '^done$')" 0; ck "quiet 자리 비었음" "$(ls "$SD/doorbell-quiet" 2>/dev/null | wc -l | tr -d ' ')" 0
  fixed_s="$(fsec "$t0" "$t1")"; echo "    ⑫ 고친 판 ${fixed_s}s · holder 몫 $(holder_sec)s(6회 · 기록마다 python3 1회)"
  python3 -c "import sys;sys.exit(0 if $fixed_s <= 7 else 1)" || { echo "    ⑫ 7초 넘음 ${fixed_s}s"; r=1; }
  if [ -f "${R2378_BASE_WAKEGATE:-/nonexistent}" ]; then
    cp "$C/mbox_wakegate.sh" "$BOX/fixed.sh"; cp "$R2378_BASE_WAKEGATE" "$C/mbox_wakegate.sh"
    for s in base#a base#b base#c; do held "$s" $((NOW - 600)); done
    for s in base#d base#e base#f; do quiet "$s" $((NOW - 3600)); done
    t0="$(tsec)"; run send other#1 self#1 "[질문] r2378 ⑫ 기준판"; t1="$(tsec)"
    base_s="$(fsec "$t0" "$t1")"
    echo "    ⑫ 기준판 ${base_s}s · 남은 기록 held $(ls "$SD/doorbell-held" | grep -cE '^(base|dead)#')개 + quiet $(ls "$SD/doorbell-quiet" | grep -cE '^(base|dead)#')개 · last_err=absent $(cat "$SD/doorbell-held"/base#* 2>/dev/null | grep -c 'last_err=absent')줄 · 결과 줄 $(printf '%s\n' "$OUT" | wc -l | tr -d ' ')줄"
    cp "$BOX/fixed.sh" "$C/mbox_wakegate.sh"
  fi
  return $r; }

echo "=== r2378 반례 (SRC=$SRC)"
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do want "$n" || continue
  t0="$(date +%s)"; MUT=""; case_$n; rc=$?; t1="$(date +%s)"
  if [ "$rc" = 0 ]; then ok "반례 $n ($((t1 - t0))s)"; else bad "반례 $n ($((t1 - t0))s)"; fi
done
if [ "${R2378_EXPECT:-green}" != red ]; then
  echo "=== r2378 변이 (사본에서만 · 원본 대조 = 위 반례 실행)"
  for pair in 1:M1 2:M2 3:M3 4:M4 5:M5 6:M6 7:M7 10:M8 11:M9; do
    n="${pair%%:*}"; m="${pair##*:}"; want "$n" || continue
    t0="$(date +%s)"; MUT="$m"; case_$n; rc=$?; t1="$(date +%s)"
    [ -f "$T/box-c$n/.mutated" ] || { bad "변이 $m 적용 실패 ($((t1 - t0))s)"; continue; }
    if [ "$rc" != 0 ]; then ok "변이 $m → 반례 $n FAIL 확인 ($((t1 - t0))s)"; else bad "변이 $m 이 반례 $n 에 안 잡힘 ($((t1 - t0))s)"; fi
  done
fi
echo "---"
if [ "${R2378_EXPECT:-green}" = red ]; then
  if [ "$npass" = 0 ] && [ "$nfail" -gt 0 ]; then echo "ALL RED(기대대로 · FAIL $nfail)"; exit 0; fi
  echo "RED 아님 — PASS $npass"; exit 1
fi
[ "$nfail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $nfail"; exit 1; }
