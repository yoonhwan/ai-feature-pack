#!/usr/bin/env python3
"""ft-news-tree.py <TREE.md> — 뉴스용 «완성본 하는 일» 트리를 한 번에 그린다.

왜: 나노가 많아지면 하는 일이 좌석마다 흩어진다. 오빠 2026-09-23 「많은 일을 많은 나노워커가 해도
뉴스에서 메인하네스가 한번에 노출하도록 트리구조 출력」. 오케가 손으로 트리를 다시 쓰면 매번 달라지고
카드 폴더(대기/진행/완성)와 어긋나도 모른다 — 그래서 상태는 «카드 폴더·seats.json»에서 읽는다.

TREE.md 한 줄 = 한 노드. 들여쓰기 2칸 = 한 단계. `#` 로 시작하는 줄과 빈 줄은 무시.
  [idx:<카드 id>] 설명          상태를 카드 폴더에서 읽는다(완성=✅ 진행=🔄 대기=⏳). 진행이면 좌석·턴을 붙인다.
  [✅ idx:<카드 id>] 설명       적힌 상태를 쓰되, 카드 폴더와 다르면 «⚠카드:진행» 을 붙인다(적힌 것 ≠ 들어간 것).
  [✅|🔄|⏳|⏸|❌] 설명           카드 없는 일 — 적힌 상태 그대로.
  설명                          자식이 있으면 자식에서 접는다(❌ 있으면 ❌ · 전부 ✅=✅ · 전부 ⏸=⏸ · ✅/🔄 섞이면 🔄 · 아니면 ⏳).
"""
import json
import re
import subprocess
import sys
from pathlib import Path

GLYPHS = "✅🔄⏳⏸❌"
FOLDER_GLYPH = {"완성": "✅", "진행": "🔄", "대기": "⏳", "inbox": "⏳"}
LINE = re.compile(r"^(?P<ind> *)(?:\[(?P<st>[" + GLYPHS + r"])?\s*(?:idx:(?P<idx>[^\]\s]+))?\]\s*)?(?P<text>.*)$")


def card_folder(indices: Path, idx: str) -> str | None:
    for folder in FOLDER_GLYPH:
        if (indices / folder / f"{idx}.md").exists():
            return folder
    return None


def nano_slug(idx: str) -> str:
    # ft-nano-spawn.sh 49행과 같은 규칙 — 소문자 · [a-z0-9-] 밖은 '-' · 앞 40자
    return re.sub(r"[^a-z0-9-]", "-", idx.lower())[:40]


def seats_on(seats: dict, idx: str) -> list[str]:
    # index 필드가 없는 재가동 좌석이 있다(2026-09-23 ptt-mic#0) — 그때는 스폰 이름 규칙으로 찾는다
    slug = nano_slug(idx)
    out = []
    for name, v in seats.items():
        if not isinstance(v, dict) or v.get("_replaced_by"):
            continue
        by_index = str(v.get("index", "")).endswith(f"/{idx}.md")
        by_name = not v.get("index") and re.sub(r"#\d+$", "", name).endswith(f"-{slug}")
        if by_index or by_name:
            out.append(name)
    return out


def seat_turn(status_sh: Path, seat: str) -> str:
    try:
        r = subprocess.run(["bash", str(status_sh), "turn", seat], capture_output=True, text=True, timeout=10)
        return (r.stdout.split() or ["?"])[0]
    except (OSError, subprocess.TimeoutExpired):
        return "?"


def parse(path: Path) -> list[dict]:
    root: dict = {"children": [], "level": -1}
    stack = [root]
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = LINE.match(raw.rstrip())
        node = {"level": len(m["ind"]) // 2, "st": m["st"], "idx": m["idx"], "text": m["text"], "children": []}
        while stack[-1]["level"] >= node["level"]:
            stack.pop()
        stack[-1]["children"].append(node)
        stack.append(node)
    return root["children"]


def resolve(node: dict, ctx: dict) -> str:
    kids = [resolve(c, ctx) for c in node["children"]]
    note = ""
    if node["idx"]:
        folder = card_folder(ctx["indices"], node["idx"])
        derived = FOLDER_GLYPH.get(folder or "", "❌")
        if folder is None:
            note = " ⚠카드없음"
        if node["st"] and node["st"] != derived and folder:
            note += f" ⚠카드:{folder}"
        if folder == "진행":
            live = [f"{s} {'정지레디' if ctx['seats'][s].get('role') == 'stop-ready' else seat_turn(ctx['status_sh'], s)}"
                    for s in seats_on(ctx["seats"], node["idx"])]
            note += f"  ← {' · '.join(live)}" if live else "  ← 좌석 없음"
        st = node["st"] or derived
    elif node["st"]:
        st = node["st"]
    elif kids:
        st = ("❌" if "❌" in kids else "✅" if all(k == "✅" for k in kids) else "⏸" if all(k == "⏸" for k in kids)
              else "🔄" if ("🔄" in kids or "✅" in kids) else "⏳")
    else:
        st = "⏳"
    node["out_st"], node["note"] = st, note
    ctx["count"][st] = ctx["count"].get(st, 0) + (0 if node["children"] else 1)
    return st


def render(nodes: list[dict], prefix: str = "") -> list[str]:
    lines = []
    for i, n in enumerate(nodes):
        last = i == len(nodes) - 1
        lines.append(f"{prefix}{'└─' if last else '├─'} {n['out_st']} {n['text']}{n['note']}")
        lines += render(n["children"], prefix + ("   " if last else "│  "))
    return lines


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    tree = Path(sys.argv[1])
    wt = Path(subprocess.run(["git", "-C", str(tree.parent), "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip())
    common = Path(subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                 capture_output=True, text=True, check=True).stdout.strip()).parent
    ctx = {
        "indices": tree.parent / "indices",
        "seats": json.loads((common / ".fable-team" / "seats.json").read_text(encoding="utf-8")),
        "status_sh": wt / ".fable-team" / "bin" / "ft-seat-status.sh",
        "count": {},
    }
    nodes = parse(tree)
    for n in nodes:
        resolve(n, ctx)
    for n in nodes:  # 맨 윗줄(골·묶음 이름)은 가지 없이
        print(f"{n['out_st']} {n['text']}{n['note']}")
        print("\n".join(render(n["children"])))
    total = sum(ctx["count"].values())
    print("\n말단 " + " · ".join(f"{g}{ctx['count'].get(g, 0)}" for g in GLYPHS) + f" / {total}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
