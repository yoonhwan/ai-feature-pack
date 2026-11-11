#!/usr/bin/env python3
"""ft 2.0 패키지 manifest — build <루트> 로 소스 지문을 만들고 verify <manifest> <폴더> 로 대조한다.

제외 규칙은 EXCLUDE 한 곳 · 그 문자열을 manifest 에 남긴다 · 같은 입력 두 번 = 같은 출력.
경로 = 루트 기준 상대경로 · 경로 순 정렬(다른 위치의 사본과도 대조) · `git` 호출 0(HEAD 를 파일로 읽는다).
종료 코드: 0 = 만들어짐/같음 · 1 = 다름 · 2 = 판정 불가(못 읽음·손상).
"""
import hashlib
import json
import os
import sys

SCHEMA = 1
TOOL = "tools/manifest.py"
EXCLUDE = ("__pycache__/", "*.pyc", "*.pyo", ".*")


def skip_entry(rel):
    name = rel.rsplit("/", 1)[-1]
    return name == "__pycache__" or name.startswith(".") or name.endswith((".pyc", ".pyo"))


def kind_of(rel):
    parts = rel.split("/")
    suffix = os.path.splitext(parts[-1])[1]
    if parts[0] == "tests" or parts[-1].startswith("test_"):
        return "test"
    if parts[0] == "contracts" or suffix in (".tsv", ".json", ".yaml", ".yml"):
        return "contract"
    return "doc" if suffix in (".md", ".txt") else "code"


def walk_files(root):
    """루트 아래 파일의 상대경로를 경로 순으로 돌려준다(제외 규칙 적용)."""
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        prefix = "" if rel_dir == "." else rel_dir.replace(os.sep, "/") + "/"
        dirnames[:] = [name for name in dirnames if not skip_entry(prefix + name)]
        found += [prefix + name for name in filenames if not skip_entry(prefix + name)]
    return sorted(found)


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    except OSError:
        return None


def head_of(gitdir):
    """HEAD 파일 하나로 sha 를 푼다 — 링크 워크트리는 commondir 도 본다."""
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
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def entry(root, rel):
    with open(os.path.join(root, *rel.split("/")), "rb") as handle:
        data = handle.read()
    return {"path": rel, "kind": kind_of(rel), "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest()}


def build(root):
    files = [entry(root, rel) for rel in walk_files(root)]
    return {"schema": SCHEMA, "tool": TOOL, "exclude": list(EXCLUDE),
            "source": {"sha": git_sha(root)}, "count": len(files), "files": files}


def load_manifest(path):
    text = read_text(path)
    if text is None:
        return None
    try:
        doc = json.loads(text)
        return {item["path"]: item for item in doc["files"]} if doc["schema"] == SCHEMA else None
    except (ValueError, KeyError, TypeError, AttributeError):
        return None


def differs(before, after):
    """지문이 다르면 True — sha256 우선, sha 가 같고 바이트가 달라도 다름."""
    return before["sha256"] != after["sha256"] or before["bytes"] != after["bytes"]


def verify(manifest_path, folder):
    """(rc, 문서 또는 사유 1줄) — 빠짐·남음·다름을 각각 센다."""
    want = load_manifest(manifest_path)
    if want is None:
        return 2, f"판정 불가 {manifest_path}: manifest 를 읽지 못했다(없음·JSON 손상·schema 다름)"
    if not os.path.isdir(folder):
        return 2, f"판정 불가 {folder}: 폴더가 아니다"
    have = {rel: entry(folder, rel) for rel in walk_files(folder)}
    missing = sorted(path for path in want if path not in have)
    extra = sorted(path for path in have if path not in want)
    different = sorted(path for path in want
                       if path in have and differs(want[path], have[path]))
    doc = {"missing": missing, "extra": extra, "different": different,
           "count": {"manifest": len(want), "folder": len(have), "missing": len(missing),
                     "extra": len(extra), "different": len(different)}}
    return (0 if not (missing or extra or different) else 1), doc


def main(argv):
    if len(argv) == 3 and argv[1] == "build":
        if not os.path.isdir(argv[2]):
            print(f"판정 불가 {argv[2]}: 폴더가 아니다", file=sys.stderr)
            return 2
        print(json.dumps(build(argv[2]), ensure_ascii=False, indent=2))
        return 0
    if len(argv) == 4 and argv[1] == "verify":
        rc, out = verify(argv[2], argv[3])
        if rc == 2:
            print(out, file=sys.stderr)
            return 2
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return rc
    print("사용법: manifest.py build <루트> | verify <manifest> <폴더>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
