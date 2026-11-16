"""r2109 좌석 우편함 env 이름 = FT_SEAT_MBOX_DIR (반례 ① ② ③ · 변이 M1 M2 · ④~⑨ ⑪ = 1.x tests/test_seat_mbox_name_split_r2109.sh).
① ② = dry-run argv 판독 · ③ = 실제 열기 1갈래(기존 시험의 가짜 git·tmux·pi · 가짜 tmux 가 받은 프로세스 env 를 적음) · 실 tmux·실 pi·실 우편함 0 · sleep 0 · 70초 안.
"""
import importlib.util, json, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
spec = importlib.util.spec_from_file_location("r2109_pl", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pl)
SEAT, OLD, OTHER = "FT_SEAT_MBOX_DIR", "FT_MBOX_DIR", "R2109_OTHER_KEY"
SEEN = [*pl.SEAT_ENV, SEAT, OLD, OTHER]   # 가짜 tmux 가 적는 프로세스 env 키(없는 키 = null)
MUTANTS = {"M1": ("launch_plan.py", '[("FT_SEAT_MBOX_DIR", box)]', '[("FT_MBOX_DIR", box)]'),
           "M2": ("launch.py", '"FT_MBOX_DIR", "FT_SEAT_MBOX_DIR")', '"FT_MBOX_DIR",)')}


def world(tmp, comm=True):
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    if comm:
        (root / ".fable-team" / "comm").mkdir()
    return root, fake


def cells(argv, key):
    """tmux argv 에서 `-e <key>=…` 칸의 값 목록(`-e` 바로 뒤 칸만)."""
    return [w.split("=", 1)[1] for e, w in zip(argv, argv[1:]) if e == "-e" and w.startswith(key + "=")]


def dry(root, fake, launcher):
    out, rc = pl._launch(root, fake, launcher, extra=["--dry-run"], env_extra=None)
    assert rc == 0 and out["dry_run"] is True, out
    return out


def case1(tmp, launcher=pl.LAUNCH):   # ① comm 실재 → 새 이름 칸 정확히 1 · 옛 이름 칸 0 · mbox 칸 = 새 이름 글자
    root, fake = world(tmp)
    out = dry(root, fake, launcher)
    box = str(root / ".fable-team" / "comm")
    tmux = out["argv"]["tmux"]
    assert (cells(tmux, SEAT), cells(tmux, OLD)) == ([box], []), tmux
    assert out["paths"]["mbox"] == SEAT + "=" + box, out["paths"]


def case2(tmp, launcher=pl.LAUNCH):   # ② comm 없음 → 두 이름 칸 0 · «우편함 명시 0» 글자 그대로 · 나머지 argv = ① 에서 그 1쌍만 뺀 것
    root, fake = world(tmp, comm=False)
    out = dry(root, fake, launcher)
    box = root / ".fable-team" / "comm"
    tmux = out["argv"]["tmux"]
    assert (cells(tmux, SEAT), cells(tmux, OLD)) == ([], []), tmux
    assert out["paths"]["mbox"] == "우편함 명시 0 — %s 없음" % box, out["paths"]
    box.mkdir()
    full = dry(root, fake, launcher)["argv"]
    at = full["tmux"].index(SEAT + "=" + str(box))
    assert full["tmux"][:at - 1] + full["tmux"][at + 1:] == tmux, (full["tmux"], tmux)
    assert {k: full[k] for k in ("git", "sparse", "checkout")} == {k: out["argv"][k] for k in ("git", "sparse", "checkout")}


def case3(tmp, launcher=pl.LAUNCH):   # ③ 부모 env 두 이름 → tmux 프로세스 env 에 0 · argv 칸 = 루트 기준 · 다른 부모 키 그대로 · 성공 mbox 칸 = dry-run 글자
    root, fake = world(tmp)
    want = SEAT + "=" + str(root / ".fable-team" / "comm")   # = ① 이 확인하는 dry-run mbox 칸 글자
    body = pl.FAKE.replace("__PY__", sys.executable).replace("__SHA__", pl.FAKE_SHA).replace("__SEAT__", json.dumps(SEEN))
    (fake / "tmux").write_text(body, encoding="utf-8")
    x, y = str(tmp / "부모X" / "comm"), str(tmp / "부모Y" / "comm")
    env = pl._env(fake, extra={OLD: x, SEAT: y, OTHER: "keep"})
    done = subprocess.run(pl._argv(launcher, root), env=env, capture_output=True, text=True, timeout=70)
    assert "Traceback" not in done.stderr, done.stderr
    out = json.loads(done.stdout)
    news = [r for r in pl._log(fake) if r["prog"] == "tmux" and r["sub"] == "new-session"]
    assert done.returncode == 0 and out.get("opened") is True and len(news) == 1, (out, news)
    seen = news[0]["env"]
    assert (seen[OLD], seen[SEAT], seen[OTHER]) == (None, None, "keep"), seen
    assert (cells(news[0]["argv"], SEAT), cells(news[0]["argv"], OLD)) == ([str(root / ".fable-team" / "comm")], []), news[0]["argv"]
    assert out.get("mbox") == want, (out, want)


def test_01_seat_name_cell(tmp_path):
    case1(tmp_path)


def test_02_no_comm_no_cell(tmp_path):
    case2(tmp_path)


def test_03_parent_values_cut(tmp_path):
    case3(tmp_path)


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


@pytest.mark.parametrize("name,case", [("M1", case1), ("M2", case3)])
def test_mutants(tmp_path, name, case):
    """변이 = 그 사례 빨강 · 같은 사례를 원본으로 1회 더 = 초록."""
    launcher = _mutant(tmp_path / name, name)
    with pytest.raises(AssertionError):
        case(tmp_path / (name + "-mut"), launcher)
    case(tmp_path / (name + "-orig"))
