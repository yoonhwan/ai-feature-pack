#!/usr/bin/env bash
# test_installed_root.sh — r385 r3: 설치본(<HOME>/.claude/fable-team/live/<ver>/bin · git 밖)에서 «파일 위치 조상 탐색» 없이 루트·comm 을 푼다.
#   ⓐ ft_goal_ledger.find_root 순서: FT_ROOT → cwd git 공용 루트(.fable-team/LIVE_BIN) → 옛 설치 꼴 조상 → ERROR
#   ⓑ ft_comm_dir(= 공용 루트/.fable-team/comm · r459: LIVE_ROOT 를 보지 않는다) — ft-tick.sh·ft-hil-ask.sh 가 그 mbox.sh 로 푼다(인자 검사 전 대입만 · bash -x 추적 · 부작용 0)
#   ⓒ cwd=git 밖 → ERROR rc≠0 + 임시 HOME 쓰기 0 · FT_ROOT 명시 → 그 값 · 옛 설치 꼴(<리포>/.fable-team/bin) → 옛 «$HERE/../comm» 과 같은 곳
#   ⓓ 실제 BYZ(읽기만 · FT_TEST_BYZ_ROOT · 없으면 SKIP 표기) cwd 에서 설치본 ft-goal-table.sh rc0 + 골 표
#   ⓔ r385 r4: ft_board_env.ft_root 같은 순서(①FT_ROOT 그 값 그대로) · 설치본 ft-sheet-events.sh(spawn·nano-close 의 prepare 경로) 루트 풀이
# mktemp 만 쓴다 — 실 HOME·실 리포 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KBIN="$(cd -- "$HERE/../kit/fable-team/bin" && pwd -P)"
BYZ="${FT_TEST_BYZ_ROOT:-$HOME/Project/Agent/BYZ-Work/BYZ-Agents}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; skip=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «$1» 기대 «$2»"; }
unset FT_ROOT FT_HARNESS_ROOT FT_TICK_MBOX FT_MBOX_CMD

H="$T/home"; LB="$H/.claude/fable-team/live/9.9.9/bin"; mkdir -p "$LB"; cp -p "$KBIN"/* "$LB/" 2>/dev/null
NOGIT="$T/nogit"; mkdir -p "$NOGIT"
# 픽스처 리포(BYZ 꼴): .fable-team/LIVE_BIN·LIVE_ROOT · 라이브 루트 LR 의 comm · 옛 설치 꼴 bin
FX="$T/fx"; LR="$T/live-root"; mkdir -p "$FX/.fable-team/bin" "$FX/.fable-team/comm" "$LR/.fable-team/comm"
git -C "$FX" init -q -b main
printf '%s\n' "$LB" > "$FX/.fable-team/LIVE_BIN"; printf '%s\n' "$LR" > "$FX/.fable-team/LIVE_ROOT"
: > "$LR/.fable-team/comm/mbox.sh"; : > "$FX/.fable-team/comm/mbox.sh"
cp -p "$KBIN"/* "$FX/.fable-team/bin/" 2>/dev/null
snap() { (cd "$H" && find . -type f ! -path '*/__pycache__/*' | LC_ALL=C sort); }   # 파이썬 바이트코드 캐시는 데이터 쓰기 아님
BEFORE="$(snap)"

root_of() {  # <cwd> <bin> [env…] → find_root 결과 또는 ERROR 줄
  local cwd="$1" bin="$2"; shift 2
  (cd "$cwd" && env HOME="$H" "$@" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_goal_ledger as g
try: print(g.find_root(RuntimeError))
except RuntimeError as e: print("ERROR", e)' "$bin" 2>&1)
}
mbox_of() {  # <cwd> <도구> [env…] → 추적에서 MBOX= 마지막 값 · rc
  local cwd="$1" tool="$2"; shift 2
  (cd "$cwd" && env HOME="$H" HIL_LEDGER="$T/hil.md" "$@" bash -x "$LB/$tool" --r385-r3-no-such-flag 2>&1 >/dev/null | sed -n "s/^+* *MBOX=//p" | tail -1)
}

# ── ⓐ find_root ──
eq "$(root_of "$FX" "$LB")" "$FX" "ⓐ 설치본 · cwd=리포 → git 공용 루트(.fable-team/LIVE_BIN)"
mkdir -p "$FX/sub/dir"; eq "$(root_of "$FX/sub/dir" "$LB")" "$FX" "ⓐ 설치본 · cwd=리포 하위 폴더 → 공용 루트"
r="$(root_of "$NOGIT" "$LB")"; case "$r" in ERROR*) ok "ⓐ 설치본 · cwd=git 밖 → ERROR";; *) bad "ⓐ cwd=git 밖 ERROR 아님 «$r»";; esac
eq "$(root_of "$NOGIT" "$LB" FT_ROOT="$FX")" "$FX" "ⓐ FT_ROOT 명시 → 그 값"
eq "$(root_of "$NOGIT" "$FX/.fable-team/bin")" "$FX" "ⓐ 옛 설치 꼴(<리포>/.fable-team/bin) · cwd=git 밖 → 조상 탐색(회귀 0)"

# ── ⓑ comm · tick·hil-ask mbox 경로 ──
eq "$(cd "$FX" && HOME="$H" bash -c '. "$1/ft-harness-root.sh"; ft_comm_dir "$1"' _ "$LB")" "$FX/.fable-team/comm" "ⓑ ft_comm_dir 설치본 · cwd=리포 → 공용 루트 comm(LIVE_ROOT 0 · r459)"
eq "$(mbox_of "$FX" ft-tick.sh)" "$FX/.fable-team/comm/mbox.sh" "ⓑ ft-tick.sh 설치본 · cwd=리포 → <공용 루트>/.fable-team/comm/mbox.sh(r459)"
eq "$(mbox_of "$FX" ft-hil-ask.sh)" "$FX/.fable-team/comm/mbox.sh" "ⓑ ft-hil-ask.sh 설치본 · cwd=리포 → <공용 루트>/.fable-team/comm/mbox.sh(r459)"
eq "$(mbox_of "$FX" ft-tick.sh FT_TICK_MBOX=/x/mbox.sh)" "/x/mbox.sh" "ⓑ ft-tick.sh env 명시 → 그 값"
old="$(cd "$NOGIT" && HOME="$H" bash -c '. "$1/ft-harness-root.sh"; ft_comm_dir "$1"' _ "$FX/.fable-team/bin")"
eq "$old" "$(cd "$FX/.fable-team/bin/../comm" && pwd)" "ⓑ 옛 설치 꼴 → 옛 «\$HERE/../comm» 과 같은 곳(회귀 0)"

# ── ⓒ git 밖 → ERROR rc≠0 + 임시 HOME 쓰기 0 ──
(cd "$NOGIT" && HOME="$H" bash "$LB/ft-tick.sh" --r385-r3-no-such-flag >/dev/null 2>"$T/e1"); rc=$?
[ "$rc" != 0 ] && grep -q ERROR "$T/e1" && ok "ⓒ ft-tick.sh 설치본 · cwd=git 밖 → ERROR rc=$rc" || bad "ⓒ ft-tick.sh git 밖 rc=$rc «$(head -c 200 "$T/e1")»"
(cd "$NOGIT" && HOME="$H" bash "$LB/ft-goal-table.sh" >/dev/null 2>"$T/e2"); rc=$?
[ "$rc" != 0 ] && grep -q ERROR "$T/e2" && ok "ⓒ ft-goal-table.sh 설치본 · cwd=git 밖 → ERROR rc=$rc" || bad "ⓒ ft-goal-table.sh git 밖 rc=$rc «$(head -c 200 "$T/e2")»"
[ "$(snap)" = "$BEFORE" ] && ok "ⓒ 임시 HOME 밑 새 파일 0" || bad "ⓒ 임시 HOME 에 새 파일: $(comm -13 <(printf '%s\n' "$BEFORE") <(snap) | head -3 | tr '\n' ' ')"

# ── ⓓ 실제 BYZ cwd(읽기만) → 설치본 ft-goal-table.sh rc0 ──
if [ -f "$BYZ/.fable-team/LIVE_BIN" ] && [ -f "$BYZ/.fable-team/LIVE_ROOT" ]; then
  out="$(cd "$BYZ" && HOME="$H" bash "$LB/ft-goal-table.sh" 2>"$T/e3")"; rc=$?
  [ "$rc" = 0 ] && case "$out" in *"골 표"*) true;; *) false;; esac && ok "ⓓ 설치본 · cwd=BYZ → ft-goal-table.sh rc0 + 골 표 ($(printf '%s\n' "$out" | grep -c '^|')행)" || bad "ⓓ ft-goal-table.sh cwd=BYZ rc=$rc «$(head -c 300 "$T/e3")»"
else
  echo "SKIP ⓓ BYZ 루트 없음: $BYZ (FT_TEST_BYZ_ROOT)"; skip=$((skip+1))
fi

# ── ⓔ ft_board_env.ft_root (r385 r4 · 사건 #109675 A: nano-close·nano-spawn «사건 원장 prepared 실패») ──
board_of() {  # <cwd> <bin> [env…] → ft_root() 결과 또는 ERROR 줄
  local cwd="$1" bin="$2"; shift 2
  (cd "$cwd" && env HOME="$H" "$@" python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_board_env as e
try: print(e.ft_root())
except RuntimeError as x: print("ERROR", x)' "$bin" 2>&1)
}
BEFORE_E="$(snap)"
eq "$(board_of "$FX" "$LB")" "$FX" "ⓔ ft_root 설치본 · cwd=리포 → git 공용 루트(.fable-team/LIVE_BIN)"
eq "$(board_of "$FX/sub/dir" "$LB")" "$FX" "ⓔ ft_root 설치본 · cwd=리포 하위 폴더 → 공용 루트"
r="$(board_of "$NOGIT" "$LB")"; case "$r" in ERROR*) ok "ⓔ ft_root 설치본 · cwd=git 밖 → raise";; *) bad "ⓔ ft_root git 밖 raise 아님 «${r}»";; esac
eq "$(board_of "$NOGIT" "$LB" FT_ROOT=/x/root)" "/x/root" "ⓔ ft_root FT_ROOT 명시 → 그 값 그대로(LIVE_BIN 검사 0)"
eq "$(board_of "$NOGIT" "$FX/.fable-team/bin")" "$FX" "ⓔ ft_root 옛 설치 꼴 · cwd=git 밖 → git -C HERE 공용 루트(회귀 0)"
(cd "$NOGIT" && HOME="$H" bash "$LB/ft-sheet-events.sh" pending >/dev/null 2>"$T/e4"); rc=$?
[ "$rc" != 0 ] && grep -q '루트를 못 풂' "$T/e4" && ok "ⓔ ft-sheet-events.sh 설치본 · cwd=git 밖 → rc=$rc + 사유" || bad "ⓔ sheet-events git 밖 rc=$rc «$(head -c 200 "$T/e4")»"
SK="$(cd "$FX" && HOME="$H" bash "$LB/ft-sheet-events.sh" key spawn r4-fx 'byz-x-nano-r4-fx#0' 2>"$T/e5")"
(cd "$FX" && HOME="$H" bash "$LB/ft-sheet-events.sh" prepare "$SK" '{"ev":"spawn","team":"harness","id":"r4-fx","seat":"byz-x-nano-r4-fx#0","ref":"x.md","by":"t"}' >/dev/null 2>>"$T/e5"); rc=$?
[ -n "$SK" ] && [ "$rc" = 0 ] && ok "ⓔ spawn 경로(ft-nano-spawn.sh:251 꼴) 설치본 · cwd=리포 → key+prepare rc0" || bad "ⓔ spawn 경로 key=«${SK}» prepare rc=$rc «$(head -c 200 "$T/e5")»"
(cd "$FX" && HOME="$H" bash "$LB/ft-sheet-events.sh" abort "$SK" >/dev/null 2>&1)
[ "$(snap)" = "$BEFORE_E" ] && ok "ⓔ 임시 HOME 밑 새 파일 0" || bad "ⓔ 임시 HOME 에 새 파일: $(comm -13 <(printf '%s\n' "$BEFORE_E") <(snap) | head -3 | tr '\n' ' ')"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) · skip=$skip =="
[ $fail = 0 ]
