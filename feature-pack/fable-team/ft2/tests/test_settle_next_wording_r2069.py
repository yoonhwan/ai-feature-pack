"""r2069 keeper session-absent «다음 수» 문구 — UNKNOWN [긴급] 본문 끝 = «다음 수 산출 가지 확인 → 인수 또는 반환» (카드 반례 ①②③④ · 변이 M1).
대역 = r2055 settle 한 길 시험의 world·nano·rnd(임시 root · 가짜 tmux·mbox · 주입 시계) 그대로 · ① = 코어 CLI claim→start→effect→result(owner 풀림) 실 꼴.
② owner 없음 ∧ result 없음 꼴은 코어 CLI 로 못 만듦 → settle_nano 직접(r2214 대역과 같은 길) · tmux-error = probe 주입. 실 tmux·실 발신·sleep 0.
기준판(팩 origin/main 6d45071f) = ① ② Red(«다음 수 판독 확인») · ③ ④ = 지킴. ⑤ 회귀 = r2055 세 시험 파일 재실행.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("settle_r2069", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
s = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(s)
TEAM, KS = s.TEAM, "adapters/pi/keeper_settle.py"
WANT = "· 다음 수 산출 가지 확인 → 인수 또는 반환"


def cli(w, *argv):
    out, rc = w.CLI.run(list(argv) + ["--root", str(w.root), "--team", TEAM])
    assert rc == 0, out
    return out


def urgent(w, work):
    return [x for x in s.sent(w) if "[긴급] UNKNOWN %s %s " % (TEAM, work) in x]


def c1(w):   # ① 세션 0 · done 아님 · result 줄 있음(owner 풀림) → [긴급] 1통 · 본문 끝 = 새 문구 · 판정 줄 그대로
    h = s.nano(w, "r9691", alive=False)
    g = str(cli(w, "claim", "--work", "r9691", "--holder", h)["gen"])
    for argv in (["start"], ["effect", "--effect", "push"], ["result"]):
        cli(w, argv[0], "--work", "r9691", "--holder", h, "--gen", g, *argv[1:])
    assert cli(w, "project")["works"]["r9691"]["owner"] is None
    lines = s.rnd(w)
    assert s.has(lines, "UNKNOWN %s r9691 %s session-absent" % (TEAM, h)), lines
    got = urgent(w, "r9691")
    assert len(got) == 1 and got[0].endswith(WANT), got


def c2(w):   # ② 같은 조건 · result 줄 없음 → 같은 문구 1통 / 같은 바퀴 한 번 더 → 0통(지문)
    h = s.nano(w, "r9692", alive=False)
    k = w.keeper()
    for _ in range(2):
        k.cache = {"@round": {}}
        k.settle_nano(TEAM, "r9692", "a1", h, {"owner": None, "done": False}, "")
    got = urgent(w, "r9692")
    assert len(got) == 1 and got[0].endswith(WANT), got
    assert k.lines[0] == "UNKNOWN %s r9692 %s session-absent" % (TEAM, h), k.lines


def c3(w):   # ③ owner 남음 = owner-orphan 문구 그대로 · tmux 판독 실패 = «판독 확인» 그대로
    s.nano(w, "r9693", alive=False)
    s.rnd(w)
    h = s.nano(w, "r9694", alive=False)
    k = w.keeper()
    k.cache, k.probe = {"@round": {}}, lambda seat: "rc 1 tmux 실패"
    k.settle_nano(TEAM, "r9694", "a1", h, {"owner": None, "done": False}, "")
    a, b = urgent(w, "r9693"), urgent(w, "r9694")
    assert len(a) == 1 and " owner-orphan" in a[0] and a[0].endswith("· 다음 수 owner·intent 대조 뒤 손 park"), a
    assert len(b) == 1 and " tmux-error" in b[0] and b[0].endswith("· 다음 수 판독 확인"), b


def c4(w):   # ④ done ∧ 세션 0 → PARKED session-absent 줄 · [긴급] 0
    h = s.nano(w, "r9695", alive=False)
    k = w.keeper()
    k.cache = {"@round": {}}
    k.settle_nano(TEAM, "r9695", "a1", h, {"owner": None, "done": True}, "")
    assert k.lines == ["PARKED %s r9695 %s session-absent" % (TEAM, h)] and not urgent(w, "r9695"), k.lines


CASES = {"①": c1, "②": c2, "③": c3, "④": c4}
MUTANTS = {"M1": ('"session-absent": "산출 가지 확인 → 인수 또는 반환", ', "", c1)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](s.world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(s.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(s.world(tmp_path / "w1", monkeypatch, tree))
    case(s.world(tmp_path / "w2", monkeypatch))
