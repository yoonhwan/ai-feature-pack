#!/bin/bash
# mbox-body-subst-gate — PreToolUse:Bash (r1400 · 2026-11-05 docker 볼륨 83개 사고)
# 왜: 쪽지 본문을 큰따옴표로 넘기면서 그 안에 `$(docker volume prune -f)` 꼴을 적었다. 셸이 «쪽지를 보내기 전»에
#   그 명령을 실행해 9.8GB 볼륨이 승인 없이 지워졌다. mbox.sh 는 이미 치환된 글자를 받으므로 안에서 막을 수 없다 —
#   막을 곳은 실행 전 단계인 이 훅 하나뿐이다. 본문은 글자여야 한다.
# 판정: 명령 구간의 «mbox.sh(ft-mbox.sh) 의 send·relay» 를 찾아 본문 인자(send = 셋째 인자 · relay = 요약 인자)의
#   «원문 글자»(셸이 풀기 전)를 본다 — 따옴표 밖이나 큰따옴표 안에 백틱 또는 `$(` 가 있으면 exit 2. 홑따옴표 안은 글자라 통과.
# 예외 1개: 본문 인자 전체가 `"$(cat <경로>)"` 또는 `"$(< <경로>)"` 한 개 = 파일 읽기 → 통과(파일 안 글자는 다시 풀리지 않는다).
# ★FAIL-OPEN(sibling 훅 관례)★: stdin JSON 해석 실패 = 허용 + stderr 1줄 — 단 «쪽지 송신 + 치환 글자» 가 같이 보이면 막는다(의심 쪽).
# ★설치(~/.claude/hooks/ cp + settings.json PreToolUse Bash 등록)는 이 파일 범위 밖 — master 몫★
# ★알려진 한계★: `bash -c '<안쪽 명령>'` 처럼 «다른 셸에 글자로 넘긴» 구간은 이 훅이 풀지 않는다(간접 실행 범위 밖).
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT
python3 - <<'PYEOF'
import json, os, re, sys

MSG = (
    "🚫 쪽지 본문 안 명령 치환 금지 (11-05 docker 볼륨 83개 사고)\n"
    "본문은 파일에 쓰고 \"$(cat 파일)\" 또는 relay 로 넘기세요. 본문 안 백틱·$( ) 는 보내기 전에 셸이 실행합니다.\n"
)


def block(detail):
    sys.stderr.write(MSG + "명령: " + detail[:300] + "\n")
    sys.exit(2)


def warn_open(what):
    sys.stderr.write("WARN mbox-body-subst-gate: " + what + " — 검사 없이 허용(fail-open)\n")
    sys.exit(0)


raw = os.environ.get("INPUT", "")
try:
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("객체 아님")
    cmd = data.get("tool_input", {}).get("command", "")
    if not isinstance(cmd, str) or not cmd:
        raise ValueError("command 없음")
except Exception as e:
    if re.search(r"mbox\.sh[^;&|\n]{0,40}(send|relay)", raw) and ("$(" in raw or "`" in raw):
        block(raw)
    warn_open("stdin JSON 해석 실패(" + str(e) + ")")

INTERP = {"bash", "sh", "zsh", "dash", "ksh", "env", "exec", "command", "timeout", "nohup", "time"}
SCRIPT = ("mbox.sh", "ft-mbox.sh")
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\[[^\]]*\])?\+?=")
# 예외: 본문 인자 전체가 파일 읽기 한 개 — 경로 = 글자 + 변수 펼침($NAME · ${NAME} · 매개변수 펼침은 명령 실행이 아니다 · r1403) · 경로를 큰따옴표로 감싼 꼴도 허용
#   그 밖 글자(; & | ` ( ) ' · $( · ${…:-…} 펼침 연산)는 예외 밖 = 막는다
_PIECE = r"[A-Za-z0-9_./~+:@-]|\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Za-z_][A-Za-z0-9_]*"
_PATH = r"(?:" + _PIECE + r")+"
_DQ = '"'
EXC = re.compile(r"^\$\(\s*(?:cat\s+(?:" + _PATH + "|" + _DQ + _PATH + _DQ + r")|<\s*(?:" + _PATH + "|" + _DQ + _PATH + _DQ + r"))\s*\)$")
OP = "op"


def subst_end(text, i):
    """text[i:i+2] == "$(" → 매칭 ")" 다음 위치. 치환 전체를 한 낱말 조각으로 삼킨다(셸도 그렇게 한 단어로 본다)."""
    depth, j, n, q = 0, i + 1, len(text), None
    while j < n:
        ch = text[j]
        if q:
            if ch == "\\" and q == '"':
                j += 2
                continue
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise ValueError("치환 미종결")


def tokenize(text):
    """셸 단어로 나누되 «어느 따옴표 안 글자였는지» 를 남긴다 — kind: u=따옴표 밖 · d=큰따옴표 · s=홑따옴표."""
    toks, cur, i, n, q = [], [], 0, len(text), None
    while i < n:
        ch = text[i]
        if q is None:
            if ch in " \t":
                if cur:
                    toks.append(cur)
                    cur = []
                i += 1
            elif ch == "\n" or ch in ";&|()":
                if cur:
                    toks.append(cur)
                    cur = []
                toks.append([(OP, ch)])
                i += 1
            elif ch == "'":
                q = "'"
                cur.append(("s", ""))
                i += 1
            elif ch == '"':
                q = '"'
                cur.append(("d", ""))
                i += 1
            elif ch == "\\":
                if i + 1 < n:
                    cur.append(("u", text[i + 1]))
                i += 2
            elif ch == "$" and i + 1 < n and text[i + 1] == "(":
                e = subst_end(text, i)
                if cur and cur[-1][0] == "u":
                    cur[-1] = ("u", cur[-1][1] + text[i:e])
                else:
                    cur.append(("u", text[i:e]))
                i = e
            else:
                if cur and cur[-1][0] == "u":
                    cur[-1] = ("u", cur[-1][1] + ch)
                else:
                    cur.append(("u", ch))
                i += 1
        elif q == "'":
            if ch == "'":
                q = None
                i += 1
            else:
                if cur and cur[-1][0] == "s":
                    cur[-1] = ("s", cur[-1][1] + ch)
                else:
                    cur.append(("s", ch))
                i += 1
        else:  # 큰따옴표 안 — \" \\ \$ \` 만 탈출
            if ch == '"':
                q = None
                i += 1
            elif ch == "\\" and i + 1 < n and text[i + 1] in '"$`\\':
                if cur and cur[-1][0] == "d":
                    cur[-1] = ("d", cur[-1][1] + text[i + 1])
                else:
                    cur.append(("d", text[i + 1]))
                i += 2
            elif ch == "$" and i + 1 < n and text[i + 1] == "(":
                e = subst_end(text, i)
                if cur and cur[-1][0] == "d":
                    cur[-1] = ("d", cur[-1][1] + text[i:e])
                else:
                    cur.append(("d", text[i:e]))
                i = e
            else:
                if cur and cur[-1][0] == "d":
                    cur[-1] = ("d", cur[-1][1] + ch)
                else:
                    cur.append(("d", ch))
                i += 1
    if q is not None:
        raise ValueError("따옴표 미종결")
    if cur:
        toks.append(cur)
    return toks


def is_op(tok):
    return len(tok) == 1 and tok[0][0] == OP


def text_of(tok):
    return "".join(t for _, t in tok)


def segments(toks):
    segs, cur = [], []
    for tok in toks:
        if is_op(tok):
            if cur:
                segs.append(cur)
                cur = []
        else:
            cur.append(tok)
    if cur:
        segs.append(cur)
    return segs


def subcommand_index(seg):
    """mbox.sh(ft-mbox.sh) 의 send·relay 토큰 위치 — 명령 자리이거나 bash/sh 계열 인터프리터 바로 뒤만."""
    ci = next((k for k, t in enumerate(seg) if not ASSIGN.match(text_of(t))), None)
    if ci is None:
        return None
    cw = text_of(seg[ci])
    cands = []
    if os.path.basename(cw) in SCRIPT:
        cands.append(ci)
    elif os.path.basename(cw) in INTERP:
        k = ci + 1
        while k < len(seg):
            t = text_of(seg[k])
            if t.startswith("-") or ASSIGN.match(t):
                k += 1
                continue
            if os.path.basename(t) in SCRIPT:
                cands.append(k)
            break
    for k in cands:
        if k + 1 < len(seg) and text_of(seg[k + 1]) in ("send", "relay"):
            return k + 1
    return None


def body_bad(tok):
    kinds = [k for k, _ in tok]
    if kinds and all(k == "s" for k in kinds):
        return False                      # 홑따옴표 전체 = 글자
    if len(tok) == 1 and tok[0][0] == "d" and EXC.match(tok[0][1]):
        return False                      # 파일 읽기 한 개
    return any(k in ("u", "d") and ("`" in t or "$(" in t) for k, t in tok)


try:
    toks = tokenize(cmd)
except Exception as e:
    if re.search(r"mbox\.sh[^;&|\n]{0,40}(send|relay)", cmd) and ("$(" in cmd or "`" in cmd):
        block(cmd)
    warn_open("명령 해석 실패(" + str(e) + ")")

for seg in segments(toks):
    sub = subcommand_index(seg)
    if sub is None:
        continue
    body = seg[sub + 3:] if text_of(seg[sub]) == "send" else seg[sub + 4:]
    for tok in body:
        if body_bad(tok):
            block(cmd)
sys.exit(0)
PYEOF
