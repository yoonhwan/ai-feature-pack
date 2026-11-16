"""r2121 ft2 launch Pi 좌석 결속 — 창 뒤(late) 세션 중 «남의 것 확정»(마지막 session_info 이름 있음 ∧ 좌석 이름 0)은 뺀다 (카드 ⑧ ⑨ · 변이 M4~M6).
대역 = 가짜 tmux(list-panes·show-environment·list-sessions) · 가짜 ps · 임시 intent·세션 폴더 · ft_seat_pi.py 실제 실행(bin 사본).
실 tmux·실 세션 폴더·실 명부 0 · sleep 0. 기준판(팩 origin/main) = ⑧ Red(«세션 바뀜»). 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import datetime, importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
FILES = ("ft_seat_pi.py", "ft_seat_pi_ft2.py", "ft_seat_pi_turn.py", "ft_seat_codex.py")
SEAT, OTHER, WORK = "byz-knowledge-tester-pi#2", "byz-knowledge-tester-pi#3", "knowledge-tester-press-1"
TMUX = r'''#!__PY__
import json, os, sys
a = [x for x in sys.argv[1:] if x != "-u"]
d = json.load(open(os.environ["FAKE_ST"]))
open(os.environ["FAKE_ST"] + ".log", "a").write(" ".join(a) + "\n")
name = a[a.index("-t") + 1].lstrip("=") if "-t" in a else ""
if a[0] == "list-panes":
    sys.stdout.write("".join("%s\t%s\t%s\t0\n" % (s, p["pid"], p["cwd"]) for s, p in d["panes"].items()))
elif a[0] == "list-sessions":
    sys.stdout.write("".join(s + "\n" for s in d["panes"]))
elif a[0] == "show-environment":
    if name not in d["panes"]:
        sys.stderr.write("can't find session: %s\n" % name); sys.exit(1)
    sys.stdout.write("".join("%s=%s\n" % kv for kv in d["env"].get(name, {}).items()))
'''
PS = r'''#!__PY__
import sys
a = sys.argv[1:]
sys.stdout.write((a[1] if a[3] == "pid=" else "pi") + "\n")
'''


def z(at, sec):   # intent.at(로컬 · tz 없음) + sec → UTC «Z» 꼴(pi 세션 head.timestamp)
    t = datetime.datetime.fromisoformat(at).astimezone(datetime.timezone.utc) + datetime.timedelta(seconds=sec)
    return t.strftime("%Y-%m-%dT%H:%M:%S.123Z")


class Seat:
    """임시 세계 1개 — ft2 launch 좌석(env 에 TMUXC_PI_SESSION_ID 없음) · intent · worktree · 세션 폴더 · 가짜 tmux·ps."""
    def __init__(s, tmp, bindir=BIN):
        s.tmp, s.bin = tmp, tmp / "bin"
        s.bin.mkdir(parents=True)
        for f in FILES:
            shutil.copy(bindir / f, s.bin / f)
        fake = tmp / "fake"
        fake.mkdir()
        for name, body in (("tmux", TMUX), ("ps", PS)):
            (fake / name).write_text(body.replace("__PY__", sys.executable), encoding="utf-8")
            (fake / name).chmod(0o755)
        s.wt, s.sess, s.st = Path(os.path.realpath(tmp)) / "wt", tmp / "sess", tmp / "st.json"
        s.wt.mkdir()
        s.at = (datetime.datetime.now() - datetime.timedelta(hours=9)).strftime("%Y-%m-%dT%H:%M:%S")
        root = tmp / "ft2root"
        launch = root / ".fable-team" / "teams" / "knowledge" / "runtime" / "launch"
        launch.mkdir(parents=True)
        (launch / (WORK + "@a1.intent")).write_text(json.dumps({"FT2_HOLDER": SEAT, "FT2_WORK": WORK, "FT2_ATTEMPT": "a1", "at": s.at, "state": "opened", "worktree": str(s.wt)}), encoding="utf-8")
        env = {"FT2_ATTEMPT": "a1", "FT2_HOLDER": SEAT, "FT2_ROOT": str(root), "FT2_TEAM": "knowledge", "FT2_WORK": WORK}
        s.st.write_text(json.dumps({"panes": {SEAT: {"pid": "5101", "cwd": str(s.wt)}}, "env": {SEAT: env}}), encoding="utf-8")
        s.env = dict(os.environ, FT_TMUX=str(fake / "tmux"), FAKE_ST=str(s.st), FT_PI_SESSIONS=str(s.sess), PATH=str(fake) + os.pathsep + os.environ["PATH"])
        s.first = s.put("01a1e012", 1, [SEAT])   # 첫 세션 = intent at +1초 · 이름 = 좌석

    def put(s, sid, sec, names=(), pad=0, lead=False):
        """세션 파일 1개(worktree 폴더) · names = session_info 이름 차례 · pad = 이름 사이(lead = 첫 이름 앞에도) 본문 바이트."""
        rows = [{"type": "session", "version": 3, "id": sid, "timestamp": z(s.at, sec), "cwd": str(s.wt)}]
        for i, n in enumerate(names):
            rows += ([{"type": "message", "message": {"role": "user", "content": [{"type": "text", "text": "x" * pad}]}}] if (i or lead) and pad else []) + [{"type": "session_info", "name": n}]
        rows += [{"type": "message", "message": {"role": "assistant", "stopReason": "stop", "content": []}}]
        f = s.sess / ("--" + str(s.wt).strip("/").replace("/", "-") + "--") / ("%s_%s.jsonl" % (z(s.at, sec).replace(":", "-"), sid))
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
        return f

    def late(s, names, pad=0, lead=False):   # 창(120초) 뒤 세션 — tmux 세션 없음(주인 env 증명 0)
        return s.put("254928b2", 8 * 3600, names, pad, lead)

    def run(s):
        """ft_seat_pi.py <좌석> → (rc, stdout, stderr 끝 줄)."""
        p = subprocess.run([sys.executable, str(s.bin / "ft_seat_pi.py"), SEAT], capture_output=True, text=True, timeout=25, env=s.env, cwd=str(s.tmp))
        return p.returncode, p.stdout.strip(), (p.stderr.strip().splitlines() or [""])[-1]

    def path(s):   # locate 경로(첫 세션이면 결속)
        p = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import ft_seat_pi as p; print(p.locate(sys.argv[2])[0])", str(s.bin), SEAT],
                           capture_output=True, text=True, timeout=25, env=s.env, cwd=str(s.tmp))
        return p.stdout.strip()


MOVED = (1, "", "판정 불가 Pi: 세션 바뀜")


def c8(tmp, bindir=BIN):   # ⑧ tester#2 꼴 — late 이름 = «…-pi#3»(tmux 세션 없음) → 결속 = 첫 세션 · ft_seat_pi.py rc 0
    s = Seat(tmp, bindir)
    s.late([OTHER])
    rc, out, err = s.run()
    assert (rc, err) == (0, "") and out and s.path() == str(s.first), (rc, out, err)


def c9a(tmp, bindir=BIN):   # ⑨ late 이름 = 좌석 이름 → «세션 바뀜» 그대로(진짜 /new)
    s = Seat(tmp, bindir)
    s.late([SEAT])
    assert s.run() == MOVED


def c9b(tmp, bindir=BIN):   # ⑨ late 이름 없음 · owners 에 없음 → «세션 바뀜» 그대로
    s = Seat(tmp, bindir)
    s.late([])
    assert s.run() == MOVED


def c9c(tmp, bindir=BIN):   # ⑨ late session_info 가 66KB 본문 뒤에만 · 이름 = 다른 좌석 → 뺌(파일 전체 읽기)
    s = Seat(tmp, bindir)
    s.late([OTHER], pad=66 * 1024, lead=True)
    rc, out, err = s.run()
    assert (rc, err) == (0, "") and s.path() == str(s.first), (rc, out, err)


def c9d(tmp, bindir=BIN):   # ⑨ late 앞 = «…-pi#3» · 66KB 본문 · 뒤 = 좌석 이름(DA R1) → 빼지 않음 · «세션 바뀜»
    s = Seat(tmp, bindir)
    s.late([OTHER, SEAT], pad=66 * 1024)
    assert s.run() == MOVED


def c9e(tmp, bindir=BIN):   # ⑨ 마지막 session_info 이름 빈 글 → 이름 없음 = «세션 바뀜»
    s = Seat(tmp, bindir)
    s.late([OTHER, ""])
    assert s.run() == MOVED


def c9t(tmp, bindir=BIN):   # ⑨ 이름 판독 합계 7초 넘음 = 판정 불가(ValueError) · «세션 바뀜»·결속 0
    s = Seat(tmp, bindir)
    s.late([OTHER])
    spec = importlib.util.spec_from_file_location("f2_%d" % id(s), str(s.bin / "ft_seat_pi_ft2.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.CAP = -1   # 남은 몫 0 = 첫 줄에서 상한 넘음
    intent = json.loads(next((tmp / "ft2root").rglob("*.intent")).read_text(encoding="utf-8"))
    with pytest.raises(ValueError, match="이름 판독"):
        mod.first_session((intent, "5101", str(s.wt)), s.sess)


CASES = {"⑧": c8, "⑨a": c9a, "⑨b": c9b, "⑨c": c9c, "⑨d": c9d, "⑨e": c9e, "⑨t": c9t}
F2 = "ft_seat_pi_ft2.py"
MUTANTS = {"M4": ("late = [sid for sid, path in late if not foreign(path, seat, end)]", "late = [sid for sid, path in late]", "⑧"),
           "M5": ("return bool(seat and got and got[-1]) and seat not in got", "return bool(seat and got and got[-1])", "⑨a"),
           "M6": ('                got.append(rec["name"].strip() if isinstance(rec.get("name"), str) else "")\n',
                  '                return [rec["name"].strip() if isinstance(rec.get("name"), str) else ""]\n', "⑨d")}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path)


def test_bin_equals_kit():   # kit 사본 맞춤
    kit = BIN.parent / "kit" / "fable-team" / "bin" / F2
    assert (BIN / F2).read_bytes() == kit.read_bytes()


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, case = MUTANTS[name]
    mut = tmp_path / "mbin"
    mut.mkdir()
    for f in FILES:
        shutil.copy(BIN / f, mut / f)
    text = (mut / F2).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (mut / F2).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", mut)
    CASES[case](tmp_path / "w2")   # 원본으로 같은 사례 1회 더 = PASS
