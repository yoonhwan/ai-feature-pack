"""r1960 keeper 끝 결과 닫기 변이 M1~M10 (사본 ft2 에서만 · 변이마다 원본으로 같은 사례 1회 더) — r2299 사례 파일과 70초 나눔(이름·단언 그대로)."""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest
FT2 = Path(__file__).resolve().parents[1]
_S = importlib.util.spec_from_file_location("r1960_cases_for_mut", str(FT2 / "tests" / "test_pi_keeper_endings_r1960.py"))
C = importlib.util.module_from_spec(_S)
_S.loader.exec_module(C)
world, c1b, c1s, c2, c3, c4, c4b, c5, c6, c7b, c7d = C.world, C.c1b, C.c1s, C.c2, C.c3, C.c4, C.c4b, C.c5, C.c6, C.c7b, C.c7d
KE, KC, KP = "adapters/pi/keeper_endings.py", "adapters/pi/keeper_close.py", "adapters/pi/keeper.py"
SNAP = 'H, alive = _mod("holders", os.path.join(HERE, "ft2_holders.py")), k.alive_sessions()\n    held_by = {t: {h for _, h in got.values()} for t in teams if (got := latest(k, t)) is not None}'
MUTANTS = {"M1": (KE, 'prs = _prs(k, REPO.search(url).group(1) if REPO.search(url) else url, "nano/" + work)', 'prs = [{"number": 0, "mergeCommit": {"oid": k.git(tree, "rev-parse", "HEAD")[1].strip()}, "baseRefName": "main"}]', c1b),
           "M2": (KE, '        return _resolved_end(k, team, work)\n    land = _mod("land", os.path.join(HERE, "keeper_land.py"))\n    for ref in land.REFS:', '        return _resolved_end(k, team, work)\n    if any(r.get("kind") == "refuse" and r.get("work") == work for r in _proj().journal.Journal(_proj().runtime_path(k.root, team), rec=_proj().record).records()):\n        return "refused", "journal refuse"\n    land = _mod("land", os.path.join(HERE, "keeper_land.py"))\n    for ref in land.REFS:', c2),
           "M3": (KE, 'r.get("FT2_HOLDER") == holder', 'r.get("FT2_HOLDER") is False', c4),
           "M4": (KC, 'return self.unknown_seat(team, work, attempt, dispatched, "intent-none"', 'return None and self.unknown_seat(team, work, attempt, dispatched, "intent-none"', c4b),   # r2055 held → unknown_seat
           "M5": (KE, "st.wake(team, work, holder, key, idle, fmt, slot)", "None", c5),
           "M6": (KC, "if not self.idle(team, work, holder, attempt):   # kill 직전 가드", "if not (ending or self.idle(team, work, holder, attempt)):", c6),
           "M7": (KE, SNAP, "\n    ".join(SNAP.split("\n    ")[::-1]), c7d),
           "M8": (KE, "H.auto_opened(k.call, k.tmux, seat, it) if work", '(True, "") if work', c7b),
           "M10": (KE, 'if bad := [r for r in sorted(getattr(k, "stale", ())) if _common(k, r) == _common(k, tree)]:', "if bad := []:", c1s),
           "M9": (KP, "if self.sock and endings.ending(self, team, work):", "if self.sock and endings.ending(self, team, work) and (land.cli.run(['complete', '--root', self.root, '--team', team, '--work', work, '--attempt', attempt]) or True):", c3)}   # r2000 — complete() 는 남은 범위 관문이 먼저 막으므로 cli complete 를 바로 부른다
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    shutil.copytree(FT2, copy := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / rel).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(world(case, tmp_path / "w1", monkeypatch, copy))
    case(world(case, tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
