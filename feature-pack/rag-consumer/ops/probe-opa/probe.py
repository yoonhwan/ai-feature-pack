#!/usr/bin/env python3
"""One-shot evidence probe for the 1Password popup / timeout problem (design arch-20261015-opa-popup-design-r4 §4).

It narrows candidates; it never fixes anything and never proves that operation is healthy. Run by ``probe.sh``
under a temporary launchd job, so the processes sit in the same launchd context as the consumer tick.

Value-free by construction: stdout/stderr of every child is only tested in memory (empty or not, fixed
substring lists) and dropped; the result holds only finite enumerations, booleans, integers and timestamps.
The service-account token goes from its file into the memory of this process and then into the environment of
the ``op`` children that need it, nowhere else.

Modes:  --run DIR | --close-timeout DIR | --report DIR | --list-pids DIR | --validate FILE
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import stat
import subprocess
import sys
import time

SCHEMA_VERSION = 1
SELFTEST = os.environ.get("PROBE_SELFTEST") == "1"


def override(name: str, default):
    """Test hooks: honoured only under --selftest; a real run always uses the default."""
    return os.environ.get(name, default) if SELFTEST else default


# External-call 7-second rule: one attempt, no retry. Recovery after a timeout is local clean-up with its own cap.
ATTEMPT_S = float(override("PROBE_T_ATTEMPT", 7.0))
REAP_WAIT_S = float(override("PROBE_T_REAP", 2.0))
PIPE_DRAIN_S = float(override("PROBE_T_PIPE", 1.0))
LOCAL_BUDGET_S = float(override("PROBE_T_LOCAL", 15.0))
LOG_CALL_S = 3.0
LOCAL_CALL_S = 3.0
P4_HOST, P4_PORT = "my.1password.com", 443

STATUSES = (
    "success", "auth_error", "network_error", "timeout", "spawn_error", "unsupported",
    "observation_unknown", "skipped_prior_unresolved", "skipped_not_applicable",
)
TCC_VALUES = ("seen_attributed", "seen_unattributed", "none_logged_ok", "unknown_log_unavailable")
STEPS = ("P4", "P0", "P2", "P1", "P1b")
CLI_STEPS = ("P0", "P2", "P1", "P1b")
CONCLUSIONS = (
    "p0_blocked", "default_path_only_blocked", "dedicated_path_also_blocked", "no_repro_twice",
    "intermittent_repro", "no_repro_tcc_unobservable", "auth_error", "network_reachability",
    "cause_unconfirmed", "observation_unknown",
)
CONCLUSION_TEXT = {
    "p0_blocked": "자격 없는 op 기동에서 이미 막힘/요청 — 원인 미확정, 별도 결정(DA 포함)",
    "default_path_only_blocked": "기본 경로에서만 막히고 전용 경로는 통과(단일 시행) — 전용 경로 후보 유지, S2 승인 요청 대상",
    "dedicated_path_also_blocked": "전용 경로에서도 막힘 — 전용 경로 후보 근거 약화, 원인 미확정",
    "no_repro_twice": "이번 시점 재현 없음(2회) — 팝업 부재 보증 아님, 변경 보류, S2",
    "intermittent_repro": "간헐 재현 확인 — 전용 경로 후보 약하게 유지, S2",
    "no_repro_tcc_unobservable": "재현 없음 + 팝업 관측 불가 — 변경 보류",
    "auth_error": "토큰 폐기/만료/권한 후보 — 팝업 해결안 보류, 토큰 재발급 후보(오빠 손)",
    "network_reachability": "도달성 후보 — 네트워크 점검 후보",
    "cause_unconfirmed": "원인 미확정 — 변경 보류",
    "observation_unknown": "결과 없음/불완전 — 관측 미확정",
}
# The only exception class names a result may carry; anything else is recorded as plain ``Exception``.
ERROR_CLASSES = ("OSError", "ValueError", "KeyError", "TypeError", "RuntimeError", "Exception")
OP_ENV_ALLOWLIST = ("PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR")
VERSION = re.compile(r"^\d+\.\d+\.\d+")
AUTH_MARKERS = ("unauthorized", "not signed in", "invalid token", "invalid service account", "authenticat",
                "not authorized", "forbidden", "(401)", "(403)", "expired", "revoked")
NETWORK_MARKERS = ("dial tcp", "no such host", "network is unreachable", "connection refused", "connection reset",
                   "i/o timeout", "tls", "could not resolve", "temporary failure in name resolution",
                   "no route to host", "timed out")
TCC_RELEVANT = ("1password", "2bua8c4s2c", "kTCCServiceSystemPolicyAppData".lower())
TCC_LINE = re.compile(r"^\d{4}-\d{2}-\d{2} \d")
PID_FIELD = re.compile(r"pid[=: ]+(\d+)")


# --------------------------------------------------------------------------------------------------- files
def write_json_atomic(path: Path, document: dict) -> None:
    temporary = path.with_name(path.name + ".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(document, sort_keys=True, separators=(",", ":")))
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def now_ms() -> int:
    return int(time.time() * 1000)


def ps_line(pid: int) -> str:
    """``lstart comm`` exactly as the shell cleanup will compare it ('' when unavailable)."""
    try:
        done = subprocess.run(["ps", "-o", "lstart=,comm=", "-p", str(pid)], capture_output=True, text=True,
                              timeout=LOCAL_CALL_S, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


class PidBook:
    """``pids.json``: this process and every op child it creates, written just before and just after spawning."""

    def __init__(self, directory: Path):
        self.path = directory / "pids.json"
        self.document: dict = {"v": 1, "self": {"pid": os.getpid(), "ps": ps_line(os.getpid())}, "children": [],
                               "pending": None}
        self.flush()

    def flush(self) -> None:
        write_json_atomic(self.path, self.document)

    def before(self, step: str) -> None:
        self.document["pending"] = step
        self.flush()

    def after(self, step: str, pid: int | None) -> None:
        self.document["pending"] = None
        if pid is not None:
            self.document["children"].append({"step": step, "pid": pid, "ps": ps_line(pid)})
        self.flush()

    def pids(self) -> set[int]:
        return {self.document["self"]["pid"], *(c["pid"] for c in self.document["children"])}


class Budget:
    def __init__(self, seconds: float):
        self.end = time.monotonic() + seconds

    def remaining(self) -> float:
        return max(0.0, self.end - time.monotonic())


# ------------------------------------------------------------------------------------------- the children
def run_child(step: str, argv: list[str], env: dict[str, str], book: PidBook, budget: Budget) -> dict:
    """One attempt, no retry: ``communicate(timeout=ATTEMPT_S)``; recovery after a timeout is always finite.

    kill() touches the direct child only. Exit confirmation (wait) and pipe draining are separate and each
    bounded; a descendant that keeps the pipe open is never waited for (the read ends are just closed).
    """
    info = {"status": "observation_unknown", "rc": None, "child_pid": None, "child_exited": None, "reaped": False,
            "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False, "stdout": b"", "stderr": b""}
    book.before(step)
    try:
        proc = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, close_fds=True)
    except OSError:
        book.after(step, None)
        info["status"] = "spawn_error"
        return info
    book.after(step, proc.pid)
    info["child_pid"] = proc.pid
    try:
        info["stdout"], info["stderr"] = proc.communicate(timeout=ATTEMPT_S)
        info.update(rc=proc.returncode, child_exited=True, reaped=True, status="success")
        return info
    except subprocess.TimeoutExpired:
        info["status"] = "timeout"
    proc.kill()  # the direct child only: never a group, never a shared daemon, never a descendant
    try:
        proc.wait(timeout=REAP_WAIT_S)
        info.update(rc=proc.returncode, child_exited=True, reaped=True)
    except subprocess.TimeoutExpired:
        info.update(child_exited=False, child_exit_unconfirmed=True)
    if info["child_exited"]:
        try:
            proc.communicate(timeout=min(budget.remaining(), PIPE_DRAIN_S))
        except subprocess.TimeoutExpired:
            info["descendants_may_hold_pipe"] = True
    else:
        info["descendants_may_hold_pipe"] = True
    for stream in (proc.stdout, proc.stderr):
        if stream:
            try:
                stream.close()
            except OSError:
                pass
    return info  # partial output is not kept: stdout/stderr stay empty


def op_environment(token: str | None, home: str | None = None) -> dict[str, str]:
    env = {name: os.environ[name] for name in OP_ENV_ALLOWLIST if name in os.environ}
    if home is not None:
        env["HOME"] = home
        env["OP_CONFIG_DIR"] = home + "/.config/op"
    if token is not None:
        env["OP_SERVICE_ACCOUNT_TOKEN"] = token
    return env


def read_token() -> str | None:
    path = override("PROBE_TOKEN_FILE", None) or os.path.join(os.path.expanduser("~"), ".config", "krb", "op-sa-token")
    try:
        token = Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return token or None


def dedicated_home() -> str | None:
    """§5.1: <HOME>/.local/share/airag/op-home, 0700, a real directory owned by us, at its real path."""
    expected = os.path.join(os.path.realpath(os.path.expanduser("~")), ".local", "share", "airag", "op-home")
    try:
        os.makedirs(expected, mode=0o700, exist_ok=True)
        info = os.lstat(expected)
    except OSError:
        return None
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077
            or os.path.realpath(expected) != expected):
        return None
    return expected


def classify_version(info: dict) -> tuple[str, bool | None]:
    if info["status"] != "success":
        return info["status"], None
    if info["rc"] != 0:
        return "observation_unknown", None
    ok = bool(VERSION.match(info["stdout"].decode("utf-8", "replace").strip()))
    return ("success" if ok else "unsupported"), None


def classify_account(info: dict) -> tuple[str, bool | None]:
    if info["status"] != "success":
        return info["status"], None
    if info["rc"] == 0:
        try:
            document = json.loads(info["stdout"].decode("utf-8"))
        except ValueError:
            return "unsupported", False
        if isinstance(document, dict) and document.get("type") == "SERVICE_ACCOUNT":
            return "success", True
        return "unsupported", False
    low = info["stderr"].decode("utf-8", "replace").lower()
    if any(marker in low for marker in AUTH_MARKERS):
        return "auth_error", None
    if any(marker in low for marker in NETWORK_MARKERS):
        return "network_error", None
    return "observation_unknown", None


# ---------------------------------------------------------------------------------------------- tcc / s0
def local_run(argv: list[str], budget: Budget):
    timeout = min(LOCAL_CALL_S, budget.remaining())
    if timeout <= 0:
        return None
    try:
        return subprocess.run(argv, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None


def observe_tcc(start_wall: float, end_wall: float, pids: set[int], budget: Budget) -> str:
    """Window [start-0.5 s, end+2 s]. ``none_logged_ok`` needs another TCC line as a positive control."""
    stamp = "%Y-%m-%d %H:%M:%S"
    first = time.strftime(stamp, time.localtime(math.floor(start_wall - 0.5)))
    last = time.strftime(stamp, time.localtime(math.ceil(end_wall + 2.0)))
    timeout = min(LOG_CALL_S, budget.remaining())
    if timeout <= 0:
        return "unknown_log_unavailable"
    try:
        done = subprocess.run(
            [override("PROBE_LOG_BIN", "/usr/bin/log"), "show", "--start", first, "--end", last, "--predicate",
             'subsystem == "com.apple.TCC"', "--style", "compact"],
            capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return "unknown_log_unavailable"
    if done.returncode != 0:
        return "unknown_log_unavailable"
    lines = [line for line in done.stdout.decode("utf-8", "replace").splitlines() if TCC_LINE.match(line)]
    if not lines:
        return "unknown_log_unavailable"
    relevant = [line for line in lines if any(word in line.lower() for word in TCC_RELEVANT)]
    if not relevant:
        return "none_logged_ok"
    for line in relevant:
        if any(int(found) in pids for found in PID_FIELD.findall(line)):
            return "seen_attributed"
    return "seen_unattributed"


def snapshot(budget: Budget) -> dict:
    launchctl = override("PROBE_LAUNCHCTL", "launchctl")
    uid = os.getuid()
    disabled = loaded = "unknown"
    done = local_run([launchctl, "print-disabled", f"gui/{uid}"], budget)
    if done is not None and done.returncode == 0:
        for line in done.stdout.decode("utf-8", "replace").splitlines():
            if '"com.airag.consumer"' in line and "=>" in line:
                value = line.split("=>", 1)[1].strip().lower()
                disabled = "true" if value in ("disabled", "true") else "false" if value in ("enabled", "false") else "unknown"
    done = local_run([launchctl, "print", f"gui/{uid}/com.airag.consumer"], budget)
    if done is not None:
        if done.returncode == 0:
            loaded = "true"
        elif b"Could not find service" in done.stderr:
            loaded = "false"
    count = None
    done = local_run(["pgrep", "-x", "op"], budget)
    if done is not None and done.returncode in (0, 1):
        count = len(done.stdout.split())
    try:
        sock = int(os.stat(os.path.join(os.path.expanduser("~"), ".config", "op", "op-daemon.sock")).st_mtime * 1000)
    except OSError:
        sock = None
    return {"consumer_disabled": disabled, "consumer_loaded": loaded, "op_process_count": count,
            "op_socket_mtime_utc_ms": sock}


# -------------------------------------------------------------------------------------------------- steps
def blank_step(step: str, status: str) -> dict:
    now = now_ms()
    return {"step": step, "status": status, "rc": None, "elapsed_ms": 0, "started_utc_ms": now, "ended_utc_ms": now,
            "child_pid": None, "child_exited": None, "reaped": False, "child_exit_unconfirmed": False,
            "descendants_may_hold_pipe": False, "account_type_confirmed": None, "tcc_observation": None}


def stage_p4() -> dict:
    step = blank_step("P4", "observation_unknown")
    started_wall, started = time.time(), time.monotonic()
    stub = override("PROBE_P4_STUB", None)
    if stub:
        status = stub if stub in STATUSES else "observation_unknown"
    else:
        deadline = started + ATTEMPT_S
        try:
            raw = socket.create_connection((P4_HOST, P4_PORT), timeout=max(0.01, deadline - time.monotonic()))
            raw.settimeout(max(0.01, deadline - time.monotonic()))
            with ssl.create_default_context().wrap_socket(raw, server_hostname=P4_HOST):
                status = "success"
        except (socket.timeout, TimeoutError):
            status = "timeout"
        except (socket.gaierror, ConnectionError, ssl.SSLError, OSError):
            status = "network_error"
    step.update(status=status, elapsed_ms=int((time.monotonic() - started) * 1000),
                started_utc_ms=int(started_wall * 1000), ended_utc_ms=now_ms())
    return step


def stage_cli(name: str, argv: list[str] | None, env: dict[str, str], classify, book: PidBook,
              budget: Budget, *, blocked: str | None = None) -> dict:
    step = blank_step(name, "observation_unknown")
    started_wall, started = time.time(), time.monotonic()
    if blocked is not None:  # a precondition failed before anything was started
        step["status"] = blocked
        return step
    info = run_child(name, argv, env, book, budget)
    status, confirmed = classify(info)
    ended_wall = time.time()
    step.update(
        status=status, rc=info["rc"], elapsed_ms=int((time.monotonic() - started) * 1000),
        started_utc_ms=int(started_wall * 1000), ended_utc_ms=int(ended_wall * 1000), child_pid=info["child_pid"],
        child_exited=info["child_exited"], reaped=info["reaped"], child_exit_unconfirmed=info["child_exit_unconfirmed"],
        descendants_may_hold_pipe=info["descendants_may_hold_pipe"], account_type_confirmed=confirmed,
    )
    if info["child_pid"] is not None:
        step["tcc_observation"] = observe_tcc(started_wall, ended_wall, book.pids(), budget)
    return step


def stops(step: dict) -> str | None:
    """§4.3 for P0/P2/P1: 'unresolved' (timeout or a TCC request seen), 'complete' (an error), or None."""
    if step["tcc_observation"] in ("seen_attributed", "seen_unattributed") or step["status"] == "timeout":
        return "unresolved"
    return None if step["status"] == "success" else "complete"


def p1b_allowed(steps: dict[str, dict]) -> bool:
    return all(steps[n]["status"] == "success" and steps[n]["tcc_observation"] == "none_logged_ok"
               for n in ("P0", "P2", "P1"))


def conclude(steps: dict[str, dict]) -> str:
    cli = [steps[n] for n in CLI_STEPS if n in steps]
    if any(s["status"] == "auth_error" for s in cli):
        return "auth_error"
    if steps.get("P4", {}).get("status") == "network_error" and any(s["status"] == "timeout" for s in cli):
        return "network_reachability"
    for name, verdict in (("P0", "p0_blocked"), ("P2", "dedicated_path_also_blocked"),
                          ("P1", "default_path_only_blocked")):
        step = steps.get(name)
        if step is None or step["status"].startswith("skipped"):
            return "cause_unconfirmed"
        if stops(step) == "unresolved":
            return verdict
        if step["status"] != "success":
            return "cause_unconfirmed"
    if any(steps[n]["tcc_observation"] == "unknown_log_unavailable" for n in ("P0", "P2", "P1")):
        return "no_repro_tcc_unobservable"
    p1b = steps.get("P1b")
    if p1b is None:
        return "cause_unconfirmed"
    if p1b["status"] == "success" and p1b["tcc_observation"] == "none_logged_ok":
        return "no_repro_twice"
    if stops(p1b) == "unresolved":
        return "intermittent_repro"
    return "cause_unconfirmed"


def new_result() -> dict:
    return {"schema_version": SCHEMA_VERSION, "steps": [], "s0": {}, "complete": False, "tcc_unknown": False,
            "conclusion": "observation_unknown", "timed_out_wait": False, "aborted_class": None}


def execute(directory: Path) -> None:
    result_path = directory / "result.json"
    book = PidBook(directory)
    budget = Budget(LOCAL_BUDGET_S)
    result = new_result()
    done: dict[str, dict] = {}

    def save(complete: bool = False) -> None:
        result["steps"] = [done[n] for n in STEPS if n in done]
        result["tcc_unknown"] = any(s["tcc_observation"] == "unknown_log_unavailable" for s in result["steps"]
                                    if s["step"] in CLI_STEPS)
        result["complete"] = complete
        if complete:
            result["conclusion"] = conclude(done)
        write_json_atomic(result_path, result)

    try:
        result["s0"] = snapshot(budget)
        save()
        done["P4"] = stage_p4()
        save()
        token = read_token()
        op = override("PROBE_OP_BIN", None) or shutil.which("op", path=os.environ.get("PATH"))
        stopped: str | None = None
        for name in CLI_STEPS:
            if stopped is not None:
                done[name] = blank_step(name, "skipped_prior_unresolved" if stopped == "unresolved"
                                        else "skipped_not_applicable")
            elif name == "P1b" and not p1b_allowed(done):
                done[name] = blank_step(name, "skipped_not_applicable")
            else:
                done[name] = run_cli(name, op, token, book, budget)
                if name != "P1b":
                    stopped = stops(done[name])
            save()
        token = None
        save(complete=True)
    except Exception as error:  # class name only, from a fixed list
        result["steps"] = [done[n] for n in STEPS if n in done]
        result.update(complete=True, conclusion="observation_unknown",
                      aborted_class=type(error).__name__ if type(error).__name__ in ERROR_CLASSES else "Exception")
        write_json_atomic(result_path, result)


def run_cli(name: str, op: str | None, token: str | None, book: PidBook, budget: Budget) -> dict:
    if name == "P0":
        if not op:
            return stage_cli(name, None, {}, classify_version, book, budget, blocked="spawn_error")
        return stage_cli(name, [op, "--version"], op_environment(None), classify_version, book, budget)
    if not op:
        return stage_cli(name, None, {}, classify_account, book, budget, blocked="spawn_error")
    if token is None:
        return stage_cli(name, None, {}, classify_account, book, budget, blocked="observation_unknown")
    argv = [op, "user", "get", "--me", "--format", "json"]
    if name == "P2":
        home = dedicated_home()
        if home is None:
            return stage_cli(name, None, {}, classify_account, book, budget, blocked="observation_unknown")
        return stage_cli(name, argv, op_environment(token, home), classify_account, book, budget)
    return stage_cli(name, argv, op_environment(token), classify_account, book, budget)


# ------------------------------------------------------------------------------------------- validation
def _int(value) -> bool:
    return type(value) is int


def _int_or_none(value) -> bool:
    return value is None or _int(value)


def _bool_or_none(value) -> bool:
    return value is None or type(value) is bool


STEP_FIELDS = {
    "step": lambda v: v in STEPS, "status": lambda v: v in STATUSES, "rc": _int_or_none, "elapsed_ms": _int,
    "started_utc_ms": _int, "ended_utc_ms": _int, "child_pid": _int_or_none, "child_exited": _bool_or_none,
    "reaped": lambda v: type(v) is bool, "child_exit_unconfirmed": lambda v: type(v) is bool,
    "descendants_may_hold_pipe": lambda v: type(v) is bool, "account_type_confirmed": _bool_or_none,
    "tcc_observation": lambda v: v is None or v in TCC_VALUES,
}
S0_FIELDS = {
    "consumer_disabled": lambda v: v in ("true", "false", "unknown"),
    "consumer_loaded": lambda v: v in ("true", "false", "unknown"),
    "op_process_count": _int_or_none, "op_socket_mtime_utc_ms": _int_or_none,
}
TOP_FIELDS = {
    "schema_version": lambda v: v == SCHEMA_VERSION, "complete": lambda v: type(v) is bool,
    "tcc_unknown": lambda v: type(v) is bool, "conclusion": lambda v: v in CONCLUSIONS,
    "timed_out_wait": lambda v: type(v) is bool, "aborted_class": lambda v: v is None or v in ERROR_CLASSES,
}


def _fields_ok(document, table) -> bool:
    return isinstance(document, dict) and set(document) == set(table) and all(
        check(document[key]) for key, check in table.items())


def validate_result(document) -> bool:
    """Strict closed schema: exact keys, finite enumerations, no free text anywhere."""
    if not isinstance(document, dict) or set(document) != {*TOP_FIELDS, "steps", "s0"}:
        return False
    if not all(check(document[key]) for key, check in TOP_FIELDS.items()):
        return False
    if not isinstance(document["s0"], dict) or (document["s0"] and not _fields_ok(document["s0"], S0_FIELDS)):
        return False
    return isinstance(document["steps"], list) and all(_fields_ok(s, STEP_FIELDS) for s in document["steps"])


def read_result(directory: Path) -> dict:
    """A missing, unreadable, invalid or not-complete result reads as observation_unknown."""
    unknown = new_result()
    try:
        document = json.loads((Path(directory) / "result.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return unknown
    if not validate_result(document):
        return unknown
    if document["complete"] is not True:
        document["conclusion"] = "observation_unknown"
    return document


def close_on_timeout(directory: Path) -> None:
    current = read_result(directory)
    if current["complete"] is True:
        return
    current.update(complete=True, timed_out_wait=True, conclusion="observation_unknown")
    write_json_atomic(Path(directory) / "result.json", current)


def report(directory: Path) -> int:
    result = read_result(directory)
    out = ["== 1Password 연결 점검 프로브 결과 (후보 축소일 뿐 — 변경 보류가 기본, 진단 성공은 운영 재개 승인이 아님) =="]
    if not result["steps"] and not result["s0"]:
        out.append("결과 없음/불완전: observation_unknown")
    else:
        s0 = result["s0"]
        if s0:
            out.append("S0: consumer disabled={consumer_disabled} loaded={consumer_loaded} op 프로세스={op_process_count}".format(**s0))
        for step in result["steps"]:
            out.append("{step}: {status} tcc={tcc} {ms}ms".format(
                step=step["step"], status=step["status"], tcc=step["tcc_observation"] or "-", ms=step["elapsed_ms"]))
    if result["tcc_unknown"]:
        out.append("tcc_unknown: TCC 로그 관측 불가 단계가 있음")
    if result["timed_out_wait"]:
        out.append("결과 대기 시간 초과: timed_out_wait")
    out.append(f"결론: {result['conclusion']} — {CONCLUSION_TEXT[result['conclusion']]}")
    out.append("공통: consumer 는 disabled 유지")
    print("\n".join(out))
    return 0 if result["complete"] is True and result["conclusion"] != "observation_unknown" else 1


def list_pids(directory: Path) -> int:
    try:
        document = json.loads((Path(directory) / "pids.json").read_text(encoding="utf-8"))
        entries = [document["self"], *document["children"]]
    except (OSError, ValueError, KeyError, TypeError):
        return 0
    for entry in entries:
        if _int(entry.get("pid")) and isinstance(entry.get("ps"), str) and "|" not in entry["ps"]:
            print(f"{entry['pid']}|{entry['ps']}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        sys.stderr.write("usage: probe.py --run|--close-timeout|--report|--list-pids DIR | --validate FILE\n")
        return 2
    mode, target = argv
    if mode == "--run":
        execute(Path(target))
        return 0
    if mode == "--close-timeout":
        close_on_timeout(Path(target))
        return 0
    if mode == "--report":
        return report(Path(target))
    if mode == "--list-pids":
        return list_pids(Path(target))
    if mode == "--validate":
        try:
            return 0 if validate_result(json.loads(Path(target).read_text(encoding="utf-8"))) else 1
        except (OSError, ValueError):
            return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
