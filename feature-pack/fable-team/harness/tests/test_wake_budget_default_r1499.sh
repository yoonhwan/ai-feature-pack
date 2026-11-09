#!/usr/bin/env bash
# test_wake_budget_default_r1499.sh — r1499: 깨움 예산 «기본값» = 좌석 100000 · 팀 100000 (env 없이도 옛 상한에서 안 막힌다)
#  고치기 전: mbox_wakebudget.sh:76 이 `${FT_MBOX_WAKE_SEAT_MAX:-6}` / `${FT_MBOX_WAKE_TEAM_MAX:-30}` 이라
#             env 를 주지 않는 모든 좌석이 좌석 6 · 팀 30 에서 «조용히» 막혔다(gate=budget · #275011 · #275173 · 오빠 #275187).
#  이 파일은 상한 «동작» 시험이 아니라 «기본값» 시험이다 — env 두 개를 unset 하고 옛 상한을 넘겨 본다.
#  (상한 동작 시험 = test_wake_budget_team_r1484.sh · test_mbox_doorbell_merge_r1476.sh — 상한을 env 로 소유한다)
#  격리: 임시 박스(<박스>/.fable-team/{comm,state}) · 임시 명부(FT_SEATS_JSON) · 가짜 시계 FT_MBOX_NOW · 실 우편함·실 장부 0.
#  T1 env unset · 한 좌석 7통 = 7 reserved(옛 좌석 상한 6 에서 안 막힌다) · 좌석 n=7 · exhausted 0
#  T2 env unset · 같은 팀 6석 × 6통 = 36 reserved(옛 팀 상한 30 에서 안 막힌다) · 팀 장부 n=36
#  T3 :76 상수 = 100000 두 개 · 6/30 잔재 0 (grep -o 로 «개수» 를 센다 — 두 상수가 한 줄이라 grep -c 는 1 이다)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
COMM="$HERE/../comm"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

W0=1700002800                  # 한 시각 창의 시작(472223 * 3600) — 창 경계가 결정적이도록
NOW="$W0"
BOX=""; C=""

mkbox() {  # <이름> → 새 격리 박스 경로
  local r="$T/box-$1"
  mkdir -p "$r/.fable-team/comm" "$r/.fable-team/state" "$r/tmp"
  cp "$COMM"/mbox*.sh "$COMM"/mbox*.py "$COMM"/ft-agent-alive.sh "$r/.fable-team/comm/" 2>/dev/null
  printf '%s' "$r"
}
use() {  # <박스경로> — 예산·명부 경로를 이 박스 안으로 못 박는다
  BOX="$1"; C="$BOX/.fable-team/comm"
  export FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$BOX/.fable-team/state" TMPDIR="$BOX/tmp"
  : > "$BOX/err"
}
BD() { printf '%s' "$BOX/.fable-team/state/wake-budget"; }
reserve() {  # <좌석> → OUT(예약 stdout) · RC · ERR — ★기본값을 재는 시험이므로 env 두 개를 지우고 부른다★
  OUT="$(env -u FT_MBOX_WAKE_SEAT_MAX -u FT_MBOX_WAKE_TEAM_MAX FT_MBOX_NOW="$NOW" \
         bash "$C/mbox.sh" budget reserve "$1" send 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
  return 0
}
bn() { sed -n 's/.*"n": *\([0-9]*\).*/\1/p' "$(BD)/$1.json" 2>/dev/null; }

# ── T1: 기본값 좌석 — env unset · 한 좌석 7통이 «모두» reserved (옛 상한 6 이면 7통째 exhausted seat n=6) ──
B1="$(mkbox t1)"; use "$B1"
printf '%s\n' '{"byz-harness-w1#1":{"agent":"pi","tick":null}}' > "$T/seats-t1.json"
export FT_SEATS_JSON="$T/seats-t1.json"
reserved=0; exhausted=0
for i in 1 2 3 4 5 6 7; do
  NOW=$((NOW + 5)); reserve "byz-harness-w1#1"
  case "$OUT" in
    reserved*) reserved=$((reserved + 1)) ;;
    exhausted*) exhausted=$((exhausted + 1)); bad "T1 $i 통 reserved" "$OUT (기본값이 옛 상한 6 에서 막혔다)" ;;
  esac
  [ "$RC" = 0 ] || bad "T1 $i 통 rc0" "rc=$RC OUT=$OUT"
done
eq "T1 7통 모두 reserved" "$reserved" 7
eq "T1 exhausted 0" "$exhausted" 0
eq "T1 7통째 stdout reserved n=7" "$OUT" "reserved n=7 team=7"
eq "T1 좌석 장부 n=7" "$(bn "byz-harness-w1#1")" 7
eq "T1 팀 장부 n=7" "$(bn _team-harness)" 7
# 예산이 «exhausted» 를 내지 않으면 gate 는 budget 이 될 수 없다(mbox_wakegate.sh:55 · mbox.sh:274 가 rc≠0 일 때만 budget).
eq "T1 원장 7행(예약 7회 · gate=budget 0 의 근거)" "$(grep -c 'src=send ' "$(BD)/_ledger.log" 2>/dev/null)" 7
grep -q 'exhausted' "$(BD)/_ledger.log" 2>/dev/null && bad "T1 원장에 exhausted 0" || ok "T1 원장에 exhausted 0"

# ── T2: 기본값 팀 — env unset · 같은 팀 6석 × 6통 = 36 «모두» reserved (옛 팀 상한 30 이면 31통째 exhausted team n=30) ──
B2="$(mkbox t2)"; use "$B2"
NOW="$W0"
printf '%s\n' '{"byz-harness-a#1":{},"byz-harness-b#1":{},"byz-harness-c#1":{},"byz-harness-d#1":{},"byz-harness-e#1":{},"byz-harness-f#1":{}}' > "$T/seats-t2.json"
export FT_SEATS_JSON="$T/seats-t2.json"
reserved=0; exhausted=0
for s in a b c d e f; do
  for i in 1 2 3 4 5 6; do
    NOW=$((NOW + 5)); reserve "byz-harness-$s#1"
    case "$OUT" in
      reserved*) reserved=$((reserved + 1)) ;;
      exhausted*) exhausted=$((exhausted + 1)); bad "T2 harness-$s $i 통 reserved" "$OUT (기본값이 옛 팀 상한 30 에서 막혔다)" ;;
    esac
  done
done
eq "T2 36통 모두 reserved" "$reserved" 36
eq "T2 exhausted 0" "$exhausted" 0
eq "T2 팀 장부 n=36(옛 상한 30 초과)" "$(bn _team-harness)" 36
eq "T2 마지막 좌석 n=6" "$(bn "byz-harness-f#1")" 6
eq "T2 원장 36행" "$(grep -c 'src=send ' "$(BD)/_ledger.log" 2>/dev/null)" 36

# ── T3: :76 상수 두 개가 100000 — 옛 6/30 문자열 잔재 0 ──────────────────────────────────────────
WB="$COMM/mbox_wakebudget.sh"
eq "T3 :76 기본값 100000 두 개" "$(sed -n '76p' "$WB" | grep -o ':-100000}' | grep -c .)" 2
eq "T3 파일 전체 6/30 기본값 잔재 0" "$(grep -o ':-6}\|:-30}' "$WB" | grep -c .)" 0

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
