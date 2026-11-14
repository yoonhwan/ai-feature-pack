"""r1921 보정1 — DA HOLD R1·R2 경계(DA-r1921-impl-300386 · evidence review_cases.py 와 같은 입력).
R1 = external_wait 시한 안이면 오류 깨움도 키 0 · R2 = 같은 attempt 도달 미확인(unsure)은 정상·오류 갈래 공통 차단(두 방향).
입력 = r1921 시험 대역(r1813 World) 재사용 · 가짜 tmux noecho = r1813 R1-b 와 같은 대역 · sleep 0. 기준판(f49d7f2f) = 셋 다 Red.
"""
import importlib.util, json  # noqa: E401
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r1921_cases_for_da", str(FT2 / "tests" / "test_pi_keeper_stall_error_r1921.py"))
R = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(R)
B, KEY = R.B, "harness|%s@a1" % R.W


def _noecho(w):
    B._put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), noecho=True))


def test_r1_external_wait_blocks_error_wake(tmp_path, monkeypatch):   # R1 — scan 이유 = 시한 안 → 오류 깨움 키 0
    w = B.World(tmp_path, monkeypatch)
    R._seat(w, "503 Service Unavailable", 121)
    clock = lambda: B._stamp(B.T0 - 16 * B.M)   # noqa: E731
    assert w.LC.Lifecycle(str(w.root), "harness", clock=clock).progress(B.W, "L1", "external_wait", deadline=5).result == "접수 성공"
    lines = w.round()
    assert w.tmux("send-keys") == [] and not [x for x in lines if x.startswith("WOKE")], lines


def test_r2_normal_unsure_blocks_error_wake(tmp_path, monkeypatch):   # R2 ① 정상 깨움 도달 미확인 → 뒤 오류 121초 → 키 추가 0
    w = B.World(tmp_path, monkeypatch)
    w.seat()
    _noecho(w)
    w.round()
    assert KEY in w.k.state["unsure"] and len(w.tmux("send-keys")) == 3
    R._err(w, "503 Service Unavailable", B.T0 + 1)
    w.round(122)
    assert len(w.tmux("send-keys")) == 3 and w.k.state.get("err_woke", {}) == {}


def test_r2_error_unsure_blocks_normal_wake(tmp_path, monkeypatch):   # R2 ② 오류 깨움 도달 미확인 → 정상 턴 복귀 15분 → 키 추가 0
    w = B.World(tmp_path, monkeypatch)
    R._seat(w, "503 Service Unavailable", 121)
    _noecho(w)
    w.round()
    assert len(w.tmux("send-keys")) == 3 and w.k.state.get("err_woke", {}) == {}
    w.session(w.tree(), 1 * B.M)
    w.round(17 * B.M)
    assert len(w.tmux("send-keys")) == 3 and w.k.state["woke"] == {}
