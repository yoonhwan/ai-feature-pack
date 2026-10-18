"""ft-board ① 완성 트리 — NEWS-TREE 의 «구조»(들여쓰기·줄 글·[idx:])만 읽고 상태는 카드 폴더에서 낸다 (판정 496 · 설계 §8-2-r2).

분모 C = 그 팀 카드 폴더 고유 id 집합. 트리는 «배치»만 정한다 — 첫 등장 1곳만 세고, 트리에 없는 카드는 `축 미연결` 로 보존한다.
불변식: 팀·상태마다 Σ(축별 계수) + 미연결 계수 = |C 의 그 상태|.
손 상태 글자(`[✅]` 등)는 읽지 않고 지운다 — 지운 줄 끝에 `(카드 미연결)` 경보를 붙인다.
"""
import re
from pathlib import Path

STATES = ("완성", "진행", "대기", "중복")
GLYPHS = "✅🔄⏳⏸❌"
LINE = re.compile(r"^(?P<ind> *)(?:\[(?P<st>[" + GLYPHS + r"])?\s*(?:idx:(?P<idx>[^\]\s]+))?\]\s*)?(?P<text>.*)$")
UNLINKED = "축 미연결"


def parse_tree(path: Path) -> list[dict]:
    root: dict = {"children": [], "level": -1}
    stack = [root]
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = LINE.match(raw.rstrip())
        hand = bool(m["st"]) and not m["idx"]
        text = m["text"] + (" (카드 미연결)" if hand else "")
        node = {"level": len(m["ind"]) // 2, "idx": m["idx"], "text": text, "children": []}
        while stack[-1]["level"] >= node["level"]:
            stack.pop()
        stack[-1]["children"].append(node)
        stack.append(node)
    return root["children"]


def _new_axis(title: str) -> dict:
    return {"title": title, "counts": dict.fromkeys(STATES, 0), "entries": [], "recent": None, "_done": []}


def _count(ax: dict, name: str, card: dict) -> None:
    ax["counts"][card["state"]] += 1
    if card["state"] == "완성":
        ax["_done"].append((card["mtime"], name))


def _card_entry(depth: int, name: str, text: str, card: dict | None) -> dict:
    if card is None:
        return {"d": depth, "k": "card", "idx": name, "text": text, "state": "카드 없음", "folders": []}
    return {"d": depth, "k": "card", "idx": name, "text": text or card["title"], "state": card["state"],
            "folders": card["folders"]}


def _place(node: dict, depth: int, ax: dict, cards: dict, seen: dict) -> None:
    name = node["idx"]
    if name and name in seen:
        ax["entries"].append({"d": depth, "k": "dup", "idx": name, "text": f"(중복 링크 — 첫 위치: {seen[name]})"})
    elif name:
        seen[name] = ax["title"]
        card = cards.get(name)
        if card:
            _count(ax, name, card)
        ax["entries"].append(_card_entry(depth, name, node["text"], card))
    else:
        ax["entries"].append({"d": depth, "k": "head", "idx": None, "text": node["text"]})
    for kid in node["children"]:
        _place(kid, depth + 1, ax, cards, seen)


def _finish(ax: dict, cards: dict) -> dict:
    if ax["_done"]:  # 최근 = 센 완성 카드 중 mtime 최대 · 같으면 basename 오름차순 첫째
        ax["recent"] = cards[min(ax["_done"], key=lambda t: (-t[0], t[1]))[1]]["title"]
    del ax["_done"]
    return ax


def _axis(node: dict, cards: dict, seen: dict) -> dict:
    ax = _new_axis(node["text"])
    if node["idx"]:
        _place({**node, "children": []}, 0, ax, cards, seen)
    for kid in node["children"]:
        _place(kid, 1, ax, cards, seen)
    return _finish(ax, cards)


def _unlinked(cards: dict, seen: dict) -> dict | None:
    rest = sorted(n for n in cards if n not in seen)
    if not rest:
        return None
    ax = _new_axis(UNLINKED)
    for name in rest:
        _count(ax, name, cards[name])
        ax["entries"].append(_card_entry(1, name, "", cards[name]))
    return _finish(ax, cards)


def fold(nodes: list[dict] | None, cards: dict) -> list[dict]:
    """nodes=None → `_tree` 미지정(전부 미연결). cards = {id: {state, folders, title, mtime}}."""
    seen: dict = {}
    axes = [_axis(n, cards, seen) for n in (nodes or [])]
    tail = _unlinked(cards, seen)
    return axes + ([tail] if tail else [])
