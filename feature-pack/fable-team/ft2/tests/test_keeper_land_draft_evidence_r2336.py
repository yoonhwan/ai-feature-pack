"""r2336 keeper — «초안·증거 착지» 는 착지 아님: 구현 착지 sha 의 바뀐 경로가 «카드 파일 A + design/ 아래 마디 indices / evidence·baselines 문서» 뿐이면 keeper_land.landed_in 이 «초안·증거 착지 <sha8>» 로 되돌린다.
반례 = 카드 ①~⑨ · ⑪(⑩ 은 회귀 시험 5파일 이름 diff 0 = 돌리는 쪽 몫) · 변이 M1~M6 은 ft2 사본으로(변이마다 원본 같은 사례 1회 더).
공용 lib(ft-land-kind-lib.sh)·card_stage·transition_watch·ft-card-flow 판정 0 · 가짜 git·가짜 lib 호출 주입 · 실 리포·네트워크·sleep 0 · 기준판 Red = ① ②.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
SHA, TEAM, WORK = "ab" * 20, "harness", "r9336"
CARD = "design/harness/indices/대기/%s.md" % WORK
LAND_PY = "adapters/pi/keeper_land.py"
LIB = FT2.parent / "legacy" / "1.x" / "harness" / "bin" / "ft-land-kind-lib.sh"
DOC_EXT = (".md", ".txt", ".log", ".json", ".jsonl", ".csv", ".tsv", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".html", ".pdf")


def _land(ft2):
    spec = importlib.util.spec_from_file_location("r2336_land_%d" % id(ft2), str(ft2 / LAND_PY))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fake(land, rows, kind="구현", git_rc=0, card=CARD):
    """가짜 keeper 착지 판독 — 카드 경로 캐시(landing 이 고른 카드) · lib 호출 = kind 1낱말 · diff-tree = rows."""
    class Fake(land.Landing):
        def __init__(s):
            s.root, s.pack, s.stale, s.cache, s.state, s.calls, s.libs = "/byz", "/pack", set(), {}, {}, [], []
            s.env, s.rows, s.kind, s.git_rc = {}, rows, kind, git_rc
            s.cache["@round"] = {("card", TEAM, WORK): ("origin/ops/main-base", card, "# 인덱스\n")}

        def pre_attempt(s, *a, **kv):
            return ""

        def git(s, repo, *a, retry=0, timeout=25):
            s.calls.append((repo, a))
            return s.git_rc, "".join("%s\0%s\0" % row for row in s.rows), ""

        def call(s, argv, timeout=7, retry=0):
            s.libs.append(argv)
            return 0, s.kind, ""

    return Fake()


def verdict(rows, ft2=None, **kv):
    """landed_in 1회 → (가짜 keeper, (sha, ref, 사유))."""
    k = fake(_land(ft2 or FT2), rows, **kv)
    return k, k.landed_in(TEAM, WORK, "/byz", "origin/ops/main-base", SHA)


def draft(got):
    assert got == (None, None, "초안·증거 착지 " + SHA[:8]), got


def landed(got):
    assert got == (SHA, "byz:origin/ops/main-base", ""), got


def c1(ft2=None):   # ① 카드 A + design/teams/cfo/evidence/a/*.txt 2 → 초안·증거 착지(기준판 Red)
    k, got = verdict([("A", CARD), ("A", "design/teams/cfo/evidence/a/x.py.txt"), ("A", "design/teams/cfo/evidence/a/out.txt")], ft2=ft2)
    draft(got)
    assert [a[0] for _, a in k.calls] == ["diff-tree"]


def c2(ft2=None):   # ② 카드 A + design/teams/v65/baselines/B.md → 초안·증거 착지(기준판 Red)
    land = _land(ft2 or FT2)
    assert tuple(land.DOC_EXT) == DOC_EXT, land.DOC_EXT   # 문서 목록 = 카드 동결(K1)
    draft(verdict([("A", CARD), ("A", "design/teams/v65/baselines/B.md")], ft2=ft2)[1])


def c3(ft2=None):   # ③ 카드 A + design/harness/evidence/r1689/scan.sh → 착지(실행 파일)
    landed(verdict([("A", CARD), ("A", "design/harness/evidence/r1689/scan.sh")], ft2=ft2)[1])


def c4(ft2=None):   # ④ 카드 A + design/evidence/x/check_target.py → 착지
    landed(verdict([("A", CARD), ("A", "design/evidence/x/check_target.py")], ft2=ft2)[1])


def c5(ft2=None):   # ⑤ 카드 A + clients/web/src/a.ts → 착지(design/ 밖)
    landed(verdict([("A", CARD), ("A", "clients/web/src/a.ts")], ft2=ft2)[1])


def c6(ft2=None):   # ⑥ 카드 A + design/rag/sql/94-x.sql → 착지(마디 아님 · .sql 목록 밖)
    landed(verdict([("A", CARD), ("A", "design/rag/sql/94-x.sql")], ft2=ft2)[1])


def c7(ft2=None):   # ⑦ ⑭ 마디 whole — evidence-x/ · myevidence/ · clients 아래 .json·.md → 착지(K4)
    landed(verdict([("A", CARD), ("A", "design/teams/cfo/evidence-x/a.md"),
                    ("A", "design/teams/cfo/myevidence/a.md")], ft2=ft2)[1])
    landed(verdict([("A", CARD), ("A", "clients/web/src/i18n/ko.json"), ("A", "clients/web/README.md")], ft2=ft2)[1])


def c8(ft2=None):   # ⑧ keeper 만 — 같은 sha 의 land_kind 낱말(구현·카드 문서만·판정 불가) 기준판 그대로 · 다른 3곳에 초안 글자 0
    land = _land(ft2 or FT2)
    for word in ("구현", "카드 문서만", "판정 불가 git diff-tree rc 128 ab"):
        assert land.land_kind("/byz", "/byz", SHA, lambda argv, cap: (0, word, "")) == word, word
    for path in (LIB, FT2 / "adapters" / "pi" / "card_stage.py", FT2 / "adapters" / "pi" / "transition_watch.py",
                 FT2.parent / "legacy" / "1.x" / "harness" / "bin" / "ft-card-flow.sh"):
        text = path.read_text(encoding="utf-8")
        assert "초안·증거" not in text and "draft_doc" not in text, path


def c9(ft2=None):   # ⑨ 판독 git rc≠0 → 판정 불가 · 이 바퀴 보류(착지 아님)
    got = verdict([("A", CARD), ("A", "design/harness/evidence/r1689/out.md")], git_rc=128, ft2=ft2)[1]
    assert got == (None, None, "판정 불가 · 초안 판독 git rc 128 " + SHA[:8]), got


def c11(ft2=None):   # ⑪ 카드 M + design/…/evidence/M1.md 만 → 착지 그대로(r1793 꼴 · A 조건)
    landed(verdict([("M", CARD), ("A", "design/harness/evidence/M1.md")], ft2=ft2)[1])


CASES = {name: obj for name, obj in sorted(globals().items()) if name.startswith("c") and name[1:].isdigit()}
MUTANTS = {
    "M1": ([('    return any(seg in DOC_MID for seg in mid) and os.path.splitext',
            '    return any(seg in ("baselines",) for seg in mid) and os.path.splitext')], c1),
    "M2": ([('    return any(seg in DOC_MID for seg in mid) and os.path.splitext(segs[-1])[1].lower() in DOC_EXT',
            '    return any(seg in DOC_MID for seg in mid)')], c3),
    "M3": ([('    return any(seg in DOC_MID for seg in mid) and os.path.splitext(segs[-1])[1].lower() in DOC_EXT',
            '    return any(seg in path for seg in DOC_MID) and os.path.splitext(segs[-1])[1].lower() in DOC_EXT')], c7),
    "M4": ([('    if word in ("구현", "카드 문서만") or word.startswith("판정 불가 "):\n        return word',
            '    if word == "구현":\n        return "초안·증거 착지"\n    if word in ("구현", "카드 문서만") or word.startswith("판정 불가 "):\n        return word')], c8),
    "M5": ([('            return "판정 불가 · 초안 판독 git rc %s %s" % (rc, sha[:8])', '            return "초안·증거 착지 " + sha[:8]')], c9),
    "M6": ([('    if not card or not any(path == card and status.startswith("A") for status, path in rows):', "    if not card:")], c11),
}


def mutant(tmp, pairs, case):
    """변이 1개 — ft2 사본(tmp/ft2)에 글자 바꿈 → 그 사례 FAIL 이어야 · 원본으로 같은 사례 1회 더 PASS."""
    copy = tmp / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy / LAND_PY
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(copy)
    case(FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    pairs, case = MUTANTS[name]
    mutant(tmp_path, pairs, case)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name):
    CASES[name](FT2)
