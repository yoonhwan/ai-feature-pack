"""r1939 ft2 keeper fill — 접수 남은 일이 상한(8)이면 submit 0 · 보류·[다음 막힘] 0 · submit «용량 부족»(경합)도 같은 처리 (반례 ①~⑥ · 변이 M1~M3).
대역 = r1913 세계(임시 root·git·가짜 tmux·가짜 launch·가짜 record) + 가짜 cli project·submit · 실 tmux·명부·ft2 원장·mbox·설치 0 · sleep 0.
기준판 = ①·②·④ Red. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_fill_r1939", str(HERE / "test_keeper_fill_empty_slot_r1913.py"))
fl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fl)
kw, nx, nh, A = fl.kw, fl.nx, fl.nh, fl.A
FULL, BUSY, REFUSE = "용량 부족", {"result": "용량 부족", "reason": "남은 일 8 >= 상한 8 (접수 장부 8)"}, {"result": "접수 거부", "reason": "시험 거부"}
def keeper(w, mp, proj, submit):
    """proj = project 가 돌려줄 dict(바꾸면 다음 바퀴 반영) · submit = 비어 있지 않으면 그 dict 를 rc1 로 · calls = fill 이 부른 동사."""
    k = w.keeper()
    cli, calls = type(k).close.__globals__["keeper_next"].cli, []
    def run(argv, real=cli.run):
        calls.append(argv[0]) if argv[0] != "submit" else calls.extend(["submit", argv[argv.index("--work") + 1]])
        if argv[0] == "project":
            return dict(proj), 0 if proj.get("result") == "접수 성공" else 1
        return (dict(submit), 1) if argv[0] == "submit" and submit else real(argv)
    mp.setattr(cli, "run", run)
    return k, calls
def wait(k):
    return [x for x in k.lines if x.startswith("FILL-WAIT harness")]
def c1(w, mp):     # ① 남은 일 8/8 · 나노 8/9 → submit 0 · 보류 0 · 쪽지 0 · FILL-WAIT 1줄
    k, calls = keeper(w, mp, {"result": "접수 성공", "remaining": 8}, {})
    w.round(k)
    assert "submit" not in calls and calls.count("project") == 1, (calls, k.lines)
    assert k.state.get("fill_hold") == {} and fl.held(w) == [] and nx.launched(w) == []
    assert wait(k) == ["FILL-WAIT harness 남은 일 8/8 — fill 0 · 다음 바퀴"], k.lines
def c2(w, mp):     # ② 같은 상태 3바퀴 → FILL-WAIT 1줄 · 8→7(submit 경합 실패)→8 = 값 변화마다 1줄
    proj, busy = {"result": "접수 성공", "remaining": 8}, dict(BUSY)
    k, calls = keeper(w, mp, proj, busy)
    [w.round(k) for _ in range(3)]
    assert len(wait(k)) == 1 and "submit" not in calls, k.lines
    proj["remaining"] = 7
    w.round(k)
    proj["remaining"] = 8
    w.round(k)
    assert [x for x in wait(k) if "남은 일 8/8" in x] == ["FILL-WAIT harness 남은 일 8/8 — fill 0 · 다음 바퀴"] * 2, k.lines
def c3(w, mp):     # ③ 남은 일 7/8 → fill 지금처럼 submit → assign → deliver
    k, calls = keeper(w, mp, {"result": "접수 성공", "remaining": 7}, {})
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(A)) in w.round(k), k.lines
    assert [x for x in calls if x in ("submit", "assign", "deliver")][:3] == ["submit", "assign", "deliver"] and wait(k) == []
def c4(w, mp):     # ④ project 7 인데 submit «용량 부족»(경합) → 보류 0 · 쪽지 0 · 다음 바퀴 같은 카드 다시
    busy = dict(BUSY)
    k, calls = keeper(w, mp, {"result": "접수 성공", "remaining": 7}, busy)
    w.round(k)
    assert calls.count("submit") == 1 and k.state.get("fill_hold") == {} and fl.held(w) == [], (calls, k.lines)
    assert any(x.startswith("FILL-WAIT harness %s submit %s" % (A, FULL)) for x in k.lines), k.lines
    busy.clear()
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(A)) in w.round(k), k.lines
def c5(w, mp):     # ⑤ submit «접수 거부» → 지금처럼 보류(새 꼴 «시각|사유») + 쪽지 1 · 원장 updated 갱신 = 풀림
    k, calls = keeper(w, mp, {"result": "접수 성공", "remaining": 7}, REFUSE)
    w.round(k)
    hold = k.state["fill_hold"]
    assert list(hold) == ["harness|" + A] and str(hold["harness|" + A]).endswith("|접수 거부") and len(fl.held(w)) == 1, (hold, k.lines)
    kw._put(w.state / "card-assign" / (A + ".json"), {"state": "none", "updated": w.t + 10 ** 9})
    w.round(k)
    assert calls.count(A) == 2, (hold, calls)   # 풀림 → A 다시 submit(B 아님)
def c6(w, mp):     # ⑥ project 판독 실패 → 지금처럼 submit 시도(실 submit → 열림)
    k, calls = keeper(w, mp, {"result": "복구 필요", "reason": "시험 손상"}, {})
    assert "NEXT harness fill:%s -> %s %s" % (A, A, nh(A)) in w.round(k) and "submit" in calls and wait(k) == [], k.lines
FULLW = {"cap": "9", "live": 8}
CASES = {"①": (c1, FULLW), "②": (c2, FULLW), "③": (c3, {}), "④": (c4, {}), "⑤": (c5, {}), "⑥": (c6, {})}
def run(name, tmp, mp, ft2=kw.FT2):
    case, opts = CASES[name]
    case(fl.world(tmp, mp, ft2=ft2, **opts), mp)
KN = "adapters/pi/keeper_next.py"
MUTANTS = {"M1": ("intake_open(k, team) and choose(", "choose(", "①"),
           "M2": ('if out.get("result") == "용량 부족":', "if False:", "④"),
           "M3": ('if out.get("result") == "용량 부족":', "if rc != 0:", "⑤")}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    shutil.copytree(kw.FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    [(tmp_path / sub).mkdir() for sub in ("w1", "w2")]
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
