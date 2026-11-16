"""r2050 좌석 열기 env 에 FT_MBOX_DIR=<FT2_ROOT>/.fable-team/comm 1칸 (반례 ①③④⑥⑦ · 변이 M1~M4 · ⑤ = 기존 시험 3벌 그대로).
① ③ ④ = dry-run argv 판독 · ⑥ ⑦ = 실제 열기 1갈래(기존 시험의 가짜 git·tmux·pi · 가짜 tmux 가 받은 프로세스 env 를 적음) · 실 tmux·실 pi 0 ·
② 래퍼 고정은 이 파일 밖(카드 보정 1 · 우편함 래퍼 쪽 tests) · sleep 0 · 70초 안.
"""
import importlib.util, json, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
spec = importlib.util.spec_from_file_location("r2050_pl", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pl)
KEY = "FT_MBOX_DIR"
MUTANTS = {"M1": ("launch_plan.py", " + mbox for word", " for word"), "M2": ("launch_plan.py", "if os.path.isdir(box) else []", "if True else []"),
           "M3": ("launch.py", ", mbox=plan[\"mbox\"]", ""), "M4": ("launch.py", 'if k != "FT_MBOX_DIR"', "if True")}
SEEN = [*pl.SEAT_ENV, KEY, "PATH", "HOME"]   # 가짜 tmux 가 적는 프로세스 env 키(없는 키 = null)


def world(tmp, comm=True):
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    if comm:
        (root / ".fable-team" / "comm").mkdir()
    return root, fake


def dry(root, fake, launcher, parent=None):
    out, rc = pl._launch(root, fake, launcher, extra=["--dry-run"], env_extra={KEY: parent} if parent else None)
    assert rc == 0 and out["dry_run"] is True, out
    return out


def boxes(argv):
    """tmux argv 의 `-e FT_MBOX_DIR=…` 값 목록(`-e` 바로 뒤 칸만)."""
    return [w.split("=", 1)[1] for e, w in zip(argv, argv[1:]) if e == "-e" and w.startswith(KEY + "=")]


def case1(tmp, launcher=pl.LAUNCH):   # ① comm 있음 → 정확히 1개 = <루트>/.fable-team/comm
    root, fake = world(tmp)
    out = dry(root, fake, launcher)
    assert boxes(out["argv"]["tmux"]) == [str(root / ".fable-team" / "comm")], out["argv"]["tmux"]


def case3(tmp, launcher=pl.LAUNCH):   # ③ comm 없음 → 칸 0 · «우편함 명시 0» 1줄 · 나머지 argv = comm 있을 때에서 그 1쌍만 뺀 것
    root, fake = world(tmp, comm=False)
    out = dry(root, fake, launcher)
    box = root / ".fable-team" / "comm"
    assert boxes(out["argv"]["tmux"]) == [] and out["argv"]["tmux"].count("-e") == 6, out["argv"]["tmux"]
    assert out["paths"]["mbox"] == "우편함 명시 0 — %s 없음" % box, out["paths"]
    box.mkdir()
    full = dry(root, fake, launcher)["argv"]
    at = full["tmux"].index(KEY + "=" + str(box))
    assert full["tmux"][:at - 1] + full["tmux"][at + 1:] == out["argv"]["tmux"], (full["tmux"], out["argv"]["tmux"])
    assert {k: full[k] for k in ("git", "sparse", "checkout")} == {k: out["argv"][k] for k in ("git", "sparse", "checkout")}


def case4(tmp, launcher=pl.LAUNCH):   # ④ 부모 env 의 남의 팀 값 → 좌석 칸 = 루트 값 1개 · comm 없으면 0개
    other = str(tmp / "남의팀" / "comm")
    root, fake = world(tmp / "a")
    assert boxes(dry(root, fake, launcher, other)["argv"]["tmux"]) == [str(root / ".fable-team" / "comm")]
    root, fake = world(tmp / "b", comm=False)
    assert boxes(dry(root, fake, launcher, other)["argv"]["tmux"]) == []


def launch(root, fake, launcher, parent=None):
    """실제 열기 1회 — 부모 env 의 FT_MBOX_DIR = parent(None = 키 없음) · 가짜 tmux 는 SEEN 키를 적는다 → (결과, rc, 넘긴 env, new-session 줄)."""
    body = pl.FAKE.replace("__PY__", sys.executable).replace("__SHA__", pl.FAKE_SHA).replace("__SEAT__", json.dumps(SEEN))
    (fake / "tmux").write_text(body, encoding="utf-8")
    env = {k: v for k, v in pl._env(fake).items() if k != KEY}
    env.update({KEY: parent} if parent else {})
    done = subprocess.run(pl._argv(launcher, root), env=env, capture_output=True, text=True, timeout=70)
    assert "Traceback" not in done.stderr, done.stderr
    news = [x for x in pl._log(fake) if x["prog"] == "tmux" and x["sub"] == "new-session"]
    return json.loads(done.stdout), done.returncode, env, news


def case6(tmp, launcher=pl.LAUNCH):   # ⑥ 실제 열기 성공 결과 mbox 칸 = dry-run 칸과 같은 글자(없음·있음 두 벌)
    root, fake = world(tmp / "a", comm=False)
    out, rc, _, _ = launch(root, fake, launcher)
    assert (rc, out.get("opened"), out.get("mbox")) == (0, True, "우편함 명시 0 — %s 없음" % (root / ".fable-team" / "comm")), out
    root, fake = world(tmp / "b")
    out, rc, _, _ = launch(root, fake, launcher)
    assert (rc, out.get("opened"), out.get("mbox")) == (0, True, "FT_MBOX_DIR=%s" % (root / ".fable-team" / "comm")), out


def case7(tmp, launcher=pl.LAUNCH):   # ⑦ 부모 값 → tmux 프로세스 env 에 키 없음 · argv 칸 = comm 없음 0 · 있음 루트 값 1 · PATH·HOME 그대로
    other = str(tmp / "남의팀" / "comm")
    for name, comm in (("a", False), ("b", True)):
        root, fake = world(tmp / name, comm=comm)
        out, rc, env, news = launch(root, fake, launcher, other)
        assert rc == 0 and out.get("opened") is True and len(news) == 1, (out, news)
        seen = news[0]["env"]
        assert seen[KEY] is None, seen
        assert boxes(news[0]["argv"]) == ([str(root / ".fable-team" / "comm")] if comm else []), news[0]["argv"]
        assert (seen["PATH"], seen["HOME"]) == (env["PATH"], env.get("HOME")), seen


def test_01_explicit_box(tmp_path):
    case1(tmp_path)


def test_03_no_comm_no_box(tmp_path):
    case3(tmp_path)


def test_04_parent_value_ignored(tmp_path):
    case4(tmp_path)


def test_06_open_result_mbox(tmp_path):
    case6(tmp_path)


def test_07_tmux_env_drops_parent(tmp_path):
    case7(tmp_path)


def _mutant(tmp, name):
    filename, needle, replacement = MUTANTS[name]
    dest = tmp / "mutant" / "feature-pack" / "fable-team" / "ft2"
    shutil.copytree(FT2, dest, ignore=shutil.ignore_patterns("__pycache__"))
    target = dest / "adapters" / "pi" / filename
    text = target.read_text(encoding="utf-8")
    if text.count(needle) != 1:
        raise RuntimeError("%s 치환 0 — needle 불일치" % name)
    target.write_text(text.replace(needle, replacement), encoding="utf-8")
    return dest / "adapters" / "pi" / "launch.py"


@pytest.mark.parametrize("name,cases", [("M1", (case1,)), ("M2", (case3,)), ("M3", (case6,)), ("M4", (case7,))])
def test_mutants(tmp_path, name, cases):
    """변이 = 그 사례 빨강 · 같은 사례를 원본으로 1회 더 = 초록."""
    launcher = _mutant(tmp_path / name, name)
    for i, case in enumerate(cases):
        with pytest.raises(AssertionError):
            case(tmp_path / ("%s-%d" % (name, i)), launcher)
        case(tmp_path / ("%s-%d-orig" % (name, i)))
