"""ft2 keeper ROUND 칸 셈 — `b1=` 은 착지 판정 초 · `items=` 분모는 그 바퀴에 돌 수 있는 자리 (반례 ㊻가~아 · 변이 M109~M112).

카드 ft2-keeper-round-cells-b1-items · 계약 H1(`b1=` = landing + complete) · H2(`items=` 분모) · H3(그대로) · H4(`other=` 식 그대로).
대역(카드 «시험 입력»): test_keeper_round_60s.Rig 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run(요청 상한과 자기 소요 중 작은 값만큼 시계를 올린다) ·
가짜 journal·tmux·mbox(인자만 기록) · sleep 0 · 네트워크 0 · 실 runtime·실 git·실 tmux 0. 새 대역 0.
"""
import shutil

import pytest

import keeper_world_r1812 as W
from test_keeper_round_60s import FT2, KP, Rig, _next, field, line


def _rows(w, *extra):
    """그 팀 journal 줄 — dispatch 는 Rig 기본값 · extra = 반환·쉼 줄(r1990·r2055)."""
    return w.rows("t1") + list(extra)


def _burn(w):
    """b1 에서 예산을 다 쓴다 — git 판독 7초씩, 남은 몫이 7초보다 작아지면 그 자리에서 끊긴다(Cut)."""
    return w.reads(("git", "show", "HEAD:card.md"), 7.0, 12)


# ── ㊻ H1 · H2 ────────────────────────────────────────────────────────────────
def c_ga(w):   # ㊻가 착지 판정의 git 호출 6초 · complete 0초 → b1=6 · other=0 · wall 그대로
    def land(team, work):
        w.reads(("git", "show", "HEAD:card.md"), 6.0)   # landing 안의 바깥 호출
        w.done.append(["land", team, work])
        return ("ab" * 20, "main", "")
    w.k.landing = land
    w.round()
    assert field(w.k, "b1") == "6" and field(w.k, "other") == "0", w.k.lines   # 초가 other= 로 새지 않는다
    assert field(w.k, "wall") == "6" and field(w.k, "fetch_root") == "0", w.k.lines


def c_na(w):   # ㊻나 handled 2 · 진행 1(complete=False = 닫지 않음) · 끊김 없음 → items=N/N (DA R1 기대 5/5)
    w.works = {"t1": ["w1", "w2", "w3"]}
    w.k.rows_of = lambda team: _rows(w, {"kind": "returned", "work": "w1", "attempt": "a1"},
                                        {"kind": "returned", "work": "w2", "attempt": "a1"})
    w.k.complete = lambda *a: False   # 진행 = b1 뒤 stall 길(닫기 자리 없음)
    w.round()
    assert field(w.k, "items") == "5/5" and field(w.k, "cut") == "-", w.k.lines   # b1·stall·b2f·b3o·b3r — w3 의 b2c 는 안 도는 자리


def c_da(w):   # ㊻다 work 2 · 최신 attempt 반환 1 · 쉼 1(열기 실패 아님) · 끊김 없음 → items=N/N
    w.works = {"t1": ["w1", "w2"]}
    w.k.rows_of = lambda team: _rows(w, {"kind": "returned", "work": "w1", "attempt": "a1"},
                                        {"kind": "parked", "work": "w2", "attempt": "a1", "reason": "idle"})
    w.round()
    assert field(w.k, "items") == "3/3" and field(w.k, "cut") == "-", w.k.lines   # b2f·b3o·b3r 만 돈다


def c_ra(w):   # ㊻라 열기 실패 쉼(LAUNCH_FAILED)인 work 는 건너뛰지 않는다 = 끊긴 자리 뒤 남은 자리에 3개로 든다
    w.works = {"t1": ["w1", "w2"]}
    w.k.rows_of = lambda team: _rows(w, {"kind": "parked", "work": "w2", "attempt": "a1", "reason": "launch-failed"})
    w.k.landing = lambda team, work: _burn(w)
    w.round()
    assert field(w.k, "cut") == "t1:w1:b1" and field(w.k, "items") == "1/9", w.k.lines   # 1 + w1 b2c·stall 2 + w2 3 + b2f 1 + b3 2


def c_ma(w):   # ㊻마 진행 2 + handled 1 · 첫 진행 work 의 b1 에서 끊김 → cut=<팀>:<work>:b1 · items=1/9 · N 에 handled 자리 3개 없다
    w.works = {"t1": ["w1", "w2", "w3"]}
    w.room(handled=["t1|w3@a1"])
    w.k.landing = lambda team, work: _burn(w)
    w.round()
    assert field(w.k, "cut") == "t1:w1:b1" and field(w.k, "items") == "1/9", w.k.lines   # 1 + w1 b2c·stall 2 + w2 3 + b2f 1 + b3 2
    assert w.state()["cursor"] == {"team": "t1", "work": "w1", "stage": "b1", "cuts": 1}, w.state()
    w.k.lines[:] = []
    w.k, w.done = _next(w), []
    w.k.landing = lambda team, work: (w.done.append(["land", team, work]), ("ab" * 20, "main", ""))[1]
    w.round()
    assert [d[2] for d in w.done if d[0] == "land"][0] == "w1", w.done   # 이어받기 = cursor 그 자리부터(H3 그대로)


def c_a(w):   # ㊻아 진행 work 1개가 투영 done(b1 없이 닫기 자리로) · 끊김 없음 → items=N/N · b1=0
    w.k.project = lambda root, team: {"result": w.mod.OK, "works": {"w1": {"done": True}}}
    w.k.stage_card = lambda *a: None   # r2140 K1 = 초 0
    w.round()
    assert field(w.k, "items") == "4/4" and field(w.k, "b1") == "0", w.k.lines   # b2c·b2f·b3o·b3r — b1 자리는 남지 않는다


def c_ba(w):   # ㊻바 landing 안에서 Cut — Cut 은 그대로 올라가고 그때까지의 초가 b1= 에 든다 · cursor 자리 = b1
    w.k.landing = lambda team, work: _burn(w)
    w.round()
    assert field(w.k, "cut") == "t1:w1:b1" and field(w.k, "b1") == "45", w.k.lines   # 6회 7초 + 남은 몫 3초
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w1 b1 — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t1", "work": "w1", "stage": "b1", "cuts": 1}, w.state()


def c_sa(w):   # ㊻사 landing 이 Ungraded(git 7초 넘음) — 그 자리 남은 판정 0 · 다음 자리 · «판정 불가» 줄 그대로 · 그 초가 b1= 에 든다
    w.k.landing = lambda team, work: w.reads(("git", "show", "HEAD:card.md"), 8.0)
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 t1 w1 git 7초 넘음"], w.k.lines
    assert field(w.k, "b1") == "7" and field(w.k, "cut") == "-", w.k.lines   # 8초는 상한 7초에서 멈춘다
    assert field(w.k, "items") == "4/4", w.k.lines   # DA R1 기대 — 판정이 끝난 work 의 b2c·stall 은 안 도는 자리


def c_wait(w):   # R1 보강 landed 판정 뒤 land_ready=False(기다림) — 그 work 의 b2c·stall 은 안 도는 자리 → items=N/N
    w.k.land_ready = lambda *a: False
    w.round()
    assert field(w.k, "items") == "4/4" and field(w.k, "cut") == "-", w.k.lines
    assert field(w.k, "b1") == "0", w.k.lines   # 기다림에는 초가 들지 않는다


def c_r2(w):   # R2 첫 팀에서 끊기면 뒤 팀의 handled work 자리도 분모에서 빠진다 (DA 기대 1/7)
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    w.room(handled=["t2|w2@a1"])
    w.k.landing = lambda team, work: _burn(w)
    w.round()
    assert field(w.k, "cut") == "t1:w1:b1" and field(w.k, "items") == "1/7", w.k.lines   # 1 + t1 b2c·stall 2 + b2f 2 + b3 2


CASES = {"㊻가": c_ga, "㊻나": c_na, "㊻다": c_da, "㊻라": c_ra, "㊻마": c_ma, "㊻바": c_ba, "㊻사": c_sa, "㊻아": c_a,
         "R1-대기": c_wait, "R2-뒤팀": c_r2}
MUTANTS = {
    "M109": (KP, "        landed = self.timed(\"b1\", self.landing, team, work, work=work)", "        landed = self.landing(team, work)",
             ("㊻가", "㊻바", "㊻사")),
    "M110": (KP, " and (p[0], p[1]) not in self.skipped_works])", "])", ("㊻나", "㊻다")),
    "M111": (KP, 'if rec.get("kind") == "parked" and rec.get("reason") != settling.LAUNCH_FAILED', 'if rec.get("kind") == "parked"',
             ("㊻라",)),
    "M112": (KP, "return len([p for p in self.positions() if not self.before(*p) and p not in self.unused and (p[0], p[1]) not in self.skipped_works])",
             "return len(self.positions())", ("㊻나", "㊻아")),
}


def test_receipt_cells(tmp_path, monkeypatch):   # R3 (DA HOLD 2/3) 실제 완료→close→receipt 경로 = 이번 방문 자리를 분모에서 빼지 않는다
    """Rig 의 close 대역은 state.handled 를 안 바꿔 이 회귀를 가린다 — 임시 git·가짜 tmux 로 keeper 바퀴를 실제로 돌린다.

    receipt(keeper_close)가 이번 바퀴 work 를 handled 에 적은 뒤 분모를 다시 읽으면 이미 센 b2c 까지 빠져 4/3 이 된다(기대 4/4).
    """
    w = W.World(tmp_path, monkeypatch)
    w.enable()
    w.card("r9", w.pack_sha())
    w.work("r9", done=True, alive=True)
    k = w.keeper()
    lines = w.round(k)
    assert "harness|r9@a1" in k.state["handled"], k.state["handled"]   # 영수 경로가 이번 바퀴에 handled 를 적었다
    assert field(k, "items") == "4/4" and field(k, "cut") == "-", lines
    assert any(x.startswith("RECEIPT") for x in lines), lines   # 끊김 없이 영수까지 갔다


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Rig(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w1").mkdir()
    try:   # 변이 세계 = 판정 줄이 달라지거나(AssertionError) 값이 없거나(KeyError) 심사가 선다
        CASES[cases[0]](Rig(tmp_path / "w1", tree))
    except BaseException:   # noqa: BLE001 — 어떤 실패든 변이를 잡은 것
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, cases[0]))
    for case in cases[1:]:   # 같은 변이의 다른 사례 = 원본 나무로 PASS(대조)
        assert CASES[case](Rig(tmp_path / ("c" + case), None)) is None
