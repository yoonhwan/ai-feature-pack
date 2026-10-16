"""Pass trace (design r17 section 4, errata 1 sections 2-3, errata 2 sections 1, 2 and 6).

Everything here is synthetic: fake adapters, a fake clock, tmp files. The behavior-unchanged claim is checked on what
the wrapped function returns or raises (the same object) and on the pass result; the trace file is read with the
documented reader rule (whole lines only, schema-valid only).
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import threading
import types

import pytest

from airag_consumer import _pass_trace as pass_trace
from airag_consumer import tick
from airag_consumer._pass_trace import Trace, install, wrap_call, wrap_window
from test_tick import KEYS, base_environment, run_tick, synthetic_service


class Clock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


def read_rows(path):
    """The reader rule: only newline-terminated lines count, and only those inside the closed schema."""
    parts = Path(path).read_bytes().split(b"\n")[:-1]
    rows = []
    for part in parts:
        if not part:
            continue
        try:
            row = json.loads(part)
        except ValueError:
            continue
        if pass_trace._valid(row):
            rows.append(row)
    return rows


@pytest.fixture
def trace_path(tmp_path):
    return tmp_path / "pass-trace.jsonl"


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def trace(trace_path, clock):
    made = Trace(trace_path, clock=clock)
    assert made.active
    return made


def fake_adapter(result=None, error=None):
    seen = []

    def adapter(cfg, path, body_obj, *, base=None):
        seen.append((cfg, path, body_obj, base))
        if error is not None:
            raise error
        return result

    return adapter, seen


class Coded(Exception):
    def __init__(self, code):
        super().__init__("MARKER_MESSAGE")
        self.code = code


# ---- the wrapper is a pass-through -----------------------------------------------------------------------------


def test_wrapper_returns_the_same_object_and_passes_every_argument(trace):
    sentinel = object()
    adapter, seen = fake_adapter(result=sentinel)
    owner = types.SimpleNamespace(adapter=adapter)
    assert wrap_call(trace, owner, "adapter", "llm", tokenize=True)
    assert owner.adapter("cfg", "/tokenize", {"a": 1}, base="b") is sentinel
    assert seen == [("cfg", "/tokenize", {"a": 1}, "b")]
    assert owner.adapter.__wrapped__ is adapter


@pytest.mark.parametrize("raised", [ValueError("x"), Coded("PROVIDER_TIMEOUT"), KeyboardInterrupt(), SystemExit(3)])
def test_business_exceptions_are_reraised_as_the_same_object(trace, trace_path, raised):
    adapter, _ = fake_adapter(error=raised)
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm", tokenize=True)
    with pytest.raises(type(raised)) as info:
        owner.adapter("cfg", "/chat/completions", {})
    assert info.value is raised
    rows = read_rows(trace_path)
    assert [row["ph"] for row in rows] == ["b", "e"] and rows[1]["out"] in pass_trace.CALL_OUTCOMES


@pytest.mark.parametrize("code, outcome", [
    ("PROVIDER_TIMEOUT", "timeout"), ("PROVIDER_UNREACHABLE", "unreachable"), ("PROVIDER_UNAVAILABLE", "unreachable"),
    ("PROVIDER_HTTP_ERROR", "http_error"), ("PROVIDER_RATE_LIMITED", "http_error"),
    ("PROVIDER_SERVER_ERROR", "http_error"), ("PROVIDER_REQUEST_ERROR", "http_error"),
    ("PROVIDER_BAD_RESPONSE", "error"), ("SOMETHING_ELSE", "error"), (7, "error"), (None, "error"),
])
def test_outcome_is_classified_from_the_error_code_only(trace, trace_path, code, outcome):
    adapter, _ = fake_adapter(error=Coded(code))
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm")
    with pytest.raises(Coded):
        owner.adapter("cfg", "/chat/completions", {})
    assert read_rows(trace_path)[1]["out"] == outcome


def test_an_error_without_a_code_is_an_error_outcome(trace, trace_path):
    adapter, _ = fake_adapter(error=RuntimeError("MARKER_MESSAGE"))
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "other")
    with pytest.raises(RuntimeError):
        owner.adapter("cfg", "/x", {})
    assert read_rows(trace_path)[1]["out"] == "error"


def test_tokenize_flag_uses_the_bound_path_only(trace, trace_path):
    adapter, _ = fake_adapter(result={})
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm", tokenize=True)
    owner.adapter("cfg", "/tokenize", {})  # positional
    owner.adapter("cfg", path="/tokenize", body_obj={})  # keyword
    owner.adapter("cfg", "/chat/completions", {})
    owner.adapter("/tokenize", "/chat/completions", {})  # cfg happens to equal the tokenize path: only path counts
    begins = [row["tok"] for row in read_rows(trace_path) if row["ph"] == "b"]
    assert begins == [True, True, False, False]


def test_a_signature_that_cannot_be_bound_stops_the_trace_not_the_call(trace, trace_path):
    adapter, seen = fake_adapter(result="done")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm", tokenize=True)
    with pytest.raises(TypeError):  # raised by the original call itself, not by the trace
        owner.adapter("cfg")
    assert not trace.active and seen == []
    assert owner.adapter("cfg", "/tokenize", {}) == "done"
    assert read_rows(trace_path) == []


def test_wrapping_is_refused_for_a_missing_or_differently_shaped_target(trace):
    owner = types.SimpleNamespace(plain=lambda: None, other=lambda x: x, number=3)
    original = owner.other
    assert wrap_call(trace, owner, "missing", "llm") is False
    assert wrap_call(trace, owner, "number", "llm") is False
    assert wrap_call(trace, owner, "other", "llm", tokenize=True) is False  # no `path` parameter
    assert owner.other is original
    assert wrap_window(trace, owner, "missing") is False


def test_a_whole_call_includes_the_reading_of_the_body(trace, trace_path, clock):
    def adapter(cfg, path, body_obj):
        clock.advance(2.5)  # the time is spent after the transport call returned, while the body is read
        return {}

    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm")
    owner.adapter("cfg", "/x", {})
    begin, end = read_rows(trace_path)
    assert end["t"] - begin["t"] == pytest.approx(2.5)


# ---- the line format ---------------------------------------------------------------------------------------------


def test_lines_follow_the_closed_schema_and_stay_value_free(trace, trace_path, clock):
    adapter, _ = fake_adapter(result={})
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "embed")
    owner.adapter("MARKER_CFG_VALUE", "MARKER_PATH_VALUE", {"input": "MARKER_BODY_VALUE"}, base="MARKER_BASE")
    clock.advance(0.25)
    owner.adapter("MARKER_CFG_VALUE", "MARKER_PATH_VALUE", {})
    raw = trace_path.read_bytes()
    assert b"MARKER" not in raw
    assert stat.S_IMODE(trace_path.stat().st_mode) == 0o600
    assert raw.endswith(b"\n") and all(len(line) + 1 <= pass_trace.LINE_MAX_BYTES for line in raw.split(b"\n")[:-1])
    rows = read_rows(trace_path)
    assert [set(row) for row in rows[:2]] == [
        {"v", "n", "ph", "name", "tok", "t"}, {"v", "n", "ph", "name", "tok", "t", "out"},
    ]
    assert rows[0]["n"] == rows[1]["n"] == 0 and rows[2]["n"] == rows[3]["n"] == 1
    assert {row["name"] for row in rows} == {"embed"} and {row["tok"] for row in rows} == {False}
    assert all(type(row["t"]) is float for row in rows) and rows[2]["t"] == pytest.approx(0.25)


GOOD = {
    "b": {"v": 1, "n": 0, "ph": "b", "name": "llm", "tok": False, "t": 0.0},
    "e": {"v": 1, "n": 0, "ph": "e", "name": "llm", "tok": True, "t": 1.5, "out": "ok"},
    "wb": {"v": 1, "i": 0, "ph": "wb", "t": 0.0},
    "we": {"v": 1, "i": 3, "ph": "we", "t": 2.0, "out": "fail"},
    "x": {"v": 1, "ph": "x", "t": 3.0, "rsn": "cap_lines"},
}


@pytest.mark.parametrize("phase", sorted(GOOD))
def test_every_good_record_is_valid_with_and_without_the_dropped_counter(phase):
    assert pass_trace._valid(GOOD[phase])
    assert pass_trace._valid({**GOOD[phase], "d": 5})


@pytest.mark.parametrize("phase, change", [
    ("b", {"extra": 1}), ("b", {"v": True}), ("b", {"v": 2}), ("b", {"t": 1}), ("b", {"t": -0.1}),
    ("b", {"t": 86_400.5}), ("b", {"t": float("nan")}), ("b", {"name": "http"}), ("b", {"n": 100_000}),
    ("b", {"n": True}), ("b", {"tok": 1}), ("b", {"out": "ok"}), ("b", {"i": 0}), ("b", {"d": 0}),
    ("b", {"d": 100_000}), ("b", {"d": True}), ("e", {"out": "boom"}), ("e", {"out": None}),
    ("wb", {"n": 0}), ("wb", {"out": "ok"}), ("wb", {"i": 10_000}), ("we", {"out": "timeout"}), ("we", {"name": "llm"}),
    ("x", {"rsn": "other"}), ("x", {"n": 0}), ("x", {"out": "ok"}),
])
def test_records_outside_the_closed_schema_are_rejected(phase, change):
    assert not pass_trace._valid({**GOOD[phase], **change})


@pytest.mark.parametrize("phase, missing", [
    ("b", "name"), ("b", "tok"), ("b", "n"), ("e", "out"), ("we", "out"), ("wb", "i"), ("x", "rsn"),
])
def test_records_missing_a_required_field_are_rejected(phase, missing):
    record = dict(GOOD[phase])
    del record[missing]
    assert not pass_trace._valid(record)


def test_non_dict_records_are_rejected():
    assert not any(pass_trace._valid(value) for value in (None, [], "b", 3, ("v", 1)))


def test_size_constants_keep_the_stop_line_reserve():
    assert pass_trace.EVENT_LINES_MAX + 8 == pass_trace.LINES_MAX == 2048
    assert pass_trace.EVENT_BYTES_MAX + 1024 == pass_trace.FILE_MAX_BYTES == 384 * 1024
    assert pass_trace.LINE_MAX_BYTES == 192 and pass_trace.STOP_LINE_MAX_BYTES == 96


def test_the_widest_lines_fit_their_byte_limits():
    widest_call = {"v": 1, "n": 99_999, "ph": "e", "name": "embed", "tok": False, "t": 86_400.0,
                   "out": "unreachable", "d": 99_999}
    assert pass_trace._encode(widest_call) is not None
    stop = pass_trace._encode({"v": 1, "ph": "x", "t": 86_400.0, "rsn": "write_error", "d": 99_999})
    assert stop is not None and len(stop) + 1 <= pass_trace.STOP_LINE_MAX_BYTES


# ---- the trace file contract -------------------------------------------------------------------------------------


def test_first_pass_creates_the_file_without_a_previous_generation(tmp_path, trace_path):
    made = Trace(trace_path)
    assert made.active and trace_path.is_file() and not Path(str(trace_path) + ".prev").exists()
    assert stat.S_IMODE(trace_path.stat().st_mode) == 0o600


def test_an_existing_trace_is_rotated_to_one_previous_generation(tmp_path, trace_path):
    trace_path.write_text("old\n", encoding="utf-8")
    made = Trace(trace_path)
    assert made.active
    assert Path(str(trace_path) + ".prev").read_text(encoding="utf-8") == "old\n"
    assert trace_path.read_bytes() == b""


def test_a_symlinked_trace_is_not_followed_and_the_pass_work_is_unchanged(tmp_path, trace_path):
    victim = tmp_path / "victim.txt"
    victim.write_text("keep\n", encoding="utf-8")
    trace_path.symlink_to(victim)
    made = Trace(trace_path)
    assert not made.active and victim.read_text(encoding="utf-8") == "keep\n" and trace_path.is_symlink()
    adapter, _ = fake_adapter(result="same")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(made, owner, "adapter", "llm")
    assert owner.adapter("cfg", "/x", {}) == "same"
    assert victim.read_text(encoding="utf-8") == "keep\n"


def test_a_directory_at_the_trace_path_disables_the_trace(tmp_path, trace_path):
    trace_path.mkdir()
    assert not Trace(trace_path).active and trace_path.is_dir()


def test_a_previous_generation_that_cannot_be_replaced_disables_the_trace(tmp_path, trace_path):
    trace_path.write_text("old\n", encoding="utf-8")
    Path(str(trace_path) + ".prev").mkdir()
    assert not Trace(trace_path).active and trace_path.read_text(encoding="utf-8") == "old\n"


def test_a_missing_directory_disables_the_trace_without_raising(tmp_path):
    assert not Trace(tmp_path / "absent" / "pass-trace.jsonl").active


# ---- failures never reach the work -------------------------------------------------------------------------------


def selective_write(trace, behavior):
    real = os.write

    def write(fd, data):
        if fd == trace._fd:
            return behavior(real, fd, data)
        return real(fd, data)

    return write


def test_a_write_error_turns_the_trace_off_and_the_call_goes_on(trace, trace_path, monkeypatch):
    def broken(real, fd, data):
        raise OSError(28, "MARKER_DISK")

    monkeypatch.setattr(os, "write", selective_write(trace, broken))
    adapter, _ = fake_adapter(result="ok-result")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm")
    assert owner.adapter("cfg", "/x", {}) == "ok-result"
    assert owner.adapter("cfg", "/x", {}) == "ok-result"
    assert not trace.active


def test_a_short_write_leaves_a_fragment_and_the_stop_line_starts_on_its_own_line(trace, trace_path, monkeypatch):
    done = []

    def short_once(real, fd, data):
        if not done:
            done.append(1)
            return real(fd, data[: len(data) // 2])
        return real(fd, data)

    monkeypatch.setattr(os, "write", selective_write(trace, short_once))
    adapter, _ = fake_adapter(result="r")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(trace, owner, "adapter", "llm")
    assert owner.adapter("cfg", "/x", {}) == "r"
    assert owner.adapter("cfg", "/x", {}) == "r"
    raw = trace_path.read_bytes()
    first = raw.split(b"\n")[0]
    with pytest.raises(ValueError):
        json.loads(first)  # the fragment is not a line
    rows = read_rows(trace_path)
    assert [row["ph"] for row in rows] == ["x"] and rows[0]["rsn"] == "write_error"  # the fragment did not eat it
    assert not trace.active


def test_line_cap_writes_one_stop_line_and_nothing_after(tmp_path, trace_path, monkeypatch):
    monkeypatch.setattr(pass_trace, "EVENT_LINES_MAX", 3)
    made = Trace(trace_path)
    adapter, _ = fake_adapter(result="r")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(made, owner, "adapter", "llm")
    for _ in range(4):
        assert owner.adapter("cfg", "/x", {}) == "r"
    rows = read_rows(trace_path)
    assert [(row["ph"], row.get("n")) for row in rows] == [("b", 0), ("e", 0), ("b", 1), ("x", None)]
    assert rows[-1]["rsn"] == "cap_lines" and not made.active


def test_byte_cap_writes_one_stop_line_within_the_reserve(tmp_path, trace_path, monkeypatch):
    monkeypatch.setattr(pass_trace, "EVENT_BYTES_MAX", 200)
    made = Trace(trace_path)
    adapter, _ = fake_adapter(result="r")
    owner = types.SimpleNamespace(adapter=adapter)
    wrap_call(made, owner, "adapter", "llm")
    for _ in range(4):
        owner.adapter("cfg", "/x", {})
    rows = read_rows(trace_path)
    assert rows[-1]["ph"] == "x" and rows[-1]["rsn"] == "cap_bytes" and not made.active
    assert trace_path.stat().st_size <= 200 + pass_trace.STOP_LINE_MAX_BYTES


def test_an_invalid_line_is_skipped_and_counted_as_missing(trace, trace_path):
    token = trace.begin_call("not-a-name", False)  # outside the schema: not written
    trace.end_call((token[0], "llm", False), "ok")
    rows = read_rows(trace_path)
    assert [row["ph"] for row in rows] == ["e"] and rows[0]["d"] == 1


def test_a_busy_lock_drops_the_event_without_waiting_and_marks_the_next_line(trace, trace_path):
    holder = trace._lock
    holder.acquire()
    result = []
    worker = threading.Thread(target=lambda: result.append(trace.begin_call("llm", False)))
    worker.start()
    worker.join(timeout=5)
    stuck = worker.is_alive()
    holder.release()
    worker.join(timeout=5)
    assert not stuck  # a business thread never waits behind the trace lock
    trace.end_call(result[0], "ok")
    rows = read_rows(trace_path)
    assert [row["ph"] for row in rows] == ["e"] and rows[0]["d"] == 1


def test_call_numbers_are_unique_across_threads_and_every_event_is_written_or_counted(trace, trace_path):
    tokens, guard = [], threading.Lock()

    def work():
        for _ in range(25):
            token = trace.begin_call("llm", False)
            trace.end_call(token, "ok")
            with guard:
                tokens.append(token)

    threads = [threading.Thread(target=work) for _ in range(8)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)
    assert len({token[0] for token in tokens}) == 200
    rows = read_rows(trace_path)
    assert len(rows) + len(trace._drops) == 400  # nothing is lost silently: written or counted
    assert all(pass_trace._valid(row) for row in rows)


# ---- windows -------------------------------------------------------------------------------------------------------


def test_each_window_gets_a_start_and_end_pair_with_its_outcome(trace, trace_path):
    outcomes = iter([{"ok": True}, {"ok": False}, ValueError("boom"), "not a dict"])

    def publish(*args, **kwargs):
        value = next(outcomes)
        if isinstance(value, Exception):
            raise value
        return value

    owner = types.SimpleNamespace(publish=publish)
    assert wrap_window(trace, owner, "publish")
    assert owner.publish(1, a=2) == {"ok": True}
    assert owner.publish() == {"ok": False}
    with pytest.raises(ValueError):
        owner.publish()
    assert owner.publish() == "not a dict"
    rows = read_rows(trace_path)
    assert [(row["ph"], row["i"], row.get("out")) for row in rows] == [
        ("wb", 0, None), ("we", 0, "ok"), ("wb", 1, None), ("we", 1, "fail"),
        ("wb", 2, None), ("we", 2, "error"), ("wb", 3, None), ("we", 3, "fail"),
    ]


# ---- installation on the real adapters ---------------------------------------------------------------------------


def adapter_targets():
    from airag import embeddings, llm_enrichment
    from airag_consumer import bridge, memory

    return [
        (llm_enrichment, "_post_json"), (embeddings, "_post_embeddings"),
        (memory.OpenAICompatibleMemoryExtractor, "__call__"), (bridge, "_publish_window"),
    ]


def restore_on_exit(monkeypatch):
    originals = {}
    for owner, attr in adapter_targets():
        originals[(owner, attr)] = getattr(owner, attr)
        monkeypatch.setattr(owner, attr, originals[(owner, attr)])  # registers the undo
    return originals


def test_install_wraps_the_three_adapters_and_the_window_publisher(trace_path, monkeypatch):
    originals = restore_on_exit(monkeypatch)
    made = install(trace_path)
    assert made is not None and made.active
    for (owner, attr), original in originals.items():
        assert getattr(owner, attr).__wrapped__ is original


def test_install_wraps_nothing_when_one_target_is_missing(tmp_path, trace_path, monkeypatch):
    from airag_consumer import bridge

    originals = restore_on_exit(monkeypatch)
    monkeypatch.delattr(bridge, "_publish_window")
    assert install(trace_path) is None
    assert not trace_path.exists()
    for (owner, attr), original in originals.items():
        if (owner, attr) != (bridge, "_publish_window"):
            assert getattr(owner, attr) is original


def test_install_traces_a_real_tokenize_call_end_to_end(trace_path, monkeypatch):
    from airag import llm_enrichment

    restore_on_exit(monkeypatch)

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self, limit=-1):
            return b'{"tokens":[1,2]}'

    monkeypatch.setattr(llm_enrichment.urllib.request, "urlopen", lambda request, timeout: Response())
    assert install(trace_path) is not None
    cfg = types.SimpleNamespace(endpoint="http://127.0.0.1:1/v1", timeout_s=1.0)
    assert llm_enrichment._post_json(cfg, "/tokenize", {"model": "MARKER_MODEL"}) == {"tokens": [1, 2]}
    begin, end = read_rows(trace_path)
    assert (begin["name"], begin["tok"], end["out"]) == ("llm", True, "ok")
    assert b"MARKER" not in trace_path.read_bytes() and b"127.0.0.1" not in trace_path.read_bytes()


# ---- the tick hands the path to the pass child -------------------------------------------------------------------


def test_the_tick_passes_the_trace_file_to_the_pass_child(tmp_path, monkeypatch):
    seen = []
    monkeypatch.setattr(subprocess, "run", lambda argv, **kw: seen.append(list(argv)) or types.SimpleNamespace(returncode=1))
    environment = {name: "0" * 64 for name in tick.NAMES}
    with pytest.raises(tick.TickError):
        tick._run_component(tmp_path / "config.json", environment, tmp_path, ["child"])
    assert seen[0][:2] == ["child", "--config"]
    assert seen[0][-2:] == ["--trace-file", str(tmp_path / "pass-trace.jsonl")]


def test_a_real_tick_leaves_a_private_trace_and_rotates_it_the_next_time(tmp_path, capsys):
    item, hooks = synthetic_service(tmp_path)
    env = {**base_environment(), **KEYS}
    assert run_tick(tmp_path, item, hooks, env=env) == tick.EXIT_OK
    trace_file = tmp_path / "logs" / tick.TRACE_FILE_NAME
    assert trace_file.is_file() and stat.S_IMODE(trace_file.stat().st_mode) == 0o600
    assert not any(value.encode() in trace_file.read_bytes() for value in KEYS.values())
    run_tick(tmp_path, item, hooks, env=env)
    assert Path(str(trace_file) + ".prev").is_file()


def test_the_pass_child_installs_the_trace_in_a_fresh_process(tmp_path):
    code = (
        "import sys; sys.path.insert(0, %r)\n"
        "from airag_consumer import _pass_child\n"
        "raise SystemExit(_pass_child.child_main(['--config', %r, '--trace-file', %r]))\n"
    ) % (str(Path(__file__).resolve().parents[1] / "src"), str(tmp_path / "absent.json"), str(tmp_path / "t.jsonl"))
    with (tmp_path / "frame.json").open("wb") as frame:
        run = subprocess.run(
            [sys.executable, "-c", code], input=json.dumps(KEYS), text=True, stdout=frame,
            stderr=subprocess.DEVNULL, check=False,
        )
    assert run.returncode == 0  # the option parsed and the (failing) pass still delivered its frame
    assert (tmp_path / "t.jsonl").is_file() and stat.S_IMODE((tmp_path / "t.jsonl").stat().st_mode) == 0o600
