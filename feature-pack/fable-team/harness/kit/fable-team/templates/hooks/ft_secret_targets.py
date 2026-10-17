"""ft_secret_targets — ft_secret_judge 의 «비밀을 stdout 으로 내는 모양» 표(R135a · R219 분리): target(단어들) → 고정 이유 글자 | None.
문자열만 본다(실행 0). 이유는 고정 글자뿐 — 명령 속 값·이름을 다시 쓰지 않는다."""
from __future__ import annotations

import re

from ft_secret_lex import W

NAME = re.compile(r"PASSWORD|PASS|TOKEN|SECRET|DSN|KEY|WEBHOOK", re.I)
SECRET_VAR = re.compile(r"\$\{?[A-Za-z_]*(?:" + NAME.pattern + ")", re.I)
READERS = {"cat", "head", "tail", "less", "more", "bat", "nl", "tac", "strings", "od", "xxd", "grep", "egrep", "fgrep"}


def secret_path(p: str) -> bool:
    b = p.rsplit("/", 1)[-1]
    if re.search(r"(^|/)secrets/", p) or p.endswith(".cred"):
        return True
    if re.fullmatch(r"\.env(\..+)?", b):
        return not b.endswith((".example", ".sample", ".template"))
    return "token" in b and not b.endswith((".md", ".py", ".sh", ".ts", ".js", ".html"))


DUMPERS = {"diff", "cmp", "comm", "paste", "column", "fold", "expand", "rev", "sort", "uniq", "base64", "jq", "yq", "hexdump", "iconv"}
KEYS_FILTERS = {"keys", "keys[]", "keys_unsorted", "length", "type"}  # jq·yq 가 키 이름·개수만 내는 필터
LISTERS = {"export", "declare", "typeset", "readonly"}
AWKS = {"awk", "gawk", "mawk", "nawk"}
INTERP = re.compile(r"python[0-9.]*|node(?:js)?|ruby|perl")
CODE_FLAG = re.compile(r"-[a-zA-Z]*[ceEp]|--eval|--print")
ENV_DUMP = {  # 언어 → «통째» 환경변수 모양(첨자·.get 처럼 한 칸만 집는 것은 제외)
    "py": r"\b(?:os\.)?environ\b(?!\s*\[|\.(?:get|setdefault|pop|keys|__contains__)\b)",
    "no": r"\bprocess\.env\b(?!\s*[.\[])",
    "ru": r"\bENV\b(?!\s*\[|\.(?:fetch|key\?|keys|has_key\?))",
    "pe": r"%ENV\b",
}
NAMES_ONLY = re.compile(r"(?:sorted\(|list\(|len\(|\bin\s+|import\s+(?:[\w.]+\s*,\s*)*|Object\.keys\(|\bkeys\s+)$")
READ_CODE = re.compile(r"\bopen\b|readFile|File\.read|IO\.read|\bread\b")
KEYS_ONLY_CODE = re.compile(r"(?:import [\w, ]+;\s*)*print\((?:sorted|len)\(json\.load\(open\(sys\.argv\[\d+\]\)\)\)\)\s*")  # BOOT 22 의 키 이름만 idiom 한 꼴 전체
GIT_SHOW = {"diff", "show", "log", "cat-file", "blame"}
GIT_QUIET = {"--stat", "--name-only", "--name-status", "--numstat", "--shortstat", "--summary", "--quiet", "--raw"}
GIT_PATCH = {"-p", "--patch", "-u", "--cc", "--patch-with-stat", "--patch-with-raw"}
FILE_LEAK = " 로 비밀 파일 내용 출력"


def _flag(x: str, letters: str) -> bool:
    return re.fullmatch(r"-[a-zA-Z]*[%s][a-zA-Z]*" % letters, x) is not None


def dumper(h: str, r: list[W], pos: list[W]) -> str | None:  # 파일을 되비추는 명령 — 내용 0 인 옵션(diff -q · cmp 기본)은 통과
    if not any(secret_path(x) for x in pos):
        return None
    if h == "diff" and any(_flag(x, "q") or x == "--brief" for x in r):
        return None
    if h in ("jq", "yq") and all(x.replace(" ", "") in KEYS_FILTERS for x in pos if not secret_path(x)):
        return None
    if h == "cmp" and not any(_flag(x, "l") or x == "--verbose" for x in r):
        return None
    return h + FILE_LEAK


def cut(r: list[W], pos: list[W]) -> str | None:  # -d= -f1(키 이름)만 통과 — 다른 칸·글자·바이트는 값이다
    if not any(secret_path(x) for x in pos):
        return None
    fields = [x[2:] for x in r if x.startswith("-f") and len(x) > 2] + [b for a, b in zip(r, r[1:]) if a == "-f"]
    delim = "-d=" in r or any(a == "-d" and b == "=" for a, b in zip(r, r[1:]))
    if fields == ["1"] and delim and not any(_flag(x, "cb") for x in r):
        return None
    return "cut 로 비밀 값 출력"


def listing(h: str, r: list[W], pos: list[W]) -> str | None:  # export -p · declare -p/-x · typeset -p — 대상 이름 없음(또는 비밀 이름)이면 환경 출력
    if not (any(_flag(x, "p") for x in r) or (h in ("declare", "typeset") and any(_flag(x, "x") for x in r))) or any("=" in x for x in pos):
        return None
    return h + " 로 환경변수 통째 출력" if not pos or any(NAME.search(x) for x in pos) else None


def sed_opts(r: list[W]) -> tuple[list[str], bool, bool, bool, list[str]]:  # → (식들, -f 쓰나, -n 쓰나, -i 쓰나, 위치 단어들) — 옵션 파서(붙임·분리·복합 -nf·--long=)
    ex, f, n, ip, rest, i = [], False, False, False, [], 0
    while i < len(r):
        x, i = r[i], i + 1
        if x.startswith("--"):
            k, _, v = x.partition("=")
            opts = [({"--expression": "e", "--file": "f", "--quiet": "n", "--silent": "n", "--in-place": "i"}.get(k, ""), v)]
        elif x.startswith("-") and len(x) > 1:
            opts = []
            for j, c in enumerate(x[1:], 2):
                opts.append((c, x[j:] if c in "efli" else ""))
                if c in "efli":
                    break
        else:
            rest.append(x)
            continue
        for c, v in opts:
            if c and c in "efl" and not v and i < len(r):
                v, i = r[i], i + 1
            ex += [v] if c == "e" else []
            f, n, ip = f or c == "f", n or c == "n", ip or c == "i"
    return ex, f, n, ip, rest


def sed(r: list[W]) -> str | None:  # -n 이면서 p 명령이 없거나 -i(제자리 수정)이면 stdout 이 비어 있다 · -f(식 파일)는 알 수 없어 거절
    ex, f, n, ip, rest = sed_opts(r)
    if not any(secret_path(x) for x in rest) or ip:
        return None
    scripts = ex or [" ".join(x for x in rest if not secret_path(x))]
    if n and not f and not any(re.search(r"(?:^|[\d$\x01;{}!/\s])p(?:$|[;}\s])", t) for t in scripts):
        return None
    return "sed" + FILE_LEAK


def awk(r: list[W], pos: list[W]) -> str | None:  # 프로그램 전체가 `-F=` 의 `{print $1}` 한 꼴(키 이름)일 때만 통과 — 다른 pattern·action 은 기본 출력이 새어 나간다
    if not any(secret_path(x) for x in pos):
        return None
    prog = next((x for x in pos if x != "=" and not secret_path(x)), "")
    fs = [x[2:] if len(x) > 2 else (r[k + 1] if k + 1 < len(r) else "") for k, x in enumerate(r) if x.startswith("-F")]
    keys = bool(fs) and fs[-1] == "=" and not any(x.startswith(("FS=", "-vFS=")) for x in r)  # 유효 FS 가 정확히 `=` (마지막 -F · -v FS= 없음)
    only = re.fullmatch(r"\s*\{\s*print\s*\(?\s*[$\x01]1\s*\)?\s*;?\s*\}\s*", prog)
    return None if keys and only and not any(_flag(x, "f") for x in r) else "awk" + FILE_LEAK


def interp(h: str, r: list[W]) -> str | None:  # -c/-e 본문만 본다 — 스크립트 파일 실행은 문자열로 알 수 없다
    k = next((i for i, x in enumerate(r[:-1]) if CODE_FLAG.fullmatch(x)), None)
    if k is None:
        return None
    body, code, lang = " ".join(r), r[k + 1], h[:2]
    if any(not NAMES_ONLY.search(body[:m.start()]) for m in re.finditer(ENV_DUMP[lang], body)):
        return h + " 로 환경변수 통째 출력"
    paths = re.findall(r"""['"]([^'"]+)['"]""", body) + [x for x in r if not re.search(r"[\s()]", x)]
    if any(secret_path(p) for p in paths) and READ_CODE.search(body) and not KEYS_ONLY_CODE.fullmatch(code):
        return h + FILE_LEAK
    return None


def git(r: list[W]) -> str | None:  # 비밀 경로(pathspec 또는 <rev>:<경로>)의 «내용»을 찍는 하위 명령
    i = 0
    while i < len(r) and r[i].startswith("-"):
        i += 2 if r[i] in ("-C", "-c") else 1
    if i >= len(r) or r[i] not in GIT_SHOW:
        return None
    sub, args = r[i], r[i + 1:]
    if not any(secret_path(x.split(":", 1)[-1]) for x in args if not x.startswith("-")):
        return None
    patch = any(x in GIT_PATCH for x in args)
    if (sub == "log" and not patch) or (sub == "cat-file" and "-p" not in args):
        return None
    if not patch and any(x.split("=")[0] in GIT_QUIET for x in args):
        return None
    return "git" + FILE_LEAK


def target(a: list[W]) -> str | None:  # 비밀을 stdout 으로 내는 모양이면 고정 이름, 아니면 None
    if not a:
        return None
    h, r = a[0], a[1:]
    pos = [x for x in r if not x.startswith("-")]
    if h in ("secret", "ft-secret"):
        return "래퍼 secret 의 맨 호출"
    if h == "gcloud" and any(r[i:i + 3] == ["secrets", "versions", "access"] for i in range(len(r))):
        return "gcloud secrets versions access"
    if h == "op" and (r[:1] == ["read"] or ("item" in r and "get" in r and any(x.startswith("--reveal") for x in r))):
        return "op 비밀 조회"
    if h == "security" and r[:1] in (["find-generic-password"], ["find-internet-password"]) and any(re.fullmatch(r"-[a-zA-Z]*[wg][a-zA-Z]*", x) for x in r):
        return "security 비밀번호 조회"
    if h == "gh" and r[:2] == ["auth", "token"]:
        return "gh auth token"
    if h == "printenv" and (not pos or any(NAME.search(x) for x in pos)):
        return "printenv 의 비밀 출력"
    if h == "env" and not pos:
        return "env 전체 출력"
    if h in ("echo", "printf") and any(SECRET_VAR.search(x) for x in r):
        return h + " 로 비밀 변수 출력"
    if h in READERS:
        grep = h.endswith("grep")
        if grep and any(re.fullmatch(r"-[a-zA-Z]*[qclL][a-zA-Z]*", x) or x in ("--quiet", "--count", "--files-with-matches") for x in r):
            return None  # 내용 없이 개수·이름만 나온다
        if any(secret_path(x) for x in (pos[1:] if grep else pos)):
            return h + FILE_LEAK
    if h == "cut":
        return cut(r, pos)
    if h in LISTERS:
        return listing(h, r, pos)
    if h == "set" and not r:
        return "set 로 환경변수 통째 출력"
    if h in DUMPERS:
        return dumper(h, r, pos)
    if h == "sed":
        return sed(r)
    if h in AWKS:
        return awk(r, pos)
    if INTERP.fullmatch(h):
        return interp(h, r)
    if h == "git":
        return git(r)
    return None
