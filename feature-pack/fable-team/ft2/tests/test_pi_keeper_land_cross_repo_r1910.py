"""r1910 keeper — 착지 repo(팩)에 intent base_sha 객체가 없으면(다른 repo base) 착지 committer 시각 vs intent at 으로 옛 줄 판정.
카드 반례 ①~⑤ + DA 구현 조건(명시적 missing ↔ git 실패 · at 파싱 실패 = 판정 불가 · 로컬 aware 순간 비교) · r1812 대역 · 역사 공유 0 repo 2개.
기준판(팩 origin/main 64b4bec0) = ① ④ ⑤ ⑥ ⑦ Red(merge-base rc128 판정 불가) · ② ③ = 지금과 같음.
"""
import datetime
import importlib.util
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1910", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, _put, _git = kw.World, kw._put, kw._git


def opened(w, work, land, base, at=None):   # 카드(착지 land) + 일 1개(dispatch a1) · intent base_sha·at(None = 칸 없음)
    w.card(work, land), w.work(work)
    body = {k: v for k, v in (("state", "opened"), ("base_sha", base), ("at", at)) if v}
    _put(w.runtime() / "launch" / ("%s@a1.intent" % work), body)
    return land


def cross(w, work, at=None):   # 팩 착지 sha · BYZ base sha(팩에 객체 없음)
    return opened(w, work, w.pack_sha(), w.commit("byz", {}, "ops/main-base"), at)


def done(w, work, n=1, k=None):
    lines = w.round(k)
    assert w.kinds("complete") == n and any("COMPLETED" in x and work in x for x in lines), lines


def held(w, work, text, k=None):
    lines = w.round(k)
    assert w.kinds("complete") == 0 and any(x.startswith("HELD") and work in x and text in x for x in lines), lines


def c1(w):   # ① r1899 꼴 · 착지 시각 > at → complete 1회 · 다음 바퀴 재 complete 0
    done(w, cross(w, "r9911", "2020-01-01T00:00:00"))
    assert w.round() and w.kinds("complete") == 1


def c2(w):   # ② 같은 repo · 착지 sha 가 base 조상 아님 → 진행(지금과 같음)
    base = w.pack_sha()
    done(w, opened(w, "r9912", w.pack_sha(), base))


def c3(w):   # ③ 같은 repo · 착지 sha 가 base 조상 → 옛 착지 줄 HELD(지금과 같음)
    old = w.pack_sha()
    opened(w, "r9913", old, w.pack_sha())
    held(w, "r9913", "옛 착지 줄(attempt 전) " + old[:8])


def c4(w):   # ④ 다른 repo · 착지 시각 < at → «옛 착지 줄(다른 repo 시각)» HELD
    land = cross(w, "r9914", "2099-01-01T00:00:00")
    held(w, "r9914", "옛 착지 줄(attempt 전 · 다른 repo 시각) " + land[:8])


def c5(w):   # ⑤ 다른 repo · intent at 없음 → 판정 불가 · base_sha 없음 → 진행(지금과 같음)
    cross(w, "r9916"), held(w, "r9916", "판정 불가 · 옛 착지 시각 대조")
    done(w, opened(w, "r9915", w.pack_sha(), None))


def c6(w):   # ⑥ at 파싱 실패 → 판정 불가 · 같은 순간(offset %cI ↔ 로컬 naive at) → 진행
    cross(w, "r9917", "어제"), held(w, "r9917", "판정 불가 · 옛 착지 시각 대조")
    land = w.pack_sha()
    at = datetime.datetime.fromisoformat(_git(w.tmp / "seed-pack", "log", "-1", "--format=%cI", land)).astimezone()
    done(w, opened(w, "r9918", land, w.commit("byz", {}, "ops/main-base"), at.replace(tzinfo=None).isoformat()))


def c7(w):   # ⑦ cat-file 자체 git 실패(rc128 · repo 없음 꼴) → 판정 불가 · complete 0
    cross(w, "r9919", "2020-01-01T00:00:00")
    k = w.keeper()
    k.git = (lambda real: lambda repo, *a, **kv: (128, "", "fatal: 가짜") if a[:1] == ("cat-file",) else real(repo, *a, **kv))(k.git)
    held(w, "r9919", "판정 불가 · 옛 착지 대조 cat-file rc 128", k)


@pytest.mark.parametrize("case", [c1, c2, c3, c4, c5, c6, c7], ids=lambda f: f.__name__)
def test_r1910(tmp_path, monkeypatch, case):
    case(World(tmp_path, monkeypatch))
