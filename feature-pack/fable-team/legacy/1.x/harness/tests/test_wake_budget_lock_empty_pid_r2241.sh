#!/usr/bin/env bash
# test_wake_budget_lock_empty_pid_r2241.sh — r2241: 깨움 예산 잠금(.lock)에 pid 가 비었거나 숫자가 아니면 나이로 판정한다.
#  고치기 전: _wg_lock 이 빈 pid 를 «아무것도 안 함» 으로 넘겨, mkdir 와 pid 쓰기 사이에 죽은 잠금이 영원히 남았다(11-18 12:17 lock-timeout 74줄).
#  격리: 임시 박스(<박스>/.fable-team/{comm,state}) · 가짜 시계 FT_MBOX_NOW · mtime = touch -t · 가짜 stat(PATH) · 실 우편함·실 장부 0 · sleep 0.
#  ① 빈 .lock 120초 → 풂 rc0       · ② 빈 .lock 5초 → 상한 rc1 · 폴더 남음
#  ③ 죽은 숫자 pid 풂 · 산 pid 상한  · ④ pid «abc» 120초 → ① 과 같음
#  ⑧ stat rc1 → 풀기 0 상한 rc1 / 확인 사이 폴더 사라짐 → rc0 · 남이 새로 만든 잠금 rm 0
#  두 경로 = /tmp · /private/tmp(있으면) · R2241_COMM=<comm 폴더> 로 대상 바꿈(기준판·변이 대조)
set -uo pipefail
export FT_MBOX_WAKE_LOCK_TRIES=3
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="${R2241_COMM:-$HERE/../comm}"
fail=0; T=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "기대 '$3' 실제 '$2'"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "'$3' 없음 :: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "'$3' 있음 :: $2" ;; *) ok "$1" ;; esac; }
stamp() { date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S; }
NOW=1700002800
SEAT="byz-harness-nano-t#0"

use() {  # <이름> → 새 격리 박스 · BD = 예산 폴더 · L = 잠금
  BOX="$T/box-$1"; C="$BOX/.fable-team/comm"
  mkdir -p "$C" "$BOX/.fable-team/state/wake-budget" "$BOX/tmp" "$BOX/bin"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$C/" 2>/dev/null
  export FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" TMPDIR="$BOX/tmp"
  BD="$BOX/.fable-team/state/wake-budget"; L="$BD/.lock"
}
lock() {  # <나이 초> [pid 내용] — 잠금 폴더 + mtime
  mkdir -p "$L"; [ -z "${2:-}" ] || printf '%s' "$2" > "$L/pid"
  touch -t "$(stamp $(( $(date +%s) - $1 )))" "$L"
}
reserve() {  # → OUT · RC · ERR · LOG
  OUT="$(PATH="$BOX/bin:$PATH" FT_MBOX_NOW="$NOW" bash "$C/mbox.sh" budget reserve "$SEAT" send 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err")"; LOG="$(cat "$BD/_errors.log" 2>/dev/null)"
}
TIMEOUT="ERROR 예산 잠금 10초 초과 —"

run() {  # <경로 바탕>
  local base="$1" s
  T="$(mktemp -d "$base/r2241.XXXXXX")"
  s=$(date +%s)
  use c1; lock 120; reserve
  eq "①[$base] rc0" "$RC" 0; has "①[$base] reserved" "$OUT" "reserved n=1"
  has "①[$base] WARN" "$ERR" "WARN 예산 잠금 빈 pid 12"; has "①[$base] errlog" "$LOG" "lock-stale-empty age=12"
  eq "①[$base] errlog 1줄" "$(grep -c lock-stale-empty "$BD/_errors.log" 2>/dev/null)" 1
  use c2; lock 5; reserve
  eq "②[$base] rc1" "$RC" 1; has "②[$base] 문구" "$OUT" "$TIMEOUT $BD/.lock"
  [ -d "$L" ] && ok "②[$base] 폴더 남음" || bad "②[$base] 폴더 남음"; hasnt "②[$base] WARN 0" "$ERR" "빈 pid"
  use c3a; dead="$(bash -c 'echo $$')"; lock 5 "$dead"; reserve
  eq "③[$base] 죽은 pid rc0" "$RC" 0; eq "③[$base] 죽은 pid WARN" "$ERR" "WARN 예산 잠금 죽은 보유 pid $dead 해제 — $L"
  use c3b; lock 120 "$$"; reserve
  eq "③[$base] 산 pid rc1" "$RC" 1; eq "③[$base] 산 pid 문구" "$OUT" "$TIMEOUT $BD/.lock"; eq "③[$base] 산 pid 남음" "$(cat "$L/pid")" "$$"
  use c4; lock 120 abc; reserve
  eq "④[$base] rc0" "$RC" 0; has "④[$base] WARN" "$ERR" "WARN 예산 잠금 빈 pid 12"; has "④[$base] errlog" "$LOG" "lock-stale-empty age=12"
  use c8a; printf '#!/bin/sh\nexit 1\n' > "$BOX/bin/stat"; chmod +x "$BOX/bin/stat"; lock 120; reserve
  eq "⑧[$base] stat rc1 → rc1" "$RC" 1; has "⑧[$base] 문구" "$OUT" "$TIMEOUT $BD/.lock"
  [ -d "$L" ] && ok "⑧[$base] 풀기 0" || bad "⑧[$base] 풀기 0"; hasnt "⑧[$base] errlog 0" "$LOG" "lock-stale-empty"
  use c8b; printf '#!/bin/sh\nfor a; do d="$a"; done\nrm -rf "$d"\nexit 1\n' > "$BOX/bin/stat"; chmod +x "$BOX/bin/stat"; lock 120; reserve
  eq "⑧[$base] 사라짐 → 다음 바퀴 rc0" "$RC" 0; hasnt "⑧[$base] 사라짐 WARN 0" "$ERR" "빈 pid"
  use c8c; printf '#!/bin/sh\nfor a; do d="$a"; done\nrm -rf "$d"; mkdir "$d"; printf %%s "$NEWPID" > "$d/pid"\nexit 1\n' > "$BOX/bin/stat"; chmod +x "$BOX/bin/stat"; lock 120
  export NEWPID=$$; reserve; unset NEWPID
  eq "⑧[$base] 남의 새 잠금 rc1" "$RC" 1; eq "⑧[$base] 남의 새 잠금 rm 0" "$(cat "$L/pid" 2>/dev/null)" "$$"
  echo "STEP [$base] s=$(( $(date +%s) - s ))"
  rm -rf "$T"
}
trap '[ -z "$T" ] || rm -rf "$T"' EXIT
run /tmp
[ -d /private/tmp ] && run /private/tmp
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL count=$fail"; exit 1; }
