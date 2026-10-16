#!/usr/bin/env python3
"""Three-stage chain wrapper (design arch-20261015-opa-popup-design-r8 §4): N1 launchd probe -> N2 E1 terminal
table -> N3 the same E1 under ``taskpolicy -b``, run once by a human.

The reviewed tools (probe.sh, compare.sh) are called unchanged. A stage is started only when the previous one
passed its gate: the tool's exit code AND the closed-schema result JSON of *that* run (found by comparing the
result folder before and after the run: exactly one new candidate of the stage's own file type; the tool's
stdout is discarded and never parsed). The gate only decides "is the next measurement safe to start" — it is not
an interpretation of the result, and the observations this experiment looks for (a reaped P0 timeout, a TCC
unknown, a confirmed slow E1 round) are not errors.

Value-free by construction: only enums, numbers and booleans of validated result files are shown. Nothing is
written. No ``op`` process is ever signalled — a signal goes to the direct child tool only (``proc.send_signal``),
never to a group, and never again after the first one.

Exit codes: tool codes are passed on unchanged (a tool ended by signal N gives 128+N); 0 all stages passed,
2 refused to start, 5 a gate stopped the chain, 6 a tool overran its limit, 7 not enough time left for the next
stage (``skipped_budget``), 130/143/129 interrupted.
"""

from __future__ import annotations

import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import stat
import subprocess
import sys
import time

_SPEC = importlib.util.spec_from_file_location("compare_core", Path(__file__).with_name("compare.py"))
compare = importlib.util.module_from_spec(_SPEC)
sys.modules["compare_core"] = compare
_SPEC.loader.exec_module(compare)  # loads probe.py too; both read --mode from sys.argv exactly like the tools
probe = compare.probe

# Design §4.4: one canonical overall limit per plan, built from these parts (the tools keep their own 75 s).
STEP_S = probe.override_seconds("PROBE_CH_T_STEP", 75.0)          # a tool's own contract
TRANSITION_S = probe.override_seconds("PROBE_CH_T_TRANSITION", 3.0)   # result lookup + gate + display, local files only
SLOT_S = probe.override_seconds("PROBE_CH_T_SLOT", 80.0)         # one stage slot: tool limit + overrun watch
OVERRUN_S = probe.override_seconds("PROBE_CH_T_OVERRUN", 77.0)   # past this the tool broke its contract
GRACE_S = probe.override_seconds("PROBE_CH_T_GRACE", 3.0)        # wait after the one TERM
CANCEL_WAIT_S = probe.override_seconds("PROBE_CH_T_CANCEL", 16.0)  # the probe's clean-up (<= 15 s) after a signal
START_NEED_S = SLOT_S + TRANSITION_S
FINAL_S = 1.0  # the closing display

STAGE_TITLE = {"N1": "N1 launchd 프로브", "N2": "N2 터미널 op --version 6회", "N3": "N3 낮은 우선순위(taskpolicy -b) op --version 6회",
               "N4-A1": "N4-A1 launchd op --version (ProcessType=Background)",
               "N4-B": "N4-B launchd op --version (ProcessType 지정 안 함)",
               "N4-A2": "N4-A2 launchd op --version (ProcessType=Background)"}
# N4 (design r10 §4): three launchd probe runs with only `op --version`, Background -> unset -> Background. The value is
# "does the job's plist carry ProcessType=Background" for that stage.
N4_EXPECT = {"N4-A1": True, "N4-B": False, "N4-A2": True}
PLANS = {"full": ("N1", "N2", "N3"), "e1": ("N2", "N3"), "probe": ("N1",), "n4": tuple(N4_EXPECT)}
SIGNAL_CODE = {signal.SIGINT: 130, signal.SIGTERM: 143, signal.SIGHUP: 129}
PROBE_NAME = re.compile(r"^\d{8}-\d{6}-\d+-\d+$")
E1_NAME = re.compile(r"^compare-\d{8}-\d{6}-\d+-\d+\.result\.json$")
MAX_RESULT_BYTES = 1 << 20

E1_STATUSES = (*compare.RAN, "skipped_budget", "skipped_after_unconfirmed", "cancelled")
E1_CONDITIONS = ("fast", "slow", "mixed", "incomplete")
E1_EXIT_CLASSES = ("ran_all", "incomplete", "cancelled")
E1_TOP = ("v", "rounds", "conditions", "op_count_before", "op_count_after", "sock_mtime_changed",
          "removed_name_count_A", "leftover_check_required", "complete", "exit_class", "conclusion")
E1_ROUND = ("variant", "round", "status", "elapsed_ms", "rc", "reaped", "child_exit_unconfirmed")


def clock() -> float:
    return time.monotonic()


def plan_total(count: int) -> float:
    """The overall limit of a plan with ``count`` stages: every stage but the last takes its normal slot (tool
    limit + one transition); the last one must still be startable (83 s) and finish its overrun path."""
    return (count - 1) * (STEP_S + TRANSITION_S) + START_NEED_S + FINAL_S


class Cancelled(BaseException):
    """Raised by the signal handler (once). ``left`` says whether the forwarded-to tool was still running."""

    def __init__(self, signum: int):
        super().__init__(signum)
        self.signum = signum
        self.left = False


def build_tools(here: Path, python: str) -> dict[str, list[str]]:
    probe_sh, compare_sh = str(here / "probe.sh"), str(here / "compare.sh")
    p0 = ["/bin/bash", probe_sh, "--python", python, "--p0-only", "--process-type"]
    return {"N1": ["/bin/bash", probe_sh, "--python", python],
            "N2": ["/bin/bash", compare_sh, "--python", python],
            "N3": ["/usr/sbin/taskpolicy", "-b", "/bin/bash", compare_sh, "--python", python],
            "N4-A1": [*p0, "background"], "N4-B": [*p0, "unset"], "N4-A2": [*p0, "background"]}


# ----------------------------------------------------------------------------------------------- the gates
def _int(value) -> bool:
    return type(value) is int


def _int_or_none(value) -> bool:
    return value is None or _int(value)


def _bool(value) -> bool:
    return type(value) is bool


def valid_e1(doc) -> bool:
    """Strict closed schema of the E1 result: exact keys, finite enumerations, no free text anywhere."""
    if not isinstance(doc, dict) or set(doc) != set(E1_TOP):
        return False
    if doc["v"] != 1 or not _int(doc["v"]) or not _bool(doc["sock_mtime_changed"]):
        return False
    if not (_int_or_none(doc["op_count_before"]) and _int_or_none(doc["op_count_after"])
            and _int(doc["removed_name_count_A"]) and _bool(doc["leftover_check_required"])
            and _bool(doc["complete"])):
        return False
    if doc["exit_class"] is not None and doc["exit_class"] not in E1_EXIT_CLASSES:
        return False
    if doc["conclusion"] is not None and doc["conclusion"] not in compare.CONCLUSION_TEXT:
        return False
    conditions = doc["conditions"]
    if not isinstance(conditions, dict) or set(conditions) != {"A", "B", "C"} \
            or any(v not in E1_CONDITIONS for v in conditions.values()):
        return False
    rounds = doc["rounds"]
    if not isinstance(rounds, list) or len(rounds) > len(compare.PLAN):
        return False
    for item in rounds:
        if not isinstance(item, dict) or set(item) != set(E1_ROUND):
            return False
        if item["variant"] not in ("A", "B", "C") or item["round"] not in (1, 2) or not _int(item["round"]):
            return False
        if item["status"] not in E1_STATUSES or not _int_or_none(item["elapsed_ms"]) or not _int_or_none(item["rc"]):
            return False
        if not _bool(item["reaped"]) or not _bool(item["child_exit_unconfirmed"]):
            return False
    return True


def gate_probe(doc) -> str | None:
    """G1: None = the next stage may start, otherwise a value-free reason."""
    if not probe.validate_result(doc):
        return "result_schema"
    if (doc["complete"] is not True or doc["aborted_class"] is not None or doc["timed_out_wait"]
            or doc["conclusion"] == "observation_unknown"):
        return "probe_incomplete"
    executed = [s for s in doc["steps"] if not s["status"].startswith("skipped")]
    if any(s["child_exit_unconfirmed"] or s["descendants_may_hold_pipe"]
           or (s["child_pid"] is not None and not s["reaped"]) for s in executed):
        return "probe_exit_unconfirmed"
    if any(s["status"] in ("spawn_error", "observation_unknown", "unsupported") for s in executed):
        return "probe_step_error"
    return None


def gate_e1(doc) -> str | None:
    """G2/G3: None = the next stage may start, otherwise a value-free reason."""
    if not valid_e1(doc):
        return "result_schema"
    rounds = doc["rounds"]
    ran = [r for r in rounds if r["status"] in ("success", "timeout")]
    if (doc["conclusion"] == "incomplete_exit_unconfirmed"
            or any(r["child_exit_unconfirmed"] or not r["reaped"] for r in ran)):
        return "e1_exit_unconfirmed"
    if (doc["complete"] is not True or doc["exit_class"] != "ran_all" or len(rounds) != len(compare.PLAN)
            or doc["conclusion"] in ("cancelled_incomplete", "incomplete_missing_rounds")
            or any(r["status"].startswith("skipped_") or r["status"] == "cancelled" for r in rounds)):
        return "e1_incomplete"
    if doc["leftover_check_required"]:
        return "e1_leftover_check_required"
    before, after = doc["op_count_before"], doc["op_count_after"]
    if before is None or after is None or before != after:   # None == None is no proof of anything
        return "e1_count_changed"
    if doc["conclusion"] == "inconclusive_error" or any(r["status"] not in ("success", "timeout") for r in rounds):
        return "e1_inconclusive_error"
    return None


PROFILE_KEYS = {"profile_version", "profile", "process_type_set", "load_before", "load_after"}
N4_SKIPPED = ("P2", "P1", "P1b")


def _load_ok(value) -> bool:
    return value is None or (isinstance(value, list) and len(value) == 3 and all(
        type(x) in (int, float) and math.isfinite(x) and 0 <= x < 10000 for x in value))


def read_profile(directory: Path) -> tuple[str | None, dict | None]:
    """(reason, document): profile.json of this run, closed schema (design r10 §4.3). Never followed through a symlink."""
    path = directory / "profile.json"
    if not _regular_file(path):
        return "profile_missing", None
    try:
        if os.lstat(path).st_size > MAX_RESULT_BYTES:
            return "profile_schema", None
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "profile_schema", None
    if (not isinstance(document, dict) or set(document) != PROFILE_KEYS or type(document["profile_version"]) is not int
            or document["profile_version"] != 1 or document["profile"] != "p0only"
            or type(document["process_type_set"]) is not bool or not _load_ok(document["load_before"])
            or not _load_ok(document["load_after"])):
        return "profile_schema", None
    return None, document


def plist_process_type(directory: Path) -> tuple[bool, object]:
    """(readable, value): what the job plist says about the top-level ProcessType key, read as a structure — the value
    as it is (None when the key is absent). An unreadable file or a plist that is not a dictionary is (False, None).
    Nothing else of the file is kept."""
    path = directory / "job.plist"
    if not _regular_file(path):
        return False, None
    try:
        if os.lstat(path).st_size > MAX_RESULT_BYTES:
            return False, None
        document = plistlib.loads(path.read_bytes())
    except Exception:  # a broken plist can end in several parser errors; every one of them means "cannot compare"
        return False, None
    if not isinstance(document, dict):
        return False, None
    return True, document.get("ProcessType")


def gate_n4(directory: Path, doc, expect_set: bool) -> str | None:
    """G4 (design r10 §4.4): None = the next stage may start. Exit code was checked by the caller; here the closed
    result, the executed steps, the no-token profile and profile.json against the job plist."""
    reason = gate_probe(doc)
    if reason is not None:
        return reason
    # The shared validator checks every entry but not the array: N4 needs exactly P4, P0, P2, P1, P1b, once each (a
    # repeated or missing entry would hide a step that ran, because the lookup below keeps only the last of a name).
    if sorted(s["step"] for s in doc["steps"]) != sorted(probe.STEPS):
        return "result_schema"
    by = {s["step"]: s for s in doc["steps"]}
    p0 = by.get("P0")
    if p0 is None or p0["status"] not in ("success", "timeout") or (p0["status"] == "timeout" and not p0["reaped"]):
        return "p0_not_tabulable"
    for name in N4_SKIPPED:
        s = by.get(name)
        if (s is None or s["status"] != "skipped_not_applicable" or s["account_type_confirmed"] is not None
                or s["child_pid"] is not None):
            return "profile_violation"
    reason, profile = read_profile(directory)
    if reason is not None:
        return reason
    readable, found = plist_process_type(directory)
    # A: the top-level value is exactly "Background"; B: the key is not there at all (a plist cannot hold None, so
    # None means absent; a key with any value is a mismatch)
    on_plist = readable and (found == "Background" if expect_set else found is None)
    if profile["process_type_set"] is not expect_set or not on_plist:
        return "profile_mismatch"
    return None


N4_READING = {
    "association": ("ProcessType 지정 여부와 연관된 관측입니다(연관 라벨). 지정 안 함은 시스템 기본(Standard, 가벼운 제한 있음)이며 "
                    "자원 제한이 없는 상태가 아닙니다. 원인 확정 아님 · 순서·시간 간격 효과는 통제하지 못했습니다."),
    "not_removed_by_the_key": ("키를 제거만 해서는 이번 재현이 사라지지 않았습니다. 이 결과로 L1(우선순위·자원 정책 가설)의 단독 작용을 "
                               "판정하지 않으며 L2·L5·L7 도 확정이 아닙니다."),
    "not_reproduced": "이번 3회에서는 재현되지 않았습니다 — 시간·부하·상태 후보가 열려 있습니다. 재현되지 않음은 해결이 아님.",
    "hold": "해석 보류 — 이 조합은 표의 행이 아닙니다(같은 3단계를 한 번 더 할지는 별도 판단).",
}
N4_NOTE = ("A-B-A 한계: B 가 한 번이라 순간 부하·캐시·다른 사용자 상태가 고정되지 않았고 전후 부하 값은 통제 증거가 아니라 참고 "
           "기록입니다. 운영 plist 의 ProcessType 변경은 어떤 결과든 별도 설계·DA·오빠 판정 뒤에만 합니다.")


def n4_reading(observations: list[tuple[str, str]]) -> tuple[str, list[str]]:
    """(row key, lines) of the design r10 §4.6 table for the (P4, P0) status of the three stages A1, B, A2. The table is
    only read when P4 was success in every stage; every other combination is "hold"."""
    if any(p4 != "success" for p4, _ in observations):
        return "hold", ["해석 보류(네트워크 도달 조건 P4 가 단계마다 success 가 아니라 표를 읽지 않습니다) · " + N4_NOTE]
    p0s = tuple(p0 for _, p0 in observations)
    key = {("timeout", "success", "timeout"): "association", ("timeout", "timeout", "timeout"): "not_removed_by_the_key",
           ("success", "success", "success"): "not_reproduced"}.get(p0s, "hold")
    return key, [N4_READING[key], N4_NOTE]


# --------------------------------------------------------------------------------------- the result lookup
def listing(base: Path) -> set[str]:
    try:
        return set(os.listdir(base))
    except OSError:
        return set()


def _regular_file(path: Path) -> bool:
    try:
        info = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISREG(info.st_mode)


def _candidates(base: Path, new: set[str], name: str) -> list[Path]:
    """New entries of this stage's own file type only (a kept temp HOME folder of E1 is never a candidate)."""
    found = []
    for entry in sorted(new):
        path = base / entry
        if name == "N1" or name in N4_EXPECT:
            try:
                is_dir = PROBE_NAME.match(entry) and stat.S_ISDIR(os.lstat(path).st_mode)
            except OSError:
                continue
            if is_dir:
                found.append(path / "result.json")
        elif E1_NAME.match(entry) and _regular_file(path):
            found.append(path)
    return found


n4_seen: dict[str, tuple[str, str]] = {}   # (P4, P0) status of the N4 stages that passed their gate in this run


def check_stage(name: str, base: Path, before: set[str]) -> tuple[str | None, list[str], str]:
    """(stop reason or None, summary lines, observation label) from the closed-schema result of this run."""
    found = _candidates(base, listing(base) - before, name)
    if not found:
        return "result_missing", [], "-"
    if len(found) > 1:
        return "result_ambiguous", [], "-"
    path = found[0]
    if not _regular_file(path):
        return "result_missing", [], "-"
    try:
        if os.lstat(path).st_size > MAX_RESULT_BYTES:
            return "result_unreadable", [], "-"
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "result_unreadable", [], "-"
    if name in N4_EXPECT:
        reason, lines, label = gate_n4(path.parent, document, N4_EXPECT[name]), [], "-"
        if probe.validate_result(document):
            by = {s["step"]: s for s in document["steps"]}
            p4, p0 = (by.get(n, {}).get("status", "not_run") for n in ("P4", "P0"))
            n4_seen[name] = (p4, p0)
            label = f"P4={p4} P0={p0}"
            lines = ["P4 {a} · P0 {b} {ms}ms · 결론 {c}".format(a=p4, b=p0, ms=by.get("P0", {}).get("elapsed_ms", 0),
                                                            c=document["conclusion"])]
        return reason, lines, label
    if name == "N1":
        reason, lines, label = gate_probe(document), [], "-"
        if probe.validate_result(document):
            lines = ["결론 {c} · ".format(c=document["conclusion"]) + " · ".join(
                f"{s['step']} {s['status']} {s['elapsed_ms']}ms" for s in document["steps"])]
            p0 = next((s for s in document["steps"] if s["step"] == "P0"), None)
            label = f"P0={p0['status']}" if p0 else "P0=not_run"
        return reason, lines, label
    reason, lines, label = gate_e1(document), [], "-"
    if valid_e1(document):
        lines = ["결론 {c} · 조건 A={A} B={B} C={C} · ".format(c=document["conclusion"], **document["conditions"])
                 + " · ".join(f"{r['variant']}{r['round']} {r['status']} {r['elapsed_ms']}ms" for r in document["rounds"]),
                 f"전후 op 프로세스 수 {document['op_count_before']} → {document['op_count_after']}"]
        label = f"{document['conclusion']}"
    return reason, lines, label


# ------------------------------------------------------------------------------------------------ one tool
def run_tool(argv: list[str], env: dict[str, str]) -> dict:
    """Run one tool (output discarded). Past OVERRUN_S the direct tool process gets one TERM and GRACE_S to leave;
    after that it is left alone (reported, never signalled again). A signal to this process is forwarded once, to
    the direct tool child only."""
    proc = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, close_fds=True)
    try:
        try:
            return {"rc": proc.wait(timeout=OVERRUN_S), "overran": False, "left": False}
        except subprocess.TimeoutExpired:
            pass
        proc.send_signal(signal.SIGTERM)
        try:
            return {"rc": proc.wait(timeout=GRACE_S), "overran": True, "left": False}
        except subprocess.TimeoutExpired:
            return {"rc": None, "overran": True, "left": True}
    except Cancelled as stop:
        if proc.poll() is None:
            proc.send_signal(stop.signum)
            try:
                proc.wait(timeout=CANCEL_WAIT_S)
            except subprocess.TimeoutExpired:
                pass
        stop.left = proc.poll() is None
        raise


def exit_code_of(rc: int) -> int:
    return 128 - rc if rc < 0 else rc


# ----------------------------------------------------------------------------------------------- the run
def say(text: str) -> None:
    sys.stdout.write(text + "\n")
    sys.stdout.flush()


def refuse(message: str) -> int:
    say(message)
    return 2


def main(argv: list[str]) -> int:
    begin = clock()
    args = list(argv)
    if "--mode" in args:  # the explicit mode argument was already read at import
        index = args.index("--mode")
        args = args[:index] + args[index + 2:]
    python, plan = "", "full"
    while args:
        flag = args.pop(0)
        if flag == "--python" and args:
            python = args.pop(0)
        elif flag == "--plan" and args and args[0] in PLANS:
            plan = args.pop(0)
        else:
            return refuse("usage: chain.py --mode production|selftest --python <absolute python> [--plan full|e1|probe]")
    if not os.path.isabs(python):
        return refuse("python 의 절대경로가 필요합니다. 시작하지 않습니다.")
    if probe.SELFTEST and os.environ.get("PROBE_CH_TOOLS"):
        try:
            tools = json.loads(os.environ["PROBE_CH_TOOLS"])
        except ValueError:
            return refuse("시험용 도구 목록이 올바르지 않습니다. 시작하지 않습니다.")
    else:
        tools = build_tools(Path(__file__).resolve().parent, python)
    stages = PLANS[plan]
    for name in stages:
        first = tools.get(name, [""])[0]
        if not (os.path.isabs(first) and os.path.isfile(first) and os.access(first, os.X_OK)):
            return refuse(f"{name} 의 실행 파일을 찾을 수 없습니다. 아무것도 실행하지 않고 시작하지 않습니다.")
    base = Path(probe.override("PROBE_BASE", os.path.join(os.path.expanduser("~"), ".local", "share", "airag-probe")))
    if base.is_symlink() or base.parent.is_symlink():
        return refuse("점검 폴더의 위치가 심링크입니다. 시작하지 않습니다.")

    total = plan_total(len(stages))
    state: dict = {"signal": None, "finalizing": False}

    def on_signal(signum, _frame):
        if state["finalizing"] or state["signal"] is not None:
            return
        state["signal"] = signum
        raise Cancelled(signum)

    previous = {sig: signal.signal(sig, on_signal) for sig in SIGNAL_CODE}
    labels: list[str] = []
    code = 0
    n4_seen.clear()
    say(f"3단계 연속 점검 시작 — 계획 {plan}, 전체 상한 {int(total)}초. 앞 단계에서 이상이 확인되면 뒤 단계는 실행하지 않습니다.")
    try:
        try:
            for name in stages:
                if total - (clock() - begin) < START_NEED_S:
                    say(f"[{STAGE_TITLE[name]}] skipped_budget — 남은 시간이 {int(START_NEED_S)}초 미만이라 시작하지 않습니다.")
                    code = 7
                    break
                before = listing(base)
                say(f"[{STAGE_TITLE[name]}] 실행 중 (도구 상한 {int(STEP_S)}초)")
                outcome = run_tool(tools[name], dict(os.environ))
                if outcome["overran"]:
                    say(f"[{STAGE_TITLE[name]}] 도구가 {int(OVERRUN_S)}초를 넘겨 종료 신호를 한 번 보냈습니다. 뒤 단계는 실행하지 않습니다.")
                    if outcome["left"]:
                        say("남은 것 확인 필요: 도구 프로세스가 아직 남아 있을 수 있습니다(더 이상 신호를 보내지 않음).")
                    code = 6
                    break
                if outcome["rc"] != 0:
                    code = exit_code_of(outcome["rc"])
                    say(f"[{STAGE_TITLE[name]}] 도구 종료코드 {code} — 멈춥니다(뒤 단계 미실행).")
                    break
                reason, lines, label = check_stage(name, base, before)
                labels.append(f"{name}: {label}")
                for line in lines:
                    say(f"  {line}")
                clock_left = total - (clock() - begin)
                if reason is not None:
                    say(f"[{STAGE_TITLE[name]}] 중단 사유: {reason} — 뒤 단계는 실행하지 않습니다.")
                    code = 5
                    break
                say(f"[{STAGE_TITLE[name]}] 통과 (남은 시간 {int(clock_left)}초)")
        except Cancelled as stop:
            code = SIGNAL_CODE.get(stop.signum, 130)
            say(f"중단 신호({code})를 받았습니다. 진행 중이던 도구는 스스로 정리하고, 남은 단계는 실행하지 않습니다.")
            if stop.left:
                say("남은 것 확인 필요: 도구 프로세스가 아직 남아 있을 수 있습니다(더 이상 신호를 보내지 않음).")
    finally:
        state["finalizing"] = True
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    if labels and plan == "n4":
        say("관측 라벨(해석은 설계 r10 §4.6 표로만 · 원인 확정 아님): " + " | ".join(labels))
        if code == 0 and all(name in n4_seen for name in stages):
            for line in n4_reading([n4_seen[name] for name in stages])[1]:
                say(f"  {line}")
    elif labels:
        say("관측 라벨(해석은 설계 r8 §4.6 표로만 · 원인 확정 아님): " + " | ".join(labels))
    say("consumer 는 계속 disabled 입니다.")
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
