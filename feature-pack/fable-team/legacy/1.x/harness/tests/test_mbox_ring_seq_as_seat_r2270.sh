#!/usr/bin/env bash
# test_mbox_ring_seq_as_seat_r2270.sh — r2270: ring 좌석 칸에 쪽지 번호(숫자만 · #숫자)가 오면 rc 2 «좌석 아님» 1줄 · 예산·held·holder·tmux 0.
#  꼴 맞는 좌석 ring(sent·absent)·BAD_SESSION_NAME 은 그대로 · 부팅 안내 3줄 ring 꼴 = «ring <좌석> <첫 seq>».
#  사례 ①~⑥ + 변이 M1~M4(사본 mbox.sh · 변이마다 원본으로 같은 사례 1회 더). 실 우편함·실 tmux·실 좌석 0 · sleep 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
export FT_MBOX_WAKE_SEAT_MAX=6 FT_MBOX_WAKE_TEAM_MAX=30
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="$HERE/../comm"; BOOT="$HERE/../../../../../tmuxc/claude-code/skills/tmuxc/COMM-GUIDE-BOOT.md"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }

mkdir -p "$T/fakebin"
cat > "$T/fakebin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  list-panes) if [ "${2:-}" = "-a" ]; then i=0; for s in ${TMUX_SEATS:-}; do i=$((i+1)); printf '%s|%%%d\n' "$s" "$i"; done
              else printf '900001\n'; fi; exit 0;;
  has-session|list-clients|send-keys) exit 0;;
  display-message) printf 'node\n'; exit 0;;
esac
exit 1
EOF
cat > "$T/fakebin/ps" <<'EOF'
#!/bin/sh
printf '%s\n' '900001     1 S    /bin/zsh' '900002 900001 S    /usr/bin/claude --dangerously-skip-permissions'
EOF
chmod +x "$T/fakebin/tmux" "$T/fakebin/ps"
printf '%s\n' '{"zz#1":{"agent":"claude","team":"h1","tick":null}}' > "$T/seats.json"
export PATH="$T/fakebin:$PATH" FT_PS_CMD="$T/fakebin/ps" FT_AGENT_ALIVE_TIMEOUT=2 TMUX_LOG="$T/tmux.log" \
       TMUX_SEATS="zz#1" FT_BIN="$T/nobin" FT_SEATS_JSON="$T/seats.json" HOME="$T/home" \
       FT_MBOX_RATE_N=1000 FT_MBOX_RESEND_COOLDOWN=0

box() {  # box <이름> [<mbox.sh 원본>] → 격리 큐·상태 · 환경 고정
  local r="$T/box-$1"; mkdir -p "$r/comm" "$r/state" "$r/tmp"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$r/comm/"; [ -n "${2:-}" ] && cp "$2" "$r/comm/mbox.sh"
  : > "$r/comm/mailbox.jsonl"; : > "$TMUX_LOG"
  export FT_MBOX_DIR="$r/comm" FT_MBOX_STATE_DIR="$r/state" TMPDIR="$r/tmp"; B="$r"
}
run() { OUT="$(bash "$B/comm/mbox.sh" "$@" 2>"$B/err")"; RC=$?; ERR="$(cat "$B/err")"; }
led() { find "$B/state" -name _ledger.log -exec cat {} + 2>/dev/null | wc -l | tr -d ' '; }
held() { find "$B/state" -path '*doorbell-held*' -type f 2>/dev/null | wc -l | tr -d ' '; }
tm() { wc -l < "$TMUX_LOG" | tr -d ' '; }
inj() { grep -c '^send-keys .* -l ' "$TMUX_LOG"; }   # 주입 1회 = 글자(-l) 1줄 + Enter 1줄

# 사례 ①② — 숫자 좌석 거름 (rc 2 · 1줄 · 장부·held·tmux 0)
case_rej() {  # case_rej <이름> <mbox.sh> <좌석 인자> → 0 = 계약대로
  box "$1" "$2"; run ring "$3" 340590
  [ "$RC" = 2 ] && [ "$OUT" = "REJECT ring 좌석 아님 $3 — 꼴: ring <좌석> [<seq>]" ] && [ "$(led)" = 0 ] && [ "$(held)" = 0 ] && [ "$(tm)" = 0 ]
}
desc() { echo "rc=$RC out=[$OUT] err=[$ERR] led=$(led) held=$(held) tmux=$(tm)"; }
case_rej c1 "" 340590 && ok "① ring 340590 → rc 2 REJECT 1줄 · 장부·held·tmux 0" || bad "① ring 340590" "$(desc)"
case_rej c2 "" '#340590' && ok "② ring #340590 → rc 2 REJECT 1줄 · 장부·held·tmux 0" || bad "② ring #340590" "$(desc)"

# 사례 ③ — 좌석 이름 + pane 있음 + 미읽음 → sent · send-keys 1 · 장부 1줄
case_sent() {
  box "$1" "$2"; bash "$B/comm/mbox.sh" send 'zz#1' 'byz-zz-nano-claude#2' "[보고] r2270 대역" >/dev/null 2>&1
  local l0; l0="$(led)"; : > "$TMUX_LOG"; run ring 'zz#1' 1
  [ "$RC" = 0 ] && [ "$OUT" = "RING zz#1 doorbell=sent" ] && [ "$(inj)" = 1 ] && [ "$(( $(led) - l0 ))" = 1 ]
}
case_sent c3 "" && ok "③ ring zz#1 1 → doorbell=sent · send-keys 1 · 장부 1줄" || bad "③ 좌석 ring" "$(desc) inj=$(inj)"

# 사례 ④ — 좌석 이름 · pane 없음 → absent rc 0(지금 꼴)
case_abs() { box "$1" "$2"; run ring 'zq#1' 7; [ "$RC" = 0 ] && [ "$OUT" = "RING zq#1 doorbell=absent" ]; }
case_abs c4 "" && ok "④ ring zq#1(pane 없음) → doorbell=absent rc 0" || bad "④ absent" "$(desc)"

# 사례 ⑤ — 허용 밖 글자 = BAD_SESSION_NAME rc 1(거름 순서)
box c5; run ring 'a;b'
{ [ "$RC" = 1 ] && [ -z "$OUT" ] && [ "$ERR" = "BAD_SESSION_NAME a;b" ]; } && ok "⑤ ring 'a;b' → BAD_SESSION_NAME rc 1" || bad "⑤ BAD_SESSION_NAME" "$(desc)"

# 사례 ⑥ — 부팅 안내 3줄
l3="$(grep -E '^3\. ' "$BOOT")"
{ printf '%s' "$l3" | grep -qF '재발주=`ring <좌석> <첫 seq>`' && ! grep -qF '`ring <최초 seq>`' "$BOOT" \
  && [ "$(wc -c < "$BOOT" | tr -d ' ')" -le 2048 ] && [ "$(grep -cE '^[0-9]+\. ' "$BOOT")" = 17 ]; } \
  && ok "⑥ BOOT 3줄 재발주=ring <좌석> <첫 seq> · ≤2048 · 번호 줄 17" || bad "⑥ BOOT" "l3=[$l3] bytes=$(wc -c < "$BOOT")"

# 변이 M1~M4 — 사본 mbox.sh 만 바꾼다 · 변이마다 원본으로 같은 사례 1회 더
ORIG="$COMM/mbox.sh"; M="$T/mut"; mkdir -p "$M"
awk '/REJECT ring 좌석 아님/{next}1' "$ORIG" > "$M/m1.sh"
awk '/REJECT ring 좌석 아님/{g=$0; next} /db="\$\(doorbell_status "\$sess" 1/{print g} 1' "$ORIG" > "$M/m2.sh"
sed 's/\^#?\[0-9\]+\$/^[0-9]+$/' "$ORIG" > "$M/m3.sh"
sed 's/\(db="\$(doorbell_status "\$sess" 1 "\$_rsq")";\)/\1 [ "$db" = absent ] \&\& exit 2;/' "$ORIG" > "$M/m4.sh"
mut() {  # mut <이름> <사례 함수> <사례 인자…> — 변이 = FAIL · 원본 = PASS
  local n="$1" f="$2"; shift 2
  if cmp -s "$ORIG" "$M/$n.sh"; then bad "$n 변이 적용 실패"; return; fi
  if "$f" "$n-m" "$M/$n.sh" "$@"; then bad "$n 변이가 안 잡힘" "$(desc)"; else ok "$n 변이 → FAIL($(desc))"; fi
  "$f" "$n-o" "" "$@" && ok "$n 원본 같은 사례 PASS" || bad "$n 원본 같은 사례" "$(desc)"
}
mut m1 case_rej 340590      # 숫자 거름 지움 → ①
mut m2 case_rej 340590      # 거름을 예산 뒤로 → ① 장부 줄
mut m3 case_rej '#340590'   # # 붙은 숫자 안 거름 → ②
mut m4 case_abs             # pane 없는 ring 모두 rc 2 → ④

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
