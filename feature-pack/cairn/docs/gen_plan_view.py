#!/usr/bin/env python3
"""cairn plan.yaml -> multiview HTML (프로토타입 생성기).

사용: gen_plan_view.py <plan.yaml> <template.html> <out.html>
템플릿의 `const plan = { ... };` 블록(주석 마커 `// ==== 데이터 끝 ====` 직전까지)을
yaml에서 매핑한 JSON으로 치환한다. 이게 설계문서(render-multiview-design.md)의
'문자열 치환 생성기'의 실제 검증본.
"""
import json
import sys
from pathlib import Path

from ruamel.yaml import YAML

yaml = YAML(typ="safe")


def to_view(data):
    proj = data["projects"][0]
    out = {"project": proj.get("name"), "branch": proj.get("branch"),
           "type": proj.get("type", "work"), "milestones": []}
    for m in proj.get("milestones", []) or []:
        mm = {
            "id": m["id"], "name": m["name"], "status": m.get("status"),
            "start": m.get("start"), "end": m.get("end"),
            "dep": m.get("depends_on") or [], "tasks": [],
        }
        for t in m.get("tasks", []) or []:
            tt = {"id": t["id"], "s": t.get("status"), "name": t["name"],
                  "dep": t.get("depends_on") or []}
            for k in ("assignees", "reporters", "watchers", "note", "ssot", "branch", "start", "due"):
                if t.get(k):
                    tt[k] = t[k]
            if t.get("execution_ref"):
                tt["exec"] = t["execution_ref"]
            mm["tasks"].append(tt)
        out["milestones"].append(mm)
    return out


def main():
    plan_path, tpl_path, out_path = map(Path, sys.argv[1:4])
    data = yaml.load(plan_path.read_text())
    view = to_view(data)
    tpl = tpl_path.read_text()
    i = tpl.index("const plan = ")
    j = tpl.index("// ==== 데이터 끝 ====")
    html = tpl[:i] + "const plan = " + json.dumps(view, ensure_ascii=False) + ";\n" + tpl[j:]
    out_path.write_text(html)
    n = sum(len(m["tasks"]) for m in view["milestones"])
    assert "__CAIRN_" not in html and "const plan = {\n" not in html
    print(f"OK: {out_path} ({len(view['milestones'])} milestones, {n} tasks)")


if __name__ == "__main__":
    main()
