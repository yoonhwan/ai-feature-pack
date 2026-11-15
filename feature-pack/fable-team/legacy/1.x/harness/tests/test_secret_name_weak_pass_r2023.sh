#!/usr/bin/env bash
# test_secret_name_weak_pass_r2023.sh — 비밀 분류기 약한 낱말 PASS 는 «원래 글자가 대문자인 마지막 조각» 일 때만 비밀 (r2023 · T1~T5)
# 소문자 시험 카운터(pass · npass)는 비밀 아님 · 강한 낱말(PASSWORD·TOKEN·SECRET·KEY …)은 지금처럼 대소문자 무관.
# 입력 = 셸 글 문자열만 · ft_secret_judge.plan() 직접 · 실행·git·네트워크·tmux 0 · 이 파일을 다시 부르지 않음(변이는 사본 bin 에 같은 사례 표를 돌릴 뿐).
# 변이 2종: M1 대문자 조건 삭제 → T1·T5 FAIL · M2 강한 낱말도 원래 글자로 판정 → T3 FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_R2023_BIND:-$HARNESS/bin}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; SECONDS=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

# 사례 표 = 이름 \t 기대 건수(plan 이 돌려주는 줄 수) \t 입력
# T5a = r1655 PR1219 head f52c60b6 tests/test_child_watch_card_ref_r1655.sh :49 · T5b = r1518 81e5429b tests/test_team_stop_r1518.sh :176 (원문 그대로)
cat > "$T/cases.tsv" <<'EOF'
T1a	0	echo "$pass"
T1b	0	echo "$npass"
T1c	0	echo "$pass2"
T1d	0	echo "$n_pass"
T2a	1	echo "$DB_PASS"
T2b	1	echo "$PGPASS"
T2c	1	echo "$PASS"
T3a	1	echo "$db_password"
T3b	1	echo "$api_token"
T3c	1	echo "$Secret_Key"
T4a	0	echo "$PASS_MAX"
T4b	0	echo "$pass_id"
T5a	0	echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
T5b	0	echo "PASS $npass · FAIL $fail"
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
    print(name, len(j.plan(text)))
EOF

run_cases() { timeout 70 python3 -I "$T/run.py" "$1" "$T/cases.tsv" 2>&1; }  # -I 는 PYTHONPATH 를 무시 → 경로는 argv 로 넣는다
expect() { awk -F'\t' '{print $1" "$2}' "$T/cases.tsv"; }

python3 -I -m py_compile "$BIND/ft_secret_targets.py"; ck "py_compile ft_secret_targets.py" $?
got="$(run_cases "$BIND")"
for n in $(awk -F'\t' '{print $1}' "$T/cases.tsv"); do
  w="$(expect | awk -v n="$n" '$1==n{print $2}')"; g="$(awk -v n="$n" '$1==n{print $2}' <<<"$got")"
  [ "$g" = "$w" ]; ck "$n 기대 $w 건 (실제 ${g:-없음})" $?
done

if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$BIND/ft_secret_targets.py" "$HARNESS/kit/fable-team/bin/ft_secret_targets.py"; ck "kit bin 짝 cmp0" $?
  cmp -s "$BIND/ft_secret_targets.py" "$HARNESS/kit/fable-team/templates/hooks/ft_secret_targets.py"; ck "kit templates/hooks 짝 cmp0" $?
fi

# 변이 — 사본 bin 에서만. 같은 사례 표를 돌려 «기대와 달라져야» 한다(패치가 안 붙으면 FAIL).
mut() {  # mut <이름> <원본 조각> <바꿀 조각> <잡아야 할 사례 이름>
  local d="$T/mut-$1"; mkdir -p "$d"; cp -p "$BIND"/ft_secret_*.py "$d/"
  python3 -I - "$d/ft_secret_targets.py" "$2" "$3" <<'PYEOF' || { echo "FAIL 변이 $1 패치가 원본에 안 붙음"; fail=$((fail+1)); return 1; }
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
mut M1-T1 'bool(raw and raw[-1].isupper()) and ' '' T1a
mut M1-T5 'bool(raw and raw[-1].isupper()) and ' '' T5b
mut M2-T3 'any(STRONG_PIECE.search(p) for p in pieces)' 'any(STRONG_PIECE.search(p) for p in raw)' T3a

echo "----"
echo "초: 전체 ${SECONDS}s"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-name-weak-pass r2023)"; exit 0; }
echo "FAILED $fail"; exit 1
