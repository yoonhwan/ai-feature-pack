#!/usr/bin/env python3
"""ft 2.0 패키지 manifest — build <루트> 로 소스 지문을 만들고 verify <manifest> <폴더> 로 대조한다.

제외 규칙은 EXCLUDE 한 곳(skip_entry 도 파생) · 경로는 루트 기준 상대·정렬 · 같은 입력 두 번 = 같은 출력.
`git` 호출 0 — HEAD·loose ref·packed-refs 를 파일로 읽는다(없으면 null) · manifest 항목(path·kind·bytes·sha256)이 틀리면 rc2 «판정 불가».
종료 코드: 0 = 만들어짐/같음 · 1 = 다름 · 2 = 판정 불가(못 읽음·권한 없음·손상) — traceback 0.
"""
import fnmatch
import hashlib
import json
import os
import sys

SCHEMA = 1
EXCLUDE = ("__pycache__/", "*.pyc", "*.pyo", ".*")
KINDS = ("code", "contract", "test", "doc")
HEX = frozenset("0123456789abcdef")


def skip_entry(rel):
    name = rel.rsplit("/", 1)[-1]
    return any(fnmatch.fnmatchcase(name, rule.rstrip("/")) for rule in EXCLUDE)


def kind_of(rel):
    parts, suffix = rel.split("/"), os.path.splitext(rel)[1]
    if parts[0] == "tests" or parts[-1].startswith("test_"):
        return "test"
    if parts[0] == "contracts" or suffix in (".tsv", ".json", ".yaml", ".yml"):
        return "contract"
    return "doc" if suffix in (".md", ".txt") else "code"


def walk_files(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        prefix = "" if dirpath == root else os.path.relpath(dirpath, root).replace(os.sep, "/") + "/"
        dirnames[:] = [name for name in dirnames if not skip_entry(prefix + name)]
        found += [prefix + name for name in filenames if not skip_entry(prefix + name)]
    return sorted(found)


def read_text(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None


def head_of(gitdir):
    head = (read_text(os.path.join(gitdir, "HEAD")) or "").strip()
    if not head.startswith("ref: "):
        return head or None
    ref = head[5:].strip()
    common = (read_text(os.path.join(gitdir, "commondir")) or "").strip()
    bases = [gitdir] + ([os.path.join(gitdir, common)] if common else [])
    for base in bases:
        sha = read_text(os.path.join(*[base] + ref.split("/")))
        if sha:
            return sha.strip()
        for line in (read_text(os.path.join(base, "packed-refs")) or "").splitlines():
            if line.split()[1:] == [ref]:
                return line.split()[0]
    return None


def git_sha(root):
    cur = os.path.abspath(root)
    while True:
        dot = os.path.join(cur, ".git")
        if os.path.isdir(dot):
            return head_of(dot)
        text = read_text(dot) or ""
        if text.startswith("gitdir:"):
            target = text.split(":", 1)[1].strip()
            return head_of(target if os.path.isabs(target) else os.path.join(cur, target))
        cur, parent = os.path.dirname(cur), cur
        if cur == parent:
            return None


def entry(root, rel):
    data = open(os.path.join(root, *rel.split("/")), "rb").read()
    return {"path": rel, "kind": kind_of(rel), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def build(root):
    if not os.path.isdir(root):
        raise OSError(0, "폴더가 아니다", root)
    files = [entry(root, rel) for rel in walk_files(root)]
    return {"schema": SCHEMA, "tool": "tools/manifest.py", "exclude": list(EXCLUDE),
            "source": {"sha": git_sha(root)}, "count": len(files), "files": files}


def bad_item(item):
    if not isinstance(item, dict):
        return True
    sha, size = item.get("sha256"), item.get("bytes")
    return not (isinstance(item.get("path"), str) and item.get("kind") in KINDS and type(size) is int
                and isinstance(sha, str) and len(sha) == 64 and set(sha) <= HEX)


def load_manifest(path):
    try:
        doc = json.loads(read_text(path) or "")
    except ValueError:
        return None
    files = doc.get("files") if isinstance(doc, dict) and doc.get("schema") == SCHEMA else None
    wrong = not isinstance(files, list) or any(bad_item(item) for item in files)
    return None if wrong else {item["path"]: item for item in files}


def verify(manifest_path, folder):
    want = load_manifest(manifest_path)
    if want is None:
        return 2, f"판정 불가 {manifest_path}: manifest 를 읽지 못했다(없음·손상·schema·항목 필드)"
    if not os.path.isdir(folder):
        return 2, f"판정 불가 {folder}: 폴더가 아니다"
    have = {rel: entry(folder, rel) for rel in walk_files(folder)}
    missing = sorted(path for path in want if path not in have)
    extra = sorted(path for path in have if path not in want)
    different = sorted(path for path in want if path in have and (want[path]["sha256"], want[path]["bytes"]) != (have[path]["sha256"], have[path]["bytes"]))
    sizes = [len(want), len(have), len(missing), len(extra), len(different)]
    doc = {"missing": missing, "extra": extra, "different": different, "count":
           dict(zip(("manifest", "folder", "missing", "extra", "different"), sizes))}
    return (0 if not any(sizes[2:]) else 1), doc


def main(argv):
    try:
        return dispatch(argv)
    except OSError as exc:
        print(f"판정 불가 {exc.filename}: 읽지 못했다", file=sys.stderr)
        return 2  # 못 읽음 = 판정 불가


def dispatch(argv):
    if len(argv) == 3 and argv[1] == "build":
        print(json.dumps(build(argv[2]), ensure_ascii=False, indent=2))
        return 0
    if len(argv) == 4 and argv[1] == "verify":
        rc, out = verify(argv[2], argv[3])
        print(out if rc == 2 else json.dumps(out, ensure_ascii=False, indent=2),
              file=sys.stderr if rc == 2 else sys.stdout)
        return rc
    return print("사용법: manifest.py build <루트> | verify <manifest> <폴더>", file=sys.stderr) or 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
