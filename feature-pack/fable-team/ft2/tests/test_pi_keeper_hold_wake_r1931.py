"""r1931 ft2 keeper 판정 갈래 — 카드 «- 판정: HOLD» 줄이 늘면 holder 깨움 1회 · 누적 3 = 깨움 0 + 인터뷰 길 로그 (카드 반례 ①~⑨ · DA 보정 ⑩⑪ · 변이 M1~M6).
입력 = r1813 시험 대역(World: 실제 core · 가짜 tmux·ps·세션 파일 · 주입 시계) + 데이터 root 를 git 으로(카드 ref = origin/main·origin/ops/main-base).
sleep 0 · 실 tmux·pi 0. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r1813_world_for_r1931", str(FT2 / "tests" / "test_pi_keeper_stall_r1813.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
W, M, H0 = B.W, B.M, B.H0
HP = "byz-planner-nano-%s-t#0" % W
TEAMS = "| 팀 | 폴더 |\n|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` |\n| planner | `design/teams/planner/` |\n"
SHA = "ab" * 20


def _card(w, holds=0, approves=0, folder="design/harness", head="", tail=()):
    """카드 1장(상태 줄 HOLD n · APPROVE m)을 root 에 커밋 → origin/main·origin/ops/main-base 둘 다 그 커밋."""
    root = w.root
    if not (root / ".git").exists():
        B._git(root, "init", "-q", "-b", "main")
        for key, val in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
            B._git(root, "config", key, val)
    rows = ["- 판정: HOLD design/da/DA-%d.md %s" % (i, SHA) for i in range(holds)]
    rows += ["- 판정: APPROVE design/da/DA-ok%d.md %s" % (i, SHA) for i in range(approves)]
    B._put(root / "design" / "TEAMS.md", TEAMS)
    B._put(root / folder / "indices" / "대기" / ("%s.md" % W), "# 인덱스: %s\n%s\n## 상태\n" % (W, head) + "".join(x + "\n" for x in rows + list(tail)) + "\n## 메모\n- 판정: HOLD design/da/DA-x.md %s\n" % SHA)
    B._git(root, "add", "design"), B._git(root, "commit", "-q", "--allow-empty", "-m", "card")
    for ref in ("main", "ops/main-base"):
        B._git(root, "update-ref", "refs/remotes/origin/" + ref, "HEAD")


def _holds(w):   # HOLD 깨움 문구(-l) 수
    return sum(1 for x in w.tmux("send-keys") if "-l" in x["a"] and x["a"][-1].startswith("[판정] HOLD"))


def _quiet(w):   # 멈춤 깨움이 안 나는 좌석(진척 1분 전)
    w.seat(step=-1 * M, commit=-1 * M, mtime=-1 * M)


def c1(w):   # ① 0 → 1 = 깨움 1(Escape·문구·Enter) · WOKE 판정 HOLD
    _quiet(w), _card(w, 0), w.round()
    assert _holds(w) == 0
    _card(w, 1)
    lines = w.round(M)
    assert _holds(w) == 1 and ("WOKE harness %s %s 판정 HOLD" % (W, H0)) in lines, lines
    assert [x["a"][3:][-1] for x in w.tmux("send-keys")][-3::2] == ["Escape", "Enter"]


def c2(w):   # ② 같은 n 으로 다음 바퀴 = 깨움 0
    c1(w), w.round(2 * M)
    assert _holds(w) == 1


def c3(w):   # ③ 1 → 2 = 깨움 1(누계 2)
    c1(w), _card(w, 2), w.round(2 * M)
    assert _holds(w) == 2 and w.k.state["hold"] == {"harness|%s" % W: 2}


def c4(w):   # ④ 2 → 3 = 깨움 0 + 인터뷰 길 로그 1 · 다음 바퀴 로그 0
    c3(w), _card(w, 3)
    lines = w.round(3 * M)
    assert _holds(w) == 2 and lines.count("HELD harness %s HOLD 누적 3 — 인터뷰 길(하드 룰 14)" % W) == 1, lines
    assert not [x for x in w.round(4 * M) if "인터뷰 길" in x] and _holds(w) == 2


def c5(w):   # ⑤ HOLD 2 뒤 멈춤 재배정(a1 → a2) · 카드 n = 3 → 깨움 0 + 인터뷰 길 로그(누적 유지)
    w.seat(), _card(w, 1), w.round()
    assert _holds(w) == 1
    _card(w, 2), w.round(11 * M)
    assert json.loads((w.runtime() / "launch" / ("%s@a2.intent" % W)).read_text(encoding="utf-8"))["state"] == "opened"
    before = _holds(w)
    _card(w, 3)
    lines = w.round(12 * M)
    assert _holds(w) == before and any("HOLD 누적 3 — 인터뷰 길" in x for x in lines), lines


def c6(w):   # ⑥ APPROVE 줄만 늚 → 깨움 0
    _quiet(w), _card(w, 0), w.round(), _card(w, 0, 1), w.round(M)
    assert _holds(w) == 0 and w.tmux("send-keys") == []


def c7(w):   # ⑦ 멈춤 깨움을 이미 쓴 attempt 에서도 HOLD 0 → 1 = 깨움 1
    w.seat(step=-16 * M), _card(w, 0)
    assert ("WOKE harness %s %s" % (W, H0)) in w.round() and _holds(w) == 0
    _card(w, 1), w.round(M)
    assert _holds(w) == 1


def c8(w):   # ⑧ 카드 못 읽음(root 에 ref 없음) → 판정 불가 1줄 · 깨움 0
    _quiet(w)
    lines = w.round()
    assert _holds(w) == 0 and [x for x in lines if x.startswith("판정 불가 harness %s HOLD 판독" % W)], lines


def c9(w):   # ⑨ harness/W 첫 HOLD → 깨움 1 · 그 뒤 planner/W 첫 HOLD → 깨움 1 · state 키 2개
    c1(w)
    _card(w, 1, folder="design/teams/planner")
    B._put(w.root / ".fable-team" / "teams" / "planner" / "runtime" / "launch" / ("%s@a1.intent" % W), {"FT2_HOLDER": HP, "state": "opened"})
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    B._put(w.tm, dict(d, alive=d["alive"] + [HP]))
    k = w.keeper()
    k.locked(lambda: type(k).__init__.__globals__["hold"].check(k, "planner", W, "a1", []))
    assert _holds(w) == 2 and sorted(k.state["hold"]) == ["harness|%s" % W, "planner|%s" % W]


def c10(w):   # ⑩ 상태 구역 앞 예문 줄(온전한 꼴 포함) → HOLD 0 · 깨움 0
    head = "- 고치는 곳: 판정 줄 꼴\n- 판정: HOLD design/da/DA-ex.md %s\n- 판정: HOLD <판정문 경로> <세트 sha40>\n" % SHA
    _quiet(w), _card(w, 0), w.round(), _card(w, 0, head=head), w.round(M)
    assert _holds(w) == 0 and w.tmux("send-keys") == []


def c11(w):   # ⑪ 상태 구역 안 형식 불명 줄(sha 없음·짧은 sha·꼬리 글)만 늚 → 깨움 0 · 온전한 줄 1 → 깨움 1
    bad = ("- 판정: HOLD", "- 판정: HOLD design/da/DA-a.md", "- 판정: HOLD design/da/DA-b.md abab1234", "- 판정: HOLD 사전 DA %s 보정" % SHA)
    _quiet(w), _card(w, 0), w.round(), _card(w, 0, tail=bad), w.round(M)
    assert _holds(w) == 0
    _card(w, 1, tail=bad), w.round(2 * M)
    assert _holds(w) == 1


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10, "⑪": c11}
KH = "adapters/pi/keeper_hold.py"
MUTANTS = {"M1": ("    if n >= 3:\n", "    if False:\n", c4),
           "M2": ("    if n <= seen:\n        return None\n", "", c2),
           "M3": ("    if k.stall.guard(team, work, holder, rows):", "    if k.stall.guard(team, work, holder, rows) and not k.state.get(\"woke\"):", c7),
           "M4": ('n, key = holds(k, team, work), "%s|%s" % (team, work)', "n, key = holds(k, team, work), work", c9),
           "M5": ("sum(len(HOLD.findall(part)) for part in STATE.findall(body))", "len(HOLD.findall(body))", c10),
           "M6": (r"HOLD \S+ [0-9a-f]{40}[ \t]*$", r"HOLD(?=\s|$)", c11)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](B.World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KH).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KH).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(B.World(tmp_path / "w1", monkeypatch, tree))
    case(B.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
