"""r1960 keeper — 일이 끝난 나노 자리는 어떤 결과로 끝났든 닫는다 (카드 반례 ①~⑥ · 변이 M1~M6).
대역 = r1812 World(임시 BYZ·팩 리포 · 가짜 tmux·쪽지 · 실제 core) + r1813 World(⑤ 멈춤 갈래 · noecho tmux) · 실 세션 0 · sleep 0.
① 조상 검사 = 팩 리포 worktree(intent base_sha · HEAD) · ④ r1951 꼴 = submit→assign(a2 같은 holder)→deliver→complete a2 · intent @a1 만.
기준판(keeper_endings 없음) = 반례 전부 Red. 변이 바늘 = [fix] 가 담을 줄(사본에서만 고치고 원본으로 1회 더 = PASS).
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]


def _mod(name):
    spec = importlib.util.spec_from_file_location("r1960_" + name, str(FT2 / "tests" / name))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


kw, B = _mod("keeper_world_r1812.py"), _mod("test_pi_keeper_stall_r1813.py")
TEAM, _git, _lines, _put = kw.TEAM, kw._git, kw._lines, kw._put
ID = ["-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"]


def tree(w, work, new=True, land=True):
    """팩 worktree 1개(base = 팩 main 끝) · new = 새 커밋 1 · land = 그 HEAD 를 팩 main 에 push(아니면 main 만 다른 커밋으로 전진 = squash 꼴)."""
    base, pack, path = w.pack_sha(), w.tmp / "pack", w.tmp / "wt" / work
    _git(pack, "fetch", "-q", "origin"), _git(pack, "worktree", "add", "-q", "--detach", str(path), base)
    if new:
        _git(path, *ID, "commit", "-q", "--allow-empty", "-m", "n-" + work)
    _git(path, "push", "-q", "origin", "HEAD:main") if new and land else w.pack_sha() if new else None
    body = {"FT2_HOLDER": "byz-harness-nano-%s-t#0" % work, "state": "opened", "worktree": str(path), "at": "2026-01-01T00:00:00", "base_sha": base}
    _put(w.runtime() / "launch" / ("%s@a1.intent" % work), body)


def refuse(w, work):
    out, rc = w.CLI.run(["refuse", "--work", work, "--place", "keeper", "--gen", "1", "--cause", "c", "--artifact", "a", "--event", "e-" + work,
                         "--root", str(w.root), "--team", TEAM])
    assert rc == 0, out


def card(w, work, last):
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/harness/indices/진행/%s-x.md" % work: "# 인덱스: %s\n- 상태: 대기\n\n## 상태\n%s\n" % (work, last)}, ref)


def first(lines, head):
    return [x for x in lines if x.startswith(head)]


def c1(w):   # ① 착지 줄 없음 · HEAD = 팩 main 조상 · base 와 다름 → COMPLETED(조상 검사) → CLOSED-SESSION · master 알림 1통(줄 보완)
    w.enable(), w.card("r9601"), w.work("r9601", intent=False, alive=True), tree(w, "r9601")
    lines = w.round()
    assert any("조상 검사" in x for x in first(lines, "COMPLETED harness r9601")) and first(lines, "CLOSED-SESSION harness r9601"), lines
    assert w.kinds("complete") == 1 and sum("조상 검사" in x for x in _lines(str(w.mbox) + ".log")) == 1
def c1b(w):  # ①b HEAD = base_sha(새 커밋 0) → 조상이어도 landed 아님 · HELD «착지 줄 없음» 그대로(옛 착지 사유 아님)
    w.card("r9611"), w.work("r9611", intent=False, alive=True), tree(w, "r9611", new=False)
    held = first(w.round(), "HELD harness r9611")
    assert any("착지 줄 없음" in x for x in held) and not any("옛 착지" in x for x in held), held
    assert w.kinds("complete") == 0 and w.tmux("kill-session") == []
def c1c(w):  # ①c squash(HEAD 는 main 조상 아님) → HELD «착지 줄 없음» 그대로
    w.card("r9621"), w.work("r9621", intent=False, alive=True), tree(w, "r9621", land=False)
    assert any("착지 줄 없음" in x for x in first(w.round(), "HELD harness r9621")) and w.kinds("complete") == 0
def c2(w):   # ② journal 에 그 work refuse → CLOSED-ENDING refused · complete 0 · kill 1
    w.enable(), w.card("r9602"), (holder := w.work("r9602", alive=True)), refuse(w, "r9602")
    assert any("refused" in x for x in first(w.round(), "CLOSED-ENDING harness r9602"))
    assert w.kinds("complete") == 0 and w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]]
def c3(w):   # ③ 카드가 아카이브 폴더에만 → CLOSED-ENDING superseded(또는 suspended)
    w.enable(), w.card("r9603", stage="아카이브/2026-11"), w.work("r9603", alive=True)
    assert any("superseded" in x or "suspended" in x for x in first(w.round(), "CLOSED-ENDING harness r9603"))
    assert w.kinds("complete") == 0
def c3b(w):  # ③b 상태 마지막 줄 «중단: …» → CLOSED-ENDING suspended
    w.enable(), card(w, "r9613", "- 2026-11-14 — 중단: 오빠 보류"), w.work("r9613", alive=True)
    assert any("suspended" in x for x in first(w.round(), "CLOSED-ENDING harness r9613")) and w.kinds("complete") == 0
def c4(w):   # ④ r1951 재현 — dispatch a1·a2 같은 holder · intent @a1 만 opened · done → @a1 로 닫음 CLOSED-SESSION
    w.enable(), w.card("r9604", w.pack_sha())
    holder, g = w.work("r9604", alive=True), ["--root", str(w.root), "--team", TEAM]
    for argv in (["submit", "--command", "keeper-next-r9604", "--body", "카드 r9604"], ["assign", "--holder", holder, "--evidence", "v1,v2"],
                 ["deliver", "--mode", "intent"], ["complete", "--attempt", "a2"]):
        assert w.CLI.run(argv + ["--work", "r9604"] + g)[0]["result"] == "접수 성공"
    assert first(w.round(), "CLOSED-SESSION harness r9604") and w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]]
def c4b(w):  # ④b intent 하나도 없음 → HELD «intent 없음» 1줄(침묵 0) · 두 번째 바퀴 같은 줄 0
    w.card("r9614", w.pack_sha()), w.work("r9614", done=True, intent=False, alive=True)
    assert len([x for x in first(w.round(), "HELD harness r9614") if "intent 없음(attempt a1)" in x]) == 1
    assert not [x for x in w.round() if "intent 없음" in x] and w.tmux("kill-session") == []
def c6(w):   # ⑥ 회귀 가드 — 끝 결과 있음 + pane Working → HELD Working · attached 1 → HELD 사람 화면 · 역할 master → 닫기 0
    w.enable()
    for work, kw_ in (("r9606", {"pane": "⠋ Working...\n"}), ("r9616", {}), ("r9626", {"holder": "byz-harness-master-pi#999"})):
        w.card(work), w.work(work, alive=True, **kw_), refuse(w, work)
    _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), att={"byz-harness-nano-r9616-t#0": 1}))
    lines = w.round()
    for work, word in (("r9606", "Working"), ("r9616", "사람 화면"), ("r9626", "보호 역할")):
        assert any(word in x for x in first(lines, "HELD harness " + work)), (work, lines)
    assert w.tmux("kill-session") == [] and not first(lines, "CLOSED")
def c5(w):   # ⑤ unsure 남음 · after_s 지남 → 재깨움 1회 · 또 미확인 · 팀장 0 → harness master [크리티컬] 1통 · 같은 날 두 번째 0 · kill·재배정 0
    w.seat(), _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), noecho=True)), w.round()
    assert "harness|%s@a1" % B.W in w.k.state["unsure"] and len(w.tmux("send-keys")) == 3
    w.round(11 * B.M)
    assert len(w.tmux("send-keys")) == 6 and w.notes() == []
    w.round(12 * B.M), w.round(13 * B.M)
    assert len(w.notes()) == 1 and "[크리티컬]" in w.notes()[0] and "깨움 도달 미확인" in w.notes()[0], w.notes()
    assert len(w.tmux("send-keys")) == 6 and w.tmux("kill-session") == [] and w.kinds("dispatch") == 1 and w.tmux("new-session") == []


CASES = {"①": c1, "①b": c1b, "①c": c1c, "②": c2, "③": c3, "③b": c3b, "④": c4, "④b": c4b, "⑤": c5, "⑥": c6}
KE, KC = "adapters/pi/keeper_endings.py", "adapters/pi/keeper_close.py"
MUTANTS = {"M1": (KE, "head != base", "True", c1b),
           "M2": (KE, '== "refuse"', '== "refuse-x"', c2),
           "M3": (KE, '.get("FT2_HOLDER") == holder', '.get("FT2_HOLDER") is False', c4),
           "M4": (KC, 'return endings.held(self, team, "intent|', 'return None and endings.held(self, team, "intent|', c4b),
           "M5": (KE, "st.wake(team, work, holder, key, idle)", "None", c5),
           "M6": (KC, "if not self.idle(team, work, holder):", "if not (ending or self.idle(team, work, holder)):", c6)}


def world(case, tmp, mp, ft2=FT2):
    tmp.mkdir(parents=True, exist_ok=True)
    return (B.World if case is c5 else kw.World)(tmp, mp, ft2)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(CASES[name], tmp_path / "w", monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    copy = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / rel).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(world(case, tmp_path / "w1", monkeypatch, copy))
    case(world(case, tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
