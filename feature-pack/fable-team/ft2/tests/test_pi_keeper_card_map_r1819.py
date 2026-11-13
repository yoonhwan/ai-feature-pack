"""r1819 keeper 카드 짝 시험 (카드 반례 ①~④ · 변이 M1~M6 · DA#10 설계 보정 APPROVE).
r1812 대역(keeper_world_r1812) 재사용 · 임시 BYZ 리포(TEAMS.md 에 feature·chatbot) · 짝 표 = 임시 runtime 의 일반 파일.
실 runtime·실 tmux·실 Slack 0 · ④′ OSError = open 대역 주입(권한·폴더 바꾸기 0 · 하드 룰 19) · sleep 0.
기준판(팩 origin/nano/r1822-keeper-tmux-pane-target 3e75134e) = ① ② ③ ③‴ ④ Red(카드 후보 0) · 나머지 = 경계·대조.
"""
import builtins
import importlib.util
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1819", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, FT2, AB, _lines, _put = kw.World, kw.FT2, kw.AB, kw._lines, kw._put
FT = "feature"
TEAMS = kw.TEAMS + "| feature | `design/teams/feature/` |\n| chatbot | `design/teams/chatbot/` |\n"
F6 = "F-6652-2-start-settings-api"
K8 = "design/teams/chatbot/indices/진행/C-k8-rt-left-toggle-ui-tts-readout.md"
K7 = "design/teams/chatbot/indices/대기/C-k7d-seal-hook-server-event-entry-no-answer.md"
A1A, A1B = "C-k7d-a1a-seal-bot-turn", "C-k7d-a1b-seal-user-turn"


def world(tmp, mp, ft2=FT2):
    w = World(tmp, mp, ft2)
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"design/TEAMS.md": TEAMS}, ref)
    _put(w.root / ".fable-team" / "seats-feature.json", {"_master": "M-feature"})
    return w.enable(FT) or w
def card(w, path, *lands):   # 카드 1장 = 두 ref 에 같은 본문 · lands = 착지 줄 꼬리(«: sha» 또는 «(work): sha»)
    body = "# 인덱스\n- 상태: 진행\n" + "".join("- 착지%s\n" % x for x in lands)
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {path: body}, ref)
def cmap(w, *rows):   # 짝 표 = <work>\t<경로> 줄 (팀장이 쓰는 일반 파일)
    _put(w.runtime(FT) / "cards.tsv", "".join(r + "\n" for r in rows))
def run(w, *works):
    for work in works:
        w.work(work, team=FT, alive=True)
    return w.round()
def done(w, lines, n):
    assert w.kinds("complete", FT) == n and len(w.tmux("kill-session")) == n, lines
def held(lines, work, why):
    assert any(x.startswith("HELD feature %s" % work) and why in x for x in lines), lines
def c1(w):   # ① 정확한 stem 카드 + 조상 착지 줄 → complete 1
    card(w, "design/teams/feature/indices/대기/%s.md" % F6, ": " + w.pack_sha())
    done(w, run(w, F6), 1)
def c1b(w):  # ①′ r 번호 접두(r1812-x.md) → 지금과 같음
    card(w, "design/teams/feature/indices/진행/r1812-x.md", ": " + w.pack_sha())
    done(w, run(w, "r1812"), 1)
def c1c(w):  # ①″ F-6652-2.md 와 F-6652-2-a.md 둘 다 → 정확한 것만(접두 카드 sha 는 다름 · 섞이면 충돌)
    sha = w.pack_sha()
    card(w, "design/teams/feature/indices/진행/F-6652-2.md", ": " + sha)
    card(w, "design/teams/feature/indices/진행/F-6652-2-a.md", ": " + AB)
    lines = run(w, "F-6652-2")
    assert any(x.startswith("COMPLETED feature F-6652-2 착지 " + sha) for x in lines), lines
def c2(w):   # ② 짝 표 → 남의 팀(chatbot) 폴더 카드 착지 줄로 판정
    card(w, K8, ": " + w.pack_sha()), cmap(w, "C-k8-rt-left-toggle-ui-tts-readout\t" + K8)
    done(w, run(w, "C-k8-rt-left-toggle-ui-tts-readout"), 1)
def c2b(w):  # ②′ 짝 표 경로가 어느 ref 에도 없음 → «짝 표 카드 없음»
    cmap(w, "C-k8x\tdesign/teams/chatbot/indices/진행/C-k8x-none.md")
    lines = run(w, "C-k8x")
    held(lines, "C-k8x", "짝 표 카드 없음 design/teams/chatbot/indices/진행/C-k8x-none.md"), done(w, lines, 0)
def c2c(w):  # ②″ 같은 work 두 줄 → 판정 불가
    card(w, K8, ": " + w.pack_sha()), cmap(w, "C-k8\t" + K8, "C-k8\t" + K7)
    lines = run(w, "C-k8")
    held(lines, "C-k8", "판정 불가"), done(w, lines, 0)
def c3(w):   # ③ 조각 → 부모 카드의 «착지(<work>)» 줄 sha
    sha = w.pack_sha()
    card(w, K7, "(%s): %s" % (A1A, sha), ": " + AB), cmap(w, "%s\t%s" % (A1A, K7))
    lines = run(w, A1A)
    assert any(x.startswith("COMPLETED feature %s 착지 %s" % (A1A, sha)) for x in lines), lines
def c3b(w):  # ③′ 부모에 일반 착지 줄만 · 조각 행 2 → 둘 다 조각 착지 줄 없음 · complete 0 · kill 0
    card(w, K7, ": " + w.pack_sha()), cmap(w, "%s\t%s" % (A1A, K7), "%s\t%s" % (A1B, K7))
    lines = run(w, A1A, A1B)
    held(lines, A1A, "조각 착지 줄 없음"), held(lines, A1B, "조각 착지 줄 없음"), done(w, lines, 0)
def c3c(w):  # ③″ 짝 표 append 도중(조각 행 1) · 부모 일반 착지 줄만 → 조각 착지 줄 없음 · complete 0 · kill 0
    card(w, K7, ": " + w.pack_sha()), cmap(w, "%s\t%s" % (A1A, K7))
    lines = run(w, A1A)
    held(lines, A1A, "조각 착지 줄 없음"), done(w, lines, 0)
def c3d(w):  # ③‴ 짝 표 행이 자기 카드(남의 팀 C-k8 · 일반 착지 줄) → 그 sha
    sha = w.pack_sha()
    card(w, K8, ": " + sha), cmap(w, "C-k8\t" + K8)
    lines = run(w, "C-k8")
    assert any(x.startswith("COMPLETED feature C-k8 착지 " + sha) for x in lines), lines
def c4(w):   # ④ 탭 없는 줄 1 → 그 줄만 무시 · 경고 1줄 · 나머지 줄 그대로
    card(w, K8, ": " + w.pack_sha()), cmap(w, "탭 없는 줄", "C-k8\t" + K8)
    lines = run(w, "C-k8")
    assert sum(x.startswith("경고 feature") and "짝 표" in x for x in lines) == 1, lines
    done(w, lines, 1)
def c4b(w, mp):  # ④′ 짝 표 읽기 OSError(open 대역) → 그 팀 판정 불가 · 닫기 0
    card(w, K8, ": " + w.pack_sha()), cmap(w, "C-k8\t" + K8)
    real = builtins.open

    def fake(path, *a, **o):
        if str(path).endswith("cards.tsv"):
            raise PermissionError(13, "대역 주입")
        return real(path, *a, **o)
    mp.setattr(builtins, "open", fake)
    lines = run(w, "C-k8")
    mp.setattr(builtins, "open", real)
    held(lines, "C-k8", "판정 불가 · 짝 표"), done(w, lines, 0)
    assert _lines(str(w.close) + ".log") == []
CASES = {"①": c1, "①′": c1b, "①″": c1c, "②": c2, "②′": c2b, "②″": c2c,
         "③": c3, "③′": c3b, "③″": c3c, "③‴": c3d, "④": c4, "④′": c4b}
KL = "adapters/pi/keeper_land.py"
MUTANTS = {"M1": ('exact = work + ".md" in names', "exact = False", c1),
           "M2": (" if exact else ", " or ", c1c),
           "M3": ("mapped = cards.get(work)", "mapped = None", c2),
           "M4": ('m.group(1) + "/indices"', '"design/teams/%s/indices" % team', c2),
           "M5": ("land = LAND if own else", "land = LAND if True else", c3),
           "M6": ("own = name ==", "own = sum(v == mapped for v in cards.values()) < 2 or name ==", c3c)}


def call(case, w, mp):
    return case(w, mp) if case is c4b else case(w)
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    call(CASES[name], world(tmp_path, monkeypatch), monkeypatch)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KL).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KL).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        call(case, world(tmp_path / "w1", monkeypatch, tree), monkeypatch)
    call(case, world(tmp_path / "w2", monkeypatch), monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
