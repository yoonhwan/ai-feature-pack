"""r2050 좌석 열기 env 에 FT_MBOX_DIR=<FT2_ROOT>/.fable-team/comm 1칸 (반례 ①~④ · 변이 M1~M2 · ⑤ = 기존 시험 3벌 그대로).
dry-run argv 판독만(실 tmux·실 pi 0) · ② 만 스킬 ft-mbox.py 사본을 팩 꼴 워크트리 cwd 에서 send(임시 리포 · 실 우편함 0) · sleep 0 · 70초 안.
"""
import importlib.util, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent
SKILL_MBOX = FT2.parent / "legacy" / "1.x" / "skill" / "scripts" / "ft-mbox.py"
spec = importlib.util.spec_from_file_location("r2050_pl", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pl)
KEY = "FT_MBOX_DIR"
MUTANTS = {"M1": (" + mbox for word", " for word"), "M2": ("if os.path.isdir(box) else []", "if True else []")}


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


def case2(tmp, launcher=pl.LAUNCH):   # ② ① 의 env 로 스킬 래퍼 사본 send → 루트 comm 1줄 · 팩 공용 루트 comm 0줄
    root, fake = world(tmp)            # ① 단언 없이 argv 만 받는다(② 자체 결과로 빨강·초록이 갈린다)
    out = dry(root, fake, launcher)
    pack, wt, tool = tmp / "pack", tmp / "pack-wt", tmp / "tool"
    git = lambda *a: subprocess.run(["git", "-C", str(pack)] + list(a), capture_output=True, text=True, timeout=25, check=True)  # noqa: E731
    (pack / ".fable-team" / "comm").mkdir(parents=True)
    (pack / "f").write_text("1\n", encoding="utf-8")
    git("init", "-q"), git("add", "f"), git("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i")
    git("worktree", "add", "-q", "--detach", str(wt))
    tool.mkdir()
    shutil.copy(SKILL_MBOX, tool / "ft-mbox.py")
    env = {k: v for k, v in os.environ.items() if k != KEY}
    env.update({KEY: v for v in boxes(out["argv"]["tmux"])})
    done = subprocess.run([sys.executable, str(tool / "ft-mbox.py"), "send", "byz-x-da", "byz-x-nano", "r2050 시험", "--force"],
                          cwd=str(wt), env=env, capture_output=True, text=True, timeout=25)
    assert done.returncode == 0, done.stdout + done.stderr
    lines = lambda d: (d / "mailbox.jsonl").read_text(encoding="utf-8").splitlines() if (d / "mailbox.jsonl").exists() else []  # noqa: E731
    assert (len(lines(root / ".fable-team" / "comm")), len(lines(pack / ".fable-team" / "comm"))) == (1, 0), done.stdout


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


def test_01_explicit_box(tmp_path):
    case1(tmp_path)


def test_02_skill_wrapper_writes_root_box(tmp_path):
    case2(tmp_path)


def test_03_no_comm_no_box(tmp_path):
    case3(tmp_path)


def test_04_parent_value_ignored(tmp_path):
    case4(tmp_path)


def _mutant(tmp, name):
    needle, replacement = MUTANTS[name]
    dest = tmp / "mutant" / "feature-pack" / "fable-team" / "ft2"
    shutil.copytree(FT2, dest, ignore=shutil.ignore_patterns("__pycache__"))
    target = dest / "adapters" / "pi" / "launch_plan.py"
    text = target.read_text(encoding="utf-8")
    if text.count(needle) != 1:
        raise RuntimeError("%s 치환 0 — needle 불일치" % name)
    target.write_text(text.replace(needle, replacement), encoding="utf-8")
    return dest / "adapters" / "pi" / "launch.py"


@pytest.mark.parametrize("name,cases", [("M1", (case1, case2)), ("M2", (case3,))])
def test_mutants(tmp_path, name, cases):
    """변이 = 그 사례 빨강 · 같은 사례를 원본으로 1회 더 = 초록."""
    launcher = _mutant(tmp_path / name, name)
    for i, case in enumerate(cases):
        with pytest.raises(AssertionError):
            case(tmp_path / ("%s-%d" % (name, i)), launcher)
        case(tmp_path / ("%s-%d-orig" % (name, i)))
