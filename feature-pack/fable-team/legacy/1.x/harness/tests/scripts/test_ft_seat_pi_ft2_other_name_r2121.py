"""r2121 보정2 ft2 launch Pi 좌석 결속 — 창 뒤(late) 세션은 «다른 좌석 기록 증명»(session_info 이름 = 열쇠 · seat-resume <이름>.json
name·uuid 같음 ∧ 파일 안 좌석 이름 0)일 때만 뺀다 · 이름만 = 증거 아님 (카드 ⑧ ⑨ · DA 구현 확인 칸 · 변이 M4~M8).
대역 = 가짜 tmux(list-panes·show-environment·list-sessions) · 가짜 ps · 임시 intent·세션 폴더·기록 폴더(ZC_RESUME_DIR) · ft_seat_pi.py 실제 실행(bin 사본).
실 tmux·실 세션 폴더·실 기록 폴더·실 명부 0 · sleep 0. 기준판(팩 origin/main) = ⑧ Red(«세션 바뀜»). 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import datetime, importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
FILES = ("ft_seat_pi.py", "ft_seat_pi_ft2.py", "ft_seat_pi_turn.py", "ft_seat_codex.py")
SEAT, OTHER, WORK, LATE = "byz-knowledge-tester-pi#2", "byz-knowledge-tester-pi#3", "knowledge-tester-press-1", "254928b2-7cfc-4251-98e0-8637ffecde13"
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
        s.rd = tmp / "resume" / "seat-resume"
        s.rd.mkdir(parents=True)
        s.env = dict(os.environ, FT_TMUX=str(fake / "tmux"), FAKE_ST=str(s.st), FT_PI_SESSIONS=str(s.sess), ZC_RESUME_DIR=str(s.rd), PATH=str(fake) + os.pathsep + os.environ["PATH"])
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
        return s.put(LATE, 8 * 3600, names, pad, lead)

    def rec(s, name, body=None, uuid=LATE, at=None):   # 은퇴 기록 <name>.json(at = 기록 폴더 밖 경로 · body = 그대로 쓸 글)
        f = at or s.rd / (name + ".json")
        f.write_text(body if body is not None else json.dumps({"name": name, "uuid": uuid, "engine": "pi"}), encoding="utf-8")

    def run(s):
        """ft_seat_pi.py <좌석> → (rc, stdout, stderr 끝 줄)."""
        p = subprocess.run([sys.executable, str(s.bin / "ft_seat_pi.py"), SEAT], capture_output=True, text=True, timeout=25, env=s.env, cwd=str(s.tmp))
        return p.returncode, p.stdout.strip(), (p.stderr.strip().splitlines() or [""])[-1]

    def path(s):   # locate 경로(첫 세션이면 결속)
        p = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, sys.argv[1]); import ft_seat_pi as p; print(p.locate(sys.argv[2])[0])", str(s.bin), SEAT],
                           capture_output=True, text=True, timeout=25, env=s.env, cwd=str(s.tmp))
        return p.stdout.strip()


MOVED = (1, "", "판정 불가 Pi: 세션 바뀜")


def bound(s):   # 결속 = 첫 세션 · ft_seat_pi.py 줄 rc 0
    rc, out, err = s.run()
    assert (rc, err) == (0, "") and out and s.path() == str(s.first), (rc, out, err)


def c8(tmp, bindir=BIN):   # ⑧ tester#2 꼴 — late 이름 «…-pi#3»(tmux 세션 없음) · 기록 «…-pi#3».json uuid = late id → 결속 = 첫 세션
    s = Seat(tmp, bindir)
    s.late([OTHER])
    s.rec(OTHER)
    bound(s)


def moved(names, rec=None, pad=0):   # ⑨ «세션 바뀜» 그대로 칸 공용(rec = 기록 쓰기 함수)
    def case(tmp, bindir=BIN):
        s = Seat(tmp, bindir)
        s.late(names, pad=pad)
        (rec or (lambda s: None))(s)
        assert s.run() == MOVED
    return case


c9a = moved([SEAT])                                                       # ⑨1 late 이름 = 좌석 이름(진짜 /new)
c9b = moved([])                                                           # ⑨2 late 이름 없음 · owners 에 없음
c9c = moved([OTHER])                                                      # ⑨3 late 이름 = 다른 좌석 · 기록 없음(r2100 ⑥ 꼴 · 이름만 = 증거 아님)
c9d = moved([OTHER], lambda s: s.rec(OTHER, uuid="other-uuid"))           # ⑨4 기록 있음 · uuid 다름
c9e = moved([OTHER], lambda s: s.rec(OTHER, json.dumps({"name": SEAT, "uuid": LATE})))   # ⑨5 기록 name = 좌석 자신(uuid 같음)
c9f = moved([OTHER], lambda s: s.rec(OTHER, "{"))                         # ⑨6 기록 JSON 깨짐 → 예외 0
c9g = moved([OTHER, SEAT], lambda s: s.rec(OTHER), pad=66 * 1024)        # ⑨7 앞 «…-pi#3»(기록 uuid 같음) · 66KB · 뒤 좌석 이름(DA R1 · 후계가 이어 씀)


def c9h(tmp, bindir=BIN):   # ⑨8 기록 uuid 같음 · session_info 가 66KB 본문 뒤에만 → 뺌(파일 전체 읽기)
    s = Seat(tmp, bindir)
    s.late([OTHER], pad=66 * 1024, lead=True)
    s.rec(OTHER)
    bound(s)


def c9o(tmp, bindir=BIN):   # DA 칸 — 기록 폴더 밖 이름(../·절대 경로·..) = 읽기 0 · 증명 0 → «세션 바뀜»
    s = Seat(tmp, bindir)
    up, ab = "../escape", str(tmp / "abs")
    s.late([up, ab, ".."])
    s.rec(up, json.dumps({"name": up, "uuid": LATE}), at=s.rd.parent / "escape.json")
    s.rec(ab, json.dumps({"name": ab, "uuid": LATE}), at=Path(ab + ".json"))
    s.rec("..", json.dumps({"name": "..", "uuid": LATE}), at=s.rd.parent / "seat-resume" / "...json")
    assert s.run() == MOVED


def mod(s):   # bin 사본 ft_seat_pi_ft2 를 모듈로(직접 호출 칸)
    spec = importlib.util.spec_from_file_location("f2_%d" % id(s), str(s.bin / "ft_seat_pi_ft2.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def c9k(tmp, bindir=BIN, mp=None):   # DA 칸 — 같은 이름 2931번 = 기록 열쇠 1개만 읽음 · 폴더 순회 0
    s = Seat(tmp, bindir)
    f = s.late([OTHER] * 2931)
    s.rec(OTHER, uuid="other-uuid")
    mp.setenv("ZC_RESUME_DIR", str(s.rd))
    reads, raw = [], Path.read_text
    mp.setattr(Path, "read_text", lambda self, *a, **k: reads.append(self) or raw(self, *a, **k))
    for verb in ("iterdir", "glob", "rglob"):
        mp.setattr(Path, verb, lambda *a, **k: pytest.fail("폴더 순회"))
    assert mod(s).proven(f, LATE, SEAT, 10 ** 12) is False and reads == [s.rd / (OTHER + ".json")], reads


def c9t(tmp, bindir=BIN, mp=None):   # ⑨ 판독 합계 7초 넘음 = 판정 불가(ValueError) · «세션 바뀜»·결속 0
    s = Seat(tmp, bindir)
    s.late([OTHER])
    s.rec(OTHER)
    mp.setenv("ZC_RESUME_DIR", str(s.rd))
    m = mod(s)
    m.CAP = -1   # 남은 몫 0 = 첫 줄에서 상한 넘음
    intent = json.loads(next((tmp / "ft2root").rglob("*.intent")).read_text(encoding="utf-8"))
    with pytest.raises(ValueError, match="이름 판독"):
        m.first_session((intent, "5101", str(s.wt)), s.sess)


def budget(sec):   # DA R1 — 마지막 기록 읽기가 sec 초 걸림(주입 시계 · sleep 0) · 1초 = 결속 · 8초 = 판정 불가 · 결속 0
    def case(tmp, bindir=BIN, mp=None):
        s = Seat(tmp, bindir)
        s.late([OTHER])
        s.rec(OTHER)
        mp.setenv("ZC_RESUME_DIR", str(s.rd))
        m, clock, raw = mod(s), [0.0], Path.read_text
        m.time = type("T", (), {"monotonic": staticmethod(lambda: clock[0])})
        mp.setattr(Path, "read_text", lambda self, *a, **k: (raw(self, *a, **k), clock.__setitem__(0, clock[0] + sec if self.parent == s.rd else clock[0]))[0])
        intent = json.loads(next((tmp / "ft2root").rglob("*.intent")).read_text(encoding="utf-8"))
        if sec < m.CAP:
            assert m.first_session((intent, "5101", str(s.wt)), s.sess)[0] == str(s.first) and clock[0] == sec
            return
        with pytest.raises(ValueError, match="이름 판독"):
            m.first_session((intent, "5101", str(s.wt)), s.sess)
    return case


CASES = {"⑧": c8, "⑨1": c9a, "⑨2": c9b, "⑨3": c9c, "⑨4": c9d, "⑨5": c9e, "⑨6": c9f, "⑨7": c9g, "⑨8": c9h, "⑨o": c9o}
DIRECT = {"⑨k": c9k, "⑨t": c9t, "⑨b1": budget(1), "⑨b8": budget(8)}
F2 = "ft_seat_pi_ft2.py"
MUTANTS = {"M4": ("late = [sid for sid, path in late if not proven(path, sid, seat, end)]", "late = [sid for sid, path in late]", "⑧"),
           "M5": ('rec.get("name") == name and ', "", "⑨5"),
           "M6": ('                got.append(rec["name"].strip() if isinstance(rec.get("name"), str) else "")\n',
                  '                return [rec["name"].strip() if isinstance(rec.get("name"), str) else ""]\n', "⑨7"),
           "M7": (' and rec.get("uuid") == sid', "", "⑨4"),
           "M8": ("if name and record(name, sid, end):", "if name:", "⑨3"),
           "Mo": ('    if Path(name).name != name or name in (".", ".."):\n        return False\n', "", "⑨o"),   # DA 칸 덧 변이 — 폴더 밖 가드 지움
           "Mk": ("for name in dict.fromkeys(got):", "for name in got:", "⑨k"),   # DA 칸 덧 변이 — 열쇠 중복 제거 지움
           "Mb": (("    due(end)   # DA R1 — 기록 읽기·해석 뒤\n", "    due(end)   # DA R1 — 증명·결속 성공 전\n"), ("", ""), "⑨b8")}   # DA R1 — 읽기 뒤·결속 전 상한 확인 지움(읽기 전 확인만 남김)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](tmp_path)


@pytest.mark.parametrize("name", list(DIRECT))
def test_direct(name, tmp_path, monkeypatch):
    DIRECT[name](tmp_path, mp=monkeypatch)


def test_bin_equals_kit():   # kit 사본 맞춤
    kit = BIN.parent / "kit" / "fable-team" / "bin" / F2
    assert (BIN / F2).read_bytes() == kit.read_bytes()


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    mut = tmp_path / "mbin"
    mut.mkdir()
    for f in FILES:
        shutil.copy(BIN / f, mut / f)
    text = (mut / F2).read_text(encoding="utf-8")
    for o, n in zip(*((old, new) if isinstance(old, tuple) else ((old,), (new,)))):   # 여러 자리 변이 = 표지마다 1개
        assert text.count(o) == 1, (name, o)
        text = text.replace(o, n)
    (mut / F2).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    run = (lambda w, *b: DIRECT[case](w, *b, mp=monkeypatch)) if case in DIRECT else CASES[case]
    with pytest.raises((AssertionError, pytest.fail.Exception)):
        run(tmp_path / "w1", mut)
    monkeypatch.undo()
    run(tmp_path / "w2")   # 원본으로 같은 사례 1회 더 = PASS
