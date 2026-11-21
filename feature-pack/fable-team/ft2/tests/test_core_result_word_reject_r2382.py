"""r2382 — ft2 result() 거절 문구 = 허용 낱말 + 출처 (동결 반례 ①~⑤ · 변이 M1~M5).

동결 원고 = `design/harness/indices/대기/r2382-ft2-result-word-reject-lists-allowed.md`(ops f7d8b5ebb6 · 사전 DA#52 N1 반영판) §계약·§반례 집합·§변이.

| 계약 | 시험 |
|---|---|
| K1 문구 | ① · ② · M1 · M2 · M3 |
| K2 출처 하나 | ③ · M4 |
| K3 다른 길 그대로 | ④ · ⑤ · M5 |

① claim·start 뒤 result(word="완료") → REFUSED · 8낱말 모두 + 출처(실재 · 그 프로세스가 읽은 record 모듈의 실제 경로) + «RESULT_WORDS» · 줄바꿈 0
② ① 의 reason 이 `계약 밖 결과 낱말: '완료' — ` 로 시작
③ RESULT_WORDS 를 9낱말(끝 «시험 낱말»)로 바꿔 끼움 → 목록 9개 · 마지막 = «시험 낱말» · «허용 8/9낱말» 꼴 0
④ 계약 안 낱말(«접수 성공» · 기본 word) Grant·기록 = «기준판 사본»(reason 한 줄만 되돌린 판)과 바이트 같음
⑤ ①·③ 뒤 journal 줄 수·revision = 앞과 같음(쓰기 0)

변이는 core 사본에서만 돌린다. ④ 의 견줌판은 사본이 아니라 팩 core 에서 만든 «기준판 사본» 이다.
"""
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
TEAM, BAD, NINTH = "harness", "완료", "시험 낱말"
OK, REFUSED = "접수 성공", "접수 거부"
PREFIX = "계약 밖 결과 낱말: '완료' — "
LIST, SRC, SRC_END = "허용 = ", " (출처 ", " RESULT_WORDS)"
_LOADS = []


def _load(cdir, name):
    """core 사본에서 그 파일만 읽는다 — 사본마다 모듈 별명을 새로 줘서 서로 안 섞이게."""
    _LOADS.append(name)
    spec = importlib.util.spec_from_file_location("r2382_%s_%d" % (name, len(_LOADS)), os.path.join(str(cdir), name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _accept(intake, root, work):
    assert intake.Intake(str(root), TEAM).submit("c-" + work, "본문", work).result == OK


def _claim_start(node, work, holder="h1"):
    grant = node.claim(work, holder)
    assert grant.result == OK, grant
    assert node.start(work, holder, grant.gen).result == OK
    return grant


def _journal(node):
    path = node.rs.journal_path
    if not os.path.exists(path):
        return []
    return [json.loads(line) for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]


def _revision(node):
    return json.loads(Path(node.rs.state_path).read_text(encoding="utf-8"))["revision"]


def _allowed(line):
    return [w.strip() for w in line.split(LIST, 1)[1].split(SRC, 1)[0].split(" · ")] if LIST in line else []


def _source(line):
    return line.split(SRC, 1)[1].split(SRC_END, 1)[0].strip() if SRC_END in line else ""


def _normal(root, cdir):
    """④ — 계약 안 낱말 2건(«접수 성공» · 기본 word). Grant 2개와 journal 기록(«at» 뺀 것)을 낸다."""
    execution, intake = _load(cdir, "execution"), _load(cdir, "intake")
    for work in ("card-c", "card-d"):
        _accept(intake, root, work)
    node, grants = execution.Execution(str(root), TEAM), []
    for work, word in (("card-c", OK), ("card-d", "")):
        grant = _claim_start(node, work)
        got = node.result(work, "h1", grant.gen, word) if word else node.result(work, "h1", grant.gen)
        grants.append(tuple(got))
    return grants, [{k: v for k, v in rec.items() if k != "at"} for rec in _journal(node)]


def verdict(tmp_path, cdir=CORE):
    """(① 목록·출처 · ② 앞머리 · ③ 9낱말 · ④ 정상 길 · ⑤ 쓰기 0)."""
    tmp_path = Path(tmp_path)
    execution, intake = _load(cdir, "execution"), _load(cdir, "intake")
    root = str(tmp_path / "t")
    _accept(intake, root, "card-a")
    node, record = execution.Execution(root, TEAM), execution.record
    grant = _claim_start(node, "card-a")
    before = (len(_journal(node)), _revision(node))
    refused = node.result("card-a", "h1", grant.gen, word=BAD)
    line = refused.reason or ""
    one = (refused.result == REFUSED and "\n" not in line and "RESULT_WORDS" in line
           and all(word in _allowed(line) for word in record.RESULT_WORDS)
           and os.path.isfile(_source(line))
           and os.path.realpath(_source(line)) == os.path.realpath(record.__file__))
    two = line.startswith(PREFIX)
    old, record.RESULT_WORDS = record.RESULT_WORDS, tuple(record.RESULT_WORDS) + (NINTH,)
    try:
        nine = node.result("card-a", "h1", grant.gen, word=BAD).reason or ""
    finally:
        record.RESULT_WORDS = old
    three = (_allowed(nine) == list(old) + [NINTH] and "허용 8낱말" not in nine and "허용 9낱말" not in nine)
    five = (len(_journal(node)), _revision(node)) == before
    base = _mutant(tmp_path / "base", REVERT)
    four = _normal(tmp_path / "a", cdir) == _normal(tmp_path / "b", base)
    return one, two, three, four, five


def _copy_core(where):
    where = Path(where)
    where.mkdir(parents=True, exist_ok=True)
    shutil.copytree(CORE, where / "core", ignore=shutil.ignore_patterns("__pycache__"))
    return where / "core"


def _mutant(where, change):
    """core 사본 1개 + execution.py 글자 1곳 교체(`change` = (찾을 글자, 바꿀 글자))."""
    path = _copy_core(where) / "execution.py"
    text = path.read_text(encoding="utf-8")
    assert text.count(change[0]) == 1, "변이 자리 1곳이어야 한다: %r" % (change[0],)
    path.write_text(text.replace(*change), encoding="utf-8")
    return path.parent


REASON = 'reason = "계약 밖 결과 낱말: %r — 허용 = %s (출처 %s RESULT_WORDS)" % ('
ARGS = 'word, " · ".join(record.RESULT_WORDS), os.path.realpath(record.__file__))'
BLOCK = REASON + "\n                " + ARGS + "\n            return Grant(REFUSED, work, gen, holder, reason=reason)"
RETURN = "return Grant(REFUSED, work, gen, holder, reason=reason)"
WORDS8 = " · ".join(("접수 성공", "접수 거부", "복구 필요", "낡은 실행권", "BUSY", "용량 부족", "완료 유보", "회수 결과"))
REVERT = (BLOCK, 'return Grant(REFUSED, work, gen, holder, reason="계약 밖 결과 낱말: %r" % (word,))')
# M1 허용 목록 지움 · M2 앞머리를 다른 글자로 · M3 출처를 팩 경로 글자로 · M4 목록을 8낱말 글자 복사로 · M5 거절 갈래에서 _step 을 부름
MUTANTS = {
    "M1": (('" · ".join(record.RESULT_WORDS)', '""'), (False, True, False, True, True)),
    "M2": (('"계약 밖 결과 낱말: %r — ', '"허용 낱말 아님: %r — '), (True, False, True, True, True)),
    "M3": (('os.path.realpath(record.__file__)', '"ft2/core/record.py"'), (False, True, True, True, True)),
    "M4": (('" · ".join(record.RESULT_WORDS)', '"' + WORDS8 + '"'), (True, True, False, True, True)),
    "M5": ((RETURN, 'self._step(work, holder, gen, "result", "", drop=True)\n            ' + RETURN), (True, True, True, True, False)),
}


def test_frozen_cases_hold(tmp_path):
    assert verdict(tmp_path) == (True, True, True, True, True)


def test_mutants_break_their_cases(tmp_path):
    for name, (change, want) in MUTANTS.items():
        got = verdict(tmp_path / ("t-" + name), _mutant(tmp_path / name, change))
        assert got == want, (name, got)


def test_frozen_reason_line_verbatim(tmp_path):
    """K1 글자 그대로 — 동결 꼴(`— 허용 = a · b (출처 <realpath> RESULT_WORDS)`) 1줄."""
    root = str(tmp_path / "t")
    execution, intake = _load(CORE, "execution"), _load(CORE, "intake")
    _accept(intake, root, "card-v")
    node, record = execution.Execution(root, TEAM), execution.record
    grant = _claim_start(node, "card-v")
    assert node.result("card-v", "h1", grant.gen, word=BAD).reason == \
        "계약 밖 결과 낱말: '완료' — 허용 = %s (출처 %s RESULT_WORDS)" % (
            " · ".join(record.RESULT_WORDS), os.path.realpath(record.__file__))


if __name__ == "__main__":
    sys.exit(0)
