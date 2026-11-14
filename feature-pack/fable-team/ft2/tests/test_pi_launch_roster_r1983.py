"""r1983 ft2 launch 가 연 좌석 = 팀 명부 seats-<팀>.json 행 1개 (반례 ①~⑤ · 변이 M1~M3).
대역 = test_pi_launch 세계(임시 root · 가짜 git·tmux) + 임시 명부 · 실 명부·실 tmux·실 우편함 0 · sleep 0.
⑤ 잠금 = 시험이 같은 팀 lock 을 쥔 «두 번째 ft2 쓰기» 다(launch 가 opened 뒤 lock 에서 멈춤 = wait 3초 넘김 1회).
mbox send rc0 = 설치 뒤 실사건(카드 «설치») · 여기서는 mbox 판정이 보는 꼴(이름 키 dict 행)까지만 본다.
"""
import fcntl, importlib.util, json, subprocess  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("pi_launch_r1983", str(HERE / "test_pi_launch.py"))
pl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pl)
BASE_ROSTER = '{\n  "_master": "byz-harness-master-pi#1",\n  "old#0": {"role": "nano", "agent": "pi"}\n}\n'
ROW = {"role": "nano", "agent": "pi", "work": pl.WORK, "attempt": pl.ATTEMPT,
       "index": "design/harness/indices/진행/%s.md" % pl.WORK, "source": "ft2-launch"}


def world(tmp, roster=BASE_ROSTER):
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    path = root / ".fable-team" / ("seats-%s.json" % pl.TEAM)
    path.write_text(roster, encoding="utf-8")
    return root, fake, path


def rows(path):
    return json.loads(path.read_text(encoding="utf-8"))


def case_open(tmp, launcher=pl.LAUNCH):
    """① launch 성공 → 명부 행 1(holder 키 · 순서 = 기존 뒤) · 기존 칸 그대로 · 결과 «행 추가»."""
    root, fake, path = world(tmp)
    out, rc = pl._launch(root, fake, launcher)
    assert (out["result"], rc, out.get("opened")) == ("접수 성공", 0, True), out
    data = rows(path)
    assert list(data) == ["_master", "old#0", pl.HOLDER], data
    assert data[pl.HOLDER] == dict(ROW, worktree=str(pl._worktree(root))), data[pl.HOLDER]
    assert out.get("roster") == "행 추가", out


def case_resume(tmp, launcher=pl.LAUNCH):
    """② 이미 행 있음(이어 열기·재launch) → 바이트 손 0 · 행 1 그대로 · «행 있음»."""
    root, fake, path = world(tmp, BASE_ROSTER.replace('"old#0"', '"%s"' % pl.HOLDER))
    before = path.read_bytes()
    out, rc = pl._launch(root, fake, launcher)
    assert rc == 0 and out.get("roster", "").startswith("행 있음"), out
    assert path.read_bytes() == before, "바이트 손 0"
    assert pl._launch(root, fake, launcher)[1] == 0 and path.read_bytes() == before, "opened 재호출 = 쓰기 0"


def case_fail(tmp, launcher=pl.LAUNCH, rc=None):
    """③ launch 실패(git·tmux) → rc2 · 명부 바이트 손 0."""
    root, fake, path = world(tmp)
    before = path.read_bytes()
    out, code = pl._launch(root, fake, launcher, rc=rc or {"tmux": 1})
    assert (out["result"], code) == ("복구 필요", 2), out
    assert path.read_bytes() == before, "실패 길 명부 쓰기 0"


def case_corrupt(tmp, launcher=pl.LAUNCH):
    """④ 명부 손상·없음 → 쓰기·생성 0 · launch 성공 그대로 · «판정 불가 명부» stdout 칸 + stderr 1줄."""
    for name, text in (("bad", '{"_master": '), ("none", None)):
        root, fake, path = world(Path(tmp) / name, text or "")
        if text is None:
            path.unlink()
        done = subprocess.run(pl._argv(launcher, root), env=pl._env(fake), capture_output=True, text=True, timeout=70)
        out = json.loads(done.stdout)
        assert (out["result"], done.returncode, out.get("opened")) == ("접수 성공", 0, True), out
        assert out.get("roster", "").startswith("판정 불가 명부"), out
        assert [x for x in done.stderr.splitlines() if x.startswith("판정 불가 명부")] == [out["roster"]], done.stderr
        assert (path.read_text(encoding="utf-8") if path.exists() else None) == text, "쓰기·생성 0"


def case_lock(tmp, launcher=pl.LAUNCH):
    """⑤ 동시 쓰기 2(launch + 같은 팀 lock 을 쥔 다른 ft2 쓰기) → 두 행 다 남음."""
    root, fake, path = world(tmp)
    pl._launch_dir(root).mkdir(parents=True, exist_ok=True)
    with open(pl._launch_dir(root) / "roster.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stale = rows(path)                    # 다른 쓰기가 «읽은» 명부(launch 행 전)
        proc = subprocess.Popen(pl._argv(launcher, root), env=pl._env(fake), stdout=subprocess.PIPE, text=True)
        try:
            proc.wait(timeout=3)              # 잠금이 있으면 opened 뒤 lock 에서 멈춘다(= 넘김)
        except subprocess.TimeoutExpired:
            pass
        stale["other#0"] = {"role": "nano", "agent": "pi"}
        path.write_text(json.dumps(stale, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    assert json.loads(proc.communicate(timeout=70)[0])["result"] == "접수 성공"
    assert {"other#0", pl.HOLDER} <= set(rows(path)), rows(path)


CASES = {"open": case_open, "resume": case_resume, "fail": case_fail, "corrupt": case_corrupt, "lock": case_lock}
ENROLL = 'note = roster.enroll(env, plan["worktree"]'
pl.MUTANTS.update({
    "RM1": ("launch.py", ENROLL, 'note = "" and roster.enroll(env, plan["worktree"]'),
    "RM2": ("launch.py", '    write_intent(plan["intent"], dict(env, state="failed"',
            '    roster.enroll(env, plan["worktree"], planner.card_row(env["FT2_ROOT"], env["FT2_TEAM"]), os.path.dirname(plan["intent"]))\n'
            '    write_intent(plan["intent"], dict(env, state="failed"'),
    "RM3": ("launch_roster.py", "fcntl.flock(lock, fcntl.LOCK_EX)", "fcntl.LOCK_EX"),
})


@pytest.mark.parametrize("name", ["open", "resume", "corrupt", "lock"])
def test_case(tmp_path, name):
    CASES[name](tmp_path)


@pytest.mark.parametrize("rc", [{"git": 1}, {"tmux": 1}], ids=["git", "tmux"])
def test_fail(tmp_path, rc):
    case_fail(tmp_path, rc=rc)


@pytest.mark.parametrize("name,case", [("RM1", "open"), ("RM2", "fail"), ("RM3", "lock")])
def test_mutant(tmp_path, name, case):
    """M1 성공 뒤 쓰기 제거 → ① FAIL · M2 실패 길에도 쓰기 → ③ FAIL · M3 잠금 제거 → ⑤ FAIL · 원본으로 1회 더 = PASS."""
    launcher = pl._mutant(tmp_path, name)
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "bad", launcher)
    CASES[case](tmp_path / "good")
