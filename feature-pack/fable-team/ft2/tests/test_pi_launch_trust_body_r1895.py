"""r1895 ft2 launch --approve·첫 본문 인자·도달 확인·trust 창 키 0·도달 0 재배정 (반례 ①~⑥ · ⑤′~⑤⁵ · 변이 M1~M5).
대역 = test_pi_launch 세계(가짜 git·tmux·pi) · r1813 World(실제 core·실제 launch.py·가짜 tmux·ps·세션 파일·주입 시계) ·
r1871 세계(④′ NEXT 두 바퀴). 실 tmux·명부·장부·mbox·설치·전역 trust 파일 0 · sleep 0. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, os, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent

def _load(name, alias):
    spec = importlib.util.spec_from_file_location(alias, str(HERE / name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

pl, st, nx = _load("test_pi_launch.py", "pl_r1895"), _load("test_pi_keeper_stall_r1813.py", "st_r1895"), _load("test_pi_keeper_next_card_r1871.py", "nx_r1895")
M, W, H0 = st.M, st.W, st.H0
MARK = "[발주] ft2 harness %s@a1" % W

def body(root, team, work, holder):
    return ("[발주] ft2 %s %s@a1 좌석 %s — 카드 %s origin/main:design/%s/indices/대기/%s.md 를 통째로 읽고 그대로 수행 · "
            "ft2_claim → ft2_start 부터 · 산출·막힘은 팀 master 에 mbox · 산출 = 가지 nano/<work> push + master 보고까지 · "
            "main·ops/main-base push·병합·착지·설치·심링크·가지 삭제 0(= master·h 몫) · AGENTS.md «Landing the Plane» 은 이 좌석에 적용 0"
            % (team, work, holder, os.path.abspath(str(root)), team, work))   # r1900 끝 1구

def l1(tmp, ft2=FT2):   # ① dry-run argv = pi · --approve · 역할 argv · 첫 본문 1개 인자 · ② 본문 정확 · 실제 실행 intent body_mark
    root, fake = pl._paths(tmp)   # _paths 가 표 harness 행을 쓴다
    pl._runtime(root)
    out, rc = pl._launch(root, fake, ft2 / "adapters" / "pi" / "launch.py", extra=["--dry-run"])
    tm = out["argv"]["tmux"]
    seat = str(ft2 / "adapters" / "pi" / "ft2-seat.ts")   # r1905: 좌석 도구 -e 1쌍
    assert rc == 0 and tm[17:25] == [str(fake / "pi"), "-e", seat, "--approve"] + pl.SESSION_ARGV and tm[25:] == [body(root, "harness", pl.WORK, pl.HOLDER)], tm
    assert pl._launch(root, fake, ft2 / "adapters" / "pi" / "launch.py")[1] == 0
    assert json.loads(pl._intent(root).read_text(encoding="utf-8"))["body_mark"] == "[발주] ft2 harness %s@a1" % pl.WORK

def l2(tmp, ft2=FT2):   # ② 카드 루트 표 행 없음 → launch 거절 · 바깥 호출 0
    root, fake = pl._paths(tmp)
    st._put(root / ".fable-team" / "state" / "directive-roots.tsv", "planner\t.\tmain\tx\n")
    pl._runtime(root)
    out, rc = pl._launch(root, fake, ft2 / "adapters" / "pi" / "launch.py")
    assert (out["result"], rc) == ("접수 거부", 1) and "카드 루트 표 행 없음" in out["reason"] and pl._log(fake) == [], out

def world(tmp, mp, ft2=FT2, mark=True, at=-2 * M, user=None, pane=None, step=-M, **kw):
    """r1813 World + 표 행 · intent(body_mark·at) · 세션 파일(user 줄 · None = 파일 0) · pane."""
    w = st.World(tmp, mp, ft2)   # World 가 표 harness 행을 쓴다
    w.seat(step=step, **kw)
    got = json.loads((w.runtime() / "launch" / ("%s@a1.intent" % W)).read_text(encoding="utf-8"))
    extra = dict(({"body_mark": MARK} if mark else {}), **({"at": st._stamp(st.T0 + at)} if at is not None else {}))
    st._put(w.runtime() / "launch" / ("%s@a1.intent" % W), dict(got, **extra))
    shutil.rmtree(w.sess)
    if user is not None:
        f = w.session(w.tree(), -10 if user else -16 * M)
        rows = [{"type": "message", "message": {"role": "user", "content": [{"type": "text", "text": user}]}}] if user else []
        f.write_text(f.read_text(encoding="utf-8") + "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        os.utime(f, (st.T0 - 10, st.T0 - 10) if user else (st.T0 - 16 * M, st.T0 - 16 * M))
    if pane:
        st._put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), pane={H0: pane}))
    return w

def held(lines):
    return sum("본문 도달 0" in x for x in lines)

def c3(w):   # ③ 세션에 «[발주] ft2 harness rX@a1 » user 줄 → 통과(행동 0) · body 키 1회
    lines = w.round()
    assert held(lines) == 0 and w.tmux("kill-session") == [] and list(w.k.state["body"]) == ["harness|%s@a1" % W], lines

def c4(w):   # ④·⑤′ 세션 파일 0(at+60초) → 본문 도달 0 1줄 · 깨움 0 · reassign 1(새 attempt argv --approve) · 다음 바퀴 검사 0
    assert held(w.round()) == 1 and w.tmux("send-keys") == [] and len(w.tmux("kill-session")) == 1 and w.kinds("dispatch") == 2
    new = w.tmux("new-session")
    assert len(new) == 1 and "--approve" in new[0]["a"] and new[0]["a"][-1].startswith("[발주] ft2 harness %s@a2 " % W), new
    assert held(w.round(M)) == 0 and len(w.tmux("kill-session")) == 1

def c4b(w):  # ④″ at 60초 안 → 검사 0
    assert held(w.round()) == 0 and w.tmux("kill-session") == [] and w.k.state.get("body", {}) == {}

def c5b(w):  # ⑤″ 같은 work 두 번째 도달 0 → reassign 0 · HELD + [크리티컬] 1
    w.round()
    p = w.runtime() / "launch" / ("%s@a2.intent" % W)
    st._put(p, dict(json.loads(p.read_text(encoding="utf-8")), at=st._stamp(st.T0 - 2 * M)))
    assert held(w.round(M)) == 1 and len(w.tmux("kill-session")) == 1 and w.kinds("dispatch") == 2
    assert len(w.notes()) == 1 and "[크리티컬]" in w.notes()[0] and "같은 일 두 번 멈춤" in w.notes()[0], w.notes()

def c5w(w):  # ⑤ 깨움 갈래 trust 창(옛 intent · 세션 IDLE 16분) → send-keys 0 · HELD-STALL · [크리티컬] 1
    lines = w.round()
    assert w.tmux("send-keys") == [] and any(x.startswith("HELD-STALL") and "trust 창" in x for x in lines), lines
    assert len(w.notes()) == 1 and "[크리티컬]" in w.notes()[0]

def keep(w):  # ⑤‴·⑤⁗′·⑤⁗″·⑤⁵ → kill 0 · dispatch 그대로 · new-session 0
    lines = w.round()
    assert w.tmux("kill-session") == [] and w.kinds("dispatch") == 1 and w.tmux("new-session") == [] and held(lines) == 0, lines

def c5q(w):  # ⑤⁗ 옛 intent + 세션 파일 0 + opened 15분 뒤 + idle → reassign 1
    assert held(w.round()) == 1 and len(w.tmux("kill-session")) == 1 and w.kinds("dispatch") == 2

def c6(w):   # ⑤⁵ intent 못 읽음 → 행동 0
    st._put(w.runtime() / "launch" / ("%s@a1.intent" % W), "{깨짐")
    keep(w)

def c6n(w):  # ⑥ pane 보통 → 지금처럼 Escape → 문구 → Enter
    assert ("WOKE harness %s %s" % (W, H0)) in w.round()
    keys = [x["a"][3:] for x in w.tmux("send-keys")]
    assert [k[0] for k in keys] == ["Escape", "-l", "Enter"] and keys[1][1].startswith("[깨움] ft2 keeper"), keys

def c4n(tmp, mp, ft2=FT2):   # ④′ 실 core + 가짜 launch · NEXT 두 바퀴 → 첫 바퀴 reconcile 1 · 둘째 바퀴 Stall.check 도달 검사 1
    w = nx.world(tmp, mp, nx.TWO, ft2=ft2)
    assert w.round().count("NEXT harness %s -> %s %s" % (nx.W1, nx.B, nx.nh(nx.B))) == 1
    tree = str(tmp / "wt" / nx.B)
    nx.kw._put(w.runtime() / "launch" / ("%s@a1.intent" % nx.B), {"FT2_HOLDER": nx.nh(nx.B), "state": "opened", "worktree": tree,
               "at": st._stamp(nx.kw.T0 - 61), "body_mark": "[발주] ft2 harness %s@a1" % nx.B})
    assert held(w.round()) == 1 and held(w.round()) == 0

TRUST, WAIT = "Do you trust this folder?\nTrust project folder? (y/n)\n", "0.0%/1.0M\n❯ "
CASES = {"③": dict(user=MARK + " 좌석 x"), "④": {}, "④″": dict(at=-30), "⑤": dict(pane=TRUST), "⑤″": {},
         "⑤w": dict(mark=False, at=None, user="", pane=TRUST, step=-16 * M), "⑤‴": dict(mark=False, at=-20 * M, user="[harness] master 평문 발주"),
         "⑤⁗": dict(mark=False, at=-16 * M, pane=TRUST), "⑤⁗i": dict(mark=False, at=-16 * M, pane=WAIT), "⑤⁗′": dict(mark=False, at=-14 * M),
         "⑤⁗″": dict(mark=False, at=-16 * M, user=""), "⑤⁵": {}, "⑥": dict(mark=False, user="", step=-16 * M)}
RUN = {"③": c3, "④": c4, "④″": c4b, "⑤": c4, "⑤″": c5b, "⑤w": c5w, "⑤‴": keep, "⑤⁗": c5q, "⑤⁗i": c5q, "⑤⁗′": keep, "⑤⁗″": keep,
       "⑤⁵": c6, "⑥": c6n}
MUTANTS = {"M1": ("adapters/pi/launch_plan.py", '["-e", seat_tools(), "--approve"]', '["-e", seat_tools()]', "①"),
           "M2": ("adapters/pi/keeper_stall.py", "        if self.first(", "        if False and self.first(", "④"),
           "M3": ("adapters/pi/keeper_stall.py", "if rc == 0 and TRUST in pane:", "if False:", "⑤w"),
           "M4": ("adapters/pi/keeper_stall.py", "return self.reassign(team, work, attempt, holder, tree, intent, rows) or True", "return True", "④"),
           "M5": ("adapters/pi/keeper_stall.py", 'mark = intent.get("body_mark")', 'mark = intent.get("body_mark") or "[발주] ft2"', "⑤‴")}

def run(name, tmp, mp, ft2=FT2):
    if name in ("①", "②"):
        return (l1 if name == "①" else l2)(tmp, ft2)
    if name == "④′":
        return c4n(tmp, mp, ft2)
    RUN[name](world(tmp, mp, ft2, **CASES[name]))

@pytest.mark.parametrize("name", ["①", "②", "④′"] + list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)

@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
