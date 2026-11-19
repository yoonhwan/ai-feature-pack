"""r2306 — ft-seat-status list 좌석별 초(K3 · stderr SLOW-SEAT) + 끊김 흔적(K4 · FT_SEAT_STATUS_TRACE START·END).

입력은 전부 가짜다: 가짜 tmux(PATH · list-sessions = 좌석 목록) · 가짜 ft_seat_pi.py(--row 1줄 · 지정 좌석만 대역 지연 5.2초)
· tmp 명부 · 사본 bin. 기준판 = FIX 를 거꾸로 되돌린 사본(④ ⑤ Red) · 변이 M3·M4 = 사본에서만 + 원본 대조.
느린 좌석 = 대역 지연 7초 안(카드 «시험 입력») · 실 tmux · 실 좌석 · 네트워크 0.
"""
import json
import os
import re
import shutil
import signal
import subprocess
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
KIT = Path(__file__).resolve().parents[2] / "kit" / "fable-team" / "bin"
SH = "ft-seat-status.sh"
SEATS = ("ft-a-nano-pi#1", "ft-b-nano-pi#2", "ft-c-nano-pi#3")
DELAY = 5.2
TMUX = "#!/bin/sh\n[ \"$1\" = list-sessions ] && printf '%s\\n' $R2306_SEATS && exit 0\nexit 1\n"
PI = r'''import os, sys, time
mode, seat = sys.argv[1], sys.argv[3]
if seat in os.environ.get("R2306_SLOW", "").split(","):
    time.sleep(float(os.environ["R2306_DELAY"]))
print("IDLE\t42" if mode == "--row" else "IDLE")
'''
LIST_LOOP = "    for s in $(seats \"${ARG:-^ft-}\"); do row_of \"$s\"; done | emit ;;"
FIX = [("swap", "    list_rows | emit ;;", LIST_LOOP),   # (swap, 고친 글자, 기준판 글자) · (cut, 머리, 끝(포함), 기준판 글자)
       ("cut", "# r2306 K3·K4", "  return 0\n}\n\n", "")]
MUT = {"M3": [("    row_of \"$s\"\n    dt=$((SECONDS - t0))\n", "    dt=$((SECONDS - t0))\n"),   # START 줄을 좌석 끝에서 씀
              ("    [ -n \"$trace\" ] && printf '%s\\tSTART\\t%s\\n' \"${EPOCHSECONDS:-$(date +%s)}\" \"$s\" >> \"$trace\"\n",
               "    row_of \"$s\"\n    [ -n \"$trace\" ] && printf '%s\\tSTART\\t%s\\n' \"${EPOCHSECONDS:-$(date +%s)}\" \"$s\" >> \"$trace\"\n")],
       "M4": [("NR - 5 }' >&2\n", "NR - 5 }'\n")]}   # SLOW-SEAT 를 stdout 으로


def revert(text):
    for rule in FIX:
        if rule[0] == "swap":
            assert text.count(rule[1]) == 1, rule[1]
            text = text.replace(rule[1], rule[2])
            continue
        _, head, end, back = rule
        assert text.count(head) == 1, head
        i = text.index(head)
        j = text.index(end, i) + len(end)
        text = text[:i] + back + text[j:]
    return text


def world(tmp: Path, base=False, mut=None, slow=(), **extra):
    bin_ = tmp / "bin"
    shutil.copytree(BIN, bin_)
    text = (bin_ / SH).read_text(encoding="utf-8")
    text = revert(text) if base else text
    for old, new in (mut or []):
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    (bin_ / SH).write_text(text, encoding="utf-8")
    (bin_ / "ft_seat_pi.py").write_text(PI, encoding="utf-8")
    for d in ("home", "fake", "a/.fable-team"):
        (tmp / d).mkdir(parents=True)
    (tmp / "a/.fable-team/seats.json").write_text(json.dumps({s: {"agent": "pi", "role": "nano"} for s in SEATS}), encoding="utf-8")
    (tmp / "fake/tmux").write_text(TMUX, encoding="utf-8")
    (tmp / "fake/tmux").chmod(0o755)
    env = {k: v for k, v in os.environ.items() if k != "FT_SEAT_STATUS_TRACE"}
    env = {**env, "PATH": f"{tmp / 'fake'}{os.pathsep}{os.environ['PATH']}", "HOME": str(tmp / "home"),
           "FT_ROOTS_TSV": str(tmp / "none.tsv"), "FT_SEATS_JSON": str(tmp / "a/.fable-team/seats.json"),
           "R2306_SEATS": " ".join(SEATS), "R2306_SLOW": ",".join(slow), "R2306_DELAY": str(DELAY), **extra}
    return bin_, env


def run(tmp: Path, cap=60.0, **kw):
    """list 1회 · cap 초 넘으면 프로세스 묶음 kill(scan.sh 의 timeout 끊김 흉내) → (rc, stdout, stderr)."""
    bin_, env = world(tmp, **kw)
    proc = subprocess.Popen(["bash", str(bin_ / SH), "list"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    try:
        out, err = proc.communicate(timeout=cap)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, err = proc.communicate()
        return 124, out, err
    return proc.returncode, out, err


def slow_lines(err):
    return [x for x in err.splitlines() if x.startswith("SLOW-SEAT")]


def c4(tmp, **kw):   # ④ ft-b 5.2초 → stderr SLOW-SEAT 1줄 · stdout = 기준판과 같은 바이트(기준판 = SLOW-SEAT 0 = Red)
    rc, out, err = run(tmp / "f", slow=(SEATS[1],), **kw)
    _, want, _ = run(tmp / "b", base=True)   # 기준판 stdout(지연 0 · 행 글자는 지연과 무관)
    got = slow_lines(err)
    assert rc == 0 and len(got) == 1 and re.fullmatch(r"SLOW-SEAT ft-b-nano-pi#2 s=[567] agent=pi", got[0]), err
    assert out == want and out.count("\n") == 3, (out, want)


def c5(tmp, **kw):   # ⑤ 추적 · 두 번째 좌석에서 끊김 → 파일 끝 줄 = 그 좌석 START · 그 좌석 END 0(기준판 = 파일 0 = Red)
    trace = tmp / "trace.tsv"
    rc, _, _ = run(tmp / "f", cap=2.0, slow=(SEATS[1],), FT_SEAT_STATUS_TRACE=str(trace), **kw)
    rows = [x.split("\t") for x in trace.read_text(encoding="utf-8").splitlines()] if trace.exists() else []
    assert rc == 124 and [r[1:3] for r in rows] == [["START", SEATS[0]], ["END", SEATS[0]], ["START", SEATS[1]]], rows
    assert all(r[0].isdigit() for r in rows) and rows[1][3].isdigit(), rows


def c6(tmp, **kw):   # ⑥ env 없음 · 모든 좌석 5초 미만 → 추적 파일 0 · stderr·stdout = 기준판과 같음
    rc, out, err = run(tmp / "f", **kw)
    brc, bout, berr = run(tmp / "b", base=True)
    assert (rc, out, err) == (brc, bout, berr) and not slow_lines(err), (err, berr)
    assert not [p for p in tmp.rglob("*") if p.is_file() and "trace" in p.name]


CASES = {"④": c4, "⑤": c5, "⑥": c6}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path)


@pytest.mark.parametrize("name", ("④", "⑤"))
def test_base_red(name, tmp_path):
    with pytest.raises(AssertionError):
        CASES[name](tmp_path, base=True)


def test_trace_full_run(tmp_path):   # K4 끊김 없음 = 좌석마다 START·END 짝 · stdout 은 env 없을 때와 같음
    trace = tmp_path / "trace.tsv"
    _, out, _ = run(tmp_path / "f", FT_SEAT_STATUS_TRACE=str(trace))
    _, plain, _ = run(tmp_path / "p")
    rows = [x.split("\t")[1:3] for x in trace.read_text(encoding="utf-8").splitlines()]
    assert rows == [[k, s] for s in SEATS for k in ("START", "END")] and out == plain, rows


def test_base_is_origin_text(tmp_path):
    bin_, _ = world(tmp_path, base=True)
    assert "r2306" not in (bin_ / SH).read_text(encoding="utf-8")


@pytest.mark.parametrize("name, kills", [("M3", "⑤"), ("M4", "④")])
def test_mutant(name, kills, tmp_path):
    with pytest.raises(AssertionError):
        CASES[kills](tmp_path / "m", mut=MUT[name])
    CASES[kills](tmp_path / "o")   # 원본 = 같은 사례 통과(반대 결과 대조)


def test_bin_equals_kit():
    assert (BIN / SH).read_bytes() == (KIT / SH).read_bytes()
