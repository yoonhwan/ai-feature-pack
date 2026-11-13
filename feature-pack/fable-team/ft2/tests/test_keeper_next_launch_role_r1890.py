"""r1890 keeper 다음 카드 launch 역할 = session — 표(role-defaults.tsv)에 있는 기본 세션 역할로 연다 (반례 ①~③ · 변이 M1).
대역 = r1871 세계(임시 root·git·가짜 tmux·가짜 launch·가짜 record) · ② 는 그 argv 그대로 «실제» launch.py --dry-run(쓰기 0).
실 tmux·명부·ft2 원장·mbox·설치 0 · sleep 0. 기준판(--role nano) = ② Red. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r1890", str(HERE / "test_pi_keeper_next_card_r1871.py"))
nx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nx)
kw, B, W1 = nx.kw, nx.B, nx.W1
KN = "adapters/pi/keeper_next.py"


def argv_of(w):
    """가짜 launch 가 기록한 argv 1줄(keeper reconcile 이 넘긴 그대로)."""
    rows = nx.log(w, "launch.py")
    assert len(rows) == 1, rows
    return json.loads(rows[0])


def run(tmp, mp, ft2=kw.FT2):
    w = nx.world(tmp, mp, nx.TWO, ft2=ft2)
    assert "NEXT harness %s -> %s %s" % (W1, B, nx.nh(B)) in w.round()
    argv = argv_of(w)
    # ② 같은 argv 로 실제 launch.py --dry-run → 접수 성공 · opus · medium · rc0 · 런타임 바이트 그대로
    before = {p: p.read_bytes() for p in w.runtime().rglob("*") if p.is_file()}
    env = {k: v for k, v in w.env.items() if k != "FT2_MODELS_DIR"}
    done = subprocess.run([sys.executable, str(ft2 / "adapters" / "pi" / "launch.py"), *argv, "--dry-run"],
                          env=env, capture_output=True, text=True, timeout=25)
    out = json.loads(done.stdout)
    assert (done.returncode, *map(out.get, ("result", "role", "model", "effort"))) == \
        (0, "접수 성공", "session", "claude-opus-5-5", "medium"), (done.returncode, out)
    assert {p: p.read_bytes() for p in w.runtime().rglob("*") if p.is_file()} == before
    # ① reconcile 이 launch 에 넘긴 role = session
    assert argv[argv.index("--role") + 1] == "session", argv
    # ③ 좌석 이름 = byz-<팀>-nano-<stem>#0 그대로 · keeper_close protected_ok(B5) 통과
    assert out["holder"] == nx.nh(B) == "byz-harness-nano-%s#0" % B
    assert nx.ledger(w, B) == {"state": "seat", "seat": nx.nh(B)}
    k = w.keeper()
    assert k.protected_ok("harness", B, out["attempt"], out["holder"], out["holder"]) is True


def test_launch_role_session(tmp_path, monkeypatch):
    run(tmp_path, monkeypatch)


def test_mutant_m1_role_nano(tmp_path, monkeypatch):
    """M1 role 을 nano 로 되돌림 → ② FAIL(실제 launch rc2 «역할 nano — role-defaults.tsv 행 없음»)."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    old = '"--role", "session"'
    assert text.count(old) == 1
    (tree / KN).write_text(text.replace(old, '"--role", "nano"'), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError) as bad:
        run(tmp_path / "w1", monkeypatch, tree)
    assert "(2, " in str(bad.value) and "역할 nano — role-defaults.tsv 행 없음" in str(bad.value)
    run(tmp_path / "w2", monkeypatch)   # 원본으로 1회 더 = PASS
