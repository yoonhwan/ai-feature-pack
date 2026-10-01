"""Derive the reason-code registry from source: ``python tests/_regen_reason_codes.py`` rewrites it.

A reason code is a ``[A-Z][A-Z0-9_]{1,100}`` string literal that the sources *declare* as a code:
bound by a call to a parameter named ``code``/``reason_code`` (by position or keyword), the message of an
exception (the CLI reports ``str(exc)`` as the code), or the value of a ``"code"``/``"reason_code"`` dict
key. Every other literal occurrence is a *reference* (compared against a declared value), *data*, or a
structural context a person classified once in ``reason_code_review.py``. Classification is per occurrence;
a value may play several roles. Pure functions here take ``{relative path: source text}`` so the rules
can be tested on synthetic snippets.
"""

from __future__ import annotations

import ast
import builtins
from dataclasses import dataclass
from pathlib import Path
import re
import sys

CODE = re.compile(r"[A-Z][A-Z0-9_]{1,100}")
PARAMS = ("code", "reason_code")
# Calls whose literal arguments are plain data (names, keys, SQL, formats), never reported reason codes.
DATA_CALLS = frozenset({
    "getattr", "setattr", "hasattr", "get", "pop", "setdefault", "startswith", "endswith", "execute",
    "executemany", "executescript", "convert", "normalize", "new", "format", "join", "replace", "split",
    "encode", "decode", "register_converter", "register_adapter", "fullmatch", "match", "search", "compile",
    "add", "remove", "discard", "index", "count", "find", "write", "print", "append", "extend", "update",
    "isinstance", "issubclass", "fromhex", "environ", "getenv", "strip", "lstrip", "rstrip", "lower", "upper",
    "pragma", "attach", "frozenset", "set", "tuple", "list", "sorted", "dict", "deepcopy", "field",
})
REVIEW_FILE = Path(__file__).with_name("reason_code_review.py")
CONSUMER_ROOT = Path(__file__).resolve().parents[1] / "src" / "airag_consumer"
OUTPUT = CONSUMER_ROOT / "reason_codes.py"


@dataclass(frozen=True)
class Occurrence:
    path: str
    line: int
    value: str
    kind: str  # declaration | compare | data | structural


@dataclass(frozen=True)
class Binding:
    positional: frozenset[int]
    keywords: frozenset[str]


_NONE = Binding(frozenset(), frozenset())


def _name(node: ast.expr) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return ""


def _params(args: ast.arguments, *, method: bool) -> list[tuple[str, int | None]]:
    """(name, positional index or None for keyword-only) with self/cls dropped for methods."""
    names = [a.arg for a in [*args.posonlyargs, *args.args]]
    if method and names and names[0] in ("self", "cls"):
        names = names[1:]
    result: list[tuple[str, int | None]] = [(n, i) for i, n in enumerate(names)]
    result += [(a.arg, None) for a in args.kwonlyargs]
    return result


def _binding(params: list[tuple[str, int | None]]) -> Binding:
    hits = [(n, i) for n, i in params if n in PARAMS]
    return Binding(frozenset(i for _, i in hits if i is not None), frozenset(n for n, _ in hits))


def _is_dataclass(node: ast.ClassDef) -> bool:
    return any(_name(d.func if isinstance(d, ast.Call) else d) == "dataclass" for d in node.decorator_list)


def build_bindings(trees: dict[str, ast.Module]) -> tuple[dict[str, Binding], set[str]]:
    """Code-parameter bindings by callee name (functions, methods, constructors) + exception class names."""
    functions: dict[str, Binding] = {}
    classes: dict[str, ast.ClassDef] = {}
    for tree in trees.values():
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef):
                classes[node.name] = node
    for tree in trees.values():
        methods = {id(f) for c in ast.walk(tree) if isinstance(c, ast.ClassDef)
                   for f in c.body if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef))}
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name != "__init__":
                b = _binding(_params(node.args, method=id(node) in methods))
                old = functions.get(node.name, _NONE)
                functions[node.name] = Binding(old.positional | b.positional, old.keywords | b.keywords)

    exceptions: set[str] = set()

    def is_exception(name: str, seen: frozenset[str] = frozenset()) -> bool:
        if name in seen:
            return False
        if name in classes:
            return any(is_exception(_name(b), seen | {name}) for b in classes[name].bases)
        return isinstance(getattr(builtins, name, None), type) and issubclass(getattr(builtins, name), BaseException)

    def class_binding(name: str, seen: frozenset[str] = frozenset()) -> Binding | None:
        node = classes.get(name)
        if node is None or name in seen:
            return None
        for item in node.body:
            if isinstance(item, ast.FunctionDef) and item.name == "__init__":
                return _binding(_params(item.args, method=True))
        if _is_dataclass(node):
            fields = [t.target.id for t in node.body if isinstance(t, ast.AnnAssign) and isinstance(t.target, ast.Name)
                      and "ClassVar" not in ast.dump(t.annotation)]
            return _binding([(f, i) for i, f in enumerate(fields)])
        for base in node.bases:
            inherited = class_binding(_name(base), seen | {name})
            if inherited is not None:
                return inherited
        return None

    constructors: dict[str, Binding] = {}
    for name in classes:
        if is_exception(name):
            exceptions.add(name)
        found = class_binding(name)
        if found is not None and (found.positional or found.keywords):
            constructors[name] = found
        elif name in exceptions:
            constructors[name] = Binding(frozenset({0}), frozenset())  # the message is the reported code
        else:
            constructors.setdefault(name, _NONE)
    for name in dir(builtins):
        if is_exception(name):
            exceptions.add(name)
            constructors.setdefault(name, Binding(frozenset({0}), frozenset()))
    merged = dict(functions)
    for name, binding in constructors.items():
        old = merged.get(name, _NONE)
        merged[name] = Binding(old.positional | binding.positional, old.keywords | binding.keywords)
    return merged, exceptions


def _parents(tree: ast.AST) -> dict[ast.AST, ast.AST]:
    return {child: parent for parent in ast.walk(tree) for child in ast.iter_child_nodes(parent)}


def _kind(node: ast.Constant, parents: dict[ast.AST, ast.AST], bindings: dict[str, Binding]) -> str:
    parent = parents.get(node)
    if isinstance(parent, (ast.Tuple, ast.List, ast.Set)) and isinstance(parents.get(parent), ast.Compare):
        return "compare"
    if isinstance(parent, ast.Call):
        if node not in parent.args:
            return "structural"
        callee = _name(parent.func)
        if any(isinstance(a, ast.Starred) for a in parent.args[:parent.args.index(node)]):
            return "structural"
        if parent.args.index(node) in bindings.get(callee, _NONE).positional:
            return "declaration"
        return "data" if callee in DATA_CALLS else "structural"
    if isinstance(parent, ast.keyword):
        call = parents.get(parent)
        if parent.arg in PARAMS:
            if isinstance(call, ast.Call) and parent.arg in bindings.get(_name(call.func), _NONE).keywords:
                return "declaration"
            return "structural"
        return "data"
    if isinstance(parent, ast.Dict):
        if node in parent.values:
            key = parent.keys[parent.values.index(node)]
            if isinstance(key, ast.Constant) and key.value in PARAMS:
                return "declaration"
        return "data"
    if isinstance(parent, ast.Subscript):
        return "data"
    if isinstance(parent, ast.Compare):
        return "compare"
    return "structural"


def scan(sources: dict[str, str]) -> list[Occurrence]:
    trees = {path: ast.parse(text, filename=path) for path, text in sources.items()}
    bindings, _ = build_bindings(trees)
    found: list[Occurrence] = []
    for path, tree in trees.items():
        parents = _parents(tree)
        for node in ast.walk(tree):
            if isinstance(node, ast.Constant) and isinstance(node.value, str) and CODE.fullmatch(node.value):
                found.append(Occurrence(path, node.lineno, node.value, _kind(node, parents, bindings)))
    return sorted(found, key=lambda o: (o.path, o.line, o.value))


@dataclass(frozen=True)
class Result:
    registry: frozenset[str]
    declared: frozenset[str]
    kinds: dict[Occurrence, str]  # final classification: reason | reference | data
    unclassified: list[Occurrence]
    contradictions: list[str]


def classify(occurrences: list[Occurrence], review: dict[tuple[str, int, str], tuple[str, str]]) -> Result:
    declared = {o.value for o in occurrences if o.kind == "declaration"}
    problems: list[str] = []
    manual_reasons = {value for (path, line, value), (kind, _) in review.items() if kind == "reason"}
    declared_or_reason = declared | manual_reasons
    kinds: dict[Occurrence, str] = {}
    unclassified: list[Occurrence] = []
    by_key = {(o.path, o.line, o.value): o for o in occurrences}
    for key, (kind, why) in review.items():
        occurrence = by_key.get(key)
        if kind not in ("reason", "reference", "data") or not why.strip():
            problems.append(f"{key}: invalid review entry")
        elif occurrence is None:
            problems.append(f"{key}: no such literal occurrence (stale entry)")
        elif occurrence.kind != "structural":
            problems.append(f"{key}: the rules already classify it as {occurrence.kind}; review applies to structural only")
        elif kind == "reference" and key[2] not in declared_or_reason:
            problems.append(f"{key}: reference to a value that is never declared")
    for occurrence in occurrences:
        key = (occurrence.path, occurrence.line, occurrence.value)
        if occurrence.kind == "declaration":
            kinds[occurrence] = "reason"
        elif occurrence.kind == "compare":
            kinds[occurrence] = "reference" if occurrence.value in declared_or_reason else "data"
        elif occurrence.kind == "data":
            kinds[occurrence] = "data"
        elif key in review:
            kinds[occurrence] = review[key][0]
        else:
            unclassified.append(occurrence)
    registry = frozenset(declared | manual_reasons)
    return Result(registry, frozenset(declared), kinds, unclassified, problems)


def package_sources() -> dict[str, str]:
    """Consumer and core package sources by package-relative path; the registry file itself is excluded."""
    import airag

    sources: dict[str, str] = {}
    for root in (CONSUMER_ROOT, Path(airag.__file__).resolve().parent):
        for path in sorted(root.rglob("*.py")):
            if path.name == "reason_codes.py" and root == CONSUMER_ROOT:
                continue
            sources[f"{root.name}/{path.relative_to(root).as_posix()}"] = path.read_text(encoding="utf-8")
    return sources


def current_review() -> dict[tuple[str, int, str], tuple[str, str]]:
    sys.path.insert(0, str(REVIEW_FILE.parent))
    try:
        from reason_code_review import REVIEW

        return dict(REVIEW)
    finally:
        sys.path.pop(0)


def current() -> Result:
    return classify(scan(package_sources()), current_review())


def render(registry: frozenset[str]) -> str:
    body = "".join(f'    "{value}",\n' for value in sorted(registry))
    return (
        '"""Reason codes this software reports (frozen data, generated by tests/_regen_reason_codes.py).\n\n'
        "A code is a literal the consumer or core sources declare as one (a ``code``/``reason_code`` argument,\n"
        'an exception message, a ``"code"`` dict value) or that was reviewed by hand. Regenerate, never edit.\n'
        'No imports: this module is pure data."""\n\n'
        f"REASON_CODES: frozenset[str] = frozenset({{\n{body}}})\n"
    )


if __name__ == "__main__":
    result = current()
    if result.unclassified or result.contradictions:
        for o in result.unclassified:
            print(f"UNCLASSIFIED {o.path}:{o.line} {o.value}", file=sys.stderr)
        for message in result.contradictions:
            print(f"PROBLEM {message}", file=sys.stderr)
        raise SystemExit(1)
    OUTPUT.write_text(render(result.registry), encoding="utf-8")
    print(f"wrote {len(result.registry)} codes to {OUTPUT}")
