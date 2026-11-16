"""r2113 ft2 keeper 다음 카드 — 카드 머리 «- 재개: <로컬 시각>» 이 최신 attempt intent · 착지 sha committer 시각보다 뒤면 «착지»·«전달됨» 으로 막지 않음 ·
40자 넘게 잘리는 stem 의 나노 이름 = 앞 33자 + «-» + sha1(stem) 6자(원장 seat 이 먼저) · 옛 40자 이름 세션도 이름겹침 (반례 ①~⑧ · 변이 M1~M7).
대역 = r2111 세계(r1871 world · 임시 root·git·가짜 tmux·launch·record · launch/<work>@<att>.intent · card-assign 원장 json).
실 tmux·명부·ft2 원장·우편함·설치 0 · sleep 0. 기준판 = ① ⑥ Red(착지 카드 재개 0 · 잘린 이름 같음).
"""
import hashlib, importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2113_r2111", str(HERE / "test_keeper_next_delivered_reopen_r2111.py"))
r11 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r11)
base, kw, hand, alive = r11.base, r11.kw, r11.hand, r11.alive
S, KN, DAY = "r9891-Re", "adapters/pi/keeper_next.py", "2026-11-16T"
LONG = "M5-goal6-upper-last-sentence-release-confirm-lag"   # 48자 · v65 실사건
L121 = "L121-long-name-long-name-long-name-long-name-followup"   # DA R1 입력(대문자 · 41자 이상)


def card(w, stem, *heads):
    w.commit("byz", {"design/harness/indices/대기/%s.md" % stem: "# 인덱스: %s\n%s- 상태: 대기\n" % (stem, "".join(h + "\n" for h in heads))}, "main")


def landed_sha(w, mp, at):   # 팩 커밋 1개 · committer 시각 = 로컬 at
    mp.setenv("GIT_COMMITTER_DATE", at)
    try:
        return w.pack_sha()
    finally:
        mp.delenv("GIT_COMMITTER_DATE")


def skip(lines, stem, why):
    return [x for x in lines if x.startswith(("NEXT-SKIP harness %s" % stem, "판정 불가 harness %s" % stem)) and why in x]


def picked(w, stem=S):
    return stem in base.launched(w)


def landed_card(w, mp, *resume):   # ①②④⑤ 공통 — 착지 14:05 · deliveries [a1, a2] · a2 at 10:50
    sha = landed_sha(w, mp, DAY + "14:05:00")
    hand(w, S, DAY + "09:00:00"), hand(w, S, DAY + "10:50:00", holder="h2")
    card(w, S, "- 착지: " + sha, *("- 재개: " + x for x in resume))


def c1(w, mp):   # ① 착지 14:05 · a2 at 10:50 · 재개 16:28 → 고름 · launch 1
    landed_card(w, mp, DAY + "16:28:00")
    lines = w.round()
    assert base.launched(w) == [S] and skip(lines, S, "착지") == [], (lines, base.launched(w))


def c2(w, mp):   # ② 재개 13:00(착지보다 앞) → 건너뜀 · 사유 «착지»
    landed_card(w, mp, DAY + "13:00:00")
    lines = w.round()
    assert not picked(w) and len(skip(lines, S, "이미 착지")) == 1, lines
    assert any("막힌 사유별 착지 1" in x for x in base.notes(w)), base.notes(w)


def c3(w, mp, at="15:00:00"):   # ③ 착지 줄 없음 · a1 at 15:37 · 재개 15:00 → 건너뜀 · «전달됨»
    hand(w, S, DAY + "15:37:00")
    card(w, S, "- 재개: " + DAY + at)
    lines = w.round()
    assert not picked(w) and len(skip(lines, S, "전달됨")) == 1, lines


def c3b(w, mp):   # ③ 둘째 칸 — 재개 16:00 → 고름
    hand(w, S, DAY + "15:37:00")
    card(w, S, "- 재개: " + DAY + "16:00:00")
    w.round()
    assert base.launched(w) == [S], base.launched(w)


def c4(w, mp):   # ④ 재개 꼴 깨짐 → 건너뜀 · «판정 불가» 1줄 · 둘째 바퀴 같은 줄 0
    landed_card(w, mp, "어제 쯤")
    lines = w.round()
    assert not picked(w) and len([x for x in lines if x.startswith("판정 불가 harness %s" % S) and "재개" in x]) == 1, lines
    more = r11.again(w)
    assert not picked(w) and [x for x in more[len(lines):] if x.startswith("판정 불가 harness %s" % S) and "재개" in x] == [], more


def c5(w, mp):   # ⑤ 재개 줄 2개(앞 16:28 · 뒤 13:00) → 마지막 줄 = 13:00 → 건너뜀
    landed_card(w, mp, DAY + "16:28:00", DAY + "13:00:00")
    lines = w.round()
    assert not picked(w) and len(skip(lines, S, "이미 착지")) == 1, lines


def tail(stem):
    return "byz-harness-nano-%s-%s#0" % (stem[:33].rstrip("-"), hashlib.sha1(stem.encode("utf-8")).hexdigest()[:6])


def old40(stem):
    return "byz-harness-nano-%s#0" % stem[:40].rstrip("-")


def c6(w, mp):   # ⑥ 41자 이상 · 원장 없음 → 앞 33자 + «-» + 해시 6자 · «…-confirm-lag» 와 «…-r2» 다름
    k, kn = w.keeper(), w.K.closing.keeper_next
    a, b = kn.nano_name(k, "harness", LONG), kn.nano_name(k, "harness", LONG + "-r2")
    assert a != b and (a, b) == (tail(LONG), tail(LONG + "-r2")), (a, b)


def c7(w, mp):   # ⑦ 41자 이상 · 원장 seat = 옛 40자 이름 → 그 이름 · launch 0 / 40자 이하 → 지금과 같음
    kw._put(w.state / "card-assign" / (LONG + ".json"), {"state": "seat", "seat": old40(LONG), "since": 1.0})
    card(w, LONG)
    w.round()
    k, kn = w.keeper(), w.K.closing.keeper_next
    assert kn.nano_name(k, "harness", LONG) == old40(LONG) and LONG not in base.launched(w), base.launched(w)
    assert kn.nano_name(k, "harness", S) == "byz-harness-nano-%s#0" % S and k.lines == [], k.lines


def c8(w, mp, name=None):   # ⑧ L121 · 원장 없음 · deliveries 0 · 옛 40자 이름(소문자) 살아 있음 → 고르지 않음 · «이름겹침» · launch 0
    card(w, L121)
    alive(w, name or old40(L121).lower())
    lines = w.round()
    assert not picked(w, L121) and L121 not in base.launched(w) and len(skip(lines, L121, "이름겹침")) == 1, lines


def c8b(w, mp):   # ⑧ 둘째 칸 — 옛 40자 이름 글자 그대로(대문자) 살아 있음 → 같음
    c8(w, mp, old40(L121))


def c8c(w, mp):   # ⑧ 셋째 칸 — 둘 다 없음 → 고름 · 새 이름(해시 꼬리)으로 launch 1
    card(w, L121)
    alive(w, "byz-harness-nano-other#0")
    lines = w.round()
    holders = {r.get("holder") for r in w.journal() if r.get("work") == L121 and r.get("holder")}
    assert base.launched(w) == [L121] and holders == {tail(L121)} and skip(lines, L121, "이름겹침") == [], (holders, lines)


CASES = {"①": c1, "②": c2, "③": c3, "③'": c3b, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑧'": c8b, "⑧''": c8c}
MUTANTS = {"M1": (" or end >= at", "", ("②",)),
           "M2": ("            if t >= at:\n                return False\n", "", ("③",)),
           "M3": ("back[-1].split", "back[0].split", ("⑤",)),
           "M4": ('        if led.get("state") == "seat" and isinstance(led.get("seat"), str) and led["seat"]:\n            return led["seat"]\n', "", ("⑦",)),
           "M5": ("sha1(stem.encode", "sha1(stem[:40].encode", ("⑥",)),
           "M6": ("x.lower() in olds or ", "", ("⑧",)),
           "M7": ("x.lower() in olds or ", "x not in olds0 and x.lower() in olds or ", ("⑧'",))}


def run(name, tmp, mp, ft2=kw.FT2):
    w = base.world(tmp, mp, {}, ft2=ft2)
    CASES[name](w, mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises(AssertionError):
            run(case, bad, monkeypatch, tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
