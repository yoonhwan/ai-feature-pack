# sheet_env.sh — test_sheet_render.sh · test_sheet_events.sh 공용 준비 (source 용). 실제 gh·tmux·슬랙·LLM 호출 0 · 라이브 .fable-team 쓰기 0.
BIN="$HERE/../bin"
FIX="$HERE/../fixtures/sheet"
T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }
export FT_BOARD_NOW="2026-10-12T11:00:00" FT_BOARD_GH_TTL=0 FT_BOARD_GH_REFRESH=1 FT_VERDICT_BIN="$BIN/ft-verdict.sh"
export FT_BOARD_TMUX="bash $T/tmux.sh" FT_BOARD_GH="cat $T/gh.json" FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_SEAT_STATUS="$T/status.sh"
printf '#!/bin/sh\nprintf "h-master#1\\nh-nano-a#0\\nh-nano-b#0\\nl-master#1\\nc-master#1\\np-master#1\\n"\n' > "$T/tmux.sh"
printf '#!/bin/sh\necho EMPTY\n' > "$T/inbox.sh"
printf '#!/bin/sh\necho '"'"'{"state":"WORKING","turn_end":null,"duration_ms":null,"reported":null,"source":"jsonl"}'"'"'\n' > "$T/status.sh"
echo '[]' > "$T/gh.json"
NROOT=0
new_root() { NROOT=$((NROOT+1)); export FT_ROOT="$T/root$NROOT"; mkdir -p "$FT_ROOT"; python3 "$FIX/make_root.py" "$FT_ROOT"; FB="$FT_ROOT/.fable-team"; }
board() { python3 "$BIN/ft-board.py" "$@"; }
sheet_txt() { board render --sheet --text; }
