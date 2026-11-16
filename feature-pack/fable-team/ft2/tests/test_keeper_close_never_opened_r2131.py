"""r2131 ft2 keeper — 열린 적 없는 끝난 일(intent failed·없음 · 세션 0 · 열기 자식 0)은 kill 0 닫기 영수 1줄로 끝낸다 (카드 r2131-keeper-close-never-opened-quiet · C1~C4).

사례 = ①~⑤ · ⑦~⑩ (⑥ = 기존 시험 재실행 목록) · 변이 M1~M4(사본 ft2 에서만 · 원본 같은 사례 1회 더).
대역 = test_launch_failed_end 세계(r1812 keeper_world · 가짜 tmux·launch·mbox) + 가짜 ps(FT2_KEEPER_PS · lstart 만 주입).
실 tmux·실 runtime·실 우편함 0 · sleep 0. 기준판(팩 origin/main) FAIL = ① ② ③ ⑩.
"""
import importlib.util
import json
import os
import shutil
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("launch_failed_r2131", str(HERE / "test_launch_failed_end.py"))
lf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lf)
kw, FT2, TEAM, has, rnd = lf.kw, lf.FT2, lf.TEAM, lf.has, lf.rnd
KPS = '#!/bin/sh\ncase "$*" in *lstart=*) ;; *) exec ps "$@";; esac\nf="$FAKE_TMUX.kps"\n' \
      'if [ -f "$f.rc" ]; then exit "$(cat "$f.rc")"; fi\ncat "$f"\n'
STARTED = float(int(time.time()) - 600)
CNO = "CLOSED-NEVER-OPENED harness"


def world(tmp, mp, ft2=FT2):
    w = lf.world(tmp, mp, ft2=ft2)
    kw._put(w.tmp / "bin" / "kps", KPS), (w.tmp / "bin" / "kps").chmod(0o755)
    w.env["FT2_KEEPER_PS"] = str(w.tmp / "bin" / "kps")
    return w


def ps_at(w, late=0, rc=None):
    """가짜 ps 1줄 = «S <lstart>» · late = 시작 시각 늦춤(같은 pid 다른 프로세스 = dead) · rc = 판독 실패."""
    kw._put(str(w.tm) + ".kps", "S    " + time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(STARTED + late)) + "\n")
    if rc is not None:
        kw._put(str(w.tm) + ".kps.rc", str(rc))


def job(w, work, holder=None, state="failed", done=True):
    """나노 1석 = 접수 → 배정 → 전달(→ complete) · intent state(None = 파일 없음) · 세션 0."""
    holder = holder or "byz-%s-nano-%s#0" % (TEAM, work)
    steps = [["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
             ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2", "--resources", "R-" + work],
             ["deliver", "--work", work]] + ([["complete", "--work", work, "--attempt", "a1"]] if done else [])
    for argv in steps:
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", TEAM])
        assert rc == 0, out
    if state:
        kw._put(w.runtime() / "launch" / ("%s@a1.intent" % work), {"FT2_HOLDER": holder, "state": state, "at": lf.stamp(w.t),
                                                                     "base": "origin/main", "step": "git checkout", "reason": "x"})
    return holder


def alive(w, holder):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"], d["pane"][holder] = d["alive"] + [holder], "✻ Brewed for 3s\n❯ "
    kw._put(w.tm, d)


def kid(w, work, name, row):
    kw._put(w.runtime() / "launch" / ("%s@a1%s" % (work, name)), row)


def sent(w):   # keeper [긴급] 만(나노 정원 ★크리티컬★ = 이 카드 밖 · 기준판에도 나는 줄)
    return [x for x in lf.sent(w) if "ft2-keeper [긴급]" in x]


def receipts(lines, work):
    return [x for x in lines if x.startswith("RECEIPT harness %s " % work)]


def handled(w, work):
    path = w.state / "ft2-keeper" / "state.json"
    book = json.loads(path.read_text(encoding="utf-8")).get("handled", {}) if path.exists() else {}
    return "%s|%s@a1" % (TEAM, work) in book


def counted(w):
    """keeper 1개 · close 호출 셈(인스턴스 덧씌움 = team_round 가 부르는 바로 그 자리)."""
    k, calls = w.keeper(), []
    real = k.close
    k.close = lambda *a, **kv: calls.append(a[1]) or real(*a, **kv)
    return k, calls


def quiet(w, work, lines):   # C2·C4 공통 — 닫기 줄·영수·handled·kill 0
    assert not has(lines, CNO) and not receipts(lines, work), lines
    assert not handled(w, work) and not w.tmux("kill-session"), lines


def c1(w):   # ① done · intent failed · 세션 없음 → 닫기 줄 1 · 영수 1 · alert 0 · kill 0
    h = job(w, "r9701")
    lines = rnd(w)
    assert len(has(lines, "%s r9701 %s intent=failed owner=없음" % (CNO, h))) == 1, lines
    assert len(receipts(lines, "r9701")) == 1 and handled(w, "r9701"), lines
    assert not has(lines, "UNKNOWN") and not sent(w) and not w.tmux("kill-session"), (lines, sent(w))


def c2(w):   # ② done · intent 파일 없음 · holder = 다른 일 holder · 세션 없음(r1885 꼴) → ① 과 같음
    h = job(w, "r9702", holder="byz-harness-nano-r9701-other#0", state=None)
    lines = rnd(w)
    assert len(has(lines, "%s r9702 %s intent=없음 owner=없음" % (CNO, h))) == 1, lines
    assert len(receipts(lines, "r9702")) == 1 and handled(w, "r9702"), lines
    assert not has(lines, "UNKNOWN") and not sent(w) and not w.tmux("kill-session"), (lines, sent(w))


def c3(w):   # ③ 두 바퀴 → 둘째 바퀴 판정 줄 0 · alert 0 · 영수 1 그대로
    c1(w)
    lines = rnd(w, dt=60)
    assert not has(lines, "r9701") and not sent(w), lines
    assert handled(w, "r9701")


def c4(w):   # ④ done · intent failed · holder 세션 살아 있음 → UNKNOWN intent-none · alert 1 · kill 0
    alive(w, job(w, "r9704"))
    lines = rnd(w)
    assert has(lines, "UNKNOWN harness r9704", "intent-none"), lines
    assert len([x for x in sent(w) if "intent-none" in x]) == 1, sent(w)
    quiet(w, "r9704", lines)


def c5(w):   # ⑤ done 아님 · intent failed · 세션 없음 → ⓑ close 직접 1회 = 닫기 0 · ⓐ 통합 = 지금 길(launch-failed)
    job(w, "r9705", done=False)
    k, calls = counted(w)
    k.one_work = lambda team, work, *a: "close"   # ⓑ 같은 입력으로 close 자리 1회(가드 미도달 = FAIL)
    lines = rnd(w, k=k)
    assert calls == ["r9705"], (calls, lines)
    quiet(w, "r9705", lines)
    lines = rnd(w, dt=60)   # ⓐ 새 keeper · 통합 길 그대로
    assert has(lines, "UNKNOWN harness r9705", "launch-failed"), lines
    quiet(w, "r9705", lines)


def c7(w):   # ⑦ done · intent 없음 · 세션 없음 · .owner 자식 alive → 닫기 0 · .owner 없음 + .intent.resume alive 1회 더
    job(w, "r9707", state=None)
    ps_at(w)
    kid(w, "r9707", ".owner", {"child_pid": os.getpid(), "started": STARTED, "keeper_pid": os.getpid()})
    lines = rnd(w)
    assert has(lines, "UNKNOWN harness r9707", "intent-none"), lines
    quiet(w, "r9707", lines)
    (w.runtime() / "launch" / "r9707@a1.owner").unlink()
    kid(w, "r9707", ".intent.resume", {"pid": os.getpid(), "started": STARTED, "kind": "resume"})
    quiet(w, "r9707", rnd(w, dt=60))


def c8(w):   # ⑧ ⑦ 과 같되 ps 판독 실패(unknown) → 닫기 0
    job(w, "r9708", state=None)
    ps_at(w, rc=1)
    kid(w, "r9708", ".owner", {"child_pid": os.getpid(), "started": STARTED, "keeper_pid": os.getpid()})
    quiet(w, "r9708", rnd(w))


def c9(w):   # ⑨ ⑦ 첫 바퀴 뒤 opened · holder alive → 둘째 바퀴 handled 에 없음 · close 1 · 열린 intent 길 판정 줄 1
    h = job(w, "r9709", state=None)
    ps_at(w)
    kid(w, "r9709", ".owner", {"child_pid": os.getpid(), "started": STARTED, "keeper_pid": os.getpid()})
    quiet(w, "r9709", rnd(w))
    kid(w, "r9709", ".intent", {"FT2_HOLDER": h, "state": "opened", "worktree": str(w.tmp / "wt" / "r9709"), "at": lf.stamp(w.t)})
    alive(w, h)
    k, calls = counted(w)
    lines = rnd(w, dt=60, k=k)
    assert calls == ["r9709"], (calls, lines)
    seen = [x for x in lines if x.split(" ", 1)[-1].startswith("harness r9709 %s " % h) and x.split()[0].isupper()]   # 판정 줄(통지 줄 0)
    assert len(seen) == 1 and not has(seen, "intent-none"), lines
    quiet(w, "r9709", lines)


def c10(w):   # ⑩ ⑦ 과 같되 .owner 자식 dead(같은 pid 다른 시작 시각) → ① 과 같음 · owner=dead
    h = job(w, "r9710", state=None)
    ps_at(w, late=3600)
    kid(w, "r9710", ".owner", {"child_pid": os.getpid(), "started": STARTED, "keeper_pid": os.getpid()})
    lines = rnd(w)
    assert len(has(lines, "%s r9710 %s intent=없음 owner=dead" % (CNO, h))) == 1, lines
    assert len(receipts(lines, "r9710")) == 1 and handled(w, "r9710"), lines
    assert not has(lines, "UNKNOWN") and not sent(w) and not w.tmux("kill-session"), (lines, sent(w))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10}
KC = "adapters/pi/keeper_close.py"
MUTANTS = {   # (고칠 글자, 새 글자, 반드시 FAIL 이어야 하는 사례)
    "M1": ('        if self.probe(dispatched) != "absent":   # ⓒ', "        if False:   # ⓒ", ("④",)),
    "M2": ('        if not row.get("done"):   # ⓐ', "        if False:   # ⓐ", ("⑤",)),
    "M3": ("                return self.receipt(team, work, attempt, dispatched, gen) and None", "                return None", ("③",)),
    "M4": ('            if there and (data is None or keeper_next.kl.alive(', "            if False and (data is None or keeper_next.kl.alive(", ("⑦", "⑧")),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch))


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
            CASES[case](world(tmp_path / ("w%d" % i), monkeypatch, ft2=tree))
        (tmp_path / ("ok%d" % i)).mkdir()   # 원본으로 같은 사례 1회 더 = PASS(반대 결과 대조)
        CASES[case](world(tmp_path / ("ok%d" % i), monkeypatch))
