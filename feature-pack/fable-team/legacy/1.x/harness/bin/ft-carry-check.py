#!/usr/bin/env python3
"""ft-carry-check.py — r2229 승계 인계서 열린 칸 대조(ft-successor-open.sh ⓐ-4 의 판정 1곳).

쓰기: ft-carry-check.py <새 인계서> --root <ROOT>
  새 인계서의 «앞 인계서: <경로>» 1줄(상대경로 = ROOT 기준) → 앞 판 «## 열린 칸» 절의 칸(줄)마다
  그 줄의 키 하나라도 ① 새 판 «## 열린 칸» 절에 다시 나오거나(이월) ② 새 판 어디든 «닫음: <키…> — <근거 ≥10자>»
  ③ 새 판 어디든 «<…키…>: 이월» 줄에 있으면 통과. 키 없는 칸 = 대조 밖.
rc0 = 통과(OK 1줄) · 줄 없음(WARN 1줄 · 옛 꼴) · rc1 = REJECT 1줄(말없이 사라짐 · 앞 인계서 판정 불가)
자동 길 WARN 낮춤(FT_CARRY_WARN_ONLY)은 부르는 쪽(ft-successor-open.sh) 몫이다.
"""
import os
import re
import sys

KEY = re.compile(r"#(\d{6})|\b(r\d{3,4}[a-z]?)\b|\bPR #?(\d{4})\b")
PREV = re.compile(r"^앞 인계서:\s*(\S.*?)\s*$", re.M)
OPEN = re.compile(r"^## 열린 칸(?!\s*감시)[^\n]*\n(.*?)(?=^## |\Z)", re.M | re.S)
CLOSE = re.compile(r"닫음:\s*(.*?)\s*[—-]\s*(.*)$")
CARRY = re.compile(r"^(.*?):\s*이월")
CELL = re.compile(r"^(- |\* |\d+\. |\|)")
TABLE_SEP = re.compile(r"^\|[-|: ]+\|$")
MIN_WHY = 10


def keys(s):
    return ["#" + a if a else (b or "PR " + c) for a, b, c in KEY.findall(s)]


def cells(sec):  # 칸 = 줄 1개 · 들여쓴 이음 줄은 앞 줄에 붙임 · 표 구분 행 제외
    out = []
    for line in sec.split("\n"):
        if CELL.match(line) and not TABLE_SEP.match(line.strip()):
            out.append(line)
        elif line.startswith((" ", "\t")) and line.strip() and out:
            out[-1] += " " + line.strip()
    return out


def passed_keys(new):  # 새 판에서 «이월·닫음» 으로 인정되는 키
    sec = OPEN.search(new)
    ok = set(keys(sec.group(1))) if sec else set()
    for line in new.split("\n"):
        m = CLOSE.search(line)
        if m and len(m.group(2).strip()) >= MIN_WHY:
            ok |= set(keys(m.group(1)))
        m = CARRY.search(line)
        if m:
            ok |= set(keys(m.group(1)))
    return ok


def judge(body_path, root):
    new = open(body_path, encoding="utf-8").read()
    m = PREV.search(new)
    if not m:
        return 0, "WARN 앞 인계서 줄 없음 · 열린 칸 대조 0"
    rel = m.group(1).strip("`'\"")
    path = rel if os.path.isabs(rel) else os.path.join(root, rel)
    try:
        prev = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        return 1, f"REJECT 앞 인계서 판정 불가 경로 못 읽음 {path}: {type(e).__name__}"
    sec = OPEN.search(prev)
    if not sec:
        return 1, f"REJECT 앞 인계서 판정 불가 «## 열린 칸» 절 없음 {path}"
    ok = passed_keys(new)
    keyed = [k for k in (keys(c) for c in cells(sec.group(1))) if k]
    miss = [k[0] for k in keyed if not any(x in ok for x in k)]
    if miss:
        return 1, f"REJECT 열린 칸 말없이 사라짐 {len(miss)}({' '.join(miss[:8])}) — 새 «## 열린 칸» 에 키 이월 또는 «닫음: <키> — <근거>» · 앞 인계서 {rel}"
    return 0, f"OK 열린 칸 대조 칸 {len(keyed)} · 사라짐 0 · 앞 인계서 {rel}"


def main(argv):
    if len(argv) != 4 or argv[2] != "--root":
        print("REJECT 앞 인계서 판정 불가 쓰기: ft-carry-check.py <새 인계서> --root <ROOT>")
        return 1
    rc, line = judge(argv[1], argv[3])
    print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
