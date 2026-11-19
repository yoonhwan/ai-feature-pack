"""r2281 ft2 keeper — 승계 끝 구 나노 닫기: 재개 기록 먼저 → tmux 세션만 kill (카드 반례 ①~⑦ · ⑧ = 기존 시험 재실행 목록).
대역 = r1812 keeper_world(실제 core 장부 · 가짜 tmux · 주입 시계) + BYZ 대역 clone 의 실제 git worktree 2개(구 @a1 · 후계 @a2) + seat-resume 폴더(FT2_SEAT_RESUME_DIR).
실 tmux·실 명부·실 seat-resume 0 · sleep 0. 기준판(갈래 없음) = ① Red. 변이 M1~M4 = 자매 파일 test_pi_keeper_close_old_mut_r2281.py.
"""
import json
import os
from pathlib import Path

import pytest

import keeper_world_r1812 as kw

TEAM, W = kw.TEAM, "r9281"
S, H = "byz-harness-nano-r9281-t#1", "byz-harness-nano-r9281-t#2"
UUID = "0b9e2c1a-7d4f-4e21-9a3b-5c6d7e8f9012"
IDLE = "✻ Brewed for 3s\n❯ "


def _git(cwd, *a):
    return kw._git(cwd, *a)


def tree(w, attempt):
    return w.root / ".fable-team" / "teams" / TEAM / "worktrees" / ("%s@%s" % (W, attempt))


def session(w, folder, name="2026-11-13T00-00-00-000Z_%s.jsonl" % UUID, turn="stop", age=7200):
    """pi 세션 파일 1개(--<cwd>-- 폴더) · 마지막 줄 stopReason = turn · mtime = 지금 - age."""
    log = Path(w.env["FT2_PI_SESSIONS"]) / ("--%s--" % str(folder).strip("/").replace("/", "-")) / name
    rows = [{"type": "session", "id": UUID}, {"type": "model_change", "modelId": "opus-5-5"},
            {"type": "message", "message": {"role": "assistant", "stopReason": turn}}]
    kw._put(log, "".join(json.dumps(x) + "\n" for x in rows))
    os.utime(log, (w.t - age, w.t - age))
    return log


def world(tmp, mp, ft2=kw.FT2, new=H, ancestor=True, files=1, pane=IDLE, turn="stop", att=0):
    """구 S(@a1 · 로컬 커밋 1) · 후계 new(@a2 · ancestor 면 S HEAD 위 커밋 1 · 아니면 main 위) · 장부 = S 배정 → new 교대 배정(최신 dispatch holder)."""
    w = kw.World(tmp, mp, ft2)
    for key, val in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        _git(w.root, "config", key, val)
    for argv in (["submit", "--command", "c-" + W, "--body", "b", "--work", W], ["assign", "--work", W, "--holder", S, "--evidence", "v1,v2"],
                 ["deliver", "--work", W], ["assign", "--work", W, "--holder", new, "--evidence", "v1,v2", "--rotation", "true"], ["deliver", "--work", W]):
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    kw._put(w.state / "ft20-switch" / (TEAM + ".json"), "{}")
    main = _git(w.root, "rev-parse", "HEAD")
    _git(w.root, "worktree", "add", "-q", "--detach", str(tree(w, "a1")), main)
    _git(tree(w, "a1"), "commit", "-q", "--allow-empty", "-m", "old")
    w.old = _git(tree(w, "a1"), "rev-parse", "HEAD")
    _git(w.root, "worktree", "add", "-q", "--detach", str(tree(w, "a2")), w.old if ancestor else main)
    _git(tree(w, "a2"), "commit", "-q", "--allow-empty", "-m", "new")
    for attempt, holder, at in (("a1", S, "2026-01-01T00:00:00"), ("a2", new, "2026-01-02T00:00:00")):
        kw._put(w.runtime() / "launch" / ("%s@%s.intent" % (W, attempt)), {"FT2_HOLDER": holder, "state": "opened", "worktree": str(tree(w, attempt)), "at": at})
    for n in range(files):
        session(w, tree(w, "a1"), turn=turn) if n == 0 else session(w, tree(w, "a1"), name="2026-11-13T01-00-00-000Z_x%d.jsonl" % n, age=3600)
    session(w, tree(w, "a2"), turn="", age=60)   # 후계 = 일하는 중(턴 열림)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d.update(alive=[S, new], pane={S: pane, new: "⠋ Working...\n"}, att={S: att})
    kw._put(w.tm, d)
    w.rs = tmp / "resume"
    w.env["FT2_SEAT_RESUME_DIR"] = str(w.rs)
    w.branches = _git(w.root, "for-each-ref", "--format=%(refname)")
    return w


def kills(w):
    return [a[-1] for a in w.tmux("kill-session")]


def rec(w):
    path = w.rs / (S + ".json")
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def closed(w, lines):
    """① 결과 — 재개 기록 1(검증 칸) · kill 1(=S) · CLOSED-SUCCEEDED 1줄 · 가지·worktree·ref 그대로."""
    assert [x for x in lines if x.startswith("CLOSED-SUCCEEDED")] == ["CLOSED-SUCCEEDED %s %s %s -> %s" % (TEAM, W, S, H)], lines
    assert kills(w) == ["=" + S]
    doc = rec(w)
    assert doc and doc["name"] == S and doc["engine"] == "pi" and doc["uuid"] == UUID and doc["retired_by"] == H, doc
    assert doc["cwd"] == str(tree(w, "a1")) and os.path.isfile(doc["jsonl"]) and doc["model"] == "opus-5-5" and doc["binding"], doc
    assert tree(w, "a1").is_dir() and _git(tree(w, "a1"), "rev-parse", "HEAD") == w.old
    assert _git(w.root, "for-each-ref", "--format=%(refname)") == w.branches


def untouched(w, lines, record=False):
    assert kills(w) == [] and not [x for x in lines if x.startswith("CLOSED-SUCCEEDED")], lines
    assert (rec(w) is not None) == record


def c1(w):    # ① 유휴 · clean · S HEAD ⊂ H HEAD · jsonl 1 → 기록 1 + kill 1 + 닫기 줄 1
    closed(w, w.round())


def c2(w):    # ② H 가 다른 계보 → 손 0 · 줄 0
    lines = w.round()
    untouched(w, lines)
    assert not [x for x in lines if S in x and x.startswith(("WORKING", "판정 불가"))], lines


def c3(w):    # ③ S dirty → 닫기 0 · keep 1줄
    kw._put(tree(w, "a1") / "dirty.txt", "x")
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if x.startswith("WORKING %s keep dirty" % TEAM) and S in x], lines


def c3b(w):   # ③ⓑ S HEAD ⊄ H HEAD ∧ 로컬 ref 끝 아님 → 닫기 0 · keep 1줄
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if x.startswith("WORKING %s keep not-ancestor" % TEAM) and S in x], lines


def c3c(w):   # ③ⓒ H 가 main 위(S HEAD ⊄ H HEAD) ∧ S HEAD = nano/<work> 끝 → 닫기 1
    _git(w.root, "branch", "nano/" + W, w.old)
    w.branches = _git(w.root, "for-each-ref", "--format=%(refname)")
    closed(w, w.round())


def c3d(w):   # ③ⓒ′ S HEAD = refs/ft2/keep/ ref 끝 → 닫기 1
    _git(w.root, "update-ref", "refs/ft2/keep/%s-%s" % (W, w.old[:12]), w.old)
    w.branches = _git(w.root, "for-each-ref", "--format=%(refname)")
    closed(w, w.round())


def c4(w):    # ④ S pane Working → 닫기 0 · 기록 0
    untouched(w, w.round())


def c5(w):    # ⑤ jsonl 없음 → 기록 0 · 닫기 0 · 판정 불가 1줄(C3 턴 끝 근거 없음이 C4 앞에서 먼저 걸림)
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if S in x and "판정 불가 · Pi 턴 끝 근거 없음(세션 파일 없음" in x], lines


def c5d(w):   # ⑤′ jsonl 있음 · mtime < S session_created(앞선 좌석 파일) → C4 판정 불가 1줄 · 기록 0 · kill 0
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["born"] = {S: int(w.t - 3600)}
    kw._put(w.tm, d)
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if x.startswith("판정 불가 %s %s %s 재개 기록 jsonl 1개" % (TEAM, W, S))], lines


def c5b(w):   # ⑤ⓑ 기록 쓰기 실패(폴더 자리에 일반 파일) → 닫기 0 · 판정 불가 1줄
    kw._put(w.rs, "not a folder")
    lines = w.round()
    assert kills(w) == [] and [x for x in lines if x.startswith("판정 불가 %s %s %s 재개 기록 쓰기" % (TEAM, W, S))], lines


def c5c(w):   # ⑤ⓒ 같은 pi 세션 폴더에 jsonl 2개 → 판정 불가 1줄 · 기록 0 · kill 0
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if x.startswith("판정 불가 %s %s %s 재개 기록 jsonl 2개" % (TEAM, W, S))], lines


def c6(w):    # ⑥ 같은 name · uuid 기록 이미 있음 → 다시 쓰기 0 · 닫기 1
    log = session(w, tree(w, "a1"))
    kw._put(w.rs / (S + ".json"), {"name": S, "engine": "pi", "uuid": UUID, "jsonl": str(log), "cwd": str(tree(w, "a1")), "model": "opus-5-5", "retired_by": H, "at": "x", "binding": {"k": 1}})
    os.utime(w.rs / (S + ".json"), (1, 1))
    closed(w, w.round())
    assert os.path.getmtime(w.rs / (S + ".json")) == 1 and rec(w)["at"] == "x"


def c7(w):    # ⑦ ALL_STOP → «예정» 줄 · kill 0 · 기록 0
    kw._put(w.state / "ALL_STOP.json", {"since": 1, "reason": "시험"})
    lines = w.round()
    untouched(w, lines)
    assert [x for x in lines if x.startswith("예정 CLOSED-SUCCEEDED %s %s %s" % (TEAM, W, S))], lines


CASES = {"①": (c1, {}), "②": (c2, {"new": "byz-harness-nano-r9999-t#2"}), "②′": (c2, {"new": "byz-harness-nano-r9281-t#0"}),
         "③": (c3, {}), "③ⓑ": (c3b, {"ancestor": False}), "③ⓒ": (c3c, {"ancestor": False}), "③ⓒ′": (c3d, {"ancestor": False}),
         "④": (c4, {"pane": "⠋ Working...\n"}), "④ⓑ": (c4, {"turn": "toolUse"}), "④ⓒ": (c4, {"att": 1}),
         "⑤": (c5, {"files": 0}), "⑤′": (c5d, {}), "⑤ⓑ": (c5b, {}), "⑤ⓒ": (c5c, {"files": 2}), "⑥": (c6, {}), "⑦": (c7, {})}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    case, kv = CASES[name]
    case(world(tmp_path, monkeypatch, **kv))
