# block-destructive.sh 의 판정기(판정 466) — 훅이 python3 <이 파일> <명령> <JSON 원문> 으로 부른다.
# 출력 = PATTERN 을 볼 글자. 예외는 Inelig → 명령 전체(fail-closed).
import json, os, re, shlex, subprocess, sys

class Inelig(Exception): pass          # 예외 자격 없음 → 명령 전체에 PATTERN

REDIR = {"<", ">", ">>", "<<", "<<<", ">|", "&>", "&>>", ">&", "<&", "<>", "<<-"}
FILE_OUT = {">", ">>", ">|", "&>", "&>>", ">&", "<>"}
CONSUMERS = {"bash", "sh", "zsh", "dash", "ksh", "fish", "eval", "source", ".", "exec", "xargs", "env", "sudo", "nohup",
             "time", "timeout", "nice", "watch", "coproc", "command", "builtin", "function", "{", "}", "!", "ssh"}
INTERP = re.compile(r"(python|perl|ruby)[0-9.]*|node")
FILTERS = {"head", "tail", "wc", "sort", "uniq", "cut"}
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=")
HD_OPEN = re.compile(r"<<(-?)\s*([^\s;&|()<>]+)")

MOVE = re.compile(r"(^|[\s;&|(])(cd|pushd|popd)(?=[\s;&|)]|$)")   # 이동 단어 뒤 구분자(; & | ))도 경계 — DA r2 Q2
def mbox_ok(path, cwd, moved):
    # 정본 mbox = JSON cwd 의 git 루트 + /.fable-team/comm/mbox.sh (realpath 일치만 · 절대경로는 글자 그대로 `..` 0)
    # 상대경로 정본 = JSON cwd 기준 realpath 일치 · 명령에 cd/pushd/popd 가 있으면 실행 위치가 달라 인정 0(R64)
    if re.search(r"[*?\[\]{}$~`]", path) or (path.startswith("/") and ".." in path.split("/")): return False
    if not path.startswith("/") and (moved or not cwd): return False
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       cwd=cwd or ".", capture_output=True, text=True, timeout=5)
    if r.returncode: return False
    g = r.stdout.strip()
    want = os.path.realpath(os.path.join(os.path.dirname(g) if os.path.basename(g) == ".git" else g, ".fable-team/comm/mbox.sh"))
    return os.path.isfile(want) and os.path.realpath(os.path.join(cwd or ".", path)) == want
def strip_heredoc(cmd):
    # → (본문 뺀 명령 · 따옴표 밖 개행은 `;`, 본문, 개수). 따옴표 밖 `<<` 만 센다 · 2개 이상·미종결·여는 줄 따옴표 불일치 = Inelig
    lines, out, body, n, q, esc, li = cmd.split("\n"), [], [], 0, None, False, 0
    while li < len(lines):
        line = lines[li]; li += 1
        i, delim, dash = 0, None, ""
        while i < len(line):
            ch = line[i]
            if esc: esc = False
            elif ch == "\\" and q != "'": esc = True
            elif q: q = None if ch == q else q
            elif ch in "'\"": q = ch
            elif ch == "#" and (i == 0 or line[i - 1] in " \t;&|"): break
            elif line.startswith("<<<", i): i += 3; continue
            elif line.startswith("<<", i):
                m = HD_OPEN.match(line, i)
                if not m or n: raise Inelig
                n, dash, delim = 1, m.group(1), re.sub(r"['\"\\]", "", m.group(2))
                i = m.end(); continue
            i += 1
        out.append(line + ("\n" if q else ";"))
        if delim is None: continue
        if q: raise Inelig
        while True:
            if li >= len(lines): raise Inelig
            b = lines[li]; li += 1
            if (b.lstrip("\t") if dash else b) == delim: break
            body.append(b)
    return "".join(out)[:-1], "\n".join(body), n
def split(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""                                      # 주석 처리 없음 — 보이는 글자는 전부 본다
    segs, cur = [], []
    for tok in lex:
        if re.fullmatch(r"[;&|()]+", tok):
            if "(" in tok or ")" in tok or (not cur and "|" in tok): raise Inelig
            if cur: segs.append((cur, tok))
            cur = []
        else: cur.append(tok)
    return segs + ([(cur, "")] if cur else [])
def text_sink(w, hd):
    c = w[0]
    return (c in ("echo", "grep", "egrep", "fgrep") or (c == "printf" and "-v" not in w[1:])
            or (c == "git" and w[1:2] == ["commit"]) or (c in ("cat", "tee") and hd))
def classify(toks, sep, cwd, moved):
    words, redirs, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        if t in REDIR: redirs.append((t, toks[i + 1] if i + 1 < len(toks) else "")); i += 2
        elif re.fullmatch(r"[<>&|]+", t): raise Inelig
        else: words.append(t); i += 1
    g = dict(toks=toks, words=words, redirs=redirs, sep=sep, mbox=False, cmd="", kind="other",
             hd=any(o in ("<<", "<<-") for o, _ in redirs))
    ci = next((k for k, w in enumerate(words) if not ASSIGN.match(w)), None)
    if ci is None:
        g["kind"] = "assign" if words else "other"; return g
    g["cmd"] = words[ci]
    if "$" in g["cmd"]: raise Inelig                          # 명령 단어가 변수
    if ci == 0:
        g["mbox"] = g["cmd"] == "bash" and len(words) > 2 and words[2] in ("send", "relay", "ring") and mbox_ok(words[1], cwd, moved)
        if g["mbox"] or text_sink(words, g["hd"]): g["kind"] = "sink"
    return g
def fileout(g):
    return g["cmd"] == "tee" or any(o in FILE_OUT and t != "/dev/null" and not (o == ">&" and re.fullmatch(r"\d+|-", t))
                                    for o, t in g["redirs"])
def judge(cmd, cwd):
    if re.search(r"\$\(|`|[<>]\(|\$'|\\\n|\$\{!", cmd): raise Inelig
    text, body, n = strip_heredoc(cmd)
    moved = bool(MOVE.search(re.sub(r"[\\'\"]", "", cmd)))   # 이동 판별은 따옴표·역슬래시를 지운 글자로(c''d·c\d) — DA r1 Q2
    segs = [classify(t, s, cwd, moved) for t, s in split(text)]
    if sum(o in ("<<", "<<-") for g in segs for o, _ in g["redirs"]) != n: raise Inelig
    for g in segs:
        skip = g["mbox"]
        for t in g["toks"]:
            if skip and t == "bash": skip = False; continue
            b = os.path.basename(t)
            if b in CONSUMERS or INTERP.fullmatch(b): raise Inelig
    others = [g for g in segs if g["kind"] == "other"]
    if others and any(fileout(g) for g in segs if g["kind"] == "sink"): raise Inelig
    for i, g in enumerate(segs):
        j = i
        while g["kind"] == "sink" and "|" in segs[j]["sep"].replace("||", "") and j + 1 < len(segs):
            j += 1
            if segs[j]["cmd"] not in FILTERS or any(a.startswith("--compress-program") for a in segs[j]["words"]): raise Inelig
    body_in = n and not any(g["hd"] and g["kind"] == "sink" and g["cmd"] in ("cat", "tee") for g in segs)
    lines = [" ".join(g["toks"]) for g in others] + ([body] if body_in else [])
    if any(g["kind"] == "assign" for g in segs) and any("$" in l for l in lines): raise Inelig
    return "\n".join(lines)

cmd = sys.argv[1]
try:
    cwd = json.loads(sys.argv[2]).get("cwd")
    print(judge(cmd, cwd if isinstance(cwd, str) else None))
except Exception:
    print(cmd)
