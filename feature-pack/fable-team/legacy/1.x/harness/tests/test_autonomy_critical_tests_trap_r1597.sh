#!/usr/bin/env bash
# test_autonomy_critical_tests_trap_r1597.sh — r1597 «tests/ 의 mktemp -d → trap EXIT rm -rf» 줄만 D2 크리티컬 destroy 에서 뺀다
#   ⓐ 예외 성립(두 줄 꼴 · r1592 실사건 한 줄 꼴) ⓑ 반례 ①~⑨(전부 kind=destroy · ⑧ = arch 인수 NG1 줄 앞 파괴 명령 3종)
#   ⓒ 키트 사본 cmp0 · 변이 M1(경로 조건)·M2(mktemp 확인)·M3(대입 변수 일치)·M4(줄 전체 긍정)
#   ⓒ 의 «기존 시험 2개 rc 불변» 은 따로 돌린다(시험 1개 70초 상한 — test_autonomy_standing_d2_r1577.sh 가 41초 · 카드 r1597 증거 줄)
#   격리: 임시 리포(origin bare + clone) · 실 상태·실 원격·press 0(나노는 쏘지 않는다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MK='T="$(mktemp -d)"'; TRP="trap 'rm -rf \"\$T\"' EXIT"; DEST='[[ $out =~ ^CRITICAL\ kind=destroy\  ]]'
python3 -c "import ast;[ast.parse(open('$BIN/'+f).read()) for f in ('autonomy_scope_rules.py','autonomy_scope_classify.py')]"; ck "python ast 2종" $?
mkrepo "$T/iso"; R="$W"
pr() {  # pr <경로> <내용…> → PRSHA(origin/main 에서 1커밋)
  git -C "$R" checkout -q -B "pr$RANDOM" origin/main; mkdir -p "$R/$(dirname -- "$1")"
  printf '%s\n' "${@:2}" > "$R/$1"; cm "$R" "r1597 case"; PRSHA="$(sha "$R" HEAD)"; git -C "$R" checkout -q main; }
crit() { out="$(python3 "$BIN/autonomy_scope_classify.py" classify "$1" --repo "$R" --critical 2>&1)"; rc=$?; }
okc() { [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; }
# ── ⓐ 예외 = 세 조건 모두 참인 그 줄
pr tests/t_r1597.sh "$MK" "$TRP"; crit "$PRSHA"; A1="$PRSHA"; okc; ck "ⓐ1 tests/ 의 두 줄(mktemp -d · trap EXIT rm -rf) → CRITICAL-OK rc0" $?
pr tests/t_r1597_one.sh "$MK; $TRP"; crit "$PRSHA"; A2="$PRSHA"; okc; ck "ⓐ2 r1592 실사건 꼴 한 줄(T=…; trap … EXIT) → CRITICAL-OK rc0" $?
# ── ⓑ 반례 — 하나라도 거짓이면 지금처럼 destroy
pr bin/x_r1597.sh "$MK" "$TRP"; crit "$PRSHA"; B1="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ1 같은 두 줄이 tests/ 밖(bin/) → kind=destroy" $?
pr tests/t_r1597_p.sh 'T=/tmp/x' "$TRP"; crit "$PRSHA"; B2="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ2 변수 대입이 mktemp 아님(T=/tmp/x) → kind=destroy" $?
pr tests/t_r1597_f.sh "$MK" "trap 'rm -rf /tmp/x' EXIT"; crit "$PRSHA"; B3="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ3 고정 경로(trap 'rm -rf /tmp/x' EXIT) → kind=destroy" $?
pr tests/t_r1597_n.sh "$MK" 'rm -rf "$T"'; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ4 trap 없는 rm -rf \"\$T\" → kind=destroy" $?
pr tests/t_r1597_k.sh "$MK" "trap 'rm -rf \"\$T\"; kill 0' EXIT"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ5 trap 안에 다른 파괴 명령(kill 0) → kind=destroy" $?
pr tests/t_r1597_r.sh "$MK" 'T=/tmp/y' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ6 같은 파일에서 V 재대입 → kind=destroy" $?
pr tests/t_r1597_o.sh "$MK" "$TRP" 'kill 0'; crit "$PRSHA"; B7="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ7 예외 줄과 함께 다른 destroy 줄 → kind=destroy" $?
pr tests/t_r1597_8a.sh "$MK" "rm -rf / ; $TRP"; crit "$PRSHA"; B8="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ8a 줄 앞에 rm -rf / ; → kind=destroy" $?
pr tests/t_r1597_8b.sh "$MK" "kill -9 1 && $TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ8b 줄 앞에 kill -9 1 && → kind=destroy" $?
pr tests/t_r1597_8c.sh "$MK" "psql -c \"DROP TABLE users\" ; $TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ8c 줄 앞에 psql … DROP TABLE ; → kind=destroy" $?
pr tests/t_r1597_ov.sh "$MK" 'X="$(mktemp -d)"; '"$TRP"; crit "$PRSHA"; B9="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck "ⓑ9 한 줄 꼴에서 앞 대입 변수(X)와 trap 변수(T)가 다름 → kind=destroy" $?
# ── ⓒ 키트 사본 = bin 사본(두 파일)
for f in autonomy_scope_rules.py autonomy_scope_classify.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f"; ck "ⓒ 키트 사본 cmp0 $f" $?; done
# ── 변이 M1~M4 — 제품 파일 1곳씩 지우면 그 칸이 «빨강»(예외가 잘못 열린다)
mut() {  # mut <이름> <파일> <원문> <바꿀 글> → $T/mut-<이름>
  local mb="$T/mut-$1"; mkdir -p "$mb"; for f in "$BIN"/*; do ln -s "$f" "$mb/$(basename "$f")"; done; rm -f "$mb/$2"
  python3 - "$BIN/$2" "$mb/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
mc() { out="$(python3 "$T/mut-$1/autonomy_scope_classify.py" classify "$2" --repo "$R" --critical 2>&1)"; rc=$?; }
mut m1 autonomy_scope_rules.py 'if not path or not (path.startswith("tests/") or "/tests/" in path):' 'if False:'
mc m1 "$B1"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM1 경로 조건(tests/) 지우기 → ⓑ1 이 예외로 새어 통과(빨강)" $?
mut m2 autonomy_scope_rules.py '    return bool(re.search(MKTEMP_ASSIGN % v, body))' '    return True'
mc m2 "$B2"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM2 mktemp 대입 확인 지우기 → ⓑ2 가 예외로 새어 통과(빨강)" $?
mut m3 autonomy_scope_rules.py 'if not var or (m.group("pre") and m.group("pre") != var.group(1)):' 'if not var:'
mc m3 "$B9"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM3 대입 변수 일치 조건 지우기 → ⓑ9 가 예외로 새어 통과(빨강)" $?
mut m4 autonomy_scope_rules.py 'TRAP_LINE = re.compile(r"^\s*' 'TRAP_LINE = re.compile(r"^.*?'
mc m4 "$B8"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM4 «줄 전체가 trap» 긍정(^) 느슨하게 → ⓑ8a 가 예외로 새어 통과(빨강)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
