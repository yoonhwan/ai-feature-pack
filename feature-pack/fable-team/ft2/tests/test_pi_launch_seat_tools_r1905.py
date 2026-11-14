"""r1905 ft2 launch — pi argv 에 좌석 도구 확장 `-e <설치본>/adapters/pi/ft2-seat.ts` 1쌍 · 없으면 tmux 전 rc≠0 (반례 ①~③ · 변이 M1).
대역 = test_pi_launch 세계(임시 root·가짜 git·tmux·pi) + 가짜 설치본(ft2 사본 · 시험 제외).
실 tmux·설치·전역 ~/.pi/agent/extensions 쓰기 0 · sleep 0. 변이는 사본에서만 · 원본 사본으로 1회 더.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("pi_launch_r1905", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pl)
SEAT = Path("adapters", "pi", "ft2-seat.ts")
M1 = ('["-e", seat_tools(), "--approve"]', '["--approve"]')


def install(tmp, seat=True, mutate=None):
    """가짜 설치본 1개 — seat=False 면 ft2-seat.ts 0 · mutate = launch_plan.py 치환 1곳(치환 0 = 빨강)."""
    tree = Path(tmp) / "inst" / "ft2"
    shutil.copytree(pl.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    if not seat:
        (tree / SEAT).unlink()
    if mutate:
        plan = tree / "adapters" / "pi" / "launch_plan.py"
        text = plan.read_text(encoding="utf-8")
        if text.count(mutate[0]) != 1:
            raise RuntimeError("치환 0 — needle 불일치 %r" % (mutate,))   # AssertionError 아님(변이 통과로 세지 않는다)
        plan.write_text(text.replace(*mutate), encoding="utf-8")
    return tree


def seat_world(tmp, **kw):
    tree = install(tmp, **kw)
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    return tree, root, fake, tree / "adapters" / "pi" / "launch.py"


def case_pair(tmp, **kw):
    """① 설치본에 ft2-seat.ts 있음 → pi 바로 뒤 `-e <그 경로>` 정확히 1쌍 · `--approve` 앞 · 실제 new-session 도 같은 argv."""
    tree, root, fake, launcher = seat_world(tmp, **kw)
    out, rc = pl._launch(root, fake, launcher, extra=["--dry-run"])
    tm = out["argv"]["tmux"]
    i = tm.index(str(fake / "pi"))
    assert rc == 0 and tm[i:i + 4] == [str(fake / "pi"), "-e", str(tree / SEAT), "--approve"], tm
    assert tm[i:].count("-e") == 1, tm
    out, rc = pl._launch(root, fake, launcher)
    new = [x["argv"] for x in pl._log(fake) if x.get("sub") == "new-session"]
    assert (rc, len(new)) == (0, 1) and new[0] == tm[1:], (out, new)


def case_missing(tmp):
    """② ft2-seat.ts 없음 → rc≠0 «판정 불가 좌석 도구 없음 <경로>» · git·tmux 호출 0."""
    tree, root, fake, launcher = seat_world(tmp, seat=False)
    out, rc = pl._launch(root, fake, launcher)
    assert rc != 0 and out.get("opened") is not True, out
    assert "판정 불가 좌석 도구 없음 %s" % (tree / SEAT) in out.get("reason", ""), out
    assert pl._log(fake) == [], "git·tmux 0"


def case_role(tmp):
    """③ 역할 argv(모델·생각) 있는 좌석 → `--approve` 뒤 역할 argv 순서 그대로 · 첫 본문은 마지막 1개."""
    tree, root, fake, launcher = seat_world(tmp)
    tm = pl._launch(root, fake, launcher, extra=["--dry-run"])[0]["argv"]["tmux"]
    i = tm.index("--approve")
    assert tm[i + 1:-1] == pl.SESSION_ARGV and tm[-1].startswith("[발주] ft2 %s %s@" % (pl.TEAM, pl.WORK)), tm


CASES = {"①": case_pair, "②": case_missing, "③": case_role}


@pytest.mark.parametrize("name", list(CASES))
def test_case(tmp_path, name):
    CASES[name](tmp_path)


def test_mutant_m1(tmp_path):
    """M1 `-e` 쌍 삭제 → ① FAIL · 원본 사본으로 같은 사례 1회 더 = PASS."""
    with pytest.raises(AssertionError):
        case_pair(tmp_path / "bad", mutate=M1)
    case_pair(tmp_path / "good")
