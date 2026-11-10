#!/bin/bash
# fable-team slack-post-guard — PreToolUse:Bash
# 왜: 나노·좌석이 `hermes send` 로 슬랙에 직접 올리면 한 단위가 뿌리 글 여러 개로 쪼개진다(감사: 제안서 5건 중 4건 손 발행).
#     슬랙 발행은 byz_thread_post.py start|progress|result 하나뿐이다(오빠 판정 405 — 채널 #byz-planner · 공식 도구만).
# 판정 단위 = 명령 «위치»에 hermes 가 오는 구간(; && || | 개행으로 분리 · bash -c/eval 안쪽 재귀 — gh-issue-author-guard 와 같은 꼴).
#   따옴표 안 문자열·heredoc 본문·mbox/commit/grep 의 인자는 명령이 아니다(오탐 실측 8건 중 4건: mbox send 본문 · git commit -m · grep 패턴).
# 차단(exit 2): 그 구간이 `hermes … send …` 이고 `-t`/`--to` 값에 slack 이 있을 때. 값이 변수($)·치환이면 «판정 불가 = deny».
#   따옴표 분리('sl''ack')는 shlex 가 한 단어로 합친다. `--list` 가 있으면 통과.
# 통과: 다른 플랫폼(telegram 등) · --list · 대상 인자 없음 · hermes 가 명령 위치에 없는 모든 명령.
# deny 마다 state/hook-falsepos.log 에 원문 1줄 기록(오탐 검토용) — 기록 실패는 deny 를 바꾸지 않는다.
# ★설치(~/.claude/settings.json 등록·훅 홈 복사)는 이 파일 범위 밖 — master 몫★
# ★FAIL-OPEN(sibling 훅 관례): stdin JSON·명령 파싱 불가 = 판단 불가 → 허용(stderr 로 알림).★
set +e
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

python3 - "$INPUT" <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time

def allow(): sys.exit(0)

try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.stderr.write("[slack-post-guard] stdin JSON 파싱 불가 — 허용(fail-open)\n"); allow()
if data.get("tool_name") != "Bash":
    allow()
cmd = (data.get("tool_input") or {}).get("command") or ""
if not isinstance(cmd, str) or "hermes" not in re.sub(r"['\"\\]", "", cmd).lower():   # 따옴표로 쪼갠 her""mes 도 후보로 남긴다
    allow()
cwd = data.get("cwd") if isinstance(data.get("cwd"), str) else ""

SEP = {";", "&&", "||", "|", "&", "(", ")", "|&"}
WRAP = {"command", "sudo", "env", "time", "exec", "nohup", "builtin"}
SHELLS = {"bash", "sh", "zsh"}
XARGS_VALUE_OPTS = {"-I", "-n", "-L", "-P", "-s", "-d", "-E", "-a"}
TARGET_LONG = ("--to", "--target")

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
    lex.commenters = ""                                       # 단어 안 `#`(slack:#채널)을 주석으로 자르지 않는다
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
    while i < len(seg):
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]) or os.path.basename(seg[i]) in WRAP:
            i += 1
        elif os.path.basename(seg[i]) == "xargs":             # xargs [옵션] 명령 — 옵션(값 받는 것 포함)을 건너뛴 자리가 명령 위치
            i += 1
            while i < len(seg) and seg[i].startswith("-"):
                i += 2 if seg[i] in XARGS_VALUE_OPTS else 1
        else:
            break
    return i

def targets(args):
    """-t/--to 의 값 목록(`-tslack`·`--to=slack:C1` 형 포함)."""
    vals, i = [], 0
    while i < len(args):
        t = args[i]
        if t in ("-t",) + TARGET_LONG and i + 1 < len(args): vals.append(args[i + 1]); i += 2; continue
        for k in TARGET_LONG:
            if t.startswith(k + "="): vals.append(t.split("=", 1)[1])
        if re.match(r"^-t.+", t) and not t.startswith("--"): vals.append(t[2:])
        i += 1
    return vals

def violation(seg):
    s = command_start(seg)
    if s >= len(seg): return False
    head = os.path.basename(seg[s])
    if head in SHELLS or head == "eval":                      # bash -c "…" / eval … 안쪽 재귀
        inner = " ".join(seg[s + 1:]) if head == "eval" else (seg[seg.index("-c") + 1] if "-c" in seg[s + 1:-1] else "")
        return any(violation(sub) for sub in segments(inner)) if inner else False
    if head != "hermes": return False
    args = seg[s + 1:]
    if "send" not in args or "--list" in args: return False
    for v in targets(args):
        if "slack" in v.lower() or "$" in v or "`" in v:      # 변수·치환 = 판정 불가 → deny
            return True
    return False

def log_deny():
    """state/hook-falsepos.log 에 원문 1줄. 실패해도 deny 는 그대로."""
    try:
        path = os.environ.get("FT_HOOK_FALSEPOS_LOG")
        if not path:
            top = subprocess.run(["git", "-C", cwd or ".", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                 capture_output=True, text=True, timeout=2).stdout.strip()
            path = os.path.join(re.sub(r"/\.git/?$", "", top), ".fable-team/state/hook-falsepos.log")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write("%s\tslack-post-guard\t%s\t%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S%z"), cwd, cmd.replace("\n", "⏎")[:500]))
    except Exception as e:
        sys.stderr.write("[slack-post-guard] 오탐 기록 실패(%s) — deny 는 유지\n" % type(e).__name__)

try:
    if any(violation(seg) for seg in segments(cmd)):
        log_deny()
        sys.stderr.write("🚫 [slack-post-guard] 슬랙 발행은 byz_thread_post.py start|progress|result 로 — 판정 405 "
                         "(손 `hermes send` 슬랙 발행 금지 · 채널 #byz-planner 하나 · 공식 도구만)\n")
        sys.exit(2)
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write("[slack-post-guard] 명령 파싱 실패(%s) — 허용(fail-open)\n" % e)
allow()
PYEOF
RC=$?
[ "$RC" = "2" ] && exit 2
exit 0
