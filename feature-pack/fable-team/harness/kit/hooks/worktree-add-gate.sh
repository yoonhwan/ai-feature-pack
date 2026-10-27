#!/bin/bash
# worktree-add-gate — PreToolUse:Bash (r835 · master 154176 · planner 154162 · r3 = 외부 DA r1·r2 HOLD 뒤 재설계)
# 왜: 팀 좌석이 맨손 `git worktree add` 로 착지·카드 워크트리를 만들면 풀 체크아웃(1.43GiB · 나노 sparse 0.24GiB) — 45분 4곳 = 6Gi.
# ★이 훅은 «안내» 만 한다 — deny 0★. 명령 글자로는 대상 리포를 끝까지 못 가린다(DA r1·r2 반례). ★보장 = kit/fable-team/githooks/post-checkout★
#   (워크트리 표식 파일 ft-wt-mode 가 없는 팀 워크트리는 처음 보는 checkout 에 sparse).
# 안내 조건: 명령 단어(줄·연산자 뒤 첫 단어 · X=y·env·command·nohup·time·exec 다음)가 git 이고, 전역 옵션(-C·-c·--git-dir·--work-tree 등)
#   뒤 첫 하위 명령이 worktree, 그다음이 add ∧ 대상 리포의 주 워크트리에 design/teams/ → stdout additionalContext 1개 + stderr 1줄 · rc 0.
#   대상 = --git-dir(최종 -C 기준) → -C(누적) → 그 앞 `cd|pushd`(괄호 서브셸 밖으로 안 샘) → 입력 cwd. `bash|sh|zsh -c` · `eval` 문자열도 같은 규칙.
# 조용히 통과(출력 0): 판별 못 함(미전개 변수 · git 밖) · 팩 리포(design/teams/ 없음) · 도구 호출 · 인자 속 글자 · worktree list/remove/prune.
# ★못 읽음★: 입력 JSON 깨짐·command 없음·python3 없음 = 통과 + stderr 1줄(fail-open · 기존 kit/hooks 훅과 같은 규칙).
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse Bash 등록)는 master — 이 파일 범위 밖★
set +e
INPUT=$(cat 2>/dev/null)
export INPUT
command -v python3 >/dev/null 2>&1 || { echo "WARN worktree-add-gate: python3 없음 — 통과" >&2; exit 0; }
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys

MSG = ("팀 워크트리는 ft-wt-add.sh <이름> --team <팀> -b <가지> 로 (sparse · r835) · 맨손 worktree add 는 post-checkout 이"
       " 남의 팀 폴더 0 으로 줄인다 · 풀이 꼭 필요하면 ft-wt-add.sh <이름> --full <사유 10자 이상> -b <가지>")
OPS = {"&&", "||", ";", "|", "&", ";;", "(", ")", "|&"}
LEAD = {"do", "then", "else", "elif", "if", "while", "until", "{", "!"}
WRAP = {"env", "command", "nohup", "time", "exec"}
SHELLS = {"bash", "sh", "zsh", "dash"}
ARG_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def warn(msg):
    print(f"WARN worktree-add-gate: {msg} — 통과", file=sys.stderr)
    sys.exit(0)


def strip_heredoc(text):
    """heredoc 본문 줄을 뺀다(본문 글자는 명령이 아니다) · <<< 는 아님."""
    out, delim = [], None
    for line in text.split("\n"):
        if delim is not None:
            if line.strip() == delim:
                delim = None
            continue
        out.append(line)
        m = re.search(r"(?<!<)<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        if m:
            delim = m.group(2)
    return "\n".join(out)


def toks(text):
    lx = shlex.shlex(strip_heredoc(text), posix=True, punctuation_chars="();<>|&\n")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    return list(lx)


def is_op(t):
    return t in OPS or (bool(t) and set(t) <= set(";&|()\n"))


def unresolved(p):
    return "$" in p or "`" in p


def join(base, p):
    return os.path.normpath(os.path.join(base, os.path.expanduser(p)))


def git_target(ts, j, cur, skip):
    """ts[j] = git 다음 · skip = 앞 cd 가 미전개. → (하위 명령 위치, ('dir'|'gitdir'|'skip', 값))"""
    d, gd = cur, None
    while j < len(ts) and ts[j].startswith("-") and not is_op(ts[j]):
        o, val = ts[j], None
        if "=" in o and o.split("=", 1)[0] in ARG_OPTS:
            o, val = o.split("=", 1)
        elif o in ARG_OPTS and j + 1 < len(ts):
            val = ts[j + 1]; j += 1
        if o == "-C" and val is not None:
            if unresolved(val):
                skip = True
            else:
                d, skip = join(d, val), skip and not os.path.isabs(os.path.expanduser(val))
        elif o == "--git-dir" and val is not None:
            gd = val
        j += 1
    if gd is not None:   # git 은 --git-dir 상대값을 «모든 -C 뒤» 폴더 기준으로 푼다(옵션 순서 무관)
        if unresolved(gd) or (skip and not os.path.isabs(os.path.expanduser(gd))):
            return j, ("skip", None)
        return j, ("gitdir", join(d, gd))
    return j, ("skip", None) if skip else ("dir", d)


def scan(text, cwd, depth=0):
    """명령 글자 → `git … worktree add` 마다 (종류, 값) 목록."""
    try:
        ts = toks(text)
    except ValueError:
        warn("명령 조각내기 실패")
    hits, cur, cur_skip, i, start, stack = [], cwd, False, 0, True, []
    while i < len(ts):
        t = ts[i]
        if is_op(t):
            for ch in t:   # ( … ) 서브셸 안의 cd 는 밖으로 안 샌다
                if ch == "(":
                    stack.append((cur, cur_skip))
                elif ch == ")" and stack:
                    cur, cur_skip = stack.pop()
            start = True; i += 1; continue
        if not start:
            i += 1; continue
        if t in LEAD or t in WRAP or ASSIGN.match(t):
            i += 1; continue
        start, base = False, os.path.basename(t)
        if t in ("cd", "pushd") and i + 1 < len(ts) and not is_op(ts[i + 1]):
            nxt = ts[i + 1]
            if unresolved(nxt):
                cur_skip = True
            else:
                cur = join(cur, nxt)
            i += 2; continue
        if depth < 3 and base in SHELLS:
            j = i + 1
            while j < len(ts) and ts[j].startswith("-") and (ts[j].startswith("--") or "c" not in ts[j]):
                j += 1
            if j + 1 < len(ts) and ts[j].startswith("-") and "c" in ts[j]:
                hits += scan(ts[j + 1], cur, depth + 1)
        elif depth < 3 and t == "eval":
            j = i + 1
            while j < len(ts) and not is_op(ts[j]):
                j += 1
            hits += scan(" ".join(ts[i + 1:j]), cur, depth + 1)
        elif base == "git":
            j, hit = git_target(ts, i + 1, cur, cur_skip)
            if j + 1 < len(ts) and ts[j] == "worktree" and ts[j + 1] == "add":
                hits.append(hit)
        i += 1
    return hits


def byz_root(kind, val):
    """대상 리포의 주 워크트리에 design/teams/ 가 있으면 그 루트, 아니면 None."""
    if kind == "gitdir":
        args = ["git", f"--git-dir={val}", "rev-parse", "--path-format=absolute", "--git-common-dir"]
    else:
        while val and not os.path.isdir(val):
            val = os.path.dirname(val)
        if not val:
            return None
        args = ["git", "-C", val, "rev-parse", "--path-format=absolute", "--git-common-dir"]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=5)
    except Exception:
        return None
    if r.returncode != 0 or not r.stdout.strip():
        return None
    root = os.path.dirname(r.stdout.strip().rstrip("/"))
    return root if os.path.isdir(os.path.join(root, "design", "teams")) else None


raw = os.environ.get("INPUT", "")
if not raw.strip():
    warn("입력 없음")
try:
    data = json.loads(raw)
except Exception:
    warn("입력 JSON 깨짐")
if data.get("tool_name", "Bash") != "Bash":
    sys.exit(0)
cmd = (data.get("tool_input") or {}).get("command")
if not isinstance(cmd, str) or not cmd.strip():
    warn("command 없음")
cwd = data.get("cwd") or os.getcwd()
if "worktree" not in cmd:
    sys.exit(0)
for kind, val in scan(cmd, cwd):
    root = None if kind == "skip" else byz_root(kind, val)
    if root:
        note = f"[worktree-add-gate] {MSG} (리포 {root})"
        print(note, file=sys.stderr)
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": note}}, ensure_ascii=False))
        sys.exit(0)
sys.exit(0)
PYEOF
exit 0
