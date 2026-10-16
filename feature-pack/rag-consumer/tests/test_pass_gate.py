"""DB check gate and pass-state file (design r17 section 6, errata 1 sections 1, 4, 5, errata 2 sections 3, 5, errata 3).

The check is read-only and runs in the pass child before the pass. A pass that was not shown to end cleanly (no file,
``running``, any invalid or foreign state file) gets the check; a refused check never starts the pass; a state file
that cannot be written safely never lets a pass start either. Real synthetic stores are used for the check itself;
scripted fake SQLCipher objects cover what real stores cannot show (a failing quick_check, a hung call, the exact
statement list). No real `op`, no launchd, no operational file.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import threading
import types

import pytest

from airag.db import connect as core_connect
from airag_consumer import _pass_gate as gate
from airag_consumer import _result, tick
from airag_consumer.reason_codes import REASON_CODES
from airag_consumer.runtime import RuntimeConfig
from test_runtime import CONSUMER_KEY, PROJECTION_KEY
from test_tick import KEYS, base_environment, run_tick, synthetic_service

CODES = ("DATABASE_INTEGRITY_FAILED", "DATABASE_INTEGRITY_UNAVAILABLE", "PASS_STATE_UNAVAILABLE")


# ---- the frame carries an optional, closed integrity record ---------------------------------------------------


def good_record():
    return {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 12.5}, {"db": "projection", "out": "not_ok", "ms": 3.0}]}


def frame_with(record):
    return {"exit": 0, "summary": {}, "code": "", "type": "", "integrity": record}


def test_the_three_gate_codes_are_registered_and_allowed_in_a_frame():
    for code in CODES:
        assert code in REASON_CODES and code in _result.FRAME_CODES


def test_a_frame_may_carry_a_valid_integrity_record_and_keeps_it():
    assert _result.validate_frame(frame_with(good_record())) == frame_with(good_record())


@pytest.mark.parametrize("bad", [
    None, [], "x", {}, {"v": 1}, {"v": 2, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.0}]},
    {"v": True, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.0}]},
    {"v": 1, "dbs": []}, {"v": 1, "dbs": "x"},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.0}] * 2},  # one entry per database
    {"v": 1, "dbs": [{"db": "archive", "out": "ok", "ms": 1.0}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "fine", "ms": 1.0}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 1}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": -0.1}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 120_000.5}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": float("nan")}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.0, "extra": 1}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok"}]},
    {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.0}], "extra": 1},
])
def test_an_invalid_integrity_record_drops_only_the_field(bad):
    cleaned = _result.validate_frame(frame_with(bad))
    assert cleaned == {"exit": 0, "summary": {}, "code": "", "type": ""}


def test_other_extra_frame_keys_are_still_rejected():
    assert _result.validate_frame({"exit": 0, "summary": {}, "code": "", "type": "", "body": "x"}) is None
    assert _result.validate_frame({**frame_with(good_record()), "body": "x"}) is None


def test_the_widest_integrity_record_fits_its_byte_limit():
    widest = {"v": 1, "dbs": [
        {"db": "consumer", "out": "identity_error", "ms": 119_999.999},
        {"db": "projection", "out": "identity_error", "ms": 119_999.999},
    ]}
    assert len(json.dumps(widest, sort_keys=True, separators=(",", ":")).encode()) <= 512
    assert _result.integrity_valid(widest)


# ---- the pass-state file ------------------------------------------------------------------------------------


def state_text(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def test_project_id_is_sixteen_hex_digits_without_any_path_text():
    one = gate.project_id("/a/consumer.db", "/a/projection.db")
    assert len(one) == 16 and int(one, 16) >= 0 and "consumer" not in one
    assert one == gate.project_id("/a/consumer.db", "/a/projection.db")
    assert one != gate.project_id("/b/consumer.db", "/a/projection.db")
    assert one != gate.project_id("/a/projection.db", "/a/consumer.db")  # the order is part of the value
    assert one == hashlib.sha256(b"/a/consumer.db\n/a/projection.db").hexdigest()[:16]


def test_only_a_valid_clean_file_for_the_same_project_skips_the_check(tmp_path):
    path = tmp_path / "pass-state.json"
    project = gate.project_id("/c", "/p")
    assert gate.state_is_clean(str(path), project) is False  # no file
    assert gate.write_state(str(path), project, "running")
    assert gate.state_is_clean(str(path), project) is False  # running
    assert gate.write_state(str(path), project, "clean")
    assert gate.state_is_clean(str(path), project) is True
    assert gate.state_is_clean(str(path), gate.project_id("/c", "/other")) is False  # another project
    assert state_text(path) == {"v": 1, "proj": project, "state": "clean"}
    assert stat.S_IMODE(path.stat().st_mode) == 0o600


@pytest.mark.parametrize("content", [
    '{"v":2,"proj":"%s","state":"clean"}', '{"v":true,"proj":"%s","state":"clean"}',
    '{"v":1,"proj":"%s","state":"Clean"}', '{"v":1,"proj":"%s","state":"clean","x":1}', '{"v":1,"proj":"%s"}',
    '[1]', 'not json', '', '{"v":1,"proj":"%s","state":"clean"}' + " " * 300, '\xff\xfe',
])
def test_an_invalid_or_oversized_state_content_never_counts_as_clean(tmp_path, content):
    path = tmp_path / "pass-state.json"
    project = gate.project_id("/c", "/p")
    path.write_bytes((content % project if "%s" in content else content).encode("latin-1"))
    path.chmod(0o600)
    assert gate.state_is_clean(str(path), project) is False


def test_an_unsafe_state_file_never_counts_as_clean(tmp_path):
    project = gate.project_id("/c", "/p")
    path = tmp_path / "pass-state.json"
    assert gate.write_state(str(path), project, "clean")
    path.chmod(0o644)  # group/world readable
    assert gate.state_is_clean(str(path), project) is False
    path.chmod(0o600)
    link = tmp_path / "linked.json"
    link.symlink_to(path)
    assert gate.state_is_clean(str(link), project) is False  # a link is never followed
    twin = tmp_path / "twin.json"
    os.link(path, twin)  # a second name: nlink 2
    assert gate.state_is_clean(str(path), project) is False
    twin.unlink()
    directory = tmp_path / "dir.json"
    directory.mkdir()
    assert gate.state_is_clean(str(directory), project) is False
    assert gate.state_is_clean(str(path), project) is True  # and the plain file is accepted again


def test_writing_the_state_replaces_atomically_and_leaves_no_temporary_file(tmp_path):
    path = tmp_path / "pass-state.json"
    project = gate.project_id("/c", "/p")
    assert gate.write_state(str(path), project, "clean")
    assert gate.write_state(str(path), project, "running")
    assert state_text(path)["state"] == "running"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["pass-state.json"]


def test_a_failed_replace_keeps_the_old_file_and_removes_the_temporary_one(tmp_path, monkeypatch):
    path = tmp_path / "pass-state.json"
    project = gate.project_id("/c", "/p")
    assert gate.write_state(str(path), project, "clean")
    real = os.replace

    def broken(source, target, *args, **kwargs):
        if str(target) == str(path):
            raise OSError(28, "MARKER_DISK")
        return real(source, target, *args, **kwargs)

    monkeypatch.setattr(os, "replace", broken)
    assert gate.write_state(str(path), project, "running") is False
    assert state_text(path)["state"] == "clean"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["pass-state.json"]


def test_a_state_that_cannot_be_created_reports_false(tmp_path):
    assert gate.write_state(str(tmp_path / "absent" / "pass-state.json"), "0" * 16, "running") is False
    blocked = tmp_path / "pass-state.json"
    blocked.mkdir()  # replacing a directory by a file fails
    assert gate.write_state(str(blocked), "0" * 16, "running") is False
    assert sorted(p.name for p in tmp_path.iterdir()) == ["pass-state.json"]


# ---- the database budget ------------------------------------------------------------------------------------


def test_the_budget_grows_with_the_database_size_up_to_the_ceiling(tmp_path):
    database = tmp_path / "db"
    assert gate.database_budget(str(database)) == 7.0  # unreadable size counts as one unit
    database.write_bytes(b"x")
    assert gate.database_budget(str(database)) == 7.0
    with database.open("r+b") as handle:
        handle.truncate(16 * 1024 * 1024 + 1)
    assert gate.database_budget(str(database)) == 14.0
    (tmp_path / "db-wal").write_bytes(b"w")
    assert gate.database_budget(str(database)) == 14.0
    with database.open("r+b") as handle:
        handle.truncate(2 * 1024 * 1024 * 1024)
    assert gate.database_budget(str(database)) == 70.0


# ---- the check on real synthetic stores ---------------------------------------------------------------------


@pytest.fixture(scope="module")
def service(tmp_path_factory):
    item, _ = synthetic_service(tmp_path_factory.mktemp("gate"))
    config = RuntimeConfig.load(item["config"])
    return types.SimpleNamespace(item=item, consumer=config.consumer_db, projection=config.projection_db)


def real_targets(service, *, consumer_key=CONSUMER_KEY, projection_key=PROJECTION_KEY, consumer=None, projection=None):
    return [
        gate.Target("consumer", str(consumer or service.consumer), consumer_key, gate.consumer_identity),
        gate.Target("projection", str(projection or service.projection), projection_key, gate.projection_identity),
    ]


def outcomes(rows):
    return {row["db"]: row["out"] for row in rows}


def fingerprint(*paths):
    return [(hashlib.sha256(Path(p).read_bytes()).hexdigest(), Path(p).stat().st_mtime_ns) for p in paths]


def test_both_synthetic_stores_pass_and_nothing_on_disk_changes(service):
    before = fingerprint(service.consumer, service.projection)
    rows = gate.check_databases(real_targets(service))
    assert outcomes(rows) == {"consumer": "ok", "projection": "ok"}
    assert [row["db"] for row in rows] == ["consumer", "projection"]
    assert _result.integrity_valid({"v": 1, "dbs": rows})
    assert fingerprint(service.consumer, service.projection) == before


def test_a_wrong_key_or_a_missing_or_plain_file_is_an_open_error(service, tmp_path):
    plain = tmp_path / "plain.db"
    plain.write_bytes(b"not a database" * 1000)
    rows = gate.check_databases(real_targets(
        service, consumer_key=b"z" * 32, projection=plain,
    ))
    assert outcomes(rows) == {"consumer": "open_error", "projection": "open_error"}
    missing = gate.check_databases(real_targets(service, consumer=tmp_path / "absent.db"))
    assert outcomes(missing) == {"consumer": "open_error", "projection": "ok"}
    assert not (tmp_path / "absent.db").exists()  # a read-only open never creates the file


def test_a_store_of_the_other_kind_is_an_identity_error_not_an_open_error(service):
    rows = gate.check_databases(real_targets(service, consumer=service.projection, projection=service.consumer,
                                             consumer_key=PROJECTION_KEY, projection_key=CONSUMER_KEY))
    assert outcomes(rows) == {"consumer": "identity_error", "projection": "identity_error"}


def test_the_core_opener_cannot_open_the_consumer_ledger_which_is_why_the_check_has_its_own(service):
    with pytest.raises(Exception):
        core_connect.open_readonly(service.consumer, CONSUMER_KEY)
    core_connect.open_readonly(service.projection, PROJECTION_KEY).close()


# ---- the check against scripted SQLCipher objects ------------------------------------------------------------


class FakeCursor:
    def __init__(self, rows):
        self.rows = rows

    def fetchone(self):
        return self.rows[0] if self.rows else None

    def fetchall(self):
        return list(self.rows)


class FakeConnection:
    def __init__(self, owner):
        self.owner = owner
        self.closed = False

    def execute(self, sql, *params):
        self.owner.statements.append(sql)
        lowered = sql.lower()
        if self.owner.fail_at and self.owner.fail_at in lowered:
            raise RuntimeError("MARKER_ERROR_TEXT")
        if "cipher_version" in lowered:
            return FakeCursor([] if self.owner.no_cipher else [("4.5.0",)])
        if "quick_check" in lowered:
            return FakeCursor(self.owner.quick_rows)
        return FakeCursor([(1,)])

    def set_progress_handler(self, handler, steps):
        self.owner.handlers.append((handler, steps))

    def interrupt(self):
        self.owner.interrupted.set()
        self.owner.release.set()

    def close(self):
        self.closed = True


class FakeSqlcipher:
    def __init__(self, *, quick_rows=None, fail_at=None, no_cipher=False, block=False):
        self.quick_rows = [("ok",)] if quick_rows is None else quick_rows
        self.fail_at, self.no_cipher, self.block = fail_at, no_cipher, block
        self.statements, self.handlers, self.uris, self.connections = [], [], [], []
        self.interrupted, self.release = threading.Event(), threading.Event()

    def connect(self, uri, **kwargs):
        self.uris.append((uri, kwargs))
        if self.block:
            self.release.wait(10)
        connection = FakeConnection(self)
        self.connections.append(connection)
        return connection


def fake_target(name="consumer", identity=lambda con: True):
    return gate.Target(name, "/synthetic/path/to/" + name + ".db", b"k" * 32, identity)


def test_the_check_opens_read_only_and_sends_only_read_statements_in_order():
    fake = FakeSqlcipher()
    rows = gate.check_databases([fake_target()], sqlcipher3=fake)
    assert outcomes(rows) == {"consumer": "ok"}
    uri, kwargs = fake.uris[0]
    assert "mode=ro" in uri and kwargs == {"uri": True, "isolation_level": None}
    lowered = [sql.lower() for sql in fake.statements]
    assert "pragma key" in lowered[0] and "temp_store" in lowered[1] and "query_only" in lowered[2]
    assert "busy_timeout=1000" in lowered[3].replace(" ", "")
    assert "sqlite_master" in lowered[4] and "cipher_version" in lowered[5] and "quick_check" in lowered[6]
    assert not any(word in sql for sql in lowered for word in ("journal_mode", "synchronous", "foreign_keys",
                                                                 "insert", "update", "create", "delete", "drop"))
    assert fake.connections[0].closed and fake.handlers  # closed, and a progress handler was installed


def test_a_quick_check_that_is_not_ok_is_not_ok_and_no_row_is_kept():
    fake = FakeSqlcipher(quick_rows=[("*** in database main ***",), ("MARKER_ROW",)])
    rows = gate.check_databases([fake_target()], sqlcipher3=fake)
    assert outcomes(rows) == {"consumer": "not_ok"} and "MARKER" not in json.dumps(rows)


def test_a_failing_quick_check_statement_counts_as_not_ok():
    rows = gate.check_databases([fake_target()], sqlcipher3=FakeSqlcipher(fail_at="quick_check"))
    assert outcomes(rows) == {"consumer": "not_ok"} and "MARKER" not in json.dumps(rows)


@pytest.mark.parametrize("fail_at", ["pragma key", "temp_store", "query_only", "busy_timeout", "sqlite_master"])
def test_a_failure_while_opening_is_an_open_error(fail_at):
    rows = gate.check_databases([fake_target()], sqlcipher3=FakeSqlcipher(fail_at=fail_at))
    assert outcomes(rows) == {"consumer": "open_error"}


def test_an_empty_cipher_version_is_an_open_error():
    assert outcomes(gate.check_databases([fake_target()], sqlcipher3=FakeSqlcipher(no_cipher=True))) == {
        "consumer": "open_error"}


def test_a_failing_or_false_identity_is_an_identity_error():
    assert outcomes(gate.check_databases(
        [fake_target(identity=lambda con: False)], sqlcipher3=FakeSqlcipher())) == {"consumer": "identity_error"}

    def raises(con):
        raise RuntimeError("MARKER_ERROR_TEXT")

    rows = gate.check_databases([fake_target(identity=raises)], sqlcipher3=FakeSqlcipher())
    assert outcomes(rows) == {"consumer": "identity_error"} and "MARKER" not in json.dumps(rows)


def test_a_hung_database_is_decided_as_deadline_without_waiting_for_the_thread(monkeypatch):
    monkeypatch.setattr(gate, "BUDGET_UNIT_S", 0.2)
    monkeypatch.setattr(gate, "BUDGET_CEILING_S", 0.2)
    fake = FakeSqlcipher(block=True)
    try:
        rows = gate.check_databases([fake_target("consumer"), fake_target("projection")], sqlcipher3=fake)
        assert outcomes(rows) == {"consumer": "deadline", "projection": "deadline"}
        assert rows[0]["ms"] >= 100.0 and rows[1]["ms"] == 0.0  # the second one never started
        assert _result.integrity_valid({"v": 1, "dbs": rows})
    finally:
        fake.release.set()  # let the daemon thread end


def test_a_finished_check_is_not_overwritten_by_the_deadline():
    rows = gate.check_databases([fake_target("consumer"), fake_target("projection")], sqlcipher3=FakeSqlcipher())
    assert outcomes(rows) == {"consumer": "ok", "projection": "ok"}


def test_an_unavailable_sqlcipher_module_is_an_open_error_for_every_database(monkeypatch):
    import builtins

    real = builtins.__import__

    def refuse(name, *args, **kwargs):
        if name == "sqlcipher3":
            raise ImportError("MARKER_IMPORT")
        return real(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", refuse)
    rows = gate.check_databases([fake_target("consumer"), fake_target("projection")])
    assert outcomes(rows) == {"consumer": "open_error", "projection": "open_error"}


# ---- the refusal ---------------------------------------------------------------------------------------------


def row(db, out):
    return {"db": db, "out": out, "ms": 1.0}


def test_all_ok_means_no_refusal():
    assert gate.refusal_for([row("consumer", "ok"), row("projection", "ok")]) is None


@pytest.mark.parametrize("rows, expected", [
    ([row("consumer", "not_ok"), row("projection", "ok")], ("DATABASE_INTEGRITY_FAILED", "consumer")),
    ([row("consumer", "ok"), row("projection", "not_ok")], ("DATABASE_INTEGRITY_FAILED", "projection")),
    ([row("consumer", "open_error"), row("projection", "ok")], ("DATABASE_INTEGRITY_UNAVAILABLE", "consumer")),
    ([row("consumer", "ok"), row("projection", "deadline")], ("DATABASE_INTEGRITY_UNAVAILABLE", "projection")),
    ([row("consumer", "identity_error"), row("projection", "ok")], ("DATABASE_INTEGRITY_UNAVAILABLE", "consumer")),
    ([row("consumer", "open_error"), row("projection", "not_ok")], ("DATABASE_INTEGRITY_FAILED", "projection")),
])
def test_a_proven_damage_outranks_an_unavailable_check(rows, expected):
    refusal = gate.refusal_for(rows)
    assert (refusal["code"], refusal["type"]) == expected and set(refusal) == {"code", "type"}


# ---- the flow before and after a pass -------------------------------------------------------------------------


def run_before(service, state_file, **keys):
    return gate.before_pass(str(service.item["config"]), str(state_file), keys.get("consumer", CONSUMER_KEY),
                            keys.get("projection", PROJECTION_KEY))


def project_of(service):
    return gate.project_id(str(service.consumer), str(service.projection))


def forbid_check(monkeypatch):
    def called(*args, **kwargs):
        raise AssertionError("the check must not run")

    monkeypatch.setattr(gate, "check_databases", called)


def test_an_unusable_config_leaves_everything_to_the_pass_itself(tmp_path, monkeypatch):
    forbid_check(monkeypatch)
    state = tmp_path / "pass-state.json"
    result = gate.before_pass(str(tmp_path / "absent.json"), str(state), CONSUMER_KEY, PROJECTION_KEY)
    assert result == gate.Gate() and not state.exists()
    gate.after_pass(result, str(state))
    assert not state.exists()


def test_the_first_pass_is_checked_then_recorded_as_running(service, tmp_path):
    state = tmp_path / "pass-state.json"
    result = run_before(service, state)
    assert result.refusal is None and result.project == project_of(service)
    assert outcomes(result.integrity["dbs"]) == {"consumer": "ok", "projection": "ok"}
    assert state_text(state)["state"] == "running"
    gate.after_pass(result, str(state))
    assert state_text(state) == {"v": 1, "proj": project_of(service), "state": "clean"}


def test_a_clean_state_skips_the_check_but_still_records_running(service, tmp_path, monkeypatch):
    state = tmp_path / "pass-state.json"
    assert gate.write_state(str(state), project_of(service), "clean")
    forbid_check(monkeypatch)
    result = run_before(service, state)
    assert result.refusal is None and result.integrity is None
    assert state_text(state)["state"] == "running"


def test_a_running_or_foreign_state_is_checked_again(service, tmp_path):
    state = tmp_path / "pass-state.json"
    for written in (project_of(service), "f" * 16):
        assert gate.write_state(str(state), written, "running" if written != "f" * 16 else "clean")
        assert run_before(service, state).integrity is not None


def test_a_refused_check_neither_starts_the_pass_nor_touches_the_state(service, tmp_path):
    state = tmp_path / "pass-state.json"
    result = run_before(service, state, consumer=b"z" * 32)
    assert result.refusal == {"code": "DATABASE_INTEGRITY_UNAVAILABLE", "type": "consumer"}
    assert outcomes(result.integrity["dbs"]) == {"consumer": "open_error", "projection": "ok"}
    assert not state.exists()
    gate.after_pass(result, str(state))
    assert not state.exists()  # no clean mark after a refusal
    assert gate.write_state(str(state), project_of(service), "running")
    gate.after_pass(result, str(state))
    assert state_text(state)["state"] == "running"


def test_a_failed_running_write_refuses_the_pass_even_when_an_old_clean_file_exists(service, tmp_path, monkeypatch):
    state = tmp_path / "pass-state.json"
    assert gate.write_state(str(state), project_of(service), "clean")
    real = os.replace

    def broken(source, target, *args, **kwargs):
        if str(target) == str(state):
            raise OSError(28, "MARKER_DISK")
        return real(source, target, *args, **kwargs)

    monkeypatch.setattr(os, "replace", broken)
    forbid_check(monkeypatch)  # the clean file skipped the check, so the pass would have started without `running`
    result = run_before(service, state)
    assert result.refusal == {"code": "PASS_STATE_UNAVAILABLE", "type": "pass_state"}
    assert state_text(state)["state"] == "clean"  # the old file is still there, and it is not an excuse to start
    gate.after_pass(result, str(state))
    assert state_text(state)["state"] == "clean"


def test_a_failed_clean_write_leaves_running_for_the_next_check(service, tmp_path, monkeypatch):
    state = tmp_path / "pass-state.json"
    result = run_before(service, state)
    monkeypatch.setattr(gate, "write_state", lambda *args: False)
    gate.after_pass(result, str(state))
    assert state_text(state)["state"] == "running"


# ---- the tick (parent) and the pass child, end to end -------------------------------------------------------


def last_line(tmp_path):
    return json.loads((tmp_path / "logs" / "tick-20260927.log").read_text(encoding="utf-8").strip().splitlines()[-1])


def keyed(**extra):
    return {**base_environment(), **KEYS, **extra}


def test_the_tick_passes_the_state_file_to_the_pass_child(tmp_path, monkeypatch):
    seen = []
    monkeypatch.setattr(subprocess, "run", lambda argv, **kw: seen.append(list(argv)) or types.SimpleNamespace(returncode=1))
    environment = {name: "0" * 64 for name in tick.NAMES}
    with pytest.raises(tick.TickError):
        tick._run_component(tmp_path / "config.json", environment, tmp_path, ["child"])
    argv = seen[0]
    assert argv[argv.index("--state-file") + 1] == str(tmp_path / "pass-state.json")
    assert argv[argv.index("--trace-file") + 1] == str(tmp_path / "pass-trace.jsonl")


def test_the_first_tick_logs_the_check_and_ends_clean_and_the_second_does_not_check(tmp_path):
    item, hooks = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, hooks, env=keyed()) == tick.EXIT_OK
    first = last_line(tmp_path)
    assert first["status"] == "ok" and _result.integrity_valid(first["integrity"])
    assert outcomes(first["integrity"]["dbs"]) == {"consumer": "ok", "projection": "ok"}
    state = tmp_path / "logs" / "pass-state.json"
    assert state_text(state)["state"] == "clean" and stat.S_IMODE(state.stat().st_mode) == 0o600
    run_tick(tmp_path, item, hooks, env=keyed())  # whatever the second pass reports, it is not checked again
    assert "integrity" not in last_line(tmp_path)
    assert state_text(state)["state"] == "clean"


def test_a_store_that_cannot_be_opened_stops_the_tick_with_its_own_code_and_type(tmp_path):
    item, hooks = synthetic_service(tmp_path)
    wrong = {"AIRAG_CONSUMER_KEY_HEX": ("d" * 32).encode().hex()}
    assert run_tick(tmp_path, item, hooks, env=keyed(**wrong)) == tick.EXIT_RUNTIME
    line = last_line(tmp_path)
    assert line["status"] == "runtime_error" and line["exit"] == 40
    assert (line["code"], line["type"]) == ("DATABASE_INTEGRITY_UNAVAILABLE", "consumer")
    assert outcomes(line["integrity"]["dbs"]) == {"consumer": "open_error", "projection": "ok"}
    assert "summary" not in line and not (tmp_path / "logs" / "pass-state.json").exists()


def test_a_pass_killed_after_it_started_is_checked_again_by_the_next_tick(tmp_path):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "kill-in-pass", env=keyed()) == tick.EXIT_RUNTIME
    assert last_line(tmp_path)["code"] == "COMPONENT_PROCESS_FAILED"
    state = tmp_path / "logs" / "pass-state.json"
    assert state_text(state)["state"] == "running"  # the forced kill left no clean mark
    assert run_tick(tmp_path, item, "normal", env=keyed()) == tick.EXIT_OK
    assert "integrity" in last_line(tmp_path)  # checked again
    assert state_text(state)["state"] == "clean"


def test_a_pass_that_fails_by_itself_still_ends_clean(tmp_path):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "short", env=keyed()) == tick.EXIT_RUNTIME
    assert state_text(tmp_path / "logs" / "pass-state.json")["state"] == "clean"


def test_a_state_file_that_cannot_be_written_stops_the_tick_before_the_pass(tmp_path):
    item, _ = synthetic_service(tmp_path)
    (tmp_path / "logs" / "pass-state.json").mkdir(parents=True)  # not a regular file: unreadable and unreplaceable
    marker = tmp_path / "marker.json"
    assert run_tick(tmp_path, item, "env-probe", env=keyed(TICK_MARKER=str(marker))) == tick.EXIT_RUNTIME
    line = last_line(tmp_path)
    assert (line["code"], line["type"]) == ("PASS_STATE_UNAVAILABLE", "pass_state")
    assert outcomes(line["integrity"]["dbs"]) == {"consumer": "ok", "projection": "ok"}
    assert not marker.exists()  # the pass body never ran


def test_a_valid_integrity_field_from_the_child_is_logged_and_an_invalid_one_is_dropped(tmp_path):
    item, _ = synthetic_service(tmp_path)
    assert run_tick(tmp_path, item, "forged-integrity-good", env=keyed()) == tick.EXIT_OK
    assert last_line(tmp_path)["integrity"] == {"v": 1, "dbs": [{"db": "consumer", "out": "ok", "ms": 1.5}]}
    assert run_tick(tmp_path, item, "forged-integrity-bad", env=keyed()) == tick.EXIT_OK
    line = last_line(tmp_path)
    assert "integrity" not in line and line["status"] == "ok"
