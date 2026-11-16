"""r2140 ft2 keeper — keeper 밖에서 complete 된 work 도 투영 done 이면 card_stage 1회(K1 done 갈래 · K2 쉼·반환 건너뜀) · 성공 기억(K3).
대역 = r1812 World(임시 리포·가짜 tmux·주입 시계) + r2026 가짜 card_stage(호출 기록) · complete·park·return = 실 CLI(임시 원장) · 실 BYZ 리포·실 push 0 · sleep 0.
①~⑤ · 변이 M1(K1 호출 삭제 → ①) · M2(K2 갈래 삭제 → ② ③) · M3(성공 기억 삭제 → ④)."""
import importlib.util
import shutil
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r2140_wire", str(Path(__file__).with_name("test_pi_keeper_card_stage_wire_r2026.py")))
wire = importlib.util.module_from_spec(_S)
_S.loader.exec_module(wire)
World, Fake, keeper, start, AT, FT2 = wire.World, wire.Fake, wire.keeper, wire.start, wire.AT, wire.FT2
TEAM, MASTER, STAGED = "harness", "M-harness", ("r-x", "진행→완성", "c0ffee")


def cli(w, *argv):
    out, rc = w.CLI.run(list(argv) + ["--root", str(w.root), "--team", TEAM])
    assert rc == 0, (argv, out)
    return out


def ext_done(w, work, mp, via=""):
    """dispatch a1 → (parked | returned) a1 → complete a1 — 전부 keeper 밖(실 CLI)."""
    start(w, work)
    holder = "byz-%s-nano-%s-t#0" % (TEAM, work)
    if via == "parked":
        cli(w, "park", "--work", work, "--attempt", "a1", "--reason", "idle-done")
    if via == "returned":   # r1990 반환 = owner 0 이어야 함 → claim·start·result 뒤 현역 master 손
        mp.setenv("FT_SEAT", holder)
        gen = cli(w, "claim", "--work", work, "--holder", holder)["gen"]
        for verb in ("start", "result"):
            cli(w, verb, "--work", work, "--holder", holder, "--gen", str(gen))
        mp.setenv("FT_SEAT", MASTER)
        cli(w, "return", "--work", work, "--attempt", "a1", "--evidence", "산출 0")
    cli(w, "complete", "--work", work, "--attempt", "a1")
    assert w.kinds("complete") == 1 and (not via or w.kinds(via) == 1), w.journal()


def stages(lines, *kinds):
    return [x for x in lines if x.split(" ", 1)[0] in kinds]


def quiet(w, work):   # K2 = complete·close·깨움 0(keeper 손 줄 0)
    mail = Path(str(w.mbox) + ".log")
    sent = [x for x in (mail.read_text(encoding="utf-8").splitlines() if mail.exists() else []) if work in x]
    assert w.kinds("complete") == 1 and not w.tmux("kill-session") and not sent, (w.journal(), sent)


def c1(w, mp):   # ① 남이 complete(쉼 0) → 한 바퀴 card_stage 1회(work·at) · CARD-STAGE 1줄 · 닫기 판정은 card_stage 없는 판과 같다
    ext_done(w, "r9401", mp)
    fake = Fake([STAGED])
    lines = w.round(keeper(w, fake))
    assert fake.calls == [(TEAM, "r9401", AT)], (fake.calls, lines)
    assert stages(lines, "CARD-STAGE") == ["CARD-STAGE harness r9401 진행→완성 c0ffee"], lines
    assert w.kinds("complete") == 1 and not w.tmux("kill-session"), lines


def two(via):
    def case(w, mp):   # ② 쉼(parked) · ③ 반환(returned) 뒤 complete → card_stage 1회 · complete·close·깨움 0
        ext_done(w, "r9402", mp, via)
        fake = Fake([STAGED])
        lines = w.round(keeper(w, fake))
        assert fake.calls == [(TEAM, "r9402", AT)] and len(stages(lines, "CARD-STAGE")) == 1, (fake.calls, lines)
        quiet(w, "r9402")
    return case


def c4(w, mp):   # ④ ① · ② 다음 바퀴 2회 더(STAGED → NOOP) → 2·3 바퀴 호출 0(state 재로딩 = 바퀴마다 새 keeper)
    ext_done(w, "r9404", mp)
    w.card("r9405", w.pack_sha()), w.work("r9405", intent=False)
    cli(w, "park", "--work", "r9405", "--attempt", "a1", "--reason", "idle-done")
    cli(w, "complete", "--work", "r9405", "--attempt", "a1")
    fake = Fake([STAGED, None])
    w.round(keeper(w, fake))
    assert sorted(c[1] for c in fake.calls) == ["r9404", "r9405"], fake.calls
    for _ in range(2):
        lines = w.round(keeper(w, fake))
        assert len(fake.calls) == 2 and not stages(lines, "CARD-STAGE", "NOOP", "Unsure"), (fake.calls, lines)


def c5(w, mp):   # ⑤ 쉼 · done 아님 → card_stage 0(건너뜀) · keeper 자기 complete 의 Unsure 1회 → 다음 바퀴 재시도 1회(한 바퀴 두 번 0)
    start(w, "r9406")
    cli(w, "park", "--work", "r9406", "--attempt", "a1", "--reason", "idle-done")
    start(w, "r9407")
    fake = Fake([Fake.Unsure("push 결과 불명"), STAGED])
    lines = w.round(keeper(w, fake))
    assert fake.calls == [(TEAM, "r9407", AT)] and len(stages(lines, "Unsure")) == 1, (fake.calls, lines)
    lines = w.round(keeper(w, fake))
    assert [c[1] for c in fake.calls] == ["r9407", "r9407"] and len(stages(lines, "CARD-STAGE")) == 1, (fake.calls, lines)
    w.round(keeper(w, fake))
    assert len(fake.calls) == 2 and w.kinds("complete") == 1, fake.calls


CASES = {"①": c1, "②": two("parked"), "③": two("returned"), "④": c4, "⑤": c5}
KP = "adapters/pi/keeper.py"
MUTANTS = {"M1": ('            self.timed("b1", self.stage_card, team, work)   # r2140 K1', "", ("①",)),
           "M2": ('                self.timed("b1", self.stage_card, team, work)   # r2140 K2', "                pass", ("②", "③")),
           "M3": ('        self.state["staged"][key] = day', "", ("④",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch), monkeypatch)


@pytest.mark.parametrize("name,case", [(m, c) for m, (_o, _n, cs) in MUTANTS.items() for c in cs])
def test_mutant(name, case, tmp_path, monkeypatch):
    old, new, _cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        CASES[case](World(tmp_path / "w", monkeypatch, tree), monkeypatch)
