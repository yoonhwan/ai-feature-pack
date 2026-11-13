"""r1893 keeper — 이번 attempt 좌석을 열 때(launch intent base_sha) 이미 있던 옛 «- 착지:» 줄은 complete 근거로 안 쓴다.
카드 반례 ①~④ + 최신 dispatch attempt 대조(옛 a0 intent 무시) · DA APPROVE-DESIGN §1·§2(rc1 = 조상 아님 = 진행).
r1812 대역(keeper_world_r1812) 재사용 · 임시 bare·임시 root 만 · 실 원격·장부·명부·pane 0 · sleep 0.
기준판(팩 origin/main 6d428738) = ① ④ Red · ② ③ ③′ ③″ = 지금과 같은 결과(회귀·경계).
"""
import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1893", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, _put = kw.World, kw._put


def opened(w, work, base, attempt="a1", intent=True):
    """일 1개(submit→assign→deliver = dispatch a1) · intent 에 base_sha 를 적는다(base None = 칸 없음)."""
    seat = w.work(work, intent=intent)
    if base is not None:
        body = {"FT2_HOLDER": seat, "state": "opened", "worktree": str(w.tmp / "wt" / work), "base_sha": base}
        _put(w.runtime() / "launch" / ("%s@%s.intent" % (work, attempt)), body)
    return seat


def c1(w):   # ① 착지 sha = intent base 의 조상(좌석 열 때 이미 있던 줄) → complete 0 · HELD «옛 착지 줄(attempt 전)»
    old = w.pack_sha()
    base = w.pack_sha()
    w.card("r9301", old), opened(w, "r9301", base)
    lines = w.round()
    assert w.kinds("complete") == 0, lines
    assert any(x.startswith("HELD") and "r9301 옛 착지 줄(attempt 전) " + old[:8] in x for x in lines), lines


def c2(w):   # ② base 뒤 새 커밋 착지 줄 → 조상 아님(rc1) → COMPLETED(회귀)
    base = w.pack_sha()
    new = w.pack_sha()
    w.card("r9302", new), opened(w, "r9302", base)
    lines = w.round()
    assert w.kinds("complete") == 1 and any("COMPLETED" in x and new in x for x in lines), lines


def c3(w):   # ③ 최신 attempt intent 없음 → 지금처럼 COMPLETED
    old = w.pack_sha()
    w.pack_sha()
    w.card("r9303", old), opened(w, "r9303", None, intent=False)
    assert w.kinds("complete") == 0
    lines = w.round()
    assert w.kinds("complete") == 1, lines


def c3b(w):  # ③′ intent 는 있으나 base_sha 칸 없음 → 지금처럼 COMPLETED
    old = w.pack_sha()
    w.pack_sha()
    w.card("r9304", old), opened(w, "r9304", None)
    lines = w.round()
    assert w.kinds("complete") == 1, lines


def c3c(w):  # ③″ 옛 a0 intent 에만 base_sha(최신 dispatch = a1 · intent 없음) → 옛 intent 로 대신 0 → COMPLETED
    old = w.pack_sha()
    base = w.pack_sha()
    w.card("r9305", old), opened(w, "r9305", base, attempt="a0", intent=False)
    lines = w.round()
    assert w.kinds("complete") == 1, lines


def c4(w):   # ④ 조상 대조 git rc128(가짜 · base_sha 대상 merge-base 만) → 판정 불가 · complete 0
    old = w.pack_sha()
    base = w.pack_sha()
    w.card("r9306", old), opened(w, "r9306", base)
    k = w.keeper()
    real = k.git
    k.git = lambda repo, *a, **kv: (128, "", "fatal: 가짜") if a[:2] == ("merge-base", "--is-ancestor") and a[-1] == base else real(repo, *a, **kv)
    lines = w.round(k)
    assert w.kinds("complete") == 0, lines
    assert any(x.startswith("HELD") and "r9306" in x and "판정 불가" in x for x in lines), lines


@pytest.mark.parametrize("case", [c1, c2, c3, c3b, c3c, c4], ids=lambda f: f.__name__)
def test_r1893(tmp_path, monkeypatch, case):
    case(World(tmp_path, monkeypatch))
