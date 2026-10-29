#!/usr/bin/env bash
# test_hil_result_notify_r1117.sh — r1117: h 끝 결과 쪽지(ft-hil.sh entry_body → ft-hil-notify.sh done) · ft-merge-land 거절 기다림 표식 · approve-merge 승인 도착 쪽지 (카드 반례 R1~R8)
# 격리: 임시 HIL_DIR·쪽지함(가짜 mbox.sh = 인자를 sent.log 에 적는 셸)·상태 폴더 · merge-land 는 임시 origin+clone(_merge_fixture)의 «승인 파일 없음» 분기까지만 — 실 mbox·실 /tmp/h*·실 gh 0 · 고정 sleep 0
# 변이 대조: R1117_BIN=<변이 사본 bin> 으로 돌리면 ⓐ(진입 파일 끝 알림 1줄 삭제)·ⓕ(.sent 이름 바꾸기 삭제)가 FAIL 한다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1117_BIN:-$HERE/../bin}"
. "$HERE/_merge_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

C="$T/ft/comm"; mkdir -p "$C" "$T/hil" "$T/home" "$T/state"
PM='byz-planner-master-claude#166'; RS='byz-feature-master-claude#49'
printf '{"_master": "%s"}\n' "$PM" > "$T/ft/seats-planner.json"
printf '#!/bin/bash\n[ -e "$(dirname "$0")/fail" ] && exit 1\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
hil()  { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$C" bash "$BIN/ft-hil.sh" "$@"; }
runh() { env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$1"; }   # 오빠 `bash /tmp/h<N>` — 쪽지함은 진입 파일에 박힌 값(env 0)
nsent() { cat "$C/sent.log" 2>/dev/null | grep -c .; }
clr() { rm -f "$C/sent.log" "$C/fail"; }
plan() { { echo '#!/usr/bin/env bash'; [ -z "$2" ] || echo "# ft-hil-request seat=$2"; echo 'echo 작업'; echo "echo '=== 결과 === $1'"; echo "exit ${3:-0}"; } > "$T/$1.sh.hil"; }

echo "== ⓐ R1 머리 표식 있음 → rc0 → 표식 좌석 1통 + planner master 1통 = 2통"
plan p1 "$RS"; out="$(hil --add "$T/p1.sh.hil" 2>"$T/e1")"; [ "$out" = "! bash $T/hil/h1" ] && ok "--add → h1" || bad "--add out=$out $(cat "$T/e1")"
clr; o="$(runh "$T/hil/h1")"; rc=$?
[ "$rc" = 0 ] && ok "h1 rc0" || bad "h1 rc=$rc"
has "$o" "=== 결과 === p1" "계획 출력은 화면에 그대로(tee)"
[ "$(nsent)" = 2 ] && ok "쪽지 정확히 2통" || bad "쪽지 $(nsent)통: $(cat "$C/sent.log" 2>&1)"
grep -qxF "$RS	ft-hil-h1	[완료 h1] rc=0 · === 결과 === p1 · 계획 $T/p1.sh.hil" "$C/sent.log" && ok "  └ 요청 좌석 1통(결과 줄·계획 경로)" || bad "요청 좌석 줄 없음: $(cat "$C/sent.log" 2>&1)"
grep -q "^$PM	ft-hil-h1	\[완료 h1\] rc=0 " "$C/sent.log" && ok "  └ planner master 1통" || bad "planner 줄 없음"

echo "== ⓑ R2 머리 표식 없음 → 등록 WARN 1줄 · 실행 뒤 planner master 1통만"
plan p2 ""; out="$(hil --add "$T/p2.sh.hil" 2>"$T/e2")"
[ "$out" = "! bash $T/hil/h2" ] && ok "--add → h2(stdout 1줄 그대로)" || bad "out=$out"
[ "$(grep -c 'WARN 요청 좌석 표식 없음' "$T/e2")" = 1 ] && ok "  └ WARN 1줄" || bad "WARN: $(cat "$T/e2")"
clr; runh "$T/hil/h2" >/dev/null
[ "$(nsent)" = 1 ] && grep -q "^$PM	ft-hil-h2	\[완료 h2\] rc=0" "$C/sent.log" && ok "planner master 1통만" || bad "쪽지: $(cat "$C/sent.log" 2>&1)"

echo "== ⓒ R3·R8 rc 보존 — 계획 rc7 → h rc7 · mbox rc1 이어도 rc7 + stderr «판정 불가» 1줄"
plan p3 "$RS" 7; hil --add "$T/p3.sh.hil" >/dev/null 2>&1
clr; runh "$T/hil/h3" >/dev/null 2>&1; rc=$?
[ "$rc" = 7 ] && ok "h3 exit 7" || bad "h3 rc=$rc"
grep -q "^$RS	ft-hil-h3	\[완료 h3\] rc=7 · === 결과 === p3" "$C/sent.log" && ok "  └ [완료 h3] rc=7" || bad "rc7 줄 없음: $(cat "$C/sent.log" 2>&1)"
plan p4 "$RS" 7; hil --add "$T/p4.sh.hil" >/dev/null 2>&1
clr; touch "$C/fail"; runh "$T/hil/h4" >/dev/null 2>"$T/e4"; rc=$?
[ "$rc" = 7 ] && ok "mbox 실패에도 h4 exit 7" || bad "h4 rc=$rc"
grep -q '판정 불가' "$T/e4" && ok "  └ stderr «판정 불가»" || bad "stderr: $(cat "$T/e4")"
[ "$(nsent)" = 0 ] && ok "  └ 쪽지 0(가짜 mbox 실패)" || bad "쪽지가 생겼다"

echo "== ⓓ R4 머리 표식 린트 실패·4좌석 → --add REJECT rc2 · h 파일 0"
before="$(ls "$T/hil" | grep -c '^h[0-9]*$')"
plan p5 "byz-x"; o="$(hil --add "$T/p5.sh.hil" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT" "린트 실패 = REJECT rc2" || bad "rc=$rc $o"
plan p6 "$RS $PM byz-ops-master-claude#64 byz-v65-master-claude#250"; o="$(hil --add "$T/p6.sh.hil" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT 요청 좌석은 3개까지" "4좌석 = REJECT rc2" || bad "rc=$rc $o"
[ "$(ls "$T/hil" | grep -c '^h[0-9]*$')" = "$before" ] && ok "  └ 새 h 파일 0" || bad "h 파일이 생겼다: $(ls "$T/hil")"

echo "== ⓔ R5 ft-merge-land 승인 파일 없음 → REJECT rc2 그대로 + 기다림 표식 1줄 · 재거절 덧쓰기 0"
mkrepo "$T/r"; mkdir -p "$T/r/.fable-team"
export FT_ROOT="$T/r" FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_LEVEL=each FT_MBOX_DIR="$C"
S1="$(printf 'a%.0s' {1..40})"; WF="$T/state/autonomy-merge-wait/$S1"
o="$(FT_SEAT="$RS" bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$S1" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 2 ] && has "$o" "REJECT 오빠 승인 파일 없음" "REJECT rc2 그대로" || bad "rc=$rc $o"
has "$o" "기다림 등록 $WF" "  └ REJECT 줄 끝 «기다림 등록 <경로>»"
grep -qE "^seat=$RS epoch=[0-9]+$" "$WF" 2>/dev/null && [ "$(grep -c . "$WF")" = 1 ] && ok "  └ 표식 1줄 seat=FT_SEAT" || bad "표식: $(cat "$WF" 2>&1)"
FT_SEAT='byz-other-master-claude#1' bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$S1" --repo "$W" >/dev/null 2>&1
grep -qE "^seat=$RS " "$WF" && [ "$(ls "$T/state/autonomy-merge-wait" | grep -c .)" = 1 ] && ok "재거절 = 파일 1개 그대로(덧쓰기 0)" || bad "재거절 뒤: $(cat "$WF" 2>&1)"

echo "== ⓕ R6 approve-merge(표식 있음) → APPROVED 그대로 + [승인 도착] 1통 + .sent · 재승인 0통"
clr; o="$(bash "$BIN/ft-autonomy.sh" approve-merge "$S1" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && has "$o" "APPROVED $S1" "APPROVED 줄 그대로" || bad "rc=$rc $o"
[ "$(nsent)" = 1 ] && grep -qxF "$RS	ft-hil-approve	[승인 도착 ${S1:0:10}] approve-merge 끝 — ft-merge-land 다시 실행" "$C/sent.log" && ok "  └ 표식 좌석에 1통" || bad "쪽지: $(cat "$C/sent.log" 2>&1)"
[ ! -e "$WF" ] && [ -f "$WF.sent" ] && ok "  └ 표식 → .sent" || bad "표식 상태: $(ls "$T/state/autonomy-merge-wait")"
clr; bash "$BIN/ft-autonomy.sh" approve-merge "$S1" >/dev/null 2>&1
[ "$(nsent)" = 0 ] && ok "재승인 = 0통" || bad "재승인 쪽지 $(nsent)통"

echo "== ⓖ R7 approve-merge(표식 없음) → APPROVED 그대로 · 0통 · 새 파일 0 / seat=unknown → planner «수신자 모름» 1통"
S2="$(printf 'b%.0s' {1..40})"; clr; o="$(bash "$BIN/ft-autonomy.sh" approve-merge "$S2" 2>&1)"
has "$o" "APPROVED $S2" "APPROVED 그대로"
[ "$(nsent)" = 0 ] && [ "$(ls "$T/state/autonomy-merge-wait" | grep -c .)" = 1 ] && ok "  └ 0통 · 새 표식 파일 0" || bad "쪽지 $(nsent) · $(ls "$T/state/autonomy-merge-wait")"
S3="$(printf 'c%.0s' {1..40})"; env -u FT_SEAT bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$S3" --repo "$W" >/dev/null 2>&1
clr; bash "$BIN/ft-autonomy.sh" approve-merge "$S3" >/dev/null 2>&1
[ "$(nsent)" = 1 ] && grep -q "^$PM	ft-hil-approve	\[승인 도착 ${S3:0:10}\] 수신자 모름" "$C/sent.log" && ok "seat=unknown → planner master «수신자 모름» 1통" || bad "쪽지: $(cat "$C/sent.log" 2>&1)"

echo "== ⓗ R8 승인 쪽 mbox rc1 → APPROVED·rc 불변 · stderr «판정 불가» · 표식 남음(.sent 0)"
S4="$(printf 'd%.0s' {1..40})"; FT_SEAT="$RS" bash "$BIN/ft-merge-land.sh" 7 --approve-sha "$S4" --repo "$W" >/dev/null 2>&1
clr; touch "$C/fail"; o="$(bash "$BIN/ft-autonomy.sh" approve-merge "$S4" 2>"$T/e8")"; rc=$?
[ "$rc" = 0 ] && has "$o" "APPROVED $S4" "mbox 실패에도 APPROVED rc0" || bad "rc=$rc $o"
grep -q '판정 불가' "$T/e8" && ok "  └ stderr «판정 불가»" || bad "stderr: $(cat "$T/e8")"
[ -f "$T/state/autonomy-merge-wait/$S4" ] && [ ! -e "$T/state/autonomy-merge-wait/$S4.sent" ] && ok "  └ 표식 남음(다음 승인에 다시 시도)" || bad "표식 상태 틀림"

echo "== ⓘ 팩 추적본 bin = 키트 bin (cmp0 ×4)"
K="$HERE/../kit/fable-team/bin"
for f in ft-hil.sh ft-hil-notify.sh ft-merge-land.sh ft-autonomy.sh; do cmp -s "$HERE/../bin/$f" "$K/$f" && ok "cmp0 $f" || bad "키트 사본 다름: $f"; done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
