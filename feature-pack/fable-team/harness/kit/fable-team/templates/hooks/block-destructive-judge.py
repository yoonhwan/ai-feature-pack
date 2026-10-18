# block-destructive.sh 의 판정기(판정 466) — 훅이 python3 <이 파일> <명령> <JSON 원문> 으로 부른다.
# 출력 = PATTERN 을 볼 글자. 예외는 Inelig → 명령 전체(fail-closed).
import fnmatch, json, os, re, shlex, subprocess, sys
try: import block_destructive_hil as bdh   # R115 hil 싱크(같은 폴더)
except ImportError: bdh = None             # 없으면 hil 싱크만 꺼진다(fail-closed) — 나머지 판정은 그대로
ungit = bdh.ungit if bdh else list         # git 전역 옵션 정규화(없으면 훅의 sed 사본이 보강)
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
    def common(d):   # d 의 git 공용 폴더 — git 밖·없는 폴더면 None
        try: r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=d, capture_output=True, text=True, timeout=5)
        except OSError: return None
        return None if r.returncode else r.stdout.strip()
    # 절대경로 정본은 cwd 와 무관하게 «그 파일이 속한 리포» 의 루트 정본과 realpath 가 같을 때만 인정(R105 · cwd 가 git 밖이어도)
    g = common(cwd or ".") or (common(os.path.dirname(path)) if path.startswith("/") else None)
    if not g: return False
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
    g = dict(toks=toks, words=words, redirs=redirs, sep=sep, mbox=False, cmd="", kind="other", hil=bool(bdh and bdh.sink(words, redirs)),
             hd=any(o in ("<<", "<<-") for o, _ in redirs))
    ci = next((k for k, w in enumerate(words) if not ASSIGN.match(w)), None)
    if ci is None:
        g["kind"] = "assign" if words else "other"; return g
    g["cmd"] = words[ci]
    if "$" in g["cmd"]: raise Inelig                          # 명령 단어가 변수
    if ci == 0:
        g["mbox"] = g["cmd"] == "bash" and len(words) > 2 and words[2] in ("send", "relay", "ring") and mbox_ok(words[1], cwd, moved)
        if g["mbox"] or g["hil"] or text_sink(words, g["hd"]): g["kind"] = "sink"
    return g
def fileout(g):
    return g["cmd"] == "tee" or any(o in FILE_OUT and t != "/dev/null" and not (o == ">&" and re.fullmatch(r"\d+|-", t))
                                    for o, t in g["redirs"])
def judge(cmd, cwd, q=False):   # q = --inject: 단어를 셸 인용으로 되살려 낸다(따옴표 안 < 와 리다이렉트 < 구분 · DA x7 r1 Q2)
    if re.search(r"\$\(|`|[<>]\(|\$'|\\\n|\$\{!", cmd): raise Inelig
    text, body, n = strip_heredoc(cmd)
    moved = bool(MOVE.search(re.sub(r"[\\'\"]", "", cmd)))   # 이동 판별은 따옴표·역슬래시를 지운 글자로(c''d·c\d) — DA r1 Q2
    segs = [classify(t, s, cwd, moved) for t, s in split(text)]
    if sum(o in ("<<", "<<-") for g in segs for o, _ in g["redirs"]) != n: raise Inelig
    for g in segs:
        skip = g["mbox"]
        for t in ([] if g["hil"] else g["toks"]):   # hil 구간은 sink() 가 모양 전체를 이미 증명했다
            if skip and t == "bash": skip = False; continue
            b = os.path.basename(t)
            if b in CONSUMERS or INTERP.fullmatch(b): raise Inelig
    others = [g for g in segs if g["kind"] == "other"]
    if (bdh and bdh.bad(segs, cwd)) or others and any(fileout(g) for g in segs if g["kind"] == "sink"): raise Inelig
    for i, g in enumerate(segs):
        j = i
        while g["kind"] == "sink" and "|" in segs[j]["sep"].replace("||", "") and j + 1 < len(segs):
            j += 1
            if segs[j]["cmd"] not in FILTERS or any(a.startswith("--compress-program") for a in segs[j]["words"]): raise Inelig
    body_in = n and not any(g["hd"] and g["kind"] == "sink" and g["cmd"] in ("cat", "tee") for g in segs)
    lines = [" ".join(shlex.quote(t) if q and t not in REDIR and not re.fullmatch(r"[<>&|;()]+", t) else t for t in f(g["toks"])) for f in (list, ungit) for g in others] + ([body] if body_in else [])   # 원래 줄 먼저 · 정규화 줄은 «추가»(대체 0)
    if any(g["kind"] == "assign" for g in segs) and any("$" in l for l in lines): raise Inelig
    return "\n".join(lines)

# ── 판정 595: INJECT 전용 «게시 싱크» (--inject 모드만 · 위 judge()/기본 호출 경로는 불변) ──
# 따옴표 heredoc 본문이 게시 래퍼·gh·git commit 의 «본문 파일/값» 으로만 쓰이고 실행 소비 구간이 전부 «F 가 아님»(구간 순서대로 대입 해소
# + realpath ≠ F)으로 증명될 때만 본문을 뺀다. 증명 못 하면 Inelig = 명령 전체 검사(fail-closed).
WRAPPER = re.compile(r"(^|/)ft-gh-as-tank\.sh$")
VALUE_OPT = {"--body", "-b", "--title", "-t", "-m", "--message"}
STATE_CMDS = {"read", "declare", "typeset", "local", "mapfile", "readarray", "getopts", "-exec", "-execdir", "-ok", "-okdir"}
HD_SUB = re.compile(r"\$\(\s*cat\s+<<-?\s*(['\"])([A-Za-z_][A-Za-z0-9_]*)\1[ \t]*\n(.*?)\n[ \t]*\2[ \t]*\n[ \t]*\)", re.S)
def post_file_arg(w, k):   # w[k] 가 게시 싱크의 «본문 파일» 자리인가
    b, p = os.path.basename(w[0]), (w[k - 1] if k else "")
    if b == "bash" and len(w) > 2 and WRAPPER.search(w[1]):
        return w[2] in ("create", "comment", "comment-edit", "pr-comment", "pr-create") and k == 4 or w[2] in ("edit", "pr-edit") and p == "--body-file"
    if b == "gh": return w[1:2] in (["pr"], ["issue"]) and w[2:3] in (["create"], ["comment"], ["edit"]) and p in ("--body-file", "-F")
    return b == "git" and w[1:2] == ["commit"] and p in ("-F", "--file")
def touches(t, base):   # 토큰 t 가 파일 F(끝 이름 base)를 가리킬 수 있는가 — 같은 끝 이름(./F·$D/F) 또는 글롭
    return base in t or bool(re.search(r"[*?\[]", t) and fnmatch.fnmatchcase(base, os.path.basename(t)))
def resolve(t, env):   # $VAR·${VAR} 를 앞 구간의 리터럴 대입 값으로 — 풀리지 않는 $·백틱이 남으면 None(증명 불가)
    r = re.sub(r"\$(\w+|\{\w+\})", lambda m: env.get(m.group(1).strip("{}"), "\0"), t)
    return None if re.search(r"[$`\0]", r) else r
def rp(p, cwd, moved):   # realpath(심링크를 따라감) — 상대경로는 cwd 가 확실할 때만 · 글롭·~·{} 면 None
    if p is None or re.search(r"[*?\[\]{}~]", p) or (not os.path.isabs(p) and (moved or not cwd)): return None
    return os.path.realpath(os.path.join(cwd or "/", p))
def envs_before(segs):   # 구간 i 는 «앞 구간까지의» `VAR=리터럴`·`export VAR=리터럴` 대입만으로 검사 — 값에 $·백틱·글롭이 있거나 += 등 다른 꼴이면 그 변수는 미해소
    env, out = {}, []
    for toks, _ in segs:
        out.append(dict(env))
        if toks[0] == "unset": [env.pop(t, None) for t in toks[1:]]
        elif toks[0] == "export" or all(ASSIGN.match(t) for t in toks):
            for t in (toks[1:] if toks[0] == "export" else toks):
                m = re.fullmatch(r"(\w+)=(.*)", t, re.S)
                if m and resolve(m[2], {}) == m[2] and not re.search(r"[*?\[{~]", m[2]): env[m[1]] = m[2]
                else: env.pop(re.match(r"\w*", t)[0], None)
    return out + [env]   # 마지막 항목 = 전 구간 최종 env (구간 검사에는 쓰지 않는다)
def runs_only_other(toks, env, frp, cwd, moved):   # 허용 꼴: bash|sh|INTERP + 옵션 없는 스크립트 경로 · 첫 단어 = 경로 — 그 경로 realpath ≠ F
    g = classify(toks, "", cwd, moved)
    if not g["cmd"]: return True
    ws = g["words"][g["words"].index(g["cmd"]):]
    c = resolve(ws[0], env)
    if c is None or (ws[0] == "printf" and "-v" in ws) or any(t in STATE_CMDS for t in ws): return False
    b = os.path.basename(c)
    if b in ("bash", "sh") or INTERP.fullmatch(b): s = resolve(ws[1], env) if len(ws) > 1 and not ws[1].startswith("-") else None
    elif b in CONSUMERS: return False
    elif "/" in c: s = c
    else: return True
    p = rp(s, cwd, moved)
    return p is not None and p != frp
def inject_view(cmd, cwd):
    out = cmd
    for m in reversed(list(HD_SUB.finditer(cmd))):              # F2: 게시 싱크 본문 옵션 값 "$(cat <<'D' … D)"
        if any(l.strip(" \t") == m.group(2) for l in m.group(3).split("\n")): continue   # 본문 안 구분자 줄 = 셸은 거기서 끝낸다
        w = re.split(r"[;&|\n]", cmd[:m.start()])[-1].replace('"', " ").split()
        b = os.path.basename(w[0]) if w else ""
        if len(w) >= 3 and w[-1] in VALUE_OPT and (b == "gh" and w[1] in ("pr", "issue") and w[2] in ("create", "comment", "edit")
                                                   or b == "git" and w[1] == "commit"):
            out = out[:m.start()] + out[m.end():]
    if out != cmd: return out
    text, _, n = strip_heredoc(cmd)                             # F1: cat > F <<'D' 본문 + F 는 게시 싱크 본문 파일 자리에만
    opens = [m.group(1) for m in re.finditer(r"<<-?\s*([^\s;&|()<>]+)", cmd)]
    if n != 1 or not opens or any(o[0] not in "'\"" for o in opens) or "`" in text: raise Inelig   # 따옴표 없는 구분자 = 본문 안 $(…) 실행
    moved, segs, F, hi = bool(MOVE.search(re.sub(r"[\\'\"]", "", cmd))), split(text), None, 0
    for i, (toks, _) in enumerate(segs):
        if "<<" in toks or "<<-" in toks:
            outs = [toks[i + 1] for i, t in enumerate(toks) if t in (">", ">>", ">|") and i + 1 < len(toks)]
            if toks[0] != "cat" or len(outs) != 1: raise Inelig
            F, hi = outs[0], i
    envs = envs_before(segs)
    fr = resolve(F, envs[hi]) if F else None; frp = rp(fr, cwd, moved); base = os.path.basename((fr or "").rstrip("/"))
    if frp is None or not base: raise Inelig
    for i, ((toks, _), env) in enumerate(zip(segs, envs)):
        if i == hi: continue
        if not runs_only_other(toks, env, frp, cwd, moved): raise Inelig
        for k, t in enumerate(toks):
            r = resolve(t, env)
            if (touches(t, base) or r is not None and (touches(r, base) or rp(r, cwd, moved) == frp)) and not (r == fr and post_file_arg(toks, k)):
                raise Inelig
    return text
inj = sys.argv[1:2] == ["--inject"] and len(sys.argv) == 4      # 판정 595: 인자 4개일 때만 INJECT 모드 (명령이 글자 그대로 `--inject` 여도 기본 경로)
cmd = sys.argv[2] if inj else sys.argv[1]
try:
    cwd = json.loads(sys.argv[-1]).get("cwd"); cwd = cwd if isinstance(cwd, str) else None
    try: print(judge(cmd, cwd, inj))
    except Inelig: print(inject_view(cmd, cwd) if inj else bdh.norm_all(cmd) if bdh else cmd)
except Exception:
    print(cmd if inj or not bdh else bdh.norm_all(cmd))   # 파싱 실패(주석·짝 안 맞는 따옴표)도 보수 경로 — hil 자격은 판정 전체 실패로 0
