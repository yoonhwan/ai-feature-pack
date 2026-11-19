#!/usr/bin/env python3
"""ft-carry-check.py — r2229 승계 인계서 열린 칸 대조(ft-successor-open.sh ⓐ-4 의 판정 1곳).

쓰기: ft-carry-check.py <새 인계서> --root <ROOT>
  새 인계서의 «앞 인계서: <경로>» 1줄(상대경로 = ROOT 기준) → 앞 판 «## 열린 칸» 절의 칸(줄)마다
  그 줄의 키 하나라도 ① 새 판 «## 열린 칸» 절에 다시 나오거나(이월) ② 새 판 어디든 «닫음: <키…> — <근거 ≥10자>»
  ③ 새 판 어디든 «<…키…>: 이월» 줄에 있으면 통과. 키 없는 칸 = 대조 밖.
rc0 = 통과(OK 1줄) · 줄 없음(WARN 1줄 · 옛 꼴) · rc1 = REJECT 1줄(말없이 사라짐 · 앞 인계서 판정 불가)
자동 길 WARN 낮춤(FT_CARRY_WARN_ONLY)은 부르는 쪽(ft-successor-open.sh) 몫이다.

--d2-carry (r2234 · planner master · desk 승계만 · 부르는 쪽이 넘김):
  «앞 인계서:» 없음 · «새 인계서: <경로>» 없음 · 못 읽음 = REJECT · 앞 판 «## 열린 칸» 절 없음 = WARN 대조 0칸 진행
  본문 + 새 인계서에서 오빠 질문 줄(«이월» 줄 · «오빠 답» 절 표 행 · 목록 줄)의 키 자리 Slack ts 는 줄마다 1개(O3)
  + 키 자리 뒤 «D2 1번|2번|3번|off — <왜 사람 ≥10자>»(O4) · «닫음: <ts> — <근거>» 가 있는 ts 는 건너뜀(O5)
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
TS = re.compile(r"(?<![\d.])\d{10}\.\d{6}(?!\d)")
NEWF = re.compile(r"^새 인계서:\s*(\S.*?)\s*$", re.M)
D2 = re.compile(r"D2 (?:[123]번|off)\s*[—-]\s*([^|)\n]*)")
HEAD = re.compile(r"^#+ ")


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


def d2_targets(text):  # O2 오빠 질문 줄 → (키 자리, 그 뒤) · 닫음 줄(O5) 제외 · 키 자리에 ts 있는 줄만
    out, ask = [], False
    for line in text.split("\n"):
        if HEAD.match(line):
            ask = "오빠 답" in line
        elif CLOSE.search(line):
            continue
        elif ask and line.startswith("|") and not TABLE_SEP.match(line.strip()):
            c = line.strip().strip("|").split("|")
            out.append((c[0], "|".join(c[1:])))
        elif ask and CELL.match(line):
            j = min([k for k in (line.find(":"), line.find("|")) if k >= 0] or [len(line)])
            out.append((line[:j], line[j:]))
        elif "이월" in line:
            i = line.find(": 이월")
            i = line.find("이월") if i < 0 else i
            out.append((line[:i], line[i:]))
    return [(k, r) for k, r in out if TS.search(k)]


def d2_judge(text):  # O3 한 줄 한 키 · O4 분류 칸 · O5 닫은 ts 건너뜀
    done = set()
    for line in text.split("\n"):
        m = CLOSE.search(line)
        if m and len(m.group(2).strip()) >= MIN_WHY:
            done |= set(TS.findall(m.group(1)))
    bad = []
    for key, rest in d2_targets(text):
        ts = TS.findall(key)
        if all(t in done for t in ts):
            continue
        if len(ts) > 1:
            return 1, f"REJECT ts 키는 한 줄에 하나({len(ts)}) — 줄마다 ts 1개 + «D2 n번 — <왜 사람>» · 고른 칸 = «닫음: <ts> — <근거>»"
        m = D2.search(rest)
        if not (m and len(m.group(1).strip()) >= MIN_WHY):
            bad.append(ts[0])
    if bad:
        return 1, f"REJECT D2 재분류 없는 오빠 질문 {len(bad)}({' '.join(bad[:8])}) — 줄마다 «D2 1번|2번|3번|off — <왜 사람 ≥10자>» · 고른 칸 = «닫음: <ts> — <근거>»"
    return 0, ""


def read_rel(rel, root, what):
    rel = rel.strip("`'\"")
    path = rel if os.path.isabs(rel) else os.path.join(root, rel)
    try:
        return rel, path, open(path, encoding="utf-8").read(), ""
    except (OSError, UnicodeDecodeError) as e:
        return rel, path, None, f"REJECT {what} 판정 불가 경로 못 읽음 {path}: {type(e).__name__}"


def judge(body_path, root, d2=False):
    new = open(body_path, encoding="utf-8").read()
    m = PREV.search(new)
    if not m and d2:
        return 1, "REJECT 앞 인계서 줄 없음 — planner master · desk 승계 본문에 «앞 인계서: <경로>» · «새 인계서: <경로>» 2줄"
    if not m:
        return 0, "WARN 앞 인계서 줄 없음 · 열린 칸 대조 0"
    if d2:
        n = NEWF.search(new)
        if not n:
            return 1, "REJECT 새 인계서 줄 없음 — 본문에 «새 인계서: <경로>»(ROOT 기준) 1줄"
        _, _, doc, err = read_rel(n.group(1), root, "새 인계서")
        if err:
            return 1, err
        new = new + "\n" + doc
    rel, path, prev, err = read_rel(m.group(1), root, "앞 인계서")
    if err:
        return 1, err
    if d2:
        rc, line = d2_judge(new)
        if rc:
            return rc, line
    sec = OPEN.search(prev)
    if not sec and d2:
        return 0, f"WARN 열린 칸 절 없음 — 대조 0칸 · 앞 인계서 {rel}"
    if not sec:
        return 1, f"REJECT 앞 인계서 판정 불가 «## 열린 칸» 절 없음 {path}"
    ok = passed_keys(new)
    keyed = [k for k in (keys(c) for c in cells(sec.group(1))) if k]
    miss = [k[0] for k in keyed if not any(x in ok for x in k)]
    if miss:
        return 1, f"REJECT 열린 칸 말없이 사라짐 {len(miss)}({' '.join(miss[:8])}) — 새 «## 열린 칸» 에 키 이월 또는 «닫음: <키> — <근거>» · 앞 인계서 {rel}"
    if d2 and not OPEN.search(new):
        return 0, f"WARN 열린 칸 절 없음(새 인계서) — 대조 칸 {len(keyed)} · 사라짐 0 · 앞 인계서 {rel}"
    return 0, f"OK 열린 칸 대조 칸 {len(keyed)} · 사라짐 0 · 앞 인계서 {rel}"


def main(argv):
    d2 = argv[4:] == ["--d2-carry"]
    if len(argv) != 4 + d2 or argv[2] != "--root":
        print("REJECT 앞 인계서 판정 불가 쓰기: ft-carry-check.py <새 인계서> --root <ROOT> [--d2-carry]")
        return 1
    rc, line = judge(argv[1], argv[3], d2)
    print(line)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
