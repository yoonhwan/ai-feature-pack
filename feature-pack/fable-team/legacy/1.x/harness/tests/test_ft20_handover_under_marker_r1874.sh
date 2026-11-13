#!/usr/bin/env bash
# test_ft20_handover_under_marker_r1874.sh — r1874: 2.0 표식 아래 «같은 계보 역할 좌석» 교대는 표식을 내리지 않고 통과한다.
#   반례 ①~⑩(카드 그대로) + 변이 M1~M4(사본 lib 에서만) · 실 명부·실 표식·실 ft2 원장 쓰기 0 — 임시 루트(FT_FT20_ROOT) + 도구 사본만
#   tmux·reap·quiesce·ft2 cli = 스텁(가짜 세계) · HOME = 임시 · press 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$HERE/../bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
K="$T/kit"; R="$T/root"; S="$T/stub"; SW="$R/.fable-team/state/ft20-switch"
fail=0; n=0; t0="$(date +%s)"
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
mkdir -p "$K" "$S" "$T/home" "$R/.fable-team"; git -C "$R" init -q
for f in ft20-switch-lib.sh ft-name-lint.sh ft-seat-retire.sh ft-successor-open.sh; do cp -p "$H/$f" "$K/$f"; done; cp -p "$H"/ft_*.py "$K/"
printf '#!/bin/sh\nexit 1\n' > "$S/tmux"; printf '#!/bin/sh\necho left=0\n' > "$S/reap"; printf '#!/bin/sh\nexit 0\n' > "$S/q"; chmod +x "$S"/*
export PATH="$S:$PATH" HOME="$T/home" FT_FT20_ROOT="$R" FT2_CLI=/nonexistent FT_SEAT_REAP_BIN="$S/reap" FT_SEAT_QUIESCE_BIN="$S/q" FT_TMUX="$S/tmux" FT20_AUTONOMY_BIN=/nonexistent
A5='byz-harness-arch-pi#335'; A6='byz-harness-arch-pi#336'; AC='byz-harness-arch-claude#209'; P4='byz-planner-arch-pi#4'
N0='byz-harness-nano-r1799-x#0'; N1='byz-harness-nano-r1799-x#1'
world() {   # world <구 좌석> [marker|broken|none] — 명부·표식 새로
  rm -rf "$SW" "$R/.fable-team"/seats*.json*; mkdir -p "$SW"
  printf '{"_%s":"%s","%s":{"role":"%s"}}\n' "$(echo "$1" | cut -d- -f3)" "$1" "$1" "$(echo "$1" | cut -d- -f3)" > "$R/.fable-team/seats-harness.json"
  case "${2:-marker}" in
    marker) printf '{"team":"harness","switched_at":"2026-11-13T00:00:00+0900","h":"8260","by":"fx"}\n' > "$SW/harness.json";;
    broken) printf '{"team":"harness",' > "$SW/harness.json";;
  esac
}
hsh() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
bak() { ls "$SW"/*.json.unmarked-* 2>/dev/null | grep -c .; }
retire() { ( cd "$R" && FT_SEATS_JSON="$R/.fable-team/seats-harness.json" bash "${KD:-$K}/ft-seat-retire.sh" "$@" ) >"$T/o" 2>&1; RC=$?; }
sopen() { ( cd "$R" && bash "$K/ft-successor-open.sh" "$1" "$R" --name "$2" --agent pi ) >"$T/o" 2>&1; RC=$?; }   # 가드 뒤 usage(rc2)에서 멈춘다 = 개설 0

# ① 같은 계보 arch 승계 + 표식 → RETIRED rc0 · 표식 sha 그대로 · 보관본 0
world "$A5"; s0="$(hsh "$SW/harness.json")"; retire "$A5" "$A6"
ck "① $A5 → #336 retire rc=$RC · RETIRED · 표식 sha 그대로 · 보관본 $(bak)" \
  "$([ "$RC" = 0 ] && grep -q "^RETIRED $A5 -> $A6" "$T/o" && grep -q 'INFO 2.0 표식 아래 같은 계보 승계 허용 팀 harness h8260' "$T/o" && [ "$(hsh "$SW/harness.json")" = "$s0" ] && [ "$(bak)" = 0 ] && echo 0 || echo 1)"
# ② successor-open 가드 → 통과(뒤 usage rc2 · 표식 REJECT 0)
world "$A5"; sopen "$A5" "$A6"
ck "② successor-open 가드 통과 rc=$RC(usage 2 · 표식 REJECT 0)" "$([ "$RC" = 2 ] && ! grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"
# ③ 계보 다름(에이전트 바뀜) → rc3
world "$AC"; retire "$AC" "$A6"; ck "③ 계보 다름 $AC → $A6 rc=$RC(3)" "$([ "$RC" = 3 ] && grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"
# ④ 번호 역행 → rc3
world "$A6"; retire "$A6" "$A5"; ck "④ 번호 역행 #336 → #335 rc=$RC(3)" "$([ "$RC" = 3 ] && echo 0 || echo 1)"
# ⑤ 팀 다름 → rc3
world "$A5"; retire "$A5" "$P4"; ck "⑤ 팀 다름 $A5 → $P4 rc=$RC(3)" "$([ "$RC" = 3 ] && echo 0 || echo 1)"
# ⑥ 구 이름이 다른 팀 명부 `_*` 칸 값 → rc3
world "$A5"; printf '{"_arch":"%s"}\n' "$A5" > "$R/.fable-team/seats-planner.json"; retire "$A5" "$A6"
ck "⑥ 구 이름이 planner 명부 _arch 값 rc=$RC(3)" "$([ "$RC" = 3 ] && echo 0 || echo 1)"
# ⑦ 표식 깨진 JSON → rc3 «판정 불가»
world "$A5" broken; retire "$A5" "$A6"; ck "⑦ 깨진 표식 rc=$RC(3 · 판정 불가)" "$([ "$RC" = 3 ] && grep -q '판정 불가' "$T/o" && echo 0 || echo 1)"
# ⑧ 표식 없는 팀 → 지금 그대로(RETIRED rc0 · 허용 INFO 0) · 교대 창(A<N> 보관본 · 자율 도구 없음) → rc2 그대로
world "$A5" none; retire "$A5" "$A6"
ck "⑧ 표식 없음 retire rc=$RC · RETIRED · 허용 INFO 0" "$([ "$RC" = 0 ] && grep -q '^RETIRED' "$T/o" && ! grep -q '같은 계보 승계 허용' "$T/o" && echo 0 || echo 1)"
world "$A5" none; printf '{"team":"harness","h":"A17"}\n' > "$SW/harness.json.unmarked-20261113T000000"; retire "$A5" "$A6"
ck "⑧-b 교대 창(A17 보관본) ft20_window_guard rc=$RC(2 그대로)" "$([ "$RC" = 2 ] && echo 0 || echo 1)"
# ⑨ --record-only 길 → 가드 손 0(표식 REJECT·허용 INFO 둘 다 0)
world "$A5"; retire "$A5" --record-only
ck "⑨ --record-only rc=$RC · 표식 가드 안 탐" "$([ "$RC" != 3 ] && ! grep -q '2.0 전환됨\|같은 계보 승계 허용' "$T/o" && echo 0 || echo 1)"
# ⑩ 같은 계보 nano 승계 → rc3 그대로
world "$N0"; retire "$N0" "$N1"; ck "⑩ nano 승계 $N0 → #1 rc=$RC(3)" "$([ "$RC" = 3 ] && grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"

# ── 변이(사본 폴더에서만 · 실 파일 치환 0) — 새면(rc0) 검출 ────────────────
mut() {  # mut <이름> <원문> <바꿀 글>
  KD="$T/mut-$1"; rm -rf "$KD"; cp -Rp "$K" "$KD"
  python3 - "$KD/ft20-switch-lib.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mut M1 '[ "${old%#*}" = "${new%#*}" ]' 'true'
world "$AC"; retire "$AC" "$A6"; ck "M1 계보 비교 빼기 → ③ 새어 rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
mut M2 '[ "$((10#$nn))" -gt "$((10#$on))" ]' 'true'
world "$A6"; retire "$A6" "$A5"; ck "M2 번호 비교 빼기 → ④ 새어 rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
mut M3 '[ "$teams" = "$team" ]' 'true'
world "$A5"; printf '{"_arch":"%s"}\n' "$A5" > "$R/.fable-team/seats-planner.json"; retire "$A5" "$A6"
ck "M3 단일 팀 검사 빼기 → ⑥ 새어 rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
mut M4 '[ "$(printf '"'"'%s'"'"' "${old%#*}" | cut -d- -f3)" != nano ]' 'true'
world "$N0"; retire "$N0" "$N1"; ck "M4 nano 제외 빼기 → ⑩ 새어 rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
KD=""

echo "RUN 1회차 $(( $(date +%s) - t0 ))초 · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
