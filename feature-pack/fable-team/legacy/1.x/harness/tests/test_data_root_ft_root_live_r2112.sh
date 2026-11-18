#!/usr/bin/env bash
# test_data_root_ft_root_live_r2112.sh — r2112: env FT_ROOT 가 리포 공용 루트(안에 .fable-team/LIVE_ROOT)여도 ft_data_root = LIVE_ROOT 값.
#   ① FT_ROOT=R(LIVE_ROOT=L) → L   ② LIVE_ROOT 값 상대경로 / 없는 폴더 → ERROR rc≠0   ③ 값 끝 \r → L
#   ④ 소비자 실경로: FT_ROOT=R · ft-session-close-ledger.sh note → L 원장 1줄 · R 원장 0   ⑤ FT_ROOT=X(LIVE_ROOT 없음) → X
# 임시 폴더만 쓴다 — 실 리포 · 실 state · 실 우편함 0 · sleep 0 · cwd = git 밖.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd -- "$HERE/../bin" && pwd -P)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «${1}» 기대 «${2}»"; }

R="$T/repo"; L="$T/live"; X="$T/plain"; NOGIT="$T/nogit"
mkdir -p "$R/.fable-team" "$L" "$X" "$NOGIT"
git -C "$R" init -q -b main
printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"
dr() { (cd "$NOGIT" && env -u FT_ROOT -u FT_MBOX_DIR FT_ROOT="$1" bash -c '. "$1/ft-harness-root.sh"; ft_data_root "$1"' _ "$BIN" 2>&1); }

# ① FT_ROOT = 리포 루트(LIVE_ROOT 있음) → L
eq "$(dr "$R")" "$L" "① FT_ROOT=R(LIVE_ROOT=L) → L"

# ② LIVE_ROOT 값 = 상대경로 / 없는 폴더 → ERROR rc≠0
for v in "relative/path" "$T/nope"; do
  printf '%s\n' "$v" > "$R/.fable-team/LIVE_ROOT"
  out="$(dr "$R")"; rc=$?
  case "$out" in *"ERROR LIVE_ROOT 가 절대경로 폴더가 아님"*) [ "$rc" != 0 ] && ok "② 값 «${v}» → ERROR rc=$rc" || bad "② 값 «${v}» rc=0";;
    *) bad "② 값 «${v}» → ERROR 줄 없음 rc=$rc «${out}»";; esac
done

# ③ 값 끝 \r → L
printf '%s\r\n' "$L" > "$R/.fable-team/LIVE_ROOT"
eq "$(dr "$R")" "$L" "③ LIVE_ROOT 값 끝 \\r → L"
printf '%s\n' "$L" > "$R/.fable-team/LIVE_ROOT"

# ④ 소비자 실경로: ft-session-close-ledger.sh note (tmux 호출 0 = FT_SESSION_CLOSE_ID)
LED=".fable-team/state/session-close/ledger.tsv"
out="$(cd "$NOGIT" && env -u FT_ROOT -u FT_MBOX_DIR -u FT_SESSION_CLOSE_LEDGER FT_ROOT="$R" FT_SESSION_CLOSE_ID=- FT_SEAT=t \
  bash "$BIN/ft-session-close-ledger.sh" note s-r2112 tool-r2112 why 2>&1)"; rc=$?
eq "$rc" 0 "④ note rc0 «${out}»"
eq "$(wc -l 2>/dev/null < "$L/$LED" | tr -d ' ')" 1 "④ L 원장 1줄"
[ ! -e "$R/$LED" ] && ok "④ R 아래 원장 0" || bad "④ R 아래 원장 생김"

# ⑤ FT_ROOT = LIVE_ROOT 없는 폴더 → 그 값
eq "$(dr "$X")" "$X" "⑤ FT_ROOT=X(LIVE_ROOT 없음) → X"

echo "SUMMARY fail=$fail"
[ "$fail" = 0 ]
