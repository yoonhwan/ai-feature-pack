"""r1969 keeper b2 = b2c(close)·b2f(fill) 둘로 재기 · slow 칸 · 바퀴 캐시(cards git 2회·gates status 2회·list-sessions 1회) — 반례 ①~⑤ · 변이 M1~M4.
r1812 대역(keeper_world_r1812.World · 임시 git·가짜 tmux) · 바깥 호출 = k.call 감싸 세기 · 주입 시계 · 실 tmux·명부·설치 0 · sleep 0.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

kw = importlib.util.module_from_spec(importlib.util.spec_from_file_location("keeper_world_r1969", str(Path(__file__).with_name("keeper_world_r1812.py"))))
kw.__spec__.loader.exec_module(kw)
World, FT2, _put = kw.World, kw.FT2, kw._put
TEAMS, IDLE = ("aa", "bb", "cc"), "✻ Brewed for 3s\n❯ "
def kn_of(k):
    return type(k).team_round.__globals__["closing"].keeper_next
def counted(k):
    calls, real = [], k.call
    k.call = lambda argv, *a, **o: (calls.append(argv), real(argv, *a, **o))[1]
    return calls
def teams(w, names=TEAMS, cap="9"):
    """팀마다 대기 카드 1장(design/teams/<팀>/indices) · 표 행 `*` 1개 = 같은 카드 리포 · spawn·acct 표식 = status 호출이 생김."""
    w.commit("byz", {"design/teams/%s/indices/대기/r97-%s.md" % (t, t): "# 인덱스\n- 우선: 높음\n" for t in names}, "main")
    _put(w.state / "directive-roots.tsv", "*\t.\torigin/main\tdesign/teams/*/indices\n")
    for t in names:
        _put(w.state / "ft20-switch" / (t + ".json"), "{}"), w.runtime(t).mkdir(parents=True), w.enable(t)
    _put(w.state / "SPAWN_HOLD", "{}"), _put(w.state / "ACCT_PAUSE", "x")
    for tool, rc in (("spawn-hold", 3), ("acct-pause", 0)):   # 끔 = hold rc3 · acct rc0
        _put(w.tmp / "bin" / ("ft-%s.sh" % tool), "exit %d\n" % rc)
    w.env.update(FT2_TEAM_NANO_MAX=cap, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
def rounded(w, body):
    """한 바퀴(실 _round · 실 fetch) · team_round = body(k, kn, 팀) · B3·보고 0 → (keeper, 팀 단계까지 호출 목록, 팀별 반환).
    r1960 이후 B3 에 고아 점검(자기 list-sessions 1회)이 붙음 → 마지막 팀이 끝난 곳에서 자른다(셈 = 팀 단계만)."""
    k = w.keeper()
    kn, calls, got, cut = kn_of(k), counted(k), {}, [0]
    k.retired, k.report = (lambda: None), (lambda: None)
    k.team_round = lambda t: (got.__setitem__(t, body(k, kn, t)), cut.__setitem__(0, len(calls)))
    assert k.run_once() == 0
    return k, calls[:cut[0]], got
def n(calls, word):
    return sum(word in a for a in calls)
def c1(w):   # ① 팀 3개 fill(gates→cards) → cards git 2회 · status 2회 · list-sessions 1회 (팀 수와 무관)
    teams(w)
    _, calls, got = rounded(w, lambda k, kn, t: (kn.gates(k, t), kn.cards(k, t)))
    assert [n(calls, x) for x in ("ls-tree", "grep", "status", "list-sessions")] == [1, 1, 2, 1], calls
    assert all(g[0] is True and set(g[1][0]) == {"r97-" + t} for t, g in got.items()) and len(got) == 3, got
def c2(w):   # ② (DA R1) HELD Working 뒤 pane 만 idle · 착지 ref·intent·세션 그대로 → 다음 바퀴 close 1회 · CLOSED-SESSION + RECEIPT
    w.enable(), w.card("r9701", w.pack_sha()), w.work("r9701", done=True, alive=True, pane="⠋ Working...\n")
    k = w.keeper()
    first = list(w.round(k))
    assert any(x.startswith("HELD harness r9701") and "Working" in x for x in first), first
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["pane"] = {key: IDLE for key in d["pane"]}
    _put(w.tm, d)
    assert [x.split()[0] for x in w.round(k)[len(first):] if "r9701" in x] == ["CLOSED-SESSION", "RECEIPT"]
def c3(w):   # ③ 같은 바퀴 launch 직후 → gates = tmux 목록 ∪ launching (캐시가 합집합을 안 깸) · kill 뒤 = list-sessions 다시
    teams(w, ("aa",), cap="2")
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    _put(w.tm, dict(d, alive=["byz-aa-nano-old#0", "byz-aa-nano-gone#0"]))
    def body(k, kn, t):
        out = [kn.gates(k, t)]
        k.call([k.tmux, "kill-session", "-t", "=byz-aa-nano-gone#0"])
        out.append(kn.gates(k, t))
        k.cache.setdefault("launching", set()).add("byz-aa-nano-new#0")
        return out + [kn.gates(k, t)]
    _, calls, got = rounded(w, body)
    assert got["aa"] == [None, True, None] and n(calls, "list-sessions") == 2, (got, calls)
def c4(w):   # ④ 팀 2개 · 같은 카드 리포 → raw git 공유(2회) · 팀별 카드 선택은 따로(A 결과가 B 로 새지 않음)
    teams(w, ("aa", "bb"))
    _, calls, got = rounded(w, lambda k, kn, t: kn.cards(k, t))
    assert {t: sorted(g[0]) for t, g in got.items()} == {"aa": ["r97-aa"], "bb": ["r97-bb"]}, got
    assert n(calls, "ls-tree") + n(calls, "grep") == 2 and got["aa"][0]["r97-aa"][1] is True, calls
def c5(w):   # ⑤ ROUND 줄 = b2c(close)·b2f(fill) 둘 · slow=<팀>:<칸>:<초> 1칸 (로그 1줄 그대로)
    w.card("r9702", w.pack_sha()), w.work("r9702", intent=False)
    k = w.keeper()
    def tick(dt, out=None):
        return setattr(w, "t", w.t + dt) or out
    kn = kn_of(k)
    real, kn.fill = kn.fill, (lambda k, t: tick(2))
    try:
        k.complete, k.close, k.retired = (lambda *a: tick(1, True)), (lambda *a: tick(4)), (lambda: None)
        rows = [x for x in w.round(k) if x.startswith("ROUND")]
    finally:
        kn.fill = real
    assert rows == ["ROUND s=7 fetch=0 b1=1 b2c=4 b2f=2 b3=0 stall=0 slow=harness:b2c:4"], rows
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}
KP, KN = "adapters/pi/keeper.py", "adapters/pi/keeper_next.py"
CLOSE = 'self.timed("b2c", self.close, team, work, attempt, row, dispatched)'
PAD = " " * 20   # r1960 끝 갈래도 같은 close 줄(들여쓰기 16) → done 갈래(20) 1곳만 변이
MUTANTS = {"M1": (KN, "return fn() if got is None else", "return fn() if True else", c1),
           "M2": (KP, PAD + CLOSE, PAD + 'None if self.state.setdefault("m2", {}).setdefault(work, False) else self.state["m2"].update({work: True}) or ' + CLOSE, c2),
           "M3": (KN, ' | k.cache.get("launching", set())) if rc == 0', ") if rc == 0", c3),
           "M4": (KN, ' and os.path.dirname(p) == mine}', "}", c4)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree))
