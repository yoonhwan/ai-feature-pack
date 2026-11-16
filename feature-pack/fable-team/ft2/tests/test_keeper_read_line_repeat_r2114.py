"""r2114 keeper 판독 실패 줄 반복 — 옮겨진 짝 표 카드 = 줄 0 · 짝 표 카드·HOLD 판독 «판정 불가» 줄 = 값이 바뀔 때만 1줄 (반례 ①~⑥ · 변이 M1~M4).
대역 = r2030 world(r1871 임시 root·git·가짜 tmux) · r1931 world(r1813 · 카드 git) · keeper 상태 파일(state.json). 실 keeper 로그·명부·원장 0 · sleep 0.
기준판(팩 origin/main) = ① ⑤ Red. 변이는 ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent


def _load(name, rel):
    spec = importlib.util.spec_from_file_location(name, str(HERE / rel))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


R = _load("r2030_for_r2114", "test_pi_launch_first_body_card_map_r2030.py")
H = _load("r1931_for_r2114", "test_pi_keeper_hold_wake_r1931.py")
kw, V65, W = R.kw, R.V65, H.W
KN, KH = "adapters/pi/keeper_next.py", "adapters/pi/keeper_hold.py"


def mapw(tmp, mp, ft2, stage=None):
    """짝 표 = v65 대기 경로 · 카드는 stage 폴더에만(None = indices 어디에도 없음)."""
    w = R.world(tmp, mp, stage, ft2=ft2) if stage else R.base.world(tmp, mp, None, ft2=ft2)
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n" + R.ROOTS)
    kw._put(w.runtime() / "cards.tsv", "w1\t%s\n" % (V65 % "대기"))
    return w


def maplines(w, k=None):
    """한 바퀴의 «짝 표 카드» 줄(같은 keeper 로 여러 바퀴면 그 바퀴 몫만)."""
    k = k or w.keeper()
    before = len(k.lines)
    return [x for x in w.round(k)[before:] if "짝 표 카드" in x]


def moved(tmp, mp, ft2, stages):
    for i, stage in enumerate(stages):
        w = mapw(tmp / str(i), mp, ft2, stage)
        got = [maplines(w), maplines(w)]
        assert got == [[], []] and R.base.launched(w) == [], (stage, got)


def c1(tmp, mp, ft2=kw.FT2):   # ① 카드 완성/ 에만 → 후보 0 · 줄 0 · 바퀴 2회
    moved(tmp, mp, ft2, ["완성"])


def c2(tmp, mp, ft2=kw.FT2):   # ② 완성후/ · 아카이브/2026-11/ → 같음
    moved(tmp, mp, ft2, ["완성후", "아카이브/2026-11"])


def c3(tmp, mp, ft2=kw.FT2):   # ③ 이름이 indices 어디에도 없음 → 바퀴 1 = 1줄 · 바퀴 2 = 0 · 재기동 뒤 바퀴 3 = 0
    w = mapw(tmp, mp, ft2)
    k = w.keeper()
    got = [maplines(w, k), maplines(w, k), maplines(w)]
    assert [len(x) for x in got] == [1, 0, 0] and "git rc 128/0" in got[0][0], got
    return w


def c4(tmp, mp, ft2=kw.FT2):   # ④ ③ 뒤 ls-tree 실패(rc4 ≠ 0)로 값 바뀜 → 1줄 더 · 같은 값 다음 바퀴 0
    w = c3(tmp, mp, ft2)
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n*\t.\torigin/nope\tdesign/teams/*/indices\n")
    got = [maplines(w), maplines(w)]
    assert [len(x) for x in got] == [1, 0] and "git rc 128/128" in got[0][0], got


def hw(tmp, mp, ft2):
    """W 의 카드 후보 0(카드 루트에 다른 이름 카드만) · 멈춤 깨움 0 좌석."""
    w = H.B.World(tmp, mp, ft2)
    H._quiet(w), H._card(w, 0)
    away(w)
    return w


def away(w):   # W 카드를 다른 이름으로 옮김 → 카드 후보 0
    H.B._git(w.root, "mv", "-f", "design/harness/indices/대기/%s.md" % W, "design/harness/indices/대기/zz-other.md")
    H.B._git(w.root, "commit", "-qm", "away")
    for ref in ("main", "ops/main-base"):
        H.B._git(w.root, "update-ref", "refs/remotes/origin/" + ref, "HEAD")


def holdlines(w, dt):
    return [x for x in w.round(dt) if x.startswith("판정 불가 harness %s HOLD 판독" % W)]


def c5(tmp, mp, ft2=kw.FT2):   # ⑤ 카드 후보 0 · 바퀴 3회 → 1줄
    w = hw(tmp, mp, ft2)
    got = [holdlines(w, i * H.M) for i in range(3)]
    assert [len(x) for x in got] == [1, 0, 0] and "HOLD 판독 카드 후보 0" in got[0][0], got
    return w


def c6(tmp, mp, ft2=kw.FT2):   # ⑥ ⑤ 뒤 카드가 생겨 판독 = 숫자 → 다음 바퀴 다시 사라짐 → 1줄 더
    w = c5(tmp, mp, ft2)
    H._card(w, 0)
    assert holdlines(w, 3 * H.M) == []
    away(w)
    got = [holdlines(w, 4 * H.M), holdlines(w, 5 * H.M)]
    assert [len(x) for x in got] == [1, 0], got


def c5b(tmp, mp, ft2=kw.FT2):   # ⑤′(M4 용 · ④ 꼴 A3) ⑤ 뒤 사유 글자 바뀜(카드 ref 없음) → 1줄 더
    w = c5(tmp, mp, ft2)
    for ref in ("main", "ops/main-base"):
        H.B._git(w.root, "update-ref", "-d", "refs/remotes/origin/" + ref)
    got = [holdlines(w, 3 * H.M), holdlines(w, 4 * H.M)]
    assert [len(x) for x in got] == [1, 0] and "카드 후보 0" not in got[0][0], got


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑤′": c5b}
MUTANTS = {"M1": (KN, 'MOVED = ("완성", "완성후", "아카이브")', 'MOVED = ("완성",)', c2),                         # A1 단계 목록 줄임
           "M2": (KN, 'k.state.setdefault("map_seen", {})', '(k.cache.get("@round") or {}).setdefault("map_seen", {})', c3),   # A2 기억 = 바퀴 캐시
           "M3": (KH, "    k.state.get(\"hold_read\", {}).pop(key, None)", "    None", c6),                          # A3 기억 안 지움
           "M4": (KH, "if book.get(key) != n:", "if key not in book:", c5b)}                                        # A3 값 비교 없이 한 번만


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch)


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(tmp_path / "w1", monkeypatch, tree)
    case(tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
