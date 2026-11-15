"""r1990 — 전달됐지만 착지 0·owner 0 인 최신 attempt 를 현역 master 가 `return` 1줄로 큐에 되돌린다(실 CLI · 임시 원장).
반례 ① r1976 꼴 → OK · 남은 일 −1 · keeper 바퀴 HELD 0 · 같은 카드 a2(accept 1줄) · 남은 일 +1 · a1 재호출 = 낡음
② owner ③ uncertain ④ done ⑤ 낡은 attempt ⑥ master 아님 = 거부·바이트 불변 ⑦ 같은 줄 두 번 = 쓰기 0.
변이 M1 owner 검사 삭제 → ② · M2 남은 일 셈 그대로 → ① · M3 choose 가 반환을 끝남 → ① · M4 keeper 건너뜀 삭제 → ①. 실 원장·tmux·설치 0 · sleep 0.

㉘너·㉘더·㉘러(ft2-launch-failed-end L11 · r2065 덧 고침) — 코어 현역 master 판독도 «명부 찾기 한 함수»(seats-<팀>.json → 없고 v65 면 seats.json · 그 밖 None)를 부른다.
㉘너 v65 팀 · seats-v65.json 없음 · seats.json `_master` = 손 → return 접수(returned 1줄) · confirm 도 같은 판정
㉘더 명부 둘 다 없음 → 접수 거부 · 쓰기 0 · revision 그대로 · ㉘러 v65 아닌 팀 · seats.json 만 있음 → 접수 거부(넘어가지 않음). M71 `_master` 경로를 조립으로 되돌림 → ㉘너 FAIL.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1990_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw, TEAM, R, EV = base.kw, "harness", "r9990", "HEAD = base · 산출 0 · 세션 0"
NANO, MASTER = "byz-harness-nano-r9990#0", "M-harness"
TEAM_V, MASTER_V = "v65", "M-v65"   # ㉘너 = v65 팀(명부 이름 = seats.json · seats-v65.json 은 없다)


def deliver_and_result(cli, root, mp, work=R, result=True, team=TEAM):
    """r1976 꼴 = keeper-next 접수 → 배정 a1 → 전달 → 나노 claim·start → result(owner 0 · done 0)."""
    mp.setenv("FT_SEAT", NANO)
    steps = [["submit", "--command", "keeper-next-" + work, "--body", "카드 " + work, "--work", work],
             ["assign", "--work", work, "--holder", NANO, "--evidence", "v1,v2"], ["deliver", "--work", work],
             ["claim", "--work", work, "--holder", NANO], ["start"]] + ([["result"]] if result else [])
    gen = None
    for argv in steps:
        argv = argv if len(argv) > 1 else argv + ["--work", work, "--holder", NANO, "--gen", str(gen)]
        out, rc = cli.run(argv + ["--root", str(root), "--team", team])
        assert rc == 0, (argv, out)
        gen = out.get("gen")
    return gen


def give_back(cli, root, mp, attempt="a1", seat=MASTER, work=R, team=TEAM):
    mp.setenv("FT_SEAT", seat)
    return cli.run(["return", "--work", work, "--attempt", attempt, "--evidence", EV, "--root", str(root), "--team", team])


def left(cli, root, team=TEAM):
    return cli.run(["project", "--root", str(root), "--team", team])[0]["remaining"]


def journal(root, team=TEAM):
    path = Path(root) / ".fable-team" / "teams" / team / "runtime" / "journal.jsonl"
    return [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]


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


def test_no_roster_refused(tmp_path, monkeypatch):   # ㉘더
    """명부 둘 다 없음 = seats-harness.json·seats.json 0 → 현역 master 판독 None = 접수 거부 · 쓰기 0 · revision 그대로."""
    cli = kw._mod(kw.FT2 / "core" / "cli.py", "c1990_neod_%d" % id(tmp_path))
    deliver_and_result(cli, tmp_path, monkeypatch)
    before, rev = snap(tmp_path), cli.run(["project", "--root", str(tmp_path), "--team", TEAM])[0]["revision"]
    out, rc = give_back(cli, tmp_path, monkeypatch)
    assert (out["result"], rc) == ("접수 거부", 1) and "master" in out["reason"], out
    assert snap(tmp_path) == before
    assert cli.run(["project", "--root", str(tmp_path), "--team", TEAM])[0]["revision"] == rev


def test_non_v65_does_not_fall_through(tmp_path, monkeypatch):   # ㉘러
    """v65 아닌 팀 · seats-harness.json 없음 · seats.json 만 있음 → 넘어가지 않고 접수 거부(명부 없음과 같다)."""
    cli = kw._mod(kw.FT2 / "core" / "cli.py", "c1990_neol_%d" % id(tmp_path))
    kw._put(tmp_path / ".fable-team" / "seats.json", {"_master": MASTER})
    assert not (tmp_path / ".fable-team" / "seats-harness.json").exists()
    deliver_and_result(cli, tmp_path, monkeypatch)
    before = snap(tmp_path)
    out, rc = give_back(cli, tmp_path, monkeypatch)
    assert (out["result"], rc) == ("접수 거부", 1) and "master" in out["reason"], out
    assert snap(tmp_path) == before


def test_v65_seats_master_not_refused(tmp_path, monkeypatch):   # ㉘너
    neon(tmp_path, monkeypatch)


def test_return_twice_writes_nothing(tmp_path, monkeypatch):   # ⑦
    cli = core(tmp_path, monkeypatch, kw.FT2)
    deliver_and_result(cli, tmp_path, monkeypatch)
    assert give_back(cli, tmp_path, monkeypatch)[1] == 0
    before = snap(tmp_path)
    assert give_back(cli, tmp_path, monkeypatch)[0]["written"] is False and snap(tmp_path) == before


def test_returned_reopens_same_card(tmp_path, monkeypatch):   # ①
    c1(tmp_path, monkeypatch, kw.FT2)


def neon(tmp, mp, ft2=kw.FT2):
    """㉘너 — v65 팀 · seats-v65.json 없음 · seats.json `_master` = 손 → return 접수 · confirm 도 같은 판정."""
    cli = kw._mod(ft2 / "core" / "cli.py", "c1990_neon_%d" % id(tmp))
    kw._put(Path(tmp) / ".fable-team" / "seats.json", {"_master": MASTER_V})
    assert not (Path(tmp) / ".fable-team" / "seats-v65.json").exists()
    gen = deliver_and_result(cli, tmp, mp, team=TEAM_V)                     # confirm 길 = 표식 → 같은 손
    assert cli._load("execution").Execution(str(tmp), TEAM_V).mark_uncertain(R, NANO, gen, "무응답").written
    mp.setenv("FT_SEAT", MASTER_V)
    out, rc = cli.run(["confirm", "--work", R, "--holder", NANO, "--gen", str(gen), "--word", "회수 결과",
                       "--evidence", EV, "--root", str(tmp), "--team", TEAM_V])
    assert (out["result"], out["stage"], rc) == ("접수 성공", "result", 0), out
    assert journal(tmp, TEAM_V)[-1]["confirmed_by"] == MASTER_V
    gen = deliver_and_result(cli, tmp, mp, work=R + "b", team=TEAM_V)      # return 길 = 접수 거부가 아님
    out, rc = give_back(cli, tmp, mp, work=R + "b", seat=MASTER_V, team=TEAM_V)
    assert (out["result"], rc) == ("접수 성공", 0), out
    assert [rec for rec in journal(tmp, TEAM_V) if rec["kind"] == "returned"][-1]["returned_by"] == MASTER_V


MUTANTS = {"M1": ("core/dispatch.py", '("owner 있음", work in (state.get("owners") or {}))', '("owner 있음", False)'),
           "M2": ("core/record.py", ' | set(state.get("returned") or {})', ""),
           "M3": ("adapters/pi/keeper_next.py", 'state.get("done") or {}, {}, []',
                  '{**(state.get("done") or {}), **(state.get("returned") or {})}, {}, []'),
           "M4": ("adapters/pi/keeper.py", ' or (work, attempt) in back:', ":"),   # 덤 · keeper 건너뜀 삭제 → ① HELD
           "M71": ("core/execution.py", "roster.roster_path(self.root, self.team)",
                   'os.path.join(self.root, ".fable-team", "seats-%s.json" % self.team)')}   # L11 · 명부 찾기 한 함수 되돌림 → ㉘너 FAIL


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
        neon(tmp_path / "w", monkeypatch, tree) if name == "M71" else (
            refused("② owner", tmp_path / "w", monkeypatch, tree) if name == "M1" else c1(tmp_path / "w", monkeypatch, tree))
