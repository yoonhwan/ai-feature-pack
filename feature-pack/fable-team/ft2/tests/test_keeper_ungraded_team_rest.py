"""ft2 keeper 팀 자리 Ungraded — 한 팀의 느린 git 이 뒤 팀을 굶기지 않는다 (반례 52가~바 · 변이 M129 · M131 · M132 · M137).

카드 ft2-keeper-ungraded-team-rest · 계약 T1(뒤 팀이 돈다) · T2(남은 자리 0 · 분모 손 0) · T3(Cut·cursor 그대로) · T4(b3).
원천 = b2f(빈 칸 채우기) 다 — BYZ keeper 로그 17~18일 16138줄에서 팀 자리 Ungraded 49줄이 전부 그 칸이다(«읽은 것» 절 실측).
대역 = `test_keeper_round_60s.Rig` 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run(요청 상한과 자기 소요 중 작은 값만큼 시계를 올린다) ·
가짜 journal·카드·tmux·mbox(인자만 기록) · sleep 0 · 네트워크 0 · 실 runtime·실 git·실 tmux 0. 새 대역 0.
"""
import re
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig, _next, field, line


def _three(w):
    """팀 3개(a · b · c) · 팀마다 work 1장 — 이름순으로 도는 차례가 그대로 보인다."""
    w.teams, w.works = ["a", "b", "c"], {t: ["w1"] for t in ("a", "b", "c")}


def _slow_fill(w, who, seconds=8.0):
    """b2f(빈 칸 채우기) 안의 git 판독 1회가 7초를 넘게 한다 — 그 팀 자리 Ungraded 의 실제 원천(실측 49/49 = b2f)."""
    g = w.mod.Keeper.__init__.__globals__

    def fill(k, team):
        w.done.append(["fill", team])
        if team == who:
            w.reads(("git", "-C", str(w.root), "merge-base", "a", "b"), seconds)
        return None
    g["closing"].keeper_next.fill = fill


def _lands(w, done=0):
    return [d for d in w.done[done:] if d[0] == "land"]


def _ratio(w):
    got, allm = field(w.k, "items").split("/")
    assert int(allm) > 0, w.k.lines
    return got == allm


# ── 52가~바 ──────────────────────────────────────────────────────────────────
def c_52ga(w):   # 52가 a 의 b2f git 판독 1회 7초 넘음 → 판정 불가 1줄 · b · c 가 모두 돈다 · cut=- · items N/N
    _three(w)
    _slow_fill(w, "a")
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 a - git 7초 넘음"], w.k.lines
    assert _lands(w) == [["land", "a", "w1"], ["land", "b", "w1"], ["land", "c", "w1"]], w.done
    assert field(w.k, "cut") == "-" and _ratio(w), w.k.lines


def c_52na(w):   # 52나 52가 + c 의 work 안 git 도 7초 넘음 → 판정 불가 2줄 · c 의 다음 work 는 돈다(:587 그대로)
    _three(w)
    w.works = {"a": ["w1"], "b": ["w1"], "c": ["w1", "w2"]}
    _slow_fill(w, "a")

    def land(team, work):
        w.done.append(["land", team, work])
        if (team, work) == ("c", "w1"):
            w.reads(("git", "-C", str(w.root), "show", "HEAD:card.md"), 8.0)
        return ("ab" * 20, "main", "")
    w.k.landing = land
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 a - git 7초 넘음", "판정 불가 c w1 git 7초 넘음"], w.k.lines
    assert ["land", "c", "w2"] in _lands(w), w.done   # work 안 Ungraded = 그 work 만 0 · 다음 work 는 그대로
    assert field(w.k, "cut") == "-" and _ratio(w), w.k.lines


def c_52da(w):   # 52다 52가를 2바퀴 연속 → 두 바퀴 모두 b · c 가 돈다 · «예산 2회 넘음» 0 · ROUND-CAP 0 · cursor 없음
    _three(w)
    _slow_fill(w, "a")
    for n in range(2):
        done = len(w.done)
        w.round()
        assert _lands(w, done) == [["land", "a", "w1"], ["land", "b", "w1"], ["land", "c", "w1"]], (n, w.done[done:])
        assert line(w.k, "판정 불가") == ["판정 불가 a - git 7초 넘음"], w.k.lines
        assert line(w.k, "ROUND-CAP") == [], w.k.lines
        assert not any("예산 2회 넘음" in x for x in w.k.lines), w.k.lines
        assert "cursor" not in w.state(), w.state()
        assert _ratio(w), w.k.lines
        if n == 0:
            w.room(**w.k.state)
            _next(w)


def c_52ra(w):   # 52라 a 의 팀 자리에서 예산 끊김(Cut) → ROUND-CAP 1줄 · cut=a:-:b2f · cursor 남음 · b · c 0
    _three(w)

    def fill(k, team):
        w.done.append(["fill", team])
        if team == "a":
            w.reads(("git", "-C", str(w.root), "read-tree", "x"), 7.0, 7)   # 7초씩 → 남은 몫 < 7초 = 그 자리에서 끊김
        return None
    w.mod.Keeper.__init__.__globals__["closing"].keeper_next.fill = fill
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP a - b2f — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "a", "work": "-", "stage": "b2f", "cuts": 1}, w.state()
    assert field(w.k, "cut") == "a:-:b2f" and _lands(w) == [["land", "a", "w1"]], w.done
    assert line(w.k, "판정 불가") == [], w.k.lines   # 예산 끊김은 판정 불가가 아니다


# 52마 기대 = 고치기 앞 판(origin/main 14d7677f)에서 같은 대역으로 잰 줄 그대로(경로만 <root> 로 바꿈)
_QUIET_LINES = [
    "FETCH-TRY <root> 1/2 rc=0 s=0",
    "FETCH-TRY <root> 1/2 rc=0 s=0",
    "SLOW-CELL a b1 s=0 n=0 slow_call=0",
    "ROUND s=0 fetch=0 b1=0 b2c=0 b2f=0 b3=0 stall=0 fetch_root=0 fetch_pack=0 wall=0 other=0 items=11/11 cut=- slow=a:b1:0",
]


def c_52ma(w):   # 52마 7초 넘음 없음 → ROUND·판정 줄이 고치기 앞 판과 바이트 같음
    _three(w)
    w.round()
    assert [re.sub(r"\S*/root\b", "<root>", x) for x in w.k.lines] == _QUIET_LINES, w.k.lines
    assert "cursor" not in w.state(), w.state()


def c_52ba(w):   # 52바 b3o 에서 git 7초 넘음 → b3r 가 돈다(T4)
    w.mod.Keeper.__init__.__globals__["endings"].orphans = lambda k, order: w.reads(("git", "show"), 8.0)
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 - - git 7초 넘음"], w.k.lines
    assert ["retired"] in w.done, w.done   # b3o 판정 불가 = b3o 만 0


CASES = {"52가": c_52ga, "52나": c_52na, "52다": c_52da, "52라": c_52ra, "52마": c_52ma, "52바": c_52ba}
MUTANTS = {
    "M129": (KP, "                except Ungraded:\n                    continue   # R7 팀 자리 판정 불가",
             "                except Ungraded:\n                    raise   # 팀 고리 밖으로 그대로", ("52가", "52다")),
    "M131": (KP, "                except Ungraded:\n                    continue   # R7 팀 자리 판정 불가",
             '                except Ungraded:\n                    self.cut_pos, self.cut = (team, "-", "b2f"), "%s:-:b2f" % team\n                    raise Cut(self.cut)',
             ("52다",)),
    "M132": (KP, "                except Ungraded:\n                    continue   # R7 팀 자리 판정 불가",
             "                except (Ungraded, Cut):\n                    continue   # R7 팀 자리 판정 불가", ("52라",)),
    "M137": (KP, "                except Ungraded:\n                    pass   # R7 b3o 판정 불가",
             "                except Ungraded:\n                    raise   # b3o 갈래 받는 곳 뺌", ("52바",)),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Rig(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w1").mkdir()
    try:   # 변이 세계 = 판정 줄이 달라지거나(AssertionError) 값이 없거나(KeyError) 심사가 선다
        CASES[cases[0]](Rig(tmp_path / "w1", tree))
    except BaseException:   # noqa: BLE001 — 어떤 실패든 변이를 잡은 것
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, cases[0]))
    for case in cases[1:]:   # 같은 변이의 다른 사례 = 원본 나무로 PASS(대조)
        assert CASES[case](Rig(tmp_path / ("c" + case), None)) is None
