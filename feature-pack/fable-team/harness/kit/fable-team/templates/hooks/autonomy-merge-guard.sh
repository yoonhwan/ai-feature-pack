#!/bin/bash
# fable-team autonomy-merge-guard — PreToolUse:Bash (r-autonomy-hooks 훅③ · 판정 1355 · EVAL-night-autonomy-20261013 결함 2)
# 왜: 10-13 밤 planner 가 main 병합·배포를 판별기 없이 손판단(1333·1337) → 판정 1675: 자율 중에도 main 병합 = 오빠 값(push-merge 대리 폐지).
# 동작(ON·BYZ 리포 안만): 오빠 승인 `<상태>/autonomy-merge-approved/<40hex>`(ft-autonomy.sh approve-merge 가 씀)가 있고 그 내용 1줄이 `<상태>/autonomy.log` 에 글자 그대로 있는 sha 만 통과.
#   옛 `autonomy-merge-ok/`(push-merge PROXY 시절 파일)는 읽지 않는다 — 파일은 보존, 승인 근거 아님(DA② H1).
#   · `gh pr merge`/`ft-gh-as-tank.sh pr merge` → `--match-head-commit <sha>` 필수(헤드 결속은 gh 가 강제). `gh api …/pulls/N/merge` 는 `sha=<sha>`.
#   · main 대상 `git push`(main·HEAD:main·x:main·refs/heads/main · `--repo` 포함 · 맨 push+현재 브랜치 main) → 보내는 쪽 ref(없으면 HEAD)의 rev-parse sha. 삭제(:main·--delete/-d)·--all·--mirror·와일드카드는 항상 deny. --dry-run allow.
#   `env -S '<명령>'` 는 `bash -c` 처럼 안쪽을 재검사. OFF·위변조·따옴표/heredoc/mbox 본문 글자만 = allow.
# ★FAIL-OPEN★: 파싱 불가·ft-autonomy.sh 실패 = 허용 + 로그(FT_AUTONOMY_HOOK_LOG). 외부 호출 0. ★설치는 이 파일 범위 밖 — 설치 카드★
set +e
INPUT=$(cat 2>/dev/null); [ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time

LOG = os.environ.get("FT_AUTONOMY_HOOK_LOG") or os.path.expanduser("~/.claude/logs/autonomy-hooks.log")
WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
VALOPTS = {"-u", "-C", "-S", "-P", "-k", "-s", "-n"}  # 값을 하나 더 먹는 래퍼 옵션(env -u NAME · timeout -k N · nice -n N)
SHA = re.compile(r"^[0-9a-f]{40}$")
REASON = ("자율 ON 중 병합·main push 는 오빠가 `! bash /tmp/h<N>`(ft-autonomy.sh approve-merge <sha>)로 승인한 sha 만 — pr merge 는 --match-head-commit <sha> 로, "
          "main push 는 승인된 sha 를 보낼 때만(판정 1675). 승인 전이면 오빠 큐.")

def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" autonomy-merge-guard: {msg}\n")
    except OSError:
        pass

def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root if root and os.path.isdir(os.path.join(root, ".fable-team")) else ""

def mode_of(root):
    cands = [os.environ.get("FT_AUTONOMY_SH") or "", os.path.join(root, ".fable-team/bin/ft-autonomy.sh"), os.path.join(root, "scripts/fable-team-bin/ft-autonomy.sh")]
    sh = next((c for c in cands if c and os.path.isfile(c)), None)
    p = subprocess.run(["bash", sh, "mode"], capture_output=True, text=True, timeout=5, env=dict(os.environ, FT_ROOT=root)) if sh else None
    if p is None or p.returncode != 0:
        note("ft-autonomy.sh mode 를 못 읽음 — 허용(fail-open)")
    return p.stdout.strip() if p is not None and p.returncode == 0 else ""

def strip_heredocs(cmd):
    out, delim = [], None
    for line in cmd.split("\n"):
        if delim is not None:
            delim = None if line.strip() == delim else delim
            continue
        out.append(line)
        m = re.search(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        delim = m.group(2) if m else None
    return "\n".join(out)

def simple_commands(cmd):
    """명령 문자열 → [단어들] — 따옴표 안·heredoc 본문은 글자일 뿐 명령이 아니다. 리다이렉트 토큰은 버린다."""
    lex = shlex.shlex(strip_heredocs(cmd), posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
    segs, words, skip = [], [], False
    for t in lex:
        if skip:
            skip = False
        elif t and set(t) <= set(";&|()\n"):
            segs.append(words); words = []
        elif t and set(t) <= set("<>&|"):
            skip = True
        else:
            words.append(t)
    return segs + [words]

def env_split(prog, a):
    """`env -S/--split-string '<명령>'` 의 문자열 → env 가 실제로 하듯 셸 코드가 아닌 argv(없으면 None). 뒤 남은 인자는 끝에 붙는다."""
    if prog != "env":
        return None
    if a[0] in ("-S", "--split-string") and len(a) > 1:
        s, rest = a[1], a[2:]
    elif a[0].startswith("--split-string="):
        s, rest = a[0][len("--split-string="):], a[1:]
    elif re.match(r"^-S.", a[0]):
        s, rest = a[0][2:], a[1:]
    else:
        return None
    return shlex.split(s) + rest

def resolve(words):
    """환경 대입·래퍼·셸 인터프리터를 벗겨 (프로그램 basename, 인자들) — `bash -c 'x'` 는 ('-c', [x])."""
    w = list(words)
    while w:
        b = os.path.basename(w[0])
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):
            w.pop(0)
        elif b in WRAP:
            w.pop(0)
            while w and (w[0].startswith("-") or re.match(r"^([A-Za-z_][A-Za-z0-9_]*=|[0-9.]+$)", w[0])):
                split = env_split(b, w)
                if split is not None: w = split; break  # 첫 낱말이 실행 프로그램 — 맨 위 루프가 다시 벗긴다(bash -c 일 때만 셸 코드 재검사)
                del w[:2 if w[0] in VALOPTS else 1]
        elif b in SHELLS:
            w.pop(0)
            while w and w[0].startswith("-") and not re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", w[0]):
                w.pop(0)
            if w and w[0].startswith("-"):
                return "-c", w[1:2]
        else:
            return b, w[1:]
    return "", []

def head_arg(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a[len(flag) + 1:]
    return ""

class Guard:
    def __init__(self, state, cwd):
        self.approved, self.logpath, self.cwd = os.path.join(state, "autonomy-merge-approved"), os.path.join(state, "autonomy.log"), cwd

    def ok(self, sha):
        """승인 파일 1줄(`approve-merge <sha> …`)이 autonomy.log 의 한 줄과 글자 그대로 같을 때만 — 파일만 있으면(직접 쓰기) 아니다."""
        if not SHA.match(sha):
            return False
        try:
            with open(os.path.join(self.approved, sha), encoding="utf-8") as f:
                lines = f.read().splitlines()
            with open(self.logpath, encoding="utf-8") as f:
                logged = set(f.read().splitlines())
        except OSError:
            return False
        return len(lines) == 1 and lines[0].startswith("approve-merge %s " % sha) and lines[0] in logged

    def git(self, *a):
        p = subprocess.run(["git", "-C", self.cwd, *a], capture_output=True, text=True, timeout=5)
        return p.stdout.strip() if p.returncode == 0 else ""

    def push_denied(self, args):
        flags = [a for a in args if a.startswith("-")]
        if "--dry-run" in flags or "-n" in flags:
            return False
        pos, skip = [], False
        has_repo = any(a == "--repo" or a.startswith("--repo=") for a in args)  # --repo 가 원격을 정하면 positional 전부가 refspec
        for a in args:
            if skip:
                skip = False
            elif a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
                skip = True
            elif not a.startswith("-"):
                pos.append(a)
        if "--all" in flags or "--mirror" in flags:
            return True
        specs = pos if has_repo else pos[1:]
        if "--delete" in flags or "-d" in flags:  # 삭제 = 보내는 쪽이 빈 refspec(`:main`)과 같다
            specs = [r if ":" in r else ":" + r for r in specs]
        specs = specs or (["HEAD:main"] if self.git("symbolic-ref", "--short", "HEAD") == "main" else [])
        for r in specs:
            r = r.lstrip("+")
            src, dst = r.split(":", 1) if ":" in r else (r, r)
            if "*" not in r and dst.replace("refs/heads/", "", 1) != "main":
                continue
            if "*" in r or not src or not self.ok(self.git("rev-parse", "--verify", "-q", src + "^{commit}")):
                return True
        return False

    def denied(self, cmd, depth=0):
        for words in simple_commands(cmd):
            prog, args = resolve(words)
            if prog == "cd" and args:
                self.cwd = os.path.normpath(os.path.join(self.cwd, args[0]))
            elif prog == "-c" and depth < 3 and args and self.denied(args[0], depth + 1):
                return True
            elif prog in ("gh", "ft-gh-as-tank.sh"):
                if any(args[i:i + 2] == ["pr", "merge"] for i in range(len(args))):
                    if not self.ok(head_arg(args, "--match-head-commit")):
                        return True
                elif "api" in args and any(re.search(r"/pulls/[0-9]+/merge$", a) for a in args):
                    if not self.ok(next((a[4:] for a in args if a.startswith("sha=")), "")):
                        return True
            elif prog == "git":
                a, i = list(args), 0
                while i < len(a) and a[i].startswith("-"):
                    if a[i] == "-C" and i + 1 < len(a):
                        self.cwd = os.path.normpath(os.path.join(self.cwd, a[i + 1]))
                    i += 2 if a[i] in ("-C", "-c") else 1
                if a[i:i + 1] == ["push"] and self.push_denied(a[i + 1:]):
                    return True
        return False

try:
    d = json.loads(os.environ["INPUT"])
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if d.get("tool_name") != "Bash" or not re.search(r"merge|push", cmd):  # 거의 모든 Bash 호출 앞에 서는 훅 — 관련 글자 없으면 즉시 통과
        sys.exit(0)
    cwd = d.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    root = byz_root(cwd)
    if not root or mode_of(root) != "on":
        sys.exit(0)
    state = os.environ.get("FT_AUTONOMY_STATE_DIR") or os.path.join(root, ".fable-team/state")
    hit = Guard(state, cwd).denied(cmd)
except (ValueError, OSError, AttributeError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 허용(fail-open)")
    sys.exit(0)
if hit:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": REASON}}, ensure_ascii=False))
PYEOF
exit 0
