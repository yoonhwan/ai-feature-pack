"""r2307 keeper — 착지 판독 바퀴 넘어 기억: 조상 참(anc_true) · 착지 종류(land_kind · lib 판 표지) · 거짓·판정 불가 기억 0 · 칸 상한 1000.
가짜 git·가짜 바깥 호출 주입 · 바퀴 사이 상태 = json(sort_keys) 왕복(state.json 꼴) · 실 리포·실 keeper·네트워크·sleep 0 · 변이 M1~M5 는 ft2 사본으로.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
SHA, WORK, TEAM = "ab" * 20, "r9307", "harness"
LAND_PY = "adapters/pi/keeper_land.py"
LIB = "ft-land-kind-lib.sh"


def _land(ft2):
    spec = importlib.util.spec_from_file_location("r2307_land_%d" % id(ft2), str(ft2 / LAND_PY))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def lib_root(tmp, body="v1"):
    """루트 bin = shim(LIVE_BIN 으로 넘김) · LIVE_BIN 폴더 = 본체."""
    (tmp / ".fable-team" / "bin").mkdir(parents=True, exist_ok=True)
    (tmp / "live").mkdir(exist_ok=True)
    (tmp / ".fable-team" / "bin" / LIB).write_text("# shim\n", encoding="utf-8")
    (tmp / ".fable-team" / "LIVE_BIN").write_text(str(tmp / "live") + "\n", encoding="utf-8")
    (tmp / "live" / LIB).write_text(body, encoding="utf-8")
    return str(tmp)


def fake(land, anc_rc, kind="구현", root="/byz"):
    class Fake(land.Landing):
        def __init__(s):
            s.root, s.pack, s.stale, s.cache, s.state, s.calls, s.kinds = root, "/pack", set(), {}, {}, [], []
            s.env = {}
            s.anc_rc, s.kind = list(anc_rc), kind

        def resolve_card(s, team, work):
            return [("origin/ops/main-base", "design/harness/indices/진행/%s.md" % work)], None

        def git(s, repo, *a, retry=0, timeout=25):
            s.calls.append((repo, a))
            if a[0] == "show":
                return 0, "# 인덱스\n- 착지: %s\n" % SHA, ""
            if a[0] == "merge-base":
                return s.anc_rc.pop(0) if s.anc_rc else (1, "", "")
            if a[0] == "cat-file":
                return 0, "", ""   # 객체 있음 → rc128 = 판정 불가(r2022 꼴)
            raise AssertionError(a)

        def pre_attempt(s, *a, **kv):
            return ""

        def call(s, argv, timeout=7, retry=0):
            s.kinds.append(argv)
            return (None, "", "") if s.kind is None else (0, s.kind, "")

    return Fake()


def next_round(k):
    """바퀴 끝 = state.json 저장·다음 바퀴 읽기(sort_keys) · 바퀴 캐시 새로."""
    k.state, k.cache, k.calls, k.kinds = json.loads(json.dumps(k.state, ensure_ascii=False, sort_keys=True)), {}, [], []


def anc(k):
    return [a for _, a in k.calls if a[:2] == ("merge-base", "--is-ancestor")]


def c1(land, tmp):   # ① 조상 참 → 2바퀴째 merge-base 0 · 반환 같음
    k = fake(land, [(0, "", "")])
    first = k.landing(TEAM, WORK)
    assert first == (SHA, "pack:origin/main", "") and len(anc(k)) == 1
    next_round(k)
    assert k.landing(TEAM, WORK) == first and anc(k) == [], k.calls


def c2(land, tmp):   # ② rc 1 → 기억 0 · 2바퀴째도 부름
    k = fake(land, [(1, "", "")] * 6)
    assert k.landing(TEAM, WORK) == (SHA, None, "미도달")
    assert not k.state.get("anc_true")
    next_round(k)
    assert k.landing(TEAM, WORK) == (SHA, None, "미도달") and len(anc(k)) == 3


def c3(land, tmp):   # ③ rc None · rc 128(객체 있음) → 판정 불가 · 기억 0 · 다음 바퀴 다시 부름
    for rc in (None, 128):   # 로컬 1회 + G3 ⓒ 1회 = 둘 다 같은 rc
        k = fake(land, [(rc, "", "")] * 2)
        assert k.landing(TEAM, WORK)[2] == "판정 불가 · 착지 조상 git rc %s" % rc
        assert not k.state.get("anc_true") and len(anc(k)) == 2
        next_round(k)
        k.anc_rc = [(rc, "", "")] * 2
        k.landing(TEAM, WORK)
        assert len(anc(k)) == 2


def c4(land, tmp):   # ④ 구현 → 2바퀴째 ft_land_kind 0 · 판정 불가 → 기억 0 · 다시 부름
    k = fake(land, [(0, "", "")], root=lib_root(tmp))
    assert k.landing(TEAM, WORK) == (SHA, "pack:origin/main", "") and len(k.kinds) == 1
    next_round(k)
    assert k.landing(TEAM, WORK) == (SHA, "pack:origin/main", "") and k.kinds == []
    k = fake(land, [(0, "", "")], kind=None, root=lib_root(tmp))
    assert k.landing(TEAM, WORK) == (None, None, "판정 불가 · land_kind 시간초과")
    assert [key for key in k.state.get("land_kind", {}) if key != "@lib"] == []
    next_round(k)
    k.landing(TEAM, WORK)
    assert len(k.kinds) == 1


def c4b(land, tmp):   # ④b 기억 뒤 LIVE_BIN 본체 바뀜 → ft_land_kind 1회 다시 · 표지 = 새 것
    k = fake(land, [(0, "", "")], root=lib_root(tmp, "v1"))
    k.landing(TEAM, WORK)
    old = k.state["land_kind"].get("@lib")
    next_round(k)
    lib_root(tmp, "v2")
    assert k.landing(TEAM, WORK) == (SHA, "pack:origin/main", "") and len(k.kinds) == 1
    assert k.state["land_kind"].get("@lib") not in (None, old)


def c5(land, tmp):   # ⑤ 1001번째 키 → 가장 먼저 적은 키 빠짐 · 칸 1000
    k = fake(land, [(0, "", "")])
    k.state["anc_true"] = {"/r|origin/main|%040d" % i: [1000 - i, 0] for i in range(1000)}   # 이름순 ≠ 적은 차례
    next_round(k)
    k.landing(TEAM, WORK)
    book = k.state["anc_true"]
    assert len(book) == 1000 and "/pack|origin/main|" + SHA in book
    assert "/r|origin/main|%040d" % 999 not in book and "/r|origin/main|%040d" % 0 in book


def c5b(land, tmp):   # ⑤b 상한 아래(키 3개) = 버림 0
    k = fake(land, [(0, "", "")])
    k.state["anc_true"] = {"/r|origin/main|%040d" % i: [i + 1, 0] for i in range(2)}
    k.landing(TEAM, WORK)
    assert len(k.state["anc_true"]) == 3


def c6(land, tmp):   # ⑥ 칸 꼴 오류(list) → 빈 칸 · 판독 지금 꼴 · 예외 0
    k = fake(land, [(0, "", "")])
    k.state.update(anc_true=["x"], land_kind=["y"])
    assert k.landing(TEAM, WORK) == (SHA, "pack:origin/main", "") and len(anc(k)) == 1


CASES = {"1": c1, "2": c2, "3": c3, "4": c4, "4b": c4b, "5": c5, "5b": c5b, "6": c6}
MUTANTS = {"M1": ('return book is not None and "%s|%s|%s"', 'return False and "%s|%s|%s"', (c1,)),
           "M2": ("if rc == 0 and book is not None:", "if rc in (0, 1) and book is not None:", (c2,)),
           "M3": ('if kind in ("구현", "카드 문서만") and book is not None:', "if book is not None:", (c4,)),
           "M4": ("for name in sorted(rows, key=order)[:max(0, len(rows) - MEMO_CAP)]:", "for name in []:", (c5,)),
           "M5": ('if book.get("@lib") != mark:', "if False:", (c4b,))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](_land(FT2), tmp_path)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, cases = MUTANTS[name]
    for case in cases:   # 원본 대조 = 같은 사례 통과
        case(_land(FT2), tmp_path / "orig")
    shutil.copytree(FT2, copy := tmp_path / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / LAND_PY).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / LAND_PY).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        with pytest.raises(AssertionError):
            case(_land(copy), tmp_path / "mut")
