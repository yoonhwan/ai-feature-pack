#!/usr/bin/env bash
# test_scope_never_learn_r1208.sh — r1208: 경계 종류(repo-outside·scope-table·mode)는 학습표에 있어도 docs 로 안 바뀌고(R1~R3) 새로 학습되지도 않는다(R5) · 다른 종류 학습은 그대로(R4)
# 격리: 임시 origin(bare)+clone · 임시 STATE · 가짜 분류기·슬랙·mbox(R5) — 실 STATE·실 범위·외부 호출 0 · 자기 재호출 0 · GIT_* env 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"; PT="$HERE/../kit/fable-team/templates/scope-classes-pack.tsv"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; H="$(mktemp -d)"; trap 'rm -rf "$T" "$H"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" HIL_DIR="$H" HIL_CLIP=0
mk() { local br="$1"; shift; git -C "$W" checkout -q -B "$br" "$BASE"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
cls() { local c="$1"; shift; out="$(python3 "$c" classify "$SHA" --repo "$W" --scope S1 "$@" 2>&1)"; rc=$?; }
s0=$SECONDS

# 기준 저장소: BASE 위에서 딴 가지 · main 은 한 칸 앞(ff 아님 — classify 기존 시험과 같은 꼴)
mkdir -p "$W/feature-pack/fable-team/harness/kit/fable-team/templates"; echo d > "$W/feature-pack/fable-team/a.md"
cp "$PT" "$W/feature-pack/fable-team/harness/kit/fable-team/templates/scope-classes-pack.tsv"
cm "$W" base2; git -C "$W" push -q origin main; BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
ST="$T/scope-table.tsv"   # r1198 의 scope-table 종류 줄(표 파일 자신) + 팩 표
{ printf 'forbid\tscope-table\t^feature-pack/fable-team/harness/kit/fable-team/templates/scope-classes-[^/]*\\.tsv$\n'; cat "$PT"; } > "$ST"

# ⓐ R1~R3 — 경계 종류는 학습표에 있어도 FORBID · learned 0
mk r1 'echo h > hooks.txt';                                     cls "$CLS" --table "$PT" --learned repo-outside
[ "$rc" = 3 ] && [[ "$out" == "FORBID kind=repo-outside"* ]] && [[ "$out" != *learned* ]]; ck "ⓐ R1 학습표 repo-outside · 표 밖 경로 → FORBID kind=repo-outside(learned 0)" $?
R1SHA="$SHA"
mk r2 'echo "# x" >> feature-pack/fable-team/harness/kit/fable-team/templates/scope-classes-pack.tsv'; cls "$CLS" --table "$ST" --learned scope-table
[ "$rc" = 3 ] && [[ "$out" == "FORBID kind=scope-table"* ]] && [[ "$out" != *learned* ]]; ck "ⓐ R2 학습표 scope-table · 표 파일 바꿈 → FORBID kind=scope-table" $?
mk r3 'echo n > feature-pack/fable-team/b.md; chmod 755 feature-pack/fable-team/b.md'; cls "$CLS" --table "$PT" --learned mode
[ "$rc" = 3 ] && [[ "$out" == "FORBID kind=mode"* ]] && [[ "$out" != *learned* ]]; ck "ⓐ R3 학습표 mode · 새 파일 100755 → FORBID kind=mode" $?
mk r1x 'echo h > hooks.txt';                                    cls "$CLS" --table "$PT" --learned billing,repo-outside,mode
[ "$rc" = 3 ] && [[ "$out" == "FORBID kind=repo-outside"* ]]; ck "ⓐ 학습표 여러 행(billing·repo-outside·mode) 섞여도 R1 FORBID" $?
s1=$SECONDS

# ⓑ R4 — 다른 종류(billing) 학습은 그대로 docs learned (기본 내장 표)
mk r4 'mkdir -p gateway/billing; echo b > gateway/billing/x.py'; cls "$CLS" --learned billing
[ "$rc" = 0 ] && [[ "$out" == "CLASS docs kind=billing learned"* ]]; ck "ⓑ R4 학습표 billing · billing 경로 → CLASS docs kind=billing learned" $?

# ⓐ 변이 — NEVER_LEARN 에서 repo-outside 를 뺀 사본 → R1 이 docs 로 바뀌어야(이 시험이 그 변화를 잡는다)
M="$T/mut"; mkdir -p "$M"; cp "$BIN"/*.py "$M/"   # 분류기가 함수 안에서 부르는 모듈(ft_secret_judge 등)까지 같은 폴더에
python3 -I - "$M/autonomy_scope_rules.py" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
t = re.sub(r'^NEVER_LEARN = \{[^}]*\}', 'NEVER_LEARN = {"secret", "scope-table", "mode"}', s, count=1, flags=re.M)
assert t != s; open(p, "w", encoding="utf-8").write(t)
PY
ck "ⓐ 변이 사본 만들기" $?
SHA="$R1SHA"; cls "$M/autonomy_scope_classify.py" --table "$PT" --learned repo-outside
[ "$rc" = 0 ] && [[ "$out" == "CLASS docs kind=repo-outside learned"* ]]; ck "ⓐ 변이(repo-outside 뺌) → R1 CLASS docs learned(= 원본이면 FAIL 할 자리)" $?
s2=$SECONDS

# ⓒ R5 — learn_kind: denied.tsv 에 경계 종류 행 · ON ∧ full → LEARN-SKIP · 학습표 쓰기 0 (가짜 분류기·슬랙·mbox · ft-autonomy.sh 진입)
S="$T/state"; SD="$S/autonomy-scope"
cat > "$T/cls.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = check-revert ] && { echo OK; exit 0; }
echo "FORBID kind=${STUB_KIND:?} 시험 사유"; exit 3
EOF
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/mbox.sh"
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_AUTONOMY_MBOX="$T/mbox.sh" FT_AUTONOMY_DESK='t#0' FT_AUTONOMY_GOAL_TABLE=0 FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_LEVEL=full
mkdir -p "$T/planner"
a() { ( cd "$T" && FT_NOW=1800000000 "$BASH" "$BIN/ft-autonomy.sh" "$@" ); }
a on --for 12h >/dev/null 2>&1; [ "$(a mode)" = on ]; ck "ⓒ 픽스처 ON(full)" $?
printf 'billing\t%040x\t1800000000\tfull\n' 9 > "$SD/learned-kinds.tsv"
n=0
for k in repo-outside scope-table mode; do
  n=$((n+1)); s="$(printf '%040x' "$n")"
  out="$(STUB_KIND=$k a scope-approve "$s" 2>&1)"; rc=$?
  grep -q "^$s	$k	" "$SD/denied.tsv"; ck "ⓒ R5 $k scope-approve → denied.tsv 행" $?
  out="$(a approve-merge "$s" 2>&1)"; rc=$?
  grep -q "^LEARN-SKIP kind=$k " <<<"$out" && ! grep -q '^LEARNED' <<<"$out" && [ "$(wc -l < "$SD/learned-kinds.tsv" | tr -d ' ')" = 1 ]; ck "ⓒ R5 $k approve-merge → LEARN-SKIP · 학습표 행 수 그대로(1)" $?
done
s3=$SECONDS

# ⓓ bin·kit 같은 내용 · 두 곳 같은 집합
cmp -s "$BIN/autonomy_scope_rules.py" "$MIR/autonomy_scope_rules.py" && cmp -s "$BIN/ft-autonomy-level.sh" "$MIR/ft-autonomy-level.sh"; ck "ⓓ bin·kit cmp0(rules.py · ft-autonomy-level.sh)" $?
py="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import autonomy_scope_rules as r; print(",".join(sorted(r.NEVER_LEARN)))' "$BIN")"
sh="$(sed -n 's/^NEVER_LEARN=",\([^"]*\),".*/\1/p' "$BIN/ft-autonomy-level.sh" | tr ',' '\n' | sort | paste -sd, -)"
[ -n "$py" ] && [ "$py" = "$sh" ] && [ "$py" = "mode,repo-outside,scope-table,secret" ]; out="py=$py sh=$sh"; ck "ⓓ 파이썬·셸 NEVER_LEARN 같은 집합" $?
echo "단계별 초: R1~R3=$((s1-s0)) R4+변이=$((s2-s1)) R5=$((s3-s2)) 합=$((SECONDS-s0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
