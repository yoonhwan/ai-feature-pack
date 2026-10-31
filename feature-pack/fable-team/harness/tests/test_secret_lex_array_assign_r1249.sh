#!/usr/bin/env bash
# test_secret_lex_array_assign_r1249.sh — 비밀 판정기 낱말 나누기: 배열 대입 «이름=(…)»·«이름+=(…)» 의 괄호는 서브셸이 아니다 (r1249 · 반례 R1~R9)
# 입력 = 셸 글 문자열만 · ft_secret_judge.plan() 직접 · git·네트워크·tmux 0 · 이 파일을 다시 부르지 않음(변이는 사본 bin 에 같은 사례 표를 돌릴 뿐).
# 변이 3종: 배열 갈래 끔 → R1 FAIL · 갈래를 «( 앞 아무 낱말» 로 넓힘 → R9 FAIL · 원소 치환 풀어 주기 → R6 FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_R1249_BIND:-$HARNESS/bin}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

# 사례 표 = 이름 \t 기대 건수(plan 이 돌려주는 줄 수) \t 입력(\n 은 두 글자 백슬래시 n)
cat > "$T/cases.tsv" <<'EOF'
R1	0	acts+=("set")
R1s	0	acts+=('set')
R2	0	acts=(set)
R2m	0	acts=(\n  a\n  set\n)
R3	0	             acts+=("set"); ss+=("$P 있음 until $([ "$why" = a ] && echo "$uah" || echo "$ubh")(자동)")
R4a	1	( set )
R4b	1	(set)
R4c	1	set
R5	1	f() { set; }
R6a	1	x=( $(env) )
R6b	1	arr+=("a" "$(printenv)")
R6c	1	x=(`env`)
R7	1	acts+=("set") ; set
R8	1	a=( "x" ); env
R9a	1	echo x=(set)
R9b	1	cmd a=(set)
R10	1	a=(set
EOF

cat > "$T/run.py" <<'EOF'
import sys
bind, tsv = sys.argv[1], sys.argv[2]
sys.path.insert(0, bind)
import ft_secret_judge as j
for line in open(tsv, encoding="utf-8").read().split("\n"):
    if not line:
        continue
    name, _want, text = line.split("\t", 2)
    print(name, len(j.plan(text.replace("\\n", "\n"))))
EOF

run_cases() { timeout 70 python3 -I "$T/run.py" "$1" "$T/cases.tsv" 2>&1; }  # -I 는 PYTHONPATH 를 무시 → 경로는 argv 로 넣는다
expect() { awk -F'\t' '{print $1" "$2}' "$T/cases.tsv"; }

python3 -I -m py_compile "$BIND/ft_secret_lex.py"; ck "py_compile ft_secret_lex.py" $?
[ "$(wc -l < "$BIND/ft_secret_lex.py")" -le 200 ]; ck "200줄 상한" $?
got="$(run_cases "$BIND")"
for n in R1 R1s R2 R2m R3 R4a R4b R4c R5 R6a R6b R6c R7 R8 R9a R9b R10; do
  w="$(expect | awk -v n="$n" '$1==n{print $2}')"; g="$(awk -v n="$n" '$1==n{print $2}' <<<"$got")"
  [ "$g" = "$w" ]; ck "$n 기대 $w 건 (실제 ${g:-없음})" $?
done

if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$BIND/ft_secret_lex.py" "$HARNESS/kit/fable-team/bin/ft_secret_lex.py"; ck "kit bin 짝 cmp0" $?
  cmp -s "$BIND/ft_secret_lex.py" "$HARNESS/kit/fable-team/templates/hooks/ft_secret_lex.py"; ck "kit templates/hooks 짝 cmp0" $?
fi

# 변이 — 사본 bin 에서만. 같은 사례 표를 돌려 «기대와 달라져야» 한다(패치가 안 붙으면 FAIL).
mut() {  # mut <이름> <원본 조각> <바꿀 조각> <잡아야 할 사례 이름>
  local d="$T/mut-$1"; mkdir -p "$d"; cp -p "$BIND"/ft_secret_*.py "$d/"
  python3 -I - "$d/ft_secret_lex.py" "$2" "$3" <<'PYEOF' || { echo "FAIL 변이 $1 패치가 원본에 안 붙음"; fail=$((fail+1)); return 1; }
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert a in s, a[:60]
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PYEOF
  local m w g; m="$(run_cases "$d")"
  w="$(expect | awk -v n="$4" '$1==n{print $2}')"; g="$(awk -v n="$4" '$1==n{print $2}' <<<"$m")"
  [ "$g" != "$w" ]; ck "변이 $1 → $4 가 FAIL 로 잡음 (기대 $w · 변이 ${g:-없음})" $?
}
mut off '(arr := read_array(t, i))' 'False' R1
mut widen 'ARRAY_HEAD.fullmatch("".join(cur)) and all(ARRAY_HEAD.match(w) for w in words)' '"".join(cur) != ""' R9b
mut subs 'subs.extend(w.subs)' 'pass' R6a

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-lex-array-assign r1249)"; exit 0; }
echo "FAILED $fail"; exit 1
