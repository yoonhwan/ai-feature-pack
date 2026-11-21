"""r2073 ft2 keeper — 전 세션 정지(PENALTY_STOP) 재개 전 팀에는 새 카드를 넣지 않는다 (판례 ㊲가~카 · 변이 M62~M66).
대역 = r1812 keeper_world(임시 root·git·가짜 tmux) + 가짜 launch·record·ft-penalty.sh(호출 기록 · rc 파일이 사례를 정한다) ·
실 tmux·명부·runtime·PENALTY_STOP·설치 0 · sleep 0 · 사례 1개 70초 안. 기준판(penalty_open 없음) = ㊲가·㊲라·㊲사·㊲아·㊲자·㊲차 Red.
변이는 사본에서만 돌리고 원본으로 같은 사례를 1회 더 돌린다.
"""
import importlib.util, json, shutil, sys  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_world_r2073", str(HERE / "keeper_world_r1812.py"))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)

TEAM, OTHER, A, B, P, W1 = kw.TEAM, "planner", "r9101-a", "r9102-b", "r9201-p", "r9100-w1"
STOP = "판정 1 · 2026-11-16T02:30:00 · 시험용 전 세션 정지 표식\n"
PAUSED = "판정 1 · 2026-11-16T02:30:00 · 시험용 팀 정지 표식\n"
STOPPED = "NEXT-HOLD harness PENALTY_STOP 재개 전 — 다음 카드 0"
LAUNCH = '''#!__PY__
import json, os, sys
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
rc = int(open(me + ".rc").read()) if os.path.exists(me + ".rc") else 0
if rc == 0:
    st = os.environ["FAKE_TMUX"]; d = json.load(open(st))
    d["alive"].append("byz-%s-nano-%s#0" % (a[a.index("--team") + 1], a[a.index("--work") + 1][:40])); json.dump(d, open(st, "w"))
print(json.dumps({"result": "접수 성공" if rc == 0 else "복구 필요"}))
sys.exit(rc)
'''
RECORD = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nmkdir -p .fable-team/state/card-assign\n'
          'if [ "$3" = seat ]; then printf \'{"state": "seat", "seat": "%s"}\' "$4"; else printf \'{"state": "%s", "reason": "%s"}\' "$3" "$4"; fi'
          ' > ".fable-team/state/card-assign/$2.json"\n')
PENALTY = '#!/bin/sh\nexec __PY__ "$(dirname "$0")/penalty_stub.py" "$0" "$@"\n'   # keeper 는 `bash <판정기>` 로 부른다 = sh 껍데기 + 파이썬 몸통
STUB = '''import json, os, sys
me, a = sys.argv[1], sys.argv[2:]
open(me + ".log", "a").write(json.dumps({"argv": a, "root": os.environ.get("FT_ROOT")}) + "\\n")
spec = json.load(open(me + ".rc")) if os.path.exists(me + ".rc") else 0   # 숫자 · {"팀": 숫자|[숫자들]} = 부를 때마다 다음 값
team = a[a.index("check") + 1] if "check" in a else "-"
val = spec.get(team, spec.get("*", 0)) if isinstance(spec, dict) else spec
if isinstance(val, list):
    n = int(open(me + ".n").read()) if os.path.exists(me + ".n") else 0
    open(me + ".n", "w").write(str(n + 1))
    val = val[min(n, len(val) - 1)]
sys.exit(int(val))
'''


def nh(team, stem):
    return "byz-%s-nano-%s#0" % (team, stem[:40])


def round_all(w):
    """r1929 keeper 는 launch 를 기다리지 않는다 → 띄운 가짜 launch 가 끝날 때까지 기다린 뒤 같은 keeper 로 한 바퀴 더."""
    base = w.round

    def round(k=None):
        k, more = k or w.keeper(), True
        while more:
            k.cache.pop("launching", None)   # 여는 중 칸 = 바퀴(프로세스)마다 새로
            base(k)
            more = k.cache.pop("spawned", [])
            [p.wait(25) for p in more]
        return k.lines
    w.round = round


def marked(head):   # r2395 — 표식 두 줄(«- 배정:» · «- 대기 사유:»)이 다 없는 fixture 머리에 해제 표식 1줄
    return head if any(x.startswith(("- 배정", "- 대기 사유:")) for x in head.splitlines()) else "- 배정: 없음\n" + head


def world(tmp, mp, cards=None, cap="4", live=0, enable=True, ft2=kw.FT2):
    """대기 카드 {팀: {stem: 머리 줄}} · 빈 나노 live 개 · 가짜 판정기 기본 rc = 3(재개 전)."""
    w = kw.World(tmp, mp, ft2)
    b = tmp / "bin"
    kw._put(b / "launch.py", LAUNCH.replace("__PY__", sys.executable)), kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
    kw._put(b / "ft-penalty.sh", PENALTY.replace("__PY__", sys.executable)), (b / "ft-penalty.sh").chmod(0o755)
    kw._put(b / "penalty_stub.py", STUB)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"),
                 FT2_TEAM_NANO_MAX=cap, FT2_PENALTY_BIN=str(b / "ft-penalty.sh"),
                 GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")   # 가짜 HOME = 실 ~/.claude 문턱 읽기 0
    kw._put(w.state / "directive-roots.tsv", "".join("%s\t.\torigin/main\tdesign/%s/indices\n" % (t, t) for t in sorted(cards)))
    w.commit("byz", {"design/%s/indices/대기/%s.md" % (t, s): "# 인덱스: %s\n%s- 상태: 대기\n" % (s, marked(h))
                     for t, mine in cards.items() for s, h in mine.items()}, "main")   # r2395 — 표식 없는 fixture 머리 = 해제 표식 1줄
    kw._put(w.tm, {"alive": ["byz-%s-nano-live%d#0" % (TEAM, n) for n in range(live)], "pane": {}})
    for team in cards:
        kw._put(w.state / "ft20-switch" / (team + ".json"), "{}"), (w.root / ".fable-team" / "teams" / team / "runtime").mkdir(parents=True, exist_ok=True)
    [w.enable(t) for t in cards] if enable else None
    w.pen, w.kdir = b / "ft-penalty.sh", w.state / "ft2-keeper"
    pen_rc(w, 3)
    round_all(w)
    return w


def stop(w, yes=True):
    """전 세션 정지 표식 — real ft-penalty.sh 없이 keeper 만 본다(가짜 판정기가 rc 를 정한다)."""
    kw._put(w.state / "PENALTY_STOP", STOP) if yes else (w.state / "PENALTY_STOP").unlink()


def pen_rc(w, spec):
    kw._put(Path(str(w.pen) + ".rc"), json.dumps(spec) if not isinstance(spec, int) else str(spec))


def pen_calls(w):
    return [json.loads(x) for x in kw._lines(str(w.pen) + ".log")]


def launched(w):
    return [json.loads(x)[json.loads(x).index("--work") + 1] for x in kw._lines(str(w.tmp / "bin" / "launch.py") + ".log")]


def ledger(w, stem):
    path = w.state / "card-assign" / (stem + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def receipts(w):
    return [r for r in w.journal() if r["kind"] == "close_receipt"]


def count(w, kind, work, team=TEAM):
    return sum(r["kind"] == kind and r.get("work") == work for r in w.journal(team))


def pen_lines(k):
    return [x for x in k.lines if "PENALTY_STOP" in x]


def rounds(k):
    return len([x for x in k.lines if x.startswith("ROUND ")])


def close_work(w, work):
    w.card(work, sha=w.pack_sha(), stage="완성")
    w.work(work, done=True)


def c_ga(w, mp):        # ㊲가 파일 있음 · rc 3 · 빈 칸 · 대기 1 · 두 바퀴 → fill 0 · journal 그대로 · NEXT-HOLD 1줄
    stop(w)
    k = w.keeper()
    before = len(w.journal())
    assert w.round(k) and pen_lines(k) == [STOPPED], k.lines
    assert pen_calls(w) == [{"argv": ["check", TEAM], "root": str(w.root)}] and launched(w) == [] and len(w.journal()) == before
    n = len(k.lines)
    w.round(k)
    assert [x for x in k.lines[n:] if "PENALTY_STOP" in x] == [] and launched(w) == [] and len(w.journal()) == before, k.lines[n:]


def c_gna(w, mp):       # ㊲나 재개된 팀(rc 0) → fill 1장 · PENALTY 줄 0
    stop(w)
    pen_rc(w, 0)
    k = w.keeper()
    assert w.round(k) and "NEXT harness fill:%s -> %s %s" % (A, A, nh(TEAM, A)) in k.lines, k.lines
    assert pen_lines(k) == [] and launched(w) == [A] and ledger(w, A) == {"state": "seat", "seat": nh(TEAM, A)}


def c_gda(w, mp):       # ㊲다 파일 없음 → fill 1장 · 판정기 호출 0
    k = w.keeper()
    assert w.round(k) and launched(w) == [A] and pen_calls(w) == [], k.lines


def c_gla(w, mp):       # ㊲라 파일 있음 · rc 3 · 나노 닫기 1 → 닫기 영수 1 · 다음 카드 배정 0 · submit 0
    stop(w)
    close_work(w, W1)
    k = w.keeper()
    assert w.round(k) and len(receipts(w)) == 1 and receipts(w)[0].get("next") in (None, ""), (receipts(w), k.lines)
    assert count(w, "accept", B) == 0 and launched(w) == [] and STOPPED in k.lines, k.lines


def c_gma(w, mp):       # ㊲마 rc 3 · fill_open 에 잇는 열기 1 → reconcile 그대로(launch 1 · record seat)
    stop(w)
    w.work(A, intent=False, holder=nh(TEAM, A))   # 전달 attempt a1 만 만들고 의도 파일은 두지 않는다(열기 전 상태)
    kw._put(w.kdir / "state.json", {"fill_open": {"%s|%s" % (TEAM, A): "a1"}})
    k = w.keeper()
    assert w.round(k) and launched(w) == [A] and ledger(w, A) == {"state": "seat", "seat": nh(TEAM, A)}, k.lines
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(TEAM, A)) in k.lines


def c_gba(w, mp):       # ㊲바 rc 3 · 복구 launch 가드 길(gates 거짓) → 파일 없을 때와 같은 결과 · 판정기 호출 0
    stop(w)
    w.work(A, intent=False)
    kw._put(w.kdir / "state.json", {"fill_open": {"%s|%s" % (TEAM, A): "a1"}})
    k = w.keeper()
    assert w.round(k) and launched(w) == [] and pen_calls(w) == [], k.lines
    stop(w, False)
    n = len(k.lines)
    w.round(k)
    assert launched(w) == [] and [x for x in k.lines[n:] if "PENALTY_STOP" in x] == [] and pen_calls(w) == []


def c_gsa(w, mp):       # ㊲사 판정 불가 = 막힘 — rc 1 · 도구 없음 · 시간 초과 셋 다 fill 0 · 판정 불가 1줄
    stop(w)
    for kind in ("rc1", "missing", "timeout"):
        (w.kdir / "state.json").unlink(missing_ok=True)   # 재기동 = 기억 없음(사례마다 1줄 다시)
        [Path(str(w.pen) + x).unlink(missing_ok=True) for x in (".log", ".rc", ".n")]
        base = dict(w.env)
        w.env["FT2_PENALTY_BIN"] = str(w.tmp / "bin" / "없는-판정기.sh") if kind == "missing" else str(w.pen)
        pen_rc(w, 1) if kind == "rc1" else None
        k = w.keeper()
        if kind == "timeout":   # 판정기 7초 넘김 = rc None(하위 프로세스 시간 초과 자리)
            real = k.call
            mp.setattr(k, "call", lambda a, *x, **kv: (None, "", "timed out") if "ft-penalty" in " ".join(a) else real(a, *x, **kv))
        lines = w.round(k)
        w.env.update(base)
        assert len([x for x in lines if x.startswith("판정 불가 harness PENALTY_STOP 판독 ")]) == 1, (kind, lines)
        assert launched(w) == [] and count(w, "accept", A) == 0, (kind, lines)


def c_goa(w, mp):       # ㊲아 rc 3 → 0 → 3 = NEXT-OPEN 1줄 + fill 1장 → NEXT-HOLD 다시 1줄
    stop(w)
    pen_rc(w, {TEAM: [3, 0, 3]})
    k = w.keeper()
    assert STOPPED in w.round(k) and launched(w) == []
    assert "NEXT-OPEN harness PENALTY_STOP 풀림" in w.round(k) and launched(w) == [A]   # 띄운 뒤 record 바퀴까지 같이 돈다
    assert STOPPED in w.round(k)
    assert len([x for x in k.lines if x.startswith("NEXT-HOLD")]) == 2 and len([x for x in k.lines if x.startswith("NEXT-OPEN")]) == 1, k.lines


def c_gja(w, mp):       # ㊲자 1줄 찍은 뒤 keeper 다시 만듦(상태 파일 그대로) → 0줄 · 판독은 매 바퀴
    stop(w)
    k = w.keeper()
    assert STOPPED in w.round(k)
    k2 = w.keeper()
    assert w.round(k2) and pen_lines(k2) == [] and len(pen_calls(w)) == 2, k2.lines


def c_gea(w, mp):       # ㊲차 두 팀 한 바퀴(rc 0 · rc 3) → rc 0 팀만 fill 1장 · 판정기 호출 팀당 바퀴 1회
    stop(w)
    pen_rc(w, {TEAM: 3, OTHER: 0})
    k = w.keeper()
    assert w.round(k) and launched(w) == [P] and ledger(w, P)["state"] == "seat" and ledger(w, A) == {}, k.lines
    assert count(w, "accept", A) == 0 and count(w, "accept", P, OTHER) == 1
    calls = {}
    for x in pen_calls(w):
        calls[x["argv"][-1]] = calls.get(x["argv"][-1], 0) + 1   # 팀당 바퀴 1회 = 어느 팀도 바퀴 수보다 많이 부르지 않는다
    assert calls.get(TEAM, 0) >= 1 and calls.get(OTHER, 0) >= 1 and max(calls.values()) <= rounds(k), (calls, rounds(k))


def c_gka(w, mp):       # ㊲카 팀 PAUSED · 파일 있음 → 판정기 호출 0 · PENALTY 줄 0
    stop(w)
    kw._put(w.state / (TEAM + "-tick") / "PAUSED", PAUSED)
    k = w.keeper()
    assert w.round(k) and pen_calls(w) == [] and pen_lines(k) == [] and launched(w) == []


CASES = {"㊲가": (c_ga, {TEAM: {A: ""}}),
         "㊲나": (c_gna, {TEAM: {A: ""}}),
         "㊲다": (c_gda, {TEAM: {A: ""}}),
         "㊲라": (c_gla, {TEAM: {B: ""}}),
         "㊲마": (c_gma, {TEAM: {A: ""}}),
         "㊲바": (c_gba, {TEAM: {A: ""}}),
         "㊲사": (c_gsa, {TEAM: {A: ""}}),
         "㊲아": (c_goa, {TEAM: {A: ""}}),
         "㊲자": (c_gja, {TEAM: {A: ""}}),
         "㊲차": (c_gea, {TEAM: {A: ""}, OTHER: {P: ""}}),
         "㊲카": (c_gka, {TEAM: {A: ""}})}


def run(name, tmp, mp, ft2=kw.FT2):
    case, cards = CASES[name]
    w = world(tmp, mp, cards=cards, cap="9" if name == "㊲차" else "4", ft2=ft2)
    if name == "㊲바":   # gates 거짓 = CLOSE-NEXT 표식 없음 · 복구 launch 가드 길
        (w.root / ".fable-team" / "teams" / TEAM / "CLOSE-NEXT.enabled").unlink()
    case(w, mp)


KN = "adapters/pi/keeper_next.py"
MUTANTS = {"M62": (KN, ' for x in held if x.split("|")[0] == team}) if gates(k, team) and penalty_open(k, team) else None',
                 ' for x in held if x.split("|")[0] == team}) if gates(k, team) else None', ("㊲가",)),
           "M63": (KN, "        pick = choose(k, team) if gates(k, team) and penalty_open(k, team) else None",
                   "        pick = choose(k, team) if gates(k, team) else None", ("㊲라",)),
           "M64": (KN, 'return penalty_seen(k, team, "" if rc == 0 else "hold" if rc == 3 else "rc %s" % rc)',
                   'return penalty_seen(k, team, "hold" if rc == 3 else "")', ("㊲사",)),
           "M65": (KN, "        if pick is None and not gates(k, team):",
                   "        if pick is None and not gates(k, team) and penalty_open(k, team):", ("㊲바",)),
           "M66": (KN, '    book = k.state.setdefault("penalty_seen", {})', "    book = {}", ("㊲가", "㊲자"))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for n in cases:   # 변이판 = 그 사례가 Red
        (tmp_path / "m" / n).mkdir(parents=True)
        with pytest.raises(AssertionError):
            run(n, tmp_path / "m" / n, monkeypatch, tree)
    for n in cases:   # 원본 = 같은 사례 PASS
        (tmp_path / "w" / n).mkdir(parents=True)
        run(n, tmp_path / "w" / n, monkeypatch)
