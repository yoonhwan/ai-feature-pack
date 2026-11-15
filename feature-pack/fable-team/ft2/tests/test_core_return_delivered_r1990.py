"""r1990 — 전달됐지만 착지 0·owner 0 인 최신 attempt 를 현역 master 가 `return` 1줄로 큐에 되돌린다(실 CLI · 임시 원장).
반례 ① r1976 꼴 → OK · 남은 일 −1 · keeper 바퀴 HELD 0 · 같은 카드 a2(accept 1줄) · 남은 일 +1 · a1 재호출 = 낡음
② owner ③ uncertain ④ done ⑤ 낡은 attempt ⑥ master 아님 = 거부·바이트 불변 ⑦ 같은 줄 두 번 = 쓰기 0.
변이 M1 owner 검사 삭제 → ② · M2 남은 일 셈 그대로 → ① · M3 choose 가 반환을 끝남 → ① · M4 keeper 건너뜀 삭제 → ①. 실 원장·tmux·설치 0 · sleep 0.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1990_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw, TEAM, R, EV = base.kw, "harness", "r9990", "HEAD = base · 산출 0 · 세션 0"
NANO, MASTER = "byz-harness-nano-r9990#0", "M-harness"


def deliver_and_result(cli, root, mp, work=R, result=True):
    """r1976 꼴 = keeper-next 접수 → 배정 a1 → 전달 → 나노 claim·start → result(owner 0 · done 0)."""
    mp.setenv("FT_SEAT", NANO)
    steps = [["submit", "--command", "keeper-next-" + work, "--body", "카드 " + work, "--work", work],
             ["assign", "--work", work, "--holder", NANO, "--evidence", "v1,v2"], ["deliver", "--work", work],
             ["claim", "--work", work, "--holder", NANO], ["start"]] + ([["result"]] if result else [])
    gen = None
    for argv in steps:
        argv = argv if len(argv) > 1 else argv + ["--work", work, "--holder", NANO, "--gen", str(gen)]
        out, rc = cli.run(argv + ["--root", str(root), "--team", TEAM])
        assert rc == 0, (argv, out)
        gen = out.get("gen")
    return gen


def give_back(cli, root, mp, attempt="a1", seat=MASTER, work=R):
    mp.setenv("FT_SEAT", seat)
    return cli.run(["return", "--work", work, "--attempt", attempt, "--evidence", EV, "--root", str(root), "--team", TEAM])


def left(cli, root):
    return cli.run(["project", "--root", str(root), "--team", TEAM])[0]["remaining"]


def snap(root):
    return tuple(p.read_bytes() for p in sorted(Path(root, ".fable-team", "teams", TEAM, "runtime").rglob("*")) if p.is_file())


def c1(tmp, mp, ft2):   # ① 반환 → 남은 일 −1 · keeper HELD 0 · 같은 카드 a2 · 남은 일 +1 · accept 1줄 · a1 낡음
    w = base.world(tmp, mp, {R: "- 긴급: 예\n"}, ft2=ft2)
    deliver_and_result(w.CLI, w.root, mp)
    before = left(w.CLI, w.root)
    out, rc = give_back(w.CLI, w.root, mp)
    assert (out["result"], out["stage"], rc) == ("접수 성공", "returned", 0), out
    assert w.journal()[-1]["kind"] == "returned" and left(w.CLI, w.root) == before - 1
    k = w.keeper()   # 반환 뒤 첫 바퀴 = a1 HELD 0 · fill 이 a2 를 띄움(뒤 바퀴의 a2 진행 중 HELD 는 보통 일)
    assert k.run_once() == 0 and not [x for x in k.lines if x.startswith(tuple("%s harness %s " % (v, R) for v in ("HELD", "UNKNOWN", "WORKING", "PARKED")))], k.lines   # r2055 HELD → 판정 4낱말
    [p.wait(25) for p in k.cache.pop("spawned", [])]
    w.round()
    assert base.count(w, "dispatch", R) == 2 and base.count(w, "accept", R) == 1 and R in base.launched(w)
    assert left(w.CLI, w.root) == before
    assert give_back(w.CLI, w.root, mp)[0]["result"] == "접수 거부"


def core(tmp, mp, ft2):
    cli = kw._mod(ft2 / "core" / "cli.py", "c1990_%d" % id(tmp))
    kw._put(tmp / ".fable-team" / "seats-harness.json", {"_master": MASTER})
    return cli


def refused(case, tmp, mp, ft2=kw.FT2):
    cli = core(tmp, mp, ft2)
    gen = deliver_and_result(cli, tmp, mp, result=case not in ("② owner", "③ uncertain"))
    if case == "③ uncertain":   # 표식 = owner 도 남는다 · 사유 칸으로 미확정 거부를 가른다
        assert cli._load("execution").Execution(str(tmp), TEAM).mark_uncertain(R, NANO, gen, "무응답").written
    if case == "④ done":
        assert cli.run(["complete", "--work", R, "--attempt", "a1", "--root", str(tmp), "--team", TEAM])[1] == 0
    before = snap(tmp)
    out, rc = give_back(cli, tmp, mp, attempt="a0" if case == "⑤ 낡은" else "a1", seat=NANO if case == "⑥ 나노 손" else MASTER)
    why = {"② owner": "owner", "③ uncertain": "미확정", "④ done": "완료", "⑤ 낡은": "낡은", "⑥ 나노 손": "master"}[case]
    assert (out["result"], rc) == ("접수 거부", 1) and why in out["reason"], out
    assert snap(tmp) == before


@pytest.mark.parametrize("case", ["② owner", "③ uncertain", "④ done", "⑤ 낡은", "⑥ 나노 손"])
def test_refused(case, tmp_path, monkeypatch):
    refused(case, tmp_path, monkeypatch)


def test_return_twice_writes_nothing(tmp_path, monkeypatch):   # ⑦
    cli = core(tmp_path, monkeypatch, kw.FT2)
    deliver_and_result(cli, tmp_path, monkeypatch)
    assert give_back(cli, tmp_path, monkeypatch)[1] == 0
    before = snap(tmp_path)
    assert give_back(cli, tmp_path, monkeypatch)[0]["written"] is False and snap(tmp_path) == before


def test_returned_reopens_same_card(tmp_path, monkeypatch):   # ①
    c1(tmp_path, monkeypatch, kw.FT2)


MUTANTS = {"M1": ("core/dispatch.py", '("owner 있음", work in (state.get("owners") or {}))', '("owner 있음", False)'),
           "M2": ("core/record.py", ' | set(state.get("returned") or {})', ""),
           "M3": ("adapters/pi/keeper_next.py", 'state.get("done") or {}, {}, []',
                  '{**(state.get("done") or {}), **(state.get("returned") or {})}, {}, []'),
           "M4": ("adapters/pi/keeper.py", ' or (work, attempt) in back:', ":")}   # 덤 · keeper 건너뜀 삭제 → ① HELD


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        refused("② owner", tmp_path / "w", monkeypatch, tree) if name == "M1" else c1(tmp_path / "w", monkeypatch, tree)
