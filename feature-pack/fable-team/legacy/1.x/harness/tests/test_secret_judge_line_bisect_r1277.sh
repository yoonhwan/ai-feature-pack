#!/usr/bin/env bash
# test_secret_judge_line_bisect_r1277.sh — ft_secret_judge.plan() 줄 번호: 문장마다 «처음부터 개행 세기» → 개행 위치 표 1회 + 이분 탐색 (r1277 · 반례 R1~R4 · 변이 1)
# 옛 판 plan() 을 이 시험 안에 그대로 두고(t.count) 새 판과 «같은 글에 같은 결과인가» 를 대조한다. 입력 = 셸 글 문자열만 · git·네트워크·tmux 0 · 이 파일을 다시 부르지 않음.
# R1 큰 글(줄 5,000 · 명령 문장 2,000 · 판정 걸림 0) → [] · 새 판 시간 ≤ 옛 판의 1/3 (같은 프로세스에서 둘 다 잼)
# R2 판정 걸림이 첫 줄·가운데·끝 줄 → 줄 번호가 옛 판과 같음 + line_no() 가 «모든 글자 위치»(개행 자리 포함)에서 옛 t.count+1 과 같음
# R3 heredoc 이 낀 글 → 옛 판과 같은 결과
# R4 마지막 줄에 개행 없음 · 빈 글 · 개행만 → 옛 판과 같은 결과
# 변이 1: bisect_left → bisect_right (line_no 안) → R2 FAIL (개행 자리 줄 번호 어긋남).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$HERE/.."
BIND="${FT_R1277_BIND:-$HARNESS/bin}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }

cat > "$T/run.py" <<'EOF'
import re, sys, time
sys.path.insert(0, sys.argv[1])
import ft_secret_judge as j

def old_plan(text):  # r1277 이전 plan() — 줄 번호 두 곳만 t.count 로 센다(나머지 줄은 새 판과 글자 그대로)
    t = j.strip_heredocs(text)
    found = [(t.count("\n", 0, o) + 1, why) for o, why in j.check(t)]
    if re.match(r"#!.*\s-[a-z]*x", t):
        found.append((1, "셔뱅 -x 로 값이 추적 출력됨"))
    fn, tracked = j.func_lines(t), set()
    for s in j.parse(t):
        line, to_file = t.count("\n", 0, s.start) + 1, j.out_state(s.redirs)[0]
        if s.args[:1] == ["set"] and any(re.fullmatch(r"-[a-zA-Z]*x[a-zA-Z]*", a) or a == "xtrace" for a in s.args[1:]):
            found.append((line, "set -x 로 값이 추적 출력됨"))
        elif tracked and s.args and not s.decl and s.args[0] not in j.EXEMPT and not to_file and line not in fn and not any(a.startswith("--format") for a in s.args):
            use = re.compile(r"\$\{?(?:%s)(?![A-Za-z0-9_#])" % "|".join(map(re.escape, tracked)))
            if any(use.search(a) for a in s.args[1:]):
                found.append((line, "비밀 변수를 인자로 넘긴 명령의 출력이 화면으로 감(>/dev/null 또는 --format 필요)"))
        if line not in fn:
            tracked |= {w.split("=")[0] for w in s.assigns + (s.args[1:] if s.decl else []) if "=" in w and any(j.has_target(x) for x in w.subs)}
    return sorted(set(found))

def same(name, text, expect_min=0):
    o, n = old_plan(text), j.plan(text)
    print(("OK " if o == n and len(n) >= expect_min else "BAD ") + name, len(n), n[:3])

fill = "echo step $((i+1)) done >> /tmp/x.log"
# R1 큰 글 — 줄 5,000 · 명령 문장 2,000 이상 · 판정 0
big = "\n".join(fill if k % 2 == 0 else "# 메모 " + "가" * 200 for k in range(5000)) + "\n"
t0 = time.perf_counter(); o = old_plan(big); t_old = time.perf_counter() - t0
t0 = time.perf_counter(); n = j.plan(big); t_new = time.perf_counter() - t0
print("OK R1 결과 [] 같음" if o == n == [] else "BAD R1 결과 %r %r" % (o[:2], n[:2]))
print("TIME old=%.2fs new=%.2fs" % (t_old, t_new))
print("OK R1 새 판 ≤ 옛 판 1/3" if t_new * 3 <= t_old else "BAD R1 새 판 %.2fs · 옛 판 %.2fs (1/3 초과)" % (t_new, t_old))

# R2 판정 걸림이 첫 줄·가운데·끝 줄
hit = "printenv GH_TOKEN"
body = [fill] * 200
for name, k in (("first", 0), ("middle", 100), ("last", 199)):
    ls = list(body); ls[k] = hit
    txt = "\n".join(ls) + "\n"
    same("R2 %s" % name, txt, 1)
    print("OK R2 %s 줄=%d" % (name, k + 1) if [x[0] for x in j.plan(txt)] == [k + 1] else "BAD R2 %s 줄 %r" % (name, j.plan(txt)))
sample = "echo a\n\nprintenv GH_TOKEN;\n\n  set -x\n# c\nx=$(op read op://v/i/f)\necho \"$x\"\n"
nl = [m.start() for m in re.finditer("\n", sample)]
bad = [p for p in range(len(sample) + 2) if j.line_no(nl, p) != sample.count("\n", 0, p) + 1]
print("OK R2 line_no 모든 위치(개행 자리 포함) 옛 값과 같음" if not bad else "BAD R2 line_no 어긋난 위치 %r" % bad[:5])
same("R2 sample", sample, 1)

# R3 heredoc 이 낀 글
h = "cat <<'EOF'\nprintenv GH_TOKEN\nEOF\nprintenv GH_TOKEN\ncat <<EOF2\n$(op read op://v/i/f)\nEOF2\necho done\n"
same("R3 heredoc", h, 1)
same("R3 heredoc 뒤 걸림", "cat <<'EOF'\nx\ny\nEOF\n" + "\n".join([fill] * 5) + "\nprintenv GH_TOKEN\n", 1)

# R4 마지막 줄 개행 없음 · 빈 글 · 개행만
same("R4 끝 개행 없음", "echo a\nprintenv GH_TOKEN", 1)
same("R4 빈 글", "", 0)
same("R4 개행만", "\n\n\n", 0)
same("R4 한 줄 개행 없음", "printenv GH_TOKEN", 1)
EOF

run() { timeout 70 python3 -I "$T/run.py" "$1" 2>&1; }  # -I 는 PYTHONPATH 를 무시 → 경로는 argv 로 넣는다

python3 -I -m py_compile "$BIND/ft_secret_judge.py"; ck "py_compile ft_secret_judge.py" $?
got="$(run "$BIND")"; echo "$got" | sed 's/^/  | /' | head -40
check_all() {  # $1=출력 → BAD 줄 수
  grep -c '^BAD' <<<"$1"
}
bads="$(check_all "$got")"; [ "$bads" = 0 ]; ck "R1~R4 옛 판과 같음 (BAD ${bads}줄)" $?
grep -q '^OK R1 새 판 ≤ 옛 판 1/3' <<<"$got"; ck "R1 시간 1/3 이하" $?
grep -q '^OK R2 line_no' <<<"$got"; ck "R2 line_no 모든 위치" $?

if [ "$BIND" = "$HARNESS/bin" ]; then
  cmp -s "$BIND/ft_secret_judge.py" "$HARNESS/kit/fable-team/bin/ft_secret_judge.py"; ck "kit bin 짝 cmp0" $?
  cmp -s "$BIND/ft_secret_judge.py" "$HARNESS/kit/fable-team/templates/hooks/ft_secret_judge.py"; ck "kit templates/hooks 짝 cmp0" $?
fi

# 변이 1 — 사본 bin 에서만. bisect_left → bisect_right 이면 R2 가 FAIL 이어야 한다(패치가 안 붙으면 FAIL).
d="$T/mut1"; mkdir -p "$d"; cp -p "$BIND"/ft_secret_*.py "$d/"
python3 -I - "$d/ft_secret_judge.py" <<'PYEOF' || { echo "FAIL 변이 1 패치가 원본에 안 붙음"; fail=$((fail+1)); }
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
a = "return bisect_left(nl, pos) + 1"
assert a in s, a
s = s.replace(a, "return bisect_right(nl, pos) + 1", 1).replace("from bisect import bisect_left", "from bisect import bisect_left, bisect_right", 1)
open(p, "w", encoding="utf-8").write(s)
PYEOF
m="$(run "$d")"
grep -q '^BAD R2' <<<"$m"; ck "변이 1 bisect_right → R2 가 FAIL 로 잡음" $?

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (secret-judge line bisect r1277)"; exit 0; }
echo "FAILED $fail"; exit 1
