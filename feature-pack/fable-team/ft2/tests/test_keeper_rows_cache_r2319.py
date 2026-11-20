"""r2319 keeper journal 닫힌 segment 캐시 — 반례 ①~⑫ · 변이 M1~M8(사본에서만 · 변이마다 원본으로 같은 사례 1회 더).

계약 = 카드 r2319 C1~C8 · 대상 = adapters/pi/keeper_endings.py 의 _rows.
대역 = 임시 runtime(journal.N.jsonl 닫힌 것 + journal.jsonl 활성 · 실제 record 꼴) + 가짜 keeper
(root · 캐시 폴더 k.dir 주입 · log 줄 모음) + 가짜 시계. 네트워크 0 · 실 runtime·tmux·원장 0 · sleep 0.
⑩ 회귀(불변 목록 재실행) = 이 파일 밖 — 카드가 든 4개 시험 파일을 기준 나무(origin/main keeper_endings)
와 이 나무에서 돌려 실패 이름 diff 0 (근거 = PR 본문 · 한 판독 70초 규칙 때문에 시험 안에서 돌리지 않는다).
"""
import importlib.util
import json
import os
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
KE = "adapters/pi/keeper_endings.py"
TEAM, AT, ACTIVE, CACHE = "harness", "2026-11-20T06:00:00", "journal.jsonl", "journal-rows"


def load(tree=FT2, name="r2319_ke"):
    spec = importlib.util.spec_from_file_location(name, str(Path(tree) / KE))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class K:
    """keeper 대역 — root · 캐시 폴더(dir) 주입 · log 는 줄만 모은다(파일 쓰기 0)."""
    def __init__(s, root):
        s.root = str(root)
        s.dir = str(Path(s.root) / ".fable-team" / "state" / "ft2-keeper")
        s.lines = []

    def log(s, kind, team="", text=""):
        s.lines.append(" ".join(w for w in (kind, team, text) if w))


class W:
    """임시 runtime — 닫힌 segment N개 + 활성 1개. seq 는 만든 순서대로 1, 2, 3 …"""
    def __init__(s, tmp):
        s.root, s.seq = Path(tmp) / "root", 0
        s.rt = s.root / ".fable-team" / "teams" / TEAM / "runtime"
        s.rt.mkdir(parents=True)
        s.k = K(s.root)

    def row(s, work=""):
        s.seq += 1
        return {"schema": 1, "team": TEAM, "seq": s.seq, "kind": "dispatch", "command": "c", "attempt": "a1",
                "at": AT, "body": {}, "work": work or "w%d" % s.seq, "holder": "h#0"}

    def write(s, name, rows):
        with open(s.rt / name, "w", encoding="utf-8") as fh:
            for rec in rows:
                fh.write(json.dumps(rec) + "\n")

    def add(s, name, n=2):   # segment 에 n행 덧붙임(seq 이어짐)
        with open(s.rt / name, "a", encoding="utf-8") as fh:
            for _ in range(n):
                fh.write(json.dumps(s.row()) + "\n")


def world(tmp, closed=2, active=2):
    w = W(tmp)
    for n in range(1, closed + 1):
        w.write("journal.%d.jsonl" % n, [w.row(), w.row()])
    w.write(ACTIVE, [w.row() for _ in range(active)])
    return w


def full(w, ke):   # 기준판 = 캐시 없이 전부 판독(Journal.records)
    proj = ke._proj()
    return proj.journal.Journal(proj.runtime_path(w.k.root, TEAM), rec=proj.record).records()


def cache(w):   # C6 위치 = keeper 상태 폴더 아래 팀마다 1파일
    return Path(w.k.dir) / CACHE / (TEAM + ".json")


def cached(w):   # 캐시 파일 바이트(없으면 None) — 기준판은 늘 None
    return cache(w).read_bytes() if cache(w).exists() else None


def opens(mp, ke, seen):   # «가짜 open 셈» — journal 파일 열기 1회 = 1
    J, orig = ke._proj().journal.Journal, ke._proj().journal.Journal._records_of

    def rec(self, path):
        seen.append(os.path.basename(path))
        return orig(self, path)
    mp.setattr(J, "_records_of", rec)


class Clock:   # «가짜 시계» — time.monotonic 1개만 흉내
    def __init__(s, vals):
        s.vals, s.i = list(vals), 0

    def monotonic(s):
        v = s.vals[min(s.i, len(s.vals) - 1)]
        s.i += 1
        return v


def c1(w, ke, mp):   # ① 첫 판독 = 캐시 생김 · 둘째 판독 = 닫힌 쪽 열기 0 · 결과 같음
    want = full(w, ke)
    assert ke._rows(w.k, TEAM) == want and cache(w).is_file()
    seen = []
    opens(mp, ke, seen)
    assert ke._rows(w.k, TEAM) == want and seen == [ACTIVE], seen


def c2(w, ke, mp):   # ② 둘째 판독 사이 활성에 1행 더함 → 새 행 들어감 · 닫힌 쪽 열기 0
    want = full(w, ke)
    assert ke._rows(w.k, TEAM) == want
    w.add(ACTIVE, 1)
    want = full(w, ke)
    seen = []
    opens(mp, ke, seen)
    got = ke._rows(w.k, TEAM)
    assert got == want and len(got) == len(want) and seen == [ACTIVE], (len(got), len(want), seen)


def c3(w, ke, mp):   # ③ 회전(활성 → journal.3 · 새 활성) → 캐시 틀림 · 전부 다시 판독 · 캐시 새로 씀
    assert ke._rows(w.k, TEAM) == full(w, ke)
    had = cached(w)   # 기준판 = None(캐시 0) — 캐시 단언은 캐시가 있던 나무에서만: 기준판 Red 를 ① ② ⑫ 로 둔다
    os.replace(w.rt / ACTIVE, w.rt / "journal.3.jsonl")
    w.write(ACTIVE, [w.row(), w.row()])
    want = full(w, ke)
    seen = []
    opens(mp, ke, seen)
    got = ke._rows(w.k, TEAM)
    assert got == want and seen == ["journal.%d.jsonl" % n for n in (1, 2, 3)] + [ACTIVE], seen
    assert had is None or [r[1] for r in json.loads(cached(w))["closed"]] == ["journal.%d.jsonl" % n for n in (1, 2, 3)]


def c4(w, ke, mp):   # ④ reclaim(journal.1 지움) → 캐시 틀림 · 지운 행 없음 · 결과 = 전부 판독
    assert ke._rows(w.k, TEAM) == full(w, ke)
    os.unlink(w.rt / "journal.1.jsonl")
    want = full(w, ke)
    seen = []
    opens(mp, ke, seen)
    got = ke._rows(w.k, TEAM)
    assert got == want and seen == ["journal.2.jsonl", ACTIVE], seen
    assert [r["work"] for r in got] == [r["work"] for r in want] and "w1" not in [r["work"] for r in got]


def c5(w, ke, mp):   # ⑤ 닫힌 segment 1개 size 같고 mtime 다름 → 전부 다시 판독
    assert ke._rows(w.k, TEAM) == full(w, ke)
    path = w.rt / "journal.2.jsonl"
    st = os.stat(path)
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns + 10 ** 9))
    want = full(w, ke)
    seen = []
    opens(mp, ke, seen)
    assert ke._rows(w.k, TEAM) == want and seen == ["journal.1.jsonl", "journal.2.jsonl", ACTIVE], seen


def c6(w, ke, mp):   # ⑥ 캐시 파일 깨짐(반쪽 JSON) → 전부 판독 · 결과 같음 · 캐시 새로 씀
    assert ke._rows(w.k, TEAM) == full(w, ke)
    cache(w).parent.mkdir(parents=True, exist_ok=True)
    cache(w).write_text('{"v": 1, "closed": [', encoding="utf-8")
    before = cached(w)
    want = full(w, ke)
    seen = []
    opens(mp, ke, seen)
    assert ke._rows(w.k, TEAM) == want and seen == ["journal.1.jsonl", "journal.2.jsonl", ACTIVE], seen
    after = cached(w)   # 깨진 캐시를 새로 썼는가 — 기준판 = 그대로(깨진 채)
    assert after == before or json.loads(after)["rows"] == want[:-2]   # 캐시 = 닫힌 쪽만


def c7(w, ke, mp):   # ⑦ 캐시 쓰기 실패(가짜 replace 예외) → 결과 같음 · 예외 0 · 캐시 파일 0
    class Os:   # os 대역 — replace 만 실패
        def __getattr__(s, name):
            return getattr(os, name)

        def replace(s, *_a):
            raise OSError("가짜 replace 실패")
    want = full(w, ke)
    mp.setattr(ke, "os", Os())
    assert ke._rows(w.k, TEAM) == want and not cache(w).exists()


def c8(w, ke, mp):   # ⑧ 활성 파일 깨진 줄 → None · 캐시 손 0
    assert ke._rows(w.k, TEAM) == full(w, ke)
    before = cached(w)   # 기준판 = None
    with open(w.rt / ACTIVE, "a", encoding="utf-8") as fh:
        fh.write("{깨진 줄\n")
    assert ke._rows(w.k, TEAM) is None and cached(w) == before


def c9(w, ke, mp):   # ⑨ 캐시 끝 seq ≥ 활성 첫 seq(이음 역행) → None
    assert ke._rows(w.k, TEAM) == full(w, ke)
    w.write(ACTIVE, [w.row()])
    rec = json.loads((w.rt / ACTIVE).read_text(encoding="utf-8").splitlines()[0])
    rec["seq"] = 1
    w.write(ACTIVE, [rec])
    assert ke._rows(w.k, TEAM) is None


def c11(w, ke, mp):   # ⑪ 판독 중 journal.3 생김(전·후 목록 다름) → 결과는 지금과 같음 · 캐시 쓰기 0
    want = full(w, ke)
    J, orig, born = ke._proj().journal.Journal, ke._proj().journal.Journal._records_of, []

    def rec(self, path):
        got = orig(self, path)
        if not born and os.path.basename(path) == "journal.2.jsonl":
            born.append(1)
            w.write("journal.3.jsonl", [w.row()])
        return got
    mp.setattr(J, "_records_of", rec)
    assert ke._rows(w.k, TEAM) == want and born and not cache(w).exists()


def c12(w, ke, mp):   # ⑫ 가짜 시계 — 활성 판독 1.5초 · cache=hit → ROWS-SLOW 1줄 · 0.3초 → 줄 0
    assert ke._rows(w.k, TEAM) == full(w, ke)
    n = len(full(w, ke))
    mp.setattr(ke, "time", Clock([100.0, 100.0, 100.01, 100.01, 101.51]))   # r2346 — 이 가짜 시계에는 thread_time 이 없어 cpu=0.00 · r2362 시계 2자리(proj·key) 더
    assert ke._rows(w.k, TEAM) is not None
    assert w.k.lines == ["ROWS-SLOW %s cache=hit load=0.01 active=1.50 n=%d cpu=0.00 proj=0.00 key=0.01 get=0.00" % (TEAM, n)], w.k.lines
    mp.setattr(ke, "time", Clock([200.0, 200.01, 200.31]))
    assert ke._rows(w.k, TEAM) is not None and len(w.k.lines) == 1, w.k.lines


CASES = {"1": c1, "2": c2, "3": c3, "4": c4, "5": c5, "6": c6, "7": c7, "8": c8, "9": c9, "11": c11, "12": c12}
MUTANTS = {   # (고칠 글자, 바꾼 글자, 그 변이가 깨뜨려야 하는 사례)
    "M1": ("closed = _rows_get(path, key) if key else None", "closed = None", c1),
    "M2": ("out.append([n, os.path.basename(path), st.st_size, st.st_mtime_ns])", "out.append([n, os.path.basename(path), st.st_size])", c5),
    "M3": ('got.get("closed") == key', 'got.get("closed") == key[:len(got.get("closed") or [])]', c3),
    "M4": ("    except (OSError, ValueError, KeyError, TypeError):\n        pass\n", "    except (OSError, ValueError, KeyError, TypeError):\n        raise\n", c6),
    "M5": ('        if out and rec["seq"] <= out[-1]["seq"]:', "        if False:", c9),
    "M6": ("        active = j._records_of(j.active_path) if os.path.exists(j.active_path) else []   # 활성은 매번 (C1)",
           "        active = [] if hit else (j._records_of(j.active_path) if os.path.exists(j.active_path) else [])", c2),
    "M7": ("    if t2 - t0 >= ROWS_SLOW_S:", "    if True:", c12),
    "M8": ("        if key and not hit and _rows_key(j) == key:", "        if key and not hit:", c11),
}


def run(case, tmp, tree):
    mp = pytest.MonkeyPatch()
    try:
        case(world(tmp), load(tree), mp)
    finally:
        mp.undo()


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    run(CASES[name], tmp_path / "w", FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, case = MUTANTS[name]
    copy = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / KE).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / KE).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", copy)
    run(case, tmp_path / "w2", FT2)   # 원본으로 같은 사례 1회 더 = PASS
