"""r2267 ft2 keeper 휴면 팀 깨움 후보 — SKIP_TEAMS 팀은 선행 판정만 읽고, 풀린 카드 묶음이 생기면 planner _master 에 1통 (반례 ①~⑧ · 변이 M1~M8).
대역 = r1812 keeper_world(임시 root·git·가짜 tmux·가짜 mbox·주입 시계 w.t) + SKIP_TEAMS cb + 카드 루트 표 cb 행 + 가짜 gh(호출 기록).
실 리포·실 tmux·실 원장·설치 0 · sleep 0. 기준판 = ③ Red(휴면 팀은 바퀴에서 통째로 빠진다). M6 = r2159(progress) 착지 뒤 판에서 돌린다.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r2267", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
FT2, DAY, CB = kw.FT2, 86400, "cb"
IDX = "design/teams/cb/indices/%s/%s.md"
A, B, DA, DB, RUN = "r9500-a", "r9502-b", "r9501-dep", "r9503-dep", "r9504-run"
GH = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\necho "[]"\n'
KN, KP, KR = "adapters/pi/keeper_next.py", "adapters/pi/keeper.py", "adapters/pi/keeper_report.py"


def put(w, stage, stem, head="", idx=IDX):
    w.commit("byz", {idx % (stage, stem): "# 인덱스: %s\n%s- 상태: 대기\n" % (stem, head)}, "main")


def move(w, stem, to="완성", idx=IDX):
    seed = w.tmp / "seed-byz"
    kw._git(seed, "checkout", "-q", "main")
    (seed / (idx % (to, stem))).parent.mkdir(parents=True, exist_ok=True)
    kw._git(seed, "mv", idx % ("대기", stem), idx % (to, stem))
    w.commit("byz", {}, "main")


def skip(w, body):
    kw._put(w.state / "ft2-keeper" / "SKIP_TEAMS", body)


def world(tmp, mp, ft2=FT2):
    """휴면 팀 cb · 대기 카드 A(선행 r9501) · B(선행 r9503) · 참조 카드 r9501 · r9503 은 대기."""
    w = kw.World(tmp, mp, ft2)
    skip(w, "cb\n")
    kw._put(w.state / "directive-roots.tsv", "cb\t.\torigin/main\tdesign/teams/cb/indices\nharness\t.\torigin/main\tdesign/harness/indices\n")
    kw._put(tmp / "bin" / "gh", GH), (tmp / "bin" / "gh").chmod(0o755)
    w.env["FT2_GH"] = str(tmp / "bin" / "gh")
    w.commit("byz", {IDX % ("대기", s): "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h) for s, h in
                     ((DA, ""), (DB, ""), (A, "- 선행: r9501 착지\n"), (B, "- 선행: r9503 착지\n"))}, "main")
    return w


def mails(w):
    return kw._lines(str(w.mbox) + ".log")


def wakes(w):
    return [x for x in mails(w) if "[깨움 후보]" in x]


def seen(w):
    return json.loads((w.state / "ft2-keeper" / "state.json").read_text(encoding="utf-8")).get("wake_seen", {})


def c1(w):   # ① 휴면 팀 판독 = 원장·팀 쪽지·fill·gh 0 · 재개 줄 진행 카드 · BYZ 낡은 바퀴 = 판독 0
    put(w, "진행", RUN, "- 재개: PR #1\n")
    w.round(), move(w, DA)
    lines = w.round()
    assert len(wakes(w)) == 1 and len(mails(w)) == 1, mails(w)
    assert [x for x in lines if " cb " in " %s " % x and not x.startswith("NOTIFIED cb ")] == [], lines
    assert not w.runtime(CB).exists() and not kw._lines(str(w.tmp / "bin" / "gh") + ".log")
    st = json.loads((w.state / "ft2-keeper" / "state.json").read_text(encoding="utf-8"))
    assert not [key for key in st.get("resume_seen", {}) if CB in key], st
    assert "fill_open" not in st and "fill_hold" not in st, st   # fill 이 한 번이라도 불리면 생기는 칸(활성 팀 0 바퀴)
    before = seen(w)
    move(w, DB)
    kw._git(w.root, "fetch", "-q", "origin"), kw._git(w.root, "remote", "set-url", "origin", str(w.tmp / "none.git"))
    w.round()
    assert len(wakes(w)) == 1 and seen(w) == before, (mails(w), seen(w))
    kw._git(w.root, "remote", "set-url", "origin", str(w.tmp / "byz.git"))
    w.round()
    assert len(wakes(w)) == 2, mails(w)


def c2(w):   # ② 남은 예산 < 7초 → 그 바퀴 판독 0 · 다음 바퀴 이어서
    w.round(), move(w, DA)
    before, k = seen(w), w.keeper()
    k.__class__.__init__.__globals__["WORK_S"] = 3
    w.round(k)
    assert wakes(w) == [] and seen(w) == before, (mails(w), seen(w))
    w.round()
    assert len(wakes(w)) == 1, mails(w)


def c3(w):   # ③ 참조 카드가 완성/ 으로 감 → planner 1통(기준판 0 → Red)
    w.round()
    assert wakes(w) == [], mails(w)
    move(w, DA), w.round()
    assert wakes(w) == ["send M-planner ft2-keeper [깨움 후보] cb 선행 풀린 카드 1장: %s · 휴면 풀기 = SKIP_TEAMS 에서 cb 줄 지움" % A], mails(w)


def c4(w):   # ④ 처음 본 바퀴부터 풀린 카드 = 기억만 · 휴면 → 깨움 → 다시 휴면 첫 바퀴 = 0통
    move(w, DA), w.round()
    assert wakes(w) == [] and seen(w)[CB][A] == "", (mails(w), seen(w))
    skip(w, ""), w.round()   # 깨움(SKIP_TEAMS 밖 바퀴) = 기억 지움
    assert CB not in seen(w), seen(w)
    skip(w, "cb\n"), w.round()   # 다시 휴면 · B = 선행 기억
    assert seen(w)[CB][B] == "선행", seen(w)
    skip(w, ""), w.round()
    move(w, DB), skip(w, "cb\n"), w.round()   # 다시 휴면 첫 바퀴에 B 풀림 = 처음 보는 팀 → 0통
    assert wakes(w) == [], mails(w)


def c5(w):   # ⑤ ③ 다음 바퀴 · 다음 날 · 같은 묶음 → 0통 · 둘째 카드도 풀림 → 지문 바뀜 → 1통
    c3(w)
    w.round()
    w.t += DAY
    w.round()
    assert len(wakes(w)) == 1, mails(w)
    move(w, DB), w.round()
    assert len(wakes(w)) == 2 and "선행 풀린 카드 2장: %s · %s ·" % (A, B) in wakes(w)[1], mails(w)


def c6(w):   # ⑥ 1일째 mbox 실패 → 그날 0 · 2일째 1통 · planner master 승계 → 1통
    w.round(), move(w, DA)
    kw._put(str(w.mbox) + ".rc", "1")
    w.round(), w.round()
    assert len(wakes(w)) == 1, mails(w)   # 시도 1회(실패) · 그날 재시도 0
    Path(str(w.mbox) + ".rc").unlink()
    w.t += DAY
    w.round(), w.round()
    assert len(wakes(w)) == 2, mails(w)
    kw._put(w.root / ".fable-team" / "seats-planner.json", {"_master": "M-planner2"})
    w.round()
    assert len(wakes(w)) == 3 and wakes(w)[2].startswith("send M-planner2 "), mails(w)


def c7(w):   # ⑦ planner _master 빈칸 → 쪽지 0 · 판정 불가 1줄(그날 1회)
    kw._put(w.root / ".fable-team" / "seats-planner.json", {"_master": ""})
    w.round(), move(w, DA)
    lines = w.round() + w.round()
    assert mails(w) == [] and len([x for x in lines if x.startswith("판정 불가 cb 쪽지 받는 곳 없음")]) == 1, lines


def c8(w):   # ⑧ 휴면 아닌 팀(harness) 선행 풀림 → 깨움 0 · 기억 0
    hi = "design/harness/indices/%s/%s.md"
    put(w, "대기", "r9601-dep", idx=hi), put(w, "대기", "r9600-h", "- 선행: r9601\n", idx=hi)
    w.round(), move(w, "r9601-dep", idx=hi), w.round()
    assert wakes(w) == [] and list(seen(w)) == [CB], (mails(w), seen(w))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
MUTANTS = {
    "M1": (KP, "closing.keeper_next.wake_read(self, team)", "(closing.keeper_next.wake_read(self, team), closing.keeper_next.fill(self, team))", "①"),
    "M2": (KP, "if (left := self.left()) is not None and left < CALL_S:", "if False:", "②"),
    "M3": (KN, ' and prev and prev.get(s) in ("선행", "선행불명", "풀림")', "", "④"),
    "M4": (KR, 'key = "%s|wake|%s|%s" % (team, to,', 'key = "%s|%s|wake|%s|%s" % (self.stamp()[:10], team, to,', "⑤"),
    "M5": (KR, "return self.finish(team, key, to, rc, seen, body)   # W4", "return self.finish(team, key, to, 0, seen, body)   # W4", "⑥"),
    "M7": (KP, 'self.state["wake_seen"].pop(team)', "None", "④"),
    "M8": (KN, "k.wake(team, freed)", 'k.notify(team, "wake", "[깨움 후보] " + " ".join(freed))', "③"),
}


def run(name, tmp, mp, ft2=FT2):
    CASES[name](world(tmp, mp, ft2))


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS


@pytest.mark.skip(reason="M6 = 휴면 팀 길에서 progress() 부름 — r2159(진행 카드 재개 줄 progress) 미착지 판 · r2159 착지 뒤 판에서 돌린다")
def test_mutant_m6():
    pass
