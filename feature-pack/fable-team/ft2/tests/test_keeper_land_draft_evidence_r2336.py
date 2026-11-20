"""r2336 keeper — «초안·증거 착지» 는 착지 아님: 구현 착지 sha 의 바뀐 경로가 «카드 파일 A + 문서 확장자(.md .txt .json .jsonl .png .tsv)» 뿐이면 keeper_land.landed_in 이 «초안·증거 착지 <sha8>» 로 되돌린다.
공용 lib(ft-land-kind-lib.sh)·card_stage·transition_watch·ft-card-flow 판정 0 · 가짜 git·가짜 lib 호출 주입 · 실 리포·네트워크·sleep 0 · 변이 M1~M6 은 ft2 사본으로(변이마다 원본 같은 사례 1회 더).
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
SHA, TEAM, WORK = "ab" * 20, "harness", "r9336"
CARD = "design/harness/indices/대기/%s.md" % WORK
LAND_PY = "adapters/pi/keeper_land.py"
EVID = "design/teams/cfo/evidence/SCRATCH-expire-20261120/"
LIB = FT2.parent / "legacy" / "1.x" / "harness" / "bin" / "ft-land-kind-lib.sh"


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


def verdict(rows, **kv):
    """landed_in 1회 → (sha, ref, 사유) · 판독 git 호출 기록 같이."""
    k = fake(_land(kv.pop("ft2", None) or FT2), rows, **kv)
    return k, k.landed_in(TEAM, WORK, "/byz", "origin/ops/main-base", SHA)


def draft(k, got):
    assert got == (None, None, "초안·증거 착지 " + SHA[:8]), got
    return k


def landed(got):
    assert got == (SHA, "byz:origin/ops/main-base", ""), got


def c1(ft2=None):   # ① 실사건 cfo 꼴 = 카드 A + evidence .txt 2 → 착지 아님 (기준판 Red)
    k, got = verdict([("A", CARD), ("A", EVID + "scratch_expire.py.txt"), ("A", EVID + "scratch-expire-out.txt")], ft2=ft2)
    assert [a[0] for _, a in draft(k, got).calls] == ["diff-tree"]


def c2(ft2=None):   # ② 카드 A + evidence .md 1 → 착지 아님 (기준판 Red)
    draft(*verdict([("A", CARD), ("A", "design/harness/evidence/r2336/out.md")], ft2=ft2))


def c3(ft2=None):   # ③ 실행 파일 scan.sh 섞임 → 지금처럼 착지
    landed(verdict([("A", CARD), ("A", EVID + "scan.sh")], ft2=ft2)[1])


def c4(ft2=None):   # ④ 실행 파일 check_target.py 섞임 → 지금처럼 착지
    landed(verdict([("A", CARD), ("A", EVID + "check_target.py")], ft2=ft2)[1])


def c5(ft2=None):   # ⑤ 문서 확장자 6종(.md .txt .json .jsonl .png .tsv) 혼합 → 착지 아님
    rows = [("A", CARD)] + [("A", EVID + "e" + ext) for ext in (".md", ".txt", ".json", ".jsonl", ".png", ".tsv")]
    draft(*verdict(rows, ft2=ft2))


def c6(ft2=None):   # ⑥ 카드만 바뀐 착지(r2274 C2) → 사유 그대로 «카드 문서만 착지»(초안 판독 0)
    k, got = verdict([("A", CARD)], kind="카드 문서만", ft2=ft2)
    assert got == (None, None, "카드 문서만 착지 " + SHA[:8]), got
    assert k.calls == [], k.calls


def c7(ft2=None):   # ⑦ 마디 대조 — 사유가 keeper 판정 줄 꼬리에 그대로 붙는다(with_why)
    spec = importlib.util.spec_from_file_location("r2336_settle", str((ft2 or FT2) / "adapters" / "pi" / "keeper_settle.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    why = verdict([("A", CARD), ("A", EVID + "out.txt")], ft2=ft2)[1][2]
    assert why == "초안·증거 착지 " + SHA[:8], why
    seat = mod.Settling.__new__(mod.Settling)
    seat.why = why
    assert seat.with_why("NEXT-SKIP", WORK) == "NEXT-SKIP · " + why


def c8(ft2=None):   # ⑧ keeper 만 — 공용 lib·card_stage·transition_watch 에 초안 낱말 0(판정 그대로)
    for path in (LIB, FT2 / "adapters" / "pi" / "card_stage.py", FT2 / "adapters" / "pi" / "transition_watch.py",
                 FT2.parent / "legacy" / "1.x" / "harness" / "bin" / "ft-card-flow.sh"):
        text = path.read_text(encoding="utf-8")
        assert "초안·증거" not in text and "DOC_EXT" not in text and "draft_land" not in text, path


def c9(ft2=None):   # ⑨ git 실패 = 판정 불가 · 착지 아님(fail-closed)
    got = verdict([("A", CARD), ("A", EVID + "out.txt")], git_rc=128, ft2=ft2)[1]
    assert got == (None, None, "판정 불가 · 초안 판독 git rc 128 " + SHA[:8]), got


def c10(ft2=None):   # ⑩ lib 호출은 ft_land_kind 1회 그대로 · diff-tree 는 keeper 자기 손
    k, got = verdict([("A", CARD), ("A", EVID + "out.txt")], ft2=ft2)
    draft(k, got)
    assert len(k.libs) == 1 and "ft_land_kind" in " ".join(k.libs[0]), k.libs
    assert "diff-tree" not in " ".join(" ".join(x) for x in k.libs)


def c11(ft2=None):   # ⑪ 카드가 그 커밋에서 A 가 아님 → 착지 그대로(r1793 꼴 카드 M · 카드 미포함)
    landed(verdict([("M", CARD), ("A", "design/harness/evidence/r1793/out.md")], ft2=ft2)[1])
    landed(verdict([("A", EVID + "out.md"), ("A", "design/harness/evidence/r1793/note.txt")], ft2=ft2)[1])


CASES = {name: obj for name, obj in sorted(globals().items()) if name.startswith("c") and callable(obj) and name[1:].isdigit()}
MUTANTS = {
    "M1": ([("    return all(os.path.splitext(path)[1].lower() in DOC_EXT for _, path in rows)", "    return False")], c1),
    "M2": ([('    if not card or not any(path == card and status.startswith("A") for status, path in rows):', "    if not card:")], c11),
    "M3": ([('DOC_EXT = (".md", ".txt", ".json", ".jsonl", ".png", ".tsv")', 'DOC_EXT = (".md", ".txt", ".json", ".jsonl", ".png", ".tsv", ".sh")')], c3),
    "M4": ([('return "초안·증거 착지 " + sha[:8] if draft_only', 'return "착지 " + sha[:8] if draft_only')], c7),
    "M5": ([('            return "판정 불가 · 초안 판독 git rc %s %s" % (rc, sha[:8])', '            return ""')], c9),
    "M6": ([('        if kind != "구현":', '        if kind != "구현" and not self.draft_land(team, work, repo, sha):')], c6),
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
