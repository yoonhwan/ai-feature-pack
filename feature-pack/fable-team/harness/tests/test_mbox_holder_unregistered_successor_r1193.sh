#!/usr/bin/env bash
# test_mbox_holder_unregistered_successor_r1193.sh — r1193 · Issue #5245: 명부에 없는(retire 전) 이름이 같은 역할 현역보다 번호가 크면
#   holder(doorbell·ring 대상) = 그 이름 자신. 실사건: chatbot arch#41→#42 승계 rc=5(첫 doorbell·RESEND ring 이 구 #41 창으로).
#  R1 #41 현역 · #42 행 없음 → holder(#42) = #42 · ring #42 = «RING …#42» · send #42 doorbell 이 #42 pane 으로
#  R2 holder(#41) = #41 · R3 #40 행 없음(옛 이름) → #41 · R4 #41 _replaced_by=#42 → #42 · R5 역할 이름(번호 없음) → #41
#  기준판 = 변이(번호 비교 줄 → «return top» = 고치기 전 줄) — R2~R5 값 같음 · R1 은 #41(FAIL 재현)
# 격리: 정본 comm 사본 + 가짜 명부 + 임시 우편함 + 가짜 tmux(send-keys 를 파일에) + ps 스냅샷 · 실 명부·실 큐·실 tmux 0 · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 재진입 표지 = RSG_ACTIVE(자식 1회)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
A=byz-zz-arch-claude; P40="$A#40"; P41="$A#41"; P42="$A#42"; M=byz-zz-master-claude#50
mkdir -p "$T/stub" "$T/tmp"
cat > "$T/stub/tmux" <<'EOS'
#!/bin/bash
case "$1" in
  list-panes) case "$*" in *'#{session_name}'*) for s in $FAKE_SESSIONS; do echo "$s"; done ;; *) echo 999990 ;; esac ;;
  display-message) echo claude ;;
  send-keys) [ "${4:-}" = -l ] && printf '%s|%s\n' "$3" "${5:-}" >> "$FAKE_TMUX_LOG" ;;
esac
exit 0
EOS
printf '#!/bin/sh\nexit 0\n' > "$T/stub/pgrep"; chmod +x "$T/stub/tmux" "$T/stub/pgrep"
printf '%s\n' '999990 0 999990 Mon Oct 28 12:00:00 2026 00:00.00 S login' \
  '999991 999990 999991 Mon Oct 28 12:00:00 2026 00:00.00 S claude' > "$T/ps.snapshot"

roster() {   # roster <chain 0|1> — #41 현역(+다른 역할 행) · chain=1 = #41 _replaced_by #42 + #42 행
  python3 - "$ENVROOT/seats/seats-zz.json" "$1" "$P41" "$P42" "$M" <<'PY'
import json, sys
p, c, o, n, m = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4], sys.argv[5]
d = {"_master": m, m: {"role": "master"}, o: {"role": "arch"}}
if c: d[o] = {"role": "stop-ready", "_replaced_by": n}; d[n] = {"role": "arch"}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$SRC"/ft-agent-alive.sh "$C/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; roster 0; : > "$C/mailbox.jsonl"; rm -f "$T"/tmp/mbox-*
  if [ -n "${1:-}" ]; then "$1"; fi
}
xenv() { env -u FT_PLANNER_HEAD_MODE -u FT_DOORBELL_TAIL PATH="$T/stub:$PATH" TMPDIR="$T/tmp" FAKE_TMUX_LOG="$T/log" \
  FAKE_SESSIONS="$P41|%1 $P42|%2" FT_PS_SNAPSHOT="$T/ps.snapshot" FT_AGENT_ALIVE_TIMEOUT=2 \
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
  FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" "$@"; }
sh_() { : > "$T/log"; OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
hold() { (cd "$ENVROOT" && xenv python3 "$C/mbox.py" holder "$1" 2>&1); }
keys() { grep -c "^$1|" "$T/log" 2>/dev/null || true; }
mut_old() {   # 고치기 전 줄로 되돌림(사본만) = 기준판
  sed -i '' 's/^    return name if num(name) > num(top) else top$/    return top/' "$C/mbox_lineage.py"
  grep -q '^    return top$' "$C/mbox_lineage.py"
}
vals() { new_env "${1:-}" || { echo "MUT-FAIL"; return; }; local r1 r2 r3 r5; r1="$(hold "$P42")"; r2="$(hold "$P41")"; r3="$(hold "$P40")"; r5="$(hold "$A")"
  roster 1; echo "$r1 $r2 $r3 $(hold "$P41") $r5"; }

# 기준판(변이) · 고친 판 값 — 순서 R1 R2 R3 R4 R5
B="$(vals mut_old)"; F="$(vals)"
set -- $B; [ "$1" = "$P41" ] && ok "변이(번호 비교 줄 삭제 = 기준판) → R1 holder($P42) = $1 FAIL 재현" || bad "변이가 R1 에 안 잡힘 :: $B"
set -- $F
[ "$1" = "$P42" ] && ok "R1 미등록 번호 큰 $P42 → holder = 자신" || bad "R1 :: $1"
[ "$2" = "$P41" ] && ok "R2 현역 $P41 → $P41" || bad "R2 :: $2"
[ "$3" = "$P41" ] && ok "R3 미등록 옛 번호 $P40 → 현역 $P41" || bad "R3 :: $3"
[ "$4" = "$P42" ] && ok "R4 은퇴 사슬 ${P41} -> ${P42} → ${P42}" || bad "R4 :: $4"
[ "$5" = "$P41" ] && ok "R5 역할 이름 $A → 현역 $P41" || bad "R5 :: $5"
[ "$(echo "$B" | cut -d' ' -f2-)" = "$(echo "$F" | cut -d' ' -f2-)" ] && ok "ⓑ R2~R5 기준판과 같음 ($(echo "$F" | cut -d' ' -f2-))" || bad "ⓑ 기준판 다름 :: base=$B fixed=$F"

# ⓐ 실제 길: ring #42 = «RING #42» + #42 pane(%2) 주입 1 · send #42 doorbell 도 %2 (구 #41 pane %1 은 0)
new_env; sh_ ring "$P42" 9001
case "$OUT" in "RING $P42 doorbell=sent") [ "$(keys %2)" = 1 ] && [ "$(keys %1)" = 0 ];; *) false;; esac \
  && ok "ⓐ ring $P42 → «RING $P42 doorbell=sent» · %2 주입 1 · %1 0" || bad "ⓐ ring rc=$RC :: $OUT :: $(tr '\n' ' ' < "$T/log")"
new_env; sh_ send "$P42" "$P41" "[인계] 첫 쪽지"
case "$OUT" in *"to=$P42 "*"doorbell=sent"*) [ "$(keys %2)" = 1 ] && [ "$(keys %1)" = 0 ];; *) false;; esac \
  && ok "ⓐ send $P42 doorbell → %2 주입 1 · %1 0" || bad "ⓐ send rc=$RC :: $OUT :: $(tr '\n' ' ' < "$T/log")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
