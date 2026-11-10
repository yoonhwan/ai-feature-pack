#!/usr/bin/env python3
"""ft_secret_followup — r1002 점검 표의 «실값» 행 256건(46파일)을 값 0 으로 셋 답한다 (r1027 · 읽기 전용).
ⓐ 시각: 행 줄의 `timestamp`(없으면 파일 mtime) → byz-keys 원장 «교체 …날짜» 전/뒤/같은날 · 뒤인 행은 그 줄을 낸 도구·첫 명령 이름만(앞붙은 «이름=값» 대입문은 건너뛴다).
ⓑ 지문: 값을 r1002 가림 함수가 찾은 자리에서만 읽어 sha256 앞 8자 → 1Password 볼트 전부 + GCP SM 전부의 값도 같은 방식 · 같은 줄 값마다 따로 대조 · 출력은 «키 이름 · 살아 있음(일치)/옛 키(일치 0) + 줄 수»(값·해시 글자 0).
ⓒ 삭제 계획: 실값 파일 경로 + «살아 있는 세션의 기록인가»(tmux pane cwd ↔ 기록 폴더 · 최근 10분 쓰기) → «다음 닫힘 뒤» · 머리 줄 «되돌림 없음» · 삭제 명령은 글자로만(실행 0).
교체 시각을 못 찾거나 출처를 못 읽으면 «판정 불가/대조 못 한 곳» 1줄로 끝낸다(조용한 0 아님).
사용: (uv run --with onepassword-sdk --no-project) ft_secret_followup.py --triage MD --keys-log PATH[,PATH] [--report MD] [--plan MD] · rc: 0 · 2 usage · 4 쓰기 실패 · 볼트는 SDK 전용(op CLI 금지 · 없으면 «판정 불가» 1줄).
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_secret_followup_plan import BACK, FRONT, SAME, UNK, live_files, sources, texts  # noqa: E402  출처·세션·글(200줄 한도로 나눈 짝)
from ft_secret_shapes import NAMED, RULES, _is_placeholder  # noqa: E402  r1002 가림 함수 재사용 — 값은 여기서만 만진다
from ft_secret_targets import NAME  # noqa: E402  비밀 «이름» 판정 한 벌 재사용

USAGE = "usage: ft_secret_followup.py --triage MD --keys-log PATH[,PATH] [--report MD] [--plan MD]"
ROW = re.compile(r"^\|\s*(?P<path>/[^|]+?)\s*\|\s*(?P<no>\d+)\s*\|\s*(?P<kind>[^|]+?)\s*\|\s*(?P<v>실값|이름만|예시·가짜|판정 불가)\s*\|\s*$")
ROT = re.compile(r"교체[^\n]{0,40}?(20\d\d-\d\d-\d\d)(?:[ T](\d\d:\d\d:\d\d))?")
TS = re.compile(r"(\d{4}-\d\d-\d\d)(?:[T ](\d\d:\d\d:\d\d))?")
BUDGET, CAP = 7.0, 70.0  # 행/파일 7초 · 전체 70초


class _Timeout(Exception):
    pass

def _fire(_sig: int, _frm: object) -> None:
    raise _Timeout()

def _sha(val: str) -> str:  # 지문 — 비교만 하고 출력하지 않는다
    return hashlib.sha256(val.encode("utf-8", "replace")).hexdigest()[:8]

def rows_of(text: str) -> list[dict[str, str]]:  # 점검 표의 «실값» 행만 — 값 칸은 읽지 않는다
    return [{"path": m["path"], "line": m["no"], "kind": m["kind"]}
            for m in (ROW.match(ln) for ln in text.splitlines()) if m and m["v"] == "실값"]

def rot_at(paths: list[str]) -> tuple[str, str]:  # («마지막 교체 시각», 사유)
    best = ""
    for p in paths:
        try:
            with open(os.path.expanduser(p), errors="replace") as f:
                best = max([best] + [m.group(1) + (" " + m.group(2) if m.group(2) else "") for m in ROT.finditer(f.read())])
        except OSError:
            continue
    return (best, "") if best else ("", "판정 불가 — 교체 시각 없음")

def age(ts: str, rot: str) -> str:
    m = TS.search(ts or "")
    if not m:
        return UNK
    if m.group(1) != rot[:10]:
        return FRONT if m.group(1) < rot[:10] else BACK
    if not (m.group(2) and len(rot) > 10):
        return SAME  # 같은 날은 시각까지 있어야 가른다
    return BACK if m.group(2) >= rot[11:] else FRONT

def values_of(line: str) -> list[str]:  # 가림 함수가 찾은 자리에서만 값을 꺼낸다
    out = [m["val"] for _k, rx in RULES for m in rx.finditer(line) if not _is_placeholder(m["val"])]
    return out + [m["val"] for m in NAMED.finditer(line) if NAME.search(m["name"]) and not _is_placeholder(m["val"])]

def tool_of(line: str) -> str:  # 그 줄을 낸 도구 이름 · 첫 명령 이름만(값·경로 0) — 대입문은 건너뛴다
    def word(cmd: object) -> str:  # 파일 도구는 경로를 쓰지 않는다(위치는 «파일:줄» 칸이 이미 있다)
        w = str(cmd).split() if isinstance(cmd, str) else []
        for i, x in enumerate(w):
            if i < len(w) - 1 and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", x):
                continue  # 대입문(API_TOKEN=값 …) — 값이 출력에 새지 않게 건너뛴다
            return x if re.fullmatch(r"[A-Za-z][\w.-]*", x) else "명령 이름 판정 불가"
        return ""

    def walk(v: object, found: list[str]) -> None:
        if isinstance(v, dict):
            if isinstance(v.get("name"), str) and isinstance(v.get("input"), dict):
                w = word(v["input"].get("command") or "")
                found.append(v["name"] + "()" + (" " + w if w else ""))
            for x in v.values():
                walk(x, found)
        elif isinstance(v, list):
            for x in v:
                walk(x, found)

    found: list[str] = []
    try:
        rec = json.loads(line)
    except ValueError:
        return "기록 아님"
    walk(rec, found)
    kind = rec.get("type") if isinstance(rec.get("type"), str) else "?"
    return f"{kind} · {found[0]}" if found else f"type={kind}"

def read_lines(path: str, nos: list[int], budget: float) -> dict[int, str]:
    want, got = set(nos), {}
    signal.setitimer(signal.ITIMER_REAL, budget)
    try:
        with open(path, errors="replace") as f:
            for i, ln in enumerate(f, 1):
                if i in want:
                    got[i] = ln
                    if len(got) == len(want):
                        break
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    return got

def collect(rows: list[dict[str, str]], keys: list[tuple[str, str, list[str]]], total: float) -> None:  # 파일 하나 = 한 번만 통과
    start = time.monotonic()
    for path in dict.fromkeys(r["path"] for r in rows):
        mine = [r for r in rows if r["path"] == path]
        left, got, why = total - (time.monotonic() - start), {}, ""
        if left <= 0:
            why = "전체 상한 초과"
        else:
            try:
                got = read_lines(path, [int(r["line"]) for r in mine], min(BUDGET, left))
            except _Timeout:
                why = "파일 7초 초과"
            except OSError as e:
                why = {"FileNotFoundError": "파일 없음", "PermissionError": "읽기 권한 없음"}.get(e.__class__.__name__, "읽기 실패")
        for r in mine:
            ln, r["tool"], r["ts"], r["hits"] = got.get(int(r["line"])), "", "", []
            if ln is None:
                r["why"] = why or "줄 번호가 파일 길이 넘음"
                continue
            try:
                ts = json.loads(ln).get("timestamp")
            except ValueError:
                ts = ""
            if isinstance(ts, str) and ts:
                r["ts"] = ts + " (줄 시각)"
            else:  # 줄 시각 없음 → 파일 mtime
                try:
                    r["ts"] = time.strftime("%F %T", time.localtime(os.path.getmtime(path))) + " (mtime)"
                except OSError:
                    r["ts"] = "줄 시각 없음"
            r["tool"] = tool_of(ln)
            vals = values_of(ln)  # 값은 여기 변수에만 — 아래 지문 비교 밖으로 나가지 않는다
            r["hits"] = sorted({u for u, _d, lvs in keys for v in vals if any(_sha(v) == _sha(lv) for lv in lvs)})

def main(argv: list[str]) -> int:
    triage, keys_log, outs = "", [], {"--report": "", "--plan": ""}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--triage", "--keys-log", "--report", "--plan") and i + 1 < len(argv):
            if a == "--triage":
                triage = argv[i + 1]
            elif a == "--keys-log":
                keys_log += argv[i + 1].split(",")
            else:
                outs[a] = argv[i + 1]
            i += 2
            continue
        print(USAGE, file=sys.stderr)
        return 2
    if not triage or not keys_log:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        with open(os.path.expanduser(triage), errors="replace") as f:
            rows = rows_of(f.read())
    except OSError as e:
        print(f"ERROR ft-secret-followup: 점검 표 못 읽음 ({e.__class__.__name__})", file=sys.stderr)
        return 2
    keys, miss = sources()  # 살아 있는 키(이름 → 값들) + 대조 못 한 곳 — 값은 지문 비교에만
    signal.signal(signal.SIGALRM, _fire)
    collect(rows, keys, min(BUDGET + BUDGET * len(rows), CAP))
    rot, rot_why = rot_at(keys_log)
    for r in rows:
        r["age"] = age(r["ts"], rot) if rot else UNK
    live = live_files([r["path"] for r in rows])
    rep, pln = texts(rows, rot, rot_why, keys, miss, live)
    for path, text in ((outs["--report"], rep), (outs["--plan"], pln)):
        if not path:
            continue
        try:
            os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            with open(path, "w") as f:
                f.write(text)
        except OSError as e:
            print(f"ERROR ft-secret-followup: 파일 쓰기 실패 ({path} · {e.__class__.__name__})", file=sys.stderr)
            return 4
    c = {k: sum(1 for r in rows if r["age"] == k) for k in (FRONT, BACK, SAME, UNK)}
    files = list(dict.fromkeys(r["path"] for r in rows))
    print(f"followup={len(rows)} front={c[FRONT]} back={c[BACK]} same={c[SAME]} unknown={c[UNK]} "
          f"live_keys={len({n for r in rows for n in r['hits']})} keys={len(keys)} missed={len(miss)} files={len(files)} "
          f"live_files={sum(1 for f in files if live.get(f, '').startswith('살아'))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
