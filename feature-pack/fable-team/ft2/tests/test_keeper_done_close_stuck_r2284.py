"""r2284 ft2 keeper — 끝난 나노 닫기 막힘 2갈래 (카드 반례 ①~⑤ · 계약 C1~C3).
① 같은 바퀴 COMPLETED → CARD-STAGE 대기→완성 뒤 B2 landing 이 낡은 카드 목록을 씀(C1) · ①ⓑ NOOP = 캐시 그대로.
③④ CPU 쉼 표본 장부 수명(③ = r2354 K1 좌석 판 대조 · ④ busy 덮음) · ⑤ 닫기 가드 그대로(C3).
대역 = r2055 settle 시험 world(keeper_world_r1812 꼴 · 임시 리포 · 가짜 tmux·ps · 주입 시계) · card_stage = 실제 git 이동 대역(seed 커밋 · root fetch).
기준판(팩 origin/main d809c99c) = ① · ② Red. 변이 M1~M3 = 자매 파일 test_keeper_done_close_stuck_mut_r2284.py. sleep 0 · 실 tmux·pi 0.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2055_settle_for_r2284", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
S = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(S)
kw, FT2, TEAM = S.kw, S.FT2, S.TEAM
FOLDER = "design/harness"


def card_at(w, work, stage, sha):
    """두 ref 에 카드 1장(<work>-x.md) · 착지 줄 sha."""
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"%s/indices/%s/%s-x.md" % (FOLDER, stage, work): "# 인덱스: %s\n- 남은 범위: 없음\n- 착지: %s\n" % (work, sha)}, ref)


class Mover:
    """card_stage 대역 — 실제처럼 두 ref 에서 카드 대기→완성 git mv 커밋 · push · root fetch(remote-tracking ref 옮김) · 호출 기록."""
    class Unsure(Exception):
        pass
    spawn = None

    def __init__(self, w, noop=False):
        self.w, self.noop, self.calls = w, noop, []

    def done_at(self, root, team, work):
        return "2026-11-13T09:00:00"

    def stage(self, byz, root, team, work, at, now):
        self.calls.append(work)
        if self.noop:
            return None
        seed = self.w.tmp / "seed-byz"
        for ref in ("main", "ops/main-base"):
            kw._git(seed, "checkout", "-q", ref)
            src, dst = seed / FOLDER / "indices" / "대기" / ("%s-x.md" % work), seed / FOLDER / "indices" / "완성" / ("%s-x.md" % work)
            kw._put(dst, src.read_text(encoding="utf-8")), kw._git(seed, "rm", "-q", str(src)), kw._git(seed, "add", "-A")
            kw._git(seed, "commit", "-q", "-m", "stage"), kw._git(seed, "push", "-q", "origin", ref)
        kw._git(self.w.root, "fetch", "-q", "origin")
        return ("%s-x" % work, "대기→완성", kw._git(seed, "rev-parse", "--short", "HEAD"))


def rnd(w, k_hook=None, **kv):
    """S.rnd 와 같은 한 바퀴 · k_hook(k) = 바퀴 전 keeper 손질(card_stage 대역)."""
    if k_hook is None:
        return S.rnd(w, **kv)
    real = w.keeper
    def made():
        k = real()
        k_hook(k)
        return k
    w.keeper = made
    try:
        return S.rnd(w, **kv)
    finally:
        w.keeper = real


def state(w):
    return json.loads((w.root / ".fable-team" / "state" / "ft2-keeper" / "state.json").read_text(encoding="utf-8"))


def closed(lines, work):
    return [x for x in lines if x.startswith("CLOSED-SESSION %s %s" % (TEAM, work))]


def landed_nano(w, work, **kv):
    """착지 끝 카드(완성 · 착지 줄 조상) + 끝난 나노(done · jsonl 2시간 쉼) = 닫기 길 B2."""
    card_at(w, work, "완성", w.pack_sha())
    return S.nano(w, work, done=True, **kv)


def fetch_fail(w):
    """바퀴 B — BYZ 원격을 잠시 치워 fetch 실패(이 바퀴 B1·B2 0 · 그 좌석 표본 0) · 시계 dt 초."""
    bare, away = w.tmp / "byz.git", w.tmp / "byz.git.away"
    bare.rename(away)
    try:
        return S.rnd(w, dt=60)
    finally:
        away.rename(bare)


def c1(w, noop=False):   # ① 같은 바퀴 COMPLETED → CARD-STAGE 대기→완성 · 쉼 · 표본 2개 → 그 바퀴 CLOSED-SESSION 1 · ⓑ NOOP = 캐시 그대로 · 결과 같음
    work = "r9841"
    card_at(w, work, "대기", "0" * 40)   # 바퀴 A = 착지 줄 아직 조상 아님(complete 0 · 표본만)
    S.nano(w, work)
    first = S.rnd(w)
    assert not w.kinds("complete") and not w.tmux("kill-session"), first
    card_at(w, work, "대기", w.pack_sha())   # 착지 줄 채움 → 바퀴 B 에서 B1 complete → card_stage
    mover = Mover(w, noop=noop)
    if noop:   # ⓑ 이미 완성(다른 길이 옮김) → card_stage NOOP
        Mover(w).stage(None, None, TEAM, work, None, None)
    lines = rnd(w, k_hook=lambda k: setattr(k, "cs", mover), dt=30)
    assert mover.calls == [work], (mover.calls, lines)
    assert any(x.startswith(("CARD-STAGE", "NOOP")) for x in lines), lines
    assert len(closed(lines, work)) == 1 and len(w.tmux("kill-session")) == 1, lines


def c2(w):   # ② 바퀴 A 표본 1(쉼) → 바퀴 B fetch 실패(표본 0) → 바퀴 C(A 뒤 31~599초) 표본 1(쉼) → idle → 닫기 1
    work = "r9842"
    landed_nano(w, work)
    a = S.rnd(w, clean="")
    assert not closed(a, work) and not w.tmux("kill-session"), a
    b = fetch_fail(w)
    assert any("B1·B2 0" in x for x in b), b
    c = S.rnd(w, dt=120, clean="")
    assert len(closed(c, work)) == 1 and len(w.tmux("kill-session")) == 1, c


def c3(w):   # ③ r2354 K1 — A 뒤 605초는 같은 pane_pid = 표본 유지 → idle · 닫기 1 · A 뒤 4000초(CPU_SAMPLE_MAX 넘김) = 새 표본 → pending · 닫기 0
    work = "r9843"
    landed_nano(w, work)
    S.rnd(w, clean="")
    fetch_fail(w)
    c = S.rnd(w, dt=605, clean="")   # A 뒤 605초 = 600초 넘지만 같은 판(r2354 K1)
    assert len(closed(c, work)) == 1 and len(w.tmux("kill-session")) == 1, c
    work = "r9844"   # 4000초 = 표본 상한 넘김 → 새 표본 → pending
    landed_nano(w, work)
    S.rnd(w, clean="")
    fetch_fail(w)
    c = S.rnd(w, dt=4000, clean="")
    assert not closed(c, work) and len(w.tmux("kill-session")) == 1, c
    assert [x for x in c if "WORKING %s %s" % (TEAM, work) in x and "cpu-pending" in x] or state(w)["verdict"]["%s|%s|byz-%s-nano-%s#0" % (TEAM, work, TEAM, work)] == ["WORKING", "cpu-pending"], c


def c4(w):   # ④ 바퀴 A 쉼 → 바퀴 B 그 좌석 busy → 바퀴 C 쉼 → pending(busy 가 덮음) · 닫기 0
    work = "r9844"
    landed_nano(w, work)
    S.rnd(w, clean="")
    b = S.rnd(w, dt=60, clean="", cpu=0.9)
    assert not closed(b, work), b
    c = S.rnd(w, dt=60, clean="")
    assert not closed(c, work) and not w.tmux("kill-session"), c


def c5(w):   # ⑤ 표본 2개 쉼이어도 jsonl 무활동 < 300초 · 또는 턴 열림 → 닫기 0(C3)
    for work, kv in (("r9845", {"age": 100}), ("r9846", {"turn": "toolUse"})):
        landed_nano(w, work, **kv)
    lines = S.rnd(w, clean="") + S.rnd(w, dt=60, clean="")
    assert not closed(lines, "r9845") and not closed(lines, "r9846") and not w.tmux("kill-session"), lines


CASES = {"①": c1, "①ⓑ": lambda w: c1(w, noop=True), "②": c2, "③": c3, "④": c4, "⑤": c5}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](S.world(tmp_path, monkeypatch))


def mutant(tmp_path, monkeypatch, rel, pairs, case):
    """사본 ft2 의 변이(pairs = [(old, new)] · 각 old 1회) → 사례 FAIL · 원본으로 같은 사례 1회 더 = PASS."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (rel, old)
        text = text.replace(old, new)
    (tree / rel).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(S.world(tmp_path / "w1", monkeypatch, tree))
    case(S.world(tmp_path / "w2", monkeypatch))
