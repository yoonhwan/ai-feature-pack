#!/usr/bin/env bash
# test_mbox_ready_auto_close_r1653.sh — r1653 단계 2 [feature]: `mbox.sh ready` 성공 + FT_READY_AUTO_CLOSE=1 = 같은 실행에서 옛 좌석 ft-seat-close 1회.
#  ★기본값 = 끔(0)★ — env 는 좌석 셸마다 따로라 설치로 «끈 채» 를 보장 못 한다(planner #283594 · master #283652) · 켜기 = 1.
#  ① FT_READY_AUTO_CLOSE=1 + ready 성공 → 가짜 ft-seat-close 인자 = 옛 좌석·--reason «승계 레디 #<레디 seq> → <후계>» · AUTO-CLOSE rc=0 · ready rc0
#  ② ready-body REJECT(후계가 [인계] recv 전) → ft-seat-close 호출 0 · ready rc3
#  ③ 가짜 rc3(kill=held) → «AUTO-CLOSE <옛> rc=3» + «다음: master 판단(h)» · ready rc0(닫기 결과로 rc 를 안 바꾼다)
#  ④ 미설정(기본 0) → 호출 0  ⑤ =0 명시 → 호출 0   (①③ 은 =1 로 켜서 본다)
#  변이 M3 ready 의 자동 닫기 갈래 무효화(if false) → ① FAIL
#  격리: 정본 comm 사본 + seats-union.json + 임시 우편함 + 가짜 ft-seat-close(인자·rc 만 기록) · 실 명부·실 큐·실 tmux·실 좌석 닫기 0 · 고정 sleep 0 · 자기 재호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && { echo "h62 3"; exit 0; }\nexit 2\n' > "$T/stub/ft-hil.sh"
LOG="$T/close-args.log"; : > "$LOG"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit "${FAKE_CLOSE_RC:-0}"\n' "$LOG" > "$T/stub/ft-seat-close.sh"
O=byz-union-old-pi#1; N=byz-union-new-pi#2

roster() {   # roster <retired 0|1>
  python3 - "$ENVROOT/seats/seats-union.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
d = {"_master": n if r else o, o: {"role": "master"}, n: {"role": "master"}}
if r: d[o] = {"role": "stop-ready", "_replaced_by": n}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; printf '{}\n' > "$ENVROOT/seats/seats.json"; roster 0; : > "$Q"; : > "$LOG"
  [ -z "${1:-}" ] || "$1"
}
row() { printf '{"seq": %s, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-union.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$ENVROOT/.fable-team/state"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh"
  export FT_SEAT_CLOSE_BIN="$T/stub/ft-seat-close.sh"
  "$@" ); }
sh_() { OUT="$(cd "$ENVROOT" && xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
seqof() { printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
mut_m3() {   # M3 — ready 의 자동 닫기 갈래 무효화(= 줄 삭제와 같은 효과 · 자리 확인까지)
  python3 - "$C/mbox.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'if [ "$_rc" = 0 ] && [ "${FT_READY_AUTO_CLOSE:-0}" = 1 ]'
assert old in s, "M3 자리 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, 'if false && [ "$_rc" = 0 ]', 1))
PY
  grep -q 'if false && \[ "\$_rc" = 0 \]' "$C/mbox.sh"; }
setup() {   # setup — 옛 [인계] 1통 · retire · 후계 recv 까지(HS = [인계] seq)
  row 1 "$O" "[HIL] q1"; sh_ recv "$O"; sh_ handover "$O" "$N"; HS="$(seqof)"; [ -n "$HS" ] || return 1
  roster 1; sh_ recv "$N"
}

# ① ready 성공 → ft-seat-close 1회(옛 좌석 · --reason «승계 레디 #<seq> → 후계») · AUTO-CLOSE rc=0 · ready rc0
chk_1() {
  new_env "${1:-}" || return 2; setup || return 2
  FT_READY_AUTO_CLOSE=1 sh_ ready "$N" "$O"; [ "$RC" = 0 ] || return 1
  RS="$(printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1)"
  [ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] || return 1
  grep -qx -- "$O --reason 승계 레디 #$RS → $N" "$LOG" || return 1
  case "$OUT" in *"AUTO-CLOSE $O rc=0"*) ;; *) return 1;; esac
}
chk_1 mut_m3 && bad "M3 변이(자동 닫기 갈래 무효화)가 ① 에 안 잡힘" || ok "M3 변이(자동 닫기 무효화) → ① FAIL 확인"
chk_1 && ok "① ready 성공 → ft-seat-close 1회(옛 좌석·--reason) · AUTO-CLOSE rc=0 · ready rc0" || bad "① rc=$RC :: $OUT :: log=$(cat "$LOG")"

# ② ready-body REJECT(후계 recv 전) → ft-seat-close 호출 0 · ready rc3
new_env; row 1 "$O" "[HIL] q1"; sh_ recv "$O"; sh_ handover "$O" "$N"; HS="$(seqof)"; roster 1   # recv N 안 함
sh_ ready "$N" "$O"
[ "$RC" = 3 ] && case "$OUT" in *'아직 recv 안 함'*) true;; *) false;; esac && [ ! -s "$LOG" ] \
  && ok "② ready-body REJECT → ft-seat-close 호출 0 · ready rc3" || bad "② rc=$RC :: $OUT :: log=$(cat "$LOG")"

# ③ 가짜 rc3(kill=held) → «AUTO-CLOSE ... rc=3» + «다음: master 판단(h)» · ready rc0
new_env; setup; FT_READY_AUTO_CLOSE=1 FAKE_CLOSE_RC=3 sh_ ready "$N" "$O"
[ "$RC" = 0 ] && case "$OUT" in *"AUTO-CLOSE $O rc=3"*'다음: master 판단(h)'*) true;; *) false;; esac \
  && [ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] && ok "③ kill=held rc3 → AUTO-CLOSE rc=3 · «다음: master 판단(h)» · ready rc0" || bad "③ rc=$RC :: $OUT"

# ④ 미설정(기본값) = 끔 → 호출 0 · ready rc0 (설치가 «끈 채» 를 보장하는 자리)
new_env; setup; sh_ ready "$N" "$O"
[ "$RC" = 0 ] && [ ! -s "$LOG" ] && case "$OUT" in *AUTO-CLOSE*) false;; *) true;; esac \
  && ok "④ FT_READY_AUTO_CLOSE 미설정(기본 0) → ft-seat-close 호출 0 · ready rc0" || bad "④ rc=$RC :: $OUT :: log=$(cat "$LOG")"

# ⑤ FT_READY_AUTO_CLOSE=0 명시 → 호출 0 · ready rc0
new_env; setup; FT_READY_AUTO_CLOSE=0 sh_ ready "$N" "$O"
[ "$RC" = 0 ] && [ ! -s "$LOG" ] && case "$OUT" in *AUTO-CLOSE*) false;; *) true;; esac \
  && ok "⑤ FT_READY_AUTO_CLOSE=0 → ft-seat-close 호출 0 · ready rc0" || bad "⑤ rc=$RC :: $OUT :: log=$(cat "$LOG")"

for f in "$SRC/mbox.sh"; do bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"; done
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
