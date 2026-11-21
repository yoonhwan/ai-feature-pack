"""r2382 — 결과 확정이 «계약 밖 결과 낱말» 로 거절할 때 그 줄에 허용 8낱말과 출처(`ft2/core/record.py` RESULT_WORDS)를 같이 찍는다.

계약 대응표(카드 r2382):

| 계약 | 반례 | 변이 |
|---|---|---|
| K1 거절 줄에 허용 8낱말 | ① · ② | M1 · M2 · M3 |
| K2 출처 = 실제 record.py 경로 1개 | ③ | M4 |
| K3 다른 길 그대로 | ④ · ⑤ | M5 |

① 8낱말이 `RESULT_WORDS` 와 같은 집합·같은 개수로 실린다 · ② 틀린 낱말이 인용돼 1줄에 실린다 ·
③ 출처가 실재하고 그 파일에 8낱말이 있다 · ④ 계약 안 낱말은 그대로 «접수 성공» · ⑤ 거절 갈래 쓰기 0(다른 거절 문구 그대로).
기준판 Red = ① · ③. 변이는 core 사본의 execution.py 글자만 바꿔 «그 반례가 잡는가» 만 본다.
"""
import contextlib
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
TEAM, BAD, GOOD = "harness", "완료", "회수 결과"
OK, REFUSED = "접수 성공", "접수 거부"
CONFIRM_LINE = "낱말·근거 1줄·현역 master 손 중 하나 밖 = 쓰기 0"
LIST, SRC = "허용 8낱말 = ", " · 출처 = "
_LOADS = []


def _load(cdir, name):
    """core 사본에서 그 파일만 읽는다(변이 사본과 기준판이 서로 안 섞이게 별명을 매번 새로 준다)."""
    _LOADS.append(name)
    spec = importlib.util.spec_from_file_location("r2382_%s_%d" % (name, len(_LOADS)), os.path.join(str(cdir), name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _accept(intake, root, work):
    assert intake.Intake(str(root), TEAM).submit("c-" + work, "본문", work).result == OK


def _snap(node):
    """state·journal·bodies 스냅샷 — «쓰기 0» 을 바이트로 대조한다."""
    paths = (node.rs.state_path, node.rs.journal_path)
    return tuple(Path(p).read_bytes() if os.path.exists(p) else b"" for p in paths) \
        + tuple(sorted(os.listdir(node.rs.bodies)))


@contextlib.contextmanager
def _no_seat():
    """좌석 env(FT_SEAT)에 상관없이 confirm() 거절 갈래를 같은 조건으로 본다."""
    old = os.environ.pop("FT_SEAT", None)
    try:
        yield
    finally:
        if old is not None:
            os.environ["FT_SEAT"] = old


def _allowed(line):
    return [w.strip() for w in line.split(LIST, 1)[1].split(SRC, 1)[0].split(",")] if LIST in line else []


def verdict(tmp_path, cdir=None):
    """(① 목록 · ② 낱말 인용 1줄 · ③ 출처 · ④ 정상 길 · ⑤ 거절 갈래 쓰기 0)."""
    cdir = str(cdir or CORE)
    execution, record, intake = _load(cdir, "execution"), _load(cdir, "record"), _load(cdir, "intake")
    root = str(tmp_path / "t")
    _accept(intake, root, "card-a")
    _accept(intake, root, "card-b")
    node = execution.Execution(root, TEAM)
    grant = node.claim("card-a", "h1")
    before = _snap(node)
    refused = node.result("card-a", "h1", grant.gen, word=BAD)
    wrote = _snap(node) != before   # 거절 갈래가 쓴 것인가(ⓔ)
    line = refused.reason or ""
    one = refused.result == REFUSED and sorted(_allowed(line)) == sorted(record.RESULT_WORDS) and len(_allowed(line)) == 8
    two = repr(BAD) in line and "\n" not in line
    source = line.split(SRC, 1)[1].strip() if SRC in line else ""
    three = (os.path.isfile(source) and os.path.realpath(source) == os.path.realpath(os.path.join(cdir, "record.py"))
             and all(word in Path(source).read_text(encoding="utf-8") for word in record.RESULT_WORDS))
    grant_b = node.claim("card-b", "h1")
    good = node.result("card-b", "h1", grant_b.gen, word=GOOD)
    four = (good.result, good.written, "계약 밖" in (good.reason or "")) == (OK, True, False)
    quiet = _snap(node)
    with _no_seat():
        conf = node.confirm("card-a", "h1", grant.gen, BAD, "근거 1줄")
    five = (wrote, _snap(node) == quiet, conf.result, conf.reason) == (False, True, REFUSED, CONFIRM_LINE)
    return one, two, three, four, five


def test_reject_line_lists_allowed_words_and_source(tmp_path):
    assert verdict(tmp_path) == (True, True, True, True, True)


def _copy_core(tmp_path):
    dst = tmp_path / "core"
    shutil.copytree(CORE, dst, ignore=shutil.ignore_patterns("__pycache__"))
    return dst


def _mutant(tmp_path, old, new):
    cdir, path = _copy_core(tmp_path), tmp_path / "core" / "execution.py"
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1, "변이 자리 1곳이어야 한다: %r" % (old,)
    path.write_text(text.replace(old, new), encoding="utf-8")
    return cdir


REASON = 'reason = "계약 밖 결과 낱말: %r · 허용 8낱말 = %s · 출처 = %s" % ('
ARGS = 'word, ", ".join(record.RESULT_WORDS), record.__file__)'
RETURN = "return Grant(REFUSED, work, gen, holder, reason=reason)"
MUTANTS = {   # M1 목록·출처 뺀 원래 문구 · M2 낱말 하나 빠짐 · M3 계약 밖 낱말을 목록에 끼움 · M4 출처를 안 실재하는 경로로 · M5 거절 갈래에서 _step 을 부름(쓰기 생김)
    "M1": ((REASON + "\n                " + ARGS, 'reason = "계약 밖 결과 낱말: %r" % (word,)'), (False, True, False, True, True)),
    "M2": ((ARGS, 'word, ", ".join(record.RESULT_WORDS[:-1]), record.__file__)'), (False, True, True, True, True)),
    "M3": ((ARGS, 'word, ", ".join(record.RESULT_WORDS + ("' + BAD + '",)), record.__file__)'), (False, True, True, True, True)),
    "M4": ((ARGS, 'word, ", ".join(record.RESULT_WORDS), "ft2/core/record.py")'), (True, True, False, True, True)),
    "M5": ((RETURN, 'self._step(work, holder, gen, "result", "", drop=True)\n            ' + RETURN), (True, True, True, True, False)),
}


def test_mutants_break_their_cases(tmp_path):
    for name, (change, want) in MUTANTS.items():
        (tmp_path / name).mkdir()
        assert verdict(tmp_path / name, _mutant(tmp_path / name, *change)) == want, name


if __name__ == "__main__":
    sys.exit(0)
