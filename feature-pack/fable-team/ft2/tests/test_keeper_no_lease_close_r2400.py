"""r2400 keeper «근거 없는 나노» 닫기·열기 관문 (카드 반례 ①~⑨ · 변이 M1~M7).
대역 = r2055 settle 시험 세계(임시 root · BYZ·팩 리포 · 가짜 tmux·gh·ps·mbox · FT2_SEAT_RESUME_DIR) + 생애 영수 판독(#{session_id}) ·
실 tmux·명부·Slack 0 · sleep 0(시계 = 주입 w.t). 기준판 = ① CLOSED-NOLEASE 0 · ④ HELD-NOLEASE 0 · ⑥ 관문 참 · ⑧ 예정 0 → Red.
변이는 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2400_settle", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
t = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t)
kw = t.kw
TEAM = t.TEAM
IDLE = "✻ Brewed for 3s\n❯ "
BUSY = "⠋ Working (2s)\n❯ "
LIFE = '''if a[0] == "display-message" and "#{session_id}" in a[-1]:
    t = a[a.index("-t") + 1][1:-1]; sys.stdout.write(d.get("life", {}).get(t, "") + "\\n"); sys.exit(0 if t in d["alive"] else 1)
if a[0] == "kill-session"'''


def world(tmp, mp, ft2=kw.FT2, cap="6"):
    """한 세계 — 가짜 tmux 에 list-sessions · 생애(#{session_id}) 갈래를 심고 나노 상한 = 6(카드 ⑥ «정원 2 / 상한 6»)."""
    tmp.mkdir(parents=True, exist_ok=True)
    w = t.world(tmp, mp, ft2)
    i = kw.TMUX.replace("__PY__", sys.executable).replace('if a[0] == "kill-session"', LIFE, 1)
    kw._put(w.tmp / "bin" / "tmux", i)
    w.env["FT2_TEAM_NANO_MAX"] = cap
    return w


def tm(w, **kv):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    for key, val in kv.items():
        if isinstance(val, dict):
            d[key] = dict(d.get(key, {}), **val)
        elif key == "alive":
            d[key] = d.get(key, []) + [x for x in val if x not in d.get(key, [])]
        else:
            d[key] = val
    kw._put(w.tm, d)


def orphan(w, work, seat="#1", age=400, files=1, pane=IDLE, hand=False, life=None, holder_alive=False):
    """dispatch 밖 석 1개 — work(holder #0) · 그 석의 launch intent(생애 영수 $9/200) 또는 손 개설(intent 0 · pane 폴더)·jsonl files개(무활동 age)."""
    t.nano(w, work, age=age, alive=holder_alive)
    name = "byz-%s-nano-%s%s" % (TEAM, work, seat)
    tree, folder = str(w.tmp / "wt" / work), Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(w.tmp / "wt" / work).strip("/").replace("/", "-"))
    for extra in sorted(folder.glob("*.jsonl"))[files:]:   # files 개로 맞춘다
        extra.unlink()
    for n in range(len(sorted(folder.glob("*.jsonl"))), files):
        extra = folder / ("x%d.jsonl" % n)
        extra.parent.mkdir(parents=True, exist_ok=True)
        extra.write_text('{"type": "session"}\n', encoding="utf-8")
        os.utime(extra, (w.t - age, w.t - age))
    if hand:   # 손으로 연 석 = intent 0 · pane 폴더에 다른 대화의 Pi jsonl
        cwd = str(w.tmp / "hand" / work)
        for n in range(files):
            log = Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % cwd.strip("/").replace("/", "-")) / ("h%d.jsonl" % n)
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text('{"type": "session"}\n', encoding="utf-8")
            os.utime(log, (w.t - age, w.t - age))
        tm(w, path={name: cwd}, life={name: "$9\t200\t" + cwd})
    else:
        kw._put(w.runtime() / "launch" / ("%s@a9.intent" % work),
                {"FT2_HOLDER": name, "state": "opened", "worktree": tree, "at": "2026-01-01T00:00:00", "tmux_sid": "$9", "tmux_created": "200"})
        tm(w, life={name: life or "$9\t200\t" + tree})
    tm(w, alive=[name], pane={name: pane})
    return name


def log_of(w, work):
    """그 work 의 Pi 세션 폴더 첫 jsonl 경로."""
    return next(iter(sorted((Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(w.tmp / "wt" / work).strip("/").replace("/", "-"))).glob("*.jsonl"))))


def rnd(w, k=None, dt=0, cmd="pi", cpu=0.0):
    """한 바퀴 — 시계 dt 초 앞으로 · pane 명령·ps 표 주입(사슬 끝 %cpu) · keeper 인스턴스는 넘긴 것(state 이어짐)."""
    k = k or w.keeper()
    w.t += dt
    kw._put(str(w.tm) + ".clean", "")
    k.pane_info = lambda seat: (100, cmd)
    k.ps_rows = lambda: [(p, pp, cpu if c is None else c, n) for p, pp, c, n in t.CHAIN]
    return w.round(k)


def two(w, k=None, **kv):
    """CPU 쉼 판정 = 표본 2개(간격 30초)."""
    k = k or w.keeper()
    return rnd(w, k, **kv) + rnd(w, k, dt=30, **kv)


def kn(k):
    return type(k).close.__globals__["keeper_next"]


def kills(w):
    return w.tmux("kill-session")


def resumed(w):
    base = w.tmp / "resume"
    return sorted(p.name for p in base.glob("*.json")) if base.exists() else []


def urgent(w, word):
    return [x for x in t.sent(w) if "[긴급]" in x and word in x]


def switch(w, val="1"):
    w.env["FT2_NOLEASE_CLOSE"] = val


# ── 반례 ①~⑨ ─────────────────────────────────────────────────────────

def c1(tmp, mp, ft2=kw.FT2):   # ① 근거 없음 · 스위치 1 · 무활동 400 · CPU idle 2회 · attached 0 → 재개 기록 1 · kill 1 · CLOSED-NOLEASE
    w = world(tmp, mp, ft2)
    switch(w)
    seat = orphan(w, "r2401", age=400)
    lines = two(w)
    assert t.has(lines, "CLOSED-NOLEASE", TEAM, "r2401", seat), lines
    assert kills(w) == [["kill-session", "-t", "=" + seat]], kills(w)
    assert resumed(w) == [seat + ".json"], resumed(w)


def c1b(tmp, mp, ft2=kw.FT2):   # ① 둘째 구 무활동 200초 → 닫기 0 · WORKING orphan-open 그대로(문턱 300초)
    w = world(tmp, mp, ft2)
    switch(w)
    orphan(w, "r2402", age=200)
    lines = two(w)
    assert t.has(lines, "WORKING", TEAM, "r2402", "orphan-open"), lines
    assert not kills(w) and resumed(w) == [], (kills(w), resumed(w))


def c2(tmp, mp, ft2=kw.FT2):   # ② attached 1 → 닫기 0 · WORKING attached / pane 에 Working → 닫기 0
    w = world(tmp, mp, ft2)
    switch(w)
    seat = orphan(w, "r2403")
    tm(w, att={seat: 1})
    lines = two(w)
    assert t.has(lines, "WORKING", TEAM, "r2403", "attached") and not kills(w) and resumed(w) == [], lines
    w2 = world(tmp / "second", mp, ft2)
    switch(w2)
    orphan(w2, "r2404", pane=BUSY)
    lines = two(w2)
    assert not kills(w2) and resumed(w2) == [] and t.has(lines, "WORKING", TEAM, "r2404"), lines


def c3(tmp, mp, ft2=kw.FT2):   # ③ intent worktree 폴더 jsonl 2개 → 닫기 0 · 재개 기록 0 · UNKNOWN no-lease-resume [긴급] 1
    w = world(tmp, mp, ft2)
    switch(w)
    seat = orphan(w, "r2405", files=2)
    lines = two(w)
    assert t.has(lines, "UNKNOWN", TEAM, "r2405", seat, "no-lease-resume"), lines
    assert not kills(w) and resumed(w) == [] and len(urgent(w, "no-lease-resume")) == 1, (kills(w), resumed(w), t.sent(w))


def c4(tmp, mp, ft2=kw.FT2):   # ④ 손 개설(intent 0) · 스위치 1 · pane 폴더 jsonl 1개 · 무활동 400 → 기록 0 · kill 0 · HELD-NOLEASE 1줄 / 다음 바퀴 줄 0
    w = world(tmp, mp, ft2)
    switch(w)
    seat = orphan(w, "r2406", hand=True, age=400)
    lines = two(w)
    assert t.has(lines, "HELD-NOLEASE", TEAM, seat), lines
    assert not kills(w) and resumed(w) == [], (kills(w), resumed(w))
    again = rnd(w, dt=30) + rnd(w, dt=30)
    assert not t.has(again, "HELD-NOLEASE"), again   # 하루 1줄


def c5(tmp, mp, ft2=kw.FT2):   # ⑤ 스위치 없음 → «예정 CLOSED-NOLEASE … 스위치 끔» 1줄 · kill 0 · 기록 0 / 스위치 «true» → 같은 결과
    for val in (None, "true"):
        w = world(tmp / str(val), mp, ft2)
        if val:
            switch(w, val)
        seat = orphan(w, "r2407")
        lines = two(w)
        assert t.has(lines, "예정", "CLOSED-NOLEASE", TEAM, "r2407", seat, "스위치 끔"), lines
        assert not kills(w) and resumed(w) == [], (kills(w), resumed(w))


def c6(tmp, mp, ft2=kw.FT2):   # ⑥ 근거 없는 석이 남은 팀 · 정원 2 / 상한 6 → gates 거짓 · NEXT-HOLD «근거 없는 석 1» · [긴급] 두 바퀴에 1통 / 석이 사라진 다음 바퀴 → gates 참
    w = world(tmp, mp, ft2)
    w.enable()
    switch(w, "true")   # ⑤ 자리 = 닫지 못하고 남는다
    seat = orphan(w, "r2408", holder_alive=True)
    k = w.keeper()
    lines = two(w, k) + rnd(w, k, dt=30)   # 3바퀴째 b2f 관문이 지난 바퀴 «근거 없는 석» 을 본다
    assert t.has(lines, "NEXT-HOLD", TEAM, "근거 없는 석 1"), lines
    assert kn(k).gates(k, TEAM) is None
    lines = rnd(w, k, dt=30)   # 같은 날 두 바퀴 = [긴급] 1통
    assert len(urgent(w, "근거 없는 석")) == 1, t.sent(w)
    tm(w, alive=[])   # 그 석이 사라진 다음 바퀴
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"] = [x for x in d["alive"] if x != seat]
    kw._put(w.tm, d)
    rnd(w, k, dt=30)
    assert kn(k).gates(k, TEAM) is True, k.lines


def c7(tmp, mp, ft2=kw.FT2):   # ⑦ dispatch 밖 석 무활동 100초 · 정원 2 / 상한 6 → gates 참(관문에 안 셈)
    w = world(tmp, mp, ft2)
    w.enable()
    switch(w)
    orphan(w, "r2409", age=100)
    k = w.keeper()
    rnd(w, k, dt=100)
    assert kn(k).gates(k, TEAM) is True and not t.has(k.lines, "NEXT-HOLD", "근거 없는 석"), k.lines


def c8(tmp, mp, ft2=kw.FT2):   # ⑧ ALL_STOP 중 ① → «예정 CLOSED-NOLEASE» 1줄 · kill 0 · 기록 0
    w = world(tmp, mp, ft2)
    switch(w)
    kw._put(w.state / "ALL_STOP.json", {})
    seat = orphan(w, "r2410")
    lines = two(w)
    assert t.has(lines, "예정", "CLOSED-NOLEASE", TEAM, "r2410", seat, "ALL_STOP"), lines
    assert not kills(w) and resumed(w) == [], (kills(w), resumed(w))


def c9(tmp, mp, ft2=kw.FT2):   # ⑨ 끝 근거 있는 고아(카드 아카이브) = 지금 줄 그대로 CLOSED-ORPHAN
    w = world(tmp, mp, ft2)
    switch(w)
    w.card("r2411", stage="아카이브/2026-11")
    seat = orphan(w, "r2411", age=7200)
    lines = two(w)
    assert t.has(lines, "CLOSED-ORPHAN", TEAM, "r2411", seat) and kills(w) == [["kill-session", "-t", "=" + seat]], lines
    assert not t.has(lines, "CLOSED-NOLEASE"), lines


def c6b(tmp, mp, ft2=kw.FT2):   # ⑥b 활동이 돌아온 석 = K1 거짓 → gates 참(한 바퀴 묵은 차단 0 · DA H2)
    w = world(tmp, mp, ft2)
    w.enable()
    switch(w, "true")   # 닫지 못하고 남는 석
    orphan(w, "r2413", holder_alive=True)
    k = w.keeper()
    two(w, k) + rnd(w, k, dt=30)
    assert kn(k).gates(k, TEAM) is None, k.lines
    os.utime(log_of(w, "r2413"), (w.t, w.t))   # 활동 재개 = jsonl 새 시각
    k.cache = {}   # 바퀴 캐시 비움(DA 재현 그대로)
    assert kn(k).gates(k, TEAM) is True, (k.state.get("noleft"), k.lines)


def c6c(tmp, mp, ft2=kw.FT2):   # ⑥c 경보 받는 곳 = harness master(그 팀 아님 · DA H3)
    w = world(tmp, mp, ft2)
    seat, team = "byz-lecture-nano-test#0", "lecture"
    k = w.keeper()
    tm(w, alive=[seat])
    kw._put(w.root / ".fable-team" / "teams" / team / "CLOSE-NEXT.enabled", "enabled\n")
    k.state["noleft"] = {team: {seat: {"files": [], "idle": 300, "why": "HELD-NOLEASE"}}}
    assert kn(k).gates(k, team) is None and t.has(k.lines, "NEXT-HOLD", team, "근거 없는 석 1"), k.lines
    sent = urgent(w, "근거 없는 석")
    assert len(sent) == 1 and sent[0].startswith("send M-harness") and team in sent[0] and seat in sent[0], t.sent(w)


def c10(tmp, mp, ft2=kw.FT2):   # ⑩ jsonl 이 세션 생성 시각 앞 = 재개 근거 0 → 기록 0 · kill 0 · UNKNOWN no-lease-resume(DA H1)
    w = world(tmp, mp, ft2)
    switch(w)
    seat = orphan(w, "r2412", age=400)
    tm(w, born={seat: w.t - 100})   # 이 세션은 100초 전 시작 · jsonl 은 400초 전 대화
    lines = two(w)
    assert t.has(lines, "UNKNOWN", TEAM, "r2412", seat, "no-lease-resume"), lines
    assert not kills(w) and resumed(w) == [] and len(urgent(w, "no-lease-resume")) == 1, (kills(w), resumed(w))


CASES = {"①": c1, "①둘째": c1b, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑥b": c6b, "⑥c": c6c, "⑦": c7,
         "⑧": c8, "⑨": c9, "⑩": c10}
MUTANTS = {
    "M1": ("keeper_endings.py", 'if att != "free":', "if False:", "②"),
    "M2": ("keeper_endings.py", "    return int(val) if val.isascii() and val.isdigit() else NOLEASE_IDLE",
           "    return 0", "①둘째"),
    "M3": ("keeper_endings.py", 'if why:\n        return k.unknown_seat(team, work, "-", seat, "no-lease-resume"',
           'if False:\n        return k.unknown_seat(team, work, "-", seat, "no-lease-resume"', "③"),
    "M4": ("keeper_endings.py", "    if not ok:   # K3 손 개설 석 = 닫지 않는다", "    if False:   # K3 손 개설 석 = 닫지 않는다", "④"),
    "M5": ("keeper_endings.py", "    if not no_lease_on(k):", "    if False:", "⑤"),
    "M6": ("keeper_next.py", "    if alive and (n := noleft(k, team, alive)):", "    if False:", "⑥"),
    "M7": ("keeper_endings.py", "    if k.halt:   # K6", "    if False:   # K6", "⑧"),
    "M8": ("keeper_endings.py", "if len(files) != 1 or born is None or os.path.getmtime(files[0]) < born:", "if len(files) != 1:", "⑩"),
    "M9": ("keeper_next.py", 'if seat in alive and (age is None or age >= int(row.get("idle") or 0)):', "if seat in alive:", "⑥b"),
    "M10": ("keeper_next.py", '    k.notify("harness", "noleft|', '    k.notify(team, "noleft|', "⑥c"),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path / name, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    pack = tmp_path / "ft2mut"
    shutil.copytree(kw.FT2, pack, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = pack / "adapters" / "pi" / rel
    body = path.read_text(encoding="utf-8")
    assert body.count(old) == 1, (name, body.count(old))
    path.write_text(body.replace(old, new, 1), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / (name + "-mut"), monkeypatch, pack)
    CASES[case](tmp_path / (name + "-ok"), monkeypatch)   # 변이마다 원본으로 같은 사례 1회 더
