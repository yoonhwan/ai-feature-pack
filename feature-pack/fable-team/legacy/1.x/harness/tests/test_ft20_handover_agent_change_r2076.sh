#!/usr/bin/env bash
# test_ft20_handover_agent_change_r2076.sh — r2076 E1~E4: 2.0 표식 아래 승계 가드는 «에이전트 꼬리를 뺀 역할 줄기» 가 같으면 지난다.
#   반례 ①~⑤(카드 그대로) + 변이 M1~M5(사본 lib 에서만 · 변이마다 원본으로 같은 사례 1회 = 반대 결과 대조)
#   실 명부·실 표식·실 tmux·실 우편함 쓰기 0 — 임시 루트(FT_FT20_ROOT) · HOME 임시 · tmux·reap·quiesce 스텁 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
K="$T/kit"; R="$T/root"; S="$T/stub"; SW="$R/.fable-team/state/ft20-switch"
fail=0; n=0; t0="$(date +%s)"
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
RT="$(command -v tmux || true)"; tls() { [ -z "$RT" ] || "$RT" ls -F '#S' 2>/dev/null | sort; }; tl0="$(tls)"   # 실 tmux 세션 목록(스텁 PATH 앞에서 잡은 실 tmux)
mkdir -p "$K" "$S" "$T/home" "$R/.fable-team"; git -C "$R" init -q
for f in ft20-switch-lib.sh ft-name-lint.sh ft-seat-retire.sh ft-successor-open.sh; do cp -p "$H/$f" "$K/$f"; done; cp -p "$H"/ft_*.py "$K/"
printf '#!/bin/sh\nexit 1\n' > "$S/tmux"; printf '#!/bin/sh\necho left=0\n' > "$S/reap"; printf '#!/bin/sh\nexit 0\n' > "$S/q"; chmod +x "$S"/*
export PATH="$S:$PATH" HOME="$T/home" FT_FT20_ROOT="$R" FT2_CLI=/nonexistent FT_SEAT_REAP_BIN="$S/reap" FT_SEAT_QUIESCE_BIN="$S/q" FT_TMUX="$S/tmux" FT20_AUTONOMY_BIN=/nonexistent
I0='byz-issues-master-sol#60'; I1='byz-issues-master-pi#61'; A5='byz-harness-arch-pi#335'; A6='byz-harness-arch-pi#336'
world() {   # world <팀> <구 좌석> <_역할 칸 값> [marker|broken|none|raw:<글>] — 명부·표식 새로
  rm -rf "$SW" "$R/.fable-team"/seats*.json*; mkdir -p "$SW"
  printf '{"_%s":"%s","%s":{"role":"stop-ready","agent":"codex"}}\n' "$(echo "$2" | cut -d- -f3)" "$3" "$2" > "$R/.fable-team/seats-$1.json"
  case "${4:-marker}" in
    marker) printf '{"team":"%s","switched_at":"2026-11-12T00:00:00+0900","h":"1794494025.738289","by":"fx"}\n' "$1" > "$SW/$1.json";;
    broken) printf '{"team":"%s",' "$1" > "$SW/$1.json";;
    raw:*) printf '%s\n' "${4#raw:}" > "$SW/$1.json";;
  esac
}
g() { ( . "${KD:-$K}/ft20-switch-lib.sh"; ft20_guard_handover "$R" "$1" "$2" "" ) >"$T/o" 2>&1; RC=$?; }   # 가드 함수만(명부 인자 없음 = successor-open 꼴)
row() {   # row <이름> <기대 rc> <팀> <구> <후계> [<_역할 칸 값>] [표식]
  world "$3" "$4" "${6-$4}" "${7:-marker}"; g "$4" "$5"
  ck "$1 $4 → $5 rc=$RC($2)" "$([ "$RC" = "$2" ] && echo 0 || echo 1)"
}
hsh() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1; }
bak() { ls "$SW"/*.json.unmarked-* 2>/dev/null | grep -c .; }

# ① 실사건 — 가드 · retire · successor-open
world issues "$I0" ""; g "$I0" "$I1"
ck "① 가드 $I0 → $I1 rc=$RC(0) · INFO 팀 issues" "$([ "$RC" = 0 ] && grep -q '^INFO 2.0 표식 아래 같은 계보 승계 허용 팀 issues h1794494025.738289$' "$T/o" && echo 0 || echo 1)"
world issues "$I0" ""; s0="$(hsh "$SW/issues.json")"
( cd "$R" && FT_SEATS_JSON="$R/.fable-team/seats-issues.json" bash "$K/ft-seat-retire.sh" "$I0" "$I1" ) >"$T/o" 2>&1; RC=$?
ck "① retire rc=$RC(0) · 표식 sha 그대로 · 보관본 $(bak)" "$([ "$RC" = 0 ] && [ "$(hsh "$SW/issues.json")" = "$s0" ] && [ "$(bak)" = 0 ] && echo 0 || echo 1)"
world issues "$I0" ""; ( cd "$R" && bash "$K/ft-successor-open.sh" "$I0" "$R" --name "$I1" --agent pi ) >"$T/o" 2>&1; RC=$?
ck "① successor-open rc=$RC(usage 2) · «2.0 전환됨» 0" "$([ "$RC" = 2 ] && ! grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"

# ② 줄기
row "② 에이전트만 바뀜" 0 harness 'byz-harness-arch-claude#209' "$A6"
row "② 석 칸 없음 → 0" 0 harness "$A5" 'byz-harness-arch-0-pi#336'
row "② qa 범위 같음 · 에이전트 바뀜" 0 harness 'byz-harness-qa-web-codex#3' 'byz-harness-qa-web-pi#4'
row "② 석 0 → 1" 3 harness 'byz-harness-arch-0-pi#335' 'byz-harness-arch-1-pi#336'
row "② qa 범위 → 없음" 3 harness 'byz-harness-qa-web-pi#3' 'byz-harness-qa-pi#4'
row "② 역할 다름" 3 issues "$I0" 'byz-issues-arch-pi#61' ""
row "② 팀 다름" 3 issues "$I0" 'byz-planner-master-pi#61' ""
row "② 같은 계보" 0 harness "$A5" "$A6"

# ③ 구 이름 꼴
row "③ 에이전트 토큰 없음" 3 issues 'byz-issues-master#60' "$I1" ""
row "③ 대문자 꼬리" 3 issues 'byz-issues-master-Sol#60' "$I1" ""
row "③ 번호 글자" 3 issues 'byz-issues-master-sol#x' "$I1" ""
row "③ # 없음" 3 issues 'byz-issues-master-sol' "$I1" ""
row "③ 토큰 더 많음" 3 issues 'byz-issues-master-a-b-sol#60' "$I1" ""
row "③ 후계 lint 실패" 3 issues "$I0" 'byz-issues-master-sol#61' ""

# ④ 그대로인 관문
row "④ 번호 같음" 3 issues "$I0" 'byz-issues-master-pi#60' ""
row "④ 번호 역행" 3 issues "$I0" 'byz-issues-master-pi#59' ""
row "④ nano 같은 계보" 3 harness 'byz-harness-nano-r1799-x#0' 'byz-harness-nano-r1799-x#1'
row "④ nano 꼬리가 에이전트 글자" 3 harness 'byz-harness-nano-r1-codex#0' 'byz-harness-nano-r1-pi#1'
world issues "$I0" ""; printf '{"_master":"%s"}\n' "$I0" > "$R/.fable-team/seats-planner.json"; g "$I0" "$I1"
ck "④ 구 이름이 planner 명부 _master 값 rc=$RC(3)" "$([ "$RC" = 3 ] && echo 0 || echo 1)"
world issues "$I0" ""; printf '{"_master":""}\n' > "$R/.fable-team/seats-issues.json"; g "$I0" "$I1"
ck "④ 구 이름이 어느 명부의 행도 _* 값도 아님 rc=$RC(3)" "$([ "$RC" = 3 ] && echo 0 || echo 1)"
world issues "$I0" ""; printf '{"_master":"%s"}\n' "$I0" > "$R/.fable-team/seats-issues.json"; g "$I0" "$I1"
ck "④ 행 없음 · 같은 팀 _master 값만(실사건 이름) rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
world harness "$A5" "$A5"; printf '{"_arch":"%s"}\n' "$A5" > "$R/.fable-team/seats-harness.json"; g "$A5" "$A6"
ck "④ 행 없음 · 같은 팀 _arch 값만(같은 계보) rc=$RC(0)" "$([ "$RC" = 0 ] && echo 0 || echo 1)"
for v in null '[]' false 0 '""' '{}' '{"h":""}' '{"h":null}'; do
  row "④ 표식=$v 실사건" 3 issues "$I0" "$I1" "" "raw:$v"
  row "④ 표식=$v 같은 계보" 3 harness "$A5" "$A6" "$A5" "raw:$v"
done

# ⑤ 불변
world issues "$I0" "" broken; g "$I0" "$I1"
ck "⑤ 깨진 표식 rc=$RC(3 · 판정 불가)" "$([ "$RC" = 3 ] && grep -q '판정 불가' "$T/o" && echo 0 || echo 1)"
world issues "$I0" "" none; g "$I0" "$I1"
ck "⑤ 표식 없음 rc=$RC(0) · 허용 INFO 0" "$([ "$RC" = 0 ] && ! grep -q '같은 계보 승계 허용' "$T/o" && echo 0 || echo 1)"
ck "⑤ kit 사본 ft20-switch-lib.sh cmp 0" "$(cmp -s "$H/ft20-switch-lib.sh" "$KIT/ft20-switch-lib.sh" && echo 0 || echo 1)"

# ── 변이(사본 폴더에서만) — 변이 사본은 새고, 원본은 같은 사례에서 막는다 ──
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
mcase() {  # mcase <변이> <사례 이름> <팀> <구> <후계> <_역할 칸 값> [표식] — 변이 rc 0(샘) · 원본 rc 3(막음)
  world "$3" "$4" "$6" "${7:-marker}"; g "$4" "$5"; local m="$RC"; KD=""
  world "$3" "$4" "$6" "${7:-marker}"; g "$4" "$5"
  ck "$1 $2 → 변이 rc=$m(0) · 원본 rc=$RC(3)" "$([ "$m" = 0 ] && [ "$RC" = 3 ] && echo 0 || echo 1)"
}
mut M1 '[ "$so" = "$sn" ]' 'true';                                   mcase M1 "② 역할 다름" issues "$I0" 'byz-issues-arch-pi#61' ""
mut M2 '*-*-*) s="$s-0";;' '*-*-*) ;;'   # M2 는 거꾸로 = 변이 사본이 «막고» 원본이 지난다(② 둘째 칸 FAIL)
KD="$T/mut-M2"; world harness "$A5" "$A5"; g "$A5" 'byz-harness-arch-0-pi#336'; m="$RC"; KD=""; world harness "$A5" "$A5"; g "$A5" 'byz-harness-arch-0-pi#336'
ck "M2 ② 석 칸 없음 → 0 변이 rc=$m(3) · 원본 rc=$RC(0)" "$([ "$m" = 3 ] && [ "$RC" = 0 ] && echo 0 || echo 1)"
mut M3 '[[ "$old" =~ ^[a-z0-9-]+-[a-z0-9]+#[0-9]+$ ]]' 'true';      mcase M3 "③ 대문자 꼬리" issues 'byz-issues-master-Sol#60' "$I1" ""
mut M4 '[ "$(printf '"'"'%s'"'"' "${old%#*}" | cut -d- -f3)" != nano ]' 'true'; mcase M4 "④ nano 같은 계보" harness 'byz-harness-nano-r1799-x#0' 'byz-harness-nano-r1799-x#1' 'byz-harness-nano-r1799-x#0'
mut M5 ' && [ -n "$h" ]' '';                                         mcase M5 "④ 같은 계보 표식 null" harness "$A5" "$A6" "$A5" "raw:null"
KD=""

tl1="$(tls)"; TN="$T/tnames"; for x in $I1 $A6 byz-harness-arch-0-pi#336 byz-harness-arch-1-pi#336 byz-harness-qa-web-pi#4 byz-harness-qa-pi#4 byz-harness-nano-r1799-x#1 byz-harness-nano-r1-pi#1 byz-harness-master-pi#336; do printf '%s\n' "$x"; done > "$TN"
nt="$(comm -13 <(printf '%s\n' "$tl0") <(printf '%s\n' "$tl1") | grep -cFx -f "$TN")"
ck "실 tmux 새 세션 중 시험 이름 ${nt}개(0) · 전체 $(printf '%s' "$tl0" | grep -c .) → $(printf '%s' "$tl1" | grep -c .)" "$([ "$nt" = 0 ] && echo 0 || echo 1)"
echo "RUN 1회차 $(( $(date +%s) - t0 ))초 · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
