#!/usr/bin/env bash
# test_autonomy_scope_py_heredoc_set_r2165.sh — r2165: 셸 파일 안 «확인된 파이썬 인용 heredoc 본문» 의 «set(» 는 셸 set 으로 읽지 않는다
# · heredoc 밖 «set» · «set(N)» 과 확인 조건이 깨진 꼴은 기준판과 같은 rc · 출력(거절)
# 임시 origin(bare)+clone · 사례마다 «기준 커밋(머리 줄·끝 줄 있음) → origin/main» + «사례 커밋(줄 추가)» · 기준판 = bin 사본 + 가림 모듈을 빈 표로 · 변이는 사본에서만
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
BASE="$T/base"; cp_bin "$BASE"
printf 'def body_lines(full, shield):\n    return {}\n' > "$BASE/autonomy_scope_py_heredoc.py"   # 기준판 = 가림 없음(r2165 전 동작)
ck "기준판 사본(가림 없음)" $?
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py" "$BIN/autonomy_scope_py_heredoc.py"; ck "py_compile secret·py_heredoc" $?
same() {  # same <이름> [바라는 rc] — 새 판과 기준판 rc · 출력 바이트 같음(+ 바라는 rc)
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; local brc="$rc" bout="$out"
  crit "$CLS" "$SHA"; [ "$rc" = "$brc" ] && [ "$out" = "$bout" ] && { [ -z "${2:-}" ] || [ "$rc" = "$2" ]; }; ck "$1 (기준판 rc=$brc 같음)" $?; }
pass_new() {  # pass_new <이름> — 기준판 = 거절(오탐 재현) · 새 판 = CRITICAL-OK
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; want "$1 기준판 = $SEC(오탐 재현)" 3 "$SEC"
  crit "$CLS" "$SHA"; want "$1 → CRITICAL-OK" 0 "CRITICAL-OK"; }
SB='#!/usr/bin/env bash'; PY="python3 - <<${Q}PY${Q}"; L1='for p in sorted(set(cand) & set(keep)):'

# ① 오탐 재현 꼴
fx c1 tools/reap.sh 4 "$L1" "$SB" "exec python3 - \"\$A\" <<${Q}PY${Q}" 'cand, keep = [], []' 'PY'; pass_new "① exec python3 - \"\$A\" 본문 sorted(set(..) & set(..))"
# ② 머리 꼴 6개
fx c2a tools/a.sh 2 'x = a | set(k)' "python3 <<${Q}PY${Q}" 'PY'; pass_new "②a python3 <<'PY'"
fx c2b tools/b.sh 2 'if set(a) - set(b):' "out=\"\$(python3 - \"\$a\" <<${Q}PY${Q}" 'PY' ')"'; pass_new "②b out=\"\$(python3 - \"\$a\" <<'PY'"
fx c2c tools/c.sh 2 'x = a; set(k)' 'python3 - <<"PY"' 'PY'; pass_new "②c python3 - <<\"PY\""
fx c2d tools/d.sh 2 'x = a; set(k)' 'python3 - <<\PY' 'PY'; pass_new "②d python3 - <<\\PY"
fx c2e tools/e.sh 3 'x = a & set(k)' 'f() {' "  python3 - \"\$1\" <<${Q}PY${Q}" 'PY' '}'; pass_new "②e 함수 안 들여쓴 머리"
fx c2f tools/f.sh 2 $'\tx = a & set(k)' $'\tpython3 - <<-\'PY\'' $'\tPY'; pass_new "②f 탭 들여쓴 <<-'PY'"
# ③ 확장자 없음 · 셔뱅 .txt · heredoc 2개
fx c3a tools/runx 4 "$L1" "$SB" "$PY" 'x = 1' 'PY'; pass_new "③ 확장자 없음(셔뱅 bash)"
fx c3b notes/run.txt 4 "$L1" "$SB" "$PY" 'x = 1' 'PY'; pass_new "③' 셔뱅 .txt"
fx c3c tools/two.sh 7 "$L1" "$SB" "$PY" 'print(1)' 'PY' "$PY" 'print(2)' 'PY'; pass_new "③'' 둘째 heredoc 본문"
# ④ R1(사전 DA #325172) — 기준판 · 새 판 모두 거절 · 같은 출력
fx c4a tools/g.zsh 2 'set(N)' 'echo hi'; same "④a .zsh 맨 줄 set(N)" 3
fx c4b tools/h.zsh 2 'set(.)' 'echo hi'; same "④b .zsh 맨 줄 set(.)" 3
fx c4c tools/i.sh 2 "zsh -c ${Q}set(N)${Q}" 'echo hi'; same "④c .sh zsh -c 'set(N)'" 3
fx c4d tools/j.sh 2 "zsh -c ${Q}set(.)${Q}" 'echo hi'; same "④d .sh zsh -c 'set(.)'" 3
# ⑤ heredoc 밖 9꼴 — 기준판과 같음
k=0; for l in 'set' 'set | tee /tmp/x' '(set)' 'a && set' 'echo "$(set)"' 'x=1; set' "bash -c ${Q}set${Q}" 'set (x)' 'sorted(set)'; do
  k=$((k+1)); fx "c5_$k" "tools/o$k.sh" 2 "$l" 'echo hi'; same "⑤ heredoc 밖 «${l}»"; done
# ⑥ 확인 조건이 깨진 꼴 — 기준판과 같음(거절)
fx c6a tools/k6a.sh 2 'x = a & set(keep)' 'python3 - <<PY' 'PY'; same "⑥a 비인용 <<PY(ⓑ)" 3
fx c6b tools/k6b.sh 2 'x = a & set(keep)' "python3 -c \"import sys\" <<${Q}PY${Q}" 'PY'; same "⑥b python3 -c(ⓒ)" 3
fx c6c tools/k6c.sh 2 'set(N)' "python3 run.py <<${Q}PY${Q}" 'PY'; same "⑥c python3 run.py(ⓒ)" 3
fx c6d tools/k6d.sh 2 'set(N)' "zsh <<${Q}E${Q}" 'E'; same "⑥d zsh <<'E'(ⓒ)" 3
fx c6e tools/k6e.sh 2 'x = a & set(keep)' "true && $PY" 'PY'; same "⑥e true && python3 -(ⓒ)" 3
fx c6f tools/k6f.sh 2 'set(N)' "# $PY" 'PY'; same "⑥f 주석 줄 머리(ⓒ)" 3
fx c6g tools/k6g.sh 3 'set(N)' 'zsh -c "$(cat)" \' "$PY" 'PY'; same "⑥g 앞 줄 \\ 이음(ⓓ)" 3
fx c6h tools/k6h.sh 3 'set(N)' 'echo "' "$PY" 'PY' '"'; same "⑥h 여러 줄 큰따옴표 안 머리(ⓓ)" 3
fx c6i tools/k6i.sh 4 'set(N)' "cat <<${Q}X${Q}" "$PY" 'X' 'PY'; same "⑥i cat heredoc 본문 안 머리 + X 뒤(차례대로)" 3
fx c6j tools/k6j.sh 2 'set(N)' "$PY <<${Q}X${Q}" 'PY' 'X'; same "⑥j 머리 줄 heredoc 2개(ⓑ)" 3
fx c6k tools/k6k.sh 3 'x = a & set(keep)' "$PY" 'x = 1'; same "⑥k 끝 줄 없음(ⓔ)" 3
fx c6l tools/k6l.sh 4 'set(N)' "$PY" 'x = 1' 'PY'; same "⑥l 끝 줄 뒤 셸 줄(본문 밖)" 3
# ⑦ 확인된 본문 안 거절 유지
fx c7a tools/m7a.sh 2 'x = set(a); set' "$PY" 'PY'; same "⑦a 본문 x = set(a); set → 거절" 3
fx c7b tools/m7b.sh 2 'os.system("set")' "$PY" 'PY'; same "⑦b 본문 os.system(\"set\")"
# ⑧ 그 밖 불변 — 비밀 꼴(원문 0 · 조립) · .py · .md 울타리 · .yml
fx c8a tools/s8.sh 2 $'x = set(a)\n-----BEGIN RSA PRIV''ATE KEY-----' "$PY" 'PY'
crit "$CLS" "$SHA"; want "⑧a 본문 set( + 비밀 꼴 → 추가 줄에 비밀 꼴" 3 "$SEC 추가 줄에 비밀 꼴"; same "⑧a 기준판과 같음" 3
fx c8b app/p8.py 2 'x = set(a)' 'y = 1'; same "⑧b .py(셔뱅 없음) x = set(a)"
fx c8c docs/u8.md 3 'set(a)' '# t' '```' '```'; same "⑧c .md 울타리 안 set(a)"
fx c8d ci/w8.yml 2 '  - run: set' 'steps:'; same "⑧d .yml run: set"

# 변이 M1~M6 — 사본에서만 · 변이마다 원본으로 같은 사례 1회
mut() {  # mut <이름> <파일> <옛 글> <새 글> → 변이판 폴더 MD
  MD="$T/mut_$1"; cp_bin "$MD"
  python3 - "$MD/$2" "$3" "$4" <<'EOF'
import sys; p, old, new = sys.argv[1:4]; t = open(p, encoding="utf-8").read()
assert t.count(old) == 1, old
open(p, "w", encoding="utf-8").write(t.replace(old, new))
EOF
  ck "$1 변이 적용" $?; }
mcase() {  # mcase <변이 이름> <사례 가지> <변이판 rc> <원본 rc> — 변이판과 원본이 반대 결과
  local s; s="$(eval echo "\$SHA_$2")"
  crit "$MD/autonomy_scope_classify.py" "$s"; [ "$rc" = "$3" ]; ck "$1 변이판 $2 rc=$3(잡힘)" $?
  crit "$CLS" "$s"; [ "$rc" = "$4" ]; ck "$1 원본 $2 rc=$4" $?; }
mut M1 autonomy_scope_py_heredoc.py "    if not full:" "    if True:"
for c in c1 c2a c2b c2c c2d c2e c2f c3a c3b c3c; do mcase M1 "$c" 3 0; done
mut M2 autonomy_scope_secret.py 'return "\n".join(body.get(n, t) for n, t in items)' 'return "\n".join(body.get(n, shield_set_call(t)) for n, t in items)'
for c in c4a c4b; do mcase M2 "$c" 0 3; done
mut M3 autonomy_scope_py_heredoc.py 'if (len(ms) == 1 and not m.group("n")' 'if (len(ms) == 1'
mcase M3 c6a 0 3
mut M4 autonomy_scope_py_heredoc.py 'python[0-9.]*(?:[ \t]+-(?=[ \t])|[ \t]*$)")' 'python[0-9.]*")'
for c in c6b c6c; do mcase M4 "$c" 0 3; done
mut M5 autonomy_scope_py_heredoc.py 'and (off[i] in starts or off[i] + lead in starts)' 'and True'
mcase M5 c6h 0 3
mut M6 autonomy_scope_secret.py 'SET_CALL = re.compile(r"(?<![\w$])set(?=\()")' 'SET_CALL = re.compile(r"(?<![\w$])set\b")'
mcase M6 c7a 0 3

for f in autonomy_scope_secret.py autonomy_scope_py_heredoc.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "kit 사본 cmp0 $f" $?; done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
