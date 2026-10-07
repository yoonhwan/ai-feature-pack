#!/usr/bin/env bash
# test_live_bin_drift_check.sh — 카드 live-bin-drift-check (Issue 816 ②③): 라이브 bin ↔ origin/main 키트 드리프트 검사 + spawn·close 입구 BLOCK + tick 경고.
# mktemp 만 쓴다(bare 원격 + 클론 + 설치 꼴 <x>/.fable-team/bin) — 실제 리포·라이브 폴더·네트워크 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

for f in ft-live-bin-drift-check.sh ft-nano-spawn.sh ft-nano-close.sh ft-tick.sh; do
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

# ── 키트 꼴 원격: 가짜 2파일(a.sh 755 · b.sh 644) + 실제 검사·spawn·close·tick 4파일 ──
KP="scripts/harness-install/fable-team/bin"
ORIGIN="$T/origin.git"; SEED="$T/seed"; CLONE="$T/clone"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$SEED"; mkdir -p "$SEED/$KP"
printf '#!/bin/sh\necho a\n' > "$SEED/$KP/a.sh"; chmod 755 "$SEED/$KP/a.sh"
printf 'data b\n' > "$SEED/$KP/b.sh"; chmod 644 "$SEED/$KP/b.sh"
for f in ft-live-bin-drift-check.sh ft-nano-spawn.sh ft-nano-close.sh ft-tick.sh; do cp -p "$SRC/$f" "$SEED/$KP/$f"; done
git -C "$SEED" add -A && git -C "$SEED" -c user.email=t@t -c user.name=t commit -q -m kit
git -C "$SEED" remote add origin "$ORIGIN" && git -C "$SEED" push -q origin main
git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
LIVE="$T/.fable-team/bin"
fresh_live() { rm -rf "$LIVE"; mkdir -p "$LIVE"; for f in "$CLONE/$KP"/*; do cp -p "$f" "$LIVE/"; done; }
CHK() { bash "$LIVE/ft-live-bin-drift-check.sh" "$@"; }
FILES="$(ls "$CLONE/$KP" | wc -l | tr -d ' ')"

# ── 검사 스크립트 ──
fresh_live
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?
rc_is "$rc" 0 "같은 바이트·모드 → OK"; has "$out" "OK ref=origin/main@" "OK 줄 형식"; has "$out" "files=$FILES" "OK files=$FILES"
OKLINE="$out"

echo "# a" >> "$LIVE/a.sh"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?
rc_is "$rc" 1 "바이트 1개 바꿈 → DRIFT"; has "$out" "DRIFT n=1 ref=origin/main@" "DRIFT 첫 줄"; has "$out" "DIFF a.sh" "DIFF 항목"; has "$out" "HINT master 라이브 cp 필요" "HINT 줄"
DRIFTLINE="$(printf '%s\n' "$out" | head -1)"

fresh_live; rm "$LIVE/b.sh"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?; rc_is "$rc" 1 "하나 지움"; has "$out" "MISSING b.sh" "MISSING 항목"

fresh_live; chmod 644 "$LIVE/a.sh"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?; rc_is "$rc" 1 "실행 비트 제거"; has "$out" "MODE a.sh" "MODE 항목(755 기대)"
fresh_live; chmod 755 "$LIVE/b.sh"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?; rc_is "$rc" 1 "실행 비트 추가"; has "$out" "MODE b.sh" "MODE 항목(644 기대)"

fresh_live; echo x > "$LIVE/new.sh"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?; rc_is "$rc" 1 "새 파일"; has "$out" "EXTRA new.sh" "EXTRA 항목"

fresh_live; echo x > "$LIVE/x.sh.bak-1007"; mkdir "$LIVE/__pycache__"; echo y > "$LIVE/__pycache__/z.pyc"
out="$(CHK --bin "$LIVE" --repo "$CLONE")"; rc=$?; rc_is "$rc" 0 ".bak*·폴더 제외 → 여전히 OK"

out="$(CHK --bin "$LIVE" --repo "$CLONE" --ref nope/main)"; rc=$?; rc_is "$rc" 3 "풀 수 없는 ref → ERROR"; has "$out" "ERROR" "ERROR 줄(조용한 통과 아님)"
out="$(CHK --repo "$CLONE" 2>&1)"; rc=$?; rc_is "$rc" 2 "--bin 없음 → usage"
out="$(CHK --bin "$T/없는폴더" --repo "$CLONE")"; rc=$?; rc_is "$rc" 3 "bin 폴더 없음 → ERROR"
out="$(CHK --bin "$LIVE")"; rc=$?; rc_is "$rc" 3 "git 밖 bin + --repo 없음 → ERROR(추측 0)"

# ── spawn 입구 ──
fresh_live; echo "# a" >> "$LIVE/a.sh"
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$LIVE/ft-nano-spawn.sh" design/x/indices/대기/none.md --dry-run 2>&1)"; rc=$?
rc_is "$rc" 1 "spawn --dry-run 어긋남 → BLOCK"; has "$out" "REJECT 라이브 도구가" "spawn REJECT 줄"; has "$out" "DIFF a.sh" "spawn 에 항목 줄 노출"
SPAWNREJ="$(printf '%s\n' "$out" | grep '^REJECT 라이브 도구가')"
fresh_live
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$LIVE/ft-nano-spawn.sh" design/x/indices/대기/none.md --dry-run 2>&1)"
has "$out" "OK ref=origin/main@" "spawn 어긋남 0 → 검사 통과 줄"; hasnt "$out" "REJECT 라이브 도구가" "spawn 어긋남 0 → 입구 REJECT 없음"
rm "$LIVE/ft-live-bin-drift-check.sh"   # 설치 누락(검사 스크립트 없음) = 같은 REJECT
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$LIVE/ft-nano-spawn.sh" design/x/indices/대기/none.md --dry-run 2>&1)"; rc=$?
rc_is "$rc" 1 "검사 스크립트 없음 → BLOCK"; has "$out" "REJECT 라이브 도구가" "설치 누락도 같은 REJECT"
mkdir -p "$T/bin"; cp "$SRC/ft-nano-spawn.sh" "$T/bin/"
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$T/bin/ft-nano-spawn.sh" design/x/indices/대기/none.md --dry-run 2>&1)"
has "$out" "INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $T/bin" "spawn 설치 꼴 아님 → 건너뜀"; hasnt "$out" "REJECT 라이브 도구가" "spawn 설치 꼴 아님 → REJECT 없음"

# ── close 입구 ──
fresh_live; echo "# a" >> "$LIVE/a.sh"
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$LIVE/ft-nano-close.sh" zz-seat --result x --recv 1 2>&1)"; rc=$?
rc_is "$rc" 1 "close 어긋남 → BLOCK"; has "$out" "REJECT 라이브 도구가" "close REJECT 줄"
cp "$SRC/ft-nano-close.sh" "$T/bin/"
out="$(cd "$CLONE" && FT_NANO_PREFIX=zz- bash "$T/bin/ft-nano-close.sh" other-seat --result x --recv 1 2>&1)"
has "$out" "INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $T/bin" "close 설치 꼴 아님 → 건너뜀"; hasnt "$out" "REJECT 라이브 도구가" "close 설치 꼴 아님 → 라이브 REJECT 없음"

# ── tick ──
fresh_live
printf '{"m#1":{"role":"master","agent":"claude","tick":"ft-master-tick"}}\n' > "$T/seats.json"
printf '#!/bin/bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/fakembox.sh"; chmod +x "$T/fakembox.sh"
TICK() { (cd "$CLONE" && FT_TICK_SEATS="$T/seats.json" FT_TICK_STATE_DIR="$T/state" FT_TICK_MBOX="$T/fakembox.sh" FT_TICK_PIDFILE="$T/tick.pid" \
  FT_TICK_DRIFT_INTERVAL=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_STALL_INTERVAL=99999999 FT_TICK_GOAL_INTERVAL=99999999 bash "$LIVE/ft-tick.sh" --once 2>&1); }
sends() { grep -c '\[drift\]' "$T/mbox.log" 2>/dev/null || echo 0; }
out="$(TICK)"
hasnt "$out" "drift:" "tick 어긋남 0 → drift 로그 0"; [ "$(sends)" = 0 ] && ok "tick 어긋남 0 → 송신 0" || bad "tick 어긋남 0 → 송신 $(sends)"
echo "# a" >> "$LIVE/a.sh"
t1="$(TICK)"; has "$t1" "drift: n=1 ref=origin/main@" "tick 어긋남 → drift 로그"
[ "$(sends)" = 1 ] && ok "tick 1회차 송신 1" || bad "tick 1회차 송신 $(sends)"
t2="$(TICK)"; has "$t2" "drift: n=1" "tick 2회차도 매 회 로그 1줄"
[ "$(sends)" = 1 ] && ok "같은 서명 → 송신 추가 0" || bad "같은 서명인데 송신 $(sends)"
echo x > "$LIVE/new.sh"
t3="$(TICK)"; has "$t3" "drift: n=2" "항목 바뀜 → n=2 로그"
[ "$(sends)" = 2 ] && ok "목록 바뀜 → 송신 1회 추가" || bad "목록 바뀜 송신 $(sends)"
[ -f "$T/state/drift.sig" ] && ok "서명 파일 존재" || bad "서명 파일 없음"
d="$(cd "$CLONE" && FT_TICK_SEATS="$T/seats.json" FT_TICK_MBOX="$T/fakembox.sh" bash "$LIVE/ft-tick.sh" --dry-run 2>&1)"
has "$d" "DRY kind=drift bin=$LIVE rc=1" "--dry-run → DRY kind=drift 1줄"; [ "$(sends)" = 2 ] && ok "--dry-run 송신 0" || bad "--dry-run 송신 $(sends)"
off="$(cd "$CLONE" && FT_TICK_DRIFT=0 FT_TICK_STATE_DIR="$T/state-off" FT_TICK_SEATS="$T/seats.json" FT_TICK_MBOX="$T/fakembox.sh" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_STALL_INTERVAL=99999999 FT_TICK_GOAL_INTERVAL=99999999 FT_TICK_DRIFT_INTERVAL=0 bash "$LIVE/ft-tick.sh" --once 2>&1)"
hasnt "$off" "drift:" "FT_TICK_DRIFT=0 → 검사 안 함"
fresh_live
t4="$(TICK)"; has "$t4" "drift: OK" "복구 → drift: OK 로그"; [ -f "$T/state/drift.sig" ] && bad "복구 뒤 서명 파일 남음" || ok "복구 → 서명 파일 삭제"
t5="$(TICK)"; hasnt "$t5" "drift:" "복구 뒤 로그 0"
rm -f "$LIVE/ft-live-bin-drift-check.sh"
t6="$(TICK)"; hasnt "$t6" "drift:" "검사 스크립트 없음 → drift 로그 없이 stderr 경고만"; has "$t6" "drift_watch: missing" "검사 스크립트 없음 → 경고 1줄"

echo "--- 증거 3줄"
echo "$OKLINE"; echo "$DRIFTLINE"; echo "$SPAWNREJ"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
