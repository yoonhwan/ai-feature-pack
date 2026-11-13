#!/usr/bin/env bash
# test_scope_secret_md_inline_r1387.sh — r1387: 문서(.md) 산문 줄의 «한 줄 코드 표기(백틱 한 쌍)» 는 셸 판정 밖이다.
#   문서에서 판정하는 줄 = 코드 울타리 안 · 4칸/탭 들여쓴 줄 · «$ »·«! »·«> » 줄머리 · 키 원문 모양(SECRET_SHAPE)은 모든 추가 줄 그대로.
#   S1·S2 산문 인라인 코드 → CLASS docs · S3 울타리 · S4 «$ » · S5 산문 키 원문 모양 · S6 .sh = FORBID 그대로
#   임시 origin(bare)+clone · 기준판 = 고치기 전 sha 고정 사본 · 변이는 사본에서만 · 실 저장소·네트워크 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() {  # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋
  local br="$1" p="$2"; shift 2
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"
}
run() { out="$(python3 "$1" classify "$(git -C "$W" rev-parse "$2")" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
BASE="$T/base"; mkdir -p "$BASE"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$BASE"/
BASE_SHA=ffdb15c1   # r1387 전 판(sha 고정 — HEAD 를 쓰면 커밋 뒤 고친 판이 기준판이 된다)
( cd "$HERE/.." && git show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/autonomy_scope_secret.py" ) > "$BASE/autonomy_scope_secret.py" \
  && ck "기준판 사본 = $BASE_SHA 판(sha 고정)" 0 || ck "기준판 사본" 1
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py"; ck "py_compile secret" $?

D='design/teams/ops/indices/대기'
BT='`'
KEY="AKI""A0123456789ABCDEF"   # 시험용 가짜 키 원문 모양(문자열 이어 붙이기 · 명령줄 인자 0)
mkf s1 "$D/s1.md" "함수: ${BT}layout_mode_want(env)${BT}"
mkf s2 "$D/s2.md" "값은 ${BT}printenv TOKEN${BT} 로 본다"
mkf s3 "$D/s3.md" '예시:' '```bash' 'printenv TOKEN' '```'
mkf s4 "$D/s4.md" '$ printenv TOKEN'
mkf s5 "$D/s5.md" "키는 $KEY 이다"
mkf s6 'scripts/x.sh' "echo ${BT}env${BT}"

run "$BASE/autonomy_scope_classify.py" s1; want "S1 기준판 = FORBID secret(오판 재현)" 3 "FORBID kind=secret"
run "$BASE/autonomy_scope_classify.py" s2; want "S2 기준판 = FORBID secret(오판 재현)" 3 "FORBID kind=secret"
run "$CLS" s1; want "S1 산문 «함수: \`layout_mode_want(env)\`» → CLASS(FORBID 0)" 0 "CLASS "
run "$CLS" s2; want "S2 산문 «값은 \`printenv TOKEN\` 로 본다» → CLASS(FORBID 0)" 0 "CLASS "
run "$CLS" s3; want "S3 울타리(bash) 안 «printenv TOKEN» → FORBID secret" 3 "FORBID kind=secret"
run "$CLS" s4; want "S4 줄머리 «\$ printenv TOKEN» → FORBID secret" 3 "FORBID kind=secret"
run "$CLS" s5; want "S5 산문 키 원문 모양 → FORBID secret" 3 "FORBID kind=secret"
run "$CLS" s6; want "S6 .sh «echo \`env\`» → FORBID secret(코드 판정 무변경)" 3 "FORBID kind=secret"

mut() {  # mut <이름> <원문> <바꿀 글> — 사본에서만
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$d"/
  python3 - "$d/autonomy_scope_secret.py" "$2" "$3" <<'PYM' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return 1; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PYM
}
LINE='if fence or ln.startswith(("    ", "\t")) or ln.lstrip().startswith(("! ", "$ ", "> ")):'
mut M1 "$LINE" 'if fence or ln.startswith(("    ", "\t")) or "`" in ln or ln.lstrip().startswith(("! ", "$ ", "> ")):'
run "$T/mut-M1/autonomy_scope_classify.py" s1; want "변이 1 백틱 항 복원 → S1 빨강" 3 "FORBID kind=secret"
run "$T/mut-M1/autonomy_scope_classify.py" s2; want "변이 1 백틱 항 복원 → S2 빨강" 3 "FORBID kind=secret"
mut M2 "$LINE" 'if ln.startswith(("    ", "\t")) or ln.lstrip().startswith(("! ", "$ ", "> ")):'
run "$T/mut-M2/autonomy_scope_classify.py" s3; want "변이 2 울타리 판정 삭제 → S3 빨강(0)" 0 "CLASS "
mut M3 "$LINE" 'if fence or ln.startswith(("    ", "\t")):'
run "$T/mut-M3/autonomy_scope_classify.py" s4; want "변이 3 줄머리 판정 삭제 → S4 빨강(0)" 0 "CLASS "

cmp -s "$BIN/autonomy_scope_secret.py" "$KIT/autonomy_scope_secret.py"; ck "kit 사본 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
