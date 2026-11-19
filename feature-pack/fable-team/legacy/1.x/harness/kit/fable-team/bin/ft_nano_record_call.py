#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_call.py — r2316 R3 이 실행의 외부 호출 셈(이름·초) + 도구 실행 한 곳(run). ft_nano_record 가 run·ENV 를 그대로 다시 내보낸다(부르는 곳 글자 불변 · 200줄 상한).
이름 = git <동사> · bash 는 부른 함수 이름(예 ft_card_ref) · 그 밖 = 실행 파일 이름.
초 = clock() 차이 — Budget(elapsed)과 같은 시계 · FT_LAND_RECORD_CLOCK 주입 = 그 파일의 숫자(없거나 못 읽으면 0).
CALLS = 마지막 200회 · slow(n) = 초 큰 n개 «이름:초,…»(Budget 표식 «느린=» 칸) · timed(cmd) = with 안의 호출 1회를 센다."""
from __future__ import annotations

import os
import re
import subprocess
import time
from pathlib import Path

ENV = {**os.environ, "LC_ALL": "C"}
CALLS = []


def clock():   # 실행 시계(초) — 주입 파일이 있으면 그 값 그대로(절대초)
    p = os.environ.get("FT_LAND_RECORD_CLOCK")
    if not p:
        return time.monotonic()
    try:
        return float(Path(p).read_text(encoding="utf-8").strip())
    except (OSError, ValueError, UnicodeDecodeError):
        return 0.0


def name(cmd):   # 이름 = git <동사>(«-C»·«-c» 의 값은 건너뜀) · bash -c = 부른 함수 이름 · 그 밖 = 실행 파일 이름
    c = [str(x) for x in cmd] or [""]
    exe = Path(c[0]).name
    if exe == "git":
        skip = False
        for a in c[1:]:
            if skip:
                skip = False
            elif a in ("-C", "-c"):
                skip = True
            elif not a.startswith("-"):
                return f"git {Path(a).name}"
        return "git -"
    if exe in ("bash", "sh", "zsh"):
        if "-c" in c:
            m = re.search(r"(?:&&|\|\||;)\s*([A-Za-z_][\w.-]*)", c[c.index("-c") + 1] if c.index("-c") + 1 < len(c) else "")
            return m.group(1) if m else exe
        if len(c) > 1:
            return Path(c[1]).name
    return exe


class timed:   # r2316 R3 — with 안의 외부 호출 1회를 (이름·초)로 남긴다(return·예외 어느 쪽이든)
    def __init__(self, cmd):
        self.cmd, self.t0 = cmd, clock()

    def __enter__(self):
        return self

    def __exit__(self, *_e):
        CALLS.append((name(self.cmd), clock() - self.t0))
        del CALLS[:-200]   # 오래 사는 프로세스에서도 셈 = 마지막 200회
        return False


def slow(n=3):   # 초 큰 n개 → «이름:초,…» (없으면 «-»)
    top = sorted(CALLS, key=lambda c: -c[1])[:n]
    return ",".join(f"{nm}:{round(sec, 3):g}" for nm, sec in top) or "-"


def run(cmd, cap=7.0, env=None, inp=None, raw=False):   # → (rc|None, stdout, stderr) · 시간 초과·실행 불가 = rc None · r2316: 호출마다 (이름·초) 셈
    with timed(cmd):
        try:
            p = subprocess.run(cmd, capture_output=True, input=inp, timeout=max(0.5, cap), env=env or ENV)
        except subprocess.TimeoutExpired:
            return None, b"" if raw else "", "시간 초과"
        except OSError as e:
            return None, b"" if raw else "", str(e)
        return p.returncode, p.stdout if raw else p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
