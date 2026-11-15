"""r2022 keeper — 착지 조상 확인(git merge-base --is-ancestor) 1회 = 7초 · rc 0 = 조상 · 1 = 조상 아님 · 그 밖 = 그 칸 «판정 불가»(미도달·[크리티컬] 0).
rc 128 = 그 repo 에 객체 없음(다른 repo 착지 · cat-file -e rc1) 이면 지금처럼 다음 ref · 객체 있음·cat-file 실패 = 판정 불가(r1910 꼴).
가짜 git 실행기 주입 · 실 리포·실 keeper·sleep 0 · 변이 M1(갈래 삭제)·M2(timeout 되돌림)는 ft2 사본으로.
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
SHA, WORK, TEAM = "ab" * 20, "r9220", "harness"
LAND_PY = "adapters/pi/keeper_land.py"


def _land(ft2):
    spec = importlib.util.spec_from_file_location("r2022_land_%d" % id(ft2), str(ft2 / LAND_PY))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fake(land, script, root="/byz"):
    class Fake(land.Landing):
        def __init__(s):
            s.root, s.pack, s.stale, s.cache, s.script, s.calls, s.sent = root, "/pack", set(), {}, list(script), [], []

        def resolve_card(s, team, work):
            return [("origin/ops/main-base", "design/harness/indices/진행/%s.md" % work)], None

        def git(s, repo, *a, retry=0, timeout=25):
            s.calls.append((repo, a, timeout))
            if a[0] == "show":
                return 0, "# 인덱스\n- 착지: %s\n" % SHA, ""
            if a[0] in ("merge-base", "cat-file"):
                return s.script.pop(0) if s.script else (1, "", "")   # 대본 끝 = 조상 아님
            raise AssertionError(a)

        def pre_attempt(s, *a, **kv):
            return ""

        def notify(s, *a):
            s.sent.append(a)

    return Fake()


def anc(k):
    return [t for _, a, t in k.calls if a[:2] == ("merge-base", "--is-ancestor")]


def t1(land, tmp):   # T1 timeout(rc None) → 판정 불가 · 미도달 0 · [크리티컬] 0 · timeout = 7
    k = fake(land, [(None, "", "timeout")])
    out = k.landing(TEAM, WORK)
    assert out == (None, None, "판정 불가 · 착지 조상 git rc None"), out
    assert k.complete(TEAM, WORK, "a1", out) is None and k.sent == [], k.sent
    assert anc(k) == [7], k.calls


def t2(land, tmp):   # T2 git rc 128 · 객체 있음(cat-file rc0) → 판정 불가
    k = fake(land, [(128, "", "fatal"), (0, "", "")])
    assert k.landing(TEAM, WORK) == (None, None, "판정 불가 · 착지 조상 git rc 128")


def t2b(land, tmp):  # T2b rc 128 · 그 repo 에 객체 없음(cat-file rc1) → 다음 ref(다른 repo 착지 = 지금 그대로)
    k = fake(land, [(128, "", "fatal"), (1, "", ""), (0, "", "")])
    assert k.landing(TEAM, WORK) == (SHA, "byz:origin/ops/main-base", "")


def t3(land, tmp):   # T3 첫 ref rc0 → 지금 그대로
    k = fake(land, [(0, "", "")])
    assert k.landing(TEAM, WORK) == (SHA, "pack:origin/main", "") and anc(k) == [7]


def t4(land, tmp):   # T4 세 ref 모두 rc1 → 지금 그대로 미도달
    k = fake(land, [(1, "", "")] * 3)
    assert k.landing(TEAM, WORK) == (SHA, None, "미도달") and anc(k) == [7, 7, 7]


def t5(land, tmp):   # T5 PR 착지 조상 rc None → 판정 불가 · rc 1 → 지금 그대로 «착지 줄 없음»
    e = land.endings
    e.latest = lambda k, team: {WORK: ("a1", "h")}
    e.intent = lambda k, team, work, attempt, holder: {"worktree": str(tmp)}
    e._prs = lambda k, repo, branch: [{"number": 7, "mergeCommit": {"oid": SHA}, "baseRefName": "main"}]
    for rc, want in ((None, (None, None, "판정 불가 · PR 착지 조상 git rc None")), (1, (None, None, "착지 줄 없음"))):
        k = fake(land, [(rc, "", "")])
        k.git = (lambda real: lambda repo, *a, **kv: (0, "nano/" + WORK, "") if a[:1] == ("rev-parse",) else
                 (0, "https://github.com/o/r.git", "") if a[:1] == ("config",) else real(repo, *a, **kv))(k.git)
        assert e.pr_landed(k, TEAM, WORK) == want
        assert anc(k) == [7], k.calls


def t6(land, tmp):   # T6 pre_attempt 조상 대조도 7초(③ · 갈래는 지금 그대로)
    (tmp / ".fable-team" / "teams" / TEAM / "runtime").mkdir(parents=True)   # 빈 journal
    k = fake(land, [(0, "", ""), (1, "", "")], root=str(tmp))
    assert land.Landing.pre_attempt(k, TEAM, WORK, "/pack", SHA, {"base_sha": "cd" * 20}) == ""
    assert anc(k) == [7], k.calls


CASES = {"T1": t1, "T2": t2, "T2b": t2b, "T3": t3, "T4": t4, "T5": t5, "T6": t6}
BRANCH = '            if rc != 1 and (rc != 128 or self.git(repo, "cat-file", "-e", sha, timeout=endings.ANC_S)[0] != 1):\n'
MUTANTS = {"M1": (BRANCH + '                return None, None, "판정 불가 · 착지 조상 git rc %s" % rc\n', "", (t1, t2)),
           "M2": ('sha, ref, timeout=endings.ANC_S)[0]', 'sha, ref)[0]', (t1,))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](_land(FT2), tmp_path)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    old, new, cases = MUTANTS[name]
    shutil.copytree(FT2, copy := tmp_path / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (copy / LAND_PY).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (copy / LAND_PY).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        with pytest.raises(AssertionError):
            case(_land(copy), tmp_path)
