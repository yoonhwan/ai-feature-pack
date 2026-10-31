"""ft_secret_lex — ft_secret_judge 의 셸 글 쪼개기(R135a): heredoc 본문 제거 · 따옴표 벗기기 · 구간(; 개행 && || | & ( ))·$(…)·백틱 치환 분리.
문자열만 본다(실행 0). 알려진 모양용 얕은 렉서다 — 셸 전체 문법이 아니다."""
from __future__ import annotations

import re

HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(?:(['\"])(?P<q>\w+)\1|(?P<b>\\)(?P<bn>\w+)|(?P<n>[A-Za-z_]\w*))")


ARRAY_HEAD = re.compile(r"[A-Za-z_]\w*(\[[^\]]*\])?\+?=")  # 배열 대입 머리 «이름=»·«이름+=»·«이름[i]=» (r1249)


class W(str):
    """따옴표를 벗긴 단어. subs = 안에 든 $(…)·백틱 치환 글(단어 안 그 자리는 \\x00 · 작은따옴표 안 $ 는 \\x01)."""
    subs: list[str]

    def __new__(cls, s: str, subs: list[str] | tuple[str, ...] = ()):
        o = super().__new__(cls, s)
        o.subs = list(subs)
        return o


def body_subs(body: str) -> str:  # 비인용 heredoc 본문에서 셸이 «실행하는» $(…)·백틱 치환과 변수 확장을 뽑아 단어로 잇는다(\\$ 는 글자 · 줄바꿈은 ; 로)
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\":
            i += 2
        elif body[i:i + 2] == "$(":
            inner, i = read_sub(body, i)
            out.append("$(%s)" % inner.replace("\n", ";"))
        elif c == "$" and re.match(r"\$\{?[A-Za-z_]", body[i:]):  # 변수 확장 — 비밀 이름인지는 판정기가 `echo $NAME` 로 본다
            m = re.match(r"\$\{?[A-Za-z_]\w*", body[i:])
            out.append("$(echo %s})" % m.group(0) if m.group(0).startswith("${") else "$(echo %s)" % m.group(0))
            i += m.end()
        elif c == "`":
            j = body.find("`", i + 1)
            j = len(body) if j < 0 else j
            out.append("`%s`" % body[i + 1:j].replace("\n", ";"))
            i = j + 1
        else:
            i += 1
    return "".join(" " + x for x in out)


def strip_heredocs(t: str) -> str:  # 인용 delimiter(<<'E' <<"E" <<\E) 본문은 글자 → 제거 · 비인용 본문은 치환($(…)·백틱)만 명령 줄에 남긴다 · 줄 수는 보존
    while True:
        m = HEREDOC.search(t)
        nl = t.find("\n", m.end()) if m else -1
        if not m or nl < 0:
            return t
        word = m.group("q") or m.group("bn") or m.group("n")
        quoted = not m.group("n")
        end = re.search(r"(?m)^[ \t]*%s[ \t]*$" % re.escape(word), t[nl + 1:])
        stop = nl + 1 + end.end() if end else len(t)
        extra = "" if quoted else body_subs(t[nl + 1:nl + 1 + end.start()] if end else t[nl + 1:])
        t = t[:m.start()] + extra + t[m.end():nl] + "\n" * t[nl:stop].count("\n") + t[stop:]


def read_sub(t: str, i: int) -> tuple[str, int]:  # t[i:i+2] == '$(' → (안쪽 글, 다음 위치)
    d, j = 1, i + 2
    while j < len(t) and d:
        c = t[j]
        if c == "\\":
            j += 1
        elif c in "'\"":
            k = j + 1
            while k < len(t) and t[k] != c:
                k += 2 if t[k] == "\\" and c == '"' else 1
            j = k
        d += (c == "(") - (c == ")")
        j += 1
    return t[i + 2:j - 1], j


def read_array(t: str, i: int) -> tuple[list[W], int] | None:  # t[i]=='(' 배열 대입 → (치환이 든 원소 단어들, 짝 ')' 다음 위치) · 짝이 없으면 None(서브셸로 읽는다)
    inner, j = read_sub(t, i - 1)  # '$(' 읽기를 «x(» 자리에 빌려 쓴다 — 따옴표·\ 를 건너뛰며 짝 ')' 를 찾는다
    return None if t[j - 1:j] != ")" else ([w for _s, ws, _sep in scan(inner) for w in ws if w.subs], j)


def scan(t: str) -> list[tuple[int, list[W], str]]:  # → [(시작 위치, 단어들, 구분자)]
    segs: list[tuple[int, list[W], str]] = []
    words: list[W] = []
    cur: list[str] = []
    subs: list[str] = []
    st = {"has": False, "start": 0}

    def word() -> None:
        if st["has"]:
            words.append(W("".join(cur), subs))
        cur.clear()
        subs.clear()
        st["has"] = False

    def seg(sep: str, nxt: int) -> None:
        word()
        segs.append((st["start"], list(words), sep))
        words.clear()
        st["start"] = nxt

    def sub(inner: str) -> None:
        subs.append(inner)
        cur.append("\x00")
        st["has"] = True

    def back(i: int) -> int:  # 백틱 치환 → 다음 위치
        j = t.find("`", i + 1)
        j = len(t) if j < 0 else j
        sub(t[i + 1:j])
        return j + 1

    i, n = 0, len(t)
    while i < n:
        c, nx = t[i], t[i + 1:i + 2]
        if c == "\\":
            if nx != "\n":
                cur.append(nx)
                st["has"] = True
            i += 2
        elif c == "'":
            j = t.find("'", i + 1)
            j = n if j < 0 else j
            cur.append(t[i + 1:j].replace("$", "\x01").replace("`", "\x01"))
            st["has"] = True
            i = j + 1
        elif c == '"':
            i += 1
            st["has"] = True
            while i < n and t[i] != '"':
                if t[i] == "\\":
                    cur.append(t[i + 1:i + 2])
                    i += 2
                elif t[i:i + 2] == "$(":
                    inner, i = read_sub(t, i)
                    sub(inner)
                elif t[i] == "`":
                    i = back(i)
                else:
                    cur.append(t[i])
                    i += 1
            i += 1
        elif t[i:i + 2] == "$(":
            inner, i = read_sub(t, i)
            sub(inner)
        elif c == "`":
            i = back(i)
        elif c in " \t":
            word()
            i += 1
        elif c == "#" and not st["has"]:
            j = t.find("\n", i)
            i = n if j < 0 else j
        elif c in ";\n":
            seg(c, i + 1)
            i += 1
        elif c == "|" and t[i - 1:i] != ">":  # `>|` 는 덮어쓰기 리다이렉트
            k = 2 if nx in ("|", "&") else 1
            seg("||" if nx == "|" else "|", i + k)
            i += k
        elif c == "&" and nx != ">" and t[i - 1:i] not in ("<", ">"):  # `&>` `>&` `2>&1` 는 리다이렉트
            k = 2 if nx == "&" else 1
            seg("&" * k, i + k)
            i += k
        elif c == "(" and t[i + 1:].lstrip().startswith(")"):  # 함수 정의 `name() {` — 이름은 명령이 아니다
            words.clear()
            cur.clear()
            subs.clear()
            st["has"] = False
            i = t.index(")", i) + 1
        elif c == "(" and ARRAY_HEAD.fullmatch("".join(cur)) and all(ARRAY_HEAD.match(w) for w in words) and (arr := read_array(t, i)):
            word()  # 배열 대입 «이름=(…)» — 괄호는 서브셸이 아니다 · 글자 원소는 버리고 치환($(…)·백틱) 든 원소만 같은 구간 인자로 남겨 지금처럼 판정(r1249)
            for w in arr[0]:
                subs.extend(w.subs)
                cur.append("\x00" * len(w.subs))
                st["has"] = True
                word()
            i = arr[1]
        elif c in "()":
            seg(c, i + 1)
            i += 1
        else:
            if c in "<>" and not re.fullmatch(r"[0-9]*[&<>]*", "".join(cur)):
                word()
            cur.append(c)
            st["has"] = True
            i += 1
    seg("", n)
    return segs
