"""r2362 keeper ROWS-SLOW 줄의 load 초를 세 구간 초로 나눠 같은 줄 끝에 함께 적는다 — 고침 0 · 관찰만.

계약 K1~K3 · 반례 ①~⑥ · 변이 M1~M5(사본에서만 · 변이마다 원본으로 같은 사례 1회 더).
K1 세 칸 초 — proj = projection 가져오기 + Journal 만들기 · key = 닫힌 segment stat · get = 닫힌 행 읽기
   (캐시 hit = 캐시 json 1개 · miss = 닫힌 전부 판독) · 세 칸 합 = load(반올림 차 0.01 이하).
K2 앞 글자 그대로 — «cache= load= active= n= cpu=» 순서·꼴 그대로 · 새 꼬리 세 칸만 뒤에 붙는다.
K3 다른 길 그대로 — 1초 문턱(줄 0) · 판독 실패(None · 줄 0) · cache=hit/miss/none 글자 그대로.
대역 = 가짜 keeper(주입 wall·cpu 시계 · log 줄만 모음) + 임시 runtime(r2319 world 그대로 · 실제 record 꼴)
· 실 runtime·tmux·원장 0 · 네트워크 0 · sleep 0.
기준판(BASE git archive · 이 카드 앞) Red = ① — 꼬리 세 칸이 없어 ① 이 먼저 깨진다.
"""
import importlib.util
import pathlib
import shutil

import pytest

from test_keeper_rows_cache_r2319 import ACTIVE, TEAM as RTEAM, full, world

FT2 = pathlib.Path(__file__).resolve().parents[1]
KE = "adapters/pi/keeper_endings.py"
BASE = "9300b62801"   # 이 카드 앞 팩 main(arch 판독 기준) — 기준판 = 꼬리 세 칸 없음


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Clock:   # 가짜 시계 — monotonic(벽) 과 thread_time(cpu) 두 줄 · 값이 떨어지면 마지막 값 반복
    def __init__(s, wall, cpu=(0.0,)):
        s.w, s.c, s.i, s.j = list(wall), list(cpu), 0, 0

    @staticmethod
    def _take(vals, i):
        return vals[min(i, len(vals) - 1)]

    def monotonic(s):
        v = s._take(s.w, s.i)
        s.i += 1
        return v

    def thread_time(s):
        v = s._take(s.c, s.j)
        s.j += 1
        return v


def _world(tmp, ft2, closed=2, warm=True):
    """임시 runtime 1벌 + 그 나무의 keeper_endings · warm = 진짜 시계로 한 번 읽어 캐시를 채운다."""
    ke, w = _mod(ft2 / KE, "r2362_ke"), world(tmp, closed=closed, active=2)
    if warm:
        assert ke._rows(w.k, RTEAM) is not None
        w.k.lines.clear()
    return ke, w


def _line(w):   # 마지막 ROWS-SLOW 줄 · 이름=값 사전(앞 두 낱말 = 종류·팀)
    one = w.k.lines[-1]
    return one, dict(kv.split("=", 1) for kv in one.split()[2:])


def c1(tmp, mp, ft2=FT2):   # ① 캐시 hit — 세 칸 초가 붙고 합 = load · 꼬리 값 그대로
    ke, w = _world(tmp / "a", ft2)
    n = len(full(w, ke))
    mp.setattr(ke, "time", Clock([100.0, 100.10, 100.30, 100.35, 101.85], [50.0, 50.05]))
    assert ke._rows(w.k, RTEAM) is not None
    assert w.k.lines == ["ROWS-SLOW %s cache=hit load=0.35 active=1.50 n=%d cpu=0.05 proj=0.10 key=0.20 get=0.05" % (RTEAM, n)], w.k.lines


def c2(tmp, mp, ft2=FT2):   # ② 캐시 없음(miss) — get 칸이 닫힌 전부 판독 몫 · 합 = load
    ke, w = _world(tmp / "a", ft2, warm=False)
    n = len(full(w, ke))
    mp.setattr(ke, "time", Clock([200.0, 200.02, 200.12, 200.62, 201.62], [70.0, 70.0]))
    assert ke._rows(w.k, RTEAM) is not None
    assert w.k.lines == ["ROWS-SLOW %s cache=miss load=0.62 active=1.00 n=%d cpu=0.00 proj=0.02 key=0.10 get=0.50" % (RTEAM, n)], w.k.lines


def c3(tmp, mp, ft2=FT2):   # ③ 어느 한 칸이 큰 세 시계 값 — 세 칸 합 = load(0.01 이하) · 셋 다 0보다 큼
    for wall in ([100.0, 100.90, 101.05, 101.30, 102.30],    # proj 가 큰 경우
                 [110.0, 110.01, 110.91, 110.95, 111.95],    # key 가 큰 경우
                 [120.0, 120.02, 120.04, 121.04, 122.04]):   # get 이 큰 경우
        ke, w = _world(tmp / ("a%d" % wall[0]), ft2)
        mp.setattr(ke, "time", Clock(wall))
        assert ke._rows(w.k, RTEAM) is not None
        one, got = _line(w)
        assert abs(float(got["proj"]) + float(got["key"]) + float(got["get"]) - float(got["load"])) <= 0.01, one
        assert all(float(got[k]) > 0 for k in ("proj", "key", "get")), one


def c4(tmp, mp, ft2=FT2):   # ④ 앞 글자 그대로 — 꼬리 앞까지 r2346 꼴 그대로 · 뒤에 세 칸 이름 순서대로
    ke, w = _world(tmp / "a", ft2)
    n = len(full(w, ke))
    mp.setattr(ke, "time", Clock([100.0, 100.10, 100.30, 100.35, 101.85]))
    assert ke._rows(w.k, RTEAM) is not None
    head, one = "ROWS-SLOW %s cache=hit load=0.35 active=1.50 n=%d cpu=0.00" % (RTEAM, n), w.k.lines[0]
    assert one.startswith(head), one
    assert [kv.split("=")[0] for kv in one[len(head):].split()] == ["proj", "key", "get"], one


def c5(tmp, mp, ft2=FT2):   # ⑤ cache=hit/miss/none 글자 그대로 — 꼬리는 세 꼴 모두 붙는다
    for sub, closed, warm, want in (("h", 2, True, "hit"), ("m", 2, False, "miss"), ("n", 0, True, "none")):
        ke, w = _world(tmp / sub, ft2, closed=closed, warm=warm)
        mp.setattr(ke, "time", Clock([100.0, 100.10, 100.30, 100.35, 101.85]))
        assert ke._rows(w.k, RTEAM) is not None
        one, got = _line(w)
        assert one.split()[2] == "cache=" + want and list(got)[-3:] == ["proj", "key", "get"], one


def c6(tmp, mp, ft2=FT2):   # ⑥ 다른 길 그대로 — 1초 문턱 밑 = 줄 0 · 판독 실패 = None · 줄 0
    ke, w = _world(tmp / "a", ft2)
    mp.setattr(ke, "time", Clock([300.0, 300.01, 300.11, 300.31, 300.61]))   # load 0.31 + active 0.30
    assert ke._rows(w.k, RTEAM) is not None and w.k.lines == [], w.k.lines
    ke, w = _world(tmp / "b", ft2)
    with open(w.rt / ACTIVE, "a", encoding="utf-8") as fh:
        fh.write("{깨진 줄\n")
    mp.setattr(ke, "time", Clock([400.0, 400.10, 400.30, 400.35, 401.85]))    # load+active 1.85 · 그래도 None
    assert ke._rows(w.k, RTEAM) is None and w.k.lines == [], w.k.lines


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6}


@pytest.mark.parametrize("label", list(CASES))
def test_case(label, tmp_path, monkeypatch):
    CASES[label](tmp_path, monkeypatch)


MUTANTS = {
    "M1": ("        ta = time.monotonic()   # r2362 proj 칸 끝(load 첫 구간)", "        ta = t0", "①"),   # proj 칸 0
    "M2": ("        tb = time.monotonic()   # r2362 key 칸 끝(load 둘째 구간)", "        tb = ta", "②"),   # key 칸 0
    "M3": ("% (ta - t0, tb - ta, t1 - tb)", "% (ta - t0, tb - ta, t2 - tb)", "①"),   # get 칸이 active 까지 먹음
    "M4": ('"cache=%s load=%.2f active=%.2f n=%d cpu=%.2f"', '"cache=%s load=%.2f n=%d active=%.2f cpu=%.2f"', "④"),   # 앞 글자 순서
    "M5": ("    if t2 - t0 >= ROWS_SLOW_S:", "    if True:", "⑥"),   # 1초 문턱 지움
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    before, after, label = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = tree / KE
    text = path.read_text(encoding="utf-8")
    assert text.count(before) == 1, (name, before)
    path.write_text(text.replace(before, after), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w1", monkeypatch, tree)
    CASES[label](tmp_path / "w2", monkeypatch, FT2)   # 원본으로 같은 사례 1회 더 = PASS


# ── 기준판 Red (①) ─────────────────────────────────────────────────────────
def base_tree(tmp):
    import subprocess
    top = subprocess.run(["git", "-C", str(FT2), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=25, check=True).stdout.strip()
    out = tmp / "base" / "ft2"
    out.mkdir(parents=True)
    tar = subprocess.run(["git", "-C", top, "archive", BASE + ":feature-pack/fable-team/ft2"],
                         capture_output=True, timeout=25, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(out)], input=tar, timeout=25, check=True)
    return out


@pytest.mark.parametrize("label", ["①"])
def test_base_red(label, tmp_path, monkeypatch):
    ft2 = base_tree(tmp_path)
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w", monkeypatch, ft2)
