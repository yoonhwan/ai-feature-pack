"""ft2 doctor 입출력 계약 schema 검사기 (r1550).

표준 라이브러리만 쓴다. 손검사는 3종뿐이다 — 필수(required)·enum·조건(if/then).
rc 0 전부 통과 · 1 위반 있음 · 3 schema/예시를 못 읽음(no silent fallback).
"""
import argparse
import json
import os
import re
import sys

TYPES = {"object": dict, "array": list, "string": str, "boolean": bool,
         "null": type(None)}


class Broken(Exception):
    """schema·예시를 읽을 수 없다 — rc3."""


def read(path):
    try:
        with open(path, "rb") as fh:
            return json.loads(fh.read().decode("utf-8"))
    except (OSError, ValueError) as exc:
        raise Broken("못 읽음: %s (%s)" % (path, exc))


def type_ok(value, want):
    if want in ("integer", "number"):
        num = isinstance(value, int) or want == "number" and isinstance(value, float)
        return num and not isinstance(value, bool)
    return isinstance(value, TYPES[want])


def check(value, spec, path="$"):
    want = spec.get("type")
    if want and not type_ok(value, want):
        return ["%s: type %s 아님" % (path, want)]
    bad = []
    if "enum" in spec and value not in spec["enum"]:
        bad.append("%s: enum 밖 %r" % (path, value))
    if "pattern" in spec and isinstance(value, str):
        if not re.search(spec["pattern"], value):
            bad.append("%s: pattern 불일치 %r" % (path, value))
    if "minimum" in spec and type_ok(value, "integer"):
        if value < spec["minimum"]:
            bad.append("%s: minimum %r 미만" % (path, spec["minimum"]))
    if isinstance(value, list):
        if len(value) < spec.get("minItems", 0):
            bad.append("%s: minItems %d 미만" % (path, spec["minItems"]))
        if "items" in spec:
            for idx, one in enumerate(value):
                bad += check(one, spec["items"], "%s[%d]" % (path, idx))
    if isinstance(value, dict):
        for key in spec.get("required") or ():
            if key not in value:
                bad.append("%s: 필수 %s 없음" % (path, key))
        for key, sub in (spec.get("properties") or {}).items():
            if key in value:
                bad += check(value[key], sub, "%s.%s" % (path, key))
    if "if" in spec and not check(value, spec["if"], path):
        bad += check(value, spec.get("then") or {}, path)
    return bad


def _targets(args, here):
    if args.examples:
        return args.examples
    folder = os.path.join(here, "examples")
    if not os.path.isdir(folder):
        raise Broken("예시 폴더 없음: %s" % folder)
    return [os.path.join(folder, n) for n in sorted(os.listdir(folder))
            if n.endswith(".json")]


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="ft2 doctor 입출력 계약 schema 검사")
    ap.add_argument("--schema", default=os.path.join(here, "doctor-io.schema.json"))
    ap.add_argument("examples", nargs="*", default=None)
    args = ap.parse_args(argv)
    try:
        schema = read(args.schema)
        docs = [(os.path.basename(n), read(n)) for n in _targets(args, here)]
    except Broken as exc:
        print("SCHEMA-BROKEN: %s" % exc)
        return 3
    if not docs:
        print("SCHEMA-BROKEN: 검사할 예시 0")
        return 3
    bad = 0
    for name, doc in docs:
        errs = check(doc, schema)
        bad += 1 if errs else 0
        print("%s %s%s" % ("PASS" if not errs else "FAIL", name,
                           "" if not errs else " — " + "; ".join(errs[:3])))
    print("SCHEMA %s — 통과 %d/%d" % ("OK" if not bad else "FAIL",
                                     len(docs) - bad, len(docs)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
