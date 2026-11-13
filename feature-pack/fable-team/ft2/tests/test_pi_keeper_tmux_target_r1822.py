"""r1822 ft2 keeper tmux pane 대상 — 실 tmux 전용 소켓 시험 (카드 반례 ①~⑤ · 변이 M1~M4 · DA#10 설계 APPROVE).
입력: 실 tmux 를 `-L ft2-r1822-<pid> -f /dev/null` 로만 부른다(사용자 기본 서버·설정 손 0). 대역 2개뿐 = FT_TMUX 기록 포장
(argv 기록 뒤 같은 전용 소켓 tmux 로 exec) · ps(정상 pi argv · 받은 PID 기록). 정리 = 이 시험이 만든 세션 kill-session →
빈 서버는 스스로 끝남 → 남은 소켓 파일 삭제(kill-server 0). sleep 0. 기준판(`-t =이름`) = ① ② ⑤ Red.
"""
import importlib.util, os, shutil, subprocess, time  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
S0, S00, GONE, TEAM, W = "byz-x-nano-r1822#0", "byz-x-nano-r1822#00", "byz-x-nano-r1822#9", "x", "r1822"
SOCK = "ft2-r1822-%d" % os.getpid()
TMUX = '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$0.log"\nexec tmux -L %s -f /dev/null "$@"\n' % SOCK
PS = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\necho "node /x/pi --model claude-opus-5-5 --thinking medium"\n'
pytestmark = pytest.mark.skipif(not shutil.which("tmux"), reason="tmux 없음")


def _tm(*a):
    return subprocess.run(["tmux", "-L", SOCK, "-f", "/dev/null"] + list(a), capture_output=True, text=True, timeout=7)


def _log(path):
    return [x.split(" ") for x in Path(path).read_text(encoding="utf-8").splitlines()] if Path(path).exists() else []


@pytest.fixture
def k(tmp_path):
    b = tmp_path / "bin"
    b.mkdir(), (tmp_path / "root").mkdir()
    for name, body in (("tmux", TMUX), ("ps", PS)):
        (b / name).write_text(body, encoding="utf-8"), (b / name).chmod(0o755)
    for s in (S0, S00):
        assert _tm("new-session", "-d", "-s", s, "-x", "200", "-y", "50", "sh -c 'cat >/dev/null'").returncode == 0
    sock = _tm("display-message", "-p", "#{socket_path}").stdout.strip()
    env = {x: v for x, v in os.environ.items() if x != "FT2_TMUX_SOCKET"}
    env.update(FT_TMUX=str(b / "tmux"), FT2_KEEPER_PS=str(b / "ps"), FT2_PI_SESSIONS=str(tmp_path / "sess"))
    spec = importlib.util.spec_from_file_location("k1822_%d" % id(b), str(FT2 / "adapters" / "pi" / "keeper.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    keeper, calls = mod.Keeper(str(tmp_path / "root"), env=env, now=lambda: 1794000000.0), []
    real = keeper.call
    keeper.call = lambda argv, *a, **kw: calls.append((argv, real(argv, *a, **kw))) or calls[-1][1]
    keeper.calls, keeper.tlog, keeper.pslog = calls, str(b / "tmux.log"), str(b / "ps.log")
    yield keeper
    for s in (S0, S00):
        _tm("kill-session", "-t", "=" + s)    # 이 시험이 만든 세션만 · 마지막 세션이 닫히면 전용 서버가 스스로 끝난다
    if sock.endswith("/" + SOCK) and _tm("has-session").returncode != 0 and os.path.exists(sock):
        os.unlink(sock)


def _target(k, verb):
    return [a[a.index("-t") + 1] for a in _log(k.tlog) if a[0] == verb]


def test_c1_capture_real_pane(k):      # ① 화면 읽기 rc0 · 출력 줄 > 0 · G2 기준판 꼴 rc1·빈 PID 도 같은 서버에서 감시
    assert k.idle(TEAM, W, S0) is True
    got = [r for a, r in k.calls if a[1] == "capture-pane"]
    assert got[0][0] == 0 and len(got[0][1].splitlines()) > 0 and _target(k, "capture-pane") == ["=" + S0 + ":"]
    assert _tm("capture-pane", "-p", "-t", "=" + S0).returncode == 1
    assert _tm("display-message", "-p", "-t", "=" + S0, "#{pane_pid}").stdout.strip() == ""


def test_c2_wake_reaches_pane(k):      # ② send-keys 세 번 rc0 · 화면에 깨움 글자 1회
    k.stall.wake(TEAM, W, S0, "x|r1822@a1", 960)
    sent = [r for a, r in k.calls if a[1] == "send-keys"]
    assert [r[0] for r in sent] == [0, 0, 0] and set(_target(k, "send-keys")) == {"=" + S0 + ":"}
    assert not [x for x in k.lines if "깨움" in x and " rc " in x]
    pane, end = "", time.monotonic() + 5
    while "[깨움] ft2 keeper" not in pane and time.monotonic() < end:   # 대기 = tmux 화면 갱신 확인뿐(sleep 0)
        pane = _tm("capture-pane", "-p", "-t", "=" + S0 + ":").stdout
    assert pane.count("[깨움] ft2 keeper") == 1


def test_c3_absent_session_unsure(k):  # ③ 세션 없음 → 화면 읽기 rc1 · 판정 불가 1줄 · kill 0
    assert not k.idle(TEAM, W, GONE)
    assert [x for x in k.lines if "판정 불가" in x] == k.lines and len(k.lines) == 1 and _target(k, "kill-session") == []


def test_c4_session_slots_and_prefix_sibling(k):   # ④ 세션 자리 `=이름` 그대로 · ④′ 정확한 세션만 · ④″ 접두 형제 안 고름
    launch = Path(k.root) / ".fable-team" / "teams" / TEAM / "runtime" / "launch"
    launch.mkdir(parents=True)
    (launch / ("%s@a1.intent" % W)).write_text('{"FT2_HOLDER": "%s", "state": "opened"}' % S0, encoding="utf-8")
    k.landing, k.protected_ok = (lambda t, w: (None, None, None)), (lambda *a: True)
    k.turn_ended, k.receipt = (lambda *a: True), (lambda *a, **kw: None)
    k.close(TEAM, W, "a1", {"gen": 1}, S0)
    assert any(x.startswith("CLOSED-SESSION") for x in k.lines), k.lines
    assert set(_target(k, "has-session")) == {"=" + S0} and _target(k, "kill-session") == ["=" + S0]
    assert _tm("has-session", "-t", "=" + S0).returncode == 1 and _tm("has-session", "-t", "=" + S00).returncode == 0
    del k.lines[:]
    assert not k.idle(TEAM, W, S0) and k.stall.role(S0) is None
    assert len(k.lines) == 1 and "판정 불가" in k.lines[0] and _log(k.pslog) == []


def test_c5_role_reads_pane_pid(k):    # ⑤ display-message = 그 세션 pane 의 숫자 PID → ps 1회 → role=session
    want = _tm("list-panes", "-t", "=" + S0 + ":", "-F", "#{pane_pid}").stdout.strip()
    assert want.isdigit() and k.stall.role(S0) == "session"
    assert _target(k, "display-message") == ["=" + S0 + ":"] and _log(k.pslog) == [["-o", "args=", "-p", want]]
