"""r2257 launch 개설 영수 — alive(has-session) rc0 뒤 receipt(display-message) 1회 → opened intent tmux_sid·tmux_created (반례 ①~⑤ · 변이 M1~M3).
대역 = test_pi_launch 세계(임시 root·가짜 git·cli 동사) + 가짜 tmux(tmux 3.6a 꼴 동결: 없는 세션 has-session rc1 «can't find session» · display-message rc0 빈 출력)
· ⑤ = r1960 keeper 세계(임시 BYZ·팩 리포·가짜 tmux 생애 값). 실 tmux·명부·장부·설치 0 · 네트워크 0 · sleep 0. 변이는 사본에서만 · 원본으로 1회 더.
"""
import importlib.util, json, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
FT2 = HERE.parent


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pl = _mod(HERE / "test_pi_launch.py", "r2257_pi_launch")
e60 = _mod(HERE / "test_pi_keeper_endings_r1960.py", "r2257_endings")
holders = _mod(FT2 / "adapters" / "pi" / "ft2_holders.py", "r2257_holders")
cleanup = _mod(FT2 / "adapters" / "pi" / "launch_cleanup.py", "r2257_cleanup")
LIFE, FMT = "$7\t1795000000", "#{session_id}\t#{session_created}"
TMUX = '''#!%s
import json, os, sys
a = sys.argv[1:]
open(os.environ["FAKE_LOG"], "a").write(json.dumps({"prog": "tmux", "argv": a, "sub": a[0]}) + "\\n")
gone = os.environ.get("FAKE_GONE") == "1"
if a[0] == "has-session" and gone:
    sys.stderr.write("can't find session: %%s\\n" %% a[-1].lstrip("=")); sys.exit(1)
if a[0] == "display-message":
    sys.stdout.write("" if gone else os.environ.get("FAKE_RECEIPT", %r) + "\\n"); sys.exit(0)
sys.exit(0)
''' % (sys.executable, LIFE)


def world(tmp, work=pl.WORK, holder=pl.HOLDER):
    root, fake = pl._paths(tmp)
    (fake / "tmux").write_text(TMUX, encoding="utf-8")
    for argv in (["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
                 ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2"], ["deliver", "--work", work]):
        assert pl._cli(root, *argv)[1] == 0
    return root, fake


def launch(root, fake, launcher, work=pl.WORK, extra=(), env=None):
    argv = [sys.executable, str(launcher), "--root", str(root), "--team", pl.TEAM, "--work", work] + list(extra)
    done = subprocess.run(argv, env=pl._env(fake, None, env), capture_output=True, text=True, timeout=70)
    assert "Traceback" not in done.stderr and done.stdout.count("\n") == 1, (done.stdout, done.stderr)
    return json.loads(done.stdout), done.returncode


def intent(root, work=pl.WORK):
    return json.loads((pl._launch_dir(root) / ("%s@%s.intent" % (work, pl.ATTEMPT))).read_text(encoding="utf-8"))


def tmux_subs(fake):
    return [line["sub"] for line in pl._log(fake) if line["prog"] == "tmux"]


def case1(tmp, launcher=pl.LAUNCH):
    """① receipt «$7\\t1795000000» → opened intent tmux_sid=$7 · tmux_created=1795000000 · tmux_note 0 · receipt = has-session 뒤 1회."""
    root, fake = world(tmp)
    out, rc = launch(root, fake, launcher)
    assert (out["result"], rc, out.get("opened")) == ("접수 성공", 0, True), out
    got = intent(root)
    assert (got["state"], got.get("tmux_sid"), got.get("tmux_created"), "tmux_note" in got) == ("opened", "$7", "1795000000", False), got
    tm = [line["argv"] for line in pl._log(fake) if line["prog"] == "tmux"]
    assert [a[0] for a in tm] == ["new-session", "has-session", "display-message"], tm
    assert tm[1] == ["has-session", "-t", "=" + pl.HOLDER] and tm[2] == ["display-message", "-p", "-t", "=%s:" % pl.HOLDER, FMT], tm
    return got


def case2(tmp, launcher=pl.LAUNCH):
    """② ① intent + 같은 세션(생애 $7/1795000000) · pane cwd = intent worktree → auto_opened = (True, "") · 기준판 = «개설 영수 없음»."""
    got = case1(tmp, launcher)
    pane = lambda argv: (0, "%s\t%s\n" % (LIFE, got["worktree"]), "")  # noqa: E731
    assert holders.auto_opened(pane, "tmux", pl.HOLDER, got) == (True, ""), got


def case3(tmp, launcher=pl.LAUNCH, monkeypatch=None):
    """③ 세션 즉시 종료 → has-session rc1 → «tmux 즉시 종료» 실패 의도 · opened 0 · receipt 0 · 같은 가짜 tmux 로 why_keep «tmux 있음» 0."""
    root, fake = world(tmp)
    out, rc = launch(root, fake, launcher, env={"FAKE_GONE": "1"})
    assert (out.get("result"), rc, out.get("step"), out.get("opened")) == ("복구 필요", 2, "tmux 즉시 종료", False), out
    assert intent(root)["state"] == "failed" and tmux_subs(fake) == ["new-session", "has-session"], pl._log(fake)
    alive = launch(root, fake, launcher, extra=["--dry-run"])[0]["paths"]["alive"]
    tree, tbin = Path(tmp) / "repo", Path(tmp) / "tbin"   # 실 git(임시 리포 · detached worktree) + 가짜 tmux 만 따로 둔 PATH
    head = pl._commits(tree)[1]
    pl._git(tree, "worktree", "add", "-q", "--detach", str(tree) + "-wt", head)
    tbin.mkdir(), (tbin / "tmux").write_text(TMUX, encoding="utf-8"), (tbin / "tmux").chmod(0o755)
    for key, value in (("PATH", "%s:%s" % (tbin, Path(pl.shutil.which("git")).parent)), ("FAKE_LOG", str(fake / "log.jsonl")), ("FAKE_GONE", "1")):
        monkeypatch.setenv(key, value)
    keep, _ = cleanup.why_keep(str(tree) + "-wt", head, alive, {"add_ok": True, "path_new": True}, 25, 7)
    assert alive == ["tmux", "has-session", "-t", "=" + pl.HOLDER] and keep == "" and tmux_subs(fake)[-1] == "has-session", (alive, keep)


def note_case(tmp, launcher, receipt):
    root, fake = world(tmp)
    out, rc = launch(root, fake, launcher, env={"FAKE_RECEIPT": receipt})
    assert (out["result"], rc, out.get("opened")) == ("접수 성공", 0, True), out
    got = intent(root)
    assert (got["state"], got.get("tmux_sid"), got.get("tmux_created")) == ("opened", "", ""), got
    assert got.get("tmux_note", "").startswith("영수 판독 실패") and receipt in got["tmux_note"], got
    assert tmux_subs(fake) == ["new-session", "has-session", "display-message"], pl._log(fake)


def case4(tmp, launcher=pl.LAUNCH):
    """④ has-session rc0 · receipt rc0 «garbage» → opened 그대로 · 두 칸 빈 값 · tmux_note 1칸."""
    note_case(tmp, launcher, "garbage")


def case4b(tmp, launcher=pl.LAUNCH):
    """④b has-session rc0 · receipt rc0 빈 출력(그 사이 세션 끝남) → opened 그대로 · 두 칸 빈 값 · tmux_note 1칸."""
    note_case(tmp, launcher, "")


def case5(tmp, launcher=pl.LAUNCH, monkeypatch=None):
    """⑤ ① 꼴 launch(옛 attempt 좌석 #1 · worktree = keeper 세계 tree) 뒤 같은 work 새 dispatch(holder -t#0) · 옛 세션 생존(생애 = 영수) · 카드 아카이브(끝)
    → keeper orphans CLOSED-ORPHAN 1 · kill 1 · 기준판 = HELD-ORPHAN «개설 영수 없음» + UNKNOWN roster-outside."""
    work, seat = "r9657", "byz-harness-nano-r9657#1"
    w = e60.world(None, Path(tmp) / "k", monkeypatch)
    tree = str(w.tmp / "wt" / work)
    root, fake = world(Path(tmp) / "l", work, seat)
    out, rc = launch(root, fake, launcher, work, extra=["--worktree", tree])
    assert (out["result"], rc) == ("접수 성공", 0), out
    made = json.loads((pl._launch_dir(root) / ("%s@a1.intent" % work)).read_text(encoding="utf-8"))   # launch 가 쓴 영수 그대로 · at 만 keeper 세계 시계(jsonl 2시간 쉼) 앞으로
    e60._put(w.runtime() / "launch" / ("%s@a0.intent" % work), dict(made, at="2026-01-01T00:00:00"))
    w.card(work, stage="아카이브/2026-11"), w.work(work)
    e60.tmuxset(w, alive=[seat], pane={seat: "❯ "}, life={seat: "%s\t%s" % (LIFE, tree)})
    lines, kills = e60.run(w)
    assert e60.has(lines, "CLOSED-ORPHAN harness %s %s" % (work, seat)) and kills == [["kill-session", "-t", "=" + seat]], lines


CASES = {"①": case1, "②": case2, "③": case3, "④": case4, "④b": case4b, "⑤": case5}
NEEDS_MP = ("③", "⑤")
OPENED = '    got = receipt(plan, dict(bare, **env))   # r2257 O2: 판독 실패여도 열기 결과 그대로\n'
pl.MUTANTS.update({
    "M1": ("launch.py", "at=time.strftime(STAMP), **got, **plan[\"notes\"]))", "at=time.strftime(STAMP), **plan[\"notes\"]))"),
    "M2": ("launch.py", OPENED, OPENED + '    if got.get("tmux_note"):\n        return failed(plan, env, "tmux 영수", got["tmux_note"], repo)\n'),
    "M3": ("launch.py", 'rc, detail = call(plan["alive"], None,', 'rc, detail = call(plan["receipt"], None,'),
})


def run_case(name, tmp, launcher, mp):
    return CASES[name](tmp, launcher, mp) if name in NEEDS_MP else CASES[name](tmp, launcher)


@pytest.mark.parametrize("name", list(CASES))
def test_case(tmp_path, monkeypatch, name):
    run_case(name, tmp_path, pl.LAUNCH, monkeypatch)


@pytest.mark.parametrize("name,case", [("M1", "①"), ("M1", "②"), ("M1", "⑤"), ("M2", "④"), ("M3", "③")])
def test_mutant(tmp_path, monkeypatch, name, case):
    """M1 두 칸 안 씀 → ① ② ⑤ FAIL · M2 판독 실패 = opened 실패 → ④ FAIL · M3 alive = receipt rc → ③ FAIL · 원본으로 같은 사례 1회 더 = PASS."""
    launcher = pl._mutant(tmp_path / "m", name)
    with pytest.raises(AssertionError):
        run_case(case, tmp_path / "bad", launcher, monkeypatch)
    run_case(case, tmp_path / "good", pl.LAUNCH, monkeypatch)
