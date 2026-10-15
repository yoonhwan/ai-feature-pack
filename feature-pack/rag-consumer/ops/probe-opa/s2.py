#!/usr/bin/env python3
"""S2: key-read timing measurement (design arch-20261015-opa-popup-design-r4 §6.1).

For two conditions — the real HOME ("default") and a fresh private HOME ("dedicated", §5.1 shape) — it runs one
cold round and five warm rounds (>= 60 s apart) of three parallel ``op read`` calls (one per store key), with the
same 7.0 s per attempt / one retry / 14.0 s per call rule as the tick. It only measures; nothing is changed.

Value-free by construction: for every attempt it records the key index, the attempt number, a status class, the
monotonic milliseconds, whether it was a retry and — for a successful read — a bool "has the 64-hex shape". The
read value, the vault reference, the token and any child output are never written; a successful value only lives
in memory long enough to compare the three values of a round ("distinct" bool) and is dropped.

probe.py (reviewed, and what a human runs) is imported unchanged; its reviewed parts are reused.

Modes:  --run DIR --mode production|selftest --credentials FILE | --close-timeout DIR | --report DIR
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import threading
import time

_SPEC = importlib.util.spec_from_file_location("probe_core", Path(__file__).with_name("probe.py"))
probe = importlib.util.module_from_spec(_SPEC)
sys.modules["probe_core"] = probe
_SPEC.loader.exec_module(probe)  # it reads --mode from sys.argv exactly like the probe itself

MODE = probe.MODE
SCHEMA_VERSION = 1
NAMES = ("AIRAG_CONSUMER_KEY_HEX", "AIRAG_PROJECTION_KEY_HEX", "AIRAG_ARCHIVE_KEY_HEX")  # as tick.NAMES
_KEY = re.compile(r"[0-9a-fA-F]{64}")

# The tick's external-call rule (7.0 s per attempt, one retry, 14.0 s per call) and the spacing of warm rounds.
ATTEMPT_S = probe.override_seconds("PROBE_S2_T_ATTEMPT", 7.0)
CALL_DEADLINE_S = probe.override_seconds("PROBE_S2_T_DEADLINE", 14.0)
WARM_GAP_S = probe.override_seconds("PROBE_S2_T_GAP", 60.0)
ROUNDS = 6  # 1 cold + 5 warm
DISK_TOLERANCE_BYTES = 0  # "dedicated path does not grow": tolerance is for the implementation review to fix
COUNT_CALL_S = 3.0

CONDITIONS = ("default", "dedicated")
KINDS = ("cold", "warm")
COMPARISONS = ("both_meet", "dedicated_only_meets", "default_only_meets", "neither_meets", "incomplete")
ERROR_CLASSES = (*probe.ERROR_CLASSES, "UnsafeDedicatedPath", "CredentialSettingsInvalid")
COMPARISON_TEXT = {
    "both_meet": "기본 경로·전용 경로 모두 사전 고정 기준을 충족",
    "dedicated_only_meets": "전용 경로만 기준을 충족 — 전용 경로 후보를 지지(단일 측정의 한계)",
    "default_only_meets": "기본 경로만 기준을 충족 — 전용 경로 후보를 지지하지 않음",
    "neither_meets": "두 경로 모두 기준 미충족 — 원인 미확정, 변경 보류",
    "incomplete": "측정이 끝나지 않았거나 결과가 불완전 — 판단 보류",
}


class CredentialSettingsInvalid(Exception):
    pass


class UnsafeDedicatedPath(Exception):
    pass


# ----------------------------------------------------------------------------------------------- one attempt
class LockedPidBook(probe.PidBook):
    """``pids.json`` shared by the parallel reads: every record is written under one lock."""

    def __init__(self, directory: Path):
        self._lock = threading.RLock()
        super().__init__(directory)

    def before(self, step: str) -> None:
        with self._lock:
            super().before(step)

    def after(self, step: str, pid: int | None) -> None:
        with self._lock:
            super().after(step, pid)


def run_attempt(step: str, argv: list[str], env: dict[str, str], book: probe.PidBook, budget: probe.Budget,
                attempt_s: float) -> dict:
    """One attempt with its own limit; the same protocol as ``probe.run_child`` (one deadline fixed before the
    process starts, an independent timer during the PID record, then a single owner), built from the same reviewed
    parts. It also says whether anything was printed before a timeout (``partial_output``) — only the bool, the
    content is dropped; when that could not be looked at, it is True (no retry on unknown)."""
    info = {"status": "observation_unknown", "rc": None, "child_pid": None, "child_exited": None, "reaped": False,
            "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False, "partial_output": False,
            "stdout": b"", "stderr": b""}
    deadline = time.monotonic() + attempt_s
    book.before(step)
    if deadline - time.monotonic() <= 0:
        info["status"] = "timeout"
        return info
    try:
        proc = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, close_fds=True)
    except OSError:
        book.after(step, None)
        info["status"] = "spawn_error"
        return info
    info["child_pid"] = proc.pid
    guard = probe._Deadline(proc, deadline - time.monotonic())
    recorded = False
    try:
        guard.start()
        book.after(step, proc.pid)
        recorded = True
    except Exception:
        recorded = False
    except BaseException:
        guard.stop()
        probe._end_child(proc, info, budget)
        raise
    if not guard.stop():
        info.update(status="observation_unknown", child_exit_unconfirmed=True)
        return info
    if not recorded:
        probe._end_child(proc, info, budget)
        info["status"] = "observation_unknown"
        return info
    remaining = deadline - time.monotonic()
    if remaining <= 0 or guard.fired:
        info["partial_output"] = True  # not looked at: unknown counts as "something was there"
    else:
        try:
            info["stdout"], info["stderr"] = proc.communicate(timeout=remaining)
            info.update(rc=proc.returncode, child_exited=True, reaped=True, status="success")
            return info
        except subprocess.TimeoutExpired as expired:
            info["partial_output"] = bool(expired.stdout or expired.stderr)
    info["status"] = "timeout"
    probe._end_child(proc, info, budget)
    return info


def classify_read(info: dict) -> tuple[str, bool | None]:
    """(status class, 64-hex shape bool). The value itself is never kept by the caller."""
    if info["status"] != "success":
        return info["status"], None
    if info["rc"] == 0:
        shaped = bool(_KEY.fullmatch(info["stdout"].decode("utf-8", "replace").strip()))
        return ("success" if shaped else "unsupported"), shaped
    low = info["stderr"].decode("utf-8", "replace").lower()
    if any(marker in low for marker in probe.AUTH_MARKERS):
        return "auth_error", None
    if any(marker in low for marker in probe.NETWORK_MARKERS):
        return "network_error", None
    return "observation_unknown", None


def read_call(index: int, reference: str, op: str, env: dict[str, str], book: probe.PidBook) -> tuple[dict, str | None]:
    """One key read = the tick's call: attempt 1 (<= 7 s); a retry only after a timeout with nothing printed and
    only with what is left of the 14 s call deadline. Returns the value-free record and the value (memory only)."""
    started = time.monotonic()
    deadline = started + CALL_DEADLINE_S
    timeout = ATTEMPT_S
    attempts: list[dict] = []
    value: str | None = None
    number = 1
    while True:
        t0 = time.monotonic()
        try:
            info = run_attempt(f"K{index}", [op, "read", reference], env, book, probe.Budget(5), timeout)
        except Exception:
            info = {"status": "observation_unknown", "rc": None, "child_exited": None, "reaped": False,
                    "child_exit_unconfirmed": False, "descendants_may_hold_pipe": False, "partial_output": True,
                    "stdout": b"", "stderr": b""}
        elapsed = int((time.monotonic() - t0) * 1000)
        status, shaped = classify_read(info)
        if status == "success":
            value = info["stdout"].decode("utf-8", "replace").strip()
        attempts.append({
            "attempt": number, "status": status, "elapsed_ms": elapsed, "retried": number == 2,
            "value_format_ok": shaped, "child_exited": info["child_exited"], "reaped": bool(info["reaped"]),
            "child_exit_unconfirmed": bool(info["child_exit_unconfirmed"]),
            "descendants_may_hold_pipe": bool(info["descendants_may_hold_pipe"]),
        })
        left = deadline - time.monotonic()
        if (number == 1 and status == "timeout" and not info["partial_output"] and left > 0
                and not info["child_exit_unconfirmed"]):
            number += 1
            timeout = min(ATTEMPT_S, left)
            continue
        break
    record = {"key": index, "attempts": attempts, "call_total_ms": int((time.monotonic() - started) * 1000),
              "outcome": attempts[-1]["status"]}
    return record, (value if attempts[-1]["status"] == "success" else None)


# ----------------------------------------------------------------------------------------------- rounds
def count_op() -> int | None:
    try:
        done = subprocess.run(["pgrep", "-x", "op"], capture_output=True, timeout=COUNT_CALL_S,
                              stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return len(done.stdout.split()) if done.returncode in (0, 1) else None


def tree_bytes(path: str) -> int | None:
    total = 0
    try:
        for root, dirs, files in os.walk(path, followlinks=False):
            for name in (*dirs, *files):
                total += os.lstat(os.path.join(root, name)).st_size
    except OSError:
        return None
    return total


def dedicated_dir(path: Path) -> str | None:
    """§5.1 policy: created 0700, a real directory (no symlink), owned by us, no group/other access, at its real
    path. Anything else -> None (nothing is measured there)."""
    expected = os.path.join(os.path.realpath(path.parent), path.name)
    try:
        os.makedirs(expected, mode=0o700, exist_ok=True)
        info = os.lstat(expected)
    except OSError:
        return None
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077
            or os.path.realpath(expected) != expected):
        return None
    return expected


def now_ms() -> int:
    return int(time.time() * 1000)


def run_round(number: int, op: str, references: list[str], make_env, book: probe.PidBook, home: str | None,
              ) -> dict:
    started = now_ms()
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(read_call, i, references[i], op, make_env(), book) for i in range(3)]
        results = [future.result() for future in futures]
    ended = now_ms()
    values = [value for _, value in results]
    # as tick.load_keys: the bytes after fromhex, so one key written in lower and upper case is a duplicate
    distinct = len({bytes.fromhex(v) for v in values}) == 3 if all(v is not None for v in values) else None
    return {
        "round": number, "kind": KINDS[0] if number == 0 else KINDS[1], "started_utc_ms": started,
        "ended_utc_ms": ended, "keys_distinct": distinct, "op_count_after": count_op(),
        "dedicated_bytes": tree_bytes(home) if home else None, "calls": [record for record, _ in results],
    }


# ----------------------------------------------------------------------------------------------- criteria
def _dist(values: list[int]) -> dict | None:
    if not values:
        return None
    ordered = sorted(values)
    return {"min": ordered[0], "median": ordered[len(ordered) // 2], "max": ordered[-1]}


def evaluate(condition: dict) -> dict:
    """The pre-fixed adoption criteria of §6.1 for one condition, as plain booleans and integers."""
    rounds = condition["rounds"]
    calls = [call for r in rounds for call in r["calls"]]
    attempts = [a for call in calls for a in call["attempts"]]
    firsts = [call["attempts"][0] for call in calls if call["attempts"]]
    first_ok = sum(1 for a in firsts if a["status"] == "success")
    baseline = condition["baseline_op_count"]
    cold = [call["attempts"][0] for call in (rounds[0]["calls"] if rounds else []) if call["attempts"]]
    disk = None
    if condition["name"] == "dedicated":
        sizes = [r["dedicated_bytes"] for r in rounds]
        disk = bool(sizes) and all(s is not None for s in sizes) and all(
            s <= sizes[0] + DISK_TOLERANCE_BYTES for s in sizes[1:])
    criteria = {
        "first_try_success_count": first_ok,
        "all_first_try_success": len(rounds) == ROUNDS and first_ok == ROUNDS * 3,
        "max_attempt_ms": max((a["elapsed_ms"] for a in attempts), default=None),
        "attempts_within_limit": bool(attempts) and all(a["elapsed_ms"] <= ATTEMPT_S * 1000 for a in attempts),
        "retries_used": sum(1 for a in attempts if a["retried"]),
        "max_call_total_ms": max((c["call_total_ms"] for c in calls), default=None),
        "calls_within_deadline": bool(calls) and all(c["call_total_ms"] <= CALL_DEADLINE_S * 1000 for c in calls),
        "op_count_not_increased": baseline is not None and bool(rounds) and all(
            r["op_count_after"] is not None and r["op_count_after"] <= baseline for r in rounds),
        "disk_not_increased": disk,
        "cold_over_limit": any(a["status"] == "timeout" or (a["status"] == "success"
                                                            and a["elapsed_ms"] > ATTEMPT_S * 1000) for a in cold),
        "cold_ms": _dist([a["elapsed_ms"] for a in cold]),
        "warm_ms": _dist([call["attempts"][0]["elapsed_ms"] for r in rounds[1:] for call in r["calls"]
                          if call["attempts"]]),
    }
    criteria["no_retries"] = criteria["retries_used"] == 0
    criteria["meets_all"] = bool(
        criteria["all_first_try_success"] and criteria["attempts_within_limit"] and criteria["no_retries"]
        and criteria["calls_within_deadline"] and criteria["op_count_not_increased"] and disk is not False
        and bool(rounds) and all(r["keys_distinct"] is True for r in rounds))
    return criteria


def compare(conditions: list[dict], complete: bool) -> str:
    if not complete or len(conditions) != 2:
        return "incomplete"
    by_name = {c["name"]: c["criteria"].get("meets_all") is True for c in conditions}
    default, dedicated = by_name.get("default"), by_name.get("dedicated")
    if default and dedicated:
        return "both_meet"
    if dedicated:
        return "dedicated_only_meets"
    if default:
        return "default_only_meets"
    return "neither_meets"


# ----------------------------------------------------------------------------------------------- the schema
def _int(value) -> bool:
    return type(value) is int


def _int_or_none(value) -> bool:
    return value is None or _int(value)


def _bool_or_none(value) -> bool:
    return value is None or type(value) is bool


def _bool(value) -> bool:
    return type(value) is bool


def _dist_ok(value) -> bool:
    return value is None or (isinstance(value, dict) and set(value) == {"min", "median", "max"}
                             and all(_int(v) for v in value.values()))


ATTEMPT_FIELDS = {
    "attempt": lambda v: v in (1, 2) and _int(v), "status": lambda v: v in probe.STATUSES, "elapsed_ms": _int,
    "retried": _bool, "value_format_ok": _bool_or_none, "child_exited": _bool_or_none, "reaped": _bool,
    "child_exit_unconfirmed": _bool, "descendants_may_hold_pipe": _bool,
}
CALL_FIELDS = {"key": lambda v: v in (0, 1, 2) and _int(v), "call_total_ms": _int,
               "outcome": lambda v: v in probe.STATUSES}
ROUND_FIELDS = {
    "round": lambda v: _int(v) and 0 <= v < ROUNDS, "kind": lambda v: v in KINDS, "started_utc_ms": _int,
    "ended_utc_ms": _int, "keys_distinct": _bool_or_none, "op_count_after": _int_or_none,
    "dedicated_bytes": _int_or_none,
}
CRITERIA_FIELDS = {
    "first_try_success_count": _int, "all_first_try_success": _bool, "max_attempt_ms": _int_or_none,
    "attempts_within_limit": _bool, "retries_used": _int, "no_retries": _bool, "max_call_total_ms": _int_or_none,
    "calls_within_deadline": _bool, "op_count_not_increased": _bool, "disk_not_increased": _bool_or_none,
    "cold_over_limit": _bool, "cold_ms": _dist_ok, "warm_ms": _dist_ok, "meets_all": _bool,
}
TOP_FIELDS = {
    "schema_version": lambda v: v == SCHEMA_VERSION, "mode": lambda v: v in ("production", "selftest"),
    "complete": _bool, "timed_out_wait": _bool, "aborted_class": lambda v: v is None or v in ERROR_CLASSES,
    "comparison": lambda v: v in COMPARISONS,
}


def _exact(document, table: dict, extra: set | None = None) -> bool:
    keys = set(table) | (extra or set())
    return isinstance(document, dict) and set(document) == keys and all(
        check(document[key]) for key, check in table.items())


def validate_result(document) -> bool:
    """Strict closed schema: exact keys, finite enumerations, no free text anywhere."""
    if not _exact(document, TOP_FIELDS, {"conditions"}) or not isinstance(document["conditions"], list):
        return False
    for condition in document["conditions"]:
        if not (isinstance(condition, dict) and set(condition) == {"name", "baseline_op_count", "rounds", "criteria"}
                and condition["name"] in CONDITIONS and _int_or_none(condition["baseline_op_count"])
                and isinstance(condition["rounds"], list)):
            return False
        if condition["criteria"] != {} and not _exact(condition["criteria"], CRITERIA_FIELDS):
            return False
        for rnd in condition["rounds"]:
            if not _exact(rnd, ROUND_FIELDS, {"calls"}) or not isinstance(rnd["calls"], list):
                return False
            for call in rnd["calls"]:
                if not _exact(call, CALL_FIELDS, {"attempts"}) or not isinstance(call["attempts"], list):
                    return False
                if not all(_exact(a, ATTEMPT_FIELDS) for a in call["attempts"]):
                    return False
    return True


def new_result() -> dict:
    return {"schema_version": SCHEMA_VERSION, "mode": MODE, "complete": False, "timed_out_wait": False,
            "aborted_class": None, "comparison": "incomplete", "conditions": []}


def read_result(directory: Path) -> dict:
    """A missing, unreadable, invalid or not-complete result reads as incomplete."""
    unknown = new_result()
    try:
        document = json.loads((Path(directory) / "result.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return unknown
    if not validate_result(document):
        return unknown
    if document["complete"] is not True:
        document["comparison"] = "incomplete"
    return document


def close_on_timeout(directory: Path) -> None:
    current = read_result(directory)
    if current["complete"] is True:
        return
    current.update(complete=True, timed_out_wait=True, comparison="incomplete")
    probe.write_json_atomic(Path(directory) / "result.json", current)


# ----------------------------------------------------------------------------------------------- the run
def load_settings(path: str) -> tuple[str, str, list[str]]:
    """(op path, token, three references) from the credentials settings file the tick uses. Never recorded."""
    try:
        document = json.loads(Path(path).read_text(encoding="utf-8"))
        token_file = Path(document["token_file"]).expanduser()
        references = document["references"]
        refs = [references[name] for name in NAMES]
        if not all(isinstance(ref, str) and ref.startswith("op://") for ref in refs):
            raise ValueError
        op = document.get("op") or shutil.which("op", path=os.environ.get("PATH"))
        token = token_file.read_text(encoding="utf-8").strip()
        if not op or not token:
            raise ValueError
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise CredentialSettingsInvalid from None
    return str(op), token, refs


def execute(directory: Path, credentials: str) -> None:
    result_path = directory / "result.json"
    book = LockedPidBook(directory)
    result = new_result()

    def save(complete: bool = False) -> None:
        if complete:
            for condition in result["conditions"]:
                condition["criteria"] = evaluate(condition)
            result["comparison"] = compare(result["conditions"], len(result["conditions"]) == 2
                                           and all(len(c["rounds"]) == ROUNDS for c in result["conditions"]))
        result["complete"] = complete
        probe.write_json_atomic(result_path, result)

    if MODE == "production" and any(name.startswith(("PROBE_", "FAKE_")) for name in os.environ):
        result.update(complete=True, aborted_class="AmbientOverrideRefused")
        probe.write_json_atomic(result_path, result)
        return
    try:
        op, token, references = load_settings(credentials)
        unconfirmed = False
        for name in CONDITIONS:
            home = None
            if name == "dedicated":
                home = dedicated_dir(directory / "op-home")
                if home is None:
                    raise UnsafeDedicatedPath
            condition = {"name": name, "baseline_op_count": count_op(), "rounds": [], "criteria": {}}
            result["conditions"].append(condition)
            save()
            last_end = None
            for number in range(ROUNDS):
                if unconfirmed:
                    break
                if last_end is not None:  # warm rounds start at least the gap after the previous round ended
                    time.sleep(max(0.0, WARM_GAP_S - (time.monotonic() - last_end)))
                condition["rounds"].append(run_round(
                    number, op, references, lambda: probe.op_environment(token, home), book, home))
                last_end = time.monotonic()
                unconfirmed = any(a["child_exit_unconfirmed"] for call in condition["rounds"][-1]["calls"]
                                  for a in call["attempts"])
                save()
            if unconfirmed:  # a child that may still run: no further round, no further condition
                break
        token = ""
        save(complete=True)
    except Exception as error:  # class name only, from a fixed list
        name = type(error).__name__
        result.update(aborted_class=name if name in ERROR_CLASSES else "Exception")
        for condition in result["conditions"]:
            condition["criteria"] = {}
        result.update(complete=True, comparison="incomplete")
        probe.write_json_atomic(result_path, result)


# ----------------------------------------------------------------------------------------------- the report
def report(directory: Path) -> int:
    result = read_result(directory)
    out = ["== S2 키 읽기 측정 결과 (측정일 뿐 — 채택·규칙 예외는 오빠 결정, 진단 성공은 운영 재개 승인이 아님) =="]
    out.append(f"mode={result['mode']}" + (f" 중단={result['aborted_class']}" if result["aborted_class"] else ""))
    cold_over = False
    unconfirmed = any(a["child_exit_unconfirmed"] for condition in result["conditions"] for r in condition["rounds"]
                      for call in r["calls"] for a in call["attempts"])
    for condition in result["conditions"]:
        crit = condition["criteria"]
        out.append(f"조건 {condition['name']}: 라운드 {len(condition['rounds'])}/{ROUNDS}")
        if crit:
            cold_over = cold_over or crit["cold_over_limit"]
            out.append("  첫 시도 성공 {first_try_success_count}/18 · 재시도 {retries_used} · 최대 시도 {max_attempt_ms}ms "
                       "· 최대 호출 {max_call_total_ms}ms".format(**crit))
            out.append("  op 프로세스 비증가={op_count_not_increased} 디스크 비증가={disk_not_increased} "
                       "기준 충족={meets_all}".format(**crit))
            out.append(f"  콜드 ms {crit['cold_ms']} · 웜 ms {crit['warm_ms']}")
    if result["timed_out_wait"]:
        out.append("결과 대기 시간 초과: timed_out_wait")
    out.append(f"비교: {result['comparison']} — {COMPARISON_TEXT[result['comparison']]}")
    if cold_over:
        out.append("콜드 시작 첫 시도가 7초 기한 안에 끝나지 않음(끝나는 시점은 알 수 없음) → 규칙 예외를 둘지는 오빠 결정 "
                   "(설계자는 상수를 키우지 않음 · 그동안 전용 경로 채택·운영 재개 판정은 보류)")
    if unconfirmed:
        out.append("자식 종료 미확인 — 측정을 거기서 멈춤(재시도·다음 라운드 없음) · 남은 프로세스 확인 필요")
    out.append("일 호출량: 논리 읽기 864회/일(288 틱 × 키 3) · 재시도 포함 CLI 시도 최대 1,728회/일 · "
               "실제 서비스 API 요청 수: 미확인(문서 확인 선행)")
    out.append("공통: consumer 는 disabled 유지")
    print("\n".join(out))
    return 0 if result["complete"] is True and result["comparison"] != "incomplete" else 1


def main(argv: list[str]) -> int:
    args = list(argv)
    credentials = ""
    for flag in ("--mode", "--credentials"):  # --mode was already read at import; --credentials is taken here
        if flag in args:
            index = args.index(flag)
            if flag == "--credentials" and index + 1 < len(args):
                credentials = args[index + 1]
            args = args[:index] + args[index + 2:]
    if len(args) != 2:
        sys.stderr.write("usage: s2.py --run DIR --mode M --credentials FILE | --close-timeout DIR | --report DIR\n")
        return 2
    mode, target = args
    if mode == "--run":
        execute(Path(target), credentials)
        return 0
    if mode == "--close-timeout":
        close_on_timeout(Path(target))
        return 0
    if mode == "--report":
        return report(Path(target))
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
