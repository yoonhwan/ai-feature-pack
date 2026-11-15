#!/usr/bin/env bash
# test_seat_close_done_r1656.sh — r1656: `ft-seat-close.sh <팀장> --done` = 2.0 세션 수명 닫기(사람 h 없이).
#   ⓐ 팀장(role=master · 현역 _master 칸 값이어도)만 · --verdict 와 동시 = usage 2
#   ⓑ 관문 넷 ①마지막 발신 머리 [다음 없음 ②open-work rc0 ③close-check --no-ready(미표시 0) ④재개 기록 — 하나라도 아니면 REJECT rc1 · 쓰기 0 · kill 0
#   ⓒ 통과 = CLOSED-DONE · _closed.done{ts,seq} · role·_master 그대로 · kill 1 · 원장 verdict=done-<seq> 1줄
#   변이 M1(관문① 삭제 → 사례② 닫힘) · M2(관문② 삭제 → 사례③ 닫힘) — bin 사본에서만.
# 모든 쓰기 = mktemp · 우편함 = 정본 mbox* 복사본 · 가짜 tmux/retire/reap/open-work · 실 tmux·실 명부 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
T0=$SECONDS
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."; BIN="$REPO/harness/bin"; SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
L="byz-t-master-codex#1"; N="byz-t-nano-codex#0"
export FT_ROOT="$T/root" RETIRE_LOG="$T/retire.log" TMUX_LOG="$T/tmux.log" ZC_RESUME_DIR="$T/resume" FT_CRITICAL_OFF=1
mkdir -p "$FT_ROOT/.fable-team/state" "$ZC_RESUME_DIR" "$T/bin"; VLOG="$FT_ROOT/.fable-team/state/seat-close-verdict.log"
for f in ft-seat-close.sh ft-tick.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 같은 바이트 $f" || bad "키트 사본 어긋남 $f"; done

printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/reap-stub.sh"
printf '#!/usr/bin/env bash\necho "$*" >> "$RETIRE_LOG"\n: > "$ZC_RESUME_DIR/$1.json"\necho "RESUME ok $ZC_RESUME_DIR/$1.json"\n' > "$T/bin/retire-stub.sh"
printf 'import os, sys\nprint("OPEN-WORK stub")\nsys.exit(int(os.environ.get("OW_RC", "0")))\n' > "$T/bin/ow-stub.py"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) n=""; for a in "$@"; do case "$a" in =*) n="${a#=}";; esac; done; grep -qE "^kill-session .*=$n\$" "$TMUX_LOG" && exit 1; exit 0;;
  show-options) echo 1;;
  display-message) case "$*" in *session_attached*) echo 0;; *) echo caller#0;; esac;;
esac
exit 0
EOF
chmod 0755 "$T/bin/reap-stub.sh" "$T/bin/retire-stub.sh" "$T/bin/tmux"

new_env() {   # new_env <마지막 발신 본문> — 격리 리포 · 우편함 복사본 · 명부(_master = L · nano 1행)
  E="$(mktemp -d "$T/e.XXXXXX")"; C="$E/.fable-team/comm"; mkdir -p "$C" "$E/seats"; : > "$TMUX_LOG"; : > "$RETIRE_LOG"; : > "$VLOG"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C"/; : > "$C/mailbox.jsonl"; git -C "$E" init -q -b main
  printf '{"_master": "%s", "%s": {"role": "master", "agent": "codex", "model": "m", "tick": "t1"}, "%s": {"role": "nano", "agent": "codex", "model": "m", "tick": null}}\n' "$L" "$L" "$N" > "$E/seats/seats-t.json"
  S="$E/seats/seats-t.json"; cp "$S" "$T/roster.orig"
  printf '{"seq": 3, "ts": "2026-11-15T00:00:00", "to": "byz-t-planner-codex#1", "from": "%s", "body": "[정리] 앞 쪽지"}\n' "$L" > "$C/mailbox.log.jsonl"
  printf '{"seq": 5, "ts": "2026-11-15T00:01:00", "to": "byz-t-planner-codex#1", "from": "%s", "body": "%s"}\n' "$L" "$1" >> "$C/mailbox.log.jsonl"
  printf '{"seq": 6, "ts": "2026-11-15T00:02:00", "to": "%s", "from": "x#1", "body": "[알림] 남이 보낸 쪽지"}\n' "$L" >> "$C/mailbox.log.jsonl"
}
close_() { local b="${CB:-$BIN/ft-seat-close.sh}"; OUT="$(cd "$E" && env -u FT_SEATS_JSON PATH="$T/bin:$PATH" FT_MBOX_DIR="$C" FT_MBOX_PY="$C/mbox.py" \
  FT_SEAT_REAP_BIN="$T/bin/reap-stub.sh" FT_SEAT_RETIRE_BIN="$T/bin/retire-stub.sh" FT_SEAT_OPEN_WORK="$T/bin/ow-stub.py" OW_RC="${OW_RC:-0}" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 bash "$b" "$@" 2>&1)"; RC=$?; }
kills() { grep -c '^kill-session' "$TMUX_LOG" 2>/dev/null || true; }
J() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))' "$S" "$1"; }
untouched() { echo "$(cmp -s "$S" "$T/roster.orig" && echo same) $(kills) $(wc -l < "$VLOG" | tr -d ' ')"; }
DN="[다음 없음] 팀 일 끝 · 받을 일 0"

echo "== ① 넷 다 참 → CLOSED-DONE · kill 1 · role·_master 그대로 · _closed.done · 원장 1줄"
new_env "$DN"; close_ "$L" --reason "r1656 일 끝" --seats "$S" --done
chk "①rc0 · CLOSED-DONE seq=5" "$RC $(grep -c "^CLOSED-DONE $L seq=5 record=$ZC_RESUME_DIR/$L.json kill=ok" <<< "$OUT")" "0 1"
chk "①kill 1 · retire 1회(--record-only --verdict 5)" "$(kills) $(grep -c -- "^$L --record-only --verdict 5 --seats $S\$" "$RETIRE_LOG")" "1 1"
chk "①role master · _master L · tick 그대로" "$(J "[d['$L']['role'], d['_master'] == '$L', d['$L']['tick']]")" "['master', True, 't1']"
chk "①_closed.done.seq 5 · ts 있음" "$(J "[d['$L']['_closed']['done']['seq'], bool(d['$L']['_closed']['done']['ts'])]")" "[5, True]"
chk "①원장 1줄 verdict=done-5" "$(wc -l < "$VLOG" | tr -d ' ') $(cut -f2 "$VLOG")" "1 verdict=done-5"

echo "== ② 마지막 발신 = [정리] → REJECT ①"
new_env "[정리] 오늘 한 일"; close_ "$L" --reason r --seats "$S" --done
chk "②rc1 · REJECT 관문①" "$RC $(grep -c "^REJECT $L --done ① 마지막 발신 머리" <<< "$OUT")" "1 1"
chk "②명부 동일 · kill 0 · 원장 0" "$(untouched)" "same 0 0"

echo "== ③ open-work rc1(받을 일 있음) → REJECT ② · rc3 = 판정 불가 REJECT"
new_env "$DN"; OW_RC=1 close_ "$L" --reason r --seats "$S" --done
chk "③rc1 · REJECT 관문② 있음" "$RC $(grep -c "② 받을 일 있음(open-work rc=1)" <<< "$OUT")" "1 1"
chk "③명부 동일 · kill 0 · retire 0" "$(untouched) $(wc -l < "$RETIRE_LOG" | tr -d ' ')" "same 0 0 0"
OW_RC=3 close_ "$L" --reason r --seats "$S" --done
chk "③b rc3 → REJECT 판정 불가" "$RC $(grep -c "② 받을 일 판정 불가(open-work rc=3)" <<< "$OUT") $(untouched)" "1 1 same 0 0"

echo "== ④ 미표시 영수 1 → REJECT ③"
new_env "$DN"; printf '{"seq": 9, "ts": "2026-11-15T00:03:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] 질문"}\n' "$L" >> "$C/mailbox.jsonl"
(cd "$E" && FT_MBOX_DIR="$C" FT_MBOX_RATE_N=999 bash "$C/mbox.sh" recv "$L" >/dev/null 2>&1)
close_ "$L" --reason r --seats "$S" --done
chk "④rc1 · REJECT 관문③ 미표시" "$RC $(grep -c "^REJECT $L --done ③ REJECT $L 미표시 쪽지 1" <<< "$OUT")" "1 1"
chk "④명부 동일 · kill 0 · retire 0" "$(untouched) $(wc -l < "$RETIRE_LOG" | tr -d ' ')" "same 0 0 0"

echo "== ⑤ nano 행 → REJECT 팀장만 · --done+--verdict = usage 2"
new_env "$DN"; close_ "$N" --reason r --seats "$S" --done
chk "⑤rc1 · --done 은 팀장만" "$RC $(grep -c "^REJECT $N --done 은 팀장만(role=nano)" <<< "$OUT") $(untouched)" "1 1 same 0 0"
close_ "$L" --reason r --seats "$S" --done --verdict 4138
chk "⑤b --done --verdict → rc2 usage · 쓰기 0" "$RC $(grep -c -- '--done 은 --verdict' <<< "$OUT") $(untouched)" "2 1 same 0 0"

echo "== 변이 M1·M2 (bin 사본)"
mutc() {   # mutc <이름> <옛글자> <새글자> → $T/m/<이름>/ft-seat-close.sh
  local d="$T/m/$1"; mkdir -p "$d"; cp "$BIN"/ft-seat-close.sh "$BIN"/ft_roster_lib.py "$BIN"/ft-harness-root.sh "$d"/
  python3 - "$d/ft-seat-close.sh" "$2" "$3" <<'PY'
import sys
p, o, n = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(o) != 1: sys.exit("mut: «%s» 개수 %d" % (o, s.count(o)))
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
}
mutc M1 'if not body.lstrip().startswith("[다음 없음"):' 'if False:' || bad "M1 치환 실패"
new_env "[정리] 오늘 한 일"; CB="$T/m/M1/ft-seat-close.sh" close_ "$L" --reason r --seats "$S" --done
chk "M1 관문① 삭제 → 사례② 가 닫힘(변이 잡힘)" "$RC $(grep -c '^CLOSED-DONE' <<< "$OUT")" "0 1"
mutc M2 'if rc != 0: print("②' 'if False: print("②' || bad "M2 치환 실패"
new_env "$DN"; CB="$T/m/M2/ft-seat-close.sh" OW_RC=1 close_ "$L" --reason r --seats "$S" --done
chk "M2 관문② 삭제 → 사례③ 이 닫힘(변이 잡힘)" "$RC $(grep -c '^CLOSED-DONE' <<< "$OUT")" "0 1"

echo "RUN test_seat_close_done_r1656 $((SECONDS - T0))s"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
