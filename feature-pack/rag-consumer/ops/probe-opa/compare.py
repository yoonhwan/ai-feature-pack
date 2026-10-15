#!/usr/bin/env python3
"""E1: terminal condition table for ``op --version`` (design arch-20261015-opa-popup-design-r6 §6).

A human runs it once in a terminal. It runs ``op --version`` and nothing else, three conditions x two rounds in the
order A,B,C,A,B,C, every attempt with the 7.0 s rule (one attempt, no retry, never a shorter limit):

  A  the terminal environment minus every name starting with ``OP_`` and every name containing TOKEN, KEY, SECRET,
     PASSWORD, CREDENTIAL or AUTH (names only, case-insensitive; values are never read)
  B  the allow-listed minimal environment of probe.py (values from this terminal)
  C  B with HOME replaced by a fresh private folder (0700) and OP_CONFIG_DIR inside it

It only observes: no token is passed or read, no account command exists, no ``op`` process (shared daemon or
otherwise) is ever signalled — only the direct measurement child of this run is ended, with the reviewed
``probe._end_child`` (kill the direct child, bounded wait, bounded pipe drain). Value-free by construction: per
attempt only the status class, milliseconds, rc and two bools are kept; stdout/stderr and environment values are
dropped. The conclusion is an association label, never a cause.

probe.py (reviewed) is imported unchanged; its reviewed parts are reused.

Exit codes: 0 all six rounds ran, 1 incomplete, 2 refused to start, 130/143/129 interrupted (clean-up runs first).
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import random
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

_SPEC = importlib.util.spec_from_file_location("probe_core", Path(__file__).with_name("probe.py"))
probe = importlib.util.module_from_spec(_SPEC)
sys.modules["probe_core"] = probe
_SPEC.loader.exec_module(probe)  # it reads --mode from sys.argv exactly like the probe itself

SCHEMA_VERSION = 1

# One attempt is the 7.0 s rule; the whole run has a hard limit with a clean-up reserve that no round may use.
ATTEMPT_S = probe.ATTEMPT_S
TOTAL_S = probe.override_seconds("PROBE_C_T_TOTAL", 75.0)
RESERVE_S = probe.override_seconds("PROBE_C_T_RESERVE", 5.0)
OBS_CALL_S = probe.override_seconds("PROBE_C_T_OBS", 1.0)
# A round starts only when its worst case (attempt + reap wait + pipe drain) still leaves the reserve.
START_NEED_S = ATTEMPT_S + probe.REAP_WAIT_S + probe.PIPE_DRAIN_S + RESERVE_S

PLAN = (("A", 1), ("B", 1), ("C", 1), ("A", 2), ("B", 2), ("C", 2))
NAME_PATTERNS = ("TOKEN", "KEY", "SECRET", "PASSWORD", "CREDENTIAL", "AUTH")
RAN = ("success", "timeout", "spawn_error", "bad_output")
VERSION = probe.VERSION

CONCLUSION_TEXT = {
    "cancelled_incomplete": "중간에 멈췄습니다 — 해석하지 않습니다",
    "incomplete_exit_unconfirmed": "측정 프로세스가 끝났는지 확인하지 못했습니다 — 해석하지 않습니다(남은 것 확인 필요)",
    "incomplete_missing_rounds": "실행하지 못한 라운드가 있습니다 — 해석하지 않습니다",
    "inconclusive_error": "실행 오류 또는 출력 형식 이상이 있습니다 — 경로와 스크립트부터 점검",
    "mixed_within_condition": "같은 조건 안에서 결과가 갈렸습니다(간헐·첫 실행 효과 등은 후보일 뿐 확정 아님)",
    "terminal_all_fast": "이번 터미널 조건에서는 모두 7초 안에 끝났습니다(launchd 고유 여부는 이 결과로 확정하지 못함)",
    "terminal_all_slow": "이번 터미널 조건에서는 모두 7초를 넘었습니다(바이너리·머신 문제로 확정하지 못함)",
    "env_axis_associated": "환경 축과 연관된 관찰입니다(원인 확정 아님)",
    "isolated_config_axis_associated": "격리 설정 축과 연관된 관찰입니다(데몬·pid 파일 분열을 특정하지 않음)",
    "isolated_only_slow": "격리 설정에서만 느렸습니다(빈 설정 첫 초기화 등은 후보일 뿐)",
    "mixed_unexpected": "예상 밖 조합 — 해석 보류",
}
STATE_TEXT = {"fast": "빠름(둘 다 7초 안)", "slow": "느림(둘 다 7초 초과)", "mixed": "갈림", "incomplete": "불완전"}
SIGNAL_CODE = {signal.SIGINT: 130, signal.SIGTERM: 143, signal.SIGHUP: 129}


def clock() -> float:
    return time.monotonic()


class Cancelled(BaseException):
    """Raised by the signal handler (once); ``info`` is the in-flight attempt, when there was one."""

    def __init__(self, signum: int):
        super().__init__(signum)
        self.signum = signum
        self.info: dict | None = None


# ----------------------------------------------------------------------------------------------- one attempt
def run_attempt(argv: list[str], env: dict[str, str], limit_s: float) -> dict:
    """One attempt, no retry, one deadline fixed *before* the process starts. From the moment Popen succeeds every
    path ends the child (our direct child only — never a group, a shared daemon or a descendant)."""
    info = {"status": "observation_unknown", "rc": None, "child_pid": None, "child_exited": None, "reaped": False,
            "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False, "stdout": b"", "stderr": b""}
    deadline = time.monotonic() + limit_s
    try:
        proc = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, close_fds=True)
    except OSError:
        info["status"] = "spawn_error"
        return info
    info["child_pid"] = proc.pid
    try:
        try:
            info["stdout"], info["stderr"] = proc.communicate(timeout=max(0.0, deadline - time.monotonic()))
            info.update(rc=proc.returncode, child_exited=True, reaped=True, status="success")
            return info
        except subprocess.TimeoutExpired:
            pass
    except BaseException as exc:
        probe._end_child(proc, info, probe.Budget(5.0))
        if isinstance(exc, Cancelled):
            exc.info = info
        raise
    info["status"] = "timeout"
    probe._end_child(proc, info, probe.Budget(5.0))
    return info  # partial output is not kept: stdout/stderr stay empty


def classify(info: dict) -> str:
    if info["status"] != "success":
        return info["status"] if info["status"] in RAN else "bad_output"
    first = info["stdout"].decode("utf-8", "replace").splitlines()[:1]
    return "success" if info["rc"] == 0 and first and VERSION.match(first[0]) else "bad_output"


def round_record(variant: str, number: int, status: str, elapsed_ms: int | None = None, info: dict | None = None) -> dict:
    info = info or {}
    return {"variant": variant, "round": number, "status": status, "elapsed_ms": elapsed_ms, "rc": info.get("rc"),
            "reaped": bool(info.get("reaped")), "child_exit_unconfirmed": bool(info.get("child_exit_unconfirmed"))}


# ----------------------------------------------------------------------------------------------- environments
def env_a(environ: dict[str, str]) -> tuple[dict[str, str], int]:
    """The terminal environment without ``OP_*`` and without credential-looking names; only names are looked at."""
    kept: dict[str, str] = {}
    removed = 0
    for name, value in environ.items():
        upper = name.upper()
        if upper.startswith("OP_") or any(pattern in upper for pattern in NAME_PATTERNS):
            removed += 1
        else:
            kept[name] = value
    return kept, removed


# ----------------------------------------------------------------------------------------------- observations
def count_op() -> int | None:
    """Number of processes named exactly ``op`` (as ``pgrep -x op``); None when it could not be looked at."""
    try:
        done = subprocess.run(["pgrep", "-x", "op"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, timeout=OBS_CALL_S,
                              env={"LC_ALL": "C", "PATH": os.environ.get("PATH", "/usr/bin:/bin")})
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode == 0:
        return len(done.stdout.split())
    return 0 if done.returncode == 1 else None


def socket_mtime() -> int | None:
    try:
        return os.stat(os.path.join(os.path.expanduser("~"), ".config", "op", "op-daemon.sock")).st_mtime_ns
    except OSError:
        return None


# ----------------------------------------------------------------------------------------------- the table
def condition_state(rounds: list[dict], variant: str) -> str:
    statuses = [r["status"] for r in rounds if r["variant"] == variant]
    if len(statuses) == 2 and all(s in ("success", "timeout") for s in statuses):
        if statuses == ["success", "success"]:
            return "fast"
        return "slow" if statuses == ["timeout", "timeout"] else "mixed"
    return "incomplete"


def conclude(rounds: list[dict], cancelled: bool) -> str:
    """The first row that matches, top to bottom (design §6.3); the incomplete/error rows win over any combination."""
    if cancelled:
        return "cancelled_incomplete"
    if any(r["child_exit_unconfirmed"] for r in rounds):
        return "incomplete_exit_unconfirmed"
    if len(rounds) < len(PLAN) or any(r["status"].startswith("skipped_") for r in rounds):
        return "incomplete_missing_rounds"
    if any(r["status"] in ("spawn_error", "bad_output") for r in rounds):
        return "inconclusive_error"
    a, b, c = (condition_state(rounds, v) for v in "ABC")
    if "mixed" in (a, b, c):
        return "mixed_within_condition"
    if (a, b, c) == ("fast", "fast", "fast"):
        return "terminal_all_fast"
    if (a, b, c) == ("slow", "slow", "slow"):
        return "terminal_all_slow"
    if a == "fast" and b == "slow":
        return "env_axis_associated"
    if (a, b, c) == ("slow", "slow", "fast"):
        return "isolated_config_axis_associated"
    if (a, b, c) == ("fast", "fast", "slow"):
        return "isolated_only_slow"
    return "mixed_unexpected"


# ----------------------------------------------------------------------------------------------- the run
def refuse(message: str) -> int:
    sys.stdout.write(message + "\n")
    return 2


def new_id() -> str:
    return f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{random.randrange(100000)}"


def main(argv: list[str]) -> int:
    begin = clock()
    args = list(argv)
    if "--mode" in args:  # the explicit mode argument was already read at import
        index = args.index("--mode")
        args = args[:index] + args[index + 2:]
    if args:
        return refuse("usage: compare.py --mode production|selftest")
    op = shutil.which("op", path=os.environ.get("PATH"))
    if not op or not os.path.isabs(op):
        return refuse("op 를 찾을 수 없습니다. 아무것도 만들지 않고 시작하지 않습니다.")
    base = Path(probe.override("PROBE_BASE", os.path.join(os.path.expanduser("~"), ".local", "share", "airag-probe")))
    if base.is_symlink() or base.parent.is_symlink():
        return refuse("점검 폴더의 위치가 심링크입니다. 시작하지 않습니다.")
    try:
        os.makedirs(base, mode=0o700, exist_ok=True)
        run_id = new_id()
        result_path = base / f"compare-{run_id}.result.json"
        temp_dir = base / f"compare-{run_id}"
    except OSError:
        return refuse("점검 폴더를 만들 수 없습니다. 시작하지 않습니다.")

    state: dict = {"finalizing": False, "signal": None}

    def on_signal(signum, _frame):
        if state["finalizing"] or state["signal"] is not None:
            return
        state["signal"] = signum
        raise Cancelled(signum)

    previous = {sig: signal.signal(sig, on_signal) for sig in SIGNAL_CODE}
    rounds: list[dict] = []
    counts: dict = {"before": None, "after": None}
    sock = {"before": None, "after": None}
    removed_a = 0
    temp_made = False
    cancelled = False
    unconfirmed = False

    def save(final: dict | None = None) -> dict:
        document = {
            "v": SCHEMA_VERSION, "rounds": rounds,
            "conditions": {v: condition_state(rounds, v) for v in "ABC"},
            "op_count_before": counts["before"], "op_count_after": counts["after"],
            "sock_mtime_changed": sock["before"] != sock["after"], "removed_name_count_A": removed_a,
            "leftover_check_required": False, "complete": False, "exit_class": None, "conclusion": None,
        }
        if final:
            document.update(final)
        probe.write_json_atomic(result_path, document)
        return document

    try:
        try:
            counts["before"] = count_op()
            sock["before"] = socket_mtime()
            for variant, number in PLAN:
                if unconfirmed:
                    rounds.append(round_record(variant, number, "skipped_after_unconfirmed"))
                    save()
                    continue
                if TOTAL_S - (clock() - begin) < START_NEED_S:
                    rounds.append(round_record(variant, number, "skipped_budget"))
                    save()
                    continue
                if variant == "A":
                    env, removed_a = env_a(dict(os.environ))
                elif variant == "B":
                    env = probe.op_environment(None)
                else:
                    if not temp_made:
                        try:
                            os.mkdir(temp_dir, 0o700)
                            temp_made = True
                        except OSError:
                            rounds.append(round_record(variant, number, "spawn_error"))
                            save()
                            continue
                    env = probe.op_environment(None, home=str(temp_dir))
                started = clock()
                info = run_attempt([op, "--version"], env, ATTEMPT_S)
                elapsed = int((clock() - started) * 1000)
                rounds.append(round_record(variant, number, classify(info), elapsed, info))
                unconfirmed = bool(info.get("child_exit_unconfirmed"))
                save()
        except Cancelled as stop:
            cancelled = True
            if stop.info is not None:
                rounds.append(round_record(*PLAN[len(rounds)], "cancelled", None, stop.info))
    finally:
        state["finalizing"] = True
        for sig, handler in previous.items():
            signal.signal(sig, handler)

    counts["after"] = count_op()
    sock["after"] = socket_mtime()
    counts_bad = counts["before"] is None or counts["after"] is None or counts["before"] != counts["after"]
    leftover = counts_bad or unconfirmed or (cancelled and temp_made)
    removed_folder = False
    if temp_made and not leftover:
        shutil.rmtree(temp_dir, ignore_errors=True)
        removed_folder = not temp_dir.exists()
        leftover = not removed_folder
    complete = (not cancelled and len(rounds) == len(PLAN) and all(r["status"] in RAN for r in rounds))
    exit_class = "cancelled" if cancelled else ("ran_all" if complete else "incomplete")
    conclusion = conclude(rounds, cancelled)
    save({"leftover_check_required": leftover, "complete": complete, "exit_class": exit_class,
          "conclusion": conclusion})
    report(rounds, conclusion, counts, leftover, removed_folder, result_path)
    if cancelled:
        return SIGNAL_CODE.get(state["signal"], 130)
    return 0 if complete else 1


def report(rounds: list[dict], conclusion: str, counts: dict, leftover: bool, removed_folder: bool,
           result_path: Path) -> None:
    out = ["", "op --version 조건별 측정 결과 (값은 기록하지 않음)"]
    names = {"A": "A 터미널 환경", "B": "B 최소 환경", "C": "C 격리 설정"}
    for r in rounds:
        ms = f"{r['elapsed_ms']} ms" if r["elapsed_ms"] is not None else "-"
        out.append(f"  {names[r['variant']]} {r['round']}회: {r['status']} ({ms})")
    out.append(f"결론: {conclusion} — {CONCLUSION_TEXT[conclusion]}")
    out.append(f"전후 op 프로세스 수: {counts['before']} → {counts['after']}")
    if removed_folder:
        out.append("임시 폴더를 지웠습니다. 전후 수가 같다는 것은 새 데몬이 없다는 증명이 아닙니다.")
    if leftover:
        out.append("남은 것 확인 필요: 임시 폴더를 지우지 않았거나 프로세스를 확인하지 못했습니다(기존·새 op 는 종료하지 않음).")
    out.append(f"결과 파일: {result_path}")
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
