"""r2030 팀 폴더 밖 카드(짝 표 cards.tsv 대기 카드) — keeper 후보 · 첫 본문 카드 경로 · 나노 sparse 가 같은 자리 (T1~T8 · 변이 M1~M4).
대역 = 임시 root(짝 표·카드 루트 표) + r1871 world(임시 byz 리포·가짜 tmux·launch·record). 실 tmux·실 pi·명부·mbox·설치 0 · sleep 0.
기준판(팩 origin/main) = T1·T5·T7 Red. 변이는 ft2 사본에서만 · 원본으로 같은 사례 1회 더.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2030_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
LP, KN = "adapters/pi/launch_plan.py", "adapters/pi/keeper_next.py"
V65 = "design/teams/v65/indices/%s/w1.md"
ROOTS = "*\t.\torigin/main\tdesign/teams/*/indices\n"
NANO = "byz-knowledge-nano-w1#0"


def load(ft2, name):
    spec = importlib.util.spec_from_file_location(name, str(ft2 / LP))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def plan_root(tmp, pairs):
    """임시 root = 카드 루트 표(* 행) + knowledge 짝 표(None = 파일 0)."""
    root = tmp / "root"
    kw._put(root / ".fable-team" / "state" / "directive-roots.tsv", ROOTS)
    if pairs is not None:
        kw._put(root / ".fable-team" / "teams" / "knowledge" / "runtime" / "cards.tsv", pairs)
    return root


def body(lp, root):
    env = {"FT2_ROOT": str(root), "FT2_TEAM": "knowledge", "FT2_WORK": "w1", "FT2_ATTEMPT": "a1", "FT2_HOLDER": NANO}
    return lp.first_body(env, lp.card_row(str(root), "knowledge"))[1], env


def plain(lp, tmp):   # 기준 = 짝 표 없음 → 지금 경로(팀 폴더 대기/)
    return body(lp, plan_root(tmp / "plain", None))[0].replace(str(tmp / "plain" / "root"), "<root>")


def same_as_plain(lp, tmp, pairs):
    root = plan_root(tmp / "x", pairs)
    text = body(lp, root)[0]
    assert text.replace(str(root), "<root>") == plain(lp, tmp), text
    assert "design/teams/knowledge/indices/대기/w1.md 를 통째로" in text, text


def t1(tmp, ft2=kw.FT2):   # T1 짝 표 w1 → v65 대기 카드 = 첫 본문 카드 경로
    root = plan_root(tmp, "w1\t%s\n" % (V65 % "대기"))
    text = body(load(ft2, "lp_t1"), root)[0]
    assert "카드 %s origin/main:%s 를 통째로" % (root, V65 % "대기") in text, text


def t2(tmp, ft2=kw.FT2):   # T2 짝 표에 w1 없음 → 지금 경로(기준판과 같은 바이트)
    same_as_plain(load(ft2, "lp_t2"), tmp, "w2\t%s\n" % (V65 % "대기").replace("w1", "w2"))


def t3(tmp, ft2=kw.FT2):   # T3 짝 표에 w1 경로 2개 → 지금 경로
    same_as_plain(load(ft2, "lp_t3"), tmp, "w1\t%s\nw1\t%s\n" % (V65 % "대기", (V65 % "대기").replace("v65", "v66")))


def t4(tmp, ft2=kw.FT2):   # T4 꼴 틀림(indices 없음) → 지금 경로
    same_as_plain(load(ft2, "lp_t4"), tmp, "w1\tdesign/teams/v65/대기/w1.md\n")


def t7(tmp, ft2=kw.FT2):   # T7 plan_of sparse 끝 = 카드 폴더 · 남의 팀 제외 유지 · 짝 없음 = 지금 그대로
    lp = load(ft2, "lp_t7")
    for pairs, tail in (("w1\t%s\n" % (V65 % "대기"), ["/design/teams/knowledge/", "/design/teams/v65/indices/"]), (None, ["/design/teams/knowledge/"])):
        root = plan_root(tmp / str(bool(pairs)), pairs)
        text, env = body(lp, root)
        sparse = lp.plan_of(str(tmp), "w1@a1", str(root), "knowledge", NANO, [], str(tmp / "wt"), str(root), env, text)["sparse"]
        assert sparse[-len(tail):] == tail and "!/design/teams/*/" in sparse and sparse.count("/*") == 1, sparse


def world(tmp, mp, stage="대기", ft2=kw.FT2):
    """harness 팀 폴더 대기 카드 0 · harness 짝 표에 v65 카드 1줄 · 카드 루트 표 = harness 행 + * 행."""
    w = base.world(tmp, mp, None, ft2=ft2)
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\n" + ROOTS)
    kw._put(w.runtime() / "cards.tsv", "w1\t%s\n" % (V65 % stage))
    w.commit("byz", {V65 % stage: "# 인덱스: w1\n- 우선: 높음\n- 상태: 대기\n"}, "main")
    return w


def t5(tmp, mp, ft2=kw.FT2):   # T5 짝 표 v65 대기 카드 1장 · 팀 폴더 카드 0 → keeper 가 그 카드를 고름
    w = world(tmp, mp, ft2=ft2)
    w.round()
    assert base.launched(w) == ["w1"] and base.notes(w) == [], (base.launched(w), base.notes(w))


def t6(tmp, mp, ft2=kw.FT2):   # T6 T5 꼴 + 원장 w1 seat → 고르지 않음(배정됨 · 이중 기동 0)
    w = world(tmp, mp, ft2=ft2)
    kw._put(w.state / "card-assign" / "w1.json", {"state": "seat", "seat": "byz-knowledge-nano-w1#0"})
    w.round()
    assert base.launched(w) == [] and len(base.notes(w)) == 1 and "배정됨 1" in base.notes(w)[0], base.notes(w)


def t8(tmp, mp, ft2=kw.FT2):   # T8 짝 표 경로 단계 = 진행/ → 후보 0(대기만)
    w = world(tmp, mp, "진행", ft2=ft2)
    w.round()
    assert base.launched(w) == [] and len(base.notes(w)) == 1 and "막힌 사유별 0" in base.notes(w)[0], base.notes(w)


def t9(tmp, mp, ft2=kw.FT2):   # T9 (DA R1) 짝 work ≠ 카드 stem(별칭) → keeper 후보 0 · 로그 1줄
    w = world(tmp, mp, ft2=ft2)
    kw._put(w.runtime() / "cards.tsv", "alias-work\t%s\n" % (V65 % "대기"))
    lines = w.round()
    assert base.launched(w) == [] and lines.count("경고 harness 짝 표 별칭 — keeper 후보 0 alias-work") == 1, lines


def t10(tmp, mp, ft2=kw.FT2):   # T10 (DA R2) 짝 카드 선행 = 같은 indices 완성/ → 풀림 · 고름
    w = world(tmp, mp, ft2=ft2)
    w.commit("byz", {V65 % "대기": "# 인덱스: w1\n- 선행: r9999\n", "design/teams/v65/indices/완성/r9999.md": "# 끝난 선행\n"}, "main")
    w.round()
    assert base.launched(w) == ["w1"], (base.launched(w), base.notes(w))


def t10b(tmp, mp, ft2=kw.FT2):   # T10′ 같은 indices 대기/ 선행 = 참조 위치 밖(팀 루트·짝 indices 완성 갈래만) → 고르지 않음
    w = world(tmp, mp, ft2=ft2)
    w.commit("byz", {V65 % "대기": "# 인덱스: w1\n- 선행: r9999\n", "design/teams/v65/indices/대기/r9999.md": "# 안 끝난 선행\n"}, "main")
    w.round()
    assert base.launched(w) == [], base.launched(w)


PLAN, KEEP = {"T1": t1, "T2": t2, "T3": t3, "T4": t4, "T7": t7}, {"T5": t5, "T6": t6, "T8": t8, "T9": t9, "T10": t10, "T10′": t10b}
MUTANTS = {"M1": (LP, 'card = "%s %s:%s" % hit if hit else ', "card = ", "T1"),                       # ② 첫 본문 짝 경로 삭제
           "M2": (LP, "m = WAIT.match(paths[0]) if len(paths) == 1 else None", "m = WAIT.match(paths[0])", "T3"),   # «정확히 1개» 삭제
           "M3": (KN, "if heads3 is not None:", "if False:", "T5"),                                       # ① keeper 후보 더하기 삭제
           "M4": (LP, ' + (["/%s/" % WAIT.match(hit[2]).group(1)] if hit else [])', "", "T7")}            # ③ sparse 더하기 삭제


def run(name, tmp, mp, ft2=kw.FT2):
    tmp.mkdir(parents=True, exist_ok=True)
    return PLAN[name](tmp, ft2) if name in PLAN else KEEP[name](tmp, mp, ft2)


@pytest.mark.parametrize("name", sorted(PLAN) + sorted(KEEP))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", sorted(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
