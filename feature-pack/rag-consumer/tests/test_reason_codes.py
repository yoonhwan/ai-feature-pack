"""R10-m1: the tick reports only reason codes the sources really declare, never environment names or data."""

from __future__ import annotations

import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import _regen_reason_codes as regen  # noqa: E402
from airag_consumer import _result  # noqa: E402
from airag_consumer.reason_codes import REASON_CODES  # noqa: E402

COMMAND = "python tests/_regen_reason_codes.py"


@pytest.fixture(scope="module")
def occurrences():
    return regen.scan(regen.package_sources())


@pytest.fixture(scope="module")
def result(occurrences):
    return regen.classify(occurrences, regen.current_review())


def kinds_of(source: str, value: str) -> list[str]:
    return [o.kind for o in regen.scan({"m.py": source}) if o.value == value]


def test_registry_matches_the_values_the_sources_declare(result):
    assert REASON_CODES == result.registry, f"reason_codes.py is stale; regenerate with: {COMMAND}"


def test_every_literal_occurrence_is_classified_and_review_entries_are_sound(result):
    assert result.unclassified == [], [f"{o.path}:{o.line} {o.value}" for o in result.unclassified]
    assert result.contradictions == []


def test_reference_baseline_does_not_widen_the_registry(occurrences, result):
    kinds = {(o.path, o.value): k for o, k in result.kinds.items()}
    assert kinds[("airag_consumer/bridge.py", "NOT_FOUND")] == "reference"
    assert kinds[("airag_consumer/collector.py", "STALE_COLLECTOR_CURSOR")] == "reference"
    for value in ("KEY_OR_DB_VERIFICATION_FAILED", "UNSUPPORTED_SCHEMA_VERSION", "DATABASE_ALREADY_EXISTS",
                  "VALIDATION_ERROR"):
        assert kinds[("airag/api.py", value)] == "reason"  # {"code": value} dict items are declarations
    without = [o for o in occurrences if o.kind != "compare"]
    review = {k: v for k, v in regen.current_review().items() if v[0] != "reference"}
    assert regen.classify(without, review).registry == result.registry


def test_compare_references_never_create_a_registry_value():
    source = (
        'import os\n'
        'if os.environ.get("K") == "OP_SERVICE_ACCOUNT_TOKEN": pass\n'
        'if err == "XX_CODE": pass\n'
        'raise RuntimeError("XX_CODE")\n'
        'item = {"code": "YY_CODE"}\n'
    )
    done = regen.classify(regen.scan({"m.py": source}), {})
    by_value = {}
    for occurrence, kind in done.kinds.items():
        by_value.setdefault(occurrence.value, []).append(kind)
    assert by_value["OP_SERVICE_ACCOUNT_TOKEN"] == ["data"]
    assert sorted(by_value["XX_CODE"]) == ["reason", "reference"]
    assert by_value["YY_CODE"] == ["reason"]
    assert done.registry == {"XX_CODE", "YY_CODE"}


def test_code_parameters_bind_by_name_not_by_position():
    source = (
        'class TickError(Exception):\n'
        '    def __init__(self, exit_code, code, kind=""): ...\n'
        'def _id(value, code):\n'
        '    raise _error(code)\n'
        '@dataclass\n'
        'class VerificationDecision:\n'
        '    verified: bool\n'
        '    reason_code: str\n'
        'class EventError(Exception): pass\n'
        'TickError(40, "AA_CODE")\n'
        '_id(v, "BB_CODE")\n'
        '_id(v, code="CC_CODE")\n'
        'VerificationDecision(True, reason_code="DD_CODE")\n'
        'VerificationDecision(True, "EE_CODE")\n'
        'EventError("FF_CODE")\n'
        'getattr(x, "GG_CODE")\n'
        'y["HH_CODE"]\n'
        'if z == "II_CODE": pass\n'
        'f(*args, "JJ_CODE")\n'
        'partial(_id, "KK_CODE")\n'
    )
    kinds = {o.value: o.kind for o in regen.scan({"m.py": source})}
    for value in ("AA_CODE", "BB_CODE", "CC_CODE", "DD_CODE", "EE_CODE", "FF_CODE"):
        assert kinds[value] == "declaration", value
    assert kinds["GG_CODE"] == "data" and kinds["HH_CODE"] == "data" and kinds["II_CODE"] == "compare"
    assert kinds["JJ_CODE"] == "structural" and kinds["KK_CODE"] == "structural"  # not bindable: never declared


def test_environment_names_and_data_are_not_reason_codes():
    for name in ("OP_SERVICE_ACCOUNT_TOKEN", "PATH", "HOME", "AIRAG_CONSUMER_KEY_HEX", "BMP"):
        assert name not in REASON_CODES


def test_codes_are_reported_without_reading_any_source(monkeypatch):
    def refuse(*args, **kwargs):
        raise OSError("sources must not be read at runtime")

    monkeypatch.setattr(Path, "read_text", refuse)
    monkeypatch.setattr(Path, "rglob", refuse)
    stream = json.dumps({"ok": False, "error": {"code": "SYMLINK_PATH_REJECTED", "type": "RuntimeError"}})
    assert _result.error_fields(stream) == ("SYMLINK_PATH_REJECTED", "RuntimeError")
    assert _result.error_fields(json.dumps({"error": {"code": "OP_SERVICE_ACCOUNT_TOKEN"}}))[0] == "RUNTIME_FAILED"


# --- R11-m3: callee identity (same-named functions in different modules must not share a binding) -----------

CODE_MODULE = 'def _identifier(value, code):\n    raise RuntimeError(code)\n'
FIELD_MODULE = 'def _identifier(value, field):\n    return value\n_identifier(v, "PATH")\n'


def kind_of_value(sources: dict[str, str], path: str, value: str) -> str:
    return next(o.kind for o in regen.scan(sources) if o.path == path and o.value == value)


def test_a_same_named_function_with_a_field_parameter_does_not_declare_its_literal():
    sources = {"reason.py": CODE_MODULE, "data.py": FIELD_MODULE}
    assert kind_of_value(sources, "data.py", "PATH") != "declaration"
    assert "PATH" not in regen.classify(regen.scan(sources), {}).registry


def test_a_local_definition_wins_for_a_plain_call():
    sources = {"reason.py": CODE_MODULE + '_identifier(v, "XX_CODE")\n', "data.py": FIELD_MODULE}
    assert kind_of_value(sources, "reason.py", "XX_CODE") == "declaration"


def test_an_imported_name_with_conflicting_definitions_is_ambiguous_not_guessed():
    sources = {
        "reason.py": CODE_MODULE, "data.py": FIELD_MODULE,
        "caller.py": 'from reason import _identifier\n_identifier(v, "YY_CODE")\n',
    }
    assert kind_of_value(sources, "caller.py", "YY_CODE") == "structural"  # review decides, never a silent union


def test_a_method_call_on_another_receiver_with_conflicting_definitions_is_ambiguous():
    sources = {
        "a.py": 'class A:\n    def check(self, code):\n        ...\n',
        "b.py": 'class B:\n    def check(self, other):\n        ...\n',
        "c.py": 'obj.check("ZZ_CODE")\n',
    }
    assert kind_of_value(sources, "c.py", "ZZ_CODE") == "structural"


def test_an_unambiguous_name_defined_in_another_module_still_binds():
    sources = {"reason.py": CODE_MODULE, "caller.py": 'from reason import _identifier\n_identifier(v, "WW_CODE")\n'}
    assert kind_of_value(sources, "caller.py", "WW_CODE") == "declaration"
