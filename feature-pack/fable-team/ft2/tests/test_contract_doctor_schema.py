"""ft2 doctor 입출력 계약 시험 (r1550).

카드 사례 ⓐ~ⓔ 를 그대로 시험한다 — ⓐ 정본 8필드 그대로 · ⓑ 판정불가 enum 2값+사유 필수 ·
ⓒ ok 3 통과·bad 3 거절 · ⓓ «제품 구현 허가 아님» 원문 · ⓔ 검사기 표준 라이브러리만 ≤120줄.
변이 M1(미해결 owner 필수 빼기)·M2(enum 3번째 값)은 계약 시험이 실제로 잡는지 본다.
"""
import ast
import copy
import json
import sys
import time
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
DOCTOR = FT2 / "contracts" / "doctor"
EXAMPLES = DOCTOR / "examples"
SCHEMA = DOCTOR / "doctor-io.schema.json"
DOC = DOCTOR / "CONTRACT.md"
CHECKER = DOCTOR / "schema_check.py"

# 정본 8 독립 입력 — 더하기·빼기 0
CANON = ("symptom_key", "install_sha", "state_revision", "evidence",
         "observation", "allowed_recovery", "reverified", "unresolved")
CANON_KO = ("증상key", "설치sha", "상태revision", "근거", "관측/판정불가",
            "허용복구", "재검증", "미해결 owner")
PERMIT = ("r1506/r1507 결과와의 대조만 후행한다", "제품 구현을 허가하지 않는다")
STDLIB = {"argparse", "json", "os", "re", "sys"}

sys.path.insert(0, str(DOCTOR))
import schema_check  # noqa: E402  (경로 삽입 뒤에만 import 가능)


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def ok_files():
    return sorted(EXAMPLES.glob("ok-*.json"))


def bad_files():
    return sorted(EXAMPLES.glob("bad-*.json"))


def canon_contract(schema):
    """ⓐ 계약 문면 대조 — 8필드 그대로 · 대응표에 한글 의미가 있다."""
    assert set(schema["required"]) == set(CANON), schema["required"]
    assert set(schema["properties"]) == set(CANON), "필드 더하기·빼기 0"
    verdict = schema["properties"]["observation"]["properties"]["verdict"]["enum"]
    assert verdict == ["observed", "undetermined"], "정본 enum 2값: %s" % verdict
    text = DOC.read_text(encoding="utf-8")
    missing = [k for k in CANON + CANON_KO if k not in text]
    assert not missing, "대응표 누락: %s" % missing


def test_a_canon_eight_fields_exact():
    """ⓐ 필수 필드 = 정본 8개 그대로(더하기·빼기 0) · 한글 대응표 있음."""
    canon_contract(load(SCHEMA))


def test_b_verdict_enum_two_and_reason_required():
    """ⓑ 관측/판정불가 = enum 2값 · 판정불가면 사유 필수 · 미해결이면 owner 필수."""
    props = load(SCHEMA)["properties"]
    obs = props["observation"]
    assert obs["properties"]["verdict"]["enum"] == ["observed", "undetermined"]
    assert obs["then"]["required"] == ["reason"]
    assert props["unresolved"]["then"]["required"] == ["owner"]


def test_c_ok_examples_pass_schema():
    """ⓒ ok 3개(관측·판정불가·복구 뒤 재검증)가 schema 를 통과한다."""
    files = ok_files()
    assert len(files) == 3, [p.name for p in files]
    for path in files:
        assert schema_check.main([str(path)]) == 0, path.name


def test_c_bad_examples_rejected_rc1():
    """ⓒ bad 3개(필드 빠짐·판정불가 사유 없음·미해결 owner 없음)가 거절된다."""
    files = bad_files()
    assert len(files) == 3, [p.name for p in files]
    for path in files:
        assert schema_check.main([str(path)]) == 1, path.name
    schema, errs = load(SCHEMA), {}
    for path in files:
        errs[path.name] = " ".join(schema_check.check(load(path), schema))
    assert "evidence" in errs["bad-01-missing-field.json"]
    assert "reason" in errs["bad-02-undetermined-no-reason.json"]
    assert "owner" in errs["bad-03-unresolved-no-owner.json"]


def test_d_no_implementation_permit_line():
    """ⓓ «대조는 후행 · 제품 구현 허가 아님» 정본 원문이 CONTRACT.md 에 있다."""
    text = DOC.read_text(encoding="utf-8")
    assert all(line in text for line in PERMIT)
    assert "PR④" in text  # 구현은 PR④ 몫이다


def test_e_checker_stdlib_only_and_size():
    """ⓔ 검사기 = 표준 라이브러리만 · 120줄 이하."""
    lines = CHECKER.read_text(encoding="utf-8").splitlines()
    assert len(lines) <= 120, "%d줄" % len(lines)
    names = set()
    for node in ast.walk(ast.parse("\n".join(lines))):
        if isinstance(node, ast.Import):
            names |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom):
            names.add((node.module or "").split(".")[0])
    assert names and names <= STDLIB, sorted(names - STDLIB)


def test_broken_schema_no_silent_fallback(tmp_path):
    """schema 를 못 읽으면 rc3 — 0 으로 조용히 통과하지 않는다."""
    assert schema_check.main(["--schema", str(tmp_path / "없음.json")]) == 3
    assert schema_check.main(["--schema", str(SCHEMA), str(tmp_path)]) == 3


def test_m1_unresolved_owner_required_removed(tmp_path):
    """M1 «미해결 owner» 필수를 빼면 bad-03 이 통과한다 → ⓒ 가 FAIL 한다."""
    schema = copy.deepcopy(load(SCHEMA))
    schema["properties"]["unresolved"].pop("then")
    mutated = tmp_path / "doctor-io.schema.json"
    mutated.write_text(json.dumps(schema, ensure_ascii=False), encoding="utf-8")
    bad03 = str(EXAMPLES / "bad-03-unresolved-no-owner.json")
    assert schema_check.main(["--schema", str(mutated), bad03]) == 0
    assert schema_check.main(["--schema", str(SCHEMA), bad03]) == 1


def test_m2_enum_third_value(tmp_path):
    """M2 enum 에 3번째 값을 넣으면 ⓐ 계약 대조가 FAIL 한다."""
    schema = copy.deepcopy(load(SCHEMA))
    verdict = schema["properties"]["observation"]["properties"]["verdict"]
    verdict["enum"] = verdict["enum"] + ["partial"]
    with pytest.raises(AssertionError):
        canon_contract(schema)
    mutated = tmp_path / "doctor-io.schema.json"
    mutated.write_text(json.dumps(schema, ensure_ascii=False), encoding="utf-8")
    bad02 = str(EXAMPLES / "bad-02-undetermined-no-reason.json")
    assert schema_check.main(["--schema", str(mutated), bad02]) == 1


def test_schema_examples_default_run():
    """기본 실행 = examples/ 전부 · ok 3 통과 + bad 3 거절 → rc1(요약 줄 확인)."""
    started = time.time()
    assert schema_check.main([]) == 1
    assert time.time() - started < 7, "검사기 1회 7초 넘음"
