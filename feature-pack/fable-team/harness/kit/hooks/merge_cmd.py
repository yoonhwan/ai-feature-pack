"""merge_cmd.py — 병합·push 명령 파싱 공용 모듈 (R230 · «sha 추출 함수 공유 — 모듈 1개»).
autonomy-merge-guard.sh 의 simple_commands·resolve·head_arg 와 같은 규칙: 따옴표 안·heredoc 본문은 글자일 뿐 명령이 아니고,
env/sudo/timeout 같은 래퍼와 `bash -c` 를 벗겨 실제 프로그램을 본다. 여기에 main 향 push 의 refspec 해석(main_pushes)을 더했다."""
import os
import re
import shlex

WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
VALOPTS = {"-u", "-C", "-S", "-P", "-k", "-s", "-n"}
FORCE_FLAGS = {"--force", "-f", "--force-if-includes"}


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
                if split is not None:
                    w = split; break
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


def main_pushes(args, current_branch):
    """git push 인자 → (main 향 refspec 목록 [(src, dst, forced)], 위험 사유 또는 ""). --dry-run 은 ([], "")."""
    flags = [a for a in args if a.startswith("-")]
    if "--dry-run" in flags or "-n" in flags:
        return [], ""
    pos, skip = [], False
    has_repo = any(a == "--repo" or a.startswith("--repo=") for a in args)
    for a in args:
        if skip:
            skip = False
        elif a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
            skip = True
        elif not a.startswith("-"):
            pos.append(a)
    if "--all" in flags or "--mirror" in flags:
        return [], "--all/--mirror push"
    specs = pos if has_repo else pos[1:]
    if "--delete" in flags or "-d" in flags:
        specs = [r if ":" in r else ":" + r for r in specs]
    specs = specs or (["HEAD:main"] if current_branch == "main" else [])
    forced_flag = any(f in FORCE_FLAGS or f.startswith("--force-with-lease") for f in flags)
    out = []
    for r in specs:
        plus = r.startswith("+")
        r = r.lstrip("+")
        src, dst = r.split(":", 1) if ":" in r else (r, r)
        if "*" in r:
            return [], "와일드카드 refspec"
        if dst.replace("refs/heads/", "", 1) == "main":
            out.append((src, dst, plus or forced_flag))
    return out, ""
