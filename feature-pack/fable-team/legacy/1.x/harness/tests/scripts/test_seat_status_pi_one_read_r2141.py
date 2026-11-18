"""r2141 — ft-seat-status pi 행 = 상태와 분을 jsonl 한 번 읽기에서 함께 낸다.

입력은 전부 가짜다: 가짜 tmux(FT_TMUX) · 합성 pi 세션(FT_PI_SESSIONS) · tmp 명부 · 사본 bin.
사본 bin 의 ft_seat_pi.py 는 감싸개다: 진짜 어댑터를 돌리고, 첫 호출 뒤 jsonl 에 1줄을 덧붙이고(①②),
audit hook 으로 jsonl 열기를 «결속 탐색(locate)» 과 «상태 판독» 으로 나눠 센다(④).
R2141_BIN 으로 대상 bin 을 바꾼다(기준판 · 변이 사본). 실 tmux · 실 좌석 0 · sleep 0.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

BIN = Path(os.environ.get("R2141_BIN") or Path(__file__).resolve().parents[2] / "bin")
KIT = Path(__file__).resolve().parents[2] / "kit" / "fable-team" / "bin"
SEAT = "t-harness-master-pi#9"
TS = "2026-11-17T01:34:50Z"
STOP = {"type": "message", "timestamp": TS, "message": {"role": "assistant", "stopReason": "stop"}}
TOOL = {"type": "message", "timestamp": TS, "message": {"role": "assistant", "stopReason": "toolUse"}}
RATE = {"type": "message", "timestamp": TS, "message": {"role": "assistant", "stopReason": "error",
                                                        "errorMessage": "429 rate_limit_error"}}
TMUX = r"""#!/bin/sh
[ "$1" = -u ] && shift
case "$1" in
  list-sessions) echo "$R2141_SEAT";;
  list-panes) [ -n "$R2141_NOPANE" ] && exit 0
    case "$*" in
      *pane_pid*) printf '%s\t%s\t%s\t0\n' "$R2141_SEAT" "$R2141_PID" "$R2141_CWD";;
      *) printf '%s|%%1\n' "$R2141_SEAT";;
    esac;;
  show-environment) echo "TMUXC_PI_SESSION_ID=sid-r2141";;
  *) exit 1;;
esac
"""
WRAP = r'''import os, runpy, sys
HERE = os.path.dirname(os.path.abspath(__file__))
JSONL, LOG = os.environ["R2141_JSONL"], os.environ["R2141_LOG"]
OLD = ("--pane", "--age", "--path", "--if-pi", "--if-file")
mode = sys.argv[1] if len(sys.argv) > 1 else ""
count = {"state": 0, "bind": 0}
def hook(event, args):
    if event != "open" or not isinstance(args[0], (str, os.PathLike)):
        return
    if os.path.realpath(os.fspath(args[0])) != os.path.realpath(JSONL):
        return
    f, names = sys._getframe(1), set()
    while f:
        names.add(f.f_code.co_name)
        f = f.f_back
    count["bind" if names & {"locate", "first_session", "candidates"} else "state"] += 1
first = not os.path.exists(LOG) or not open(LOG).read()
rc = 0
if os.environ.get("R2141_FAIL_NEW") and mode.startswith("--") and mode not in OLD:
    rc = 1
else:
    sys.addaudithook(hook)
    sys.argv[0] = os.path.join(HERE, "ft_seat_pi_real.py")
    try:
        runpy.run_path(sys.argv[0], run_name="__main__")
    except SystemExit as e:
        rc = e.code or 0
with open(LOG, "a") as log:
    log.write("%s\t%d\t%d\n" % (mode, count["state"], count["bind"]))
if first and os.environ.get("R2141_APPEND"):
    with open(JSONL, "a") as out:
        out.write(os.environ["R2141_APPEND"] + "\n")
sys.exit(rc)
'''


def world(tmp: Path, start: dict, append: dict = None, **extra) -> tuple:
    bin_ = tmp / "bin"
    shutil.copytree(BIN, bin_)
    shutil.move(bin_ / "ft_seat_pi.py", bin_ / "ft_seat_pi_real.py")
    (bin_ / "ft_seat_pi.py").write_text(WRAP, encoding="utf-8")
    for d in ("cwd", "home", "fake", "sessions/enc", "a/.fable-team"):
        (tmp / d).mkdir(parents=True)
    (tmp / "a/.fable-team/seats.json").write_text(json.dumps({SEAT: {"agent": "pi", "role": "master"}}), encoding="utf-8")
    jsonl = tmp / "sessions/enc/0.jsonl"
    rows = [{"type": "session", "id": "sid-r2141", "cwd": str(tmp / "cwd")}, {"type": "session_info", "name": SEAT}, start]
    jsonl.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    tmux = tmp / "fake/tmux"
    tmux.write_text(TMUX, encoding="utf-8")
    tmux.chmod(0o755)
    env = {**os.environ, "PATH": f"{tmp / 'fake'}{os.pathsep}{os.environ['PATH']}", "HOME": str(tmp / "home"),
           "FT_TMUX": str(tmux), "FT_PI_SESSIONS": str(tmp / "sessions"), "FT_ROOTS_TSV": str(tmp / "none.tsv"),
           "FT_SEATS_JSON": str(tmp / "a/.fable-team/seats.json"), "R2141_SEAT": SEAT, "R2141_PID": str(os.getpid()),
           "R2141_CWD": str(tmp / "cwd"), "R2141_JSONL": str(jsonl), "R2141_LOG": str(tmp / "calls.log"), **extra}
    if append:
        env["R2141_APPEND"] = json.dumps(append)
    return bin_, env


def one(tmp: Path, start: dict, append: dict = None, **extra) -> list:
    bin_, env = world(tmp, start, append, **extra)
    out = subprocess.run(["bash", str(bin_ / "ft-seat-status.sh"), "one", SEAT], env=env, text=True, capture_output=True, timeout=60)
    assert out.returncode == 0, out.stderr
    return out.stdout.split()[1:3]


def calls(tmp: Path) -> list:
    return [ln.split("\t") for ln in (tmp / "calls.log").read_text().splitlines()]


def test_1_idle_then_new_turn_is_never_idle_dash(tmp_path):  # ① P1 · 기준판 Red
    state, age = one(tmp_path, STOP, TOOL)
    assert (state, age) != ("IDLE", "-")
    assert (state == "IDLE" and age.isdigit()) or (state, age) == ("BUSY", "-")


def test_2_working_then_stop_is_one_snapshot(tmp_path):  # ② P1
    state, age = one(tmp_path, TOOL, STOP)
    assert (state == "IDLE" and age.isdigit()) or (state, age) == ("BUSY", "-")


def test_3_no_append_rows_unchanged(tmp_path):  # ③ P1 · P3 — 기준판과 같은 값
    state, age = one(tmp_path / "idle", STOP)
    assert state == "IDLE" and age.isdigit()
    assert one(tmp_path / "work", TOOL) == ["BUSY", "-"]
    assert one(tmp_path / "rate", RATE) == ["RATELIMITED", "-"]


def test_4_state_read_opens_once_per_row(tmp_path):  # ④ P1 · 기준판 Red(상태 판독 2 · 전체 4)
    one(tmp_path, STOP)
    rows = calls(tmp_path)
    assert sum(int(r[1]) for r in rows) == 1, rows
    assert sum(int(r[2]) for r in rows) >= 1, rows  # 결속 탐색은 줄이지 않는다


def test_5_no_pane_is_unknown_dash(tmp_path):  # ⑤ P2
    assert one(tmp_path, STOP, R2141_NOPANE="1") == ["UNKNOWN", "-"]


def test_5b_failed_one_read_is_not_filled_by_old_pane(tmp_path):  # ⑤b P2 · M2 검출 칸
    assert one(tmp_path, STOP, R2141_FAIL_NEW="1") == ["UNKNOWN", "-"]


def test_bin_equals_kit():
    for name in ("ft_seat_pi.py", "ft-seat-status.sh"):
        assert (BIN / name).read_bytes() == (KIT / name).read_bytes(), name
