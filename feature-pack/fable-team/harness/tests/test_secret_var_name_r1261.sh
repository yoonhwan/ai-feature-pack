#!/usr/bin/env bash
# test_secret_var_name_r1261.sh — 비밀 분류기 echo·printf 판정: 변수 이름을 «_» 조각으로 본다 (r1261 · 반례 R1~R5)
# PASS 는 «마지막 조각» 일 때만 비밀(DB_PASS·PGPASS) · PASSWORD·TOKEN·SECRET·DSN·KEY·WEBHOOK 은 어느 조각이든(끝/같음) 비밀.
# 입력 = 셸 글 문자열만 · ft_secret_judge.plan() 직접 · git·네트워크·tmux 0 · 이 파일을 다시 부르지 않음(변이는 사본 bin 에 같은 사례 표를 돌릴 뿐).
# 변이 2종: PASS «마지막 조각» 조건 제거 → R1·R3 FAIL · 강한 낱말 «끝나거나 같음» 을 «같음» 으로 좁힘 → R2 PGPASSWORD FAIL.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_R1261_BIND:-$HARNESS/bin}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

# 사례 표 = 이름 \t 기대 건수(plan 이 돌려주는 줄 수) \t 입력
cat > "$T/cases.tsv" <<'EOF'
R1a	0	echo "$(date '+%F %T') ERROR pass over ${PASS_MAX}s — 바퀴 끊음" >&2
R1b	0	echo "x ERROR pass over ${PASS_MAX}s $(cut_note "$PASS_ID")" >&2
R2a	1	echo "$DB_PASS"
R2b	1	echo "${PGPASSWORD}"
R2c	1	printf '%s' "$GH_TOKEN"
R2d	1	echo "$API_KEY"
R2e	1	echo "$SECRET_VALUE"
R2f	1	echo "$SLACK_WEBHOOK_URL"
R2g	1	echo "$DATABASE_DSN"
R2h	1	echo "$PGPASS"
R2i	1	echo "$SORT_KEY_N"
R2j	1	echo "$KEYS"
R3a	0	echo "$PASS_MAX"
R3b	0	echo "${PASS_ID}"
R3c	0	echo "$PASSES"
R3d	0	echo "$BYPASS_COUNT"
R4	1	echo "$PASS_ID $GH_TOKEN"
R5a	1	printenv GH_TOKEN
R5b	1	op read op://vault/item/field
R5c	1	gcloud secrets versions access latest --secret=x
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
mut anypass 'bool(pieces and pieces[-1].endswith("PASS"))' 'any(p.endswith("PASS") for p in pieces)' R1a
mut anypass2 'bool(pieces and pieces[-1].endswith("PASS"))' 'any(p.endswith("PASS") for p in pieces)' R3a
mut equalonly 'STRONG_PIECE = re.compile(r"(?:PASSWORD' 'STRONG_PIECE = re.compile(r"^(?:PASSWORD' R2b

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-var-name r1261)"; exit 0; }
echo "FAILED $fail"; exit 1
