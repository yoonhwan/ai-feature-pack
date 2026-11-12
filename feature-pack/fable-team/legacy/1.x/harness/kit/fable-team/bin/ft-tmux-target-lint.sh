#!/usr/bin/env bash
# ft-tmux-target-lint.sh <파일|폴더>… | --range <A..B> [--repo <dir>] — pane 대상 명령의 «:» 빠짐을 막는다 (r1740 · 골 4)
#   ERR = 한 줄 안의 tmux 호출(셸 `tmux …` · 파이썬 `["tmux", …]`) 중 하위 명령이 has-session·kill-session 이 아닌데
#         `-t` 값이 «=» 로 시작하고 «:» 를 품지 않는 것 — 그 꼴은 pane 을 못 찾아 «빈 값 rc0» 이 된다(실패 표시 0).
#   파일·폴더 = 주어진 것 전부(폴더는 *.sh·*.py 재귀) · --range = 착지 게이트용: A..B 의 «추가된 줄» 만(*.sh·*.py)
#   출력 `ERR <파일>:<줄> tmux <명령> -t <값> — 끝 «:» 없음(…)` 줄마다 + 끝 줄 `OK tmux-target 0` | `ERR tmux-target <n>` · rc 0 / 1 / 2
#   주석(셸·파이썬 `#` 뒤)은 보지 않는다. 파이썬 f"={x}" 접두·tmux 전역 옵션(-L ft)·«\;» 뒤 둘째 명령도 본다.
#   변수에 담은 대상(`t="=$X"; tmux … -t "$t"`)·다른 언어는 범위 밖.
set -uo pipefail
USAGE="usage: $0 <파일|폴더>… | --range <A..B> [--repo <dir>]"
RANGE=""; REPO="."; ARGS=()
while [ $# -gt 0 ]; do case "$1" in --range) RANGE="${2:-}"; shift 2;; --repo) REPO="${2:-}"; shift 2;; -*) echo "$USAGE" >&2; exit 2;; *) ARGS+=("$1"); shift;; esac; done
[ -n "$RANGE" ] || [ "${#ARGS[@]}" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
exec python3 - "$RANGE" "$REPO" "${ARGS[@]}" <<'PY'
import os, re, subprocess, sys
rng, repo, args = sys.argv[1], sys.argv[2], sys.argv[3:]
SUF = (".sh", ".py")
GOPT = ("-L", "-S", "-f", "-c", "-T")   # 값을 먹는 tmux 전역 옵션 — `tmux -L ft has-session` 의 하위 명령은 has-session
BND = "\x01"   # 인자 경계 표지(«,») — 다음 인자가 -t 값에 섞이지 않게
SAFE = ("has-session", "kill-session", "list-clients", "switch-client", "show-environment", "set-environment", "list-windows", "list-panes", "attach-session", "rename-session", "lock-session", "detach-client")   # 계약 A1 고정 목록 — `-t` 가 target-session 인 명령만 «=<이름>» 이 맞다(tmux 단축 이름 has·attach·rename·lock·detach 는 목록 밖 — 실 tmux 3.6a arch 실측)
def git(*a):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, timeout=7)
    if r.returncode != 0: print(f"ERR tmux-target git {' '.join(a[:2])} 실패: {r.stderr.strip()[:80]}"); sys.exit(2)
    return r.stdout
def added(dif):   # diff 전문 → («추가된» 줄만, b 쪽 줄번호)
    out, name, num = [], "", 0
    for ln in dif.split("\n"):
        if ln.startswith("+++ b/"): name = ln[6:]
        elif ln.startswith("@@"):
            m = re.search(r"\+(\d+)", ln); num = int(m.group(1)) if m else 0
        elif ln[:1] == "+" and name.endswith(SUF): out.append((name, num, ln[1:])); num += 1
    return out
def file_srcs(paths, rev=None):   # 파일 목록 → (이름, 줄번호, 글) · rev 주면 그 판 내용
    out = []
    for p in paths:
        try: t = git("show", f"{rev}:{p}") if rev else open(p, encoding="utf-8", errors="replace").read()
        except OSError as e: print(f"ERR tmux-target {p} 못 읽음: {e.strerror}"); sys.exit(2)
        out += [(p, i, l) for i, l in enumerate(t.split("\n"), 1)]
    return out
def range_srcs(a, b):
    dif = git("diff", "--unified=0", "--no-renames", "--diff-filter=AM", f"{a}...{b}", "--", "*.sh", "*.py")
    return added(dif)
def code(ln):   # 따옴표 밖 # 뒤 주석 제거(근사 — bg-loop-lint 와 같은 규칙)
    q = None
    for i, ch in enumerate(ln):
        if q:
            if ch == q: q = None
        elif ch in "'\"": q = ch
        elif ch == "#" and (i == 0 or ln[i - 1] in " \t;"): return ln[:i]
    return ln
TMUX = re.compile(r"(?<![\w./-])(?:[\"']tmux[\"']|tmux)(?![\w-])")
def hit(ln):   # ERR 꼴이면 (하위 명령, -t 값), 아니면 None
    for m in TMUX.finditer(ln):
        pylike = ln[m.start()] in "\"'" and bool(re.match(r"[\"']?\s*,", ln[m.end():]))
        seg = ln[m.end():].replace('"', "").replace("'", "").replace("[", " ").replace("]", " ").replace("(", " ").replace(")", " ").replace(",", f" {BND} ")
        for ch in seg.split("\\;"):   # «\;» = tmux 명령 구분자 — 뒤 명령도 따로 본다
            toks = ch.split(); sub, i = "", 0
            while i < len(toks):   # 전역 옵션(-L ft 등)을 건너뛰고 하위 명령을 찾는다
                t = toks[i]
                if t == BND: i += 1; continue
                if t in GOPT: i += 2; continue
                if t.startswith("-"): i += 1; continue
                if re.fullmatch(r"[a-z][a-z0-9-]*", t): sub = t
                break
            if sub in SAFE: continue
            for j, t in enumerate(toks):
                if not (t == "-t" or t.startswith("-t=")): continue
                rest = ([t[3:]] if t.startswith("-t=") else []) + toks[j + 1:]
                val, started = "", False
                for r in rest:
                    if r == BND:
                        if started: break
                        continue
                    if r.startswith("#"): break   # 다음 인자 = 값 아님(cwd·#{...} 가 «:» 를 데려오지 않게)
                    val += re.sub(r"^[rRbBfF]{1,2}(?==)", "", r); started = True   # f"={seat}" 의 f 접두
                    if not pylike: break
                if val.startswith("=") and ":" not in val: return sub, val
    return None
if rng:
    a, _, b = rng.partition("..")
    srcs = range_srcs(a, b)
else:
    srcs = []
    for x in args:
        ps = sorted(os.path.join(d, f) for d, _, fs in os.walk(x) for f in fs if f.endswith(SUF)) if os.path.isdir(x) else [x]
        srcs += file_srcs(ps)
bad = []
for name, num, text in srcs:
    r = hit(code(text))
    if r: bad.append((name, num, r[0], r[1]))
for name, num, sub, val in bad:
    print(f"ERR {name}:{num} tmux {sub} -t {val} — 끝 «:» 없음(pane·옵션 명령은 «=<이름>:» · 세션 대상 명령만 «=<이름>»)")
print(f"ERR tmux-target {len(bad)}" if bad else "OK tmux-target 0")
sys.exit(1 if bad else 0)
PY
