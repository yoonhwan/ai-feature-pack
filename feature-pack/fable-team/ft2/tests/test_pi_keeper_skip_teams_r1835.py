"""r1835 ft2 keeper 제외 팀 SKIP_TEAMS 시험 (카드 반례 ①~⑥′ · 변이 M1~M9).
r1812 대역(keeper_world_r1812.World) 재사용 · 임시 root(ft20-switch 2팀 · seats-<팀>.json · state.open 주입) · 가짜 tmux·
ft-seat-close·쪽지(인자 기록) · 주입 시계 · 실 tmux·Slack·launchd·명부 0 · sleep 0. 기준판(제외 자리 없음) = ① ② ⑥ Red.
"""
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1812", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, FT2, T0, TEAM, _lines, _put = kw.World, kw.FT2, kw.T0, kw.TEAM, kw._lines, kw._put
BAD = "판정 불가 · SKIP_TEAMS 판독 실패"


def world(tmp, mp, skip=b"cfo\n", ft2=FT2):
    """cfo 팀 = TEAMS.md 행 + seats-cfo.json(_master) · skip None = SKIP_TEAMS 파일 없음."""
    w = World(tmp, mp, ft2)
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/TEAMS.md": kw.TEAMS + "| cfo | `design/teams/cfo/` |\n"}, ref)
    _put(w.root / ".fable-team" / "seats-cfo.json", {"_master": "M-cfo"})
    if skip is not None:
        (w.state / "ft2-keeper").mkdir(parents=True, exist_ok=True)
        (w.state / "ft2-keeper" / "SKIP_TEAMS").write_bytes(skip)
    return w
def ready(w, work, team):   # 착지됐는데 done=false 인 일 1개 = B1 complete 대상
    w.card(work, w.pack_sha(), folder="design/harness" if team == TEAM else "design/teams/" + team)
    w.work(work, team=team, intent=False)
def alive(w, *seats):
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    _put(w.tm, dict(d, alive=d["alive"] + list(seats)))
def retire(w, team, seat):  # 명부 `_replaced_by` 행 + 세션 생존 = B3 대상 · team "" = seats.json(v65)
    path = w.root / ".fable-team" / ("seats-%s.json" % team if team else "seats.json")
    _put(path, dict(json.loads(path.read_text(encoding="utf-8")) if path.exists() else {},
                    **{seat: {"role": "stop-ready", "_replaced_by": seat + "-new"}})), alive(w, seat)
def closes(w):
    return _lines(str(w.close) + ".log")
def mails(w):
    return _lines(str(w.mbox) + ".log")
def probes(w, seat):
    return [a for a in w.tmux("has-session") if a[-1] == "=" + seat]
def opened(w):
    return json.loads((w.state / "ft2-keeper" / "state.json").read_text(encoding="utf-8"))["open"]
def c1(w):   # ① 표식 2팀 · SKIP_TEAMS=cfo → harness complete 1 · cfo complete·tmux·쪽지 0
    ready(w, "r9101", TEAM), ready(w, "r9102", "cfo")
    lines = w.round()
    assert w.kinds("complete") == 1 and w.kinds("complete", "cfo") == 0, lines
    assert not [a for a in map(json.loads, _lines(str(w.tm) + ".log")) if "cfo" in " ".join(a)]
    assert not [x for x in mails(w) if "cfo" in x]
def c2(w):   # ② seats-cfo·seats-harness `_replaced_by` + 생존 → ft-seat-close harness 1 · cfo 0 · cfo open 손 0
    retire(w, TEAM, "O#1"), retire(w, "cfo", "C#1"), w.round()
    assert [x.split()[0] for x in closes(w)] == ["O#1"] and probes(w, "C#1") == [] and "C#1" not in opened(w)
def c2b(w):  # ②′ seats.json(v65) 안의 byz-cfo-… 행 → 호출 0 · 같은 파일 byz-harness-… 행 → 1
    retire(w, "", "byz-cfo-nano-x#0"), retire(w, "", "byz-harness-nano-y#0"), w.round()
    assert [x.split()[0] for x in closes(w)] == ["byz-harness-nano-y#0"]
def c3(w):   # ③ SKIP_TEAMS 없음 → 두 팀 모두 지금처럼 · ROUND 꼴 그대로(skip 칸 없음)
    ready(w, "r9301", TEAM), ready(w, "r9302", "cfo"), retire(w, TEAM, "O#1"), retire(w, "cfo", "C#1")
    lines = w.round()
    assert w.kinds("complete") == 1 and w.kinds("complete", "cfo") == 1 and len(closes(w)) == 2, lines
    assert [x for x in lines if x.startswith("ROUND")] and not [x for x in lines if "skip=" in x]
def c3b(w):  # ③′ 빈 줄·`# 메모`·cfo → cfo 만 빠짐(이름 없는 좌석 O#1 도 그대로 닫힘)
    ready(w, "r9311", TEAM), ready(w, "r9312", "cfo"), retire(w, TEAM, "O#1")
    lines = w.round()
    assert w.kinds("complete") == 1 and w.kinds("complete", "cfo") == 0 and len(closes(w)) == 1, lines
def c4(w):   # ④ 디코드 실패 바이트 → 이 바퀴 B1·B2·B3 0 · 판정 불가 1줄
    ready(w, "r9401", TEAM), retire(w, TEAM, "O#1")
    lines = w.round()
    assert w.kinds("complete") == 0 and closes(w) == [] and w.tmux("kill-session") == [], lines
    assert sum(x.startswith("판정 불가") and "SKIP_TEAMS 판독 실패" in x for x in lines) == 1, lines
def c5(w):   # ⑤ 로그 파일에 cfo 든 줄 = ROUND 줄 1개(skip=cfo)뿐
    ready(w, "r9501", TEAM), ready(w, "r9502", "cfo"), retire(w, TEAM, "O#1"), retire(w, "cfo", "C#1"), w.round()
    rows = [json.loads(x) for p in (w.state / "ft2-keeper").glob("*.jsonl") for x in _lines(p)]
    hit = [r for r in rows if "cfo" in r["line"] or r["team"] == "cfo"]
    assert len(hit) == 1 and hit[0]["kind"] == "ROUND" and hit[0]["line"].endswith(" skip=cfo"), hit
OPEN = {"byz-cfo-nano-a#0": "cfo", "byz-cfo-old#1": "v65", "byz-harness-nano-b#0": TEAM}
def preopen(w):  # state.open 3행(31분 전 · 생존) — cfo 행 team · 이름만 cfo(team=v65) · harness
    _put(w.state / "ft2-keeper" / "state.json", {"open": {s: {"team": t, "since": T0 - 31 * 60} for s, t in OPEN.items()}})
    alive(w, *OPEN)
def c6(w):   # ⑥ report probe·쪽지 = harness 1 · cfo 0 · NOTIFIED cfo 0 · open 3행 그대로 · notify(cfo) 0
    preopen(w)
    k = w.keeper()
    lines = w.round(k)
    assert [len(probes(w, s)) for s in OPEN] == [0, 0, 1], w.tmux("has-session")
    assert len(mails(w)) == 1 and mails(w)[0].startswith("send M-harness ft2-keeper"), mails(w)
    assert not [x for x in lines if "cfo" in x and not x.startswith("ROUND")] and set(opened(w)) == set(OPEN)
    assert k.notify("cfo", "x|cfo", "[크리티컬] 시험") is False and len(mails(w)) == 1
def c6b(w):  # ⑥′ 판독 실패 + ⑥ open → 바퀴 report 0 · --report 진입 출력 1줄 · open 3행 그대로
    preopen(w), w.round()
    assert w.tmux("has-session") == [] and mails(w) == [] and w.keeper().report_once() == BAD
    done = subprocess.run([sys.executable, str(w.ft2 / "core" / "cli.py"), "keeper", "--root", str(w.root), "--report"],
                          env=w.env, capture_output=True, text=True, timeout=60)
    assert done.returncode == 0 and done.stdout == BAD + "\n", done.stdout + done.stderr
    assert w.tmux("has-session") == [] and mails(w) == [] and set(opened(w)) == set(OPEN)
CASES = {"①": (c1, b"cfo\n"), "②": (c2, b"cfo\n"), "②′": (c2b, b"cfo\n"), "③": (c3, None), "③′": (c3b, b"\n# \xeb\xa9\x94\xeb\xaa\xa8\n\ncfo\n"),
         "④": (c4, b"\xff\xfecfo\n"), "⑤": (c5, b"cfo\n"), "⑥": (c6, b"cfo\n"), "⑥′": (c6b, b"\xff\xfecfo\n")}
KP, KC, KR = "adapters/pi/keeper.py", "adapters/pi/keeper_close.py", "adapters/pi/keeper_report.py"
MUTANTS = {"M1": (KP, " and team not in self.skip", "", "①"),
           "M2": (KC, " and not {team, (seat.split(\"-\") + [\"\"])[1]} & self.skip", "", "②"),
           "M3": (KC, "{team, (seat.split(\"-\") + [\"\"])[1]} & self.skip", "{team} & self.skip", "②′"),
           "M4": (KP, " if x.strip() and not x.strip().startswith(\"#\")", "", "③′"),
           "M5": (KP, "return set() if isinstance(exc, FileNotFoundError) else None", "return set()", "④"),
           "M6": (KC, " and not {team, (seat.split(\"-\") + [\"\"])[1]} & self.skip",
                  " and (not {team, (seat.split(\"-\") + [\"\"])[1]} & self.skip or self.log(\"HELD-SEAT\", team, seat))", "⑤"),
           "M7": (KR, "if {seen_at.get(\"team\"), (seat.split(\"-\") + [\"\"])[1]} & self.skip:", "if False:", "⑥"),
           "M8": (KR, "                continue", "                self.state[\"open\"].pop(seat)\n                continue", "⑥"),
           "M9": (KP, "return self.log(\"판정 불가\", text=\"SKIP_TEAMS",
                  "self.skip = set(); self.report(); return self.log(\"판정 불가\", text=\"SKIP_TEAMS", "⑥′")}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    case, skip = CASES[name]
    case(world(tmp_path, monkeypatch, skip))
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, label = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    case, skip = CASES[label]
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(world(tmp_path / "w1", monkeypatch, skip, tree))
    case(world(tmp_path / "w2", monkeypatch, skip))   # 원본으로 같은 사례 1회 더 = PASS
