"""r546 ⓒⓓ 대조용 — 바꾸기 «전» 사본 함수의 원문(r546 이전 판 · 글자 그대로 옮겨 적었다 · 고치지 않는다).
segments = kit/hooks/op-vault-develop-gate.sh:38-57 · env_split = kit/fable-team/templates/hooks/autonomy-merge-guard.sh:108-121 (2026-10-20 r546 착수 시점)."""
# ruff: noqa: E702  (옛 사본 원문 그대로 — 세미콜론 2문장은 이 판의 문체다 · 고치면 대조가 아니다)
import re
import shlex


def segments(cmd):
    """따옴표 밖의 구분자로 명령을 조각낸다(따옴표 안은 한 덩어리 · tracked-bin-call-gate 꼴)."""
    out, cur, q, i = [], [], None, 0
    while i < len(cmd):
        c = cmd[i]
        if q:
            cur.append(c)
            if c == q and (q == "'" or cmd[i - 1] != "\\"):
                q = None
        elif c in "'\"":
            q = c; cur.append(c)
        elif c == "$" and cmd[i:i + 2] == "$(":
            out.append("".join(cur)); cur = []; i += 1
        elif c in ";&|\n()`":
            out.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [s.strip() for s in out if s.strip()]


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
