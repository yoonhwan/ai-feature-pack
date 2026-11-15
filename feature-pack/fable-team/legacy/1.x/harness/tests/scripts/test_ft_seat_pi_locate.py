"""r1993: Pi 세션 찾기 = cwd 폴더 1개 먼저 · 그 폴더 후보 0 일 때만 전수 glob(판정 꼴 그대로)."""
import importlib, json, os, sys  # noqa: E401
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
sys.path.insert(0, str(BIN))
SEAT, SID, AT = "t-worker-pi#1", "synthetic-session-1", "2026-11-15T01:00:00"


@pytest.fixture
def pi(tmp_path, monkeypatch):
    module = importlib.import_module("ft_seat_pi")
    cwd = tmp_path / "cwd"
    cwd.mkdir()
    real = os.path.realpath(cwd)
    monkeypatch.setattr(module, "tmux_env", lambda seat, tmux: {"TMUXC_PI_SESSION_ID": SID})
    monkeypatch.setattr(module, "live_identity", lambda seat, tmux: ("1", real, SID))
    monkeypatch.setenv("FT_PI_SESSIONS", str(tmp_path / "sessions"))
    opened = []
    raw = Path.open
    monkeypatch.setattr(Path, "open", lambda self, *a, **k: opened.append(self) or raw(self, *a, **k))
    return module, tmp_path / "sessions", real, opened


def put(root, folder, cwd, name=SID, sid=SID, seat=SEAT, ts=AT):
    path = root / folder / f"2026-11-15T01-00-00-000Z_{name}.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    rows = [{"type": "session", "id": sid, "cwd": cwd, "timestamp": ts}, {"type": "session_info", "name": seat}]
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return path


def own(cwd):   # 실측 규칙 2107/2107 — 폴더 = «--» + cwd(앞뒤 / 빼고 / → -) + «--»
    return "--" + cwd.strip("/").replace("/", "-") + "--"


def test_cwd_folder_first_opens_one_file(pi):
    module, root, cwd, opened = pi
    hit = put(root, own(cwd), cwd)
    [put(root, f"--other-{i}--", "/elsewhere", name=f"x{i}", sid=f"x{i}") for i in range(3)]
    opened.clear()
    assert module.locate(SEAT)[0] == str(hit)
    assert opened == [hit]


def test_fallback_glob_when_cwd_folder_has_none(pi):
    hit = put(pi[1], "--moved--", pi[2])
    assert pi[0].locate(SEAT)[0] == str(hit)


@pytest.mark.parametrize("kw,folder", [(dict(cwd="/other"), "--other--"), (dict(seat="different-seat"), None)])
def test_mismatch_stays_undecidable(pi, kw, folder):
    module, root, cwd, _ = pi
    put(root, folder or own(cwd), kw.get("cwd", cwd), seat=kw.get("seat", SEAT))
    with pytest.raises(ValueError, match="후보 0개"):
        module.locate(SEAT)


def test_two_candidates_stay_ambiguous(pi):
    module, root, cwd, _ = pi
    put(root, own(cwd), cwd, name="a_" + SID)
    put(root, own(cwd), cwd)
    with pytest.raises(ValueError, match="후보 2개"):
        module.locate(SEAT)


def test_ft2_folder_first_then_fallback(pi):
    _, root, cwd, opened = pi
    ft2 = importlib.import_module("ft_seat_pi_ft2")
    got = ({"worktree": cwd, "at": AT}, "1", cwd)
    hit = put(root, own(cwd), cwd, ts="2026-11-15T01:00:30")
    put(root, "--other--", "/elsewhere", name="x", sid="x")
    opened.clear()
    assert ft2.first_session(got, root)[0] == str(hit)
    assert opened == [hit]
    (root / "--moved--").mkdir()
    moved = hit.rename(root / "--moved--" / hit.name)
    assert ft2.first_session(got, root)[0] == str(moved)
