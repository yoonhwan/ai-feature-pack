#!/usr/bin/env python3
"""풀스택 다이어그램 정본 빌더 — IR(fullstack.ir.json) → fullstack.drawio (+ 규칙 검사).

정본은 IR 이다. 그림은 여기서 재생성한다. 사용:
  python3 build.py            # 검사 + drawio 생성
  python3 build.py --check    # 검사만(고아 0 · 출처 없는 노드 0 · 시크릿 0 · 뷰 참조 무결)
뷰 ⓐ~ⓔ 는 IR 의 views[] 가 정의한다(drawio-skill 의 write_drawio 가 페이지로 만든다).
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
IR_PATH = HERE / "fullstack.ir.json"
OUT = HERE / "fullstack.drawio"
SKILL = Path.home() / ".claude/skills/drawio-skill/scripts/diagram_ir.py"
SECRET = re.compile(
    r"(sk-[A-Za-z0-9]{8,}|xox[abp]-|ghp_[A-Za-z0-9]{8,}|AKIA[0-9A-Z]{12,}|eyJ[A-Za-z0-9_-]{20,}"
    r"|-----BEGIN|password\s*[=:]\s*\S|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,})"
)


def load_skill():
    spec = importlib.util.spec_from_file_location("diagram_ir", SKILL)
    assert spec is not None and spec.loader is not None, f"drawio-skill 없음: {SKILL}"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(ir):
    errors = []
    ids = {n["id"] for n in ir["nodes"]}
    if len(ids) != len(ir["nodes"]):
        errors.append("중복 노드 id")
    deg = {i: 0 for i in ids}
    for e in ir["edges"]:
        for end in (e["source"], e["target"]):
            if end not in ids:
                errors.append(f"엣지 {e['id']} 의 끝 {end} 가 노드에 없음")
            else:
                deg[end] += 1
    for n in ir["nodes"]:
        if deg.get(n["id"], 0) == 0 and not n.get("group"):
            errors.append(f"고아 노드 {n['id']}")
        if not n.get("provenance"):
            errors.append(f"출처 없는 노드 {n['id']}")
        if n.get("properties", {}).get("status") not in ("사실", "추측"):
            errors.append(f"status(사실|추측) 없는 노드 {n['id']}")
    for v in ir.get("views", []):
        for nid in v["nodes"]:
            if nid not in ids:
                errors.append(f"뷰 {v['id']} 가 없는 노드 {nid} 참조")
    if m := SECRET.search(json.dumps(ir, ensure_ascii=False)):
        errors.append(f"시크릿 패턴: {m.group(0)[:12]}…")
    return errors


def main():
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    errors = check(ir)
    guess = sum(1 for n in ir["nodes"] if n["properties"].get("status") == "추측")
    print(f"nodes={len(ir['nodes'])} edges={len(ir['edges'])} views={len(ir.get('views', []))} 추측={guess}")
    for e in errors:
        print("ERROR", e)
    if errors:
        sys.exit(1)
    if "--check" in sys.argv:
        return
    skill = load_skill()
    skill.write_drawio(ir, str(OUT), views=ir.get("views") or None)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
