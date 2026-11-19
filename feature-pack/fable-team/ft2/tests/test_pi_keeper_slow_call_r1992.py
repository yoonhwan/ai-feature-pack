"""r1992 keeper — 바깥 호출 1회(시도마다) ≥ SLOW_S(5초)면 «SLOW-CALL <팀> <칸> <argv 앞 3낱말> s= rc= try=n/m» 1줄 · 동작 변경 0 — 반례 ①~⑦ · 변이 M1·M2.
대역 = r1812 World(임시 리포·가짜 tmux·주입 시계 w.t) + 가짜 호출(argv 끝 SLOWFAKE = subprocess.run 가로채 시계만 민다) · 실 세션 0 · sleep 0.
⑦ = ROUND 줄은 그대로 · 바로 앞 SLOW-CELL 1줄(slow 칸 팀·칸·초·호출 시도 수 n·SLOW-CALL 합)."""
import importlib.util
import shutil
import subprocess
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r1992_kw", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
World, FT2, M = kw.World, kw.FT2, "SLOWFAKE"
def fake(w, mp, plan):
    """plan = [(초, rc)] · rc "T" = 넘침 · SLOWFAKE 아닌 호출 = 실제 실행."""
    real = subprocess.run
    def run(argv, *a, **o):
        if not argv[-1].endswith(M):
            return real(argv, *a, **o)
        dt, rc = plan.pop(0)
        w.t += dt
        if rc == "T":
            raise subprocess.TimeoutExpired(argv, 7)
        return subprocess.CompletedProcess(argv, rc, "", "")
    mp.setattr(subprocess, "run", run)
def slow(k):
    return [x for x in k.lines if x.startswith("SLOW-CALL")]
def one(w, mp, plan, argv=("git", "status", M), team="aa", stage="b1", retry=0):
    fake(w, mp, list(plan))
    k = w.keeper()
    k.at = team
    k.timed(stage, k.call, list(argv), 7, retry)
    return slow(k)
def c1(w, mp):   # ① 6초 → 1줄(팀·칸·argv 앞 3낱말·초·rc·시도)
    assert one(w, mp, [(6, 0)]) == ["SLOW-CALL aa b1 git status SLOWFAKE s=6 rc=0 try=1/1"]
def c2(w, mp):   # ② 4초 → 0줄 · 5초 = 문턱 안(≥)
    assert one(w, mp, [(4, 0)]) == [] and one(w, mp, [(5, 1)]) == ["SLOW-CALL aa b1 git status SLOWFAKE s=5 rc=1 try=1/1"]
def c3(w, mp):   # ③ 넘침(rc None) → 1줄 rc=None · r2098 R7 로컬 git 7초 넘음 = 판정 불가 1줄 + Ungraded(그 자리 남은 판정 0)
    assert one(w, mp, [(7, "T")], ("tmux", "has-session", M)) == ["SLOW-CALL aa b1 tmux has-session SLOWFAKE s=7 rc=None try=1/1"]
    fake(w, mp, [(7, "T")])
    k = w.keeper()
    k.at = "aa"
    with pytest.raises(BaseException) as got:   # R7 = 끊김(Cut)이 아니라 판정 불가 → 그 자리만 0
        k.timed("b1", k.call, ["git", "status", M], 7, 0)
    assert type(got.value).__name__ == "Ungraded", got.value
    assert "판정 불가 aa - git 7초 넘음" in k.lines, k.lines
def c4(w, mp):   # ④ 재시도 2회 각 6초 → 2줄 try=1/2 · 2/2 (합 12 한 줄 0)
    assert [x.split()[-3:] for x in one(w, mp, [(6, 1), (6, 1)], retry=1)] == [["s=6", "rc=1", "try=1/2"], ["s=6", "rc=1", "try=2/2"]]
def c5(w, mp):   # ⑤ 팀 밖(fetch) → 팀 칸 «-» · jsonl team 도 «-»
    got = one(w, mp, [(6, 0)], ("git", "-C", str(w.root), "fetch", M), None, "fetch")
    assert got == ["SLOW-CALL - fetch git %s fetch s=6 rc=0 try=1/1" % w.root.name], got
def c6(w, mp):   # ⑥ 토큰·긴 경로 → 앞 3낱말 · git -C <repo> = repo 이름만 · 실행 파일 경로 = 끝 이름
    got = one(w, mp, [(6, 0)], ("git", "-C", "/very/long/secret/path/BYZ-Agents", "push", "--token=ghp_" + M))
    got += one(w, mp, [(6, 0)], ("/opt/homebrew/bin/gh", "pr", "list", "--token", "t0k" + M))
    assert [x.split(" s=")[0] for x in got] == ["SLOW-CALL aa b1 git BYZ-Agents push", "SLOW-CALL aa b1 gh pr list"], got
    assert not any(s in x for x in got for s in ("/very", "secret", "ghp_", "t0k", "homebrew")), got
def c7(w, mp):   # ⑦ slow 칸 = b2c 호출 3회(2·2·6초) → SLOW-CELL 1줄 n=3 · slow_call=6 · ROUND 줄 형식 그대로
    fake(w, mp, [(2, 0), (2, 0), (6, 0)])
    w.card("r9921", w.pack_sha()), w.work("r9921", intent=False)
    k = w.keeper()
    k.complete, k.retired = (lambda *a: True), (lambda: None)
    k.close = lambda *a: [k.call(["tmux", "has", M]) for _ in range(3)] and None
    rows = [x for x in w.round(k) if x.startswith(("SLOW-CELL", "ROUND"))]
    assert (rows[0] == "SLOW-CELL harness b2c s=10 n=3 slow_call=6" or rows[0].startswith("SLOW-CELL harness b2c s=10 n=3 slow_call=6 top=")) and rows[1].startswith("ROUND s=10 ") and " slow=harness:b2c:10" in rows[1], rows
    assert slow(k) == ["SLOW-CALL harness b2c tmux has SLOWFAKE s=6 rc=0 try=1/1"]
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
KP = "adapters/pi/keeper.py"
MUTANTS = {"M1": ("if dt >= SLOW_S:", "if dt < SLOW_S:", c1), "M1b": ("if dt >= SLOW_S:", "if dt < SLOW_S:", c2),
           "M2": ("            at = self.now()\n            over = False\n            try:\n                done", "            at = getattr(self, 'm2', None) or self.now()\n            self.m2 = at\n            over = False\n            try:\n                done", c4)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch), monkeypatch)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree), monkeypatch)
