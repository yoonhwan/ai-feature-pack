#!/usr/bin/env bash
# test_team_switch_window_autonomy_r1777.sh — r1777(R336) 2.0 표식 교대 창을 Slack 질문 0 으로.
#   사례: A<N> h 조건(①②③④⑤) · 숫자 h 그대로(⑥) · 교대 창 1회(⑦) · 실패 뒤 restore(⑧) · restore «이미 있음»(⑨)
#   변이 3종(M1 이벤트 일치 삭제 · M2 «∧ full» 삭제 · M3 실패 뒤 restore 삭제) — 전부 사본에서만
#   격리: 실 .fable-team·실 자율 상태·실 명부 쓰기 0 — 임시 데이터 루트(FT_FT20_ROOT · FT_ROOT) 안에서만 · press 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="$HERE/.."; H="$HB/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RK="$T/kit"; R="$T/root"          # RK = 도구 사본(변이용) · R = 임시 데이터 루트
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
now() { date +%s; }; secs() { echo "$(( $(now) - $1 ))초"; }
mkdir -p "$RK/bin" "$R/.fable-team/state" "$R/design/aifp/indices/진행"
for f in ft20-switch-lib.sh ft-team-switch.sh ft-seat-retire.sh ft-autonomy.sh ft-autonomy-level.sh ft-name-lint.sh; do cp -p "$H/$f" "$RK/bin/$f"; done
printf '{"_master":"fx-aifp-master#0","fx-aifp-nano#0":{"role":"nano","agent":"claude","tick":null}}\n' > "$R/.fable-team/seats-aifp.json"
export FT_FT20_ROOT="$R" FT_ROOT="$R" FT_BIN="$RK/bin" FT20_AUTONOMY_BIN="$RK/bin/ft-autonomy.sh"
SH="$RK/bin/ft-team-switch.sh"; LIB="$RK/bin/ft20-switch-lib.sh"
LOG="$R/.fable-team/state/autonomy.log"; AJ="$R/.fable-team/state/autonomy.json"
SN=0; tick() { SN=$((SN+1)); echo $(( $(now) + SN )); }
aut_on()   { local ev="$1" lv="${2:-full}" t; t="$(tick)"; printf '%s\ton\t%s\n' "$t" "$ev" >> "$LOG"; printf '{"mode":"on","since":%s,"event":"%s","until":null,"level":"%s"}\n' "$t" "$ev" "$lv" > "$AJ"; }
aut_off()  { local ev="${1:-A17}" t; t="$(tick)"; printf '%s\toff\t%s\n' "$t" "$ev" >> "$LOG"; printf '{"mode":"off","since":%s,"event":"%s","until":null,"level":"full"}\n' "$t" "$ev" > "$AJ"; }
aut_tamper() { printf 'garbage 줄\n' >> "$LOG"; }
aut_clear()  { rm -f "$LOG" "$AJ"; }
mk() {  # 표식 파일 직접 심기(보관본 판정용 픽스처) — $1 팀 $2 h
  printf '{"team":"%s","switched_at":"2026-11-13T00:00:00+0900","h":"%s","by":"fx","tool":"ft-team-switch.sh","card":"r1675"}\n' "$1" "$2" > "$R/.fable-team/state/ft20-switch/$1.json"
}
hsh() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
marker_h() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("h"))' "$R/.fable-team/state/ft20-switch/$1.json" 2>/dev/null; }

t0="$(now)"
# ── ① 자율 ON A17 ∧ full → mark·unmark rc0 · h=A17 그대로 ────────────────────
aut_on A17 full
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "① mark --h A17(자율 ON·full) rc=$rc" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
hp="$(marker_h aifp)"
ck "① 표식 h 칸 = A17 그대로(실제 ${hp:-없음})" "$([ "$hp" = A17 ] && echo 0 || echo 1)"
bash "$SH" status aifp --root "$R" >"$T/o" 2>&1
ck "① status 가 h=A17 로 읽힌다" "$([ $? = 0 ] && grep -q 'h=A17' "$T/o" && echo 0 || echo 1)"
bash "$SH" unmark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "① unmark --h A17 rc=$rc · 보관본 생김" "$([ "$rc" = 0 ] && ls "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-* >/dev/null 2>&1 && echo 0 || echo 1)"
# ── ⑨ 표식 있는데 restore = rc0 «이미 있음» · 내용 변화 0 ─────────────────────
bash "$SH" mark aifp --h A17 --root "$R" >/dev/null 2>&1
b0="$(hsh "$R/.fable-team/state/ft20-switch/aifp.json")"
bash "$SH" restore aifp --root "$R" >"$T/o" 2>&1; rc=$?
b1="$(hsh "$R/.fable-team/state/ft20-switch/aifp.json")"
ck "⑨ 표식 있는데 restore rc=$rc «이미 있음» · 바이트 불변" "$([ "$rc" = 0 ] && grep -q 'RESTORE keep' "$T/o" && [ "$b0" = "$b1" ] && echo 0 || echo 1)"
bash "$SH" unmark aifp --h A17 --root "$R" >/dev/null 2>&1
# ── ② 지난 이벤트 A16 → REJECT rc2 · 쓰기 0 ──────────────────────────────────
rm -f "$R/.fable-team/state/ft20-switch"/aifp.json
bash "$SH" mark aifp --h A16 --root "$R" >"$T/o" 2>&1; rc=$?
ck "② 지난 이벤트 A16(지금 A17) = rc2 · 표식 0 · $(sed -n '1s/^REJECT //p' "$T/o" | cut -c1-28)" \
  "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
# ── ③ 자율 OFF → REJECT rc2 · 상태 파일 없음도 rc2 ──────────────────────────
aut_off A17
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "③ 자율 OFF = rc2 · 표식 0" "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
aut_clear
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "③-b 자율 상태 파일 없음 = rc2 · 표식 0" "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
# ── ④ 레벨 mid → REJECT rc2 ─────────────────────────────────────────────────
aut_on A17 mid
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "④ 레벨 mid = rc2 · 표식 0" "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
# ── ⑤ 위변조(tamper) → REJECT rc2 ───────────────────────────────────────────
aut_on A17 full; aut_tamper
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "⑤ autonomy.log 위변조 = rc2 · 표식 0" "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
# ── ⑥ 숫자 h 는 지금과 같음(자율 OFF 에서도 통과) ───────────────────────────
aut_clear
bash "$SH" mark aifp --h 8260 --root "$R" --by tester >"$T/o" 2>&1; rc=$?
ck "⑥ 숫자 h 8260 = 자율 OFF 에서도 rc0 · h=8260" "$([ "$rc" = 0 ] && [ "$(marker_h aifp)" = 8260 ] && echo 0 || echo 1)"
bash "$SH" mark aifp --h A --root "$R" >"$T/o" 2>&1; ck "⑥ A 만(숫자 없음) = rc2" "$([ $? = 2 ] && echo 0 || echo 1)"
bash "$SH" unmark aifp --h 8260 --root "$R" >/dev/null 2>&1
bash "$SH" restore aifp --root "$R" >/dev/null 2>&1
rm -f "$R/.fable-team/state/ft20-switch/aifp.json" "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-*   # 표식도 보관본도 없음
bash "$SH" restore aifp --root "$R" >"$T/o" 2>&1; rc=$?
ck "⑥-b 보관본도 없이 restore = rc=$rc(rc2 · 되살릴 것 없음)" "$([ "$rc" = 2 ] && echo 0 || echo 1)"
# ── ⑦ 교대 창 1회: unmark(A17) → retire → remark(A17) 전부 rc0 ─────────────
aut_on A17 full
bash "$SH" mark aifp --h A17 --root "$R" >/dev/null 2>&1
( . "$LIB"; ft20_switch_window "$R" aifp A17 true ) >"$T/o" 2>&1; rc=$?
hp="$(marker_h aifp)"
ck "⑦ 교대 창 1회 rc=$rc · remark 뒤 표식 h=A17" "$([ "$rc" = 0 ] && [ "$hp" = A17 ] && echo 0 || echo 1)"
bash "$SH" unmark aifp --h A17 --root "$R" >/dev/null 2>&1
( . "$LIB"; ft20_guard_retire "$R" 'fx-aifp-nano#0' ) >"$T/o" 2>&1; rc=$?
ck "⑦-b 창 안 은퇴 가드(보관본 h=A17 · 자율 ON A17 full) rc=$rc" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
( . "$LIB"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; ck "⑦-c ft20_window_guard rc0" "$([ $? = 0 ] && echo 0 || echo 1)"
# ── ⑦-d 창 안인데 이벤트가 바뀌면 은퇴 가드 REJECT(같은 조건) ───────────────
aut_on A18 full
( . "$LIB"; ft20_guard_retire "$R" 'fx-aifp-nano#0' ) >"$T/o" 2>&1; rc=$?
ck "⑦-d 창(보관본 A17) · 지금 이벤트 A18 → 은퇴 가드 rc=$rc(거절)" "$([ "$rc" = 2 ] && echo 0 || echo 1)"
# ── ⑧ A17 unmark 뒤 이벤트 A18 → A17 remark rc2 → restore rc0 → 표식 원래 내용 ─
bash "$SH" restore aifp --root "$R" >/dev/null 2>&1   # ⑦-b 가 맞긴 창을 먼저 되돌린다
b0="$(hsh "$R/.fable-team/state/ft20-switch/aifp.json")"
aut_on A17 full
bash "$SH" unmark aifp --h A17 --root "$R" >/dev/null 2>&1
ck "⑧ A17 unmark 성공 · 표식 없음" "$([ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
aut_on A18 full
bash "$SH" mark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
ck "⑧ 이벤트 A18 에서 A17 remark = rc=$rc(rc2) · 표식 여전히 없음" \
  "$([ "$rc" = 2 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
bash "$SH" restore aifp --root "$R" >"$T/o" 2>&1; rc=$?
b1="$(hsh "$R/.fable-team/state/ft20-switch/aifp.json")"
ck "⑧-b restore rc=$rc · 표식 = 원래 내용(바이트 일치)" "$([ "$rc" = 0 ] && [ "$b0" = "$b1" ] && echo 0 || echo 1)"
( . "$LIB"; ft20_switch_guard "$R" aifp ) >"$T/o" 2>&1
ck "⑧-c 되살린 표식 → 1.x writer rc3(차단 유지)" "$([ $? = 3 ] && echo 0 || echo 1)"
# ── ⑩ DA #292018 회귀: 숫자 원표식(h=8260) 팀을 A17 로 연 교대 → 사건 보존 → OFF 면 은퇴 rc2, restore 는 원문 그대로 ─
aut_clear; rm -f "$R/.fable-team/state/ft20-switch/aifp.json" "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-*
bash "$SH" mark aifp --h 8260 --root "$R" >/dev/null 2>&1
aut_on A17 full
bash "$SH" unmark aifp --h A17 --root "$R" >"$T/o" 2>&1; rc=$?
wk="$(ls "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-*.window 2>/dev/null | head -1)"
ck "⑩ 숫자 원표식 8260 팀 · unmark --h A17 rc=$rc · 사건 쪽파일 있음" "$([ "$rc" = 0 ] && [ -n "$wk" ] && grep -q '"h":"A17"' "$wk" && echo 0 || echo 1)"
ck "⑩-b 보관본 JSON 은 원표식 h=8260 그대로(변형 0)" \
  "$([ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("h"))' "${wk%.window}" 2>/dev/null)" = 8260 ] && echo 0 || echo 1)"
( . "$LIB"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; ck "⑩-c 창 안(ON A17 full) 은퇴 가드 rc0" "$([ $? = 0 ] && echo 0 || echo 1)"
aut_off A17
( . "$LIB"; ft20_guard_retire "$R" 'fx-aifp-nano#0' ) >"$T/o" 2>&1; rc=$?
ck "⑩-d 자율 OFF 뒤 은퇴 가드 rc=$rc(기대 rc2 · DA HOLD 원인 닫힘)" "$([ "$rc" = 2 ] && echo 0 || echo 1)"
aut_on A18 full
( . "$LIB"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; rc=$?
ck "⑩-e 이벤트 A18 로 바뀌어도 A17 창 은퇴 rc=$rc(rc2)" "$([ "$rc" = 2 ] && echo 0 || echo 1)"
aut_on A17 full
b0="$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),ensure_ascii=False,sort_keys=True))' "${wk%.window}" 2>/dev/null)"
bash "$SH" restore aifp --root "$R" >"$T/o" 2>&1; rc=$?
b1="$(python3 -c 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),ensure_ascii=False,sort_keys=True))' "$R/.fable-team/state/ft20-switch/aifp.json" 2>/dev/null)"
ck "⑩-f restore rc=$rc · 표식 = 원표식 8260 그대로(쪽파일은 표식에 안 감)" \
  "$([ "$rc" = 0 ] && [ "$(marker_h aifp)" = 8260 ] && [ "$b0" = "$b1" ] && [ ! -e "${wk%.window}.window" ] && echo 0 || echo 1)"
( . "$LIB"; ft20_switch_guard "$R" aifp ) >"$T/o" 2>&1; ck "⑩-g 되살린 표식 → writer rc3" "$([ $? = 3 ] && echo 0 || echo 1)"
# ── ⑪ 숫자로 연 기존 교대는 쪽파일 0 · 옛 동작 그대로 ──────────────────
bash "$SH" unmark aifp --h 9001 --root "$R" >/dev/null 2>&1
aut_off A18
ck "⑪ 숫자(9001)로 연 교대 = 쪽파일 0" "$([ "$(ls "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-*.window 2>/dev/null | grep -c .)" = 0 ] && echo 0 || echo 1)"
( . "$LIB"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; rc=$?
ck "⑪-b 숫자 교대 · 자율 OFF 에서도 은퇴 가드 rc=$rc(옛 동작 그대로)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
bash "$SH" restore aifp --root "$R" >/dev/null 2>&1
# ── 변이 3종(사본에서만 · 실 파일 치환 0) ────────────────────────────────────
mut() {  # $1 이름 $2 원문 $3 바꿀 글 → $T/mut-$1/ 에 lib·도구 사본(같은 폴더 = FT20_HERE)
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; cp -p "$LIB" "$RK/bin/ft-team-switch.sh" "$d/"
  python3 - "$d/ft20-switch-lib.sh" "$2" "$3" <<'PYMUT' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return 1; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PYMUT
}
LIBA="$T/mutA"; rm -rf "$LIBA"; mkdir -p "$LIBA"; cp -p "$LIB" "$LIBA/"
# M1 이벤트 일치 확인 삭제 → ②(A16) 가 새어 통과해야 변이 검출
mut M1 '  if [ "$ev" != "$h" ]; then echo "REJECT 교대 창 h=$h 는 지금 이벤트(${ev:-없음})가 아님 — 지난 사건이거나 자율 OFF · 1.x 쓰기 0" >&2; return 2; fi' '  :'
aut_on A17 full
( . "$T/mut-M1/ft20-switch-lib.sh"; ft20_autonomy_ok A16 ) >"$T/o" 2>&1; rc=$?
ck "M1 이벤트 일치 삭제 → A16 이 rc=${rc} 로 새서 ② FAIL" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
# M2 «∧ full» 삭제 → ④(mid) 가 새어 통과해야 변이 검출
mut M2 '  if [ "$l" != full ]; then echo "REJECT 교대 창 h=$h — 자율 레벨이 full 이 아님(${l:-?}) · 1.x 쓰기 0" >&2; return 2; fi' '  :'
aut_on A17 mid
( . "$T/mut-M2/ft20-switch-lib.sh"; ft20_autonomy_ok A17 ) >"$T/o" 2>&1; rc=$?
ck "M2 «∧ full» 삭제 → mid 가 rc=${rc} 로 새서 ④ FAIL" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
# M4 사건 쏙파일 읽기 무시(원표식 h 만 보기) → ⑩-d(OFF 뒤 은퇴)가 새어 rc0 으로 ⑩ FAIL
mut M4 'h="$(ft20_window_event "$dst")"' 'h=""'
aut_on A17 full
bash "$SH" mark aifp --h 8260 --root "$R" >/dev/null 2>&1
bash "$SH" unmark aifp --h A17 --root "$R" >/dev/null 2>&1
aut_off A17
( . "$T/mut-M4/ft20-switch-lib.sh"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; rc=$?
ck "M4 사건 쏙파일 무시 → OFF 인데 rc=${rc} 로 새서 ⑩-d FAIL" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
( . "$LIB"; ft20_window_guard "$R" aifp ) >"$T/o" 2>&1; rc=$?
ck "⑩-h (정본) 같은 창 · OFF 면 rc=$rc(rc2)" "$([ "$rc" = 2 ] && echo 0 || echo 1)"
bash "$SH" restore aifp --root "$R" >/dev/null 2>&1

# ── M3 실패 뒤 restore 호출 삭제 → ⑧ 이 표식 부재로 FAIL
mut M3 'bash "$tool" restore "$team" --root "$root" >&2' 'true'
aut_on A17 full
( . "$T/mut-M3/ft20-switch-lib.sh"; ft20_switch_window "$R" aifp A17 false ) >"$T/o" 2>&1; rc=$?
ck "M3 restore 삭제 → 창 실패 뒤 표식 없음(rc=$rc) 으로 ⑧ FAIL" \
  "$([ "$rc" != 0 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
bash "$SH" mark aifp --h A17 --root "$R" >/dev/null 2>&1
( . "$LIB"; ft20_switch_window "$R" aifp A17 false ) >"$T/o" 2>&1; rc=$?
ck "⑧-d (정본) 창 실패 뒤 restore → 표식 있음(rc=$rc)" \
  "$([ "$rc" != 0 ] && [ -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"

echo "RUN 1회차 $(secs "$t0") · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
