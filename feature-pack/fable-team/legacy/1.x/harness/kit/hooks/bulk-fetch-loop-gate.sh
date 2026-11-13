#!/bin/bash
# bulk-fetch-loop-gate — PreToolUse:Bash (r1399 · 11-05 issues 좌석 `for b in $(git ls-remote origin 'refs/heads/*') … git fetch` 52분 · load 87 · 전 팀 착지 멈춤)
# 왜: 원격 가지 6천여 개를 하나씩 fetch 하면 하루를 넘게 돈다. 좌석이 그 자리에서 쓰는 한 줄이라 실행 전 훅이 막는다.
# 동작: 명령 글자 + 그 명령이 실행하는 스크립트 파일 1단계(bg-cpu-burner-gate 와 같은 읽기 틀 · 따옴표·주석·heredoc 본문 가림)에서
#   ⓐ 가지 목록 원천 = git ls-remote (refs/heads 인자 · --heads · --branches · -h) · git branch -r|-a · git for-each-ref refs/remotes
#   ⓑ 그 목록을 도는 반복 = for … in(머리에 원천) · while/until(앞 파이프·뒤 `done < <(…)` 에 원천) · `… | xargs … git fetch`
#      (원천을 담은 변수 `X=$(원천)` 을 머리·앞뒤에서 $X 로 쓰면 같은 목록) · 반복 본문에 git … fetch
#   둘 다 참 = exit 2 + stderr 1줄. 가지 하나 fetch · fetch origin main · ls-remote 만 · refspec 1회 fetch = 통과.
# ★못 읽음★: 입력 JSON 깨짐·예외 = 통과 + stderr 경고(fail-open). 파일 없음·256KB 초과·바이너리 = 읽기 생략. 거절만 — kill·실행 0.
# 범위 밖: eval·base64 로 숨긴 명령 · 2단계 이상 스크립트 · Claude 밖 좌석(pi·codex — 이 훅을 타지 않는다).
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN bulk-fetch-loop-gate: python3 없음 — 통과" >&2; exit 0; }
python3 - <<'PYEOF'
import json, os, re, shlex, sys

MSG = '원격 가지 전부를 하나씩 fetch 금지(11-05 issues 52분 · load 87) · 대조는 origin/main 한 곳 · 꼭 필요하면 refspec 1회 fetch(25초)'
MAX_FILE = 256 * 1024
SHELLS = {"bash", "sh", "zsh", "dash"}
LEAD = {"do", "then", "else", "elif", "if", "while", "until", "{", "!", "time"}
WRAP = {"env", "nohup", "nice", "stdbuf", "command", "exec", "timeout", "gtimeout"}
GIT_OPT_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
W = r"(?<![\w./-])%s(?![\w./-])"
LOOP_RE = re.compile(W % r"(for|while|until)")
DODONE_RE = re.compile(W % "(do|done)")


def warn(msg):
    print(f"WARN bulk-fetch-loop-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


def blank(arr, a, b):
    for k in range(a, b):
        if arr[k] != "\n":
            arr[k] = " "


def mask(text):
    """(clean, masked) — 길이 같음. clean = 주석·heredoc 본문을 공백으로 · masked = clean 에서 따옴표 덩어리도 x 로(bg-cpu-burner-gate 사본)."""
    n, i, pending = len(text), 0, []
    clean, masked = list(text), list(text)
    while i < n:
        c = text[i]
        if c == "\\":
            if text[i + 1:i + 2] == "\n":
                clean[i] = clean[i + 1] = masked[i] = masked[i + 1] = " "
            else:
                masked[i:i + 2] = "x" * len(masked[i:i + 2])
            i += 2; continue
        if c in "'\"":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if c == '"' and text[j] == "\\" else 1
            masked[i:j + 1] = "x" * len(masked[i:j + 1])
            i = j + 1; continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;&|()"):
            j = text.find("\n", i); j = n if j < 0 else j
            blank(clean, i, j); blank(masked, i, j); i = j; continue
        if text.startswith("<<", i) and not text.startswith("<<<", i):
            m = re.match(r"<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", text[i:])
            if m:
                pending.append(m.group(2)); i += m.end(); continue
        if c == "\n" and pending:
            j = i + 1
            for d in pending:
                while j < n:
                    e = text.find("\n", j); e = n if e < 0 else e
                    line = text[j:e]
                    blank(clean, j, e); blank(masked, j, e); j = e + 1
                    if line.strip() == d:
                        break
            pending = []; i = j; continue
        i += 1
    return "".join(clean), "".join(masked)


def pieces(m):
    """masked 를 따옴표 밖 구분자(| & && || ; 줄바꿈 ( ) $( `)로 조각 — (시작, 끝)."""
    out, s, i, n = [], 0, 0, len(m)
    while i < n:
        two, c, step = m[i:i + 2], m[i], 0
        if two in ("&&", "||", "|&", "$("):
            step = 2
        elif c in "|;\n()`" or (c == "&" and two != "&>" and not (i and m[i - 1] in "<>")):
            step = 1
        if step:
            out.append((s, i)); s = i + step; i += step
        else:
            i += 1
    out.append((s, n))
    return out


def stop(m, i):
    """i 자리가 문장 끝(; 줄바꿈 & && ||)인가 — 단독 | 는 파이프라 이어진다 · >& &> 는 넘김이라 아니다."""
    c = m[i]
    if c in ";\n":
        return True
    if c == "&":
        return not (i and m[i - 1] in "<>") and m[i + 1:i + 2] != ">"
    return c == "|" and ("|" in (m[i - 1:i], m[i + 1:i + 2]))


def stmt_left(m, a):
    i, depth = a - 1, 0
    while i >= 0:
        if m[i] == ")":
            depth += 1
        elif m[i] == "(":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and stop(m, i):
            break
        i -= 1
    return i + 1


def stmt_right(m, b):
    i, depth = b, 0
    while i < len(m):
        if m[i] == "(":
            depth += 1
        elif m[i] == ")":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and stop(m, i):
            break
        i += 1
    return i


def tokens(clean, s, e):
    try:
        return shlex.split(clean[s:e], posix=True)
    except ValueError:
        return clean[s:e].split()


def unwrap(toks):
    i = 0
    while i < len(toks):
        t, base = toks[i], toks[i].rsplit("/", 1)[-1]
        if t in LEAD or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif base in WRAP:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^\d+(\.\d+)?[smhd]?$", toks[i])):
                i += 1
        else:
            break
    return toks[i:]


def git_subs(toks):
    """토큰 속 git 호출마다 (하위 명령, 인자) — 전역 옵션(-C 경로 등)은 건너뛴다."""
    for i, t in enumerate(toks):
        if t.rsplit("/", 1)[-1] != "git":
            continue
        j = i + 1
        while j < len(toks) and toks[j].startswith("-"):
            j += 2 if toks[j] in GIT_OPT_ARG else 1
        if j < len(toks):
            yield toks[j], toks[j + 1:]


def is_source(toks):
    for sub, args in git_subs(toks):
        if sub == "ls-remote" and any("refs/heads" in a or a in ("--heads", "--branches", "-h") for a in args):
            return True
        if sub == "branch" and any(a in ("--remotes", "--all") or (re.match(r"^-[A-Za-z]+$", a) and set(a[1:]) & {"r", "a"}) for a in args):
            return True
        if sub == "for-each-ref" and any(a.startswith("refs/remotes") for a in args):
            return True
    return False


def shell_c(et):
    if et and et[0].rsplit("/", 1)[-1] in SHELLS:
        for j in range(1, len(et) - 1):
            if not et[j].startswith("-"):
                return None
            if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", et[j]):
                return et[j + 1]
    return None


def has_fetch(toks, depth=0):
    if any(sub == "fetch" for sub, _ in git_subs(toks)):
        return True
    inner = next((shell_c(toks[k:]) for k in range(len(toks)) if shell_c(toks[k:]) is not None), None)
    if inner is None or depth >= 3:
        return False
    try:
        return has_fetch(shlex.split(inner, posix=True), depth + 1)
    except ValueError:
        return has_fetch(inner.split(), depth + 1)


def script_of(et, cwd):
    """실행되는 스크립트 파일 (경로, 본문) · 없음·256KB 초과·바이너리 = None."""
    if not et or shell_c(et) is not None:
        return None
    base, path = et[0].rsplit("/", 1)[-1], None
    if base in SHELLS:
        j = 1
        while j < len(et) and et[j].startswith("-"):
            j += 2 if et[j] in ("-o", "-O", "--rcfile", "--init-file") else 1
        path = et[j] if j < len(et) else None
    elif base in ("source", "."):
        path = et[1] if len(et) > 1 else None
    elif "/" in et[0]:
        path = et[0]
    if not path or "$" in path:
        return None
    p = os.path.join(cwd, os.path.expanduser(path))
    try:
        if not os.path.isfile(p) or os.path.getsize(p) > MAX_FILE:
            return None
        with open(p, "rb") as f:
            data = f.read()
    except OSError:
        return None
    return None if b"\0" in data[:8192] else (p, data.decode("utf-8", "replace"))


def scan(text, cwd, src=None, depth=0):
    """첫 거절 자리(글자 또는 파일:줄) · 없으면 None."""
    clean, m = mask(text)
    where = (lambda a, b: f"{src}:{text.count(chr(10), 0, a) + 1}") if src else \
            (lambda a, b: " ".join(clean[a:b].split())[:80])
    ps = [(s, e, tokens(clean, s, e)) for s, e in pieces(m) if clean[s:e].strip()]
    srcs = [(s, e) for s, e, t in ps if is_source(t)]
    names = [v.group(1) for s, _ in srcs for v in [re.search(r"([A-Za-z_]\w*)=\$\(\s*$", m[max(0, s - 64):s])] if v]

    def fed(regions):
        return any(s < b and e > a for s, e in srcs for a, b in regions) or any(
            re.search(r"\$\{?%s\b" % re.escape(v), clean[a:b]) for v in names for a, b in regions)

    if srcs:
        for lm in LOOP_RE.finditer(m):
            do = next(DODONE_RE.finditer(m, lm.end()), None)
            if do is None or do.group(1) != "do":
                continue
            level, done = 0, None
            for d in DODONE_RE.finditer(m, do.start()):
                level += 1 if d.group(1) == "do" else -1
                if level == 0:
                    done = d; break
            if done is None or not any(s < done.start() and e > do.end() and has_fetch(t) for s, e, t in ps):
                continue
            regions = [(lm.start(), do.start())]
            if lm.group(1) != "for":
                regions += [(stmt_left(m, lm.start()), lm.start()), (done.end(), stmt_right(m, done.end()))]
            if fed(regions):
                return where(lm.start(), done.end())
        for s, e, t in ps:
            et = unwrap(t)
            if et and et[0].rsplit("/", 1)[-1] == "xargs" and has_fetch(et[1:]) and fed([(stmt_left(m, s), s)]):
                return where(stmt_left(m, s), e)
    for s, e, t in ps:
        et = unwrap(t)
        inner = shell_c(et)
        if inner is not None and depth < 3:
            r = scan(inner, cwd, src, depth + 1)
            if r:
                return r
        f = script_of(et, cwd) if src is None and depth == 0 else None   # 1단계만 — 명령 글자가 부른 파일
        if f:
            r = scan(f[1], cwd, f[0], depth + 1)
            if r:
                return r
    return None


def main():
    try:
        d = json.loads(os.environ["INPUT"])
    except ValueError:
        warn("입력 JSON 을 읽지 못함")
    if not isinstance(d, dict):
        warn("입력 JSON 이 객체(dict)가 아님")
    if d.get("tool_name", "Bash") != "Bash":
        sys.exit(0)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    r = scan(cmd, d.get("cwd") or os.getcwd()) if cmd else None
    if not r:
        sys.exit(0)
    print(f"REJECT bulk-fetch-loop {r} — {MSG}", file=sys.stderr)
    sys.exit(2)


try:
    main()
except Exception as e:  # SystemExit 는 Exception 이 아니라 그대로 지나간다 — 파이썬 쪽 예외 전체 = 통과 + 경고(fail-open)
    warn(f"예외 {type(e).__name__}: {e}")
PYEOF
