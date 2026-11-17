"""r1963b keeper 판정 앞 fetch — 리포마다 ls-remote 1회(고정 ref + 표 ref + 나노 가지를 한 번에) · 나노 가지 모으기 = fetch 시계 밖(ROUND nano= 칸).
반례 ①~⑦(⑤′ = 사전 DA HOLD 보정) · 변이 M1~M6 · r1812 대역(World) 재사용 · 실제 git · tmp bare 원격 · 시험 코드 sleep 0.
실사건: r1975(나노 가지) 뒤 BYZ ls-remote 가 바퀴마다 2회(실재 확인 --heads + 신선 대조) → 안 바뀐 바퀴 fetch 3.5초 → 7.4초.
"""
import importlib.util
import re
import shutil
import threading
import types
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1963b", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, _git, _put = kw.World, kw.FT2, kw._git, kw._put
KP, FAIL = "adapters/pi/keeper.py", "판정 불가 git fetch 실패"


def spy(k, deny=()):   # keeper 의 바깥 호출 기록 · deny 의 git 동사는 rc 1 로 바꿔 돌려줌
    calls, real = [], k.call
    k.call = lambda argv, *a, **b: (calls.append(list(argv)), (1, "", "deny") if argv[3:4] and argv[3] in deny else real(argv, *a, **b))[1]
    return calls
def of(w, calls, verb, repo):   # 그 리포 그 동사 호출의 꼬리 인자(ls-remote = ref 이름들 · fetch = refspec 들)
    return [a[5 if verb == "ls-remote" else 7:] for a in calls if a[:4] == ["git", "-C", str(w.tmp / repo), verb]]
def sync(w):   # 두 리포를 손으로 최신으로(keeper 밖 · 원격 추적 ref 전부)
    _git(w.root, "fetch", "-q", "origin"), _git(w.tmp / "pack", "fetch", "-q", "origin")
def ref(w, repo, name):
    return _git(w.tmp / repo, "rev-parse", "refs/remotes/origin/" + name)
def spec(*names):
    return ["+refs/heads/%s:refs/remotes/origin/%s" % (n, n) for n in names]
def nano(w, n, remote=lambda i: True):   # 팩 나노 일 n 개 · intent worktree = 팩 linked worktree(HEAD nano/<work>) · remote(i) 거짓 = 원격에 그 가지 없음
    for i in range(n):
        work = "r93%02d" % i
        remote(i) and w.commit("pack", {"n": work}, "nano/" + work, new=True)
        w.work(work)
        _git(w.tmp / "pack", "worktree", "add", "-q", "-b", "nano/" + work, str(w.tmp / "wt" / work))
    return ["nano/r93%02d" % i for i in range(n)]
def run(w, deny=()):
    k = w.keeper()
    calls = spy(k, deny)
    return calls, w.round(k)
def kf_of(k):
    return type(k).__init__.__globals__["kf"]
def c1(w):   # ① 나노 가지 3 + 두 리포 안 바뀜 → 리포마다 ls-remote 1 · fetch 0 · --heads 꼴 0
    names = nano(w, 3)
    sync(w)
    calls, lines = run(w)
    assert of(w, calls, "ls-remote", "pack") == [["refs/heads/" + n for n in ["main"] + names]] and len(of(w, calls, "ls-remote", "root")) == 1, calls
    assert of(w, calls, "fetch", "pack") == of(w, calls, "fetch", "root") == [] and not [a for a in calls if "--heads" in a], calls
    assert not [x for x in lines if x.startswith(FAIL)], lines
def c2(w):   # ② 나노 가지 1개만 원격이 앞섬 → 팩 ls-remote 1 + fetch 1(main + 나노 3) · BYZ fetch 0 · 로컬 원격 추적 ref = 새 sha
    names = nano(w, 3)
    sync(w)
    new = w.commit("pack", {"n2": "x"}, names[1])
    calls, lines = run(w)
    assert len(of(w, calls, "ls-remote", "pack")) == 1 and of(w, calls, "fetch", "pack") == [spec("main", *names)] and of(w, calls, "fetch", "root") == [], calls
    assert ref(w, "pack", names[1]) == new and not [x for x in lines if x.startswith(FAIL)], lines
def c3(w):   # ③ 표 origin/foo = 원격 있음·로컬 ref 없음 · origin/bar = 원격 없음 → ls-remote 1 · fetch 1(foo 있음·bar 없음) · 실패 0
    foo = w.commit("byz", {}, "foo", new=True)
    _put(w.state / "directive-roots.tsv", "harness\t.\torigin/foo\td/h/i\nplanner\t.\torigin/bar\td/p/i\n")
    calls, lines = run(w)
    assert of(w, calls, "ls-remote", "root") == [["refs/heads/" + n for n in ("main", "ops/main-base", "foo", "bar")]], calls
    assert of(w, calls, "fetch", "root") == [spec("main", "ops/main-base", "foo")] and ref(w, "root", "foo") == foo, calls
    assert not [x for x in lines if x.startswith(FAIL)], lines
def c4(w):   # ④ 나노 가지 7 가운데 앞 3개가 원격에 없음 → main + 남은 4 = 5 · FETCH-CAP 0(없는 가지가 상한 칸을 먹지 않는다)
    names = nano(w, 7, remote=lambda i: i >= 3)
    calls, lines = run(w)
    assert of(w, calls, "fetch", "pack") == [spec("main", *names[3:])] and not [x for x in lines if x.startswith(("FETCH-CAP", FAIL))], (calls, lines)
def c5(w):   # ⑤ ls-remote rc≠0 + extra 전부 원격에 있음(표 foo 는 원격이 앞섬) → ls-remote 1(재시도 0) · fetch 1회에 extra 포함 · foo = 새 sha · 신선
    nano(w, 2), w.commit("byz", {}, "foo", new=True)
    _put(w.state / "directive-roots.tsv", "harness\t.\torigin/foo\td/h/i\n")
    sync(w)
    new = w.commit("byz", {"f": "2"}, "foo")
    calls, lines = run(w, deny=("ls-remote",))
    assert len(of(w, calls, "ls-remote", "pack")) == 1 and of(w, calls, "fetch", "pack") == [spec("main", "nano/r9300", "nano/r9301")], calls
    assert of(w, calls, "fetch", "root") == [spec("main", "ops/main-base", "foo")] and ref(w, "root", "foo") == new, calls
    assert not [x for x in lines if x.startswith(FAIL)], lines
def c5b(w):  # ⑤′(사전 DA HOLD) ls-remote rc≠0 + 표 ref foo 는 원격이 앞섬 · bar 는 원격에 없음 → 고정 ref 만 받고 신선 선언 0: BYZ 낡음 1줄 · 착지된 일도 COMPLETED 0
    w.card("r9405", w.pack_sha()), w.work("r9405", intent=False), w.commit("byz", {}, "foo", new=True)
    _put(w.state / "directive-roots.tsv", "harness\t.\torigin/foo\td/h/i\nplanner\t.\torigin/bar\td/p/i\n")
    sync(w)
    old, k = ref(w, "root", "foo"), w.keeper()
    assert w.commit("byz", {"f": "2"}, "foo") != old
    spy(k, deny=("ls-remote",))
    lines = w.round(k)
    assert str(w.root) in k.stale and [x for x in lines if x.startswith(FAIL)] == ["%s %s — 이 바퀴 B1·B2 0" % (FAIL, w.root)], lines
    assert w.kinds("complete") == 0 and not [x for x in lines if x.startswith("COMPLETED")], lines
def c6(w):   # ⑥ 주입 시계: 나노 모으기 3초 · fetch 4초 → ROUND fetch=4 · nano=3 · s=7 / 모으기 0초 → nano= 칸 없음(옛 줄 그대로)
    sync(w), w.pack_sha()
    w.work("c6w")   # 나노 모으기 대상 = 팀·일 1개 · 팀이 0 이면 바꿔 둔 nanos 가 한 번도 안 불려 사례가 원래 실패한다(DA 실측)
    k = w.keeper()
    type(k).__init__.__globals__["time"] = types.SimpleNamespace(monotonic=lambda: w.t, time=lambda: w.t)   # 60초 카드 시험의 주입 꼴 — 이 World 모듈 안에서만 · 나노 모으기 초는 keeper 가 time.monotonic 으로 잰다
    real, git, bump = kf_of(k).nanos, k.git, threading.Lock()
    kf_of(k).nanos = lambda *a: (setattr(w, "t", w.t + 3), real(*a))[1]
    def fetcht(repo, *a, **o):   # fetch 4초 = 두 리포를 동시에 도는 한 구간(동시라 한 번만 늘린다 — fetch_root·fetch_pack 칸은 안 본다)
        if a[0] == "fetch":
            with bump:
                if not getattr(w, "bumped", False):
                    w.bumped, w.t = True, w.t + 4
        return git(repo, *a, **o)
    k.git = fetcht
    row = [x for x in w.round(k) if x.startswith("ROUND")][0]
    cell = dict(re.findall(r"(\w+)=([\d.]+)", row))
    assert (cell["fetch"], cell.get("nano"), cell["s"]) == ("4", "3", "7"), row
    assert " nano=" not in [x for x in w.round(w.keeper()) if x.startswith("ROUND")][0]
def c7(w):   # ⑦ FETCH_TARGETS 있음(root main) → ls-remote 1 · 인자 = refs/heads/main 만 · 나노 모으기 0 · 팩 호출 0
    nano(w, 1)
    _put(w.state / "ft2-keeper" / "FETCH_TARGETS", "root\tmain\n")
    k, seen = w.keeper(), []
    kf_of(k).nanos = lambda *a: seen.append(a) or {}
    calls = spy(k)
    w.round(k)
    assert of(w, calls, "ls-remote", "root") == [["refs/heads/main"]] and of(w, calls, "ls-remote", "pack") == [] and seen == [], (calls, seen)
CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c5b": c5b, "c6": c6, "c7": c7}
ONE = "fixed, extra = (list(dict.fromkeys(self.table.get(repo, []))), []) if self.table else self.cand(repo)"
CAP = "self.cap(repo, fixed + [n for n in extra if n in seen])"
MUTANTS = {"M1": (CAP, "self.cap(repo, fixed + extra)", c3),                                                    # extra 를 원격 답으로 안 거름 → 없는 ref fetch
           "M2": (ONE, ONE + "\n        self.table or self.default_refs(repo)", c1),                             # 실재 확인 ls-remote 를 따로 한 번 더(2회)
           "M3": (CAP, "self.cap(repo, [n for n in (fixed + extra)[:kf.CAP] if n in fixed or n in seen])", c4),   # 거르기 앞에 상한 자름
           "M4": ("if rc == 0 else set(extra)", "if rc == 0 else set()", c5b),                                     # ls-remote 실패 때 extra 를 빼고 고정 ref 만으로 신선
           "M5": ("        self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), time.monotonic() - at, None\n",
                  '        self.nano, self.nano_s, self.nano_dl = ({} if self.table else got), 0.0, None; self.spent["fetch"] += time.monotonic() - at\n', c6),   # 나노 모으기를 fetch 시계 안에
           "M6": ("        s += self.nano_s", "        s += 0", c6)}                                              # 나노 초를 s 에 안 넣음


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):   # 변이 = 사본에서만 → 그 사례 FAIL
    old, new, case = MUTANTS[name]
    (tmp_path / "o").mkdir()
    case(World(tmp_path / "o", monkeypatch))   # L4 대조 — 원본에서 그 사례가 먼저 통과해야 한다(사례가 원래 실패하면 변이 틀은 빈 통과)
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree))
