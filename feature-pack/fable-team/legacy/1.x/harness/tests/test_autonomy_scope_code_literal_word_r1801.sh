#!/usr/bin/env bash
# test_autonomy_scope_code_literal_word_r1801.sh — r1801: 코드 리터럴 길에서 «셸 명령이 될 수 없는 자리»(첨자 키·dict 키·실행 아닌 함수 인자)의
# 한 낱말 리터럴은 크리티컬 secret 판정에서 빠진다 · 실행 호출(감싼 모든 호출)의 인자와 셸 갈래는 그대로 거절
# 임시 origin(bare)+clone · 커밋 2개(기준 M0 · 사례 1개) · 사례마다 파일 1개 · 기준판 = bin 사본 + 빼기 모듈을 «안 뺌» 으로 바꾼 판 · 변이는 사본에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"
BYZ="${R1801_BYZ:-$HOME/Project/Agent/BYZ-Work/BYZ-Agents}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() { local br="$1" p="$2"; shift 2   # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
crit() { out="$(python3 "$1" classify "$2" --repo "${3:-$W}" --critical 2>&1)"; rc=$?; }   # crit <classify.py> <sha> [리포]
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
cp_bin() { mkdir -p "$1"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$1"/; }
BASE="$T/base"; cp_bin "$BASE"
printf 'def drop(text, mask, *_opt):\n    return mask\n' > "$BASE/autonomy_scope_code_word.py"   # 기준판 = 빼기 없음(r1801 전 동작)
ck "기준판 사본(빼기 없음)" $?
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py" "$BIN/autonomy_scope_code_word.py"; ck "py_compile secret·code_word" $?
same() {  # same <이름> — 지금 가지(SHA)에서 새 판과 기준판 출력·rc 가 같다(바이트 비교)
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; local brc="$rc" bout="$out"
  crit "$CLS" "$SHA"; [ "$rc" = "$brc" ] && [ "$out" = "$bout" ]; ck "$1 (기준판 rc=$brc 같음)" $?; }
pass_new() { local n="$1" b="$2" p="$3"; shift 3   # ① 기준판 = 거절(오탐 재현) · 새 판 = CRITICAL-OK
  mkf "$b" "$p" "$@"
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; want "$n 기준판 = CRITICAL secret(오탐 재현)" 3 "CRITICAL kind=secret"
  crit "$CLS" "$SHA"; want "$n → CRITICAL-OK" 0 "CRITICAL-OK"; }
keep_no() { local n="$1" b="$2" p="$3"; shift 3   # ②④ 새 판도 거절 + 기준판과 같은 출력
  mkf "$b" "$p" "$@"; crit "$CLS" "$SHA"; want "$n → CRITICAL secret" 3 "CRITICAL kind=secret"; same "$n"; }
keep_eq() { local n="$1" b="$2" p="$3"; shift 3; mkf "$b" "$p" "$@"; same "$n"; }   # ③⑤ 기준판과 같은 출력

# ① 통과(새로) — 첨자 키 · dict 키 · 실행 아닌 함수 인자
pass_new "①a 첨자 키 result[\"set\"]" c1a app/a.py 'x = result["set"]'
pass_new "①b dict 키 \"set\": v" c1b app/b.py 'D = {' '    "set": v,' '}'
pass_new "①c 함수 인자 load(\"set\")" c1c app/c.py 'y = load("set")'
pass_new "①d 첨자 키 SHEET[\"env\"]" c1d app/d.py 'SHEET["env"]'
# ② 거절 유지 — 실행 호출 인자(직접·중첩·여러 줄)
keep_no "②a os.system 직접" c2a app/e.py 'import os' 'os.system("set")'
keep_no "②b subprocess.run 목록" c2b app/f.py 'import subprocess' 'subprocess.run(["env"])'
keep_no "②c check_output shell=True" c2c app/g.py 'import subprocess' 'subprocess.check_output("printenv", shell=True)'
keep_no "②d os.system(str(..)) 중첩" c2d app/h.py 'import os' 'os.system(str("set"))'
keep_no "②e subprocess.run([str(..)]) 중첩" c2e app/i.py 'import subprocess' 'subprocess.run([str("env")])'
keep_no "②f os.system(d[..]) 첨자 안" c2f app/j.py 'import os' 'os.system(d["set"])'
keep_no "②g 여러 줄 run(str(..))" c2g app/k.py 'import subprocess' 'subprocess.run(' '    str("set"))'
# ③ 키·인자 자리 아님 = 지금 판정 그대로
keep_eq "③a 대입 cmd = \"set\"" c3a app/l.py 'cmd = "set"'
keep_eq "③b 단독 줄 \"set\"" c3b app/m.py '"set"'
keep_eq "③c 공백 든 f-글" c3c app/n.py 'x = f"{a} set"'
# ④ 셸 갈래 거절 유지
keep_no "④a .sh 단독 set" c4a tools/a.sh 'set'
keep_no "④b .md bash 울타리 env" c4b docs/a.md '```bash' 'env' '```'
keep_no "④c 셔뱅 sh + 확장자 없음 set" c4c tools/run1 '#!/bin/sh' 'set'
# ⑤ 여러 줄 리터럴(ⓐ 위반) = 그대로
keep_eq "⑤ 세 따옴표 안 set" c5 app/o.py 'X = """' 'set' '"""'
# 보정1(DA HOLD #293603 동결 반례) — R1 주석 안 «)» 는 괄호가 아니다 · R2 첨자 «[» 앞 공백 허용 · 실행 이름표는 «(» 호출에만
keep_no "R1 주석 안 ) 뒤 os.system 여러 줄" f1 app/p.py 'import os' 'os.system( # close )' '    str("set"))'
pass_new "R2a 공백 첨자 result [ \"set\" ]" f2a app/q.py 'x = result [ "set" ]'
pass_new "R2b 첨자 run[\"set\"](호출 아님)" f2b app/r.py 'x = run["set"]'
keep_eq "R2c 키워드 뒤 목록 return [\"env\"] = 그대로" f2c app/s.py 'def f():' '    return ["env"]'

# 변이 M1·M3·M6 — 사본에서만 · 변이마다 원본으로 같은 사례 1회
mut() {  # mut <이름> <가지> <옛 글> <새 글> → 변이판 출력 out·rc
  local d="$T/mut_$1"; cp_bin "$d"
  python3 - "$d/autonomy_scope_code_word.py" "$3" "$4" <<'EOF'
import sys; p, old, new = sys.argv[1:4]; t = open(p, encoding="utf-8").read()
assert old in t, old
open(p, "w", encoding="utf-8").write(t.replace(old, new))
EOF
  ck "$1 변이 적용" $?; crit "$d/autonomy_scope_classify.py" "$(git -C "$W" rev-parse "$2")"; }
mut M1 c2a "and not any(EXEC.fullmatch(nm) for _c, _p, nm in stack):" ":"
want "M1 실행 이름표 검사 지움 → ②a os.system(\"set\") 가 통과(사례 FAIL = 잡힘)" 0 "CRITICAL-OK"
crit "$CLS" "$(git -C "$W" rev-parse c2a)"; want "M1 원본 ②a → CRITICAL secret" 3 "CRITICAL kind=secret"
mut M3 c3a "and _spot(text, mask, i, e, stack[-1] if stack else None)" "and True"
want "M3 자리 무관 → ③a cmd = \"set\" 가 통과(기준판과 달라짐 = 잡힘)" 0 "CRITICAL-OK"
crit "$CLS" "$(git -C "$W" rev-parse c3a)"; want "M3 원본 ③a → CRITICAL secret(기준판 그대로)" 3 "CRITICAL kind=secret"
mut M6 c2d "for _c, _p, nm in stack)" "for _c, _p, nm in stack[-1:])"
want "M6 가장 가까운 호출만 → ②d os.system(str(\"set\")) 가 통과(잡힘)" 0 "CRITICAL-OK"
crit "$CLS" "$(git -C "$W" rev-parse c2d)"; want "M6 원본 ②d → CRITICAL secret" 3 "CRITICAL kind=secret"

# ⑥ 실사건 — BYZ 리포 읽기만(임시 STATE · 승인 파일·장부 쓰기 0) · 커밋이 없으면 SKIP 1줄
for pr in 8454:9d7afea7d951264cb3908958f80d46aabb2606ed 8485:7e9ab25efa9201670dddeedd488b20c2b5117993; do
  h="${pr#*:}"
  if git -C "$BYZ" cat-file -e "$h^{commit}" 2>/dev/null; then
    crit "$CLS" "$h" "$BYZ"; want "⑥ 실사건 PR ${pr%%:*} → CRITICAL-OK" 0 "CRITICAL-OK"
  else echo "SKIP ⑥ 실사건 PR ${pr%%:*} (커밋 없음)"; fi
done

for f in autonomy_scope_secret.py autonomy_scope_code_word.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "kit 사본 cmp0 $f" $?; done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
