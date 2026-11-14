"""r1963 keeper fetch — 바뀐 것 없으면 fetch 0(ls-remote sha = 로컬) · 두 리포 동시 · 낡은 리포에 기대는 판정만 0.
반례 ①~⑪ · 변이 M1~M8(M8 = ⑩ 다음 카드 보류 삭제 · r1913 세계 재사용). r1812 대역(World) 재사용 · 실제 git · tmp bare 원격 · 시험 코드 sleep 0.
낡음 = 그 리포 clone 의 remote.origin.url 을 없는 경로로(ls-remote·fetch 둘 다 rc≠0) · ⑨ 느린 원격 = uploadpack 앞 3초 지연(실제 git-upload-pack).
원인 실측: fetch 끝의 연결 검사(rev-list --not --all)가 그 리포 모든 ref 를 읽는다 — 네트워크만 쓰는 ls-remote 로 «안 바뀜» 을 먼저 가린다.
"""
import importlib.util
import shutil
import time
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1963", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, AB, _git, _lines = kw.World, kw.FT2, kw.AB, kw._git, kw._lines
FAIL, ALL, PACK_ONLY = "판정 불가 git fetch 실패", "이 바퀴 B1·B2 0", "팩 기대 판정만 0"


def lose(w, repo):   # 그 리포를 낡게: 원격 주소를 없는 경로로 → 되돌리는 함수
    old = _git(w.tmp / repo, "config", "remote.origin.url")
    _git(w.tmp / repo, "config", "remote.origin.url", str(w.tmp / "gone.git"))
    return lambda: _git(w.tmp / repo, "config", "remote.origin.url", old)
def sync(w):   # 두 리포를 손으로 최신으로(keeper 밖)
    _git(w.root, "fetch", "-q", "origin"), _git(w.tmp / "pack", "fetch", "-q", "origin")
def spy(k, deny=()):   # keeper 의 바깥 호출 기록 · deny 의 git 동사는 rc 1 로 바꿔 돌려줌
    calls, real = [], k.call
    k.call = lambda argv, *a, **b: (calls.append(list(argv)), (1, "", "deny") if argv[3:4] and argv[3] in deny else real(argv, *a, **b))[1]
    return calls
def count(w, calls, verb, repo):
    return sum(a[:4] == ["git", "-C", str(w.tmp / repo), verb] for a in calls)
def ref(w, repo, name="main"):
    return _git(w.tmp / repo, "rev-parse", "refs/remotes/origin/" + name)
def fails(lines):
    return [x for x in lines if x.startswith(FAIL)]
def c1(w):   # ① 팩 낡음 · BYZ 신선 · BYZ ops/main-base 착지 → 그 바퀴 COMPLETED · 로그 «팩 기대 판정만 0» 1줄
    w.card("r9101", w.commit("byz", {"o.txt": "o"}, "ops/main-base"), refs=("main",)), w.work("r9101", intent=False), lose(w, "pack")
    lines = w.round()
    assert any(x.startswith("COMPLETED harness r9101") for x in lines) and w.kinds("complete") == 1, lines
    assert len(fails(lines)) == 1 and str(w.tmp / "pack") in fails(lines)[0] and PACK_ONLY in fails(lines)[0] and str(w.root) not in fails(lines)[0], lines
def c2(w):   # ② 팩 낡음 · 착지 sha 가 (낡은) 팩 ref 에만 → HELD «판정 불가 · 팩 fetch 실패» · 미도달 알림 0 · complete 0
    w.card("r9102", w.pack_sha()), w.work("r9102", intent=False), sync(w), lose(w, "pack")
    lines = w.round()
    assert any(x.startswith("HELD harness r9102 판정 불가 · 팩 fetch 실패") for x in lines) and w.kinds("complete") == 0, lines
    assert _lines(str(w.mbox) + ".log") == [] and not any("미도달" in x for x in lines), lines
def c3(w):   # ③ 둘 다 낡음 → 지금과 같이 B1·B2 0 · 1줄(두 리포 경로 · 루트 먼저)
    w.card("r9103", w.pack_sha()), w.work("r9103", intent=False), sync(w), lose(w, "root"), lose(w, "pack")
    lines = w.round()
    assert fails(lines) == ["%s %s %s — %s" % (FAIL, w.root, w.tmp / "pack", ALL)] and w.kinds("complete") == 0, lines
def c4(w):   # ④ 둘 다 바뀜 → 리포마다 fetch 1회 · 낡음 0 · COMPLETED
    w.card("r9104", w.pack_sha()), w.work("r9104", intent=False)
    k = w.keeper()
    calls = spy(k)
    lines = w.round(k)
    assert not fails(lines) and any(x.startswith("COMPLETED harness r9104") for x in lines), lines
    assert (count(w, calls, "fetch", "root"), count(w, calls, "fetch", "pack")) == (1, 1), calls
def c5(w):   # ⑤(DA 재현) BYZ 낡음 · 팩 신선: 로컬 BYZ 카드 = 착지 X(팩 조상) · 원격은 Y 로 정정 → landed 0 · B1·B2 0
    w.card("r9105", w.pack_sha()), w.work("r9105", intent=False), sync(w), w.card("r9105", AB), lose(w, "root")
    lines = w.round()
    assert w.kinds("complete") == 0 and not any(x.startswith("COMPLETED") for x in lines), lines
    assert len(fails(lines)) == 1 and str(w.root) in fails(lines)[0] and ALL in fails(lines)[0], lines
def c6(w):   # ⑥ 두 리포 모두 원격 sha = 로컬 → fetch 호출 0 · ls-remote 리포마다 1회 · 판정은 ④ 와 같음
    w.card("r9106", w.pack_sha()), w.work("r9106", intent=False), sync(w)
    k = w.keeper()
    calls = spy(k)
    lines = w.round(k)
    assert not fails(lines) and any(x.startswith("COMPLETED harness r9106") for x in lines), lines
    assert [count(w, calls, v, r) for v in ("fetch", "ls-remote") for r in ("root", "pack")] == [0, 0, 1, 1], calls
def c7(w):   # ⑦ 팩만 원격 sha 다름 → 팩 fetch 1회 · BYZ fetch 0 · 팩 ref 갱신
    sync(w)
    sha, k = w.pack_sha(), w.keeper()
    calls = spy(k)
    lines = w.round(k)
    assert not fails(lines) and (count(w, calls, "fetch", "root"), count(w, calls, "fetch", "pack")) == (0, 1) and ref(w, "pack") == sha, calls
def c8(w):   # ⑧ ls-remote rc≠0 → 그 리포는 fetch 로 간다(재시도 0 = 시도 합 2) · fetch rc0 = 신선 · 판정 계속
    w.card("r9108", w.pack_sha()), w.work("r9108", intent=False), sync(w)
    main, k = w.commit("byz", {"a": "8"}, "main"), w.keeper()
    calls = spy(k, deny=("ls-remote",))
    lines = w.round(k)
    assert not fails(lines) and any(x.startswith("COMPLETED harness r9108") for x in lines) and ref(w, "root") == main, lines
    assert (count(w, calls, "fetch", "root"), count(w, calls, "fetch", "pack")) == (1, 1), calls
def c9(w):   # ⑨ 두 원격이 각각 3초 걸림 → fetch 단계는 느린 쪽 하나(동시) · 차례로면 6초+
    sync(w)
    for repo in ("root", "pack"):
        _git(w.tmp / repo, "config", "remote.origin.uploadpack", "sleep 3; git-upload-pack")
    at = time.monotonic()
    lines = w.round()
    took = time.monotonic() - at
    assert not fails(lines) and took < 5.5, (took, lines)
def c11(w):  # ⑪ 앞 바퀴 팩 낡음(② HELD) → 이번 바퀴 둘 다 신선 → 낡음 집합 비어 있음 · 그 work COMPLETED
    w.card("r9111", w.pack_sha()), w.work("r9111", intent=False), sync(w)
    back, k = lose(w, "pack"), w.keeper()
    assert any(x.startswith("HELD harness r9111 판정 불가 · 팩 fetch 실패") for x in w.round(k)) and k.stale == {str(w.tmp / "pack")}
    back()
    done = len(k.lines)
    lines = w.round(k)[done:]
    assert k.stale == set() and not fails(lines) and any(x.startswith("COMPLETED harness r9111") for x in lines), lines
f13 = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_fill_r1963", str(Path(__file__).with_name("test_keeper_fill_empty_slot_r1913.py"))))
f13.__spec__.loader.exec_module(f13)
def c10(tmp, mp, ft2=FT2):   # ⑩ 팩 낡음 · 다음 카드 후보 = 팩 대상 1(긴급 · 신선하면 먼저 뽑힘) + BYZ 대상 3 → 팩 카드 보류 1줄 · BYZ 카드는 지금처럼 연다 · 낡은 base 로 열기 0
    w = f13.world(tmp, mp, ft2=ft2)
    w.commit("byz", {"design/harness/indices/대기/r9000-p.md": "# 인덱스: r9000-p\n- 긴급: 예\n- 대상: 팩 feature-pack/x.py\n- 상태: 대기\n"}, "main")
    lose(w, "pack")
    lines = w.round(f13.keeper(w, mp)[0])
    assert "판정 불가 harness 다음 카드 보류 1장 · 팩 fetch 실패" in lines and f13.nx.launched(w) == [f13.A], (lines, f13.nx.launched(w))
def test_c10(tmp_path, monkeypatch):
    c10(tmp_path, monkeypatch)
def test_mutant_m8(tmp_path, monkeypatch):   # M8 팩 낡음 보류 삭제 → ⑩ FAIL(낡은 base 로 팩 카드를 연다)
    tree, old = tmp_path / "m" / "ft2", 'block = block or ("팩낡음" if place[0] in k.stale else "")'
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / "adapters/pi/keeper_next.py").read_text(encoding="utf-8")
    assert text.count(old) == 1
    (tree / "adapters/pi/keeper_next.py").write_text(text.replace(old, "pass"), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        c10(tmp_path / "w", monkeypatch, tree)
CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6, "c7": c7, "c8": c8, "c9": c9, "c11": c11}
KP, KL = "adapters/pi/keeper.py", "adapters/pi/keeper_land.py"
ORDER = "order = [] if self.root in self.stale else self.teams()"
MUTANTS = {"M1": (KP, ORDER, "order = [] if self.stale else self.teams()", c1),                      # 낡음 있으면 통째 0 그대로
           "M2": (KL, "if repo not in self.stale and self.git(", "if self.git(", c2),               # 낡은 팩 ref 도 조상 검사
           "M3": (KL, 'if self.stale else (sha, None, "미도달")', 'if False else (sha, None, "미도달")', c2),   # 낡음 사유 대신 미도달
           "M4": (KP, "near.split() == [far.get(n) for n in names]", "True", c7),                   # ls-remote 결과를 안 보고 늘 신선
           "M5": (KP, "pool.map(self.fresh, repos)", "map(self.fresh, repos)", c9),                 # 두 리포 차례로
           "M6": (KP, ORDER, "order = self.teams()", c5),                                           # BYZ 낡음에도 순회
           "M7": (KP, "self.stale = {", "self.stale |= {", c11)}                                    # 낡음 집합을 바퀴 사이에 안 비움


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):   # 변이 = 사본에서만 → 그 사례 FAIL(원본 PASS 는 test_case 가 본다)
    path, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree))
