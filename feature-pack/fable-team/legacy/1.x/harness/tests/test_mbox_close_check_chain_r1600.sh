#!/usr/bin/env bash
# test_mbox_close_check_chain_r1600.sh — r1600 · 여러 번 승계된 옛 좌석의 close-check 이 [인계]·[레디] 를 «사슬 끝» 하나가 아니라
#  «[인계] 를 실제로 받은 직계 후계» 에서 찾는다(구 master #176~#181 이 다 마치고도 «[인계] 없음» 으로 막히던 자리).
#  ⓐ 사슬 A→B→C · 기계 [인계] A→B(항목 2) + B 의 [레디](#1·#2 받음) → close-check A = CLOSE-OK rc0 (변이 M1 «사슬 끝만» = 빨강)
#  ⓑ [인계] 0 → REJECT · 안내 줄 후계 = «직계 B»(C 아님) · 사슬 밖 같은 역할 키 좌석의 [레디] 는 세지 않는다
#  ⓒ 기존 승계 시험 rc 불변 — 기본 = 빠른 3종(r1116 · recipient_r1460 · ready_renamed_r1493) · R1600_SLOW=1 = 느린 2종(seat_handover · r939)
#  격리: 정본 comm 사본 + 가짜 명부(seats-zz.json) + 임시 우편함 · 실 명부·실 큐·실 tmux 0 · 고정 sleep 0 · 자기 재호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
M=byz-zz-master-pi#3
A=byz-zz-arch-pi#176; B=byz-zz-arch-pi#177; C=byz-zz-arch-pi#178   # 사슬 A→B→C (여러 번 승계)
OFF=byz-zz-arch-pi#190                                              # 사슬 밖 같은 역할 키 좌석

roster() {   # A→B→C 사슬 · OUT = 사슬 밖 현역
  python3 - "$ENVROOT/seats/seats-zz.json" "$M" "$A" "$B" "$C" "$OFF" <<'PY'
import json, sys
p, m, a, b, c, off = sys.argv[1:7]
json.dump({"_master": m, m: {"role": "master"}, a: {"role": "stop-ready", "_replaced_by": b},
           b: {"role": "stop-ready", "_replaced_by": c, "_replaces": [a]},
           c: {"role": "arch", "_replaces": [b]}, off: {"role": "arch", "_replaces": []}},
          open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수] — 격리 루트 하나(정본 사본 + 가짜 명부 + 빈 큐)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; CDIR="$ENVROOT/.fable-team/comm"; Q="$CDIR/mailbox.jsonl"
  mkdir -p "$CDIR" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$CDIR/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; roster; : > "$Q"
  [ -z "${1:-}" ] || "$1"
}
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$CDIR" FT_MBOX_STATE_DIR="$ENVROOT/.fable-team/state"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$CDIR/mbox.py"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$CDIR/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv timeout 20 python3 "$CDIR/mbox.py" "$@" 2>&1)"; RC=$?; }
hbody() { printf '[인계] %s -> %s · 항목 2 · [레디] 는 항목마다 «<id> 받음»(bash mbox.sh ready %s %s)\n답 안 한 오빠 질문: 0\n남은 회신·쪽지: 2\n- #1 [%s] q1 (전문: mailbox.log.jsonl seq 1)\n- #2 [%s] q2 (전문: mailbox.log.jsonl seq 2)' "$1" "$2" "$2" "$1" "$M" "$M"; }
rbdy() { printf '[레디] %s <- %s · [인계] #%s 받음 · 항목 2\n#1 받음\n%s' "$1" "$2" "$3" "$4"; }
mut_chain_end_only() {   # M1 — «사슬 끝만» 보던 지금 코드(ⓐ 가 빨강이어야 한다)
  python3 - "$CDIR/mbox_handover.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace("near, succ = chain or [succ], (chain or [succ])[0]", "near, succ = [succ], succ")
open(p, "w", encoding="utf-8").write(s)
PY
  grep -q 'near, succ = \[succ\], succ' "$CDIR/mbox_handover.py"; }
setup_handover() {   # setup_handover <old> <succ> — 옛 좌석이 후계에 [인계] 1통(HS = 그 seq)
  sh_ send "$2" "$1" "$(hbody "$1" "$2")" || return 1
  HS="$(printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1)"
  [ -n "$HS" ]
}

# ── ⓐ 사슬 A→B→C · [인계] A→B + B [레디] → close-check A = CLOSE-OK
t_a() {   # t_a [변이함수]
  new_env "${1:-}" || return 2; setup_handover "$A" "$B" || return 2
  sh_ send "$A" "$B" "$(rbdy "$B" "$A" "$HS" $'#2 받음')" || return 2
  py close-check "$A"
  [ "$RC" = 0 ] && case "$OUT" in CLOSE-OK*'항목 2 전부 받음'*) true;; *) false;; esac
}
t_a && ok "ⓐ 직계 후계 B [인계]·[레디] → CLOSE-OK rc0" || bad "ⓐ rc=$RC :: $OUT"
t_a mut_chain_end_only; [ $? = 1 ] && ok "M1 변이(사슬 끝만 보기) = 빨강(REJECT)" || bad "M1 변이가 안 잡힘 rc=$RC :: $OUT"

# ── ⓑ1 [인계] 0 → REJECT · 안내 줄 후계 = 직계 B(C 아님)
new_env; py close-check "$A"
[ "$RC" = 3 ] && case "$OUT" in *"[인계] 없음 — bash mbox.sh handover $A $B"*) true;; *) false;; esac \
  && ok "ⓑ1 [인계] 0 → REJECT rc3 · 안내 후계 = 직계 B" || bad "ⓑ1 rc=$RC :: $OUT"

# ── ⓑ2 사슬 밖 같은 역할 키 OUT 의 [레디] → 여전히 REJECT
new_env; setup_handover "$A" "$B" && sh_ send "$OFF" "$A" "$(rbdy "$OFF" "$A" "$HS" $'#2 받음')"
[ "$RC" = 0 ] && ok "ⓑ2 사슬 밖 [레디] 자체는 가드 통과(같은 역할 키)" || bad "ⓑ2 send rc=$RC :: $OUT"
py close-check "$A"
[ "$RC" = 3 ] && case "$OUT" in *'후계 [레디] 없음'*) true;; *) false;; esac \
  && ok "ⓑ2 사슬 밖 OFF [레디] → close-check REJECT" || bad "ⓑ2 rc=$RC :: $OUT"

# ── ⓒ 기존 승계 시험 rc 불변(baseline = origin/main 07c87aae 실측: 0/0/0/0/0 · seat_handover 만 1 「REAL-STATE-GUARD」)
if [ "${R1600_SLOW:-0}" = 1 ]; then REG=(test_seat_handover.sh test_seat_handover_r939.sh); else REG=(test_mbox_handover_r1116.sh test_mbox_handover_recipient_r1460.sh test_mbox_ready_renamed_succession_r1493.sh); fi
for f in "${REG[@]}"; do
  timeout 70 bash "$HERE/$f" > "$T/$f.log" 2>&1; rc=$?
  want=0; [ "$f" = test_seat_handover.sh ] && want=1
  [ "$rc" = "$want" ] && ok "ⓒ $f rc=$rc(불변)" || bad "ⓒ $f rc=$rc (기대 $want) :: $(tail -1 "$T/$f.log")"
done

# ── 문법
for f in "$SRC/mbox_handover.py" "$SRC/mbox_lineage.py"; do
  python3 -c 'import sys,py_compile;py_compile.compile(sys.argv[1],doraise=True)' "$f" >/dev/null 2>&1 \
    && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")"
done
bash -n "$SRC/mbox.sh" 2>/dev/null && ok "bash -n mbox.sh" || bad "bash -n mbox.sh"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
