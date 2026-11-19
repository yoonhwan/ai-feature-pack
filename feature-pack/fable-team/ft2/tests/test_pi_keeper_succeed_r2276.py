"""r2276 ft2 keeper 승계 갈래 — 대화창 한도(증류 미완 표식) 나노를 후계 나노로 잇는다 (카드 반례 ①~⑧ · 사전 DA#28 APPROVE-DESIGN).
입력 = r1813 시험 대역(World: 실제 core · 실제 launch.py · 가짜 tmux·ps·세션 파일 · 주입 시계) + 업무 repo 의 bare 원격(실제 git push).
tmux 대역 2칸 더함 = #{pane_current_path}(cwd 표) · nokill(kill 뒤에도 생존). sleep 0 · 실 tmux·pi 0. 기준판(승계 갈래 없음) = ① Red.
변이 M1~M3 = 자매 파일 test_pi_keeper_succeed_mut_r2276.py(70초 나눔).
"""
import importlib.util, json, os, subprocess  # noqa: E401
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r1813_world_for_r2276", str(FT2 / "tests" / "test_pi_keeper_stall_r1813.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
W, M, H0, H1, T0, TEAM = B.W, B.M, B.H0, B.H1, B.T0, B.TEAM
W2, SLICE = "r9813-r2", "slice8"   # ① M6-c 꼴 — claim 으로 받은 work · holder 의 원래 intent = 다른 work(slice8)
TMUX = B.TMUX.replace('if a[0] == "kill-session": d["alive"].remove(name)',
                      'if a[0] == "kill-session" and not d.get("nokill"): d["alive"].remove(name)').replace(
    'if a[0] == "display-message":',
    'if a[0] == "display-message" and "#{pane_current_path}" in a: sys.stdout.write(d.get("cwd", {}).get(name, "") + "\\n")\nelif a[0] == "display-message":')


def world(tmp, mp, ft2=FT2):
    """r1813 World + bare 원격(origin · main push) + 늘린 tmux 대역."""
    w = B.World(tmp, mp, ft2)
    B._put(tmp / "bin" / "tmux", TMUX.replace("__PY__", __import__("sys").executable))
    w.bare = tmp / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", str(w.bare)], check=True, timeout=25)
    B._git(w.repo, "remote", "add", "origin", str(w.bare))
    B._git(w.repo, "push", "-q", "origin", "main")
    return w


def remote(w, work):
    done = subprocess.run(["git", "-C", str(w.bare), "rev-parse", "--verify", "-q", "refs/heads/nano/%s" % work], capture_output=True, text=True, timeout=25)
    return done.stdout.strip()


def marker(w, age, seat=H0):
    path = w.root / ".fable-team" / "state" / "pi-distill-pending" / seat.rsplit("#", 1)[0]
    B._put(path, "2026-01-01T00:00:00Z seat=%s ctx=900000 증류 미완\n" % seat)
    os.utime(path, (T0 - age, T0 - age))


def tm(w, **kv):
    B._put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), **kv))


def claimed(w, effect=False):
    """① 꼴 — submit → claim(H0 · gen1) → start(→ effect) · dispatch 0 · 그 work 의 intent 0 · H0 원래 intent = slice8 worktree · 로컬 커밋 1."""
    for argv in (["submit", "--command", "c-" + W2, "--body", "본문", "--work", W2], ["claim", "--work", W2, "--holder", H0],
                 ["start", "--work", W2, "--holder", H0, "--gen", "1"]) + ((["effect", "--work", W2, "--holder", H0, "--gen", "1", "--effect", "push"],) if effect else ()):
        assert w.cli(T0 - 40 * M, *argv)[1] == 0, argv
    tree = w.root / ".fable-team" / "teams" / TEAM / "worktrees" / ("%s@a1" % SLICE)
    B._git(w.repo, "worktree", "add", "-q", "--detach", str(tree), w.c1)
    w.c2 = (B._git(tree, "commit", "-q", "--allow-empty", "-m", "c2", at=T0 - 20 * M), B._git(tree, "rev-parse", "HEAD"))[1]
    B._put(w.runtime() / "launch" / ("%s@a1.intent" % SLICE), {"FT2_HOLDER": H0, "state": "opened", "worktree": str(tree), "at": "2026-01-01T00:00:00"})
    tm(w, alive=[H0])
    return tree


def dispatches(w, work):
    return [r for r in w.journal() if r["kind"] == "dispatch" and r.get("work") == work]


def succeeded(w, work, lines):
    """① · ⑥ 공통 결과 — push(원격 = 구 HEAD) · kill 1 · assign(H1 · rotation) · deliver · launch --base 구 HEAD · 인계 3줄 · SUCCEEDED 1줄."""
    assert [x for x in lines if x.startswith("SUCCEEDED harness %s %s -> %s" % (work, H0, H1))], lines
    assert remote(w, work) == w.c2
    assert [x["a"][-1] for x in w.tmux("kill-session")] == ["=" + H0] and len(w.tmux("new-session")) == 1
    last = dispatches(w, work)[-1]
    assert last["holder"] == H1 and w.journal()[-1]["kind"] == "deliver" and w.journal()[-1]["work"] == work
    intent = json.loads((w.runtime() / "launch" / ("%s@%s.intent" % (work, last["attempt"]))).read_text(encoding="utf-8"))
    assert intent["base_sha"] == w.c2 and intent["FT2_HOLDER"] == H1
    text = "\n".join(w.notes())
    hand = text[text.index("send %s " % H1):]
    assert "구 좌석 %s" % H0 in hand and "구 HEAD %s · 원격 가지 nano/%s" % (w.c2, work) in hand and "/대기/%s.md" % work in hand, hand


def untouched(w, work, pushed=False):
    """승계 0 — kill 0 · 새 배정 0 · (pushed=False 면) 원격 가지 0."""
    assert w.tmux("kill-session") == [] and not [r for r in dispatches(w, work) if r["holder"] == H1]
    assert pushed or remote(w, work) == ""


def c1(w):   # ① M6-c 재생 — claim 행만(dispatch 0) · 표식 10분 · Working 0 · 로컬 커밋 1 · 원격 가지 0 → 승계 1
    claimed(w), marker(w, 10 * M)
    succeeded(w, W2, w.round())


def c1b(w):  # ①′ 원격 가지 = 승계 뒤 구 HEAD(M1 짝)
    claimed(w), marker(w, 10 * M), w.round()
    assert remote(w, W2) == w.c2


def c2(w):   # ② 표식 10분 · Working → 승계 0(push 0 포함) · 표식 2분 → 승계 0
    claimed(w), marker(w, 10 * M), tm(w, pane={H0: "⠋ Working...\n"})
    assert not [x for x in w.round() if x.startswith("SUCCEEDED")]
    untouched(w, W2)
    tm(w, pane={}), marker(w, 2 * M)
    assert not [x for x in w.round(M) if x.startswith("SUCCEEDED")]
    untouched(w, W2)


def c2c(w):  # ②ⓒ 표식 10분 + 진척 0 20분(dispatch 있는 work) → 승계 1 · 깨움·S3 0(같은 바퀴)
    w.seat(step=-20 * M), marker(w, 10 * M)
    lines = w.round()
    succeeded(w, W, lines)
    assert not [x for x in lines if x.startswith(("WOKE", "REASSIGNED"))] and w.tmux("send-keys") == []


def c3(w):   # ③ push 거절(원격이 앞섬 · non-ff) → 승계 0 · kill 0 · [크리티컬] «승계 막힘 · push 거절» 1통
    tree = claimed(w)
    other = w.tmp / "other"
    B._git(w.repo, "worktree", "add", "-q", "--detach", str(other), w.c1)
    B._git(other, "commit", "-q", "--allow-empty", "-m", "far", at=T0 - 30 * M)
    B._git(other, "push", "-q", "origin", "HEAD:refs/heads/nano/%s" % W2)
    far = remote(w, W2)
    marker(w, 10 * M), w.round()
    untouched(w, W2, pushed=True)
    assert remote(w, W2) == far and B._git(tree, "rev-parse", "HEAD") == w.c2
    notes = [x for x in w.notes() if "승계 막힘" in x]
    assert len(notes) == 1 and "승계 막힘 · push 거절" in notes[0], w.notes()


def c4(w):   # ④ worktree dirty → 승계 0 · kill 0 · [크리티컬] «승계 막힘 · dirty» 1통
    tree = claimed(w)
    (tree / "dirt.txt").write_text("x", encoding="utf-8")
    marker(w, 10 * M), w.round()
    untouched(w, W2)
    notes = [x for x in w.notes() if "승계 막힘" in x]
    assert len(notes) == 1 and "승계 막힘 · dirty" in notes[0], w.notes()


def c5(w):   # ⑤ kill 뒤 probe absent 아님 → assign 0 · [크리티컬]
    claimed(w), marker(w, 10 * M), tm(w, nokill=True)
    w.round()
    assert len(w.tmux("kill-session")) == 1 and dispatches(w, W2) == [] and len(w.tmux("new-session")) == 0
    assert [x for x in w.notes() if "[크리티컬]" in x and "부재 확인 없음" in x], w.notes()


def c5b(w):  # ⑤ⓑ 구 holder 가 effect 줄 뒤 result 0 → kill 0 · assign 0 · [크리티컬] «승계 막힘 · 효과 미확정» 1통
    claimed(w, effect=True), marker(w, 10 * M), w.round()
    untouched(w, W2)
    notes = [x for x in w.notes() if "승계 막힘" in x]
    assert len(notes) == 1 and "승계 막힘 · 효과 미확정" in notes[0], w.notes()


def c6(w):   # ⑥ dispatch 행 있는 work(일반 keeper 열기 꼴 · 진척 2분 전) → ①과 같은 결과
    w.seat(step=-2 * M), marker(w, 10 * M)
    succeeded(w, W, w.round())


def _state(w, **kv):
    B._put(w.root / ".fable-team" / "state" / "ft2-keeper" / "state.json", kv)


def c7(w):   # ⑦ 같은 work 같은 날 4번째 승계 → 0 · [크리티컬]
    day = B._stamp(T0)[:10]
    _state(w, succeeded={"%s|%s|g%d" % (TEAM, W2, g): {"at": day + "T00:00:0%d" % g} for g in (7, 8, 9)})
    claimed(w), marker(w, 10 * M), w.round()
    untouched(w, W2)
    assert [x for x in w.notes() if "[크리티컬]" in x and "하루 승계 3회" in x], w.notes()


def c7b(w):  # ⑦′ S4 키(reassigned) 와 섞이지 않음 — S3 재배정 1회 기억 뒤에도 승계 1회
    _state(w, reassigned={"%s|%s" % (TEAM, W2): {"at": B._stamp(T0 - 60 * M), "from": "x#0", "to": H0}})
    claimed(w), marker(w, 10 * M)
    succeeded(w, W2, w.round())


def c8(w):   # ⑧ 표식 없음 · 진척 0 16분 → 승계 갈래 0 · 기존 S1 길(깨움) 그대로
    w.seat(step=-16 * M)
    lines = w.round()
    assert ("WOKE harness %s %s" % (W, H0)) in lines and not [x for x in lines if x.startswith(("SUCCEEDED", "HELD-SUCCEED"))]
    assert remote(w, W) == ""


def c8b(w):  # ⑧′ 장부 못 읽음 대역 → 판정 불가 1줄 · 쓰기 0
    claimed(w), marker(w, 10 * M)
    before = len(w.journal())
    (w.runtime() / "state.json").write_text("{깨짐", encoding="utf-8")
    lines = w.round()
    assert [x for x in lines if x.startswith("판정 불가 harness")] and not [x for x in lines if "SUCCEEDED" in x], lines
    assert len(w.journal()) == before and w.tmux("kill-session") == [] and remote(w, W2) == ""


CASES = {"①": c1, "①′": c1b, "②": c2, "②ⓒ": c2c, "③": c3, "④": c4, "⑤": c5, "⑤ⓑ": c5b, "⑥": c6, "⑦": c7, "⑦′": c7b, "⑧": c8, "⑧′": c8b}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))
