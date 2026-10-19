#!/usr/bin/env bash
# ft-bg-loop-lint.sh <파일|폴더>… | --range <A..B> [--repo <dir>] — 상한·종료 사건 없는 감시 루프를 막는다 (r448 · 골 6)
#   ERR = `while` 루프(그 루프의 done 줄까지) 안에 `sleep` 과 `>>` 가 같이 있는데 ft-bg-loop.sh 래퍼 밖인 것.
#   래퍼 안 = `while` 과 같은 줄(또는 `\` 로 이어진 앞 줄)에서 그보다 앞에 `ft-bg-loop` 가 있음. 주석(# 뒤)은 보지 않는다.
#   파일·폴더 = 주어진 것 전부(폴더는 *.sh 재귀) · --range = 착지 게이트용: A..B 에서 «추가·수정»된 design/**/*.sh · tests/e2e/**/*.sh 만(B 의 내용 · 옛 증거는 범위 밖)
#   출력 `ERR <파일>:<줄> …` 줄마다 + 끝 줄 `OK bg-loop 0` | `ERR bg-loop <n>` · rc 0 = 0건 · 1 = ERR · 2 = usage·git 실패
set -uo pipefail
USAGE="usage: $0 <파일|폴더>… | --range <A..B> [--repo <dir>]"
RANGE=""; REPO="."; ARGS=()
while [ $# -gt 0 ]; do case "$1" in --range) RANGE="${2:-}"; shift 2;; --repo) REPO="${2:-}"; shift 2;; -*) echo "$USAGE" >&2; exit 2;; *) ARGS+=("$1"); shift;; esac; done
[ -n "$RANGE" ] || [ "${#ARGS[@]}" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
exec python3 - "$RANGE" "$REPO" "${ARGS[@]}" <<'PY'
import os, re, subprocess, sys
rng, repo, args = sys.argv[1], sys.argv[2], sys.argv[3:]
def git(*a):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, timeout=7)
    if r.returncode != 0: print(f"ERR bg-loop git {' '.join(a[:2])} 실패: {r.stderr.strip()[:80]}"); sys.exit(2)
    return r.stdout
files = []   # (표시 이름, 내용)
if rng:
    a, _, b = rng.partition("..")
    for p in git("diff", "--name-only", "--diff-filter=AM", f"{a}...{b}").splitlines():
        if p.endswith(".sh") and (p.startswith("design/") or p.startswith("tests/e2e/")): files.append((p, git("show", f"{b}:{p}")))
for x in args:
    paths = [os.path.join(d, f) for d, _, fs in os.walk(x) for f in sorted(fs) if f.endswith(".sh")] if os.path.isdir(x) else [x]
    for p in paths:
        try: files.append((p, open(p, encoding="utf-8", errors="replace").read()))
        except OSError as e: print(f"ERR bg-loop {p} 못 읽음: {e.strerror}"); sys.exit(2)
def code(ln):   # 따옴표 밖 # 뒤 주석 제거(근사)
    q = None
    for i, ch in enumerate(ln):
        if q:
            if ch == q: q = None
        elif ch in "'\"": q = ch
        elif ch == "#" and (i == 0 or ln[i - 1] in " \t;"): return ln[:i]
    return ln
KW = re.compile(r"(?:^|[\s;&|({'\"])(while|do|done)(?=$|[\s;&|)}'\"])")
bad = 0
for name, text in files:
    lines = [code(l) for l in text.split("\n")]
    for i, ln in enumerate(lines):
        for m in re.finditer(r"(?:^|[\s;&|({'\"])while(?=\s)", ln):
            depth, body, j, k, end = 0, [], i, m.end(), None
            while j < len(lines) and end is None:   # 그 while 의 짝 done 까지(do/done 깊이)
                seg = lines[j][k:]
                for t in KW.finditer(seg):
                    if t.group(1) == "do": depth += 1
                    elif t.group(1) == "done":
                        depth -= 1
                        if depth == 0: end = j; break
                body.append(seg if end is None else lines[j][k:]); j, k = j + 1, 0
            blk = "\n".join(body)
            if not (re.search(r"\bsleep\b", blk) and ">>" in blk): continue
            pre, p = ln[:m.start() + 1], i - 1
            while p >= 0 and lines[p].rstrip().endswith("\\"): pre = lines[p] + pre; p -= 1
            if "ft-bg-loop" in pre: continue
            bad += 1
            print(f"ERR {name}:{i + 1} while+sleep+>> 루프가 ft-bg-loop.sh 래퍼 밖 — ft-bg-loop.sh --seat <좌석> --max-sec <n> --stop-file <경로> -- <명령> 로 감싼다")
print(f"ERR bg-loop {bad}" if bad else "OK bg-loop 0"); sys.exit(1 if bad else 0)
PY
