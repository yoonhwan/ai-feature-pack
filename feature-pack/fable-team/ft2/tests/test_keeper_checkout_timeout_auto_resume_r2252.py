"""r2252 O0·O2·O3 ft2 keeper — checkout 25초 넘음(intent failed ∧ resumable checkout)은 같은 attempt 를 1회 이어 열고, 그동안 쉼을 미룬다 (반례 ⑤~⑩ ⑫ ⑫′ ⑬ · 변이 M3~M7 · ⑫′ M7 = 구현 DA HOLD 1 보정).
settle 쪽 = r2058 세계(test_launch_failed_end · 임시 root·git·가짜 tmux·launch·record·mbox · 주입 시계) 한 바퀴.
launching 쪽 = keeper_launch 모듈을 바로 부른다(가짜 keeper · 가짜 Popen · 가짜 ps 출력 · 같은 세계의 intent 파일).
실 kill 0(os.kill 0 신호 판독만) · 실 launch 0 · 네트워크 0 · sleep 0. 기준판 = ⑤ ⑥ ⑫ Red(«실패 git checkout …» · failed_end park 1).
"""
import importlib.util, json, os, shutil, time, types  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_r2252_r2058", str(HERE / "test_launch_failed_end.py"))
fe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fe)
kw, FT2, TEAM = fe.kw, fe.FT2, fe.TEAM
W, KL, KS = "r9952", "adapters/pi/keeper_launch.py", "adapters/pi/keeper_settle.py"
NH = "byz-%s-nano-%s#0" % (TEAM, W)
ALIVE = {"pid": os.getpid(), "started": time.time(), "kind": "resume"}   # 예약 pid = 지금 프로세스(시작이 started 앞 = 살아 있음)
DEAD = {"pid": os.getpid(), "started": 1.0, "kind": "resume"}   # 같은 pid · 시작이 started 보다 늦음 = 다른 프로세스(죽음)


def failed(w, age=60, resumable="checkout", resume=None, step="git checkout 1/4", reason="checkout -q timed out after 25 seconds"):
    """나노 1석(접수→배정→전달 · 세션 0 · owner 남음) + intent failed(at = 지금 - age 초) + 이어 열기 표시 · 예약(.intent.resume)."""
    fe.seat(w, W, state="failed", at=fe.stamp(w.t - age), step=step, reason=reason)
    path = w.runtime() / "launch" / ("%s@a1.intent" % W)
    body = json.loads(path.read_text(encoding="utf-8"))
    body.update({"resumable": resumable, "checkout_batches": 4} if resumable else {})
    kw._put(path, body)
    kw._put(str(path) + ".resume", resume) if resume else None
    return body


class Fake:
    """launching 이 쓰는 keeper 칸만 — root·env·cache·now·read_json·call(ps 출력 1개)·log."""
    def __init__(s, w):
        s.root, s.env, s.cache, s.lines, s.t = str(w.root), {}, {}, [], w.t
        s.ps = "S " + time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(time.time() - 100))

    def now(s):
        return s.t

    def read_json(s, path):
        try:
            with open(path, encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return {}

    def call(s, argv, timeout=None):
        return 0, s.ps, ""

    def log(s, kind, team, text=""):
        s.lines.append("%s %s %s" % (kind, team, text))


def launch(w, mp, ft2):
    """keeper_launch.launching 1회 → (반환, 띄운 argv 목록, 줄) · Popen = 가짜(argv 기록 · 자식 0)."""
    kl, spawned = kw._mod(ft2 / KL, "kl_r2252_%d" % id(w)), []
    child = types.SimpleNamespace(pid=os.getpid())
    mp.setattr(kl, "subprocess", types.SimpleNamespace(DEVNULL=-3, Popen=lambda argv, **kv: spawned.append(argv) or child))
    k = Fake(w)
    got = kl.launching(k, TEAM, W, "a1", NH, ["python3", "launch.py", "--work", W])
    return got, spawned, k.lines


def round_(w):
    lines = fe.rnd(w)
    return lines, fe.kinds(w)["parked"]


def c5(w, mp, ft2):   # ⑤ failed ∧ resumable checkout ∧ 예약 없음 → launching spawn 1(argv 끝 --resume) · True(handled 0)
    failed(w)
    got, spawned, lines = launch(w, mp, ft2)
    assert got is True and len(spawned) == 1 and spawned[0][-1] == "--resume", (got, spawned, lines)
    assert [x for x in lines if x.startswith("LAUNCHING %s %s" % (TEAM, NH)) and "이어 열기" in x], lines


def c6(w, mp, ft2):   # ⑥ ⑤ 꼴 · owner ∧ 세션 부재 · 문턱 안쪽 → settle WORKING «launch-resumable» · park 0 · UNKNOWN 0
    failed(w)
    lines, parked = round_(w)
    assert parked == 0 and fe.has(lines, "WORKING %s %s" % (TEAM, W), "launch-resumable"), lines
    assert not fe.has(lines, "UNKNOWN %s %s" % (TEAM, W)) and not w.tmux("kill-session"), lines


def c7(w, mp, ft2):   # ⑦ 예약 있음 ∧ 예약 pid 죽음 ∧ failed → settle failed_end park 1 · launching «실패 …» · spawn 0
    failed(w, resume=DEAD)
    lines, parked = round_(w)
    assert parked == 1 and fe.has(lines, "UNKNOWN %s %s" % (TEAM, W), "launch-failed"), lines
    got, spawned, _ = launch(w, mp, ft2)
    assert spawned == [] and str(got).startswith("실패 git checkout"), (got, spawned)


def c8(w, mp, ft2):   # ⑧ failed ∧ resumable 없음(git add 실패) → 기준판 같음(park 1 · spawn 0)
    failed(w, resumable=None, step="git add", reason="worktree 가 이미 있음")
    lines, parked = round_(w)
    assert parked == 1 and fe.has(lines, "UNKNOWN %s %s" % (TEAM, W), "launch-failed", "git add"), lines
    got, spawned, _ = launch(w, mp, ft2)
    assert spawned == [] and str(got).startswith("실패 git add"), (got, spawned)


def c9(w, mp, ft2):   # ⑨ ⑥ 꼴인데 intent at 부터 900초 넘음 → failed_end park 1(fill 이 못 닿을 때 상한)
    failed(w, age=1000)
    lines, parked = round_(w)
    assert parked == 1 and fe.has(lines, "UNKNOWN %s %s" % (TEAM, W), "launch-failed") and not fe.has(lines, "launch-resum"), lines


def c10(w, mp, ft2):   # ⑩ 정지 중 ⑥ 꼴 → 기준판 같음(«예정 PARKED» 1줄 · kill·park 0)
    failed(w)
    kw._put(w.state / "ALL_STOP.json", {"reason": "시험"})
    lines, parked = round_(w)
    assert parked == 0 and len(fe.has(lines, "예정 PARKED %s %s" % (TEAM, W), "launch-failed")) == 1, lines
    assert not fe.has(lines, "launch-resum") and not w.tmux("kill-session"), lines


def c12(w, mp, ft2):   # ⑫ 예약 있음 ∧ 예약 pid 살아 있음 ∧ failed(again 길) → settle WORKING «launch-resuming» · launching LAUNCH-WAIT · spawn 0
    failed(w, resume=ALIVE)
    lines, parked = round_(w)
    assert parked == 0 and fe.has(lines, "WORKING %s %s" % (TEAM, W), "launch-resuming"), lines
    assert not fe.has(lines, "UNKNOWN %s %s" % (TEAM, W)), lines
    got, spawned, out = launch(w, mp, ft2)
    assert got is True and spawned == [] and [x for x in out if x.startswith("LAUNCH-WAIT") and "이어 열기 중" in x], (got, spawned, out)


def c12b(w, mp, ft2):   # ⑫′ 구현 DA HOLD 1 — ⑫ 꼴인데 intent at 부터 900초 넘음 → 그래도 기다림(park 0 · LAUNCH-WAIT · spawn 0 · 살아 있음 갈래 = 900초 검사 0)
    failed(w, age=1000, resume=ALIVE)
    lines, parked = round_(w)
    assert parked == 0 and fe.has(lines, "WORKING %s %s" % (TEAM, W), "launch-resuming"), lines
    assert not fe.has(lines, "UNKNOWN %s %s" % (TEAM, W)), lines
    got, spawned, out = launch(w, mp, ft2)
    assert got is True and spawned == [] and [x for x in out if x.startswith("LAUNCH-WAIT") and "이어 열기 중" in x], (got, spawned, out)


def c13(w, mp, ft2):   # ⑬ 예약 없음 ∧ 900초 넘음 ∧ fill_open 잇기 ∧ gates 참 → 같은 바퀴 b2c park 1 · b2f spawn 0 · launching 도 «실패» (O0 한 판정)
    failed(w, age=1000)
    kw._put(w.state / "ft2-keeper" / "state.json", {"fill_open": {"%s|%s" % (TEAM, W): "a1"}})
    lines, parked = round_(w)
    assert parked == 1 and W not in fe.launched(w), (lines, fe.launched(w))
    got, spawned, _ = launch(w, mp, ft2)
    assert spawned == [] and str(got).startswith("실패 git checkout"), (got, spawned)


CASES = {"⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10, "⑫": c12, "⑫′": c12b, "⑬": c13}
NEEDS = {"⑬": dict(nano_max="4")}
ALIVE_ARM = '    return "resuming" if seen != "dead" else ""'
MUTANTS = {   # (고칠 파일, 고칠 글자, 새 글자, 반드시 FAIL 이어야 하는 사례) · 모두 한 판정 keeper_launch.resume_state 안
    "M3": (KL, "    seen = reserved(k, base)\n", "    seen = None\n", ("⑦",)),   # .intent.resume 검사 뺌
    "M4": (KL, '    if got.get("state") != "failed" or got.get("resumable") != "checkout":', '    if got.get("state") != "failed":', ("⑧",)),   # resumable 조건 뺌
    "M5": (KL, ALIVE_ARM, '    return ""', ("⑫",)),   # 예약 pid 살아 있음 검사 뺌
    "M6": (KL, '        return "resumable" if fresh(k, got) else ""', '        return "resumable"', ("⑬",)),   # 900초 검사 뺌
    "M7": (KL, ALIVE_ARM, '    return "resuming" if seen != "dead" and fresh(k, got) else ""', ("⑫′",)),   # 구현 DA HOLD 1 — 살아 있음 갈래에 900초 붙임
}


def run(name, tmp, mp, ft2=FT2):
    CASES[name](fe.world(tmp, mp, ft2=ft2, **NEEDS.get(name, {})), mp, ft2)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises(AssertionError):
            run(case, bad, monkeypatch, ft2=tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = 반대 결과 대조
