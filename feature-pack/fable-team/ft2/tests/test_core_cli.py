"""ft2 코어 전이 CLI 시험 (r1595 · PR②-6).

ⓐ 왕복 = `submit → assign → deliver → start → effect → result → complete → reassess → reclaim`.
같은 순서를 라이브러리로 직접 부르고, CLI 줄마다의 JSON 과 1:1 대조한다. 경로 실행과 `-m` 실행 둘 다.
ⓑ 거절·판정 불가 rc: 낡은 실행권(STALE_OWNER) 1 · 손상 state 2 · 모르는 동사·값 빠짐 64 · 쓰기 0.
⚠️ reassess 줄은 «완료 유보»(rc1)다 — 코어 `Dispatch.complete` 가 재평가를 «포함» 하므로 명시 재평가는
멱등이다. 재평가가 «정본» 인 경우(complete 저장 뒤 중단)는 `test_cli_reassess_after_interrupted_complete` 가
rc0 으로 따로 본다. ⓒ = legacy_guard rc0(기존 ft2 시험 불변은 완료 보고에서 전체 실행).
"""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
CLI = os.path.join(CORE, "cli.py")
TEAM, NOW, EV = "harness", "2026-11-11T01:00:00", ("v1", "v2")
STALE, CORRUPT, HOLD, USAGE = "낡은 실행권", "복구 필요", "완료 유보", 64
STEPS = (
    (["submit", "--command", "c1", "--body", "본문-1", "--work", "W1"], 0),
    (["assign", "--work", "W1", "--holder", "h1", "--evidence", "v1,v2"], 0),
    (["deliver", "--work", "W1", "--attempt", "a1"], 0),
    (["start", "--work", "W1", "--holder", "h1", "--gen", "1"], 0),
    (["effect", "--work", "W1", "--holder", "h1", "--gen", "1", "--effect", "e1"], 0),
    (["result", "--work", "W1", "--holder", "h1", "--gen", "1"], 0),
    (["complete", "--work", "W1", "--attempt", "a1"], 0),
    (["reassess", "--work", "W1"], 1),          # complete 가 재평가를 포함 → 멱등
    (["reclaim"], 0),
)


def _load(name, alias="ft2_test_cli_"):
    spec = importlib.util.spec_from_file_location(alias + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, execution = _load("record"), _load("intake"), _load("execution")
dispatch, journal, cli = _load("dispatch"), _load("journal"), _load("cli")
Runtime = lambda root: os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", TEAM, "runtime")  # noqa: E731


def _cli(args, root, script=None, module=False):
    """CLI 1회 — stdout 은 정확히 JSON 1줄이어야 한다(ⓐ)."""
    head = [sys.executable, "-m", "core.cli"] if module else [sys.executable, script or CLI]
    done = subprocess.run(head + list(args) + ["--root", str(root), "--team", TEAM], cwd=FT2,
                          env=dict(os.environ, FT_NOW=NOW), capture_output=True, text=True, timeout=25)
    assert done.stdout.count("\n") == 1, (done.stdout, done.stderr)
    assert "Traceback" not in done.stderr, done.stderr
    return json.loads(done.stdout), done.returncode


def _lib_round_trip(root):
    """같은 순서의 라이브러리 직접 호출 — CLI 결과와 1:1 대조하는 정본(ⓐ)."""
    clock = lambda: NOW                                                                     # noqa: E731
    entry, node = intake.Intake(str(root), TEAM, clock=clock), dispatch.Dispatch(str(root), TEAM, clock=clock)
    ex = execution.Execution(str(root), TEAM, clock=clock)
    return [entry.submit("c1", "본문-1", "W1")._asdict(), node.assign("W1", "h1", evidence=EV)._asdict(),
            node.deliver("W1", "a1")._asdict(), ex.start("W1", "h1", 1)._asdict(),
            ex.effect("W1", "h1", 1, "e1")._asdict(), ex.result("W1", "h1", 1)._asdict(),
            node.complete("W1", "a1")._asdict(), node.reassess("W1")._asdict(),
            journal.Journal(Runtime(root)).reclaim()]


def test_cli_happy_life_round_trip(tmp_path):
    """ⓐ 경로 실행·`-m` 실행 둘 다 — 줄마다 JSON 1줄 · 라이브러리 직접 호출과 같은 값 · rc = 계약 rc."""
    want = _lib_round_trip(tmp_path / "lib")
    for tag, module in (("path", False), ("module", True)):
        root = tmp_path / tag
        got = [_cli(list(args), root, module=module) for args, _rc in STEPS]
        assert [row for row, _rc in got] == want, tag
        assert [rc for _row, rc in got] == [rc for _args, rc in STEPS], tag
        assert [rc for _row, rc in got] == [cli.RC[row["result"]] for row, _rc in got], tag
    words = [row["result"] for row in want]
    assert words == ["접수 성공"] * 7 + [HOLD, "회수 결과"]


def test_cli_refusal_and_unknown_rc(tmp_path):
    """ⓑ 낡은 실행권 1 · 손상 state 2 · 모르는 동사·값 빠짐 64 · 판정 불가 경로는 쓰기 0."""
    root = tmp_path / "stale"
    _cli(["claim", "--work", "W1", "--holder", "h1"], root)
    _cli(["claim", "--work", "W1", "--holder", "h2", "--rotation", "true"], root)
    out, rc = _cli(["start", "--work", "W1", "--holder", "h1", "--gen", "1"], root)
    assert (out["result"], rc, out["written"]) == (STALE, 1, False)
    broken = tmp_path / "corrupt"
    _cli(["submit", "--command", "c1", "--body", "본문-1"], broken)
    state, lines = Path(Runtime(broken), "state.json"), Path(Runtime(broken), "journal.jsonl")
    state.write_bytes(b'{"schema": 1, "revision": 2, ')
    before = (state.read_bytes(), lines.read_bytes())
    out, rc = _cli(["submit", "--command", "c2", "--body", "본문-2"], broken)
    assert (out["result"], rc) == (CORRUPT, 2)
    assert (state.read_bytes(), lines.read_bytes()) == before                        # 쓰기 0
    assert not os.path.exists(Runtime(broken) + "/bodies/c2.body")                   # 본문 생성 0
    empty = tmp_path / "usage"
    assert _cli(["nosuch", "--x", "1"], empty)[1] == USAGE
    assert _cli(["submit", "--command", "c1"], empty)[1] == USAGE
    assert not os.path.exists(empty)                                                  # 파일 생성 0


class _Stop(Exception):
    """complete 는 내구화했고 재평가 «전» 에 끊겼다 — crash 대역(exit 없이 같은 지점)."""

def test_cli_reassess_after_interrupted_complete(tmp_path):
    """reassess 가 «정본» 인 경우 = rc0. complete 가 재평가를 마치면 멱등 «완료 유보»(위 ⓐ 8번째 줄)."""

    def stop(step):
        if step == "after_complete":
            raise _Stop

    root = str(tmp_path / "interrupted")
    intake.Intake(root, TEAM, clock=lambda: NOW).submit("c1", "본문-1", "W1")     # r1616: 배정 전 접수 1줄
    node = dispatch.Dispatch(root, TEAM, clock=lambda: NOW)
    node.assign("W1", "h1", evidence=EV)
    node.deliver("W1", "a1")
    with pytest.raises(_Stop):
        dispatch.Dispatch(root, TEAM, clock=lambda: NOW, on_step=stop).complete("W1", "a1")
    out, rc = _cli(["reassess", "--work", "W1"], root)
    assert (out["result"], out["stage"], rc) == ("접수 성공", "reassess", 0)
    assert _cli(["reassess", "--work", "W1"], root)[0]["result"] == HOLD              # 두 번째 = 멱등


def test_cli_empty_command_is_json_refusal_not_traceback(tmp_path):
    """R1 반례(고치기 전 FAIL) — 코어 RecordError 도 stdout JSON 1줄 + 계약 rc 다.
    예전: cli 가 record 를 따로 _load 해 except 가 못 잡고 traceback rc1(0줄). 빈 command 는
    코어 schema 경계 그대로 «접수 거부»(rc1)이고 state·journal·본문 쓰기가 없다."""
    root = tmp_path / "empty"
    out, rc = _cli(["submit", "--command", "", "--body", "본문"], root)
    assert (out["result"], rc) == ("접수 거부", cli.RC["접수 거부"]) == ("접수 거부", 1)
    assert "비어 있지 않은 문자열" in out["reason"] and out["written"] is False
    runtime = Path(Runtime(root))
    assert [name for name in ("state.json", "journal.jsonl") if (runtime / name).exists()] == []
    assert list((runtime / "bodies").iterdir()) == [] if (runtime / "bodies").is_dir() else True


def test_cli_m1_refusal_reported_as_success_breaks_b(tmp_path):
    """변이 M1(제품 파일 1곳: `"낡은 실행권": 1` → 0) — 거절을 rc0 으로 내면 ⓑ 가 FAIL 한다."""
    source = Path(cli.__file__).read_text(encoding="utf-8")
    mutant = source.replace('"낡은 실행권": 1', '"낡은 실행권": 0')
    assert mutant != source
    path = Path(CORE, "_cli_m1_mutant.py")
    try:
        path.write_text(mutant, encoding="utf-8")
        root = tmp_path / "m1"
        _cli(["claim", "--work", "W1", "--holder", "h1"], root, script=str(path))
        _cli(["claim", "--work", "W1", "--holder", "h2", "--rotation", "true"], root, script=str(path))
        out, rc = _cli(["start", "--work", "W1", "--holder", "h1", "--gen", "1"], root, script=str(path))
        assert (out["result"], rc) == (STALE, 0)                   # 거절인데 성공 = ⓑ 위반
    finally:
        path.unlink()


def test_cli_legacy_guard_rc0():
    """ⓒ 정본 검사기 — 새 파일 2개가 1.x 경로·도구를 하나도 부르지 않는다."""
    done = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")
    assert record.SCHEMA_VERSION == 1 and cli.USAGE == 64 and set(cli.VERBS) >= {"submit", "reclaim"}
