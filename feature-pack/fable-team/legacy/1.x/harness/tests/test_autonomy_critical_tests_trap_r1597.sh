#!/usr/bin/env bash
# test_autonomy_critical_tests_trap_r1597.sh — r1597 «tests/ 의 mktemp -d → trap EXIT rm -rf» 줄만 D2 크리티컬 destroy 에서 뺀다
#   ⓐ 예외 성립(두 줄 꼴 · r1592 한 줄 꼴 · 따옴표 없는 꼴 · 템플릿 인자) ⓑ 반례 ①~⑫(전부 kind=destroy · ⑧ = NG1 앞 명령 · ⑩ = NG2 $(mktemp …) 안 명령 · ⑪ = DA② R1 대입 위치·값 전체 · ⑫ = NG3 재대입 10종)
#   ⓒ 키트 사본 cmp0 · 변이 M1(경로)·M2(mktemp 확인)·M3(변수 일치)·M4(줄 전체 긍정)·M5(앞머리 [^;]*)·M6(값 전체)·M7(줄 머리)·M8(개수 검사)
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
pr tests/t_r1597_uq.sh 'T=$(mktemp -d); '"$TRP"; crit "$PRSHA"; okc; ck 'ⓐ3 따옴표 없는 꼴 T=$(mktemp -d) · trap → CRITICAL-OK rc0' $?
pr tests/t_r1597_tpl.sh 'T="$(mktemp -d /tmp/r1597.XXXXXX)"; '"$TRP"; crit "$PRSHA"; okc; ck 'ⓐ4 템플릿 인자 1개 mktemp -d /tmp/r1597.XXXXXX → CRITICAL-OK rc0' $?
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
# ── ⓑ10 arch 재인수 NG2 — 앞머리 $(mktemp …) 안에 다른 명령이 들어가면 destroy
pr tests/t_r1597_10a.sh 'T="$(mktemp -d && rm -rf /)"; '"$TRP"; crit "$PRSHA"; B10="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ10a 앞머리 mktemp -d && rm -rf / → kind=destroy' $?
pr tests/t_r1597_10b.sh 'T="$(mktemp -d | xargs rm -rf)"; '"$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ10b 앞머리 mktemp -d | xargs rm -rf → kind=destroy' $?
pr tests/t_r1597_10c.sh 'T=$(mktemp -d) && kill -9 1 $(true); '"$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ10c 앞머리 mktemp -d) && kill -9 1 · trap → kind=destroy' $?
pr tests/t_r1597_10d.sh 'T="$(mktemp -d) $(psql -c '\''DROP TABLE users'\'')"; '"$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ10d 앞머리 mktemp -d) $(psql DROP TABLE) → kind=destroy' $?
# ── ⓑ11 DA② r1 HOLD — 대입은 «줄 머리·값 전체» 여야 한다(주석 줄·부분 문자열 = 대입 아님 · payload 실행 0)
pr tests/t_r1597_11a.sh 'T="$(mktemp -d)/../.."' "$TRP"; crit "$PRSHA"; B11="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ11a R1-a 생성 경로 뒤에 /../.. 연결 → kind=destroy' $?
pr tests/t_r1597_11b.sh '# T="$(mktemp -d)"' "$TRP"; crit "$PRSHA"; B11B="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ11b R1-b 주석 줄에만 대입 → kind=destroy' $?
# ── ⓑ12 arch 재인수 NG3 — 대입이 한 번뿐이어도 «맨 이름 T» 가 두 번 나오면 destroy(재대입·추가 대입·읽기·루프)
pr tests/t_r1597_12a.sh "$MK" 'true; T=/' "$TRP"; crit "$PRSHA"; B12="$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12a true; T=/ → kind=destroy' $?
pr tests/t_r1597_12b.sh "$MK" 'local T=/' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12b local T=/ → kind=destroy' $?
pr tests/t_r1597_12c.sh "$MK" 'declare T=/' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12c declare T=/ → kind=destroy' $?
pr tests/t_r1597_12d.sh "$MK" 'true && T=/' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12d true && T=/ → kind=destroy' $?
pr tests/t_r1597_12e.sh "$MK" 'if true; then T=/; fi' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12e if true; then T=/; fi → kind=destroy' $?
pr tests/t_r1597_12f.sh "$MK" '{ T=/; }' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12f { T=/; } → kind=destroy' $?
pr tests/t_r1597_12g.sh "$MK" '(cd "$T"; T=$PWD/..)' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12g (cd "$T"; T=$PWD/..) → kind=destroy' $?
pr tests/t_r1597_12h.sh "$MK" 'T+=/../..' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12h T+=/../.. → kind=destroy' $?
pr tests/t_r1597_12i.sh "$MK" 'read -r T' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12i read -r T → kind=destroy' $?
pr tests/t_r1597_12j.sh "$MK" 'for T in /' "$TRP"; crit "$PRSHA"; [ "$rc" = 3 ] && eval "$DEST"; ck 'ⓑ12j for T in / → kind=destroy' $?
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
mut m2 autonomy_scope_rules.py '    return bool(re.search(MKTEMP_LINE % v + MKTEMP_VALUE + MKTEMP_TAIL, body))' '    return True'
mc m2 "$B2"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM2 mktemp 대입 확인 지우기 → ⓑ2 가 예외로 새어 통과(빨강)" $?
mut m3 autonomy_scope_rules.py 'if not var or (m.group("pre") and m.group("pre") != var.group(1)):' 'if not var:'
mc m3 "$B9"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM3 대입 변수 일치 조건 지우기 → ⓑ9 가 예외로 새어 통과(빨강)" $?
mut m4 autonomy_scope_rules.py 'TRAP_LINE = re.compile(r"^\s*' 'TRAP_LINE = re.compile(r"^.*?'
mc m4 "$B8"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM4 «줄 전체가 trap» 긍정(^) 느슨하게 → ⓑ8a 가 예외로 새어 통과(빨강)" $?
mut m5 autonomy_scope_rules.py 'MKTEMP_VALUE = r"\"?\$\(\s*mktemp\s+-d(?:\s+[\w./-]+)?\s*\)\"?"' 'MKTEMP_VALUE = r"\"?\$\(\s*mktemp\s+-d[^;]*\)\"?"'
mc m5 "$B10"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM5 앞머리 값을 [^;]* 로 느슨하게(NG2 옛 구멍) → ⓑ10a 가 예외로 새어 통과(빨강)" $?
mut m6 autonomy_scope_rules.py 'MKTEMP_LINE % v + MKTEMP_VALUE + MKTEMP_TAIL' 'MKTEMP_LINE % v + MKTEMP_VALUE'
mc m6 "$B11"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM6 값 «전체» 조건 지우기(접두만) → ⓑ11a 가 예외로 새어 통과(빨강)" $?
mut m7 autonomy_scope_rules.py 'MKTEMP_LINE = r"(?m)^' 'MKTEMP_LINE = r"(?m)'
mc m7 "$B11B"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM7 «줄 머리» 긍정 지우기 → ⓑ11b(주석 줄 대입)가 예외로 새어 통과(빨강)" $?
mut m8 autonomy_scope_rules.py 'if len(re.findall(MKTEMP_NAME % v, body)) != 1:' 'if len(re.findall(MKTEMP_LINE % v, body)) != 1:'
mc m8 "$B12"; [ "$rc" = 0 ] && [ "$out" = CRITICAL-OK ]; ck "ⓘM8 개수 검사를 줄 머리로 되돌림 → ⓑ12a 가 예외로 새어 통과(빨강)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
