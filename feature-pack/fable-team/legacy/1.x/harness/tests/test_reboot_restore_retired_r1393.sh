#!/usr/bin/env bash
# test_reboot_restore_retired_r1393.sh — r1393: 재부팅 복구가 명부(seats*.json)에서 «_replaced_by» 가 있는 은퇴 좌석을 열지 않는다.
#   R1 은퇴 좌석(명부 _replaced_by=A′) · tmux 없음 → «SKIP 은퇴(→A′)» · 새 세션 0 · 래퍼 호출 0 (--dry-run)
#   R2 R1 을 실행 모드로 → 새 세션 0 · 래퍼 호출 0 · rc 0
#   R3 전팀 정지 레디 현역(B · role=stop-ready · _replaced_by 없음) → 지금처럼 열린다(래퍼 인자·세션)
#   R4 명부에 없는 좌석(C) → 지금 길 그대로(엔진 밖 FAIL 로 precheck 계속)
#   R5 명부 파일 1개 JSON 깨짐 → ERROR rc 2 «명부 읽기 실패 <파일>» · 새 세션 0 · 래퍼 호출 0
#   R6 은퇴 좌석(A)이 tmux 에 살아 있음 → «SKIP 살아 있음»(지금 그대로 · 닫기 0)
# 전부 mktemp 안 — 임시 HOME(스냅샷·projects·가짜 claude-hr.sh) · 임시 FT_ROOT(명부·원장) ·
#   ★tmux 는 격리 소켓(-L ftrr1393-test-<pid>) 셔임을 PATH 앞에 — 사용자 tmux 서버의 세션은 보지도 건드리지도 않는다★
# base 대조(기준판): R1393_BIN=<옛 판 kit bin 폴더> bash <이 파일> — R1·R2 가 FAIL 이어야 한다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R1393_BIN:-$REPO/harness/kit/fable-team/bin}"
TOOL="$BIN/ft-reboot-restore.sh"
RT="$(command -v tmux)"; SOCK="ftrr1393-test-$$"
T="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  "$RT" -L "$SOCK" list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do "$RT" -L "$SOCK" kill-session -t "=$s" 2>/dev/null; done
  [ -f "$T/pids" ] && while read -r p; do kill "$p" 2>/dev/null; done < "$T/pids"
  rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T"
}
trap cleanup EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

# ── 격리 tmux · 임시 HOME · 가짜 헤드룸 래퍼 · 임시 명부 ──
F="$T/fake"; H="$T/home"; export HOME="$H" FT_ROOT="$T/root"
mkdir -p "$F" "$H/.tmuxc/snapshots" "$H/.claude/state/seat-live" "$H/.claude/projects" "$H/.headroom" "$FT_ROOT/.fable-team/state"
FT_ROOT="$FT_ROOT" bash "$BIN/ft-all-stop.sh" init > /dev/null 2>&1 || bad "r626 정지 원장 init"
: > "$H/.zshrc"; : > "$H/.zshenv"
printf '#!/bin/bash\nexec %q -L %q "$@"\n' "$RT" "$SOCK" > "$F/tmux"; chmod +x "$F/tmux"; export PATH="$F:$PATH"
cat > "$H/.headroom/claude-hr.sh" <<EOF
#!/bin/bash
n="\$FT_SEAT"; printf '%s\n' "\$@" > "$T/args.\$n"; echo "\$\$" >> "$T/pids"
exec env ANTHROPIC_BASE_URL="http://127.0.0.1:8317" python3 -c 'import time; time.sleep(300)'
EOF
chmod +x "$H/.headroom/claude-hr.sh"
enc() { python3 -c 'import re,sys;print(re.sub("[^A-Za-z0-9]","-",sys.argv[1]))' "$1"; }
jsonl_of() { echo "$H/.claude/projects/$(enc "$T/cwd-$1")/$2.jsonl"; }
mkseat() {
  mkdir -p "$T/cwd-$1"; mkdir -p "$(dirname "$(jsonl_of "$1" "$2")")"; echo '{"type":"user"}' > "$(jsonl_of "$1" "$2")"
}
snap() {   # snap <이름:uuid> ... → latest.json
  python3 - "$H/.tmuxc/snapshots/latest.json" "$T" "$@" <<'PY'
import json, sys
out, t, rows = sys.argv[1], sys.argv[2], sys.argv[3:]
ss = [dict(name=n, cwd=f"{t}/cwd-{n}", agent="claude", model="claude-opus-5-5[1m]", effort="xhigh", session_id=u) for n, u in (r.split(":") for r in rows)]
json.dump(dict(schema=1, created_at="2026-11-05T10:00:00Z", host="t", session_count=len(ss), sessions=ss), open(out, "w"))
PY
}
registry() {   # registry <파일> <좌석> <_replaced_by|-> [role] ...  → seats-<파일>.json (메타 키 1개 포함)
  local out="$FT_ROOT/.fable-team/seats-$1.json"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, rows = sys.argv[1], sys.argv[2:]
d = {"_name": "Seatbelt-TEST", "_version": "1.0.0"}
for r in rows:
    n, rep, *role = r.split(":")
    d[n] = {"role": role[0] if role else "stop-ready", "agent": "claude"}
    if rep != "-": d[n]["_replaced_by"] = rep
json.dump(d, open(out, "w"), ensure_ascii=False, indent=2)
PY
}
reset_tmux() { tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do tmux kill-session -t "=$s"; done; rm -f "$T"/args.*; }
run() { OUT="$(bash "$TOOL" "$@" 2>&1)"; RC=$?; }
alive() { tmux has-session -t "=$1" 2>/dev/null; }

if [ -f "$TOOL" ]; then bash -n "$TOOL" && ok "bash -n ft-reboot-restore.sh" || bad "bash -n ft-reboot-restore.sh"; else bad "도구 없음 $TOOL"; fi
[ -z "${R1393_BIN:-}" ] && { cmp -s "$TOOL" "$REPO/harness/bin/ft-reboot-restore.sh" && ok "harness/bin 사본 cmp 0" || bad "harness/bin 사본 어긋남"; }

A=ftrr1393-test-a; A2=ftrr1393-test-a2; B=ftrr1393-test-b; C=ftrr1393-test-c
UA=aaaa1111-0000-4000-8000-000000000001; UB=bbbb2222-0000-4000-8000-000000000002; UC=cccc3333-0000-4000-8000-000000000003
mkseat $A $UA; mkseat $B $UB; mkseat $C $UC
registry a "$A:$A2" "$B:-:stop-ready"          # A = 은퇴(_replaced_by=A′) · B = 전팀 정지 레디 현역

# ── R1 은퇴 좌석 = SKIP 은퇴(→후계) · 새 세션 0 (--dry-run) ──
reset_tmux; snap "$A:$UA"
run --dry-run
eq "$RC" 0 "R1 rc 0"
has "$OUT" "$A · SKIP 은퇴(→$A2)" "R1 SKIP 은퇴(→후계) 줄"
hasnt "$OUT" "$A · 계획 열기" "R1 계획 열기 0"
# ── R2 같은 좌석을 실행 모드로 = 새 세션 0 · 래퍼 호출 0 ──
reset_tmux; snap "$A:$UA"
run
eq "$RC" 0 "R2 rc 0"
alive $A && bad "R2 은퇴 좌석 세션 열림" || ok "R2 은퇴 좌석 새 세션 0"
[ ! -e "$T/args.$A" ] && ok "R2 은퇴 좌석 래퍼 호출 0" || bad "R2 은퇴 좌석 래퍼가 불림"
has "$OUT" "$A · SKIP 은퇴(→$A2)" "R2 실행 모드에서도 SKIP 은퇴"
hasnt "$OUT" "ok=1" "R2 ok 계수 0"
# ── R3 전팀 정지 레디 현역(B) = 지금처럼 연다 ──
reset_tmux; snap "$B:$UB"
run
eq "$RC" 0 "R3 rc 0"
alive $B && ok "R3 정지 레디 현역 세션 열림" || bad "R3 정지 레디 현역 안 열림"
[ -e "$T/args.$B" ] && ok "R3 래퍼 호출됨" || bad "R3 래퍼 호출 0"
has "$OUT" "$B · OK" "R3 OK 줄"
hasnt "$OUT" "SKIP 은퇴" "R3 은퇴 판정 0"
# ── R4 명부에 없는 좌석(C) = 지금 길 그대로(은퇴 판정 없이 엔진 판정까지 감) ──
reset_tmux; snap "$C:$UC"
run --dry-run
hasnt "$OUT" "$C · SKIP 은퇴" "R4 명부 밖 좌석 은퇴 판정 0"
has "$OUT" "$C · 계획 열기" "R4 명부 밖 좌석 계획 열기(지금 그대로)"
eq "$RC" 0 "R4 rc 0"
# ── R6 은퇴 좌석이 살아 있음 = SKIP 살아 있음(지금 그대로 · 닫기 0) ──
reset_tmux; snap "$A:$UA"; tmux new-session -d -s $A -c "$T/cwd-$A" 'sleep 300'
run --dry-run
has "$OUT" "$A · SKIP 살아 있음" "R6 살아 있음이 먼저(은퇴 판정보다)"
alive $A && ok "R6 살아 있는 세션 닫기 0" || bad "R6 살아 있는 세션을 닫았다"
reset_tmux
# ── R5 명부 1개 JSON 깨짐 = ERROR rc 2 · 새 세션 0 · 깨진 파일 이름 1줄 ──
snap "$B:$UB"; printf '{ "broken": \n' > "$FT_ROOT/.fable-team/seats-broken.json"
run
eq "$RC" 2 "R5 rc 2"
has "$OUT" "ERROR 명부 읽기 실패" "R5 ERROR 명부 읽기 실패 줄"
has "$OUT" "seats-broken.json" "R5 깨진 파일 이름"
alive $B && bad "R5 명부 실패인데 세션 열림" || ok "R5 새 세션 0"
[ ! -e "$T/args.$B" ] && ok "R5 래퍼 호출 0" || bad "R5 명부 실패인데 래퍼 호출"
hasnt "$OUT" "REBOOT-RESTORE" "R5 실패면 좌석 표도 안 냄"
run --dry-run
eq "$RC" 2 "R5 dry-run 도 rc 2"
rm -f "$FT_ROOT/.fable-team/seats-broken.json"
# ── 명부 없음 = 지금 길 그대로(회귀 1칸) ──
rm -f "$FT_ROOT/.fable-team"/seats-*.json
reset_tmux; snap "$A:$UA"; run --dry-run
has "$OUT" "$A · 계획 열기" "명부 없음 = 은퇴 판정 0(지금 그대로)"

echo "== r1393 fail=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
