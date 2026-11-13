"""autonomy_scope_code_word.py — 코드 리터럴 길(r1195)에서 «셸 명령이 될 수 없는 자리» 의 한 낱말 리터럴을 판정 글에서 뺀다(r1801).

왜: `result["set"]` 줄은 리터럴 밖을 지우면 «set» 한 낱말이 남아 «환경변수 통째 출력» 으로 거절됐다(cfo PR 8454 오탐).
빼는 리터럴(A2) = ⓐ 안 글이 낱말 1개 ⓒ 자리 = ①첨자 키 `x[<리터럴>]` ②dict 키 `{|, <리터럴> :` ③함수 인자 `이름(…, <리터럴>, …)`
  ⓓ 감싼 «모든» 호출(괄호 깊이 · 여러 줄)의 이름 중 실행 이름표(A3)가 하나도 없다 — 하나라도 있으면 그대로 판정(거절 유지가 먼저).
표 밖 wrapper 는 추적하지 않는다(하드 룰 14). 뺀 리터럴은 마스크에서 지워 공백이 된다(A4 · 줄 번호 그대로).
보정1(DA #293603): 파이썬 주석 안 괄호는 추적 밖(R1) · 첨자 `[` 앞 공백 허용 · 실행 이름표는 «(» 호출에만(R2 · `run["set"]` = 첨자).
"""
import re

WORD = re.compile(r"[A-Za-z0-9_.-]+")
EXEC = re.compile(r"(?:system|popen|Popen|run|call|check_call|check_output|getoutput|getstatusoutput"
                  r"|create_subprocess_exec|create_subprocess_shell|spawn\w*|exec\w*)")   # A3 실행 이름표(exec*·spawn* = execvp·execSync·spawnSync 포함)
NAME = re.compile(r"[\w$]+$")
KEYWORDS = {"return", "yield", "in", "not", "and", "or", "if", "elif", "else", "is", "await", "lambda", "case",
            "assert", "del", "from", "import", "with", "as", "for", "while", "typeof", "new", "throw"}   # 이 낱말 뒤 `[` = 목록(첨자 아님)


def _near(text, mask, i, step):   # i 에서 step 쪽으로 리터럴 밖 «공백 아닌» 첫 글자 · 없으면 ""
    while 0 <= i < len(text):
        if not mask[i] and not text[i].isspace():
            return text[i]
        i += step
    return ""


def _open(text, i, c):   # 여는 괄호 → (글자, 첨자인가, 호출 이름) · 이름은 «(» 호출에만 붙는다
    head = text[max(0, i - 80):i].rstrip(" \t")
    word = (NAME.search(head) or [""])[0]
    if c == "(":
        return c, False, word
    sub = c == "[" and head[-1:] != "" and (head[-1] in "])\"'" or (word != "" and word not in KEYWORDS))
    return c, sub, ""   # 첨자 = `[` 앞(공백 허용)이 이름·닫는 괄호·따옴표 · 키워드·기호 뒤 `[` = 목록


def _spot(text, mask, s, e, top):   # ⓒ 자리 ①②③ 중 하나인가 · top = 가장 안쪽 여는 괄호 (글자, 첨자인가, 호출 이름)
    before, after = _near(text, mask, s - 1, -1), _near(text, mask, e, 1)
    if before == "[" and after == "]" and top and top[1]:
        return True   # ① 첨자 키(목록 `[` → 빼지 않음)
    if before in "{," and before and after == ":":
        return True   # ② dict 키
    return bool(top and top[0] == "(" and top[2] and before in "(," and before and after in "),")   # ③ 함수 인자


def drop(text, mask, hash_comment=False):   # → 새 마스크 · 뺀 리터럴 자리는 False · hash_comment = 파이썬 주석(# ~ 줄 끝)은 괄호 추적 밖
    out, stack, i, n = list(mask), [], 0, len(text)
    while i < n:
        if not mask[i]:
            c = text[i]
            if c == "#" and hash_comment:
                j = text.find("\n", i)
                i = n if j < 0 else j
                continue
            if c in "([{":
                stack.append(_open(text, i, c))
            elif c in ")]}" and stack:
                stack.pop()
            i += 1
            continue
        e = i
        while e < n and mask[e]:
            e += 1
        body = text[i:e]
        if len(body) >= 2 and body[0] in "\"'`" and body[-1] == body[0] and WORD.fullmatch(body[1:-1]) \
                and _spot(text, mask, i, e, stack[-1] if stack else None) \
                and not any(EXEC.fullmatch(nm) for _c, _p, nm in stack):
            out[i:e] = [False] * (e - i)
        i = e
    return out
