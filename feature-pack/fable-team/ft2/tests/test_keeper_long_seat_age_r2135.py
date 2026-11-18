"""r2135 keeper 장기 좌석 세션 나이 — 일을 든 장기 좌석(tester 등 · 나노 아님)은 좌석 jsonl 로 나이를 재고 settle 길 kill·park 0 (카드 반례 ①~⑤ · 변이 M1~M3).
대역 = r2055 settle 시험 world(임시 root · 가짜 tmux · 임시 FT2_PI_SESSIONS · 임시 FT2_SEAT_RESUME_DIR) · 실 tmux·실 runtime·실 우편함 0 · sleep 0(시계 = 주입 w.t).
좌석 폴더 A = 가짜 tmux session_path(기본 /seats/<이름>) · 일 폴더 B = intent.worktree(실 clone · push). 기준판(팩 origin/main def04ff1) = ① Red.
"""
import importlib.util
import json
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2135_settle_cases", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
t = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t)
kw, TEAM, FT2 = t.kw, t.TEAM, t.FT2
TESTER = "byz-room-tester-pi#24"   # 카드 ① holder(room tester · 실사건 #321379)


def jsonl(path, age, w, turn="stop"):
    """pi 세션 파일 1개 = 시작 줄 + assistant 마지막 줄 · mtime = 시계 − age."""
    kw._put(path, '{"type": "session"}\n' + json.dumps({"type": "message", "message": {"role": "assistant", "stopReason": turn}}) + "\n")
    os.utime(path, (w.t - age, w.t - age))
    return path


def seat_folder(w, seat, cwd=None):
    """좌석 폴더 A 의 pi 세션 폴더(가짜 tmux session_path 기본 = /seats/<이름>)."""
    return Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % (cwd or "/seats/" + seat).strip("/").replace("/", "-"))


def long_seat(w, work, holder=TESTER, age=600, turn="stop"):
    """일을 든 장기 좌석 1석 — 접수 → 배정(holder) → 전달 · 일 폴더 B(실 clone · push · jsonl 0) · intent · 좌석 폴더 A 에 jsonl 1개."""
    for argv in (["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
                 ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2", "--resources", "R-" + work], ["deliver", "--work", work]):
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    path, base = w.tmp / "wt" / work, t.git(w.tmp / "seed-byz", "rev-parse", "main")
    t.git(w.tmp, "clone", "-q", str(w.tmp / "byz.git"), str(path))
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        t.git(path, "config", k, v)
    t.git(path, "checkout", "-q", "-b", "nano/" + work)
    kw._put(path / "x.txt", work), t.git(path, "add", "-A"), t.git(path, "commit", "-q", "-m", "x"), t.git(path, "push", "-q", "origin", "nano/" + work)
    kw._put(w.runtime() / "launch" / ("%s@a1.intent" % work), {"FT2_HOLDER": holder, "state": "opened", "at": "2026-01-01T00:00:00",
                                                               "base": "origin/main", "base_sha": base, "worktree": str(path)})
    jsonl(seat_folder(w, holder) / "s.jsonl", age, w, turn)   # A — intent at 뒤(시계 2026-11) · World.round 는 있는 파일을 덮지 않음
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"], d["pane"][holder] = d["alive"] + [holder], t.IDLE_PANE
    kw._put(w.tm, d)
    return holder


def alerts(w):
    """[긴급] 쪽지 — stall S3 body-unreached 는 뺀다(실좌석 = tmuxc 가 심은 TMUXC_PI_SESSION_ID 로 세션 파일을 찾음 · 가짜 tmux show-environment = 빈 출력 · 이 카드 범위 밖)."""
    return [x for x in t.sent(w) if "긴급" in x and "body-unreached" not in x]


def c1(w):   # ① 장기 좌석 · B jsonl 0 · A jsonl 600초 stop → session-none 0 · WORKING(PARK_IDLE 안쪽) · [긴급] 0
    long_seat(w, "r9601")
    lines = t.two(w)
    assert not t.has(lines, "session-none") and t.has(lines, "WORKING harness r9601 %s" % TESTER, "jsonl-active"), lines
    assert not alerts(w) and not w.tmux("kill-session"), (alerts(w), lines)


def c2(w):   # ② seat-resume jsonl 칸 = 실재 파일(resume_ok 통과) → 그 파일 나이(600초) · session_path 폴더(A 7200초) 안 봄
    long_seat(w, "r9602", age=7200)
    cwd = str(w.root / ".worktrees" / "room-tester-24")
    log = jsonl(seat_folder(w, TESTER, cwd) / "2026-11-17_u-24.jsonl", 600, w)
    kw._put(w.tmp / "resume" / (TESTER + ".json"), {"name": TESTER, "uuid": "u-24", "engine": "pi", "cwd": cwd, "jsonl": str(log)})
    lines = t.two(w)
    assert t.has(lines, "WORKING harness r9602 %s" % TESTER, "jsonl-active") and not t.has(lines, "session-none"), lines
    assert not w.tmux("kill-session") and not alerts(w), lines


def c3(w):   # ③ A 폴더를 쓰는 살아 있는 byz 세션 2개 · jsonl < PARK_IDLE → 못 정함 → 지금처럼 session-none
    long_seat(w, "r9603")
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    other = "byz-room-tester-pi#25"
    d["alive"], d["pane"][other], d.setdefault("path", {})[other] = d["alive"] + [other], t.IDLE_PANE, "/seats/" + TESTER
    kw._put(w.tm, d)
    lines = t.two(w)
    assert t.has(lines, "UNKNOWN harness r9603 %s session-none" % TESTER), lines


def c4(w):   # ④ A jsonl 무활동 ≥ PARK_IDLE(3700초) · 안전 조건 통과 → kill 0 · park 0 · WORKING protected 1줄 · [긴급] 0
    long_seat(w, "r9604", age=3700)
    lines = t.two(w)
    got = t.has(lines, "WORKING harness r9604 %s protected" % TESTER, "나노만 닫는다", "kill·park 0")
    assert len(got) == 1 and not w.tmux("kill-session") and w.kinds("parked") == 0, lines
    assert not alerts(w) and not t.has(lines, "session-none") and not t.has(lines, "PARKED harness r9604"), (alerts(w), lines)


def c5(w):   # ⑤ 나노 holder · B jsonl ≥ PARK_IDLE · 좌석 폴더 A 에 더 새 jsonl → B 로 판독 · kill 1 · park 1(기준판과 같은 판정 줄)
    holder = t.nano(w, "r9605")
    jsonl(seat_folder(w, holder) / "s.jsonl", 60, w)
    lines = t.two(w)
    assert t.has(lines, "PARKED harness r9605 %s idle-done" % holder) and len(w.tmux("kill-session")) == 1 and w.kinds("parked") == 1, lines


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}
KS, KC = "adapters/pi/keeper_settle.py", "adapters/pi/keeper_close.py"
MUTANTS = {"M1": ([(KS, "if long_seat(holder):   # r2135 L1", "if False:   # r2135 L1"),
                   (KC, "if settle.long_seat(holder):   # r2135 L1", "if False:   # r2135 L1")], c1),
           "M2": ([(KS, "if long_seat(holder):   # r2135 L2", "if False:   # r2135 L2")], c4),
           "M3": ([(KS, "return bool(holder) and not (", "return True or not (")], c5)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](t.world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    """변이 사본에서 그 사례 FAIL · 원본으로 같은 사례 1회 더 = PASS(반대 결과 대조)."""
    edits, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    for rel, old, new in edits:
        text = (tree / rel).read_text(encoding="utf-8")
        assert text.count(old) == 1, (name, rel, old)
        (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(t.world(tmp_path / "w1", monkeypatch, tree))
    case(t.world(tmp_path / "w2", monkeypatch))
