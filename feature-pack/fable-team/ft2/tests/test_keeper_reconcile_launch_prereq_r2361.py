"""r2361 ft2 keeper — 이미 연 fill 을 다시 맞추다 좌석이 없어 복구 launch 를 할 때도, 새 카드를 고를 때와 같은 카드 판정(row[3])을 한 번 본다 (반례 ①~⑨ · 변이 M1~M6).
대역 = r2058 세계(test_launch_failed_end · 임시 root·git·가짜 tmux·가짜 launch·record·mbox·주입 시계) 한 바퀴.
실 tmux·명부·ft2 원장·Slack·설치 0 · sleep 0 · 네트워크 0(임시 bare 리포만). 기준판(복구 갈래 판정 없음) = ① Red.
"""
import importlib.util
import json
import shutil  # noqa: E401
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_r2361_r2058", str(HERE / "test_launch_failed_end.py"))
fe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fe)
kw, FT2, TEAM = fe.kw, fe.FT2, fe.TEAM
A, B, REF, W = "r9001-a", "r9002-b", "r9101-ref", "r9999-moved"
WAIT = "- 대기 사유: 오빠 결정 2건 · 답 전 나노 0\n"
KN = "adapters/pi/keeper_next.py"


def nh(stem):
    return "byz-%s-nano-%s#0" % (TEAM, stem)


def live(w, stem):   # 좌석 세션 살아 있음(원장 = 아직 0 · record 자리)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    kw._put(w.tm, dict(d, alive=d["alive"] + [nh(stem)], pane={nh(stem): "✻ Brewed for 3s\n❯ "}))


def opened(w, stem=A, attempt="a1"):   # 이미 연 fill 1개(keeper 상태 파일 · 띄운 때 attempt)
    kw._put(w.state / "ft2-keeper" / "state.json", {"fill_open": {"%s|%s" % (TEAM, stem): attempt}})


def st(w):
    path = w.state / "ft2-keeper" / "state.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def rec(w):   # 가짜 record 호출 기록(인자 1줄씩)
    return kw._lines(str(w.tmp / "bin" / "record") + ".log")


def skips(lines, stem=A):
    return [x for x in lines if x.startswith("RECONCILE-SKIP %s %s" % (TEAM, stem))]


def c1(w):   # ① 대기 사유 카드 1장 + 좌석 없음 → launching 0 · handled 0 · fill_open 에 남음(기준판 = launching 1 → Red)
    lines = w.round()
    assert fe.launched(w) == [], (lines, fe.launched(w))
    assert skips(lines) and "대기사유" in skips(lines)[0], lines
    assert "%s|%s" % (TEAM, A) in (st(w).get("fill_open") or {}) and not (st(w).get("handled") or {}), (st(w), lines)


def c2(w):   # ② 같은 상태 · 판정 "" → launching 1(지금 그대로) · RECONCILE-SKIP 0
    lines = w.round()
    assert fe.launched(w) == [A] and not skips(lines), (lines, fe.launched(w))


def c3(w):   # ③ 바퀴 2 · 판정 그대로 → RECONCILE-SKIP 1줄(값이 같으면 0줄)
    assert len(skips(w.round())) == 1
    two = w.round()
    assert not skips(two) and fe.launched(w) == [], (two, fe.launched(w))


def c4(w):   # ④ 판정 "" 로 풀림 → launching 1 · 기억 지움
    w.round()
    fe.cards(w, A, "# 인덱스: %s\n- 상태: 대기\n" % A)
    lines = w.round()
    assert fe.launched(w) == [A] and not skips(lines), (lines, fe.launched(w))
    assert "%s|%s" % (TEAM, A) not in (st(w).get("reconcile_seen") or {}), st(w)


def c5a(w):   # ⑤a «선행» → launching 0
    lines = w.round()
    assert fe.launched(w) == [] and " 선행" in skips(lines)[0], (lines, fe.launched(w))


def c5b(w):   # ⑤b «선행불명» → launching 0
    lines = w.round()
    assert fe.launched(w) == [] and " 선행불명" in skips(lines)[0], (lines, fe.launched(w))


def c5c(w):   # ⑤c 배정 대기 사유(MARK «사람») → launching 0
    lines = w.round()
    assert fe.launched(w) == [] and " 사람" in skips(lines)[0], (lines, fe.launched(w))


def c6(w):   # ⑥ 카드가 대기/ 에 없음(진행/ 로 옮김) → 판정 추가 0 · 지금 길 그대로(«대상 못 정함» · handled)
    lines = w.round()
    assert fe.launched(w) == [] and not skips(lines), lines
    assert any(x.startswith("HELD-NEXT %s" % TEAM) and "대상 못 정함" in x for x in lines), lines


def c7(w):   # ⑦ 좌석 alive · 원장 ≠ seat → record 맞춤 그대로(판정 «대기사유» 여도 launch 길 아님)
    lines = w.round()
    assert fe.launched(w) == [] and not skips(lines), (lines, fe.launched(w))
    assert any(x.startswith("record %s seat" % A) for x in rec(w)), rec(w)


def c8(w):   # ⑧ pick 있는 새 fill(같은 바퀴 choose 통과) → 판정 다시 0 · launching 1
    lines = w.round()
    assert fe.launched(w) == [A] and not skips(lines), (lines, fe.launched(w))


def c9(w):   # ⑨ fill_open 막힌 A + 고를 수 있는 B → 같은 바퀴 B launching 1 · A 부름 0 · A fill_open 에 남음
    lines = w.round()
    assert fe.launched(w) == [B], (lines, fe.launched(w))
    assert skips(lines) and "%s|%s" % (TEAM, A) in (st(w).get("fill_open") or {}), (lines, st(w))


CASES = {"①": (c1, {A: WAIT}), "②": (c2, {A: ""}), "③": (c3, {A: WAIT}), "④": (c4, {A: WAIT}),
         "⑤a": (c5a, {A: "- 선행: r9101\n"}), "⑤b": (c5b, {A: "- 선행: r7777\n"}),
         "⑤c": (c5c, {A: "- 배정: 대기(사람 · 2026-11-20)\n"}), "⑥": (c6, None),
         "⑦": (c7, {A: WAIT}), "⑧": (c8, {A: ""}), "⑨": (c9, {A: WAIT, B: ""})}


def seat(w, stem=A):   # 나노 1석(접수·배정·전달) · launch intent 는 지운다(= 아직 안 열림 · 띄우면 spawn)
    fe.seat(w, stem)
    path = w.runtime() / "launch" / ("%s@a1.intent" % stem)
    path.unlink() if path.exists() else None


def setup(w, name):
    """세계 준비 — ⑤a = 참조 카드(진행/) · ⑥ = 카드가 대기/ 에 없음 · ⑦ = 살아 있는 좌석 · ⑧ = 새 fill(이미 연 fill 0) · 나머지 = 이미 연 fill."""
    if name == "⑤a":
        w.commit("byz", {"design/harness/indices/진행/%s-x.md" % REF: "# 인덱스: %s\n- 상태: 대기\n" % REF}, "main")
    if name == "⑥":
        w.commit("byz", {"design/harness/indices/진행/%s-x.md" % W: "# 인덱스: %s\n- 상태: 대기\n" % W}, "main")
    if name == "⑧":
        return
    seat(w)
    live(w, A) if name == "⑦" else None
    opened(w)


def run(name, tmp, mp, ft2=FT2):
    case, cards = CASES[name]
    w = fe.world(tmp, mp, cards=cards, ft2=ft2, nano_max="1")
    setup(w, name)
    case(w)


SKIP = """        if pick is None and recov_skip(k, team, stem):   # r2361 K1 — 복구 launch 도 새 고르기와 같은 카드 판정(row[3])
            return BLOCKED
"""
MUTANTS = {   # (고칠 파일, [(고칠 글자, 새 글자)], 반드시 FAIL 이어야 하는 사례)
    "M1": (KN, [(SKIP, "")], "①"),   # 복구 갈래 판정 검사 지움
    "M2": (KN, [("            return BLOCKED\n",
                 '            return k.state["handled"].update({"%s|%s@%s" % (team, work, attempt): k.stamp()}) or BLOCKED\n')], "④"),   # 막힘 때 handled 씀
    "M3": (KN, [("    if book.get(key) != pre:", "    if True:")], "③"),   # 값 같을 때도 줄 씀
    "M4": (KN, [("    return pre\n", '    return pre if pre == "대기사유" else ""\n')], "⑤a"),   # «대기사유» 만 막음
    "M5": (KN, [('    pre = "" if isinstance(got, str) or stem not in got[0] else got[0][stem][3]',
                 '    pre = "배정됨" if stem in ((ft2_state(k, team) or {}).get("owners") or {}) else "" if isinstance(got, str) or stem not in got[0] else got[0][stem][3]'),
                ("        if pick is None and recov_skip(k, team, stem):", "        if recov_skip(k, team, stem):")], "⑧"),   # pick 있는 길에도 판정
    "M6": (KN, [("    mine = [x for x in mine if x not in blocked]", "    mine = list(mine)")], "⑨"),   # 막힌 항목도 mine 에 셈
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, pairs, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / path).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
