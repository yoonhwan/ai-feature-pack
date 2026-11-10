#!/bin/bash
# fable-team gh-issue-author-guard — PreToolUse:Bash
# 왜: 좌석이 gh 기본 로그인으로 Issue·PR 코멘트를 쓰면 작성자가 오빠 계정(yoonhwan)으로 올라간다. 쓰기는 Tank 래퍼로만.
# 차단(exit 2): gh issue (create|comment|edit|close|reopen|label …) · gh pr comment · gh pr review(판정·코멘트 플래그) · gh pr close -c · gh pr edit(--body/--title)
#   · 쓰기용 gh api …/issues(/N/comments|/labels …) · gh api …/pulls/N(PATCH) · …/pulls/N/(comments|reviews)(POST·PATCH) · gh api graphql mutation
# 통과: 래퍼(ft-gh-as-tank.sh)·ft-issue-create-pair.sh 경유 · gh issue view/list/status · gh pr create/merge/checkout/diff/view · 코멘트 없는 gh pr close · label 만 바꾸는 gh pr edit · graphql query · 모든 조회
# 판정 단위 = 명령 «위치»에 gh 가 오는 구간(; && || | 개행으로 분리 · bash -c/eval 안쪽 재귀) — 따옴표 안 문자열·heredoc 본문은 명령이 아니다.
# 차단 범위 = SecondWindStudio 리포 · 판정 불가 = 통과 · main 만 보호
#   리포 범위: 위 차단은 대상 리포 owner 가 GUARDED_OWNERS 일 때만. owner 결정 순서 = -R/--repo → 구간 앞 GH_REPO= → gh api 경로 repos/<owner>/ →
#   git push 원격 인자(URL 또는 `git remote get-url`) → 훅 입력 cwd 의 origin. 결정 불가 = 통과 + stderr 1줄.
#   main 보호(같은 범위): git push 의 main 삭제(:main · --delete)·강제(+main · -f)·--mirror/--prune · gh api DELETE/PATCH main · gh repo delete.
#   main 이 아닌 브랜치의 삭제·강제는 막지 않는다(오빠 10-07). 전역 force push·branch -D 는 block-destructive.sh 몫.
# ★설치(~/.claude/settings.json 등록)는 이 파일 범위 밖 — 오빠 승인 후 ops 가 한다★
# ★FAIL-OPEN(sibling 훅 관례): stdin JSON 파싱 불가 = 판단 불가 → 허용(stderr 로 알림). 막는 것은 «읽은 명령이 gh 쓰기일 때»뿐.★
set +e
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

python3 - "$INPUT" <<'PYEOF'
import json, os, re, shlex, subprocess, sys

def allow(): sys.exit(0)

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.stderr.write("[gh-issue-author-guard] stdin JSON 파싱 불가 — 허용(fail-open)\n"); allow()
if data.get("tool_name") != "Bash":
    allow()
cmd = (data.get("tool_input") or {}).get("command") or ""
if not isinstance(cmd, str) or ("gh" not in cmd and "git" not in cmd):
    allow()
cwd = data.get("cwd") if isinstance(data.get("cwd"), str) else ""

GUARDED_OWNERS = {"secondwindstudio"}
GIT_TIMEOUT = 2
MAIN_REFS = {"main", "refs/heads/main"}
FORCE_FLAGS = {"-f", "--force", "--force-with-lease", "--force-if-includes"}
GIT_VALUE_OPTS = {"-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
PUSH_VALUE_OPTS = {"-o", "--push-option", "--receive-pack", "--exec"}
ISSUE_READ = {"view", "list", "status"}
SEP = {";", "&&", "||", "|", "&", "(", ")", "|&"}
WRAP = {"command", "sudo", "env", "time", "exec", "nohup", "builtin"}
SHELLS = {"bash", "sh", "zsh"}
WRITE_METHODS = {"POST", "PATCH", "PUT", "DELETE"}

def strip_heredocs(text):
    out, end = [], None
    for line in text.split("\n"):
        if end is not None:
            if line.strip() == end: end = None
            continue
        out.append(line)
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
        if m: end = m.group(1)
    return "\n".join(out)

def newlines_to_semicolons(text):
    out, q, esc = [], None, False
    for ch in text:
        if esc: esc = False
        elif ch == "\\" and q != "'": esc = True
        elif q: q = None if ch == q else q
        elif ch in "'\"": q = ch
        elif ch == "\n": ch = ";"
        out.append(ch)
    return "".join(out)

def segments(text):
    lex = shlex.shlex(newlines_to_semicolons(strip_heredocs(text)), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    seg = []
    for tok in lex:
        if tok in SEP or set(tok) <= set(";&|()"):
            if seg: yield seg
            seg = []
        else:
            seg.append(tok)
    if seg: yield seg

def command_start(seg):
    i = 0
    while i < len(seg) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]) or os.path.basename(seg[i]) in WRAP):
        i += 1
    return i

def skip_opts(toks):
    """옵션과 그 값(-R repo 등)을 건너뛴 위치 인자 목록."""
    pos, i = [], 0
    while i < len(toks):
        t = toks[i]
        if t in ("-R", "--repo", "-H", "--hostname"): i += 2; continue
        if t.startswith("-"): i += 1; continue
        pos.append(t); i += 1
    return pos

def api_parts(args):
    """gh api 인자 → (메서드 대문자 또는 None, 본문 인자 유무, 경로)."""
    method, has_body, path = None, False, None
    i = 0
    while i < len(args):
        t = args[i]
        if t in ("-X", "--method") and i + 1 < len(args): method = args[i + 1].upper(); i += 2; continue
        if t.startswith("--method="): method = t.split("=", 1)[1].upper()
        elif t in ("-f", "-F", "--field", "--raw-field", "--input"): has_body = True; i += 2; continue
        elif t.startswith("-"): pass
        elif path is None: path = t
        i += 1
    return method, has_body, path

def api_is_issue_write(method, has_body, path):
    if not path or not re.search(r"(^|/)issues(/|\?|$)", path):
        return False
    if method == "GET": return False
    return method in WRITE_METHODS or (method is None and has_body)

def api_is_pr_write(method, has_body, path):
    if not path: return False
    p = path.split("?", 1)[0].rstrip("/")
    if re.search(r"(^|/)pulls/\d+$", p): return method == "PATCH"
    if re.search(r"(^|/)pulls/\d+/(comments|reviews)(/|$)", p):
        return method in ("POST", "PATCH") or (method is None and has_body)
    return False

def api_is_graphql_mutation(args):
    if not args or "graphql" not in args: return False
    for i, t in enumerate(args[:-1]):
        if t in ("-f", "-F", "--field", "--raw-field") and args[i + 1].startswith("query="):
            if re.sub(r"\s+", "", args[i + 1][len("query="):]).startswith("mutation"): return True
    return False

PR_REVIEW_FLAGS = ({"--approve", "--request-changes", "--comment", "--body", "--body-file"}, {"-a", "-r", "-c", "-b", "-F"})
PR_CLOSE_FLAGS = ({"--comment"}, {"-c"})
PR_EDIT_FLAGS = ({"--body", "--body-file", "--title"}, {"-b", "-F", "-t"})

def has_flag(toks, flags):
    longs, shorts = flags
    return any(t.split("=", 1)[0] in longs or (t[:2] in shorts and not t.startswith("--")) for t in toks if t.startswith("-"))

def pr_write_reason(verb, rest):
    if verb == "comment": return "gh pr comment"
    flags = {"review": PR_REVIEW_FLAGS, "close": PR_CLOSE_FLAGS, "edit": PR_EDIT_FLAGS}.get(verb)
    return "gh pr " + verb if flags and has_flag(rest, flags) else None

def api_is_main_rewrite(method, path):
    if method not in ("DELETE", "PATCH") or not path: return False
    p = path.split("?", 1)[0].rstrip("/")
    return p.endswith("git/refs/heads/main") or re.search(r"branches/main(/|$)", p) is not None

# ── 대상 리포 owner 결정 ──
def owner_of(spec):
    """OWNER/REPO · HOST/OWNER/REPO · URL(https/ssh/scp 형) → 소문자 owner. 못 정하면 None."""
    spec = (spec or "").strip()
    m = re.fullmatch(r"([^/:\s]+)/[^/:\s]+", spec) or re.search(r"[:/]([^/:\s]+)/[^/:\s]+?(?:\.git)?/?$", spec)
    if not m or m.group(1).startswith("{"): return None
    return m.group(1).lower()

def repo_arg(toks):
    for i, t in enumerate(toks):
        if t in ("-R", "--repo") and i + 1 < len(toks): return toks[i + 1]
        if t.startswith("--repo="): return t.split("=", 1)[1]
        if t.startswith("-R") and not t.startswith("--") and len(t) > 2: return t[2:]
    return None

def env_repo(prefix):
    for t in prefix:
        if t.startswith("GH_REPO="): return t.split("=", 1)[1]
    return None

def api_path_owner(path):
    m = re.match(r"^/?repos/([^/]+)/", path or "")
    return None if not m or m.group(1).startswith("{") else m.group(1).lower()

def git_remote_url(base, name):
    if not base: return None
    try:
        r = subprocess.run(["git", "-C", base, "remote", "get-url", name], capture_output=True, text=True, timeout=GIT_TIMEOUT)
    except Exception:
        return None
    return r.stdout.strip() if r.returncode == 0 else None

def cwd_owner(base):
    return owner_of(git_remote_url(base, "origin"))

def remote_owner(base, remote):
    if remote is None: return cwd_owner(base)
    if "://" in remote or re.match(r"^[^/\s]+@[^/\s]+:", remote): return owner_of(remote)
    return owner_of(git_remote_url(base, remote))

def scoped(kind, reason, owner):
    """대상 리포가 GUARDED_OWNERS 일 때만 위반. 판정 불가 = 통과 + stderr 1줄."""
    if owner is None:
        sys.stderr.write("[gh-issue-author-guard] 대상 리포 판정 불가(%s) — 허용(fail-open)\n" % reason)
        return None
    return (kind, reason) if owner in GUARDED_OWNERS else None

# ── git push ──
def parse_push(seg, s, cwd):
    """git [옵션] push … → (플래그 집합, 원격 인자, refspec 목록, 기준 디렉터리). push 가 아니면 None."""
    base, i = cwd, s + 1
    while i < len(seg) and seg[i] != "push":
        t = seg[i]
        if t == "-C" and i + 1 < len(seg): base = os.path.normpath(os.path.join(base or ".", seg[i + 1])); i += 2; continue
        if t in GIT_VALUE_OPTS: i += 2; continue
        if not t.startswith("-"): return None
        i += 1
    if i >= len(seg): return None
    flags, pos, repo, j = set(), [], None, i + 1
    while j < len(seg):
        t = seg[j]
        if t == "--repo" and j + 1 < len(seg): repo = seg[j + 1]; j += 2; continue
        if t in PUSH_VALUE_OPTS: j += 2; continue
        if t.startswith("--repo="): repo = t.split("=", 1)[1]
        elif t.startswith("--"): flags.add(t.split("=", 1)[0])
        elif t.startswith("-") and len(t) > 1: flags.update("-" + c for c in t[1:])
        else: pos.append(t)
        j += 1
    return flags, repo or (pos[0] if pos else None), pos if repo else pos[1:], base

def push_main_reason(flags, refspecs):
    if flags & {"--mirror", "--prune"}: return "git push --mirror/--prune"
    mains = [r for r in refspecs if r.lstrip("+").split(":", 1)[-1] in MAIN_REFS]
    if not mains: return None
    if flags & {"--delete", "-d"} or flags & FORCE_FLAGS or any(r.startswith((":", "+")) for r in mains):
        return "git push main 삭제·강제"
    return None

def violation(seg, cwd):
    """(종류, 사유) — 종류 author=Issue 작성자 · main=main 삭제·재작성. 아니면 None."""
    s = command_start(seg)
    if s >= len(seg): return None
    head = os.path.basename(seg[s])
    if head in SHELLS or head == "eval":                      # bash -c "…" / eval … 안쪽 재귀
        inner = " ".join(seg[s + 1:]) if head == "eval" else (seg[seg.index("-c") + 1] if "-c" in seg[s + 1:-1] else "")
        for sub in segments(inner):
            v = violation(sub, cwd)
            if v: return v
        return None
    if head == "git":
        p = parse_push(seg, s, cwd)
        reason = push_main_reason(p[0], p[2]) if p else None
        return scoped("main", reason, remote_owner(p[3], p[1])) if reason else None
    if head != "gh": return None
    rest = seg[s + 1:]
    pos = skip_opts(rest)
    if not pos: return None
    owners = [owner_of(repo_arg(rest)), owner_of(env_repo(seg[:s]))]
    kind = reason = None
    if pos[0] == "issue" and len(pos) > 1 and pos[1] not in ISSUE_READ:
        kind, reason = "author", "gh issue " + pos[1]
    elif pos[0] == "pr" and len(pos) > 1:
        reason = pr_write_reason(pos[1], rest)
        if reason: kind = "author"
    elif pos[0] == "api":
        api_args = rest[rest.index("api") + 1:] if "api" in rest else []
        method, has_body, path = api_parts(api_args)
        if api_is_issue_write(method, has_body, path): kind, reason = "author", "gh api …/issues 쓰기"
        elif api_is_pr_write(method, has_body, path): kind, reason = "author", "gh api …/pulls 쓰기"
        elif api_is_graphql_mutation(api_args): kind, reason = "author", "gh api graphql mutation"
        elif api_is_main_rewrite(method, path): kind, reason = "main", "gh api main 브랜치 삭제·변경"
        owners.append(api_path_owner(path))
    elif pos[0] == "repo" and len(pos) > 1 and pos[1] == "delete":
        kind, reason = "main", "gh repo delete"
        owners.append(owner_of(pos[2]) if len(pos) > 2 else None)
    if not reason: return None
    return scoped(kind, reason, next((o for o in owners if o), None) or cwd_owner(cwd))

try:
    for seg in segments(cmd):
        v = violation(seg, cwd)
        if v and v[0] == "main":
            sys.stderr.write("🚫 [gh-issue-author-guard] %s 차단 — main 삭제·재작성(강제 push·리베이스 후 강제)은 금지 — 오빠 10-07\n" % v[1])
            sys.exit(2)
        if v:
            sys.stderr.write(
                "🚫 [gh-issue-author-guard] %s 직접 호출 금지 — 오빠 계정(yoonhwan) 이름으로 올라간다. "
                "Tank 래퍼를 써라: bash .fable-team/bin/ft-gh-as-tank.sh <create|comment|label|close|reopen|pr-comment|pr-edit|pr-close> … --apply "
                "(Issue 생성 쌍 = ft-issue-create-pair.sh). 조회(view·list)는 gh 그대로. "
                "PR 리뷰 판정(approve·request-changes)은 사람만 — 래퍼 대체 없음, 코멘트는 pr-comment.\n" % v[1])
            sys.exit(2)
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write("[gh-issue-author-guard] 명령 파싱 실패(%s) — 허용(fail-open)\n" % e)
allow()
PYEOF
RC=$?
[ "$RC" = "2" ] && exit 2
exit 0
