"""ft2 병렬 배정·실행권 계약 사례표 재생 시험 (r1549).

카드 완료 조건을 그대로 시험한다 — ⓐ 사례 수 8 · ⓑ 의도 변이 1(FAIL) · ⓒ 표↔checker 관측 1:1 ·
ⓔ 미시험 1줄·범위 밖 축 0 · 변이 M1~M3(expect 1개·억제 1→실행 2·사례 1개 삭제)는 rc≠0.
원자료는 BYZ git show 로만 읽는다(실험 코드 실행 0).
"""
import json
import shutil
import sys
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
DISPATCH = FT2 / "contracts" / "dispatch"
CASES = DISPATCH / "cases"
DOC = DISPATCH / "CASES.md"
sys.path.insert(0, str(DISPATCH))
import replay_check  # noqa: E402  (경로 삽입 뒤에만 import 가능)


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def save(path, doc):
    Path(path).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n",
                          encoding="utf-8")


@pytest.fixture()
def table(tmp_path):
    dst = tmp_path / "cases"
    shutil.copytree(CASES, dst)
    return dst


def test_replay_1to1_ok():
    """ⓒ 표가 checker 관측과 1:1 이면 rc0."""
    assert replay_check.main([]) == 0


def test_case_count_variants_and_unexplored():
    """ⓐ 사례 8 · ⓑ 변이 1(의도 FAIL) · ⓔ 미시험 1줄."""
    files = sorted(CASES.glob("*.json"))
    assert len(files) == replay_check.CASE_COUNT == 8
    docs = [load(p) for p in files]
    assert {d["축"] for d in docs} == {"E1", "E2", "E3", "E4"}
    assert len({d["id"] for d in docs}) == 8
    variants = [d for d in docs if d["극성"] == "변이"]
    assert len(variants) == 1 and variants[0]["expect"]["판정"] == "FAIL"
    assert all(d["expect"]["판정"] == "PASS" for d in docs if d["극성"] != "변이")
    assert "미시험" in DOC.read_text(encoding="utf-8")


def test_m1_one_expect_value(table):
    """M1 사례 expect 1개를 바꾸면 rc≠0."""
    path = table / "05-e3n-claim-deliver.json"
    doc = load(path)
    doc["expect"]["관측"][0]["값"]["delivery"] = 2
    save(path, doc)
    assert replay_check.main(["--cases", str(table)]) == 1


def test_m2_suppression_becomes_two_executions(table):
    """M2 같은 attempt 재전달의 «억제 1» 을 «실행 2» 로 바꾸면 rc≠0."""
    path = table / "06-e3v-crash-before-delivery.json"
    doc = load(path)
    primary = doc["expect"]["관측"][0]["값"]
    assert primary["suppressed"] == 1 and primary["run"] == 1
    primary["suppressed"], primary["run"] = 0, 2
    save(path, doc)
    assert replay_check.main(["--cases", str(table)]) == 1


def test_m3_case_deleted(table):
    """M3 사례 1개를 지우면 rc≠0(사례 수·비교 키 소진)."""
    (table / "07-e4n-complete-reassess.json").unlink()
    assert replay_check.main(["--cases", str(table)]) == 1


def test_empty_table_is_broken(tmp_path):
    """빈 표는 rc3 — 0 으로 조용히 통과하지 않는다."""
    assert replay_check.main(["--cases", str(tmp_path)]) == 3


def test_missing_source_no_silent_fallback(tmp_path, monkeypatch):
    """원자료를 못 읽으면 rc3(no silent fallback)."""
    monkeypatch.setenv("FT2_BYZ_REPO", str(tmp_path / "없는리포"))
    monkeypatch.delenv("FT2_BYZ_SHA", raising=False)
    assert replay_check.main([]) == 3
