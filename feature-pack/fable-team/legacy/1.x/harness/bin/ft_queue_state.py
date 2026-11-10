#!/usr/bin/env python3
"""ft_queue_state.py — 오빠 큐 상태 칸 판정기 (r528 · 어휘 정본 = 같은 폴더 queue-states.tsv)

  ft_queue_state.py parse <큐.md>   행마다 JSON {line, cells(머리 이름별), state, stop, extra, recheck, error}
  ft_queue_state.py lint <큐.md>    어휘 밖 줄마다 «ERR <줄> <사유> :: <칸>» · 끝줄 «QUEUE-STATE ERR=<n> OK=<m>» · rc 0/1
상태 칸 = 머리 이름 «상태» 또는 옛 «처리됨»(같은 칸 · 이름 바꾸기 0). 읽기만 — 큐를 고쳐 쓰지 않는다.
읽기 실패(큐·어휘 파일) = stderr ERROR + rc 2 (조용한 0 금지).
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

VOCAB = Path(__file__).with_name("queue-states.tsv")
STATE_COLS = ("상태", "처리됨")
RECHECK = re.compile(r"재확인 (\d{4}-\d{2}-\d{2} \d{2}:\d{2})")


class ReadError(Exception):
    pass


def load_vocab(path=VOCAB):
    """{상태 이름: 덧말 규칙} · {정지 이름: (붙는 상태 집합, 덧말 규칙)}"""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        raise ReadError(f"어휘 정본 읽기 실패: {path}: {e}")
    states, stops = {}, {}
    for ln in lines:
        if not ln.strip() or ln.startswith("#"):
            continue
        kind, name, on, rule, _ = ln.split("\t", 4)
        if kind == "상태":
            states[name] = rule
        elif kind == "정지":
            stops[name] = (set(on.split(",")), rule)
    if not states or not stops:
        raise ReadError(f"어휘 정본에 상태·정지 행이 없다: {path}")
    return states, stops


def recheck_of(extra):
    m = RECHECK.search(extra)
    if not m:
        return None
    try:
        datetime.strptime(m.group(1), "%Y-%m-%d %H:%M")
    except ValueError:
        return None
    return m.group(1)


def rule_error(rule, extra):
    """덧말 규칙 위반 사유 — 맞으면 None"""
    if rule == "글" and not extra:
        return "덧말(누가·단계) 없음"
    if rule == "번호" and not re.search(r"\d+", extra):
        return "덧말에 hold 번호 없음"
    if rule == "판정" and not re.search(r"판정 \d+|(^|[^0-9A-Za-z])[0-9a-f]{7,40}([^0-9A-Za-z]|$)", extra):
        return "덧말에 «판정 <번호>»·착지 sha 없음"
    if rule == "재확인":
        if recheck_of(extra) is None:
            return "보류에 «재확인 YYYY-MM-DD HH:MM» 없음"
        if not RECHECK.sub("", extra).strip(" ·"):
            return "보류 사유 없음"
    return None


def judge(cell, vocab):
    """칸 글 → (상태, 정지, 덧말, 오류)"""
    states, stops = vocab
    head, _, extra = cell.partition(" — ")
    extra = extra.strip()
    words = [w.strip() for w in head.split("·")]
    state, stop = words[0], (words[1] if len(words) > 1 else None)
    if not cell.strip():
        return None, None, extra, "빈 칸"
    if state not in states:
        return None, None, extra, "어휘 밖 상태(대기·진행·보류·완료 중 하나)"
    if len(words) > 2:
        return state, None, extra, "정지 종류는 하나만"
    if stop is not None:
        if stop not in stops:
            return state, None, extra, "어휘 밖 정지 종류(일시정지·구현중정지·대기중정지 중 하나)"
        on, rule = stops[stop]
        if state not in on:
            return state, stop, extra, f"{stop} 은 {'·'.join(sorted(on))} 에만 붙는다"
    else:
        rule = states[state]
    return state, stop, extra, rule_error(rule, extra)


def table(path):
    """[(줄 번호, 칸 목록)] — 머리 1행 + 자료 행(구분 행 제외)"""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as e:
        raise ReadError(f"큐 읽기 실패: {path}: {e}")
    rows = []
    for n, ln in enumerate(text.splitlines(), 1):
        if not ln.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-+:?", c) for c in cells):
            continue
        rows.append((n, cells))
    if not rows:
        raise ReadError(f"큐에 표가 없다: {path}")
    return rows


def parse(path, vocab):
    """머리 오류면 ([], (줄, 사유)) · 아니면 (행 목록, None)"""
    rows = table(path)
    (hn, head), data = rows[0], rows[1:]
    col = next((c for c in STATE_COLS if c in head), None)
    if col is None:
        return [], (hn, f"머리에 상태 칸(상태·처리됨) 없음: {head}")
    i = head.index(col)
    out = []
    for n, cells in data:
        rec = {"line": n, "cells": dict(zip(head, cells)), "state": None, "stop": None, "extra": "", "recheck": None}
        if len(cells) <= i:
            rec["error"] = "상태 칸보다 짧은 행"
        else:
            rec["state"], rec["stop"], rec["extra"], rec["error"] = judge(cells[i], vocab)
            rec["recheck"] = recheck_of(rec["extra"]) if rec["state"] == "보류" else None
        out.append(rec)
    return out, None


def main(argv):
    if len(argv) != 3 or argv[1] not in ("parse", "lint"):
        print("usage: ft_queue_state.py parse|lint <큐.md>", file=sys.stderr)
        return 2
    try:
        rows, head_err = parse(argv[2], load_vocab())
    except ReadError as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 2
    if argv[1] == "parse":
        print(json.dumps(rows, ensure_ascii=False))
        return 0 if head_err is None else 1
    bad = [r for r in rows if r["error"]]
    if head_err:
        print(f"ERR {head_err[0]} {head_err[1]} :: ")
    for r in bad:
        cell = next((r["cells"][c] for c in STATE_COLS if c in r["cells"]), "")
        print(f"ERR {r['line']} {r['error']} :: {cell}")
    n_err = len(bad) + (1 if head_err else 0)
    print(f"QUEUE-STATE ERR={n_err} OK={len(rows) - len(bad)}")
    return 1 if n_err else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
