#!/usr/bin/env bash
# test_seat_close_dead_seat_r1520.sh — r1520: close-check REJECT «[인계] 없음» 을 입구로 dead-seat 갈래(DESIGN-r1498 §5 ⓑ).
#   조건 3(생존 확인 · 명부 참조 · 미처리 보존) 전부 참 = retire --record-only → 명부 _closed → CLOSED-DEAD · kill 0 · 하나라도 거짓 = 멈춤 1줄 · 명부 쓰기 0
#   사례 ①닫힘 ②세션 살아 있음 ③자손 남음 ④_replaced_by 없음 ⑤_master 칸 값 ⑥pending 2(역할 우편함 아님) ⑦pending 전부 역할 우편함 → 닫힘 ⑧첫 갈래 회귀
#   격리: 임시 tmux 소켓(TMUX_TMPDIR) + tmux 기록 shim · 가짜 명부·우편함(close-check·peek 스텁)·reap·retire 스텁 · 실 좌석 0 · sleep 0
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; CLOSE="$HERE/../bin/ft-seat-close.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; PID=$$; REAL="$(command -v tmux)"
O="byz-r1520o-$PID#0"; N="r1520n-$PID#0"; S0="r1520s-$PID#0"; S1="r1520s-$PID#1"
mkdir -p "$TMP/wt" "$TMP/resume" "$TMP/cf" "$TMP/shim" "$TMP/sock"; git -C "$TMP/wt" init -q
export TMUX_TMPDIR="$TMP/sock"
cleanup() { local s; for s in "$O" "$S0" "$S1"; do "$REAL" kill-session -t "=$s" 2>/dev/null; done; rm -rf "$T0"; }   # 임시 소켓의 이 회차 세션만(TMUX_TMPDIR · 실 서버 0 · kill-server 0)
trap cleanup EXIT INT TERM
printf '#!/bin/sh\necho "$*" >> "%s/tmux.log"\nexec "%s" "$@"\n' "$TMP" "$REAL" > "$TMP/shim/tmux"; chmod +x "$TMP/shim/tmux"
printf '#!/bin/sh\nif [ "${2:-}" = --dry-run ]; then echo "reap $1 found=${R1520_FOUND:-0} dry-run rc=0"; exit 0; fi\necho "$*" >> "%s/reap.log"\necho "reap $1 stopped=0 left=0 rc=0"\n' "$TMP" > "$TMP/reap.sh"
printf '#!/bin/sh\necho "$*" >> "%s/retire.log"\necho "RESUME kept %s/resume/$1.json"\n' "$TMP" "$TMP" > "$TMP/retire.sh"
cat > "$TMP/mbox.py" <<'PY'
import os, sys
c, seat = sys.argv[1], sys.argv[2]
if c == "peek": print("pending=%s scanned=1 lineage=0" % os.environ.get("R1520_PEND", "0")); sys.exit(0)
if os.environ.get("R1520_CC") == "ok": print("CLOSE-OK %s stub" % seat); sys.exit(0)
print("REJECT %s [인계] 없음 — bash mbox.sh handover %s <후계>" % (seat, seat)); sys.exit(3)
PY
export PATH="$TMP/shim:$PATH" ZC_RESUME_DIR="$TMP/resume" FT_SEAT_REAP_BIN="$TMP/reap.sh" FT_SEAT_RETIRE_BIN="$TMP/retire.sh" FT_MBOX_PY="$TMP/mbox.py" FT_CRITICAL_OFF=1
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
mkseats() {  # mkseats <모드> — normal | norep | master | same | lineage
  python3 - "$TMP/cf/seats.json" "$O" "$N" "$S0" "$S1" "$1" <<'PY'
import json, sys
p, o, n, s0, s1, mode = sys.argv[1:7]
old = {"role": "stop-ready", "agent": "claude", "_replaced_by": n, "_retired_role": "arch"}
d = {"_master": "M#1", "M#1": {"role": "master"}, o: old, n: {"role": "arch", "agent": "claude", "_replaces": [o]}}
if mode == "norep": old.pop("_replaced_by"); old["role"] = "arch"
if mode == "master": d["_master"] = o
if mode == "same": d = {"_master": "M#1", "M#1": {"role": "master"}, s0: dict(old, _replaced_by=s1), s1: {"role": "arch", "_replaces": [s0]}}
if mode == "lineage": d = {"_master": "M#1", "M#1": {"role": "master"}, s0: {"role": "tester", "agent": "claude", "tick": None}, s1: {"role": "tester", "agent": "claude", "tick": None}}
open(p, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
PY
  rm -f "$TMP"/cf/seats.json.bak-* "$TMP"/*.log
}
run() { out="$(cd "$TMP/wt" && bash "$CLOSE" "$1" --reason "r1520 시험" --seats "$TMP/cf/seats.json" 2>/dev/null)"; rc=$?; L1="$(head -1 <<<"$out")"; }
closed() { python3 -c 'import json,sys;o=json.load(open(sys.argv[1]))[sys.argv[2]];print(int("_closed" in o), o.get("role"))' "$TMP/cf/seats.json" "$1"; }
kills() { cat "$TMP/tmux.log" 2>/dev/null | grep -c 'kill-session'; }
noop() { echo "$(closed "$1" | cut -d' ' -f1) $(ls "$TMP"/cf/seats.json.bak-* 2>/dev/null | wc -l | tr -d ' ') $(kills)"; }   # 명부 쓰기 0 · .bak 0 · kill 0
mksess() { "$REAL" new-session -d -s "$1" -c "$TMP/wt" "sleep 300"; }
up() { "$REAL" has-session -t "=$1" 2>/dev/null && echo up || echo gone; }

echo "== ① 세션 없음 · _replaced_by · _* 칸 아님 · pending 0 → CLOSED-DEAD · kill 0"
mkseats normal; run "$O"
chk "① rc0 · CLOSED-DEAD" "$rc $(grep -c '^CLOSED-DEAD' <<<"$L1")" "0 1"
chk "① 명부 _closed · role stop-ready" "$(closed "$O")" "1 stop-ready"
chk "① tmux kill 0 · reap 정지 0 · retire --record-only 1" "$(kills) $(cat "$TMP/reap.log" 2>/dev/null | wc -l | tr -d ' ') $(cat "$TMP/retire.log" 2>/dev/null | grep -c -- '--record-only')" "0 0 1"

echo "== ② 세션 살아 있음 → 둘째 갈래 멈춤 «[인계] 없음 · handover 먼저 또는 --verdict»"
mkseats normal; mksess "$O"; run "$O"
chk "② rc1 · 사유" "$rc $(grep -c '\[인계\] 없음.*handover 먼저 또는 --verdict' <<<"$L1")" "1 1"
chk "② 명부 쓰기 0 · .bak 0 · kill 0 · 세션 그대로" "$(noop "$O") $(up "$O")" "0 0 0 up"
"$REAL" kill-session -t "=$O"

echo "== ③ pane 자손 남음 → 멈춤 «생존 확인»"
mkseats normal; R1520_FOUND=2 run "$O"
chk "③ rc1 · dead-seat 조건 미충족 생존 확인" "$rc $(grep -c 'dead-seat 조건 미충족 생존 확인' <<<"$L1")" "1 1"
chk "③ 명부 쓰기 0 · kill 0" "$(noop "$O")" "0 0 0"

echo "== ④ _replaced_by 없음 → 멈춤 «명부 참조»"
mkseats norep; run "$O"
chk "④ rc1 · 명부 참조" "$rc $(grep -c 'dead-seat 조건 미충족 명부 참조' <<<"$L1")" "1 1"
chk "④ 명부 쓰기 0 · kill 0" "$(noop "$O")" "0 0 0"

echo "== ⑤ _master 칸 값 → 멈춤 «명부 참조»"
mkseats master; run "$O"
chk "⑤ rc1 · 명부 참조 · _master" "$rc $(grep -c 'dead-seat 조건 미충족 명부 참조.*_master' <<<"$L1")" "1 1"
chk "⑤ 명부 쓰기 0 · kill 0" "$(noop "$O")" "0 0 0"

echo "== ⑥ pending 2 · 후계가 다른 역할 우편함 → 멈춤 «미처리 보존»"
mkseats normal; R1520_PEND=2 run "$O"
chk "⑥ rc1 · 미처리 보존" "$rc $(grep -c 'dead-seat 조건 미충족 미처리 보존' <<<"$L1")" "1 1"
chk "⑥ 명부 쓰기 0 · kill 0" "$(noop "$O")" "0 0 0"

echo "== ⑦ pending 2 · 전부 역할 우편함(후계 = 같은 역할 이름) → CLOSED-DEAD"
mkseats same; R1520_PEND=2 run "$S0"
chk "⑦ rc0 · CLOSED-DEAD · kill 0" "$rc $(grep -c '^CLOSED-DEAD' <<<"$L1") $(kills)" "0 1 0"
chk "⑦ 명부 _closed" "$(closed "$S0")" "1 stop-ready"

echo "== ⑧ 첫 갈래 회귀(close-check CLOSE-OK · 생존 구좌석 · 계보 더 큰 번호 + 재개 기록) → CLOSED-SESSION kill=ok"
mkseats lineage; mksess "$S0"; mksess "$S1"; : > "$TMP/resume/$S0.json"; R1520_CC=ok run "$S0"
chk "⑧ rc0 · CLOSED-SESSION kill=ok · dead-seat 0" "$rc $(grep -c '^CLOSED-SESSION.*kill=ok' <<<"$L1") $(grep -c 'dead-seat' <<<"$out")" "0 1 0"
chk "⑧ 옛 세션 gone · 후계 up" "$(up "$S0") $(up "$S1")" "gone up"

echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi; echo "FAILED $fail"; exit 1
