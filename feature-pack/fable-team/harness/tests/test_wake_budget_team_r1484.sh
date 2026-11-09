#!/usr/bin/env bash
# test_wake_budget_team_r1484.sh — r1484: 깨움 예산 «팀 키» = ①명부 entry.team ②좌석명 byz-<팀>-… 둘째 토큰 ③none
#  고치기 전: _wg_team 이 «명부에 team 이 없다» 를 «한 팀(default)» 으로 읽어 전 좌석을 _team-default.json 에 합산했다.
#             명부 team 이 0건(11-09 실측)이라 팀 상한 30 이 기관 전체 상한이 됐고, 09:53 소진 뒤 전 팀의 doorbell·ring 이 창 끝까지 막혔다(#275004).
#  격리: 임시 박스(<박스>/.fable-team/{comm,state}) · 임시 명부(FT_SEATS_JSON) · 가짜 시계 FT_MBOX_NOW · 실 우편함·실 장부 0.
#  T1 명부 entry.team 이 좌석명보다 이긴다        · T2 team 없음 + 규약 이름 → 이름 둘째 토큰이 팀
#  T3 팀 장부는 팀마다 따로 센다                  · T4 규약 밖 이름 = none(팀 상한 없이 좌석 상한만)
#  T5 명부 파일 없음 ≠ default                    · T6 _wg_team 본문에 문자열 default 0
set -uo pipefail
# ★상한 «동작» 시험은 상한을 스스로 소유한다(r1499 · 선례 test_mbox_doorbell_sh_tail_r1039.sh:57)★
#   기본값이 100000 으로 올라갔으므로(mbox_wakebudget.sh:76) 상한 시험은 6/30 을 env 로 명시 고정한다.
export FT_MBOX_WAKE_SEAT_MAX=6 FT_MBOX_WAKE_TEAM_MAX=30
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
reserve() {  # <좌석> → OUT(예약 stdout) · RC · ERR
  OUT="$(FT_MBOX_NOW="$NOW" bash "$C/mbox.sh" budget reserve "$1" send 2>"$BOX/err")"; RC=$?
  ERR="$(cat "$BOX/err" 2>/dev/null)"
  return 0
}
bn() { sed -n 's/.*"n": *\([0-9]*\).*/\1/p' "$(BD)/$1.json" 2>/dev/null; }
teamfiles() { ls "$(BD)" 2>/dev/null | grep -c '^_team-'; }
nodefault() { [ ! -e "$(BD)/_team-default.json" ] && ok "$1" || bad "$1" "default 장부가 생겼다"; }

# ── T1: 명부 entry.team=room 이 좌석명 byz-harness-… 보다 이긴다 ────────────────────────────────
B1="$(mkbox t1)"; use "$B1"
cat > "$T/seats-t1.json" <<'EOF'
{"byz-harness-arch-claude#1":{"agent":"claude","team":"room","tick":null}}
EOF
export FT_SEATS_JSON="$T/seats-t1.json"
reserve "byz-harness-arch-claude#1"
eq "T1 rc0" "$RC" 0
eq "T1 stdout reserved n=1 team=1" "$OUT" "reserved n=1 team=1"
eq "T1 팀 장부 = room" "$(bn _team-room)" 1
eq "T1 이름 파싱 팀(harness) 장부 0" "$(bn _team-harness)" ""
nodefault "T1 _team-default.json 없음"

# ── T2: 명부에 team 없음 + 규약 이름 → 좌석명 둘째 토큰이 팀 ───────────────────────────────────
B2="$(mkbox t2)"; use "$B2"
printf '%s\n' '{"byz-harness-arch-claude#1":{"agent":"claude","tick":null}}' > "$T/seats-t2.json"
export FT_SEATS_JSON="$T/seats-t2.json"
reserve "byz-harness-arch-claude#1"
eq "T2 rc0" "$RC" 0
eq "T2 stdout reserved n=1 team=1" "$OUT" "reserved n=1 team=1"
eq "T2 팀 장부 = harness n=1" "$(bn _team-harness)" 1
nodefault "T2 _team-default.json 없음(«모르면 한 팀» 치환 0)"
grep -q 'team=harness/1' "$(BD)/_ledger.log" 2>/dev/null && ok "T2 원장 1행에 team=harness/1" || bad "T2 원장 1행에 team=harness/1" "$(cat "$(BD)/_ledger.log" 2>/dev/null)"

# ── T3: 팀 장부 분리 — harness 30 소진 뒤에도 issues 예약은 rc0 ───────────────────────────────
B3="$(mkbox t3)"; use "$B3"
printf '%s\n' '{"byz-harness-w1#1":{},"byz-harness-w2#1":{},"byz-harness-w3#1":{},"byz-harness-w4#1":{},"byz-harness-w5#1":{},"byz-harness-w6#1":{},"byz-issues-x#1":{},"byz-room-y#1":{}}' > "$T/seats-t3.json"
export FT_SEATS_JSON="$T/seats-t3.json"
for s in w1 w2 w3 w4 w5; do              # harness 5석 × 6통 = 팀 30/창(좌석 상한 6 은 안 넘는다)
  for i in 1 2 3 4 5 6; do
    NOW=$((NOW + 5)); reserve "byz-harness-$s#1"
    [ "$RC" = 0 ] || bad "T3 harness-$s $i 통 rc0 (OUT=$OUT)"
  done
done
eq "T3 harness 팀 장부 n=30" "$(bn _team-harness)" 30
NOW=$((NOW + 5)); reserve "byz-harness-w6#1"   # 새 좌석(좌석 n=0)이라 «팀» 상한이 먼저 걸린다
eq "T3 harness 31통째 rc3" "$RC" 3
eq "T3 harness 31통째 exhausted team" "$OUT" "exhausted team n=30"
NOW=$((NOW + 5)); reserve "byz-issues-x#1"
eq "T3 issues 예약 rc0(팀 장부 분리)" "$RC" 0
eq "T3 issues stdout reserved n=1 team=1" "$OUT" "reserved n=1 team=1"
eq "T3 issues 팀 장부 n=1" "$(bn _team-issues)" 1
eq "T3 harness 장부 불변 30" "$(bn _team-harness)" 30
eq "T3 팀 장부 파일 2개(harness·issues)" "$(teamfiles)" 2
nodefault "T3 _team-default.json 없음"

# ── T4: 이름 규약 밖 = team=none — 팀 장부 0 · 좌석 상한만(7회째 exhausted seat) ───────────────
B4="$(mkbox t4)"; use "$B4"
printf '%s\n' '{"astra-da#0":{},"x":{}}' > "$T/seats-t4.json"
export FT_SEATS_JSON="$T/seats-t4.json"
reserve "astra-da#0"
eq "T4 규약 밖 rc0" "$RC" 0
eq "T4 stdout team=none" "$OUT" "reserved n=1 team=none"
eq "T4 팀 장부 파일 0" "$(teamfiles)" 0
reserve "x"
eq "T4 두 글자 이름도 team=none" "$OUT" "reserved n=1 team=none"
eq "T4 x 좌석 장부만 n+1" "$(bn x)" 1
for i in 2 3 4 5 6; do
  NOW=$((NOW + 5)); reserve "astra-da#0"
  [ "$RC" = 0 ] || bad "T4 astra-da#0 $i 통 rc0 (OUT=$OUT)"
done
NOW=$((NOW + 5)); reserve "astra-da#0"
eq "T4 7회째 exhausted seat(좌석 상한 6 은 그대로)" "$OUT" "exhausted seat n=6"
eq "T4 7회째 rc3" "$RC" 3
eq "T4 astra-da#0 좌석 장부 n=6" "$(bn "astra-da#0")" 6
eq "T4 팀 장부 파일 여전히 0" "$(teamfiles)" 0
nodefault "T4 _team-default.json 없음"

# ── T5: 명부 파일 없음 ≠ default — 규약 이름이면 T2 와 같다 ───────────────────────────────────
B5="$(mkbox t5)"; use "$B5"
export FT_SEATS_JSON="$T/없는명부-r1484.json"
rm -f "$T/없는명부-r1484.json"
reserve "byz-harness-arch-claude#1"
eq "T5 명부 없음 rc0" "$RC" 0
eq "T5 stdout reserved n=1 team=1" "$OUT" "reserved n=1 team=1"
eq "T5 팀 장부 = harness n=1" "$(bn _team-harness)" 1
nodefault "T5 _team-default.json 없음(파일 없음 ≠ default)"
reserve "이름규약밖#9"
eq "T5 명부 없음 + 규약 밖 = team=none" "$OUT" "reserved n=1 team=none"
eq "T5 규약 밖 팀 장부 0" "$(teamfiles)" 1

# ── T6: _wg_team 본문에 «default» 라는 치환 0 (grep -c) ───────────────────────────────────────
wg="$(sed -n '/^_wg_team()/,/^}/p' "$COMM/mbox_wakebudget.sh")"
eq "T6 _wg_team 본문 default 문자열 0" "$(grep -c 'default' <<<"$wg")" 0

echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
