#!/usr/bin/env bash
# test_r1888_mbox_ft20_comm_exempt.sh — r1888 우편함 통신(send·relay·handover·ready)은 2.0 전환 표식 가드 대상이 아니다.
#   r1675 시험의 mbox 갈래(send 차단·본문 보류·같은 초 2통·lib 없는 mbox 차단)를 «통신 제외» 기대로 옮겨 온 시험(DA 범위 정정).
#   ① 표식 팀 send rc0·큐1·held0 ② relay 같은 꼴 ③ handover·ready(send 를 탐) rc0 ④ 표식 0 send rc0(회귀)
#   ①b lib 없는 설치본 + 표식 = send rc0·_unjudged.held 0 · 변이 M1(사본에 send 가드 되살림) → ① FAIL
#   격리: 임시 루트(FT_FT20_ROOT)·comm 사본·가짜 명부·tmux/ft-hil 스텁 · 실 우편함·명부·표식·pane 쓰기 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HB="$HERE/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; n=0; t0=$(date +%s)
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: $(head -c 300 "$T/o" | tr '\n' ' ')"; fail=$((fail+1)); fi; }
O='byz-feature-master-claude#78'; N='byz-feature-master-claude#79'
mkdir -p "$T/stub" "$T/kit/bin"
printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && exit 0\nexit 2\n' > "$T/stub/ft-hil.sh"; chmod +x "$T/stub/ft-hil.sh"
cp -Rp "$HB/comm" "$T/kit/comm"; cp -p "$HB/bin/ft20-switch-lib.sh" "$T/kit/bin/"
roster() {   # roster <retired 0|1> — feature 팀 옛 #78 · 후계 #79
  python3 - "$R/.fable-team/seats-feature.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
d = {"_master": n if r else o, o: {"role": "master"}, n: {"role": "master"}}
if r: d[o] = {"role": "stop-ready", "_replaced_by": n}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
mark() { mkdir -p "$R/.fable-team/state/ft20-switch"; printf '{"team":"%s","h":8260,"switched_at":"2026-11-13T00:00:00"}\n' "$1" > "$R/.fable-team/state/ft20-switch/$1.json"; }
new_env() {   # new_env <표식 0|1> [kit] — 임시 데이터 루트 · 표식 팀 2개(aifp·feature) · 가짜 명부
  R="$(mktemp -d "$T/root.XXXXXX")"; C="$R/.fable-team/comm"; Q="$C/mailbox.jsonl"; K="${2:-$T/kit}"
  mkdir -p "$C" "$R/.fable-team/state"; git -C "$R" init -q; : > "$Q"
  printf '{"_master":"fx-master#0","fx-nano#0":{"role":"nano","agent":"pi","tick":null}}\n' > "$R/.fable-team/seats-aifp.json"
  roster 0; [ "$1" = 0 ] || { mark aifp; mark feature; }
}
mb() { ( cd "$R" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_FT20_ROOT="$R" FT_BIN="${FB:-$K/bin}" FT_MBOX_DIR="$C" \
  FT_MBOX_STATE_DIR="$R/.fable-team/state" FT_SEATS_JSON="$R/.fable-team/seats-feature.json" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
  FT_NAME_LINT="$HB/bin/ft-name-lint.sh" FT_MBOX_PY="$K/comm/mbox.py" FT_HIL_BIN="$T/stub/ft-hil.sh" FT_READY_AUTO_CLOSE=0 \
  bash "$K/comm/mbox.sh" "$@" ) >"$T/o" 2>&1; }
rows() { grep -c . "$Q" 2>/dev/null || true; }
held() { find "$R/.fable-team/state/ft20-switch" -name '*.txt' 2>/dev/null | grep -c . || true; }
has() { grep -q -- "$1" "$Q"; }
case1() {   # case1 [kit] → ① 표식 팀 send · rc0 · 큐 1 · held 0
  new_env 1 "${1:-}"; mb send 'fx-nano#0' 'fx-tester#0' '통신-본문-한글'; rc=$?
  [ "$rc" = 0 ] && [ "$(rows)" = 1 ] && has '통신-본문-한글' && [ "$(held)" = 0 ]
}

t=$(date +%s); case1; v=$?; ck "① 표식 팀(aifp) send rc=$rc · 큐 $(rows) · held $(held) $(( $(date +%s)-t ))초" "$v"
mb send 'fx-nano#0' 'fx-tester#0' '첫째-본문'; a=$?; mb send 'fx-nano#0' 'fx-tester#0' '둘째-본문'; b=$?
ck "① 같은 초 2통 = rc $a/$b · 큐 $(rows) · held $(held)" "$([ "$a$b" = 00 ] && [ "$(rows)" = 3 ] && has '첫째-본문' && has '둘째-본문' && [ "$(held)" = 0 ] && echo 0 || echo 1)"
new_env 1; mkdir -p "$T/nolib"; FB="$T/nolib" mb send 'fx-nano#0' 'fx-tester#0' 'lib-없는-본문'; rc=$?
ck "①b lib 없는 설치본 + 표식 = send rc=$rc · 큐 $(rows) · _unjudged held $(held)" "$([ "$rc" = 0 ] && [ "$(rows)" = 1 ] && [ "$(held)" = 0 ] && echo 0 || echo 1)"
new_env 1; printf '긴 원문\n' > "$T/long.txt"; mb relay 'fx-nano#0' 'fx-tester#0' "$T/long.txt" '릴레이-요약'; rc=$?
ck "② 표식 팀 relay rc=$rc · 큐 $(rows) · held $(held)" "$([ "$rc" = 0 ] && [ "$(rows)" = 1 ] && has '릴레이-요약' && [ "$(held)" = 0 ] && echo 0 || echo 1)"
new_env 1; mb handover "$O" "$N"; rc=$?
ck "③ 표식 팀(feature) handover rc=$rc · 큐 $(rows) · held $(held)" "$([ "$rc" = 0 ] && [ "$(rows)" = 1 ] && has '\[인계\]' && [ "$(held)" = 0 ] && echo 0 || echo 1)"
roster 1; mb recv "$N"; mb ready "$N" "$O"; rc=$?
ck "③ 표식 팀 ready rc=$rc · 큐 $(rows) · held $(held)" "$([ "$rc" = 0 ] && grep -q '\[레디\]' "$C/mailbox.log.jsonl" "$Q" 2>/dev/null && [ "$(held)" = 0 ] && echo 0 || echo 1)"
new_env 0; mb send 'fx-nano#0' 'fx-tester#0' '표식-없음'; rc=$?
ck "④ 표식 0 send rc=$rc · 큐 $(rows)(회귀)" "$([ "$rc" = 0 ] && [ "$(rows)" = 1 ] && echo 0 || echo 1)"

# 변이 M1 — 사본에서만 send 가드 호출(+lib 로딩)을 되살린다 → ① 이 FAIL 해야 한다
M="$T/mut"; rm -rf "$M"; cp -Rp "$T/kit" "$M"
python3 - "$M/comm/mbox.sh" <<'PY' || { echo "FAIL M1 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = '    case "${args[*]}" in "[레디]"*) dbto="$to";; esac'
assert s.count(a) == 1, s.count(a)
g = '    . "$FT_BIN/ft20-switch-lib.sh"; if ft20_switch_active "$FT_FT20_ROOT"; then ft20_guard_seat "$FT_FT20_ROOT" "$to" "${args[*]}" "$from" || exit $?; fi\n'
open(p, "w", encoding="utf-8").write(s.replace(a, g + a))
PY
case1 "$M"; ck "M1 send 가드 되살림 → ① rc=$rc 로 FAIL 확인" "$([ "$rc" = 3 ] && echo 0 || echo 1)"

echo "RUN 1회차 $(( $(date +%s)-t0 ))초 · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
