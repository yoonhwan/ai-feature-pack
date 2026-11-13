#!/usr/bin/env python3
"""ft_launchd_llm_gate.py — launchd 잡이 LLM 을 부를 길이 남았으면 등록·갱신 0 (r1838 · 설계 r1 §2-2 G1~G6 · G1 = B master #295034).
check --plist P [--roots T] [--baseline B] [--allow A] [--project D] [--ft2-home D] → `ALLOW <label>` rc0 | `REJECT launchd-llm <label> <사유> <파일>:<줄>` rc1
check --root-dir D [--root-key K] [--label L] … → 폴더 통째(ft2 CURRENT 전환 전)            | `UNDECIDABLE launchd-llm <label> <사유>` rc3
list-dyncalls (--roots T | --root-dir D | --plist P) … → 동적 지점 줄 `<상대경로>\t<줄 sha16>\t<결합 sha256|->\t\t<파일>:<줄> <글>` (H1 초안 · 근거 칸 = 사람)
G1 입구(plist)에서 «글자 그대로» 닿는 파일만 따라가 통째 검사(절대경로·$0/BASH_SOURCE 기준 경로의 실행·source·import) · G2 입구 뿌리 밖 = REJECT
G3 따라갈 수 없는 지점(명령 자리 변수·eval·bash -c 변수·변수/상대 경로 스크립트·파이썬 비글자 첫 인자) = 기준선 `<상대경로>\t<줄 sha16>\t<결합 sha256>\t<근거>`
   에 있고 결합 sha(그 파일 + 글자 그대로 source/import 한 파일 전체)가 같을 때만 통과 · 변수 경로 source·뿌리 밖 import·미할당 변수 = 결합 불가 REJECT
G4 글자 그대로 LLM 호출 꼴 = REJECT(허용 장부 ts 있는 줄만 예외) · G6 판독 실패·25초 초과 = 판정 불가. 실행·네트워크 0 — 읽기만.
"""
import argparse, functools, hashlib, os, plistlib, re, sys, time  # noqa: E401

LLM = r"(?:claude|codex|opencode|pi|hermes|gemini|llm|aider|ollama)"
CMD_LLM = re.compile(rf"^(?:.*/)?{LLM}$")
NET = re.compile(r"api\.anthropic\.com|api\.openai\.com|generativelanguage\.googleapis\.com|:8317\b|:8790\b|/v1/messages|/chat/completions")
MODEL = re.compile(r"""--model[= ]+['"]?[\w./-]*(?:haiku|sonnet|opus|gpt|gemini)""", re.I)
INTERP = re.compile(r"^(?:.*/)?(?:bash|sh|zsh|dash|python3?(?:\.\d+)?)$")
SKIP_WORDS = {"if", "then", "do", "else", "elif", "while", "until", "!", "exec", "command", "nohup", "time", "builtin", "env", "{", "}"}
ZERO = r"""\$\{?(?:0|BASH_SOURCE(?:\[0\])?)(?::-\$0)?\}?"""
DIRS = [re.compile(r"""\$\(\s*cd\s+(?:--\s+)?"?\$\(\s*dirname\s+(?:--\s+)?"?(%s)"?\s*\)"?\s*&&\s*pwd(?:\s+-P)?\s*\)""" % ZERO),
        re.compile(r"""\$\(\s*dirname\s+(?:--\s+)?"?(%s)"?\s*\)""" % ZERO), re.compile(r"""\$\{(0|BASH_SOURCE(?:\[0\])?)%%/\*\}""")]
PYCALL = re.compile(r"(?<![\w.])(?:subprocess\.\w+|os\.(?:system|popen|exec\w*|spawn\w*)|runpy\.run_\w+|importlib\.import_module|__import__|exec|eval)\s*\(")
SDK = re.compile(r"\s*(?:from|import)\s+(?:anthropic|openai|litellm|google\.generativeai|langchain\w*)\b")  # LLM SDK import = 글자 그대로 호출 꼴
SHIM = "# ft-root-bin-shim:"
DEADLINE = [time.monotonic() + 25]


class Stop(Exception):
    pass


def sha(data):
    return hashlib.sha256(data.encode() if isinstance(data, str) else data).hexdigest()


@functools.lru_cache(maxsize=None)
def _read(path):
    return open(path, encoding="utf-8").read()


def read(path):
    if time.monotonic() > DEADLINE[0]:
        raise Stop("UNDECIDABLE", "25초 넘음", path)
    try:
        return _read(os.path.abspath(path))
    except (OSError, UnicodeDecodeError) as exc:
        raise Stop("UNDECIDABLE", f"판독 불가({type(exc).__name__})", path) from None


def kind(path, text=None):
    ext = os.path.splitext(path)[1]
    if ext in (".sh", ".bash", ".zsh"):
        return "sh"
    if ext == ".py":
        return "py"
    first = (text if text is not None else read(path)).split("\n", 1)[0]
    return "py" if first.startswith("#!") and "python" in first else "sh" if first.startswith("#!") and re.search(r"\b(ba|z|da)?sh\b", first) else None


def segments(line):
    """셸 한 줄 → 명령 조각들 · 따옴표 안 연산자는 자르지 않음 · $( … ) 안 = 새 조각(바깥 조각엔 $__SUB 자리 = 비글자 값)."""
    out, curs, stack, i = [], [[]], [None], 0
    while i < len(line):
        c, q, cur = line[i], stack[-1], curs[-1]
        if q == "'":
            stack.pop() if c == "'" else None
            cur.append(c)
        elif c == "\\":
            cur.append(line[i:i + 2])
            i += 1
        elif line.startswith("$((", i):  # 산술 = 명령 자리 0(안의 $( 만 새 조각)
            stack.append("A"), cur.append("$__A")
            i += 2
        elif line.startswith("$(", i):
            curs.append([]), stack.append(None)
            i += 1
        elif q == "A":
            if line.startswith("))", i):
                stack.pop()
                i += 1
        elif q is None and (line.startswith("[[", i) or line.startswith("=(", i)):  # [[ … ]] · 배열 할당 =( … ) = 자르지 않음
            stack.append("T" if c == "[" else "R"), cur.append(line[i:i + 2])
            i += 1
        elif q in ("T", "R") and line.startswith("]]" if q == "T" else ")", i):
            stack.pop(), cur.append("]]" if q == "T" else ")")
            i += 1 if q == "T" else 0
        elif q in ("T", "R") and c not in "'\"":
            cur.append(c)
        elif c == ")" and q is None and len(stack) > 1:
            out.append("".join(curs.pop())), stack.pop(), curs[-1].append("$__SUB")
        elif c in "'\"" and q in (None, c):
            stack.pop() if q == c else stack.append(c)
            cur.append(c)
        elif q is None and c in ";|&()`\n":
            out.append("".join(cur)), cur.clear()
        else:
            cur.append(c)
        i += 1
    return out + ["".join(c) for c in curs]


def quote_open(line):
    q, i = None, 0
    while i < len(line):
        c = line[i]
        if q is None and c == "#" and (i == 0 or line[i - 1] in " \t;"):
            return False
        if c == "\\" and q != "'":
            i += 1
        elif c in "'\"" and q in (None, c):
            q = None if q else c
        i += 1
    return q is not None


def shell_lines(text):
    """(줄 번호, 줄, 부분) — 줄 잇기(\\ 끝)는 한 줄로 · here-doc 본문 = python3 - 이면 "py" · 아니면 "data"."""
    lines, n, tag = text.splitlines(), 0, None
    while n < len(lines):
        start, line = n + 1, lines[n]
        if tag:
            tag = None if line.strip() == tag[0] else tag
            tag and (yield start, line, tag[1])
            n += 1
            continue
        while n + 1 < len(lines) and not re.search(r"<<-?\s*['\"]?\w", line.replace("<<<", "")) and (  # here-doc 머리·끝 뒤 «)"» 줄 = 잇지 않음
                (line.endswith("\\") and not line.lstrip().startswith("#")) or (quote_open(line) and not line.lstrip().startswith(")"))):
            n += 1  # 줄 잇기 · 여러 줄 따옴표(awk·python -c 본문) = 한 명령
            line = line[:-1] + " " + lines[n].strip() if line.endswith("\\") else line + "\n" + lines[n]
        m = re.search(r"""<<-?\s*(['"]?)(\w+)\1""", line.replace("<<<", ""))
        tag = m and (m.group(2), "py" if re.search(r"\bpython[\d.]*\s+(?:-\S*\s+)*-(?:\s|$)", line) else "data")
        yield start, line, "sh"
        n += 1


def tsv(path, need):
    if not path or not os.path.exists(path):
        return []
    return [ln.split("\t") for ln in read(path).splitlines() if ln.strip() and not ln.startswith("#") and len(ln.split("\t")) >= need]


class Gate:
    def __init__(self, a, roots):
        self.roots, self.label = roots, a.label
        self.shims = {r[1].strip() for r in a.root_rows if r[0] == "@shim"}
        self.base = {(r[0], r[1]): r[2] for r in tsv(a.baseline, 4) if r[3].strip()}
        self.allowed = any(r[0] == a.label and re.fullmatch(r"\d+\.\d+", r[1].strip()) for r in tsv(a.allow, 2))
        self.seen, self.memo, self.dyn = set(), {}, []

    def rel(self, path):
        real = os.path.realpath(path)
        for key, root in self.roots.items():
            if real == root or real.startswith(root + os.sep):
                return f"{key}/{os.path.relpath(real, root)}"
        return real

    def reject(self, why, path, n):
        raise Stop("REJECT", why, f"{self.rel(path)}:{n}")

    def literal(self, line, path, n):
        if not self.allowed and (NET.search(line) or MODEL.search(line)):
            self.reject("글자 그대로 LLM 호출", path, n)

    def assigns(self, path, zero, seen=None):
        """(변수 → 값|None) — 그 파일과 글자 그대로 source 한 파일의 할당 · 값 2개 이상·비글자 = None(할당은 됨)."""
        if seen is None and (path, zero) in self.memo:
            return self.memo[(path, zero)]
        top, seen, out = seen is None, seen if seen is not None else set(), {}
        if path in seen:
            return out
        seen.add(path)
        for ln in (self.dirs(x, path, zero) for x in read(path).splitlines()):
            for m in re.finditer(r"(?:^|[;&\s])(?:local\s+|export\s+|readonly\s+|declare\s+[-\w]*\s*)?([A-Za-z_]\w*)=(\"[^\"]*\"|'[^']*'|\S*)", ln):
                val = self.resolve(m.group(2), path, zero, out)
                out[m.group(1)] = val if out.get(m.group(1), val) == val and m.group(1) not in out or out.get(m.group(1)) == val else None
            for m in re.finditer(r"\b(?:for|read(?:\s+-\w+)*)\s+([A-Za-z_]\w*)", ln):
                out.setdefault(m.group(1), None)
            src = re.match(r"\s*(?:\.|source)\s+(\S+)", ln)
            target = src and self.resolve(src.group(1), path, zero, out)
            if target and os.path.isfile(target):
                out.update({k: v for k, v in self.assigns(target, zero, seen).items() if k not in out})
        if top:
            self.memo[(path, zero)] = out
        return out

    @staticmethod
    def dirs(text, path, zero):  # $(dirname "$0") 꼴 = 그 스크립트 폴더(source 된 파일의 $0 = 부른 스크립트 · BASH_SOURCE = 자기)
        for rx in DIRS:
            text = rx.sub(lambda m: os.path.dirname(os.path.abspath(path if "BASH_SOURCE" in m.group(1) else zero)), text)
        return text

    def resolve(self, word, path, zero, env):
        """글자 그대로 경로면 절대경로 · 아니면 None(따라갈 수 없음)."""
        word = self.dirs(word, path, zero)
        word = re.sub(r"\$\{(\w+)\}|\$(\w+)", lambda m: env.get(m.group(1) or m.group(2)) or "\0$", word)
        word = word.replace('"', "").replace("'", "")
        return None if "$" in word or "`" in word or "\0" in word else word

    def bind(self, path, zero):
        """(결합 sha256, 결합 불가 이유|None) — 파일 + 글자 그대로 source/import 파일 전체를 정해진 순서(앞에서부터·처음 등장)로 잇는다."""
        if ("bind", path, zero) not in self.memo:
            self.memo[("bind", path, zero)] = self._bind(path, zero)
        return self.memo[("bind", path, zero)]

    def _bind(self, path, zero):
        files, why, todo = [], None, [path]
        while todo:
            f = todo.pop(0)
            if f in files:
                continue
            files.append(f)
            text, env = read(f), self.assigns(f, zero)
            for n, ln in enumerate(text.splitlines(), 1):
                if kind(f, text) == "sh" and (src := re.match(r"\s*(?:\.|source)\s+(\S+)", self.dirs(ln, f, zero))):
                    t = self.resolve(src.group(1), f, zero, env)
                    todo += [t] if t and os.path.isfile(t) else []
                    why = why or (None if t and os.path.isfile(t) else f"source 경로 불가 {self.rel(f)}:{n}")
                elif kind(f, text) == "py" and (imp := re.match(r"\s*(?:from\s+([\w.]+)\s+import|import\s+([\w., ]+))", ln)):
                    for mod in re.split(r"\s*,\s*", (imp.group(1) or imp.group(2)).strip()):
                        top = mod.split()[0].split(".")[0] if mod else ""
                        local = os.path.join(os.path.dirname(f), top + ".py")
                        if os.path.isfile(local):
                            todo.append(local)
                        elif top and top not in sys.stdlib_module_names and top != "__future__":
                            why = why or f"뿌리 밖 import {top} {self.rel(f)}:{n}"
        return sha("".join(f"{os.path.relpath(f, os.path.dirname(path))}\0{read(f)}\0" for f in files)), why

    def dynamic(self, path, n, line, zero, var=None):
        key, h, (b, why) = self.rel(path), sha(line.strip())[:16], self.bind(path, zero)
        if var and not why and not re.fullmatch(r"\d+|[@*#]", var) and var not in self.assigns(path, zero):
            why = f"미할당 변수 ${var}"
        self.dyn.append((key, h, "-" if why else b, f"{key}:{n} {line.strip()[:120]}"))
        if why:
            self.reject(f"결합 불가({why})", path, n)
        if (key, h) not in self.base:
            self.reject("검사 불가 동적 실행", path, n)
        if self.base[(key, h)] != b:
            self.reject("검사 불가 동적 실행(기준선 결합 불일치)", path, n)

    def follow(self, path, zero=None):
        path, zero = os.path.abspath(path), zero or path
        if (path, zero) in self.seen:
            return
        self.seen.add((path, zero))
        text = read(path)
        k = kind(path, text)
        if k is None and "\0" in text:  # 뿌리 안 이진 실행 파일 = 읽을 수 없음
            raise Stop("UNDECIDABLE", "판독 불가(이진 파일)", path)
        k = k or "sh"  # shebang 없는 글 파일을 실행 = 셸이 읽는다
        m = re.search(rf"^{re.escape(SHIM)} (\S+) → LIVE_BIN", text, re.M)
        if m and sha(text.replace(m.group(1), "@NAME@")) in self.shims:  # 생성된 루트 shim(사람 h 로 sha 등록) = ../LIVE_BIN/<이름> 로 글자 그대로
            live = read(os.path.join(os.path.dirname(path), "..", "LIVE_BIN")).split("\n")[0].strip()
            return self.follow(os.path.join(live, m.group(1)))
        if k == "py":
            return self.py(path, list(enumerate(text.splitlines(), 1)), zero)
        self.sh(path, text, zero)

    def sh(self, path, text, zero):
        env, heredoc = self.assigns(path, zero), {"py": [], "data": []}
        for n, raw, part in shell_lines(text):
            if part != "sh":
                heredoc[part].append((n, raw))
                continue
            if raw.lstrip().startswith("#") or not raw.strip():
                continue
            line = self.dirs(re.sub(r"(^|\s)#[^'\"]*$", "", raw), path, zero)
            self.literal(line, path, n)
            if src := re.match(r"\s*(?:\.|source)\s+(\S+)", line):
                t = self.resolve(src.group(1), path, zero, env)
                self.follow(t, zero) if t and os.path.isfile(t) else self.reject("결합 불가(source 경로 불가)", path, n)
                continue
            for seg in segments(line):
                words = [w for w in seg.split() if w.strip("\"'")]
                while words and (words[0] in SKIP_WORDS or re.match(r"^[A-Za-z_]\w*=", words[0]) or words[0] == "timeout"):
                    words = words[2:] if words[0] == "timeout" else words[1:]
                if not words or words[0] in ("case", "for", "[[", "[", "test", "local", "export", "declare", "readonly", "return"):
                    continue
                cmd = words[0].strip("\"'")
                if cmd.startswith("$") or cmd == "eval":  # 명령 자리 변수 = 늘 동적 지점(기준선) · 뿌리 안 경로로 풀리면 그 파일도 따라감
                    var = re.match(r"\$\{?(\w+|[@*#])", cmd)
                    self.dynamic(path, n, raw, zero, var and var.group(1))
                    t = self.resolve(cmd, path, zero, env)
                    t and os.path.isfile(t) and self.rel(t) != os.path.realpath(t) and self.follow(t)
                elif CMD_LLM.match(cmd) and not self.allowed:
                    self.reject("글자 그대로 LLM 호출", path, n)
                elif INTERP.match(cmd):
                    args = [] if "-" in words[1:] else [w for w in words[1:] if not w.startswith(("-", "<", ">", "2>", "$__SUB"))]  # «-» = 표준입력 스크립트
                    if "-c" in words[1:] or any(w.startswith("-") and "c" in w and not w.startswith("--") for w in words[1:2]):
                        self.dynamic(path, n, raw, zero)  # -c 문자열 = 따라갈 수 없음(글자 그대로여도 기준선)
                    elif args:
                        t = self.resolve(args[0], path, zero, env)
                        self.follow(t) if t and t.startswith("/") and os.path.isfile(t) else self.dynamic(path, n, raw, zero)
                    elif "<<" not in seg:  # 스크립트 없이 표준입력 = 따라갈 수 없음
                        self.dynamic(path, n, raw, zero)
                elif "/" in cmd:
                    t = self.resolve(cmd, path, zero, env)
                    if not (t and t.startswith("/")):
                        self.dynamic(path, n, raw, zero)
                    elif os.path.isfile(t) and self.rel(t) != os.path.realpath(t):
                        self.follow(t)

        for n, raw in heredoc["data"]:
            self.literal(raw, path, n)
        heredoc["py"] and self.py(path, heredoc["py"], zero)  # python3 - <<'PY' 본문 = 파이썬으로 검사

    def py(self, path, pairs, zero):
        nxt = {n: raw for n, raw in pairs}
        for n, raw in pairs:
            if raw.lstrip().startswith("#") or not raw.strip():
                continue
            self.literal(raw, path, n)
            if not self.allowed and (re.search(rf"""\[\s*['"](?:[\w./-]*/)?{LLM}['"]""", raw) or SDK.match(raw)):
                self.reject("글자 그대로 LLM 호출", path, n)
            if imp := re.match(r"\s*(?:from\s+([\w.]+)\s+import|import\s+([\w., ]+))", raw):
                for mod in re.split(r"\s*,\s*", (imp.group(1) or imp.group(2)).strip()):
                    local = os.path.join(os.path.dirname(path), mod.split()[0].split(".")[0] + ".py") if mod else ""
                    os.path.isfile(local) and self.follow(local)
            for m in PYCALL.finditer(raw):
                arg = raw[m.end():].strip() or nxt.get(n + 1, "").strip()
                lit = re.match(r"""\[?\s*(['"])([^'"]+)\1\s*(?:,\s*(['"])([^'"]+)\3)?""", arg)
                if not lit:
                    self.dynamic(path, n, raw, zero)
                    continue
                first = lit.group(2).split()[0] if lit.group(2).split() else ""
                second = lit.group(4) or (lit.group(2).split() + ["", ""])[1]
                if CMD_LLM.match(first) and not self.allowed:
                    self.reject("글자 그대로 LLM 호출", path, n)
                if INTERP.match(first):
                    self.follow(second) if second.startswith("/") and os.path.isfile(second) else self.dynamic(path, n, raw, zero)


def code_files(folder):
    for d, dirs, files in os.walk(folder):
        dirs[:] = sorted(x for x in dirs if x not in ("tests", "__pycache__") and not x.startswith("."))
        for f in sorted(files):
            p = os.path.join(d, f)
            if os.path.isfile(p) and ".bak" not in f and not f.startswith(".") and kind(p, open(p, "rb").read(256).decode("utf-8", "replace")):
                yield p


def roots_of(a):
    if a.root_dir:
        return {a.root_key: os.path.realpath(a.root_dir)}
    live = a.project and os.path.join(a.project, ".fable-team", "LIVE_BIN")
    cur = os.path.join(a.ft2_home, "CURRENT")
    sub = {"__BYZ_ROOT__": a.project, "__LIVE_BIN__": live and os.path.isfile(live) and read(live).split("\n")[0].strip(),
           "__FT2_CURRENT__": os.path.isfile(cur) and os.path.join(a.ft2_home, "versions", read(cur).strip()), "__HOME__": os.path.expanduser("~")}
    out = {}
    for key, tpl, *_ in (r for r in a.root_rows if not r[0].startswith("@")):
        if all(sub.get(p) for p in re.findall(r"__\w+?__", tpl)):
            path = re.sub(r"__\w+?__", lambda m: sub[m.group(0)], tpl.strip())
            os.path.isdir(path) and out.setdefault(key, os.path.realpath(path))
    return out


def judge(a, gate):
    if a.root_dir or not a.plist:
        for f in code_files(a.root_dir or "/dev/null") if a.root_dir else (f for r in gate.roots.values() for f in code_files(r)):
            gate.follow(f)
        return
    args = [str(x) for x in (a.doc.get("ProgramArguments") or [a.doc.get("Program", "")])]
    for x in args:
        gate.literal(x, a.plist, 0)
    a0 = args[0]
    if CMD_LLM.match(a0) and not gate.allowed:
        raise Stop("REJECT", "글자 그대로 LLM 호출", f"{a0}:0")
    if INTERP.match(a0) or os.path.basename(a0) == "env":
        rest = [x for x in args[1:] if not re.match(r"^[A-Za-z_]\w*=", x)] if os.path.basename(a0) == "env" else args[1:]
        rest = rest[1:] if os.path.basename(a0) == "env" and rest and INTERP.match(rest[0]) else rest
        if any(x.startswith("-") and "c" in x and not x.startswith("--") for x in rest[:2]):  # -c 문자열 = 뿌리 밖 · 사람이 본 글자면 기준선(plist:<label>)
            code = rest[[i for i, x in enumerate(rest) if x.startswith("-")][0] + 1] if len(rest) > 1 else ""
            key = f"plist:{gate.label}"
            gate.dyn.append((key, sha(code.strip())[:16], sha(code), f"{a.plist}:0 -c {code[:80]}"))
            if gate.base.get((key, sha(code.strip())[:16])) != sha(code) and a.verb == "check":
                raise Stop("REJECT", "검사 범위 밖 입구(-c 문자열 · 기준선 없음)", f"{a.plist}:0")
            return
        script = next((x for x in rest if not x.startswith("-")), "")
    elif gate.rel(a0) != os.path.realpath(a0):
        script = a0
    else:
        return  # 스크립트가 아닌 외부 실행 파일 1개(gcloud·colima) — 이름·인자는 위에서 G4 로 봄
    if gate.rel(script) == os.path.realpath(script):
        raise Stop("REJECT", "검사 범위 밖 입구", f"{script}:0")
    gate.follow(script)


def load_plist(path):
    raw = open(path, "rb").read()
    try:
        return plistlib.loads(raw)
    except Exception:  # noqa: BLE001 — 주석 속 «--» 같은 엄격 XML 위반(launchd·plutil 은 받음) = 주석을 걷고 1회 더 · 그래도 실패 = 판정 불가
        return plistlib.loads(re.sub(rb"<!--.*?-->", b"", raw, flags=re.S))


def main(argv):
    p = argparse.ArgumentParser(prog="ft_launchd_llm_gate.py")
    p.add_argument("verb", choices=["check", "list-dyncalls"])
    for opt in ("--plist", "--roots", "--baseline", "--allow", "--root-dir", "--label"):
        p.add_argument(opt)
    p.add_argument("--project", default=os.environ.get("FT_ROOT"))
    p.add_argument("--ft2-home", default=os.path.expanduser("~/.claude/fable-team/ft2"))
    p.add_argument("--root-key", default="ft2-current")
    a = p.parse_args(argv)
    label = a.label or (a.plist and os.path.basename(a.plist).removesuffix(".plist")) or a.root_key
    try:
        a.doc = load_plist(a.plist) if a.plist else {}
        label = a.label = a.label or a.doc.get("Label") or label
        here = os.path.dirname(os.path.abspath(__file__))  # 기본 뿌리 표 = bin/../kit · kit/fable-team/bin/../.. 의 launchd-roots.tsv
        a.roots = a.roots or next((p for p in (f"{here}/../kit/launchd-roots.tsv", f"{here}/../../launchd-roots.tsv") if os.path.isfile(p)), "")
        a.root_rows = tsv(a.roots, 2) if not a.root_dir else []
        if not a.root_dir and not os.path.isfile(a.roots):
            raise Stop("UNDECIDABLE", "뿌리 표 없음", a.roots)
        gate = Gate(a, roots_of(a))
        if a.verb == "list-dyncalls":  # 사람 h 나열 도구 = 25초 상한 없음(판정 아님)
            DEADLINE[0] = float("inf")
            gate.dynamic = lambda path, n, line, zero, var=None: gate.dyn.append(  # noqa: E731 — 판정 없이 나열만
                (gate.rel(path), sha(line.strip())[:16], Gate.bind(gate, path, zero)[0] if not Gate.bind(gate, path, zero)[1] else "-", f"{gate.rel(path)}:{n} {line.strip()[:120]}"))
            gate.reject = lambda *x: None
            gate.allowed = True
        judge(a, gate)
    except Stop as s:
        print(f"{s.args[0]} launchd-llm {label} {s.args[1]} {s.args[2]}")
        return 1 if s.args[0] == "REJECT" else 3
    except Exception as exc:  # noqa: BLE001 — 판독 실패는 무엇이든 판정 불가(traceback 0 · G6)
        print(f"UNDECIDABLE launchd-llm {label} 판독 불가({type(exc).__name__}) {a.plist or a.root_dir}")
        return 3
    if a.verb == "list-dyncalls":
        print("\n".join("\t".join((k, h, b, "", w)) for k, h, b, w in dict.fromkeys(gate.dyn)))
        return 0
    print(f"ALLOW {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
