#!/usr/bin/env bash
# test_team_switch_guard_r1675.sh — r1675 팀 2.0 전환 표식 + 1.x 쓰기 입구 가드.
#   사례 ⓐ 표식 도구(mark·unmark·status · rename · 이미 전환 rc2) ⓑ 쓰기 전 멈춤·판정 불가 ⓒ 입구 1개씩 ⓓ 새 입력 보존(보류) ⓔ 표식 0 회귀
#   r1888: 우편함(mbox) 차단 갈래는 test_r1888_mbox_ft20_comm_exempt.sh 로 옮겼다(통신 = 가드 대상 아님)
#   변이 3종(M1 표식 확인 삭제 · M2 보류 쓰기 삭제 · M3 깨진 표식을 «없음» 으로) — 전부 사본에서만
#   격리: 실 .fable-team·실 우편함·실 명부 쓰기 0 — 임시 데이터 루트(FT_FT20_ROOT) + comm 사본 · press 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HB="$HERE/.."; H="$HB/bin"; COMM="$HB/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
RK="$T/kit"; R="$T/root"          # RK = 도구 사본(변이용) · R = 임시 데이터 루트
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
now() { date +%s; }; secs() { echo "$(( $(now) - $1 ))초"; }
mkdir -p "$RK/bin" "$R/.fable-team/state" "$R/design/aifp/indices/진행"
cp -Rp "$COMM" "$RK/comm"
for f in ft20-switch-lib.sh ft-team-switch.sh ft-index-move.sh ft-nano-spawn.sh ft-seat-retire.sh ft-successor-open.sh; do cp -p "$H/$f" "$RK/bin/$f"; done
printf '{"_master":"fx-master#0","fx-nano#0":{"role":"nano","agent":"pi","tick":null}}\n' > "$R/.fable-team/seats-aifp.json"
printf '{"_master":"fx-nano#0"}\n' > "$R/.fable-team/seats-harness.json"
printf '# 카드\n- 상태: 진행\n' > "$R/design/aifp/indices/진행/c.md"
printf 'body\n' > "$T/body.txt"
export FT_FT20_ROOT="$R" FT_BIN="$RK/bin" FT_MBOX_DIR="$R/.fable-team/comm"
SH="$RK/bin/ft-team-switch.sh"; LIB="$RK/bin/ft20-switch-lib.sh"
send() { bash "$RK/comm/mbox.sh" send 'fx-nano#0' 'fx-tester#0' "$1" >"$T/mbox.log" 2>&1; }

t0=$(now)
# ── ⓐ 표식 도구 ──────────────────────────────────────────────────────────────
bash "$SH" status --root "$R" >"$T/o" 2>&1; ck "ⓐ status 0건 = NO-SWITCH rc0" $?
bash "$SH" mark aifp --h 8260 --root "$R" --by tester >"$T/o" 2>&1; ck "ⓐ mark rc0 · $(sed -n 's/^MARKED //p' "$T/o")" $?
bash "$SH" mark aifp --h 9999 --root "$R" >"$T/o" 2>&1; ck "ⓐ 이미 전환 = rc2(덮어쓰기 0)" "$([ $? -eq 2 ] && echo 0 || echo 1)"
hp="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("h"))' "$R/.fable-team/state/ft20-switch/aifp.json" 2>/dev/null)"
ck "ⓐ 표식 h 가 처음 값 그대로(8260 · 실제 $hp)" "$([ "$hp" = 8260 ] && echo 0 || echo 1)"
bash "$SH" mark harness --root "$R" >"$T/o" 2>&1; ck "ⓐ --h 없으면 rc2" "$([ $? -eq 2 ] && echo 0 || echo 1)"
bash "$SH" status aifp --root "$R" >"$T/o" 2>&1; ck "ⓐ status aifp rc0 SWITCHED" "$([ $? -eq 0 ] && grep -q 'SWITCHED team=aifp' "$T/o" && echo 0 || echo 1)"
bash "$SH" status harness --root "$R" >"$T/o" 2>&1; ck "ⓐ status 미전환 팀 rc1" "$([ $? -eq 1 ] && echo 0 || echo 1)"
bash "$SH" unmark aifp --h 8260 --root "$R" >"$T/o" 2>&1; rc=$?
ls "$R/.fable-team/state/ft20-switch"/aifp.json.unmarked-* >/dev/null 2>&1; mv=$?
ck "ⓐ unmark rc=$rc · rename 만(지우기 0)" "$([ "$rc" = 0 ] && [ "$mv" = 0 ] && [ ! -e "$R/.fable-team/state/ft20-switch/aifp.json" ] && echo 0 || echo 1)"
bash "$SH" unmark aifp --h 8260 --root "$R" >"$T/o" 2>&1; ck "ⓐ 표식 없음 unmark = rc2" "$([ $? -eq 2 ] && echo 0 || echo 1)"

# ── ⓔ(앞) 표식 0 = 지금 동작 그대로 ─────────────────────────────────────────
send "표식-없음"; rc=$?
ck "ⓔ 표식 0 이면 우편함 쓰기 그대로 rc=$rc" "$([ "$rc" = 0 ] && [ -s "$R/.fable-team/comm/mailbox.jsonl" ] && echo 0 || echo 1)"

# ── ⓑ·ⓒ·ⓓ 표식 켜고 입구 5 + 가드 본체 ───────────────────────────────────
bash "$SH" mark aifp --h 8260 --root "$R" >/dev/null 2>&1
# ⓒ①·ⓓ mbox 갈래(send 차단·본문 보류·같은 초 2통·lib 없는 mbox) = r1888 로 옮김 — 우편함 통신은 가드 대상 아님(test_r1888_mbox_ft20_comm_exempt.sh)
bash "$SH" status harness --root "$R" >/dev/null 2>&1   # 미전환 팀은 그대로 통과해야 한다
( . "$LIB"; ft20_switch_guard "$R" harness >"$T/o" 2>&1 ); ck "ⓑ 표식 없는 팀 = rc0 통과" $?
( . "$LIB"; ft20_switch_guard "$R" aifp >"$T/o" 2>&1 ); ck "ⓑ 표식 팀 = rc3" "$([ $? -eq 3 ] && grep -q 'REJECT 팀 aifp 은 2.0 전환됨' "$T/o" && echo 0 || echo 1)"
( . "$LIB"; ft20_switch_guard "" aifp >"$T/o" 2>&1 ); ck "ⓑ 루트 못 풀면 INFO + rc0" "$([ $? -eq 0 ] && grep -q '팀 판정 불가' "$T/o" && echo 0 || echo 1)"
mkdir -p "$R/.fable-team/state/ft20-switch/harness.json.d"; printf '{bad' > "$R/.fable-team/state/ft20-switch/broken.json"
( . "$LIB"; ft20_switch_guard "$R" broken >"$T/o" 2>&1 ); ck "ⓑ 깨진 표식 = 판정 불가 rc3(쓰기 0)" "$([ $? -eq 3 ] && grep -q '판정 불가' "$T/o" && echo 0 || echo 1)"
printf '{"bad' > "$R/.fable-team/seats-broken.json"
( . "$LIB"; ft20_guard_seat "$R" 'fx-nano#0' >"$T/o" 2>&1 ); ck "ⓑ 명부 깨짐 = 판정 불가 rc3" "$([ $? -eq 3 ] && grep -q '명부 못 읽음' "$T/o" && echo 0 || echo 1)"
rm -f "$R/.fable-team/seats-broken.json"
( . "$LIB"; ft20_guard_seat "$R" 'nobody#0' >"$T/o" 2>&1 ); ck "ⓑ 명부에 없는 좌석 = 팀 없음 통과 rc0 + INFO" "$([ $? -eq 0 ] && grep -q '어느 명부에도 없음' "$T/o" && echo 0 || echo 1)"
mkdir -p "$R/.fable-team/state/ft20-switch/aifp.held.block"; rm -rf "$R/.fable-team/state/ft20-switch/aifp.held"; printf 'x' > "$R/.fable-team/state/ft20-switch/aifp.held"
( . "$LIB"; ft20_switch_guard "$R" aifp "본문" me >"$T/o" 2>&1 ); ck "ⓓ 보류 폴더 쓰기 실패 = rc3 + «보류 실패»" "$([ $? -eq 3 ] && grep -q '보류 실패' "$T/o" && echo 0 || echo 1)"
rm -f "$R/.fable-team/state/ft20-switch/aifp.held"
bash "$RK/bin/ft-index-move.sh" "$R/design/aifp/indices/진행/c.md" 대기 --seat 'fx-nano#0' >"$T/o" 2>&1; rc=$?
ck "ⓒ② ft-index-move rc=$rc · 카드 그대로" "$([ "$rc" = 3 ] && [ -f "$R/design/aifp/indices/진행/c.md" ] && echo 0 || echo 1)"
ckst="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/.fable-team/seats-aifp.json")"
bash "$RK/bin/ft-seat-retire.sh" 'fx-nano#0' 'fx-nano#1' --seats "$R/.fable-team/seats-aifp.json" >"$T/o" 2>&1; rc=$?
ckst2="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/.fable-team/seats-aifp.json")"
ck "ⓒ③ ft-seat-retire rc=$rc · 명부 바이트 불변" "$([ "$rc" = 3 ] && [ "$ckst" = "$ckst2" ] && echo 0 || echo 1)"
bash "$RK/bin/ft-nano-spawn.sh" "$R/design/aifp/indices/진행/c.md" --agent pi >"$T/o" 2>&1; rc=$?
ck "ⓒ④ ft-nano-spawn rc=$rc (첫 게이트)" "$([ "$rc" = 3 ] && grep -q '2.0 전환됨' "$T/o" && echo 0 || echo 1)"
bash "$RK/bin/ft-successor-open.sh" 'fx-nano#0' "$R" --name 'fx-nano#1' --agent pi --model deepseek-v4 --body-file "$T/body.txt" >"$T/o" 2>&1; rc=$?
ck "ⓒ⑤ ft-successor-open rc=$rc (state/successor 쓰기 0)" "$([ "$rc" = 3 ] && [ ! -e "$R/.fable-team/state/successor" ] && echo 0 || echo 1)"
# ⓒ⑥ 명부에 «없는» 옛 좌석 retire = R282② 가 이름의 팀 명부에 새 행을 쓴다 → 그 팀도 실제 쓰기 대상(DA R1)
st0="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/.fable-team/seats-aifp.json")"
bash "$RK/bin/ft-seat-retire.sh" 'byz-aifp-da-codex#100' 'byz-aifp-da-codex#101' >"$T/o" 2>&1; rc=$?
st1="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$R/.fable-team/seats-aifp.json")"
ck "ⓒ⑥ 명부에 없는 좌석 retire 도 이름의 팀(aifp)으로 rc=$rc · 명부 불변" "$([ "$rc" = 3 ] && [ "$st0" = "$st1" ] && grep -q '팀 aifp' "$T/o" && echo 0 || echo 1)"
# ⓑ lib 부재 + 표식 있음 = 조용한 통과 0(rc3) · 표식 0 이면 지금 동작 그대로(기존 시험 정합)
mkdir -p "$T/nolib" && cp -p "$H/ft-index-move.sh" "$T/nolib/" && cp -p "$R/design/aifp/indices/진행/c.md" "$R/design/aifp/indices/진행/c2.md"
bash "$T/nolib/ft-index-move.sh" "$R/design/aifp/indices/진행/c2.md" 대기 --seat 'fx-nano#0' >"$T/o" 2>&1; rc=$?
ck "ⓑ lib 없음 + 표식 있음 = rc=$rc(판정 불가) · 카드 그대로" "$([ "$rc" = 3 ] && [ -f "$R/design/aifp/indices/진행/c2.md" ] && grep -q 'ft20-switch-lib.sh 없음' "$T/o" && echo 0 || echo 1)"
mv "$R/.fable-team/state/ft20-switch" "$T/sw.bak"   # 표식 0 상태(깨진 표식까지 통째로 옮긴다)
bash "$T/nolib/ft-index-move.sh" "$R/design/aifp/indices/진행/c2.md" 대기 --seat 'fx-nano#0' >"$T/o" 2>&1; rc=$?
ck "ⓑ lib 없음 + 표식 0 = 지금 동작 그대로 rc=$rc(카드 이동)" "$([ "$rc" = 0 ] && [ -f "$R/design/aifp/indices/대기/c2.md" ] && ! grep -q 'WARN' "$T/o" && echo 0 || echo 1)"
mv "$T/sw.bak" "$R/.fable-team/state/ft20-switch"; mv "$R/design/aifp/indices/대기/c2.md" "$R/design/aifp/indices/진행/c2.md"
# ⓒ③b --seats/FT_SEATS_JSON 로 명부 한 장만 줘도 «쓰기 대상 명부 전부» 검사(r465 `_*` 칸 · arch #3922 ②)
bash "$SH" unmark aifp --h 8260 --root "$R" >/dev/null 2>&1
bash "$SH" mark harness --h 9100 --root "$R" >/dev/null 2>&1
bash "$RK/bin/ft-seat-retire.sh" 'fx-nano#0' 'fx-nano#1' --seats "$R/.fable-team/seats-aifp.json" >"$T/o" 2>&1; rc=$?
ck "ⓒ③b --seats 한 장만 줘도 harness 명부(_master) 가드 rc=$rc" "$([ "$rc" = 3 ] && grep -q '팀 harness' "$T/o" && echo 0 || echo 1)"
bash "$SH" unmark harness --h 9100 --root "$R" >/dev/null 2>&1
bash "$SH" mark aifp --h 8260 --root "$R" >/dev/null 2>&1
bash "$SH" unmark aifp --h 8260 --root "$R" >/dev/null 2>&1   # 되돌리면 다시 통과(표식 없는 팀)
( . "$LIB"; ft20_switch_guard "$R" aifp >"$T/o" 2>&1 ); ck "ⓑ unmark 뒤 rc0 복귀" $?
# ── 변이 3종(사본에서만 · 실 파일 치환 0) ────────────────────────────────────
bash "$SH" mark aifp --h 8260 --root "$R" >/dev/null 2>&1
mut() {  # $1 이름 $2 원문 $3 바꿀 글 → 사본 $T/mut-$1/ft20-switch-lib.sh 에만 적용
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; cp -p "$LIB" "$d/"
  python3 - "$d/ft20-switch-lib.sh" "$2" "$3" <<'PYMUT' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return 1; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PYMUT
}
mut M1 '  m="$(ft20_switch_marker "$root" "$team")"; [ -e "$m" ] || return 0' '  m="$(ft20_switch_marker "$root" "$team")"; return 0'
( . "$T/mut-M1/ft20-switch-lib.sh"; ft20_switch_guard "$R" aifp ) >"$T/o" 2>&1; rc=$?
ck "M1 표식 확인 삭제 → 전환 팀 쓰기가 rc=${rc} 으로 새서 시험 FAIL" "$([ "$rc" = 3 ] && echo 1 || echo 0)"
mut M2 '( set -C; printf '\''%s'\'' "$body" > "$base-$(printf '\''%02d'\'' "$n").txt" ) 2>/dev/null && held="$base-$(printf '\''%02d'\'' "$n").txt"' 'true'
before="$(ls "$R/.fable-team/state/ft20-switch"/aifp.held/*.txt 2>/dev/null | wc -l | tr -d ' ')"
( . "$T/mut-M2/ft20-switch-lib.sh"; ft20_switch_guard "$R" aifp "보류될 본문" me ) >"$T/o" 2>&1; rc=$?
after="$(ls "$R/.fable-team/state/ft20-switch"/aifp.held/*.txt 2>/dev/null | wc -l | tr -d ' ')"
ck "M2 보류 쓰기 삭제 → 보류 파일 ${before}→${after} 로 ⓓ FAIL(rc=$rc)" "$([ "$before" = "$after" ] && echo 0 || echo 1)"
mut M3 '    || { echo "REJECT 팀 $team 전환 표식 판정 불가 — $m 못 읽음(깨진 JSON·권한) · 1.x 쓰기 0" >&2; return 3; }' '    || return 0'
( . "$T/mut-M3/ft20-switch-lib.sh"; ft20_switch_guard "$R" broken ) >"$T/o" 2>&1; rc=$?
ck "M3 깨진 표식을 «없음» 으로 침 → 판정 불가 사례 rc=${rc} FAIL" "$([ "$rc" = 3 ] && echo 1 || echo 0)"

echo "RUN 1회차 $(secs "$t0") · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
