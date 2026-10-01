"""Shared strict JSON parsing (p02-cli-review.txt item 3; reused by the
P-03 conversation normalization adapter per
.fable-team/airag/p03-normalize-review.txt item 3 — one JSON-input contract,
not a second one). Kept dependency-free of `store`/`normalize` so either
module can import it without a circular import."""

from __future__ import annotations

import json
import math


def _reject_nonfinite_constant(value: object) -> None:
    raise ValueError(f"non-finite JSON constant not allowed: {value}")


def _strict_parse_float(s: str) -> float:
    # A syntactically valid JSON number can still overflow to +-inf on
    # conversion (e.g. 1e400) without ever containing the NaN/Infinity
    # *token* that parse_constant intercepts — that pathway needs its own
    # finiteness check (p02-cli-review.txt item 3).
    value = float(s)
    if not math.isfinite(value):
        raise ValueError(f"non-finite JSON number not allowed: {s}")
    return value


def strict_json_loads(data: bytes | str) -> object:
    """The one JSON parser used anywhere in this package that must reject
    non-finite values: NaN/Infinity/-Infinity tokens AND numeric literals
    that merely overflow to +-inf (e.g. 1e400) are both refused, not
    silently accepted the way plain json.loads would."""
    return json.loads(data, parse_constant=_reject_nonfinite_constant, parse_float=_strict_parse_float)
