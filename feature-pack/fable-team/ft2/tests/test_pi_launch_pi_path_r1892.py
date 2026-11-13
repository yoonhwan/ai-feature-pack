"""r1892 keeper launch — pi 절대 경로 + new-session 뒤 세션 살아 있음 1회 확인 (반례 ①~③ · 변이 M1·M2).
대역 = test_pi_launch 세계(임시 root·가짜 git) + 가짜 tmux(new·has rc 따로) · 가짜 HOME · PATH = 가짜 bin:/usr/bin:/bin(실 ~/.local/bin 0)
실 tmux·명부·장부·설치 0 · sleep 0. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("pi_launch_r1892", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pl)
TMUX = '''#!%s
import json, os, sys
argv = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"prog": "tmux", "argv": argv, "sub": argv[0]}) + "\\n")
sys.exit(int(os.environ.get("FAKE_TMUX_HAS_RC" if argv[0] == "has-session" else "FAKE_TMUX_RC") or 0))
''' % sys.executable


def world(tmp, home_pi=True, bin_pi=False, has_rc=0):
    root, fake = pl._paths(tmp)
    (fake / "tmux").write_text(TMUX, encoding="utf-8")
    (fake / "pi").unlink(missing_ok=True)       # 기본 세계의 가짜 bin pi 는 이 파일이 정한다(bin_pi)
    home = Path(tmp) / "home"
    for where, on in ((home / ".local" / "bin", home_pi), (fake, bin_pi)):
        where.mkdir(parents=True, exist_ok=True)
        if on:
            (where / "pi").write_text("#!/bin/sh\n", encoding="utf-8")
            (where / "pi").chmod(0o755)
    pl._runtime(root)
    return root, fake, home, {"HOME": str(home), "PATH": "%s:/usr/bin:/bin" % fake, "FAKE_TMUX_HAS_RC": str(has_rc)}


def case_home_pi(tmp, launcher=pl.LAUNCH):
    """① env PATH 에 pi 없음 · 가짜 HOME/.local/bin 에만 → new-session 명령 = 그 절대 경로 · 모델 인자 그대로."""
    root, fake, home, extra = world(tmp)
    out, rc = pl._launch(root, fake, launcher, env_extra=extra)
    assert (out["result"], rc, out.get("opened")) == ("접수 성공", 0, True), out
    new = pl._log(fake)[4]["argv"]
    assert new[16] == str(home / ".local" / "bin" / "pi") and new[-5:-1] == pl.SESSION_ARGV, new


def case_no_pi(tmp, launcher=pl.LAUNCH):
    """① 둘 다 없음 → rc2 «pi 없음» · git·tmux 0 · 다시 불러도 바깥 호출 0."""
    root, fake, _, extra = world(tmp, home_pi=False)
    out, rc = pl._launch(root, fake, launcher, env_extra=extra)
    assert (out.get("result"), rc, out.get("step")) == ("복구 필요", 2, "pi 없음"), out
    assert pl._log(fake) == [], "git·tmux 0"
    again(root, fake, launcher, extra, "pi 없음")


def again(root, fake, launcher, extra, step):
    got = json.loads(pl._intent(root).read_text(encoding="utf-8"))
    assert (got["state"], got["step"]) == ("failed", step), got
    first = pl._log(fake)
    assert pl._launch(root, fake, launcher, env_extra=extra)[1] == 2 and pl._log(fake) == first, "바깥 호출 0"


def case_dead(tmp, launcher=pl.LAUNCH):
    """② new-session rc0 · has-session rc1 → rc2 «tmux 즉시 종료» 실패 의도 · 다시 불러도 바깥 호출 0."""
    root, fake, _, extra = world(tmp, has_rc=1)
    out, rc = pl._launch(root, fake, launcher, env_extra=extra)
    assert (out.get("result"), rc, out.get("step")) == ("복구 필요", 2, "tmux 즉시 종료"), out
    again(root, fake, launcher, extra, "tmux 즉시 종료")


def case_alive(tmp, launcher=pl.LAUNCH):
    """③ 둘 다 rc0 → opened 그대로 · new-session 1 → has-session -t =holder 1 · env 5개."""
    root, fake, _, extra = world(tmp, home_pi=False, bin_pi=True)
    out, rc = pl._launch(root, fake, launcher, env_extra=extra)
    assert (out["result"], rc, out.get("opened")) == ("접수 성공", 0, True), out
    lines = pl._log(fake)[4:]
    assert [line["sub"] for line in lines] == ["new-session", "has-session"], lines
    assert lines[1]["argv"] == ["has-session", "-t", "=" + pl.HOLDER] and lines[0]["argv"][16] == str(fake / "pi"), lines
    assert lines[0]["argv"][6:16:2] == ["-e"] * 5, lines[0]
    assert json.loads(pl._intent(root).read_text(encoding="utf-8"))["state"] == "opened"


CASES = {"home_pi": case_home_pi, "no_pi": case_no_pi, "dead": case_dead, "alive": case_alive}
pl.MUTANTS.update({
    "PM1": ("launch.py", '    if rc != 0:\n        return failed(plan, env, "tmux 즉시 종료"', '    if False:\n        return failed(plan, env, "tmux 즉시 종료"'),
    "PM2": ("launch_plan.py", '[pi or "pi"]', '["pi"]'),
})


@pytest.mark.parametrize("name", sorted(CASES))
def test_case(tmp_path, name):
    CASES[name](tmp_path)


@pytest.mark.parametrize("name,case", [("PM1", "dead"), ("PM2", "home_pi")])
def test_mutant(tmp_path, name, case):
    """M1 has-session 판정 빼기 → ② FAIL · M2 맨 pi → ① FAIL · 원본으로 같은 사례 1회 더 = PASS."""
    launcher = pl._mutant(tmp_path, name)
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "bad", launcher)
    CASES[case](tmp_path / "good")
