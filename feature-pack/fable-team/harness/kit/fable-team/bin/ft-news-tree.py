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

세션 상태 절(오빠 2026-09-29 「트리출력과 세션 작업상태 출력 맞추자」): 트리의 «← 좌석 상태» 와 맨 아래
«세션명 - 상태 - 역할 - 진행내용» 은 같은 함수(seat_state)·같은 seats.json 행(card · job · doing)에서 나온다.
  좌석 행 card = 카드 id(트리 [idx:] 와 매칭) · job = 역할 · doing = 진행내용 — 오케가 발주할 때 seats.json 에 적는다.
  대상 = 이름이 FB_CFO·CFO_ 로 시작하고 (tmux 가 살아 있거나 · 대체 없이 멈춘) 행.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

GLYPHS = "✅🔄⏳⏸❌"
FOLDER_GLYPH = {"완성": "✅", "진행": "🔄", "대기": "⏳", "inbox": "⏳"}
LINE = re.compile(
    r"^(?P<ind> *)(?:\[(?P<st>[" + GLYPHS + r"])?\s*(?:idx:(?P<idx>[^\]\s]+))?\]\s*)?(?P<text>.*)$"
)


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
        by_index = v.get("card") == idx or str(v.get("index", "")).endswith(f"/{idx}.md")
        by_name = not v.get("index") and re.sub(r"#\d+$", "", name).endswith(f"-{slug}")
        if by_index or by_name:
            out.append(name)
    return out


def seat_turn(status_sh: Path, seat: str) -> str:
    try:
        r = subprocess.run(
            ["bash", str(status_sh), "turn", seat], capture_output=True, text=True, timeout=10
        )
        return (r.stdout.split() or ["?"])[0]
    except (OSError, subprocess.TimeoutExpired):
        return "?"


SHORT_MAX = 160
TURN_KO = {"WORKING": "작업중", "IDLE": "대기"}
SEAT_PREFIX = re.compile(r"^(FB_CFO|CFO_)")


def tmux_alive() -> set[str]:
    r = subprocess.run(["tmux", "ls", "-F", "#{session_name}"], capture_output=True, text=True)
    return set(r.stdout.split("\n")) if r.returncode == 0 else set()


def seat_state(ctx: dict, seat: str) -> str:
    # 트리 주석과 세션 상태 절이 함께 쓰는 유일한 상태 판정 — 값 = 작업중/대기/정지레디/정지
    role = ctx["seats"][seat].get("role")
    if seat not in ctx["alive"] or role == "stopped":
        return "정지"
    if role == "stop-ready":
        return "정지레디"
    turn = seat_turn(ctx["status_sh"], seat)
    if (
        turn == "UNKNOWN"
    ):  # 첫 턴이 안 끝난 새 좌석은 jsonl 에 turn_duration 이 없다 — pane 스피너로 판정
        r = subprocess.run(
            ["bash", str(ctx["status_sh"]), "one", seat], capture_output=True, text=True, timeout=10
        )
        turn = {"BUSY": "WORKING", "IDLE": "IDLE"}.get((r.stdout.split() or ["", "?"])[1], turn)
    return TURN_KO.get(turn, turn)


def session_block(ctx: dict) -> list[str]:
    rows = []
    for name, v in ctx["seats"].items():
        if not isinstance(v, dict) or not SEAT_PREFIX.match(name):
            continue
        if name in ctx["alive"] or (v.get("role") == "stopped" and not v.get("_replaced_by")):
            rows.append(
                f"- {name} - {seat_state(ctx, name)} - {v.get('job', '-')} - {v.get('doing', '-')}"
            )
    return rows


def parse(path: Path) -> list[dict]:
    root: dict = {"children": [], "level": -1}
    stack = [root]
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = LINE.match(raw.rstrip())
        node = {
            "level": len(m["ind"]) // 2,
            "st": m["st"],
            "idx": m["idx"],
            "text": m["text"],
            "children": [],
        }
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
            live = [f"{s} {seat_state(ctx, s)}" for s in seats_on(ctx["seats"], node["idx"])]
            note += f"  ← {' · '.join(live)}" if live else "  ← 좌석 없음"
        st = node["st"] or derived
    elif node["st"]:
        st = node["st"]
    elif kids:
        st = (
            "❌"
            if "❌" in kids
            else "✅"
            if all(k == "✅" for k in kids)
            else "⏸"
            if all(k == "⏸" for k in kids)
            else "🔄"
            if ("🔄" in kids or "✅" in kids)
            else "⏳"
        )
    else:
        st = "⏳"
    node["out_st"], node["note"] = st, note
    ctx["count"][st] = ctx["count"].get(st, 0) + (0 if node["children"] else 1)
    return st


def short(text: str) -> str:
    # 요약본: 긴 행은 «무엇(첫 ' — ' 앞) … 지금(마지막 '→' 뒤)» 만 — 중간 이력은 전체본에서 본다
    if len(text) <= SHORT_MAX:
        return text
    head = text.split(" — ")[0]
    tail = text.rsplit("→", 1)[1].strip() if "→" in text else ""
    return f"{head} … {tail}" if tail else head


def render(nodes: list[dict], prefix: str = "", full: bool = True) -> list[str]:
    # 요약본(오빠 10-01 「아닐땐 기본 진행중과 열려있는것만」): ✅ 가지는 통째로 뺀다
    shown = nodes if full else [n for n in nodes if n["out_st"] != "✅"]
    lines = []
    for i, n in enumerate(shown):
        last = i == len(shown) - 1
        text = n["text"] if full else short(n["text"])
        lines.append(f"{prefix}{'└─' if last else '├─'} {n['out_st']} {text}{n['note']}")
        lines += render(n["children"], prefix + ("   " if last else "│  "), full)
    return lines


def main() -> int:
    # 전체본 = 오빠가 «전체»를 요청할 때만(--full 또는 FT_NEWS_FULL=1) — 기본은 요약본(컨텍스트 소모)
    full = "--full" in sys.argv or os.environ.get("FT_NEWS_FULL") == "1"
    args = [a for a in sys.argv[1:] if a != "--full"]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    tree = Path(args[0])
    wt = Path(
        subprocess.run(
            ["git", "-C", str(tree.parent), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    )
    common = Path(
        subprocess.run(
            ["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    ).parent
    ctx = {
        "indices": tree.parent / "indices",
        "seats": json.loads((common / ".fable-team" / "seats.json").read_text(encoding="utf-8")),
        # 트리 원본 워크트리(c-level-planning)엔 .fable-team/bin 이 없다 — 이 스크립트 옆 것을 쓴다(없으면 턴이 전부 ?)
        "status_sh": Path(__file__).resolve().parent / "ft-seat-status.sh",
        "count": {},
        "alive": tmux_alive(),
    }
    nodes = parse(tree)
    for n in nodes:
        resolve(n, ctx)
    for n in nodes:  # 맨 윗줄(골·묶음 이름)은 가지 없이
        if not full and n["out_st"] == "✅":
            continue
        print(f"{n['out_st']} {n['text'] if full else short(n['text'])}{n['note']}")
        print("\n".join(render(n["children"], full=full)))
    total = sum(ctx["count"].values())
    print("\n말단 " + " · ".join(f"{g}{ctx['count'].get(g, 0)}" for g in GLYPHS) + f" / {total}")
    if not full:
        print("(요약본 — ✅ 닫힌 가지 생략 · 긴 행은 «무엇 … 지금» 만 · 전체본: FT_NEWS_FULL=1)")
    print("\n세션 상태")
    print("\n".join(session_block(ctx)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
