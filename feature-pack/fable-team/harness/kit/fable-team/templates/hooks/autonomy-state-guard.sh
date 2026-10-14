#!/bin/bash
# fable-team autonomy-state-guard — PreToolUse:Bash|Write|Edit|NotebookEdit (r-autonomy-hooks 훅② · 판정 1322·1355 · DESIGN-autonomy-proxy-decision r3 §1)
# 왜: 좌석이 자율 모드를 스스로 켜고 끄거나 상태 파일을 고치면 모드 전체가 무의미하다. ON/OFF 는 오빠 `!` 한 줄(ft-hil.sh 계획 파일)로만.
# 막는 것(모드 ON/OFF 무관 · BYZ 리포 안): `autonomy.json`·`autonomy.log`(+`.tmp`)·`autonomy-merge-ok/`·`autonomy-merge-approved/`·`autonomy-digest/`·`seat-resume-attempts/` 경로를 «쓰는» 호출,
#   `ft-autonomy.sh on|off|approve-merge`·`ft-queue-digest.sh issue`·`ft-resume-attempt.sh allow` 실행(판정 1675 · 뒤 두 도구는 r163·r165 가 만든다).
#   Write/Edit/NotebookEdit 는 file_path·notebook_path. Bash 는 «양성 일치»만: 리다이렉트 `>`/`>>`/`>|` 대상 · tee · cp(마지막 인자=대상) · mv/rm/ln/install/touch/truncate 인자 · dd of= · sed/perl -i.
#   읽기 목록 밖을 전부 막는 방향은 오탐 폭발(r106c 실측)이라 금지 — cat·jq·grep·tail·ft-autonomy.sh status|mode|event·따옴표 안 글자·heredoc 본문은 allow.
# 한계(설계 §1): bypass 좌석의 적대적 우회(python -c 로 쓰기 등)까지는 못 막는다 — 그건 ft-autonomy.sh 의 위변조 표시가 잡는다.
# ★FAIL-OPEN★: 파싱 불가 = 허용 + 로그(FT_AUTONOMY_HOOK_LOG · 기본 ~/.claude/logs/autonomy-hooks.log). 외부 호출 0 — 로컬 git rev-parse 뿐.
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse 등록)는 이 파일 범위 밖 — 설치 카드★
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time

LOG = os.environ.get("FT_AUTONOMY_HOOK_LOG") or os.path.expanduser("~/.claude/logs/autonomy-hooks.log")
PROT = re.compile(r"(^|/)(autonomy\.(json|log)(\.tmp)?|(autonomy-merge-ok|autonomy-merge-approved|autonomy-digest|seat-resume-attempts)(/|$))")
DENY_EXEC = {"ft-autonomy.sh": ("on", "off", "approve-merge"), "ft-queue-digest.sh": ("issue",), "ft-resume-attempt.sh": ("allow",)}  # 뒤 두 도구는 r163·r165 가 만든다 — 이름만 먼저 막는다
WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
VALOPTS = {"-u", "-C", "-S", "-P", "-k", "-s", "-n"}  # 값을 하나 더 먹는 래퍼 옵션(env -u NAME · timeout -k N · nice -n N)
ANY_ARG = {"tee", "touch", "rm", "truncate", "ln", "install", "shred", "unlink", "mv"}
REASON = ("자율 모드 상태 파일(autonomy.json·autonomy.log)·병합 승인(autonomy-merge-approved/·옛 autonomy-merge-ok/)·묶음 발급(autonomy-digest/)·재개 원장(seat-resume-attempts/) 쓰기와 "
          "ft-autonomy.sh on|off|approve-merge · ft-queue-digest.sh issue · ft-resume-attempt.sh allow 는 오빠 `!` 한 줄만 — 좌석 경로 0(판정 1322·1675). "
          "읽기(cat·jq·tail·ft-autonomy.sh status)는 허용.")


def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" autonomy-state-guard: {msg}\n")
    except OSError:
        pass


def in_byz(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return bool(root) and os.path.isdir(os.path.join(root, ".fable-team"))


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
    """명령 문자열 → [(단어들, 리다이렉트 대상들)] — 따옴표 안·heredoc 본문은 글자일 뿐 명령이 아니다."""
    lex = shlex.shlex(strip_heredocs(cmd), posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
    segs, words, reds, redir = [], [], [], None  # redir: None | "out"(다음 토큰 = 쓰기 대상) | "in"(다음 토큰 = 입력/heredoc 구분자 — 건너뜀)
    for t in lex:
        if redir:
            reds += [t] if redir == "out" else []
            redir = None
        elif t and set(t) <= set(";&|()\n"):
            segs.append((words, reds)); words, reds = [], []
        elif t and set(t) <= set("<>&|"):
            redir = "out" if ">" in t else "in" if "<" in t else None
        else:
            words.append(t)
    return segs + [(words, reds)]


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
                if split is not None:  # 첫 낱말이 실행 프로그램 — 맨 위 루프가 다시 벗긴다(bash -c 일 때만 -c 문자열을 셸 코드로 재검사)
                    w = split
                    break
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


def violates(cmd, depth=0):
    for words, reds in simple_commands(cmd):
        if any(PROT.search(t) for t in reds):
            return True
        prog, args = resolve(words)
        if prog == "-c" and depth < 3 and args and violates(args[0], depth + 1):
            return True
        plain = [a for a in args if not a.startswith("-")]
        if plain[:1] and plain[0] in DENY_EXEC.get(prog, ()):
            return True
        if prog in ANY_ARG and any(PROT.search(a) for a in plain):
            return True
        if prog == "cp" and plain and PROT.search(plain[-1]):
            return True
        if prog == "dd" and any(a.startswith("of=") and PROT.search(a[3:]) for a in args):
            return True
        if prog in ("sed", "perl") and any(re.match(r"^-[A-Za-z]*i", a) for a in args) and any(PROT.search(a) for a in plain):
            return True
    return False


try:
    d = json.loads(os.environ["INPUT"])
    ti = d.get("tool_input") or {}
    tool = d.get("tool_name")
    if tool not in ("Bash", "Write", "Edit", "NotebookEdit") or not in_byz(d.get("cwd")):
        sys.exit(0)
    hit = violates(ti.get("command") or "") if tool == "Bash" else bool(PROT.search(str(ti.get("file_path") or ti.get("notebook_path") or "")))
except (ValueError, OSError, AttributeError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 허용(fail-open)")
    sys.exit(0)
if hit:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": REASON}}, ensure_ascii=False))
PYEOF
exit 0
