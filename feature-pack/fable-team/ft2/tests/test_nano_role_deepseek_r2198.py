"""r2198 keeper 가 여는 나노 = nano 역할 · OpenGateway deepseek (카드 반례 ②~⑦ · 변이 M1~M3).
대역 = r1871 세계(임시 root·git·가짜 tmux·가짜 launch·가짜 record) · ④⑤ 는 그 argv 로 «실제» launch.py --dry-run(쓰기 0).
실 pi·tmux·명부·ft2 원장·mbox·네트워크·설치 0 · sleep 0. 기준판(--role session · nano 행 없음) = ②③④ Red.
변이는 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조).
"""
import importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2198", str(HERE / "test_pi_keeper_next_card_r1871.py"))
nx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nx)
kw, B, W1 = nx.kw, nx.B, nx.W1
KN = "adapters/pi/keeper_next.py"
TSV = "contracts/models/role-defaults.tsv"
DS = "opengateway/deepseek/deepseek-v4.1-flash-ultrafast"
OPUS = "claude-opus-5-5"
NANO_ROW = "nano\t%s\tmedium\n" % DS
BASE = {"session": (OPUS, "medium"), "master": (OPUS, "high"), None: (OPUS, "medium")}   # ⑤ 기준판 값


def env_of(w=None):
    src = w.env if w else os.environ
    return {k: v for k, v in src.items() if k != "FT2_MODELS_DIR"}


def keeper_argv(tmp, mp, ft2=kw.FT2):
    """② keeper reconcile 이 가짜 launch 에 넘긴 argv 1줄 + 세계."""
    w = nx.world(tmp, mp, nx.TWO, ft2=ft2)
    assert "NEXT harness %s -> %s %s" % (W1, B, nx.nh(B)) in w.round()
    rows = nx.log(w, "launch.py")
    assert len(rows) == 1, rows
    return w, json.loads(rows[0])


def dry(w, argv, ft2=kw.FT2):
    done = subprocess.run([sys.executable, str(ft2 / "adapters" / "pi" / "launch.py"), *argv, "--dry-run"],
                          env=env_of(w), capture_output=True, text=True, timeout=25)
    return done.returncode, (json.loads(done.stdout) if done.stdout.strip().startswith("{") else done.stdout + done.stderr)


def with_role(argv, role):
    i = argv.index("--role")
    rest = argv[:i] + argv[i + 2:]
    return rest + ["--role", role] if role else rest


def case_keeper(tmp, mp, ft2=kw.FT2):
    """② role nano · ④ dry-run 접수 · deepseek · medium · 런타임 바이트 그대로 · ⑦ 이름·원장·protected_ok."""
    w, argv = keeper_argv(tmp, mp, ft2)
    assert argv[argv.index("--role") + 1] == "nano", argv
    before = {p: p.read_bytes() for p in w.runtime().rglob("*") if p.is_file()}
    rc, out = dry(w, argv, ft2)
    assert (rc, *map(out.get, ("result", "role", "model", "effort"))) == (0, "접수 성공", "nano", DS, "medium"), (rc, out)
    assert {p: p.read_bytes() for p in w.runtime().rglob("*") if p.is_file()} == before
    assert out["holder"] == nx.nh(B) == "byz-harness-nano-%s#0" % B
    assert nx.ledger(w, B) == {"state": "seat", "seat": nx.nh(B)}
    assert w.keeper().protected_ok("harness", B, out["attempt"], out["holder"], out["holder"]) is True


def case_models(ft2=kw.FT2):
    """③ models.py role nano → argv 1줄."""
    done = subprocess.run([sys.executable, str(ft2 / "tools" / "models.py"), "role", "nano"],
                          env=env_of(), capture_output=True, text=True, timeout=25)
    lines = done.stdout.strip().splitlines()
    assert (done.returncode, len(lines)) == (0, 1), (done.returncode, done.stdout, done.stderr)
    assert json.loads(lines[0])["argv"] == ["--model", DS, "--thinking", "medium"]


def case_others(tmp, mp, ft2=kw.FT2):
    """⑤ session · master · 역할 없음 → 기준판과 같은 model · effort."""
    w, argv = keeper_argv(tmp, mp, kw.FT2)
    for role, want in BASE.items():
        rc, out = dry(w, with_role(argv, role), ft2)
        assert (rc, out.get("role"), out.get("model"), out.get("effort")) == (0, role or "session", *want), (role, rc, out)


def test_keeper_opens_nano_deepseek(tmp_path, monkeypatch):
    case_keeper(tmp_path, monkeypatch)


def test_models_role_nano():
    case_models()


def test_other_roles_unchanged(tmp_path, monkeypatch):
    case_others(tmp_path, monkeypatch)


class FakeK:
    def __init__(self, args):
        self.env, self.tmux, self.args = {}, "tmux", args

    def call(self, argv):
        return (0, "4242\n", "") if argv[0] == "tmux" else (0, self.args, "")


@pytest.mark.parametrize("model,want", [(OPUS, "session"), (DS, "nano"), (OPUS + "[1m]", "session")])
def test_stall_role_exactly_one(model, want, monkeypatch):
    """⑥ 옛 나노 argv (모델 · medium) → 표 행 «정확히 1개»."""
    monkeypatch.delenv("FT2_MODELS_DIR", raising=False)
    spec = importlib.util.spec_from_file_location("ks_r2198", str(kw.FT2 / "adapters" / "pi" / "keeper_stall.py"))
    ks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ks)
    st = ks.Stall(FakeK("node /x/pi --model %s --thinking medium" % model))
    assert st.argv_role("byz-harness-nano-x#0") == (want, "")


def mutant(tmp, edit):
    tree = tmp / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path, old, new = edit
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (path, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    return tree


def test_mutant_m1_keeper_session(tmp_path, monkeypatch):
    """M1 keeper «nano» → «session» → ② FAIL · ④(그 argv 로는 opus) · 원본 1회 더 = PASS."""
    tree = mutant(tmp_path, (KN, '"--role", "nano"', '"--role", "session"'))
    for sub in ("w1", "w1b", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError) as bad:
        case_keeper(tmp_path / "w1", monkeypatch, tree)
    assert "'session'" in str(bad.value)
    w, argv = keeper_argv(tmp_path / "w1b", monkeypatch, tree)
    rc, out = dry(w, argv, tree)
    assert (rc, out.get("role"), out.get("model")) == (0, "session", OPUS)   # ④ FAIL 쪽 = deepseek 아님
    case_keeper(tmp_path / "w2", monkeypatch)


def test_mutant_m2_no_nano_row(tmp_path, monkeypatch):
    """M2 nano 행 뺌 → ③ FAIL · ④ rc2 «행 없음» · 원본 1회 더 = PASS."""
    tree = mutant(tmp_path, (TSV, NANO_ROW, ""))
    with pytest.raises(AssertionError):
        case_models(tree)
    (tmp_path / "w1").mkdir(), (tmp_path / "w2").mkdir()
    w, argv = keeper_argv(tmp_path / "w1", monkeypatch, tree)
    rc, out = dry(w, argv, tree)
    assert rc == 2 and "역할 nano — role-defaults.tsv 행 없음" in json.dumps(out, ensure_ascii=False), (rc, out)
    case_models()
    case_keeper(tmp_path / "w2", monkeypatch)


def test_mutant_m3_session_deepseek(tmp_path, monkeypatch):
    """M3 session 행 모델 = deepseek → ⑤ FAIL · 원본 1회 더 = PASS."""
    tree = mutant(tmp_path, (TSV, "session\t%s\tmedium" % OPUS, "session\t%s\tmedium" % DS))
    (tmp_path / "w1").mkdir(), (tmp_path / "w2").mkdir()
    with pytest.raises(AssertionError) as bad:
        case_others(tmp_path / "w1", monkeypatch, tree)
    assert DS in str(bad.value)
    case_others(tmp_path / "w2", monkeypatch)
