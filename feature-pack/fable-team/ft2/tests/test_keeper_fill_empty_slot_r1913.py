"""r1913 ft2 keeper 빈 나노 칸 채우기 — 닫힘 없는 바퀴에도 gates() 통과면 팀마다 1장 연다 (반례 ①~⑥·③b · 변이 M1~M7).
대역 = r1871 세계(임시 root·git·가짜 tmux·가짜 record) · 가짜 launch 는 «실제» launch.seat() 배정·전달 판정을 거친다(무배정·미전달 = rc1) · 실 tmux·명부·ft2 원장·mbox·설치 0 · sleep 0. 기준판(fill 없음) = ①·③·③b·④ Red. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, shutil, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1913", str(HERE / "test_pi_keeper_next_card_r1871.py"))
nx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nx)
kw, nh, A, B, C = nx.kw, nx.nh, "r9001-a", "r9002-b", "r9003-c"
LAUNCH = '''import importlib.util, json, os, sys
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
spec = importlib.util.spec_from_file_location("real_launch", os.environ["FAKE_FT2"] + "/adapters/pi/launch.py")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
holder, attempt, why = mod.seat(a[a.index("--root") + 1], a[a.index("--team") + 1], a[a.index("--work") + 1])
if holder is None: print(why); sys.exit(1)
rc = int(open(me + ".rc").read()) if os.path.exists(me + ".rc") else 0
if rc == 0:
    st = os.environ["FAKE_TMUX"]; d = json.load(open(st)); d["alive"].append(holder); json.dump(d, open(st, "w"))
print(json.dumps({"result": "접수 성공" if rc == 0 else "복구 필요"}))   # r1929 결과 1줄(띄우기 로그)
sys.exit(rc)
'''
RECORD = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\n[ -f "$0.rc" ] && exit "$(cat "$0.rc")"\nmkdir -p .fable-team/state/card-assign\n'
          'if [ "$3" = seat ]; then printf \'{"state": "seat", "seat": "%s"}\' "$4"; else printf \'{"state": "%s", "reason": "%s"}\' "$3" "$4"; fi'
          ' > ".fable-team/state/card-assign/$2.json"\n')
def world(tmp, mp, cap="4", live=2, closing=False, enable=True, ft2=kw.FT2):
    """대기 카드 A·B·C · 나노 live 개(ft2 일 없음) · 닫힘 0(closing = r1871 W1 1장 닫힘)."""
    w = kw.World(tmp, mp, ft2)
    b, kill = tmp / "bin", 'if a[0] == "kill-session"'
    kw._put(b / "tmux", kw.TMUX.replace("__PY__", sys.executable).replace(kill, nx.LS + kill, 1))
    kw._put(b / "launch.py", LAUNCH), kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
    w.env.update(FT2_KEEPER_LAUNCH=str(b / "launch.py"), FT2_CARD_ASSIGN_BIN=str(b / "record"), HOME=str(tmp / "home"),
                 FT2_TEAM_NANO_MAX=cap, FAKE_FT2=str(kw.FT2), GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.quotepath", GIT_CONFIG_VALUE_0="false")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n")
    w.commit("byz", {"design/harness/indices/대기/%s.md" % s: "# 인덱스: %s\n- 상태: 대기\n" % s for s in (A, B, C)}, "main")
    kw._put(w.tm, {"alive": ["byz-harness-nano-live%d#0" % n for n in range(live)], "pane": {}})
    kw._put(w.state / "ft20-switch" / "harness.json", "{}"), w.runtime().mkdir(parents=True, exist_ok=True)
    w.enable() if enable else None
    nx.close(w, nx.W1) if closing else None
    return nx.settle(w)
def keeper(w, mp, fail=None):
    """fail = (동사, stem) → 그 cli 호출을 «접수 거부» 로 돌려준다 · calls = fill 이 부른 (동사, work)."""
    k = w.keeper()
    cli, calls = type(k).close.__globals__["keeper_next"].cli, []
    def run(argv, real=cli.run):
        work = argv[argv.index("--work") + 1] if "--work" in argv else None
        calls.append((argv[0], work))
        return ({"result": "접수 거부", "reason": "시험 거부"}, 1) if fail == (argv[0], work) else real(argv)
    mp.setattr(cli, "run", run)
    return k, calls
def c1(w, mp):     # ① live 2 / 4 → 바퀴 1 A · 바퀴 2 B · 바퀴 3 NEXT-HOLD 열기 0
    k, _ = keeper(w, mp)
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(A)) in w.round(k), k.lines
    assert [nx.count(w, x, A) for x in ("accept", "dispatch", "deliver")] == [1, 1, 1] and nx.ledger(w, A) == {"state": "seat", "seat": nh(A)} and nh(A) in json.loads(w.tm.read_text())["alive"]
    assert w.round(k) and nx.launched(w) == [A, B] and nx.ledger(w, B)["seat"] == nh(B)
    assert any(x.startswith("NEXT-HOLD harness 나노 4 / 상한 4") for x in w.round(k)) and nx.launched(w) == [A, B]
def c2(w, mp):     # ② live == 상한 → submit·assign·deliver·launch 0
    k, calls = keeper(w, mp)
    assert any(x.startswith("NEXT-HOLD harness 나노 2 / 상한 2") for x in w.round(k))
    assert calls == [] and nx.launched(w) == [] and nx.count(w, "accept", A) == 0
def c3(w, mp):     # ③ 바퀴 1 assign 거부 → 원장 쓰기 0 · fill_hold 1 · 알림 1 → 바퀴 2 A 재호출 0 · B 진행 · 알림 0 → 바퀴 3 원장 updated 갱신 = A 다시 1
    k, calls = keeper(w, mp, ("assign", A))
    assert any(x.startswith("HELD-NEXT harness fill %s assign rc 1" % A) for x in w.round(k)), k.lines
    assert nx.log(w, "record") == [] and len(held(w)) == 1
    lines = w.round(k)
    assert [c for c in calls if c[1] == A] == [("submit", A), ("assign", A)] and list(k.state["fill_hold"]) == ["harness|" + A]
    assert "NEXT harness fill:%s -> %s %s" % (B, B, nh(B)) in lines and nx.launched(w) == [B] and len(held(w)) == 1
    kw._put(w.state / "card-assign" / (A + ".json"), {"state": "none", "updated": w.t + 1}) or w.round(k)
    assert [c for c in calls if c[1] == A] == [("submit", A), ("assign", A)] * 2
def held(w):
    return [x for x in kw._lines(str(w.mbox) + ".log") if "[다음 막힘]" in x and A in x]
def c3b(w, mp):    # ③b assign·deliver OK 뒤 launch 실패 → 바퀴 2 A 재선택 0(owner) · 두 세션 0
    kw._put(w.tmp / "bin" / "launch.py.rc", "2")
    k, _ = keeper(w, mp)
    assert any(x.startswith("HELD-NEXT harness fill:%s -> %s" % (A, A)) and "복구 필요" in x for x in w.round(k)), k.lines
    (w.tmp / "bin" / "launch.py.rc").unlink() or w.round(k)
    assert nx.launched(w) == [A, B] and nx.count(w, "dispatch", A) == 1 and nh(A) not in json.loads(w.tm.read_text())["alive"]
def c4(w, mp):     # ④ 같은 바퀴 닫힘 1 + 빈 칸 → close A · fill B · 같은 stem 두 번 0
    lines = w.round()
    assert "NEXT harness %s -> %s %s" % (nx.W1, A, nh(A)) in lines and "NEXT harness fill:%s -> %s %s" % (B, B, nh(B)) in lines, lines
    assert nx.launched(w) == [A, B] and nx.count(w, "accept", A) == nx.count(w, "accept", B) == 1
def c5(w, mp):     # ⑤ gates 거짓(표식 없음·PAUSED) → fill 0
    k, calls = keeper(w, mp)
    assert w.round(k) and calls == [] and nx.launched(w) == []
PAUSED = "판정 1 · 2026-11-14T09:00:00 · 시험용 팀 정지 표식\n"
CASES = {"①": (c1, {}), "②": (c2, {"cap": "2"}), "③": (c3, {}), "③b": (c3b, {}),
         "④": (c4, {"cap": "9", "live": 0, "closing": True}), "⑤": (c5, {"enable": False}), "⑤p": (c5, {"pre": lambda w: kw._put(w.state / "harness-tick" / "PAUSED", PAUSED)})}
def run(name, tmp, mp, ft2=kw.FT2):
    case, opts = CASES[name]
    w = world(tmp, mp, ft2=ft2, **{x: v for x, v in opts.items() if x != "pre"})
    opts.get("pre", lambda _: None)(w)
    case(w, mp)
KN, KP = "adapters/pi/keeper_next.py", "adapters/pi/keeper.py"
MUTANTS = {"M1": (KP, "            self.timed(\"b2\", closing.keeper_next.fill, self, team)\n", "            pass\n", "①"),
           "M2": (KN, "== team}) if gates(k, team) else None", "== team})", "②"),
           "M3": (KN, '            ("assign", ["--holder", nh, "--evidence", ",".join(dispatch.Dispatch.REQUIRED_EVIDENCE)], "\\0"),\n', "", "①"),
           "M4": (KN, '("deliver", ["--mode", "intent"], "전달 의도 없음")):', "):", "①"),
           "M5": (KN, '            held["%s|%s" % (team, stem)] = k.now()', "            pass  #", "③"),
           "M6": (KN, [("choose(k, team, {x.split(\"|\", 1)[1] for x in held if x.split(\"|\")[0] == team})", "choose(k, team)"),
                       ("    if not pick:\n", '    if not pick or "%s|%s" % (team, pick[0]) in held:\n')], None, "③"),
           "M7": (KN, "k.now()   # 보류 시각", 'k.now(); k.call(["bash", k.env["FT2_CARD_ASSIGN_BIN"], "record", stem, "waiting", "사람"])   # 보류 시각', "③")}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    pairs = old if isinstance(old, list) else [(old, new)]
    shutil.copytree(kw.FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / rel).write_text(text, encoding="utf-8")
    [(tmp_path / sub).mkdir() for sub in ("w1", "w2")]
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
