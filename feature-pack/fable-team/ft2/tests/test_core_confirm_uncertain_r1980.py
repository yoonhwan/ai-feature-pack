"""r1980 — 미확정 표식을 증거가 있을 때 정본 손(현역 master)이 `confirm` 1줄로 푼다(실 CLI · 임시 원장).

반례 ① 효과 뒤 결과 없음 → 표식 → confirm(같은 gen · 회수 결과 · 근거) → result 1줄 · 표식 0 · 다음 effect OK
② 다른 gen ③ 표식 없음 ④ 낱말 밖 ⑤ 나노 좌석 = 접수 거부 · 쓰기 0. 변이 M1 gen 대조 삭제 → ② · M2 역할 확인 삭제 → ⑤.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

CLI = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core", "cli.py")
TEAM, W, H, MASTER = "harness", "W1", "h1", "byz-harness-master-pi#265"
NANO = "byz-harness-nano-W1#0"
EVIDENCE = "원격 nano/W1 = 1c8abfd2, push 끝남"


def _cli(root, *argv, seat=MASTER):
    env = dict(os.environ, FT_NOW="2026-11-14T01:00:00", FT_SEAT=seat)
    proc = subprocess.run([sys.executable, CLI, *argv, "--root", str(root), "--team", TEAM],
                          capture_output=True, text=True, env=env, timeout=20)
    return json.loads(proc.stdout), proc.returncode


def _snap(root):
    run = Path(root, ".fable-team", "teams", TEAM, "runtime")
    return tuple(p.read_bytes() for p in sorted(run.rglob("*")) if p.is_file())


def _journal(root):
    path = Path(root, ".fable-team", "teams", TEAM, "runtime", "journal.jsonl")
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _state(root):
    return json.loads(Path(root, ".fable-team", "teams", TEAM, "runtime", "state.json").read_text("utf-8"))


@pytest.fixture
def world(tmp_path):
    """접수 → claim → start → effect → (result 누락) effect 다시 = 미확정 표식(gen 1)."""
    Path(tmp_path, ".fable-team").mkdir()
    Path(tmp_path, ".fable-team", "seats-%s.json" % TEAM).write_text(
        json.dumps({"_master": MASTER}), encoding="utf-8")
    assert _cli(tmp_path, "submit", "--command", "c1", "--body", "본문", "--work", W)[1] == 0
    assert _cli(tmp_path, "claim", "--work", W, "--holder", H)[1] == 0
    assert _cli(tmp_path, "start", "--work", W, "--holder", H, "--gen", "1")[1] == 0
    assert _cli(tmp_path, "effect", "--work", W, "--holder", H, "--gen", "1", "--effect", "push")[1] == 0
    out, rc = _cli(tmp_path, "effect", "--work", W, "--holder", H, "--gen", "1", "--effect", "push")
    assert (out["result"], out["stage"], rc) == ("완료 유보", "uncertain", 1)
    assert W in _state(tmp_path)["uncertain"]
    return tmp_path


def _confirm(root, gen="1", word="회수 결과", seat=MASTER, evidence=EVIDENCE):
    return _cli(root, "confirm", "--work", W, "--holder", H, "--gen", gen, "--word", word,
                "--evidence", evidence, seat=seat)


def test_confirm_clears_marker_with_evidence(world):
    out, rc = _confirm(world)
    assert (out["result"], out["stage"], rc) == ("접수 성공", "result", 0)
    last = _journal(world)[-1]
    assert (last["kind"], last["gen"], last["evidence"], last["confirmed_by"]) == ("result", 1, EVIDENCE, MASTER)
    state = _state(world)
    assert W not in state.get("uncertain", {}) and W not in state.get("owners", {})
    out, rc = _cli(world, "effect", "--work", W, "--holder", H, "--gen", "1", "--effect", "next")
    assert (out["result"], rc) == ("접수 성공", 0)


@pytest.mark.parametrize("case", ["other_gen", "nano_seat", "word_outside", "empty_evidence"])
def test_confirm_refused_writes_nothing(world, case):
    before = _snap(world)
    kwargs = {"other_gen": {"gen": "2"}, "nano_seat": {"seat": NANO},
              "word_outside": {"word": "끝남"}, "empty_evidence": {"evidence": " "}}[case]
    out, rc = _confirm(world, **kwargs)
    assert (out["result"], out["written"], rc) == ("접수 거부", False, 1)
    assert _snap(world) == before


def test_confirm_without_marker_refused(world):
    assert _confirm(world)[1] == 0
    before = _snap(world)
    out, rc = _confirm(world)
    assert (out["result"], out["written"], rc) == ("접수 거부", False, 1)
    assert _snap(world) == before
