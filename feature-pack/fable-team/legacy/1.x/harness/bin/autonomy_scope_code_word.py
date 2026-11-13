"""autonomy_scope_code_word.py — 코드 리터럴 길(r1195)에서 «셸 명령이 될 수 없는 자리» 의 한 낱말 리터럴을 판정 글에서 뺀다(r1801).

왜: `result["set"]` 줄은 리터럴 밖을 지우면 «set» 한 낱말이 남아 «환경변수 통째 출력» 으로 거절됐다(cfo PR 8454 오탐).
빼는 리터럴(A2) = ⓐ 안 글이 낱말 1개 ⓒ 자리 = ①첨자 키 `x[<리터럴>]` ②dict 키 `{|, <리터럴> :` ③함수 인자 `이름(…, <리터럴>, …)`
  ⓓ 감싼 «모든» 호출(괄호 깊이 · 여러 줄)의 이름 중 실행 이름표(A3)가 하나도 없다 — 하나라도 있으면 그대로 판정(거절 유지가 먼저).
표 밖 wrapper 는 추적하지 않는다(하드 룰 14). 뺀 리터럴은 마스크에서 지워 공백이 된다(A4 · 줄 번호 그대로).
"""
import re

WORD = re.compile(r"[A-Za-z0-9_.-]+")
EXEC = re.compile(r"(?:system|popen|Popen|run|call|check_call|check_output|getoutput|getstatusoutput"
                  r"|create_subprocess_exec|create_subprocess_shell|spawn\w*|exec\w*)")   # A3 실행 이름표(exec*·spawn* = execvp·execSync·spawnSync 포함)
NAME = re.compile(r"[\w$]+$")


def _near(text, mask, i, step):   # i 에서 step 쪽으로 리터럴 밖 «공백 아닌» 첫 글자 · 없으면 ""
    while 0 <= i < len(text):
        if not mask[i] and not text[i].isspace():
            return text[i]
        i += step
    return ""


def _spot(text, mask, s, e, top):   # ⓒ 자리 ①②③ 중 하나인가 · top = 가장 안쪽 여는 괄호 (글자, 위치, 이름)
    before, after = _near(text, mask, s - 1, -1), _near(text, mask, e, 1)
    if before == "[" and after == "]" and top and top[0] == "[" and re.match(r"[\w\])\"']", text[top[1] - 1:top[1]] or " "):
        return True   # ① 첨자 키(목록 `[` 앞은 이름·닫는 괄호가 아님 → 빼지 않음)
    if before in "{," and before and after == ":":
        return True   # ② dict 키
    return bool(top and top[0] == "(" and top[2] and before in "(," and before and after in "),")   # ③ 함수 인자


def drop(text, mask):   # → 새 마스크 · 뺀 리터럴 자리는 False(리터럴 밖 = 공백으로 바뀜)
    out, stack, i, n = list(mask), [], 0, len(text)
    while i < n:
        if not mask[i]:
            c = text[i]
            if c in "([{":
                stack.append((c, i, (NAME.search(text[max(0, i - 80):i].rstrip(" \t")) or [""])[0]))
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
