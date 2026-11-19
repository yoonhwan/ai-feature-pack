#!/usr/bin/env bash
# test_autonomy_scope_py_heredoc_cat_set_r2300.sh — r2300: 셸 파일 안 «cat > 파일 <<'끝'» 인용 heredoc 본문의 «set(» 를 셸 set 으로 읽지 않는다
# · 파이썬 머리(«python3 - <<'PY'») 판정은 r2165 그대로 · cat 꼴은 리다이렉트 있는 «>|>> 파일 1낱말» + 뒤 글 공백뿐 + /dev/ 아님 일 때만
# 임시 origin(bare)+clone · 사례마다 «기준 커밋(머리 줄·끝 줄 있음) → origin/main» + «사례 커밋(본문 줄 추가)»
# 기준판 = 사본에서 CAT 줄을 «아무것도 못 맞추는» 꼴로 = r2165 판(python 머리만) · 변이는 사본에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; SEC="CRITICAL kind=secret"; Q="'"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
fx() { local br="$1" p="$2" at="$3" add="$4"; shift 4   # fx <가지> <경로> <끼울 자리(그 줄 앞 · 끝이면 줄 수+1)> <추가 줄> <기준 줄…> → SHA
  git -C "$W" checkout -q main; mkdir -p "$W/$(dirname "$p")"; printf '%s\n' "$@" > "$W/$p"
  cm "$W" "base $br"; git -C "$W" push -q origin main
  git -C "$W" checkout -q -B "$br"
  ADD="$add" awk -v n="$at" 'NR==n{print ENVIRON["ADD"]} {print} END{if (n > NR) print ENVIRON["ADD"]}' "$W/$p" > "$T/fx.tmp" && cat "$T/fx.tmp" > "$W/$p"
  cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; eval "SHA_$br=$SHA"; }
crit() { out="$(python3 "$1" classify "$2" --repo "$W" --critical 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
cp_bin() { mkdir -p "$1"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$1"/; }
apply() {  # apply <폴더> <파일> <정규식> <새 글> — 사본 안 줄 치환 1회 · 못 찾으면 rc1(기준판 없음 = 빨강)
  python3 - "$1/$2" "$3" "$4" <<'EOF'
import re, sys
p, pat, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
t2, n = re.subn(pat, lambda m: new, t, flags=re.M)
open(p, "w", encoding="utf-8").write(t2)
sys.exit(0 if n == 1 else 1)
EOF
}
applyl() {  # applyl <폴더> <파일> <옛 글> <새 글> — 글자 그대로 치환 1회
  python3 - "$1/$2" "$3" "$4" <<'EOF'
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
n = t.count(old)
open(p, "w", encoding="utf-8").write(t.replace(old, new))
sys.exit(0 if n == 1 else 1)
EOF
}
BASE="$T/base"; cp_bin "$BASE"
apply "$BASE" autonomy_scope_py_heredoc.py '^CAT = re\.compile\(.*$' 'CAT = re.compile(r"(?!)")'
ck "기준판 사본 = r2165 판(cat 머리 꼴 없음)" $?
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py" "$BIN/autonomy_scope_py_heredoc.py"; ck "py_compile secret·py_heredoc" $?
same() {  # same <이름> [바라는 rc] — 새 판과 기준판 rc · 출력 바이트 같음(+ 바라는 rc)
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; local brc="$rc" bout="$out"
  crit "$CLS" "$SHA"; [ "$rc" = "$brc" ] && [ "$out" = "$bout" ] && { [ -z "${2:-}" ] || [ "$rc" = "$2" ]; }; ck "$1 (기준판 rc=$brc 같음)" $?; }
pass_new() {  # pass_new <이름> — 기준판 = 거절(오탐 재현) · 새 판 = CRITICAL-OK
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; want "$1 기준판 = $SEC(오탐 재현)" 3 "$SEC"
  crit "$CLS" "$SHA"; want "$1 → CRITICAL-OK" 0 "CRITICAL-OK"; }
SB='#!/usr/bin/env bash'; PY="python3 - <<${Q}PY${Q}"; CAT="cat > \"\$LIB\" <<${Q}PY${Q}"; L1='    if bad or len(set(u["selectedRegions"])) < 3:'

# ① 실사건 — BYZ PR 9359 꼴(:51 «cat > "$LIB" <<'PY'» · :66 파이썬 본문 set()) · 머리 줄은 기준 커밋에 있음
fx c1 design/teams/ops/plan.sh 7 "$L1" "$SB" 'set -e' 'LIB="$(mktemp)"' "$CAT" 'import json, sys' 'def go(u, bad):' '    print("ok")' 'PY' 'python3 "$LIB"'
pass_new "① cat > \"\$LIB\" <<'PY' 본문 len(set(u[...]))"
# ② cat 머리 통과 꼴 4개
fx c2a tools/b2a.sh 2 'x = a | set(k)' "$CAT" 'PY'; pass_new "②a cat > \"\$LIB\" <<'PY'"
fx c2b tools/b2b.sh 2 'x = a | set(k)' "cat >> \"\$LOG\" <<${Q}PY${Q}" 'PY'; pass_new "②b cat >> \"\$LOG\" <<'PY'"
fx c2c tools/b2c.sh 2 'x = a | set(k)' "cat >lib.py <<${Q}PY${Q}" 'PY'; pass_new "②c cat >lib.py <<'PY'(공백 없음)"
fx c2d tools/b2d.sh 3 'x = a & set(k)' 'f() {' "  cat > \"\$1\" <<${Q}PY${Q}" 'PY' '}'; pass_new "②d 함수 안 들여쓴 cat 머리"
# ③ cat 머리 꼴 판정 8개 — 3a·3e·3f = 나머지 확인 조건 · 3b·3c·3g·3h = 머리 꼴 자체 · 3d = 통과
fx c3a tools/b3a.sh 2 'x = a & set(keep)' "cat > \"\$LIB\" <<PY" 'PY'; same "③a 비인용 cat <<PY(ⓑ)" 3
fx c3b tools/b3b.sh 2 'x = a & set(keep)' "cat <<${Q}E${Q}" 'E'; same "③b 리다이렉트 없는 cat <<'E'" 3
fx c3c tools/b3c.sh 2 'x = a & set(keep)' "cat > out>log <<${Q}E${Q}" 'E'; same "③c 대상 낱말에 «>»" 3
fx c3d tools/b3d.sh 2 'x = a & set(keep)' "cat > \"\$LIB\" <<${Q}PY${Q}" 'PY'; pass_new "③d cat > \"\$LIB\" <<'PY'(.sh 아님 확장자 없음)"  # noqa: E501
fx c3e tools/b3e.sh 3 'x = a & set(keep)' 'echo hi \' "$CAT" 'PY'; same "③e 앞 줄 \\ 이음(ⓓ)" 3
fx c3f tools/b3f.sh 3 'x = a & set(keep)' "$CAT" 'x = 1'; same "③f 끝 줄 없음(ⓔ)" 3
fx c3g tools/b3g.sh 2 'x = a & set(keep)' "cat > \"\$LIB\" <<${Q}PY${Q} >/dev/null" 'PY'; same "③g heredoc 뒤 글 있음(ⓖ)" 3
fx c3h tools/b3h.sh 2 'x = a & set(keep)' "cat > /dev/null <<${Q}E${Q}" 'E'; same "③h 대상 /dev/(ⓗ)" 3
k=0; for h in 'f|sh' 'f;bash' 'f&&sh' 'f&sh'; do k=$((k+1))
  fx "c3i$k" "tools/b3i$k.sh" 2 'x = a & set(keep)' "cat > $h <<${Q}E${Q}" 'E'; same "③i 대상에 «${h}» 꼴(본문이 셸로 실행됨)" 3; done
fx c3j tools/b3j.sh 2 'x = a & set(keep)' "cat > /de\\v/stdout <<${Q}E${Q}" 'E'; same "③j /de<>v/stdout(ⓗ 우회 꼴)" 3
# ④ 셸 set 꼴 불변
fx c4a tools/b4a.zsh 2 'set(N)' 'echo hi'; same "④a .zsh 맨 줄 set(N)" 3
fx c4b tools/b4b.sh 2 'set | tee /tmp/x' 'echo hi'; same "④b set | tee" 3
fx c4c tools/b4c.sh 2 '(set)' 'echo hi'; same "④c (set)" 3
fx c4d tools/b4d.sh 2 'echo "$(set)"' 'echo hi'; same "④d echo \"\$(set)\"" 3
# ⑤ 파이썬 머리 꼴 불변(r2165 계약 그대로)
fx c5a tools/b5a.sh 2 'x = a & set(keep)' "$PY" 'PY'; same "⑤a python3 - <<'PY' 본문 set(" 0
fx c5b tools/b5b.sh 2 'x = a & set(keep)' "python3 -c \"import sys\" <<${Q}PY${Q}" 'PY'; same "⑤b python3 -c(ⓒ)" 3
# ⑥ 확인된 cat 본문 안 거절 유지
fx c6a tools/b6a.sh 2 'x = set(a); set' "$CAT" 'PY'; same "⑥a 본문 x = set(a); set → 거절" 3
fx c6b tools/b6b.sh 2 $'x = set(a)\n-----BEGIN RSA PRIV''ATE KEY-----' "$CAT" 'PY'
crit "$CLS" "$SHA"; want "⑥b 본문 set( + 비밀 꼴 → 추가 줄에 비밀 꼴" 3 "$SEC 추가 줄에 비밀 꼴"; same "⑥b 기준판과 같음" 3
fx c6c tools/b6c.sh 4 'set(N)' "$CAT" 'x = 1' 'PY'; same "⑥c 끝 줄 뒤 셸 줄(본문 밖)" 3

# 변이 M1~M3 — 사본에서만 · 변이마다 원본으로 같은 사례 1회
mutre() {  # mutre <이름> <파일> <정규식> <새 글>
  MD="$T/mut_$1"; cp_bin "$MD"; apply "$MD" "$2" "$3" "$4"; ck "$1 변이 적용" $?; }
mcase() {  # mcase <변이 이름> <사례 가지> <변이판 rc> <원본 rc>
  local s; s="$(eval echo "\$SHA_$2")"
  crit "$MD/autonomy_scope_classify.py" "$s"; [ "$rc" = "$3" ]; ck "$1 변이판 $2 rc=$3(잡힘)" $?
  crit "$CLS" "$s"; [ "$rc" = "$4" ]; ck "$1 원본 $2 rc=$4" $?; }
mutre M1 autonomy_scope_py_heredoc.py '^CAT = re\.compile\(.*$' 'CAT = re.compile(r"(?!)")'
for c in c1 c2a; do mcase M1 "$c" 3 0; done
mutre M2 autonomy_scope_py_heredoc.py '^CAT = re\.compile\(.*$' 'CAT = re.compile(r"""^[ \t]*cat[ \t]+(?:>>?)?[ \t]*(?:[^ \t]+)?[ \t]*$""")'
mcase M2 c3b 0 3
mutl() {  # mutl <이름> <파일> <옛 글> <새 글>
  MD="$T/mut_$1"; cp_bin "$MD"; applyl "$MD" "$2" "$3" "$4"; ck "$1 변이 적용" $?; }
mutl M3 autonomy_scope_py_heredoc.py "\"'<>|;&()" "\"'|;&()"   # 대상 낱말에 «<» «>» 허용
mcase M3 c3c 0 3

for f in autonomy_scope_secret.py autonomy_scope_py_heredoc.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "kit 사본 cmp0 $f" $?; done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
