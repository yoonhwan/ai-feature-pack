"""r2000 ft2 keeper — complete 직전 «- 남은 범위:» 관문 시험 (카드 반례 ①~⑧ · DA 직접 회귀 · 변이 M1~M3).
임시 git 리포 2쌍 + 가짜 tmux·쪽지(keeper_world_r1812 대역) · 실 리포·tmux·runtime 0 · sleep 0.
⑨ 1.x followup_gate 와 같은 7 픽스처 = J 표(판정 기대값은 1.x 시험 r1997 과 같음 · 1.x 실행 대조는 리포 밖 러너 · ft2 → 1.x import 0).
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location("keeper_world_r1812", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kw)
World, FT2, TEAM, _lines, _put = kw.World, kw.FT2, kw.TEAM, kw._lines, kw._put
IDX = "design/harness/indices"


def card(w, work, *left, sha=None, refs=("main", "ops/main-base"), folder=IDX, stage="진행"):
    sha = sha or w.pack_sha()   # left = «- 남은 범위:» 값(줄마다 1개 · 생략 = 줄 없음) · 착지 = 팩 main 새 sha
    body = "# 인덱스: %s\n- 착지: %s\n" % (work, sha) + "".join("- 남은 범위: %s\n" % v for v in left)
    for ref in refs:
        w.commit("byz", {"%s/%s/%s-x.md" % (folder, stage, work): body}, ref)
    return sha
def follow(w, rel):   # 후속 카드 파일 1장(두 ref)
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {"%s/%s" % (IDX, rel): "# 인덱스\n"}, ref)
def run(w, work, *left, **kw_):
    card(w, work, *left, **kw_), w.work(work, intent=False)
    return w.round()
def ok(w, lines, work, n=1):
    assert w.kinds("complete") == n and any(x.startswith("COMPLETED harness " + work) for x in lines), lines
def held(w, lines, work, why, n=0):
    assert w.kinds("complete") == n and any(x.startswith("UNKNOWN harness %s 남은 범위" % work) and why in x for x in lines), lines
def mails(w, work):
    return sum(work in x and ("[긴급] UNKNOWN" not in x or "착지했지만" in x) for x in _lines(str(w.mbox) + ".log"))   # r2055 settle [긴급] 은 셈 밖 · 관문 쪽지 = «[긴급] UNKNOWN … 착지했지만»
def c1(w):   # ① 착지 있음 · 줄 없음 → complete 0 · HELD · 팀장 1통
    held(w, run(w, "r9801"), "r9801", "줄 없음")
    assert mails(w, "r9801") == 1
def c2(w):   # ② 없음 → complete 1 · 근거 카드 ref:경로
    lines = run(w, "r9802", "없음 — 다 끝남")
    ok(w, lines, "r9802")
    assert any("카드 origin/ops/main-base:%s/진행/r9802-x.md" % IDX in x for x in lines), lines
def c3(w):   # ③ r9002 대기/ 실재 → complete
    follow(w, "대기/r9002-registry.md"), ok(w, run(w, "r9803", "r9002 — 등록표"), "r9803")
def c4(w):   # ④ r9002 없음 → HELD
    held(w, run(w, "r9804", "r9002 — 등록표"), "r9804", "후속 카드 r9002 없음")
def c5(w):   # ⑤ 이름 없는 설명뿐 → HELD
    held(w, run(w, "r9805", "등록표 일반화 남음"), "r9805", "후속 카드 이름 없음")
def c6(w):   # ⑥ 두 줄 · 앞 r9002 없음 · 뒤 «없음» → complete
    ok(w, run(w, "r9806", "r9002 — 등록표", "없음"), "r9806")
def c6b(w):  # ⑥′ 역방향 · 앞 «없음» · 뒤 r9002 없음 → HELD
    held(w, run(w, "r9816", "없음", "r9002 — 등록표"), "r9816", "r9002 없음")
def c7(w):   # ⑦ 자기 r 번호·자기 stem → HELD
    held(w, run(w, "r9807", "r9807 — 자기 머리"), "r9807", "자기 자신")
    held(w, run(w, "r9817", "r9817-x — 자기 stem"), "r9817", "자기 자신")
def c8(w):   # ⑧ 같은 HELD 다음 바퀴 → 팀장 0통 · 카드 고치면 다음 바퀴 complete(state.handled 영구 skip 0)
    held(w, run(w, "r9808"), "r9808", "줄 없음")
    held(w, w.round(), "r9808", "줄 없음")
    assert mails(w, "r9808") == 1
    card(w, "r9808", "없음"), ok(w, w.round(), "r9808")
def c8b(w):  # ⑧′ 쪽지 실패 → state.sent 0 → 다음 바퀴 다시 보냄
    _put(str(w.mbox) + ".rc", "1"), held(w, run(w, "r9818"), "r9818", "줄 없음")
    assert mails(w, "r9818") == 2   # 7초 + 재시도 1 둘 다 실패
    _put(str(w.mbox) + ".rc", "0"), w.round(), w.round()
    assert mails(w, "r9818") == 3 and w.kinds("complete") == 0
def d1(w):   # 완성후/ 후속 실재 → complete · 아카이브/ 만 → HELD
    follow(w, "완성후/f7-next.md"), follow(w, "아카이브/2026-11/f8-old.md")
    ok(w, run(w, "r9821", "f7-next — 완성후"), "r9821")
    held(w, run(w, "r9822", "f8-old — 아카이브"), "r9822", "f8-old 없음", n=1)
def d2(w):   # 숫자 경계 · r900 ≠ r9002-registry · 설명 속 번호 안 주움
    follow(w, "대기/r9002-registry.md")
    held(w, run(w, "r9823", "r900 — r9002 와 같이"), "r9823", "r900 없음")
def d3(w):   # 여러 후속 · 하나라도 없으면 HELD · 다 있으면 complete
    follow(w, "대기/r9002-registry.md"), follow(w, "진행/f7-next.md")
    held(w, run(w, "r9824", "f7-next · f7-miss — 둘"), "r9824", "f7-miss 없음")
    card(w, "r9824", "r9002 · f7-next — 둘"), ok(w, w.round(), "r9824")
def d4(w):   # 출처 · ops/main-base 본문(없음)이 main 본문(줄 없음)보다 먼저 · 같은 착지 sha
    sha = card(w, "r9825", "없음", refs=("ops/main-base",))
    card(w, "r9825", sha=sha, refs=("main",)), w.work("r9825", intent=False)
    ok(w, w.round(), "r9825")
def d5(w):   # 짝 표 카드(다른 팀 폴더) → 그 카드의 indices 루트에서 후속을 찾는다
    other = "design/other/indices"
    card(w, "r9826", "q1-next — 남의 폴더", folder=other)
    for ref in ("main", "ops/main-base"):
        w.commit("byz", {other + "/대기/q1-next.md": "# 인덱스\n"}, ref)
    _put(w.runtime() / "cards.tsv", "r9826\t%s/진행/r9826-x.md\n" % other), w.work("r9826", intent=False)
    ok(w, w.round(), "r9826")
def d6(w):   # 판정 불가 · 본문 캐시 없음 → complete 0 · HELD
    w.card("r9827", w.pack_sha()), w.work("r9827", intent=False)
    k = w.keeper()
    assert k.complete(TEAM, "r9827", "a1", ("a" * 40, "pack:origin/main", "")) is None and w.kinds("complete") == 0
    assert any("판정 불가 · 카드 본문 못 정함" in x for x in k.lines)
J = [("줄 없음", [], "줄 없음"), ("없음", ["없음"], ""), ("실재", ["r9002 — 등록표"], ""), ("이름 없음", ["등록표 일반화 남음"], "이름 없음"),
     ("마지막", ["r9404 — x", "없음"], ""), ("자기", ["r9002 — x", "f7-next · f7 — 섞임"], "자기 자신"), ("r 머리", ["r9100 — 자기"], "자기 자신")]
CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑥′": c6b, "⑦": c7, "⑧": c8, "⑧′": c8b,
         "완성후": d1, "숫자 경계": d2, "여러 후속": d3, "출처": d4, "짝 표": d5, "본문 없음": d6}
FU = "adapters/pi/followup.py"
MUTANTS = {"M1": ('return "줄 없음 — ', 'return "" and "줄 없음 — ', c1),
           "M2": ("if n not in have and not", "if False and n not in have and not", c4),
           "M3": ("val = found[-1].strip()", "val = found[0].strip()", c6)}
@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))
@pytest.mark.parametrize("name,left,why", J, ids=[x[0] for x in J])
def test_same_as_1x(name, left, why):   # ⑨ 1.x 픽스처 7개 · me = f7 / r9100-self 꼴 · 실재 = r9002-registry·f7-next
    fu, body = kw._mod(FT2 / FU, "fu_%s" % name), "".join("- 남은 범위: %s\n" % v for v in left)
    me = {"자기": "f7", "r 머리": "r9100-self"}.get(name, "f1")
    got = fu.judge(body, me, lambda: {"r9002-registry", "f7-next"} if name != "마지막" else set())
    assert (why in got if why else got == ""), got
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / FU).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / FU).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        case(World((tmp_path / "w1").mkdir() or tmp_path / "w1", monkeypatch, tree))
    case(World((tmp_path / "w2").mkdir() or tmp_path / "w2", monkeypatch))   # 원본 = PASS
