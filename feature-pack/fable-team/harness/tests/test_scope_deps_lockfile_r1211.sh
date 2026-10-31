#!/usr/bin/env bash
# test_scope_deps_lockfile_r1211.sh — r1211: deps 잠금 규칙은 실제 잠금 파일 이름만 막는다 · «-locked.png» 같은 보통 파일(R1)은 FORBID 0 ·
# 잠금 파일 13종(R2)·npm-shrinkwrap.json(R3)·첫 갈래 package.json 류(R4)는 FORBID deps
# 격리: 임시 origin(bare)+clone · 임시 STATE · 기본 내장 표(BYZ) — 실 STATE·외부 호출 0 · 자기 재호출 0 · GIT_* env 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
s0=$SECONDS

# 기준 저장소: BASE 위에서 딴 가지 · main 은 한 칸 앞(classify 기존 시험과 같은 꼴)
BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
n=0
add() { n=$((n+1)); git -C "$W" checkout -q -B "p$n" "$BASE"; mkdir -p "$(dirname -- "$W/$1")"; echo x > "$W/$1"; cm "$W" "p$n"; SHA="$(sha "$W" HEAD)"; }
cls() { out="$(python3 "$1" classify "$SHA" --repo "$W" --scope S1 2>&1)"; rc=$?; }
is_deps() { [ "$rc" = 3 ] && [[ "$out" == "FORBID kind=deps"* ]]; }
not_deps() { [ "$rc" = 0 ] && [[ "$out" == "CLASS "* ]] && [[ "$out" != *deps* ]]; }

# ⓐ R1 — lock 뒤에 다른 글자가 붙은 보통 파일 → deps 아님(CLASS)
for p in a-locked.png src/file-lock.py a/b.lock.bak; do
  add "$p"; cls "$CLS"; not_deps; ck "ⓐ R1 $p → CLASS(deps 아님)" $?
  [ "$p" = a-locked.png ] && R1SHA="$SHA"
done
# 낱말 안에 lock 이 든 파일 → 그대로 deps 아님
for p in clock.py docs/unlock.md; do add "$p"; cls "$CLS"; not_deps; ck "ⓐ $p → CLASS(deps 아님)" $?; done
s1=$SECONDS

# ⓑ R2 — 실제 잠금 파일 13종 → FORBID deps(대소문자 무시 포함)
for p in yarn.lock package-lock.json pnpm-lock.yaml poetry.lock uv.lock Cargo.lock bun.lockb packages.lock.json \
         Pipfile.lock Gemfile.lock deno.lock flake.lock X.LOCK gradle.lockfile .terraform.lock.hcl; do
  add "$p"; cls "$CLS"; is_deps; ck "ⓑ R2 $p → FORBID kind=deps" $?
done
# ⓒ R3 — npm-shrinkwrap.json → FORBID deps
add web/npm-shrinkwrap.json; cls "$CLS"; is_deps; ck "ⓒ R3 web/npm-shrinkwrap.json → FORBID kind=deps" $?
# ⓓ R4 — 첫 갈래 그대로
for p in package.json pyproject.toml requirements-dev.txt; do add "$p"; cls "$CLS"; is_deps; ck "ⓓ R4 $p → FORBID kind=deps" $?; done
s2=$SECONDS

# ⓐ 변이 — 옛 정규식(«-lock» 뒤 아무 글자) 사본 → R1 a-locked.png 이 FORBID deps 로 돌아와야(이 시험이 그 변화를 잡는다)
M="$T/mut"; mkdir -p "$M"; cp "$BIN"/*.py "$M/"
python3 -I - "$M/autonomy_scope_rules.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
new = r'(^|/)([^/]*[-.]lock(b|file|\.(json|ya?ml|toml|hcl))?|npm-shrinkwrap\.json)$'
old = r'(^|/)[^/]*[-.]lock[^/]*$'
assert s.count(new) == 1; open(p, "w", encoding="utf-8").write(s.replace(new, old))
PY
ck "ⓐ 변이 사본 만들기" $?
SHA="$R1SHA"; cls "$M/autonomy_scope_classify.py"; is_deps; ck "ⓐ 변이(옛 정규식) → a-locked.png FORBID kind=deps(= 원본이면 FAIL 할 자리)" $?

# ⓔ bin·kit 같은 내용
cmp -s "$BIN/autonomy_scope_rules.py" "$MIR/autonomy_scope_rules.py"; ck "ⓔ bin·kit cmp0(autonomy_scope_rules.py)" $?
echo "단계별 초: R1=$((s1-s0)) R2~R4=$((s2-s1)) 변이+cmp=$((SECONDS-s2)) 합=$((SECONDS-s0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
