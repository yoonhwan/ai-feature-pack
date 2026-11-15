#!/usr/bin/env bash
# test_seat_close_ft2_nano_hint_r1924.sh — r1924: 명부 밖 2.0 나노(ft2 launch intent FT2_HOLDER) → «명부 후보 0» 대신 keeper 판정 닫기 목록 안내 1줄 · rc 1 · 쓰기·kill 0.
# 모든 쓰기는 mktemp scratch 안 — 가짜 tmux(PATH 앞) · 실제 세션·명부 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLOSE="${FT_SEAT_CLOSE_BIN:-$HERE/../../harness/bin/ft-seat-close.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0; chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
mkdir -p "$TMP/bin"; printf '#!/bin/sh\necho "$*" >> "$TMUX_LOG"\ncase "$1" in has-session) exit 1;; esac\nexit 0\n' > "$TMP/bin/tmux"; chmod +x "$TMP/bin/tmux"
R="$TMP/repo"; L="$R/.fable-team/teams/harness/runtime/launch"; mkdir -p "$L"; git -C "$R" init -q
RP="$(cd "$R" && pwd -P)"   # 루트 = git common dir(macOS /var → /private/var)
printf '{"_master": "M#1", "M#1": {"role": "master"}}' > "$R/.fable-team/seats.json"
NANO='byz-harness-nano-w1#0'; ARCH='byz-harness-arch-pi#9'
run() { ( cd "$R" && PATH="$TMP/bin:$PATH" TMUX_LOG="$TMP/tmux.log" FT_CRITICAL_OFF=1 ZC_RESUME_DIR="$TMP/resume" bash "$CLOSE" "$1" --reason r ); }
snap() { cat "$R/.fable-team/seats.json" "$L"/* 2>/dev/null | cksum; ls -A "$R/.fable-team" "$L" | cksum; }
has() { case "$1" in *"$2"*) echo y;; *) echo n;; esac; }

# ① intent(FT2_HOLDER = 나노 · w1@a2) · 명부 행 0 → 안내 줄 1 · rc 1 · 명부·intent·tmux 변화 0
printf '{"FT2_HOLDER": "%s", "FT2_WORK": "w1"}' "$NANO" > "$L/w1@a2.intent"
printf '{"FT2_HOLDER": "someone-else#0"}' > "$L/w9@a1.intent"
B="$(snap)"; out="$(run "$NANO")"; rc=$?
chk "①rc 1 · 1줄" "$rc $(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1 1"
chk "①w1·a2·keeper-verdict-close.tsv·runtime 경로" "$(has "$out" "intent w1@a2")$(has "$out" "$RP/.fable-team/teams/harness/runtime/keeper-verdict-close.tsv")$(has "$out" 'w1\ta2\t판정 <N>')" "yyy"
chk "①명부·intent 불변 · tmux 쓰기 0" "$([ "$(snap)" = "$B" ] && echo same) $(grep -cE '^(kill-session|set-option)' "$TMP/tmux.log" 2>/dev/null || true)" "same 0"

# ③ 역할 ≠ nano(arch 명부 밖 · intent 있어도) → 지금 문구 그대로
printf '{"FT2_HOLDER": "%s"}' "$ARCH" > "$L/w2@a1.intent"
out="$(run "$ARCH")"; rc=$?
chk "③arch 지금 문구" "$rc $out" "1 REJECT 명부 후보 0개 (키 $ARCH) — --seats 로 지정"

# ③' 깨진 JSON intent 만 → 지금 문구 그대로
rm -f "$L"/*.intent; printf '{"FT2_HOLDER": "%s"' "$NANO" > "$L/w1@a2.intent"
out="$(run "$NANO")"; rc=$?
chk "③'깨진 JSON 지금 문구" "$rc $out" "1 REJECT 명부 후보 0개 (키 $NANO) — --seats 로 지정"

# ② intent 없음 → 지금 문구 그대로
rm -rf "$L"; out="$(run "$NANO")"; rc=$?
chk "②intent 없음 지금 문구" "$rc $out" "1 REJECT 명부 후보 0개 (키 $NANO) — --seats 로 지정"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAIL $fail"; exit 1; }
