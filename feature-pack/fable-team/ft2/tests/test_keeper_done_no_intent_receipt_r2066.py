"""r2066 ft2 keeper — 끝난 work 의 intent 가 opening 에서 멈췄거나 없고 배정 좌석 세션이 없으면 닫기 영수 1건으로 마감한다 (카드 r2066-keeper-done-no-intent-absent-receipt · A1~A4).

사례 = ①~⑦ (⑧ = 기존 시험 재실행 목록) · 변이 M1~M4(사본 ft2 에서만 · 원본 같은 사례 1회 더).
대역 = r2131 세계(test_keeper_close_never_opened_r2131 · r1812 keeper_world · 가짜 tmux·launch·mbox·ps). 실 tmux·실 runtime 0 · sleep 0.
판정 줄 = r2131 한 길(CLOSED-NEVER-OPENED · 정지 중 «예정» 줄) · 기준판(팩 origin/main 6d45071f) FAIL = ② ③ ⑦ (① = r2131 이 이미 닫음).
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("never_opened_r2066", str(HERE / "test_keeper_close_never_opened_r2131.py"))
no = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(no)
kw, FT2, TEAM, has, rnd = no.kw, no.FT2, no.TEAM, no.has, no.rnd
job, alive, sent, receipts, handled, quiet, counted, CNO = no.job, no.alive, no.sent, no.receipts, no.handled, no.quiet, no.counted, no.CNO


def closed(w, work, h, state, lines):   # A1 — 닫기 줄 1 · 영수 1 · handled · UNKNOWN 0 · [긴급] 0 · kill 0
    assert len(has(lines, "%s %s %s intent=%s owner=없음" % (CNO, work, h, state))) == 1, lines
    assert len(receipts(lines, work)) == 1 and handled(w, work), lines
    assert not has(lines, "UNKNOWN") and not sent(w) and not w.tmux("kill-session"), (lines, sent(w))


def unknown(w, work, lines):   # A2 — UNKNOWN intent-none · 영수·handled·kill 0
    assert has(lines, "UNKNOWN harness %s" % work, "intent-none"), lines
    quiet(w, work, lines)


def c1(w):   # ① done · intent 파일 없음 · 배정 좌석 세션 없음 → 마감
    closed(w, "r9661", job(w, "r9661", state=None), "없음", rnd(w))


def c2(w):   # ② done · intent opening(r1424 꼴 · FT2_HOLDER 있음) · 세션 없음 → ① 과 같음
    closed(w, "r9662", job(w, "r9662", state="opening"), "opening", rnd(w))


def c3(w):   # ③ ② 뒤 한 바퀴 더 → 판정 줄 0 · 영수 그대로 · [긴급] 0
    c2(w)
    lines = rnd(w, dt=60)
    assert not [x for x in has(lines, "r9662") if not x.startswith("Unsure ")] and not receipts(lines, "r9662"), lines
    assert handled(w, "r9662") and not sent(w), sent(w)


def c4(w):   # ④ done · intent opening · 배정 좌석 세션 alive → UNKNOWN intent-none + [긴급] 1
    alive(w, job(w, "r9664", state="opening"))
    lines = rnd(w)
    unknown(w, "r9664", lines)
    assert len([x for x in sent(w) if "intent-none" in x]) == 1, sent(w)


def c5(w):   # ⑤ tmux 판독 실패(rc 2) → UNKNOWN · 배정 좌석 칸 없음(close 직접) → UNKNOWN intent-none
    job(w, "r9665", state="opening")
    kw._put(str(w.tm) + ".has_rc", "2")
    unknown(w, "r9665", rnd(w))
    (Path(str(w.tm) + ".has_rc")).unlink()
    job(w, "r9675", state="opening")
    k = w.keeper()
    k.close(TEAM, "r9675", "a1", {"done": True, "gen": 1}, None)
    unknown(w, "r9675", k.lines)


def c6(w):   # ⑥ done 아님 · intent opening · 세션 없음 · close 자리 1회 → 영수 0 · 닫기 줄 0
    job(w, "r9666", state="opening", done=False)
    k, calls = counted(w)
    k.one_work = lambda team, work, *a: "close"
    lines = rnd(w, k=k)
    assert calls == ["r9666"], (calls, lines)
    quiet(w, "r9666", lines)


def c7(w):   # ⑦ 정지 중 · ② 입력 → «예정» 줄 1 · 영수 0 · [긴급] 0 / 정지 풀고 한 바퀴 → 영수 1
    h = job(w, "r9667", state="opening")
    kw._put(w.state / "ALL_STOP.json", {"since": 1, "reason": "시험"})
    lines = rnd(w)
    assert len(has(lines, "예정 CLOSED-NEVER-OPENED harness r9667 %s intent=opening owner=없음" % h)) == 1, lines
    assert not receipts(lines, "r9667") and not handled(w, "r9667") and not sent(w), (lines, sent(w))
    (w.state / "ALL_STOP.json").unlink()
    closed(w, "r9667", h, "opening", rnd(w, dt=60))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}
KC = "adapters/pi/keeper_close.py"
MUTANTS = {   # (고칠 글자, 새 글자, 반드시 FAIL 이어야 하는 사례)
    "M1": ('        if self.probe(dispatched) != "absent":   # ⓒ', "        if False:   # ⓒ", ("④",)),
    "M2": ('        if not row.get("done"):   # ⓐ', "        if False:   # ⓐ", ("⑥",)),
    "M3": ("            if quiet and self.halt:", "            if False:", ("⑦",)),
    "M4": ('"없음", "opening"):', '"없음"):', ("②",)),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](no.world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KC).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KC).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        (tmp_path / ("w%d" % i)).mkdir()
        with pytest.raises(AssertionError):
            CASES[case](no.world(tmp_path / ("w%d" % i), monkeypatch, ft2=tree))
        (tmp_path / ("ok%d" % i)).mkdir()   # 원본으로 같은 사례 1회 더 = PASS(반대 결과 대조)
        CASES[case](no.world(tmp_path / ("ok%d" % i), monkeypatch))
