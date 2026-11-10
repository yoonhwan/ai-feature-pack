#!/usr/bin/env bash
# test_mbox_uf_watch_ext_skip_r1559.sh — r1559: uf_watch 가 pi 확장 좌석(planner _master·_desk · ft-mbox-wake.ts)을 건너뛴다
#  · pi 좌석은 Monitor 감시(ft-inbox-watch)를 안 쓴다 → watch-alive rc3 «NO watch» 가 늘 참 → 경보가 늘 거짓이었다(#278241·312·317·369)
#  · 끝 = pi 확장 좌석 앞 send 에서 [긴급 · planner watch 없음] 0통 · 표식 파일 0 · stderr 1줄(끈 이유 · no_silent_fallback)
#  · claude user_facing 좌석의 watch 판정은 「지금과 같다」(긴급 1통 · 10분 1회) · 확장 미설치 = 지금과 같다 · send 출력 형식 불변
#  격리: 임시 박스(.fable-team/{comm,state}) · FT_MBOX_DIR·FT_MBOX_STATE_DIR·TMPDIR · 임시 명부(FT_SEATS_JSON) ·
#        가짜 tmux · 가짜 FT_BIN ft-mbox.sh(watch-alive = rc3 «NO watch») · 가짜 HOME(확장 있음/없음) ·
#        실 우편함·실 pane·실 명부 0 · 자기 재호출 0 · sleep 0
#  사례 ⓐ~ⓓ + 변이 M1·M2.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; COMM="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

# ── fakebin: tmux(pane 목록) / FT_BIN: ft-mbox.sh watch-alive = rc3 «NO watch» ─────────────────────────
mkdir -p "$T/fakebin" "$T/ftbin"
cat > "$T/fakebin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  list-panes)
    shift
    if [ "${1:-}" = "-a" ]; then i=0; for s in ${TMUX_SEATS:-}; do i=$((i+1)); printf '%s|%%%d\n' "$s" "$i"; done
    else printf '%s\n' "${TMUX_PANE_PID:-900001}"; fi
    exit 0;;
  has-session|list-clients) exit 0;;
  display-message) printf 'node\n'; exit 0;;
  send-keys) exit 0;;
esac
exit 1
EOF
# watch-alive 는 «감시 프로세스 0» 만 흉내낸다 — pi 좌석의 실측 상태(Monitor 안 씀)와 같다.
cat > "$T/ftbin/ft-mbox.sh" <<'EOF'
#!/bin/bash
case "${1:-}" in
  watch-alive) echo "NO watch"; exit 3;;
esac
exit 0
EOF
chmod +x "$T/fakebin/tmux" "$T/ftbin/ft-mbox.sh"
# 가짜 HOME 두 개 — 확장 설치본 있음(pi 좌석) / 없음(ⓒ). ext_wake_seat 은 «파일 존재» 만 본다.
mkdir -p "$T/ext/.pi/agent/extensions" "$T/nohome"
: > "$T/ext/.pi/agent/extensions/ft-mbox-wake.ts"

# ── 명부 2벌 — pi 확장 좌석(planner _master·_desk) / claude user_facing 좌석 ───────────────────────────
mkdir -p "$T/seats-pi" "$T/seats-claude"
# ★명부 충돌 금지★ — 좌석 행은 «한 파일» 에만(guard ①). pm#1·dm#1 = seats-planner.json 전용.
printf '%s\n' '{"_master":"pm#1","hmaster#1":{"agent":"claude","tick":null}}' > "$T/seats-pi/seats.json"
printf '%s\n' '{"_master":"pm#1","_desk":"dm#1","pm#1":{"role":"master","agent":"pi"},"dm#1":{"role":"desk","agent":"pi"}}' \
  > "$T/seats-pi/seats-planner.json"
printf '%s\n' '{"_master":"cm#1","hmaster#1":{"agent":"claude","tick":null}}' > "$T/seats-claude/seats.json"
printf '%s\n' '{"_master":"cm#1","cm#1":{"role":"master","agent":"claude"}}' \
  > "$T/seats-claude/seats-planner.json"
# 하네스 master(긴급 받는 쪽) = 박스 안 명부 — uf_watch 가 여기로 [긴급] 을 적재한다.
for d in pi claude; do printf '%s\n' '{"_master":"hmaster#1","hmaster#1":{"agent":"claude","tick":null}}' > "$T/seats-$d/seats-harness.json"; done

BOX=""; C=""
mkbox() {
  local r="$T/box-$1"
  mkdir -p "$r/.fable-team/comm" "$r/.fable-team/state" "$r/tmp"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$r/.fable-team/comm/"
  : > "$r/.fable-team/comm/mailbox.jsonl"
  printf '%s' "$r"
}
use() { BOX="$1"; C="$BOX/.fable-team/comm"; SEATDIR="${2:-$T/seats-pi}"; EXT_HOME="${3:-$T/ext}"
        export FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" TMPDIR="$BOX/tmp"
        : > "$BOX/err"; : > "$T/tmux.log"; }
run() {  # <mbox.sh 하위명령…> → OUT·RC·ERR
  OUT="$(HOME="$EXT_HOME" FT_SEATS_JSON="$SEATDIR/seats.json" FT_BIN="$T/ftbin" TMUX_LOG="$T/tmux.log" \
        FT_HARNESS_SEATS_JSON="$SEATDIR/seats-harness.json" bash "$C/mbox.sh" "$@" 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
}
S()   { run send "$@"; }
nv()  { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
urg() { FT_MBOX_DIR="$C" python3 "$C/mbox.py" peek "$1" 2>/dev/null | sed -n 's/^pending=\([0-9][0-9]*\).*/\1/p' | head -1; }
urgbody() { FT_MBOX_DIR="$C" python3 - "$1" <<'PY'
import json, os, sys
p = os.path.join(os.environ["FT_MBOX_DIR"], "mailbox.jsonl")
try: rows = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
except Exception: rows = []
print("\n".join(f'{r.get("to")}|{(r.get("body") or "").splitlines()[0]}' for r in rows if r.get("to") == sys.argv[1]))
PY
}
marks() { ls "$BOX/.fable-team/state" 2>/dev/null | grep -c '^planner-watch-missing\.'; }

# ── ⓐ pi 확장 좌석(planner _master·_desk) · watch-alive rc3 → 긴급 0 · 표식 0 · stderr 1줄 ──────────────
use "$(mkbox a)"
S pm#1 s1#1 "ⓐ pi _master 확장 좌석 쪽지"
eq "ⓐ send rc=0" "$RC" 0
eq "ⓐ pi _master → 하네스 master [긴급] 0통" "$(urg hmaster#1)" 0
eq "ⓐ pi _master → 표식 파일 0" "$(marks)" 0
grep -q 'WATCH 판정 0 — pi 확장 좌석 pm#1' <<<"$ERR" && ok "ⓐ stderr «WATCH 판정 0 — pi 확장 좌석 pm#1»" \
  || bad "ⓐ stderr 이유 1줄" "$ERR"
eq "ⓐ 도어벨 꼬리에 (WATCH 없음) 0" "$(grep -c 'WATCH 없음' <<<"$OUT")" 0
# _desk 는 user_facing 이 아니라 uf_watch 자체가 안 돌았다(원래도 경보 0) — 판정은 확장 좌석 전반에 걸린 안전망이다.
S dm#1 s1#1 "ⓐ pi _desk 확장 좌석 쪽지"
eq "ⓐ pi _desk → 하네스 master [긴급] 0통" "$(urg hmaster#1)" 0
eq "ⓐ pi _desk → 표식 파일 0" "$(marks)" 0
eq "ⓐ pi _desk → WATCH 꼬리 0(uf_watch 미호출 · user_facing 아님)" "$(grep -c 'WATCH' <<<"$OUT$ERR")" 0

# ── ⓑ claude user_facing 좌석 · watch-alive rc3 → 지금처럼 [긴급] 1통 · 10분 1회 ────────────────────────
use "$(mkbox b)" "$T/seats-claude"
S cm#1 s1#1 "ⓑ claude _master 쪽지 1"
eq "ⓑ claude 좌석 → [긴급] 1통" "$(urg hmaster#1)" 1
grep -q '\[긴급 · planner watch 없음\] cm#1' <<<"$(urgbody hmaster#1)" && ok "ⓑ 긴급 본문 = [긴급 · planner watch 없음] cm#1" \
  || bad "ⓑ 긴급 본문" "$(urgbody hmaster#1)"
eq "ⓑ 표식 파일 1" "$(marks)" 1
S cm#1 s1#1 "ⓑ claude _master 쪽지 2"
eq "ⓑ 10분 1회 — 두 번째는 긴급 0통" "$(urg hmaster#1)" 1
grep -q 'WATCH 판정 0' <<<"$ERR" && bad "ⓑ claude 좌석에 pi 확장 판정이 걸렸다" "$ERR" \
  || ok "ⓑ claude 좌석은 확장 판정 0(지금 동작 그대로)"

# ── ⓒ 확장 미설치 = ext_wake_seat 거짓 = ⓑ 와 같음(pi 좌석도 지금 동작) ───────────────────────────────
use "$(mkbox c)" "$T/seats-pi" "$T/nohome"
S pm#1 s1#1 "ⓒ 확장 미설치 pi 좌석 쪽지"
eq "ⓒ 확장 파일 없음 → [긴급] 1통(깨움 0 금지 · 지금 그대로)" "$(urg hmaster#1)" 1
eq "ⓒ 확장 파일 없음 → 표식 파일 1" "$(marks)" 1

# ── ⓓ send 출력 «doorbell=… gate=…» 형식 불변 · rc 불변 ───────────────────────────────────────────────
use "$(mkbox d)"
S pm#1 s1#1 "ⓓ pi 좌석 출력 형식"
grep -qE '^QUEUED seq=[0-9]+ .*doorbell=[a-z]+ gate=[a-z]+$' <<<"$OUT" && ok "ⓓ 출력 = QUEUED … doorbell=… gate=…" \
  || bad "ⓓ 출력 형식" "$OUT"
eq "ⓓ pi 좌석 gate=quiet(확장 좌석 · r1524 그대로)" "$(nv "$OUT" gate)" quiet
eq "ⓓ pi 좌석 doorbell=quiet" "$(nv "$OUT" doorbell)" quiet
eq "ⓓ 큐 적재는 그대로(pending 1)" "$(urg pm#1)" 1

# ── 변이 — 계약이 «그 줄» 에 걸려 있는지(각 변이는 그 사례를 FAIL 로 만든다) ─────────────────────────────
mutbox() {  # <이름> <찾을 문자열> <바꿀 문자열> <파일> → 변이 박스 경로
  local r; r="$(mkbox "mut-$1")"
  python3 - "$r/.fable-team/comm/$4" "$2" "$3" <<'PY' || echo "MUT-APPLY-FAIL $1" >&2
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
if old not in s: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s' "$r"
}
# M1: uf_watch 첫 줄 확장 판정을 끈다 → ⓐ 가 FAIL(긴급 1통 + 표식 1) 이어야 한다
B="$(mutbox m1 '  if ext_wake_seat "$to"; then echo "WATCH 판정 0' '  if false; then echo "WATCH 판정 0' mbox.sh)"
grep -q '^  if false; then echo "WATCH 판정 0' "$B/.fable-team/comm/mbox.sh" || bad "M1 변이 미적용"
use "$B"; S pm#1 s1#1 "변이 M1 재현"
if [ "$(urg hmaster#1)" = "" ] && [ "$(marks)" = 0 ]; then bad "M1(확장 판정 끔) 이 ⓐ 를 안 잡음"; else ok "M1(확장 판정 끔) → ⓐ FAIL 확인"; fi
# M2: 판정을 «user_facing 전부» 로 넓힌다 → ⓑ 가 FAIL(긴급 0통) 이어야 한다
B="$(mutbox m2 '  if ext_wake_seat "$to"; then echo "WATCH 판정 0' '  if user_facing "$to"; then echo "WATCH 판정 0' mbox.sh)"
grep -q '^  if user_facing "\$to"; then echo "WATCH 판정 0' "$B/.fable-team/comm/mbox.sh" || bad "M2 변이 미적용"
use "$B" "$T/seats-claude"; S cm#1 s1#1 "변이 M2 재현"
if [ "$(urg hmaster#1)" = "1" ]; then bad "M2(판정을 user_facing 전부로) 가 ⓑ 를 안 잡음"; else ok "M2(user_facing 전부) → ⓑ FAIL 확인"; fi

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
