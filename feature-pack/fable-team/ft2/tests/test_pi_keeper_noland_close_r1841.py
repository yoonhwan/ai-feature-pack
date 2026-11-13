"""r1841 ft2 keeper 착지 없는 일 닫기 목록 — `<팀 runtime>/keeper-noland-close.tsv` (카드 반례 ①~⑦ · 변이 M1~M6).
대역 = r1812 keeper_world(가짜 투영·intent·tmux·CloseNext · 임시 root · 실 tmux·명부·runtime 0 · sleep 0).
기준판(목록 읽기 없음) = ① ①′ ② ⑥ Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더(PASS).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r1841", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
W, NOCARD = "r9841", "판정 불가 · 카드 후보 0"
GOOD = "카드 없음 · tmux 0 · 발주문 bodies/r9841.body"
OK_BY = "byz-harness-master-pi#236 #295999"


def _world(w, rows=None, alive=False, enable=True, raw=None):
    """done 일 1개(카드 없음) · 목록 줄 rows=[(work, attempt, 근거, 승인)] · raw = 파일 본문 그대로."""
    if enable:
        w.enable()
    holder = w.work(W, done=True, alive=alive)
    body = raw if raw is not None else "".join("\t".join(r) + "\n" for r in ([("# work", "attempt", "근거", "승인")] + (rows or [])))
    if rows is not None or raw is not None:
        kw._put(w.runtime() / "keeper-noland-close.tsv", body)
    return holder


def _mine(lines):
    return [x for x in lines if W in x]


def _held_now(w, holder, lines):   # 지금 그대로 = 카드 후보 0 HELD · kill 0 · 영수 0 · handled 0
    assert _mine(lines) == ["HELD harness %s %s %s" % (W, holder, NOCARD)], lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0


def c1(w):    # ① 목록 정상 · absent → CLOSED-NOLAND 1 · RECEIPT 1 · handled → 다음 바퀴 0
    holder = _world(w, [(W, "a1", GOOD, OK_BY)])
    lines = w.round()
    assert [x.split()[0] for x in _mine(lines)] == ["CLOSED-NOLAND", "RECEIPT"], lines
    assert "CLOSED-NOLAND harness %s %s 근거 %s" % (W, holder, OK_BY) in lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 1
    assert _mine(w.round()) == [] and w.kinds("close_receipt") == 1


def c1b(w):   # ①′ 켜기 전 → RECEIPT-HOLD · handled → 다음 바퀴 0
    _world(w, [(W, "a1", GOOD, OK_BY)], enable=False)
    assert [x.split()[0] for x in _mine(w.round())] == ["CLOSED-NOLAND", "RECEIPT-HOLD"]
    assert _mine(w.round()) == [] and w.tmux("kill-session") == []


def c2(w):    # ② 목록 있음 · alive → kill 0 · 영수 0 · HELD 문구
    holder = _world(w, [(W, "a1", GOOD, OK_BY)], alive=True)
    lines = w.round()
    assert _mine(lines) == ["HELD harness %s %s 목록 있음 · 세션 살아 있음 — 닫기 0" % (W, holder)], lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0


def c3(w):    # ③ 근거에 tmux 0 빠짐 → 무효 → 지금 그대로
    holder = _world(w, [(W, "a1", "카드 없음 · 발주문 bodies/r9841.body", OK_BY)])
    _held_now(w, holder, w.round())


def c3b(w):   # ③′ 승인 빈 칸 → 무효
    holder = _world(w, [(W, "a1", GOOD, "")])
    _held_now(w, holder, w.round())


def c4(w):    # ④ attempt 다름(a2 줄 · 지금 a1) → 무효
    holder = _world(w, [(W, "a2", GOOD, OK_BY)])
    _held_now(w, holder, w.round())


def c5(w):    # ⑤ 카드 있음 · 착지 줄 없음 + 목록 정상 → 지금 그대로 HELD(N4)
    w.card(W)
    holder = _world(w, [(W, "a1", GOOD, OK_BY)])
    lines = w.round()
    assert _mine(lines) == ["HELD harness %s %s 착지 줄 없음" % (W, holder)], lines
    assert w.tmux("kill-session") == [] and w.kinds("close_receipt") == 0


def c6(w):    # ⑥ 목록 깨짐(탭 없는 줄) → 판정 불가 사유 1줄 · 같은 내용 두 바퀴째 새 줄 0 · 내용 바뀌면 다시 1줄
    holder = _world(w, raw="%s a1 깨진 줄\n" % W)
    lines = _mine(w.round())
    assert len(lines) == 1 and lines[0].startswith("HELD harness %s %s %s · 판정 불가 · 목록" % (W, holder, NOCARD)), lines
    assert _mine(w.round()) == [] and w.kinds("close_receipt") == 0 and w.tmux("kill-session") == []
    kw._put(w.runtime() / "keeper-noland-close.tsv", "%s\ta1\n" % W)
    assert len(_mine(w.round())) == 1 and w.kinds("close_receipt") == 0


def c7(w):    # ⑦ 목록 파일 없음 → 지금 그대로(바퀴마다 같은 HELD)
    holder = _world(w)
    _held_now(w, holder, w.round())
    _held_now(w, holder, w.round())


CASES = {"①": c1, "①′": c1b, "②": c2, "③": c3, "③′": c3b, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
KC = "adapters/pi/keeper_close.py"
MUTANTS = {"M1": ("ok = self.noland(team, work, attempt)", "ok = True", c3),
           "M2": ('if seen == "alive":\n            return self.log("HELD", team, "%s %s 목록 있음', 'if False:\n            return self.log("HELD", team, "%s %s 목록 있음', c2),
           "M3": ('("카드 없음", "tmux 0")', '("카드 없음",)', c3),
           "M4": ('ground, ok = rows.get((work, attempt), ("", ""))', 'ground, ok = next((v for k, v in rows.items() if k[0] == work), ("", ""))', c4),
           "M5": ("if seen == NOCARD:", "if seen:", c5),
           "M6": ('if self.state["held"].get(key) != ok:', "if True:", c6)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](kw.World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KC).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KC).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(kw.World(tmp_path / "w1", monkeypatch, tree))
    case(kw.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
