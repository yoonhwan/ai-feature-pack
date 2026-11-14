"""r1817 keeper 첫 실동작 보정 시험 (카드 반례 ①~④ · 변이 M1·M1b·M2~M4 · DA#10 설계 APPROVE).
r1812 대역(keeper_world_r1812) 재사용 · plist 틀 렌더 · `env -i PATH=<좁은 값>` 하위 프로세스 · 주입 시계 · 가짜 tmux.
실 launchd·실 Slack·실 장부·실 tmux kill 0 · reap 는 FT_REAP_NOSIGNAL=1(신호 0) · 임시 root·명부만 · sleep 0.
기준판(팩 origin/main e5275f2a83) = ① ①′ ② ②⁗ ③ ③′ ④ ④′ Red · ①″ ②′ ②″ ②‴ ②⑤ ④″ = 지금과 같은 결과(경계·대조).
"""
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1817", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, FT2, OLD, T0, TEAM, AB, _lines, _put = kw.World, kw.FT2, kw.OLD, kw.T0, kw.TEAM, kw.AB, kw._lines, kw._put
NARROW = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"          # r1812 launchd PATH(/usr/sbin 없음)
FAKE_TMUX = "#!/bin/sh\ncase \"$1\" in has-session) echo \"can't find session\" >&2; exit 1;; list-*) exit 0;; esac\nexit 1\n"


def plist_path(w):
    text = (w.ft2 / "adapters" / "pi" / "launchd" / "com.byz.ft2-keeper.plist.in").read_text(encoding="utf-8")
    return plistlib.loads(text.encode("utf-8"))["EnvironmentVariables"]["PATH"]
def reap_env(w, path, **extra):   # 좁은 PATH 앞에 가짜 tmux 만(실 tmux 서버 읽기 0) · 상태 파일 = 임시
    _put(w.tmp / "nb" / "tmux", FAKE_TMUX), (w.tmp / "nb" / "tmux").chmod(0o755)
    env = {"HOME": str(w.tmp), "PATH": "%s:%s" % (w.tmp / "nb", path), "FT_CRITICAL_OFF": "1", "FT_REAP_NOSIGNAL": "1",
           "ZC_RESUME_DIR": str(w.tmp / "rs"), "FT_REAP_DEFER_DIR": str(w.tmp / "df"), "FT_PERMIT_DIR": str(w.tmp / "pm"),
           "FT_BG_FINITE_LEDGER": str(w.tmp / "bg.tsv"), "FT_PRESS_RUNNER_RE": "r1817-never-%d" % os.getpid()}
    return dict(env, **extra)
def c1(w):   # ① 렌더한 plist PATH 로 env -i 하위 셸 → lsof·tmux·git 셋 다 찾음
    assert plist_path(w) == NARROW + ":/usr/sbin:/sbin"
    done = subprocess.run(["/usr/bin/env", "-i", "PATH=" + plist_path(w), "/bin/sh", "-c", "command -v lsof && command -v tmux && command -v git"],
                          capture_output=True, text=True, timeout=10)
    assert done.returncode == 0 and done.stdout.count("\n") == 3, done.stdout
def c1b(w):  # ①′ launchd 와 같은 좁은 PATH 로 ft-seat-close → ft-seat-reap(대역 좌석 1개) → CLOSED-SESSION · left=0 · rc0
    seat, seats = "r1817z-%d#1" % os.getpid(), w.tmp / "cwd" / "seats-zz.json"
    _put(seats, {"_master": "M", seat: {"role": "nano", "agent": "claude"}})
    done = subprocess.run(["/bin/bash", str(w.old / "bin" / "ft-seat-close.sh"), seat, "--reason", "retire -> x#2", "--seats", str(seats)],
                          cwd=str(w.tmp / "cwd"), env=reap_env(w, NARROW), capture_output=True, text=True, timeout=60)
    assert done.returncode == 0 and done.stdout.startswith("CLOSED-SESSION " + seat) and "left=0 rc=0" in done.stdout, done.stdout + done.stderr
def c1c(w):  # ①″ 절대 경로(FT_LSOF 대역 = 없는 파일)·PATH 둘 다 lsof 없음 → rc20 «실행 실패» · kill 0
    done = subprocess.run(["/bin/bash", str(w.old / "bin" / "ft-seat-reap.sh"), "r1817y-%d#1" % os.getpid()], cwd=str(w.tmp),
                          env=reap_env(w, NARROW, FT_LSOF=str(w.tmp / "없음" / "lsof")), capture_output=True, text=True, timeout=60)
    assert done.returncode == 20 and "lsof" in done.stderr and "실행 실패" in done.stderr, done.stdout + done.stderr
    assert "reap-kill" not in done.stdout and done.stdout.strip().endswith("left=? rc=20")
def landed(w, work, line, alive=True):   # 카드 착지 줄 = «- 착지: <line>» 그대로 · 나노 세션 유휴
    w.enable(), w.card(work, line), w.work(work, alive=alive)
    return w.round()
def c2(w):   # ② 꼬리 붙은 착지 줄 + 조상 → complete 1 · 닫기 1
    lines = landed(w, "r9201", "%s (ai-feature-pack origin/main · PR #1023 · 착지 확인)" % w.pack_sha())
    assert w.kinds("complete") == 1 and len(w.tmux("kill-session")) == 1, lines
def c2b(w):  # ②′ 꼬리 없음 → 지금과 같음(complete 1)
    landed(w, "r9202", w.pack_sha())
    assert w.kinds("complete") == 1
def c2c(w):  # ②″ 10자 sha → 착지 줄 없음 (짧은 sha 를 늘리지 않음)
    assert any("r9203 착지 줄 없음" in x for x in landed(w, "r9203", w.pack_sha()[:10])) and w.kinds("complete") == 0
def c2d(w):  # ②‴ 앞 글자 있는 줄 → 착지 줄 없음
    assert any("r9204 착지 줄 없음" in x for x in landed(w, "r9204", "팩 origin/main " + w.pack_sha())) and w.kinds("complete") == 0
def c2e(w):  # ②⁗ 착지 줄 두 개(엄격 1 + 꼬리 1) → 마지막 줄 sha
    sha = w.pack_sha()
    lines = landed(w, "r9205", "%s\n- 착지: %s (PR #1 · 재착지)" % (AB, sha))
    assert any(x.startswith("COMPLETED harness r9205 착지 " + sha) for x in lines) and w.kinds("complete") == 1, lines
def c2f(w):  # ②⑤ 41자 hex → 착지 줄 없음
    assert any("r9206 착지 줄 없음" in x for x in landed(w, "r9206", w.pack_sha() + "0")) and w.kinds("complete") == 0
def timed(w, b3):   # 주입 시계: fetch 리포 2개 × 5초 · B1 10초 · B2 10초 · B3 b3초
    w.card("r9301", w.pack_sha()), w.work("r9301", intent=False)
    k = w.keeper()

    def tick(dt, out=None):
        w.t += dt
        return out
    git = k.git
    k.git = lambda repo, *a, **o: (tick(5) if a[0] == "fetch" else None, git(repo, *a, **o))[1]
    k.complete, k.close, k.retired = (lambda *a: tick(10, True)), (lambda *a: tick(10)), (lambda: tick(b3))
    rows = [x for x in w.round(k) if x.startswith("ROUND")]
    jl = [json.loads(x) for p in (w.state / "ft2-keeper").glob("*.jsonl") for x in _lines(p)]
    assert [x["kind"] for x in jl if x["line"].startswith("ROUND")] == ["ROUND"]
    return rows
def c3(w):   # ③ 단계마다 10초 → ROUND s=40 · 단계 넷 · OVER 0
    assert timed(w, 10) == ["ROUND s=40 fetch=10 b1=10 b2=10 b3=10 stall=0"]   # r1898 stall 칸
def c3b(w):  # ③′ 합 61 → OVER
    assert timed(w, 31) == ["ROUND s=61 fetch=10 b1=10 b2=10 b3=31 stall=0 OVER"]
def sock(w, got, rc=0):   # 가짜 tmux 앞에 display 만 가로채는 층 · 기준 = FT2_TMUX_SOCKET(설치 렌더 고정)
    _put(w.tmp / "bin" / "tmux2", "#!/bin/sh\n[ \"$1\" = display ] && { echo '%s'; exit %d; }\nexec '%s' \"$@\"\n"
         % (got, rc, w.env["FT_TMUX"])), (w.tmp / "bin" / "tmux2").chmod(0o755)
    w.env.update(FT_TMUX=str(w.tmp / "bin" / "tmux2"), FT2_TMUX_SOCKET="/private/tmp/tmux-desk/default")
    w.enable(), w.card("r9401", w.pack_sha()), w.work("r9401", done=True, alive=True)
    _put(w.root / ".fable-team" / "seats-harness.json", {"_master": "M", "O#1": {"role": "stop-ready", "_replaced_by": "O#2"}})
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    _put(w.tm, dict(d, alive=d["alive"] + ["O#1"]))
    return w.round()
def c4(w):   # ④ tmux 소켓 경로 다름 → 판정 불가 1줄 · kill 0 · ft-seat-close 0
    lines = sock(w, "/private/tmp/tmux-other/default")
    assert sum("판정 불가" in x and "소켓" in x for x in lines) == 1, lines
    assert w.tmux("kill-session") == [] and _lines(str(w.close) + ".log") == [] and w.kinds("close_receipt") == 0
def c4b(w):  # ④′ 소켓 판독 실패(rc1) → 판정 불가 · 닫기 0 · ④″ 같은 소켓 → 지금처럼 닫음(대조)
    lines = sock(w, "", rc=1)
    assert any("판정 불가" in x and "소켓" in x for x in lines) and w.tmux("kill-session") == [], lines
def c4c(w):
    lines = sock(w, "/private/tmp/tmux-desk/default")
    assert len(w.tmux("kill-session")) == 1 and len(_lines(str(w.close) + ".log")) == 1, lines
CASES = {"①": c1, "①′": c1b, "①″": c1c, "②": c2, "②′": c2b, "②″": c2c, "②‴": c2d, "②⁗": c2e, "②⑤": c2f,
         "③": c3, "③′": c3b, "④": c4, "④′": c4b, "④″": c4c}
KL, KP, PL = "adapters/pi/keeper_land.py", "adapters/pi/keeper.py", "adapters/pi/launchd/com.byz.ft2-keeper.plist.in"
MUTANTS = {"M1": ("ft2", PL, ":/bin:/usr/sbin:/sbin<", ":/bin<", c1),
           "M1b": ("old", "bin/ft-seat-reap.sh", '"FT_LSOF", "/usr/sbin/lsof"', '"FT_LSOF", "/없음/lsof"', c1b),
           "M2": ("ft2", KL, r"(?=\s|$)", r"\s*$", c2),
           "M3": ("ft2", KL, r"(?=\s|$)", "", c2f),
           "M4": ("ft2", KP, "s = sum(self.spent.values())", "s = 0", c3)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    where, rel, old, new, case = MUTANTS[name]
    trees = {"ft2": tmp_path / "m" / "ft2", "old": tmp_path / "m" / "old"}
    shutil.copytree(FT2, trees["ft2"], ignore=shutil.ignore_patterns("tests", "__pycache__"))
    shutil.copytree(OLD / "bin", trees["old"] / "bin")
    text = (trees[where] / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (trees[where] / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w1", monkeypatch, trees["ft2"], trees["old"]))
    case(World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
def test_reap_bin_kit_same_bytes():
    assert (OLD / "bin" / "ft-seat-reap.sh").read_bytes() == (OLD / "kit" / "fable-team" / "bin" / "ft-seat-reap.sh").read_bytes()


_SS = importlib.util.spec_from_file_location("keeper_stall_world_r1817", str(Path(__file__).with_name("test_pi_keeper_stall_r1813.py")))
sw = importlib.util.module_from_spec(_SS)
_SS.loader.exec_module(sw)


def stall_rounds(tmp, mp, sock):   # fix1 R1 — 실제 _round(run_once) · r1813 대역(실제 core·launch · 가짜 tmux) · fetch 만 rc0 대역
    w = sw.World(tmp, mp)
    w.seat()
    _put(w.root / ".fable-team" / "state" / "ft20-switch" / (sw.TEAM + ".json"), "{}")
    if sock:
        w.env["FT2_TMUX_SOCKET"] = "/private/tmp/tmux-desk/default"   # 가짜 tmux display = 빈 출력 → 불일치
    lines = []
    for dt in (0, 11 * sw.M):
        w.t = sw.T0 + dt
        mp.setenv("FT_NOW", sw._stamp(w.t))
        k = w.keeper()
        git = k.git
        k.git = lambda repo, *a, **o: (0, "", "") if a[0] == "fetch" else git(repo, *a, **o)
        assert k.run_once() == 0
        lines += k.lines
    return w, lines
def test_fix1_socket_fail_round_no_stall(tmp_path, monkeypatch):   # R1 소켓 불일치 바퀴 → 깨움·재배정·kill·launch 0
    w, lines = stall_rounds(tmp_path, monkeypatch, True)
    assert sum("판정 불가" in x and "소켓" in x for x in lines) == 2, lines
    assert not any(x.startswith(("WOKE", "REASSIGNED")) for x in lines), lines
    assert w.tmux("send-keys") == [] and w.tmux("kill-session") == [] and w.tmux("new-session") == [] and w.kinds("dispatch") == 1
def test_fix1_socket_unset_stall_runs(tmp_path, monkeypatch):   # 대조: 기준 소켓 없음(셸 손 실행) → 같은 경로에서 WOKE → REASSIGNED
    w, lines = stall_rounds(tmp_path, monkeypatch, False)
    assert any(x.startswith("WOKE") for x in lines) and any(x.startswith("REASSIGNED") for x in lines), lines
