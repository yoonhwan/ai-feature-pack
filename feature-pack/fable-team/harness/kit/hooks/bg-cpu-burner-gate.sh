#!/bin/bash
# bg-cpu-burner-gate — PreToolUse:Bash (r523 · 10-20 v65 나노 loadrep.sh 의 `nice -n 19 yes > /dev/null &` 고아 → CPU 100 · 오빠 손 kill)
# 왜: «burner 쓰지 마라» 는 메모리 글뿐이라 못 막았다. 스크립트가 강제로 끊기면 trap EXIT 정리가 안 돌고 백그라운드 소모기가 주인 없이 남는다.
# 동작(모든 리포 · 머신 전체 자원): 명령 글자 + 그 명령이 실행하는 스크립트 파일 1단계(bash|sh|zsh|dash|source|. 다음 인자 · 첫 낱말이 경로)를
#   따옴표·주석·heredoc 본문을 가린 뒤 조각내 «시간 상한 없는 백그라운드 CPU 소모기» 가 있으면 exit 2 + stderr 1줄.
#   소모기 = 감싸개(env·nohup·nice·stdbuf·command·exec·time) 벗긴 첫 낱말 yes · cat /dev/zero|/dev/urandom · dd if=/dev/zero (count= 없음)
#   · while true|:|[ 1 ]|(( 1 )) 루프(본문에 sleep 이 있으면 아님 — r448 영역). 백그라운드 = 파이프라인 끝 단독 & (`done &` 포함) 또는 run_in_background.
#   면제 = burner 바로 앞 timeout|gtimeout <N> 이고 N ≤ 600초(s·m·h·d 접미 · 없음 = 초) 하나뿐(바깥 `timeout … bash x.sh` 는 안의 & 고아를 못 끈다).
# ★못 읽음★: 입력 JSON 깨짐·예외 = 통과 + stderr 경고(fail-open). 파일 없음·256KB 초과·바이너리 = 읽기 생략(경고 0). 거절만 — kill·renice·실행 0.
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN bg-cpu-burner-gate: python3 없음 — 통과" >&2; exit 0; }
python3 - <<'PYEOF'
import json, os, re, shlex, sys

MSG = ('시간 상한 없는 백그라운드 CPU 소모기 0(10-20 고아 yes 사건) · 부하 재현이 꼭 필요하면 timeout <≤600s> 로 감싸고 '
       '같은 스크립트에서 wait · 흔들리는 시험 증명은 사건 대기 + mutation(되돌리면 RED)')
LIMIT_S = 600
MAX_FILE = 256 * 1024
WRAP = {"env", "nohup", "nice", "stdbuf", "command", "exec", "time"}
TIMEOUTS = {"timeout", "gtimeout"}
SHELLS = {"bash", "sh", "zsh", "dash"}
LEAD = {"do", "then", "else", "elif", "if", "while", "until", "{", "!"}
ZERO = {"/dev/zero", "/dev/urandom", "/dev/random"}
W = r"(?<![\w./-])%s(?![\w./-])"
LOOP_RE = re.compile(W % r"while\s+(?:true|:|\[\s*1\s*\]|\(\(\s*1\s*\)\))\s*(?:;|\n)\s*do")
DODONE_RE = re.compile(W % "(do|done)")
SLEEP_RE = re.compile(W % "sleep")
AFTER_RE = re.compile(r"[ \t]*(?:(?:\d*[<>]{1,2}&?|&>>?)[ \t]*[^\s;&|()<>]*[ \t]*)*(&&|&)?")


def warn(msg):
    print(f"WARN bg-cpu-burner-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


def blank(arr, a, b):
    for k in range(a, b):
        if arr[k] != "\n":
            arr[k] = " "


def mask(text):
    """(clean, masked) — 길이 같음. clean = 주석·heredoc 본문을 공백으로 · masked = clean 에서 따옴표 덩어리도 x 로."""
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
    """masked 를 따옴표 밖 구분자로 조각 — (시작, 끝, 다음 구분자 종류: pipe|bg|and|seq)."""
    out, s, i, n = [], 0, 0, len(m)
    while i < n:
        two, c, term, step = m[i:i + 2], m[i], None, 1
        if two in ("&&", "||"):
            term, step = "and", 2
        elif two == "|&":
            term, step = "pipe", 2
        elif c == "|":
            term = "pipe"
        elif c == "&" and two != "&>" and not (i and m[i - 1] in "<>"):
            term = "bg"
        elif two == "$(":
            term, step = "seq", 2
        elif c in ";\n()`":
            term = "seq"
        if term:
            out.append((s, i, term)); s = i + step
        i += step
    out.append((s, n, "seq"))
    return out


def dur_s(t):
    m = re.match(r"^(\d+(?:\.\d+)?)([smhd]?)$", t)
    return float(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)] if m else None


def unwrap(toks):
    """감싸개를 벗긴 실행 토큰 · timeout 상한(초 · 없으면 None) · 그 글자."""
    i, limit, raw = 0, None, ""
    while i < len(toks) and toks[i] in LEAD:
        i += 1
    while i < len(toks):
        t = toks[i]; base = t.rsplit("/", 1)[-1]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1; continue
        if base in TIMEOUTS:
            i += 1
            while i < len(toks) and toks[i].startswith("-"):
                i += 2 if toks[i] in ("-s", "-k", "--signal", "--kill-after") else 1
            if i < len(toks) and dur_s(toks[i]) is not None:
                limit, raw = dur_s(toks[i]), toks[i]; i += 1
            continue
        if base in WRAP:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^-?\d+$", toks[i])
                                     or (base == "env" and "=" in toks[i])):
                i += 1
            continue
        break
    return toks[i:], limit, raw


def is_burner(et):
    if not et:
        return False
    base, args = et[0].rsplit("/", 1)[-1], et[1:]
    if base == "yes":
        return True
    if base == "cat":
        return any(a in ZERO for a in args)
    if base == "dd":
        return any(a[3:] in ZERO for a in args if a.startswith("if=")) and not any(a.startswith("count=") for a in args)
    return False


def shell_c(et):
    if et and et[0].rsplit("/", 1)[-1] in SHELLS:
        for j in range(1, len(et) - 1):
            if not et[j].startswith("-"):
                return None
            if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", et[j]):
                return et[j + 1]
    return None


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


def scan(text, bg_all, cwd, src=None, depth=0):
    """첫 거절 (어디, 덧말) · 없으면 None."""
    clean, m = mask(text)
    where = (lambda a, b: f"{src}:{text.count(chr(10), 0, a) + 1}") if src else \
            (lambda a, b: " ".join(clean[a:b].split())[:80])
    for mt in LOOP_RE.finditer(m):
        depth_dd, end = 1, None
        for d in DODONE_RE.finditer(m, mt.end()):
            depth_dd += 1 if d.group(1) == "do" else -1
            if depth_dd == 0:
                end = d; break
        if end is None or SLEEP_RE.search(m, mt.end(), end.start()):
            continue
        if bg_all or AFTER_RE.match(m, end.end()).group(1) == "&":
            return where(mt.start(), end.end()), ""
    pl = []
    for s, e, term in pieces(m):
        if clean[s:e].strip():
            pl.append((s, e))
        if term == "pipe":
            continue
        r = pipeline(clean, pl, bg_all or term == "bg", cwd, src, depth, where)
        pl = []
        if r:
            return r
    return None


def pipeline(clean, pl, bg, cwd, src, depth, where):
    for k, (s, e) in enumerate(pl):
        try:
            toks = shlex.split(clean[s:e], posix=True)
        except ValueError:
            toks = clean[s:e].split()
        et, limit, raw = unwrap(toks)
        if bg and k == len(pl) - 1 and is_burner(et):
            if limit is None:
                return where(s, e), ""
            if limit > LIMIT_S:
                return where(s, e), f" · timeout {raw} = 상한 600s 초과"
        inner = shell_c(et)
        if inner is not None and depth < 3:
            r = scan(inner, bg, cwd, None, depth + 1)
            if r:
                return r
        f = script_of(et, cwd) if src is None and depth == 0 else None   # 1단계만 — 명령 글자가 부른 파일
        if f:
            r = scan(f[1], bg, cwd, f[0], depth + 1)
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
    ti = d.get("tool_input") or {}
    cmd = ti.get("command") or ""
    if not cmd:
        sys.exit(0)
    r = scan(cmd, ti.get("run_in_background") is True, d.get("cwd") or os.getcwd())
    if not r:
        sys.exit(0)
    print(f"REJECT bg-cpu-burner {r[0]}{r[1]} — {MSG}", file=sys.stderr)
    sys.exit(2)


try:
    main()
except Exception as e:  # SystemExit 는 Exception 이 아니라 그대로 지나간다 — 파이썬 쪽 예외 전체 = 통과 + 경고(fail-open)
    warn(f"예외 {type(e).__name__}: {e}")
PYEOF
