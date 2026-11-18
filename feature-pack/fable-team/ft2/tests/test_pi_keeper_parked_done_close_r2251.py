"""r2251 ft2 keeper — 쉼(parked · idle-done) 뒤 complete 된 work 를 다음 바퀴에 B2 로 닫는다(O1 쉼 ∧ done 해제 · O2 닫기 길 그대로 · O3 반환 그대로 · O4 불변).
대역 = r1812 World(임시 리포·가짜 tmux·주입 시계) + r2026 가짜 card_stage(호출 기록) · park·return·complete = 실 CLI(임시 원장) · 실 kill·네트워크 0 · sleep 0.
①~⑥(⑥′ 사이 끼움 칸) · 변이 M1(done 조건 뺌 → ⑤) · M2(반환도 해제 → ③) · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)."""
import importlib.util
import re
import shutil
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r2251_wire", str(Path(__file__).with_name("test_pi_keeper_card_stage_wire_r2026.py")))
wire = importlib.util.module_from_spec(_S)
_S.loader.exec_module(wire)
World, Fake, keeper, AT, FT2 = wire.World, wire.Fake, wire.keeper, wire.AT, wire.FT2
TEAM, MASTER, STAGED = "harness", "M-harness", ("r-x", "진행→완성", "c0ffee")


def cli(w, *argv):
    out, rc = w.CLI.run(list(argv) + ["--root", str(w.root), "--team", TEAM])
    assert rc == 0, (argv, out)
    return out


def made(w, mp, work, via="parked", reason="idle-done", done=True):
    """착지 카드 + dispatch a1(intent · 유휴 나노 세션) → (쉼 | 반환) a1 → (complete a1) — 전부 keeper 밖(실 CLI)."""
    w.enable(), w.card(work, w.pack_sha())
    holder = w.work(work, alive=True)
    if via == "parked":
        cli(w, "park", "--work", work, "--attempt", "a1", "--reason", reason)
    if via == "returned":   # r1990 반환 = owner 0 이어야 함 → claim·start·result 뒤 현역 master 손
        mp.setenv("FT_SEAT", holder)
        gen = cli(w, "claim", "--work", work, "--holder", holder)["gen"]
        for verb in ("start", "result"):
            cli(w, verb, "--work", work, "--holder", holder, "--gen", str(gen))
        mp.setenv("FT_SEAT", MASTER)
        cli(w, "return", "--work", work, "--attempt", "a1", "--evidence", "산출 0")
    if done:
        cli(w, "complete", "--work", work, "--attempt", "a1")
    return holder


def items(lines):
    got = [re.search(r"items=(\d+)/(\d+)", x) for x in lines if x.startswith("ROUND")]
    assert len(got) == 1 and got[0], lines
    return int(got[0].group(1)), int(got[0].group(2))


def mine(lines, work):
    return [x for x in lines if work in x.split()[:3]]


def c1(w, mp):   # ① 쉼 a1 → complete a1 · 유휴 → 1바퀴에 close 1(kill 1 · 부재 확인 · 영수 1 · handled) · 기준판 = close 0 · 판정 줄 0
    holder = made(w, mp, "r9511")
    k = keeper(w, Fake([STAGED]))
    lines = w.round(k)
    assert w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]], lines
    assert w.kinds("close_receipt") == 1 and "%s|r9511@a1" % TEAM in k.state["handled"], (w.journal(), lines)
    assert any(x.startswith("CLOSED-") for x in mine(lines, "r9511")), lines
    return k, lines


def c2(w, mp):   # ② ① 뒤 둘째 바퀴 → handled 라 gone · close 0 · 영수 1회
    c1(w, mp)
    lines = w.round(keeper(w, Fake([STAGED])))
    assert len(w.tmux("kill-session")) == 1 and w.kinds("close_receipt") == 1 and not mine(lines, "r9511"), lines


def c3(w, mp):   # ③ 반환 a1 → complete → close 0 · stage_card 1(r2140 K2 그대로)
    made(w, mp, "r9513", via="returned")
    fake = Fake([STAGED])
    lines = w.round(keeper(w, fake))
    assert fake.calls == [(TEAM, "r9513", AT)], (fake.calls, lines)
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0, lines


def c4(w, mp):   # ④ 쉼 LAUNCH_FAILED a1 ∧ done → close 0(parked_failed 가드)
    reason = type(keeper(w, Fake([STAGED]))).run_once.__globals__["settling"].LAUNCH_FAILED
    made(w, mp, "r9514", reason=reason)
    lines = w.round(keeper(w, Fake([STAGED])))
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0, lines


def c5(w, mp):   # ⑤ 쉼 a1 · done 아님 → gone 그대로 · B1 0(complete 0) · close 0 · 판정 줄 0
    made(w, mp, "r9515", done=False)
    lines = w.round(keeper(w, Fake([STAGED])))
    assert w.kinds("complete") == 0 and w.tmux("kill-session") == [] and not mine(lines, "r9515"), lines


def c6(w, mp):   # ⑥ R10 — ① 판 바퀴 items ≤ 분모 · 분모에 그 work 자리가 듦(book 같은 식) · 기준판 = 그 work 분모 0
    k, lines = c1(w, mp)
    got, total = items(lines)
    assert (TEAM, "r9511") not in k.skipped_works and got <= total, (k.skipped_works, lines)


def c6b(w, mp):   # ⑥′ 사이 끼움 칸 — 바퀴 시작(:500) 뒤 · team_round 앞 complete → 그 바퀴는 같은 투영(둘 다 gone) · items ≤ 분모 · 다음 바퀴 close
    holder = made(w, mp, "r9516", done=False)
    k = keeper(w, Fake([STAGED]))
    real = k.team_round

    def wedge(team):
        if not w.kinds("complete"):
            cli(w, "complete", "--work", "r9516", "--attempt", "a1")
        return real(team)
    k.team_round = wedge
    lines = w.round(k)
    got, total = items(lines)
    assert (TEAM, "r9516") in k.skipped_works and got <= total and w.tmux("kill-session") == [], (k.skipped_works, lines)
    lines = w.round(keeper(w, Fake([STAGED])))
    assert w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]] and w.kinds("close_receipt") == 1, lines


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑥′": c6b}
KP = "adapters/pi/keeper.py"
MUTANTS = {"M1": ('            gone -= {work for work in open_ if (works.get(work) or {}).get("done")}', "            gone -= open_", ("⑤",)),
           "M2": ('settling.LAUNCH_FAILED} - back   # r2251 O3', 'settling.LAUNCH_FAILED} | back   # r2251 O3', ("③",))}


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
    (tmp_path / "o").mkdir()   # 원본 대조 = 같은 사례가 원본에서는 통과(반대 결과)
    CASES[case](World(tmp_path / "o", monkeypatch), monkeypatch)
