#!/bin/bash
# fable-team gh-issue-author-guard — PreToolUse:Bash
# 왜: 좌석이 gh 기본 로그인으로 Issue·PR 코멘트를 쓰면 작성자가 오빠 계정(yoonhwan)으로 올라간다. 쓰기는 Tank 래퍼로만.
# 차단(exit 2): gh issue (create|comment|edit|close|reopen|label …) · gh pr comment · 쓰기용 gh api …/issues(/N/comments|/labels …)
# 통과: 래퍼(ft-gh-as-tank.sh)·ft-issue-create-pair.sh 경유 · gh issue view/list/status · gh pr create/merge/checkout/diff/view · 모든 조회
# 판정 단위 = 명령 «위치»에 gh 가 오는 구간(; && || | 개행으로 분리 · bash -c/eval 안쪽 재귀) — 따옴표 안 문자열·heredoc 본문은 명령이 아니다.
# ★설치(~/.claude/settings.json 등록)는 이 파일 범위 밖 — 오빠 승인 후 ops 가 한다★
# ★FAIL-OPEN(sibling 훅 관례): stdin JSON 파싱 불가 = 판단 불가 → 허용(stderr 로 알림). 막는 것은 «읽은 명령이 gh 쓰기일 때»뿐.★
set +e
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

python3 - "$INPUT" <<'PYEOF'
import json, os, re, shlex, sys

def allow(): sys.exit(0)

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.stderr.write("[gh-issue-author-guard] stdin JSON 파싱 불가 — 허용(fail-open)\n"); allow()
if data.get("tool_name") != "Bash":
    allow()
cmd = (data.get("tool_input") or {}).get("command") or ""
if not isinstance(cmd, str) or "gh" not in cmd:
    allow()

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

def api_is_issue_write(args):
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
    if not path or not re.search(r"(^|/)issues(/|\?|$)", path):
        return False
    if method == "GET": return False
    return method in WRITE_METHODS or (method is None and has_body)

def violation(seg):
    """gh 쓰기 호출이면 사유 문자열, 아니면 None."""
    s = command_start(seg)
    if s >= len(seg): return None
    head = os.path.basename(seg[s])
    if head in SHELLS or head == "eval":                      # bash -c "…" / eval … 안쪽 재귀
        inner = " ".join(seg[s + 1:]) if head == "eval" else (seg[seg.index("-c") + 1] if "-c" in seg[s + 1:-1] else "")
        for sub in segments(inner):
            v = violation(sub)
            if v: return v
        return None
    if head != "gh": return None
    rest = seg[s + 1:]
    pos = skip_opts(rest)
    if not pos: return None
    if pos[0] == "issue" and len(pos) > 1 and pos[1] not in ISSUE_READ:
        return "gh issue " + pos[1]
    if pos[0] == "pr" and len(pos) > 1 and pos[1] == "comment":
        return "gh pr comment"
    if pos[0] == "api" and api_is_issue_write(rest[rest.index("api") + 1:] if "api" in rest else []):
        return "gh api …/issues 쓰기"
    return None

try:
    for seg in segments(cmd):
        v = violation(seg)
        if v:
            sys.stderr.write(
                "🚫 [gh-issue-author-guard] %s 직접 호출 금지 — 오빠 계정(yoonhwan) 이름으로 올라간다. "
                "Tank 래퍼를 써라: bash scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|label|close|reopen|pr-comment> … --apply "
                "(Issue 생성 쌍 = ft-issue-create-pair.sh). 조회(view·list)는 gh 그대로.\n" % v)
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
