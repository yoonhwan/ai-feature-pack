"""r2121 keeper 멈춤 갈래 — pi 세션 파일을 좌석 세션 id(D1) · 세션 이름(D2)으로 먼저 찾는다 (카드 반례 ①~⑦ · ⑨ 끝 칸 · 변이 M1~M3).
대역 = r1813 World · r1895 world(실제 core·launch.py · 가짜 tmux·ps·세션 파일 · 주입 시계) + 가짜 tmux show-environment(좌석 env).
실 tmux·실 세션 폴더·실 keeper 상태 0 · sleep 0. 기준판(팩 origin/main) = ① ② ⑥ Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import importlib.util, json, os, shutil, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent


def _load(name, alias):
    spec = importlib.util.spec_from_file_location(alias, str(HERE / name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


tb = _load("test_pi_launch_trust_body_r1895.py", "tb_r2121")
st, M, W, H0 = tb.st, tb.M, tb.W, tb.H0
X, OTHER = "4605382a-0000-7000-8000-000000000021", "byz-harness-nano-other-pi#3"
ENV = r'''#!__PY__
import json, os, sys
a = sys.argv[1:]
if a[:1] == ["show-environment"]:
    st = os.environ["FAKE_TMUX"]
    open(st + ".log", "a").write(json.dumps({"a": a}) + "\n")
    name, env = a[a.index("-t") + 1].lstrip("="), json.load(open(st)).get("env", {})
    if env.get(name) == "rc1":
        sys.stderr.write("no server running\n"); sys.exit(1)
    sys.stdout.write("FT2_HOLDER=%s\n" % name + ("TMUXC_PI_SESSION_ID=%s\n" % env[name] if env.get(name) else ""))
    sys.exit(0)
os.execv(sys.argv[0] + "0", [sys.argv[0] + "0"] + a)
'''


def envify(w, sid=None):
    """가짜 tmux 앞에 show-environment 대역 1겹 · sid = holder env TMUXC_PI_SESSION_ID(None = 없음 · "rc1" = 조회 실패)."""
    b = w.tm.parent
    if not (b / "tmux0").exists():
        (b / "tmux").rename(b / "tmux0")
        st._put(b / "tmux", ENV.replace("__PY__", sys.executable)), (b / "tmux").chmod(0o755)
    st._put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), env={H0: sid} if sid else {}))
    return w


def sfile(w, folder, sid, mtime, stop="stop", names=(), user=None, pad=0):
    """세션 파일 <sessions>/--<folder>--/<ts>_<sid>.jsonl · 첫 줄 session · session_info 이름들(pad 바이트 본문 사이) · 끝 assistant."""
    d = w.sess / ("--%s--" % str(folder).strip("/").replace("/", "-"))
    rows = [{"type": "session", "id": sid, "cwd": str(folder), "timestamp": "2026-11-16T00:00:00.000Z"}]
    for i, n in enumerate(names):
        rows += ([{"type": "message", "message": {"role": "user", "content": [{"type": "text", "text": "x" * pad}]}}] if i and pad else []) + [{"type": "session_info", "name": n}]
    rows += [{"type": "message", "message": {"role": "user", "content": [{"type": "text", "text": user}]}}] if user else []
    rows += [{"type": "message", "timestamp": "x", "message": {"role": "assistant", "stopReason": stop}}]
    f = d / ("2026-11-16T00-00-00-000Z_%s.jsonl" % sid)
    st._put(f, "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    os.utime(f, (st.T0 + mtime, st.T0 + mtime))
    return f


def acts(w):   # 깨움·kill·본문 도달 0·HELD-STALL·[크리티컬] = 행동
    lines = w.k.lines
    return (len(w.tmux("send-keys")), len(w.tmux("kill-session")), tb.held(lines), sum(x.startswith("HELD-STALL") for x in lines), len(tb.crit(w)))


def bound(w):   # id 파일로 결속 = 이 좌석 «판정 불가» 줄 0 · show-environment 1회
    return not [x for x in w.k.lines if x.startswith("판정 불가 harness %s %s" % (W, H0))] and len(w.tmux("show-environment")) == 1


def unsure(lines):
    return [x for x in lines if x.startswith("판정 불가") and "세션 id" in x]


def seat21(tmp, mp, ft2, old=False):   # ① tester#21 꼴 — intent worktree W2 폴더 파일 0 · 실 세션 = 다른 폴더 W10 의 *_X.jsonl(WORKING)
    w = envify(tb.world(tmp, mp, ft2, at=-20 * M, user=None), X)
    sfile(w, tmp / "W10", X, -10, stop="toolUse", user=tb.MARK + " 좌석 x")
    if old:   # ② W2 폴더에 다른 id 옛 IDLE 파일(30분 전)
        sfile(w, w.tree(), "old-0000", -30 * M)
    return w


def c1(tmp, mp, ft2):   # ① body-unreached 0 · reassign 0 · HELD-STALL 0 · [크리티컬] 0
    w = seat21(tmp, mp, ft2)
    w.round()
    assert acts(w) == (0, 0, 0, 0, 0) and w.kinds("dispatch") == 1 and bound(w), w.k.lines


def c2(tmp, mp, ft2):   # ② 옛 IDLE 파일 안 씀 · 깨움 0 · 재배정 0
    w = seat21(tmp, mp, ft2, old=True)
    w.round()
    assert acts(w) == (0, 0, 0, 0, 0) and w.kinds("dispatch") == 1 and bound(w), w.k.lines


def c3(tmp, mp, ft2):   # ③ env id X · 파일 0 → 판정 불가 1줄 · 행동 0 · 둘째 바퀴 같은 줄 0 / 다른 폴더 둘에 *_X 2개 → 같은 결과
    for two in (False, True):
        w = envify(tb.world(tmp / str(two), mp, ft2, at=-20 * M, user=None), X)
        if two:
            sfile(w, tmp / "W10", X, -10, stop="toolUse", user=tb.MARK + " 좌석 x")
            sfile(w, tmp / "W11", X, -10, stop="toolUse", user=tb.MARK + " 좌석 x")
        first = w.round()
        assert len(unsure(first)) == 1 and ("파일 2개" if two else "파일 0개") in unsure(first)[0] and acts(w) == (0, 0, 0, 0, 0), first
        assert unsure(w.round(M)) == [] and acts(w) == (0, 0, 0, 0, 0)


def c4(tmp, mp, ft2):   # ④ show-environment rc 1 → 판정 불가 1줄 · 행동 0
    w = envify(tb.world(tmp, mp, ft2, at=-20 * M, user=None), "rc1")
    lines = w.round()
    assert len(unsure(lines)) == 1 and "rc 1" in unsure(lines)[0] and acts(w) == (0, 0, 0, 0, 0), lines


def plain(tmp, mp, ft2, sid=None):   # r1813 꼴 좌석(진척 20분 전 · intent body_mark 없음) · 기본 세션 파일 지움
    w = st.World(tmp, mp, ft2)
    w.seat(step=-20 * M)
    shutil.rmtree(w.sess)
    return envify(w, sid)


def woke(lines):
    return sum(x.startswith("WOKE harness %s %s" % (W, H0)) for x in lines)


def c5(tmp, mp, ft2):   # ⑤ env id X · *_X 끝 = 끝난 턴 · 진척 20분 전 → 깨움 1(S2)
    w = plain(tmp, mp, ft2, X)
    sfile(w, tmp / "W10", X, -20 * M)
    assert woke(w.round()) == 1 and len(w.tmux("send-keys")) == 3, w.k.lines


def c6(tmp, mp, ft2):   # ⑥ id 없음 · holder 이름 파일 A(IDLE 20분 전) + 남 이름 파일 B(최근 WORKING) → A · 깨움 1
    w = plain(tmp, mp, ft2)
    sfile(w, w.tree(), "a", -20 * M, names=[H0])
    sfile(w, w.tree(), "b", -M, stop="toolUse", names=[OTHER])
    assert woke(w.round()) == 1, w.k.lines


def c7(tmp, mp, ft2):   # ⑦ id 없음 · 이름 없는 파일만 → 가장 최근(IDLE 16분 전) · 깨움 1
    w = plain(tmp, mp, ft2)
    sfile(w, w.tree(), "a", -16 * M)
    sfile(w, w.tree(), "b", -30 * M, stop="toolUse")
    assert woke(w.round()) == 1, w.k.lines


def c9(tmp, mp, ft2):   # ⑨ 끝 칸 — 이름 바뀜 파일(앞 남 · 66KB · 뒤 holder)은 D2 후보로 남음 / 빈 끝 이름 = 이름 없음 = 후보
    for i, names in enumerate(([OTHER, H0], [OTHER, ""])):
        w = plain(tmp / str(i), mp, ft2)
        sfile(w, w.tree(), "c", -16 * M, names=names, pad=66 * 1024)
        sfile(w, w.tree(), "d", -30 * M, stop="toolUse")
        assert woke(w.round()) == 1, (names, w.k.lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑨끝": c9}
KS = "adapters/pi/keeper_stall.py"
MUTANTS = {"M1": ("        if sid:\n", "        if False:\n", "①"),
           "M2": ('return hits[0] if len(hits) == 1 else Unsure("세션 id %s 파일 %d개" % (sid, len(hits)))', "return hits[0] if hits else None", "③"),
           "M3": ("files = [f for f in files if not foreign(f, holder, end)]", "files = files", "⑥")}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch, FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", monkeypatch, tree)
    CASES[case](tmp_path / "w2", monkeypatch, FT2)   # 원본으로 같은 사례 1회 더 = PASS
