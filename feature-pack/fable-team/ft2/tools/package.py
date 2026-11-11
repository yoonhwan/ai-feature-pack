#!/usr/bin/env python3
"""ft 2.0 패키지 — build <소스> <out> --version V 로 ft2-V/ 를 만들고, check <소스> <패키지> 로 소스와 대조한다.

패키지 꼴 = 소스 파일 그대로(manifest walk 규칙 · EXCLUDE) + MANIFEST.json(manifest.build 출력 · schema 1) + PACKAGE.json 6칸.
check = 소스에서 manifest 를 «새로» 만들어 패키지 MANIFEST 와 대조 + 패키지 실제 파일을 MANIFEST 로 대조 + 숨은 파일(r1631 verify 는 안 본다).
시각 칸 0 · `git` 호출 0(source.sha 는 manifest.git_sha) · 같은 소스 두 번 = 같은 바이트.
종료 코드: 0 = 같음/만들어짐 · 1 = 다름 · 2 = 판정 불가(못 읽음·손상·이미 있음) — traceback 0.
"""
import hashlib
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest  # noqa: E402  같은 폴더의 도구(EXCLUDE·walk·build·load_manifest 재사용)

SCHEMA, NAME = 1, "ft2"
MANIFEST_FILE, PACKAGE_FILE = "MANIFEST.json", "PACKAGE.json"
HEX = frozenset("0123456789abcdef")


def write_json(path, doc):
    data = json.dumps(doc, ensure_ascii=False, indent=2).encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(data)
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    try:
        doc = json.loads(open(path, encoding="utf-8").read())
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def sub(root, rel):
    return os.path.join(root, *rel.split("/"))


def copy_file(src, dest, rel):
    target = sub(dest, rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(sub(src, rel), target)


def all_entries(root):
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        prefix = "" if dirpath == root else os.path.relpath(dirpath, root).replace(os.sep, "/") + "/"
        found += [prefix + name for name in dirnames + filenames]
    return found


def build(src, out, version):
    dest = os.path.join(out, NAME + "-" + version)
    if os.path.exists(dest):
        return 2, f"판정 불가 {dest}: 이미 있음"
    doc = manifest.build(src)
    os.makedirs(dest)
    for item in doc["files"]:
        copy_file(src, dest, item["path"])
    stored = write_json(sub(dest, MANIFEST_FILE), doc)
    info = {"schema": SCHEMA, "name": NAME, "version": version, "source": {"sha": doc["source"]["sha"]},
            "manifest_sha256": stored, "files": doc["count"]}
    write_json(sub(dest, PACKAGE_FILE), info)
    return 0, f"PACKAGE {dest} files={doc['count']} manifest_sha256={stored}"


def bad_package(info, count):
    digest, source = info.get("manifest_sha256"), info.get("source")
    return not (info.get("schema") == SCHEMA and info.get("name") == NAME
                and isinstance(info.get("version"), str) and info["version"]
                and isinstance(source, dict) and (source.get("sha") is None or isinstance(source["sha"], str))
                and isinstance(digest, str) and len(digest) == 64 and set(digest) <= HEX
                and info.get("files") == count)


def problems(src, pkg, want, info):
    fresh = manifest.build(src)
    source = {item["path"]: item["sha256"] for item in fresh["files"]}
    differ = sorted(rel for rel in set(source) | set(want) if source.get(rel) != (want[rel]["sha256"] if rel in want else None))
    if fresh["source"]["sha"] != info["source"]["sha"]:
        differ.append("source.sha")
    have = {rel: manifest.entry(pkg, rel) for rel in manifest.walk_files(pkg) if rel not in (MANIFEST_FILE, PACKAGE_FILE)}
    missing = sorted(rel for rel in want if rel not in have)
    changed = sorted(rel for rel in have if rel in want and want[rel]["sha256"] != have[rel]["sha256"])
    hidden = sorted(rel for rel in all_entries(pkg) if rel not in (MANIFEST_FILE, PACKAGE_FILE) and manifest.skip_entry(rel))
    return [f"{word} {len(rows)}" for word, rows in
            (("다름", differ), ("빠짐", missing), ("내용 다름", changed), ("숨은 파일", hidden)) if rows]


def check(src, pkg):
    if not os.path.isdir(src):
        return 2, f"판정 불가 {src}: 폴더가 아니다"
    if not os.path.isdir(pkg):
        return 2, f"판정 불가 {pkg}: 패키지 폴더가 아니다"
    want = manifest.load_manifest(sub(pkg, MANIFEST_FILE))
    if want is None:
        return 2, f"판정 불가 {sub(pkg, MANIFEST_FILE)}: manifest 를 읽지 못했다(없음·손상·schema·항목 필드)"
    info = read_json(sub(pkg, PACKAGE_FILE))
    if info is None or bad_package(info, len(want)):
        return 2, f"판정 불가 {sub(pkg, PACKAGE_FILE)}: 칸이 빠졌거나 형식이 틀렸다"
    found = problems(src, pkg, want, info)
    return (1 if found else 0), (" ".join(found) if found else f"SAME {pkg} files={len(want)}")


def dispatch(argv):
    if len(argv) == 6 and argv[1] == "build" and argv[4] == "--version" and argv[5] and "/" not in argv[5]:
        return build(argv[2], argv[3], argv[5])
    if len(argv) == 4 and argv[1] == "check":
        return check(argv[2], argv[3])
    return 2, "사용법: package.py build <소스> <out> --version <버전> | package.py check <소스> <패키지>"


def main(argv):
    try:
        rc, line = dispatch(argv)
    except OSError as exc:
        return print(f"판정 불가 {exc.filename}: 읽지 못했다", file=sys.stderr) or 2  # 못 읽음 = 판정 불가
    print(line, file=sys.stderr if rc == 2 else sys.stdout)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
