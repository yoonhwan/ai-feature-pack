#!/usr/bin/env bash
# test_desk_tick_no_batch_r2269.sh — r2269: planner desk 로 가는 ft-desk-tick 틱 2종은 묶음 칸(wake_at) 없이 바로 깨운다.
#  ① [틱 N:N] → planner _desk(pi) 첫 통 = QUEUED · 큐 행 · 기록 행 wake_at 0 · batched.log 0줄
#  ② [aifp N분 점검 N:N] → 같은 결과
#  ③ ① 뒤 5분 [틱] = SKIPPED alert-policy(주기 15) · [aifp] 15분 뒤 = SKIPPED(주기 30)
#  ④ ft-stall-scan [멈춤] desk 틱 끊김 · ft-idle-scan [N분 점검 N:N] 첫 통 = wake_at T0+900(다른 묶음 행 그대로)
# 격리: 정본 comm 사본 + 가짜 명부(planner _master · _desk = pi) + 확장 파일 대역(HOME) + 임시 우편함 · state · tmux 스텁 · 실 우편함 0 · sleep 0.
# env: R2269_SRC = 다른 comm(기준판 Red · 변이) · R2269_CASES = "1 3" 처럼 일부만.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_MBOX_WAKE_AT; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="${R2269_SRC:-$REPO/harness/comm}"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3]) :: ${OUT:0:200} :: ${ERR:0:300}"; fi; }
want() { case " ${R2269_CASES:-1 2 3 4} " in *" $1 "*) return 0;; esac; return 1; }
mkdir -p "$T/stub"; printf 'import sys\nsys.exit(0)\n' > "$T/stub/desk_gate.py"
printf '#!/bin/sh\necho "$*" >> "$TMUX_LOG"\ncase "$1" in list-panes) exit 0;; *) exit 1;; esac\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
PM="byz-planner-master-pi#7"; PD="byz-planner-desk-pi#8"; T0=1763340000

new_env() {   # 격리 우편함 · state · TMPDIR · HOME(확장 파일 대역) · 명부 planner _master · _desk(agent pi)
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; Q="$C/mailbox.jsonl"; L="$C/mailbox.log.jsonl"; AP="$E/.fable-team/state/alert-policy"
  export TMUX_LOG="$E/tmux.log"; mkdir -p "$C" "$E/.fable-team/state" "$E/seats" "$E/tmp" "$E/home/.pi/agent/extensions"
  : > "$E/home/.pi/agent/extensions/ft-mbox-wake.ts"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; cp "$SRC"/alert-policy.tsv "$C/" 2>/dev/null
  printf '{}\n' > "$E/seats/seats.json"; : > "$Q"; : > "$TMUX_LOG"
  printf '{"_master": "%s", "_desk": "%s", "%s": {"role": "master", "agent": "pi"}, "%s": {"role": "desk", "agent": "pi"}}\n' \
    "$PM" "$PD" "$PM" "$PD" > "$E/seats/seats-planner.json"
}
sh_() { OUT="$(cd "$E" && ( unset FT_ALERT_POLICY
  env -u FT_PLANNER_HEAD_MODE -u FT_MBOX_STATE_DIR -u FT_BIN PATH="$T/stub:$PATH" TMPDIR="$E/tmp" HOME="$E/home" FT_SEATS_JSON="$E/seats/seats.json" \
  FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_MBOX_RESEND_COOLDOWN=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" \
  FT_MBOX_PY="$C/mbox.py" FT_BIN="$BIN" FT_DESK_GATE="$T/stub/desk_gate.py" FT_MBOX_NOW="${NOW:-$T0}" bash "$C/mbox.sh" send "$@" ) 2>"$E/err")"
  RC=$?; ERR="$(cat "$E/err")"; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
# rowf <파일> <seq> — 그 seq 행의 wake_at · 칸 없음 = «-» · 행 없음 = none
rowf() { python3 - "$1" "$2" <<'PY'
import json, sys
rows = [r for r in (json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()) if str(r.get("seq")) == sys.argv[2]]
print(rows[-1].get("wake_at", "-") if rows else "none")
PY
}
seq_out() { printf '%s\n' "$OUT" | sed -n 's/.*QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
# w <기대 wake_at | -> <이름> <sh_ 인자…> — QUEUED · rc 0 · 그 seq 큐 행 wake_at
w() { local x="$1" n="$2"; shift 2; : > "$Q"; sh_ "$@"
  case "$OUT" in *QUEUED*) ;; *) bad "$n → QUEUED 아님 rc=$RC :: ${OUT:0:200} :: ${ERR:0:300}"; return;; esac
  chk "$n → wake_at=$x" "$RC $(rowf "$Q" "$(seq_out)")" "0 $x"; }
TK() { printf '[틱 %s] 5분 정기 프로그레스 — ft-desk-tick.sh 1회' "$1"; }
AI() { printf '[aifp 15분 점검 %s] aifp master Working · 미읽음 0' "$1"; }

for c in 1 2; do want $c || continue; new_env
  if [ $c = 1 ]; then n="① [틱]"; b="$(TK 10:57)"; else n="② [aifp]"; b="$(AI 10:57)"; fi
  NOW=$T0 w - "$n 첫 통 → planner _desk(pi)" "$PD" ft-desk-tick "$b"
  chk "$n 기록 행(mailbox.log.jsonl)에도 wake_at 0" "$(rowf "$L" "$(seq_out)")" -
  chk "$n batched.log 0줄" "$(lines "$AP/batched.log")" 0
done
if want 3; then new_env
  NOW=$T0 sh_ "$PD" ft-desk-tick "$(TK 10:57)"; chk "③ [틱] 첫 통 → QUEUED" "${OUT%% *}" QUEUED
  NOW=$((T0+300)) sh_ "$PD" ft-desk-tick "$(TK 11:02)"
  chk "③ [틱] 5분 뒤 → SKIPPED alert-policy(주기 15)" "${OUT%%갈래=*}" "SKIPPED alert-policy "
  NOW=$T0 sh_ "$PD" ft-desk-tick "$(AI 10:57)"; chk "③ [aifp] 첫 통 → QUEUED" "${OUT%% *}" QUEUED
  NOW=$((T0+900)) sh_ "$PD" ft-desk-tick "$(AI 11:12)"
  chk "③ [aifp] 15분 뒤 → SKIPPED alert-policy(주기 30)" "${OUT%%갈래=*}" "SKIPPED alert-policy "
fi
if want 4; then new_env
  NOW=$T0 w $((T0+900)) "④ ft-stall-scan [멈춤] desk 틱 끊김" "$PM" ft-stall-scan "[멈춤] $PD · desk 틱 끊김 · 마지막 [완료] desk 틱 10:35 · 22분째"
  C5='[5분 점검 10:55] 작업 7 · 10분↑ 유휴 3 · 시간 모름 1
닫기 대상 0
할 일: 닫기 대상 줄 먼저'
  NOW=$T0 w $((T0+900)) "④ ft-idle-scan [N분 점검 N:N] 첫 통(바뀐 통)" "$PM" ft-idle-scan "$C5"
  chk "④ batched.log 2줄" "$(lines "$AP/batched.log")" 2
fi
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
[ "$fail" = 0 ]
