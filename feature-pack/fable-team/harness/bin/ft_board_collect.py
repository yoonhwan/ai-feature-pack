"""ft-board collect() — 원장 3종(명부 seats*.json · 카드 폴더 · 판정 원장)에서 중간 dict 한 장을 만든다 (판정 421·496).

생존(tmux)·판정 fold·카드 집합은 여기서 «한 번만» 읽는다 — render 두 종은 이 dict 만 본다(재조회 0).
dict 에는 시각이 없다(같은 입력 → 같은 해시). 시각이 필요한 값(미보고 가장 오래된 m분)은 시각 원본만 넣고 render 가 뺀다.
"""
import json
import re
import sys
from datetime import datetime
from pathlib import Path

import ft_board_env as env
import ft_sheet_events
from ft_board_mail import Mail
from ft_board_seat import SeatCells
from ft_board_tree import STATES, fold, parse_tree

FOLDERS = ("대기", "진행", "완성")
QUEUE_TOP = 5


TITLE_SCAN_LINES = 5


def _title(path: Path) -> str:
    """첫 5줄 안의 첫 H1(`# `) 줄 — 빈 줄·`<!--` 주석·`##` 절 제목은 건너뛴다. 없으면 «<id> (제목 없음)» (다른 줄을 고르지 않는다)."""
    with path.open(encoding="utf-8") as f:
        head = [f.readline() for _ in range(TITLE_SCAN_LINES)]
    for line in head:
        m = re.match(r"#\s+(?:인덱스:\s*)?(.*)", line.strip())
        if m:
            return m.group(1)[:80]
    return f"{path.stem} (제목 없음)"


def read_cards(cards_dir: Path) -> dict:
    """{id: {state, folders, title, mtime}} — 같은 id 가 두 폴더에 있으면 1장 · state=중복 (어느 쪽도 버리지 않는다)."""
    hits: dict = {}
    for folder in FOLDERS:
        d = cards_dir / folder
        for f in sorted(d.glob("*.md")) if d.is_dir() else []:
            hits.setdefault(f.stem, {})[folder] = f
    cards = {}
    for name, by_folder in hits.items():
        newest = max(by_folder.values(), key=lambda p: p.stat().st_mtime)
        cards[name] = {"state": "중복" if len(by_folder) > 1 else next(iter(by_folder)),
                       "folders": sorted(by_folder), "title": _title(newest), "mtime": newest.stat().st_mtime}
    return cards


def _seats_on(seats: dict, idx: str, alive: set) -> list[str]:
    slug = re.sub(r"[^a-z0-9-]", "-", idx.lower())[:40]  # ft-nano-spawn.sh 와 같은 규칙
    out = []
    for name, v in seats.items():
        if name.startswith("_") or not isinstance(v, dict) or v.get("_replaced_by") or name not in alive:
            continue
        by_index = v.get("card") == idx or str(v.get("index", "")).endswith(f"/{idx}.md")
        by_name = not v.get("index") and re.sub(r"#\d+$", "", name).endswith(f"-{slug}")
        if by_index or by_name:
            out.append(name)
    return out


def _leads(seats: dict, alive: set, cells: SeatCells) -> list[dict]:
    out = []
    for role, key in (("master", "_master"), ("arch", "_arch")):
        name = seats.get(key)
        if name and name in alive and not (seats.get(name) or {}).get("_replaced_by"):
            out.append({"role": role, "name": name, "state": cells.text(name)})
    return out


def _progress(seats: dict, cards: dict, alive: set, cells: SeatCells) -> dict:
    prog = {}
    for name, c in sorted(cards.items()):
        if c["state"] == "진행":
            live = [{"name": s, "state": cells.text(s)} for s in _seats_on(seats, name, alive)]
            prog[name] = {"title": c["title"], "seats": live}
    return prog


def _done_today(cards: dict, date: str) -> dict:
    today = [(c["mtime"], c["title"]) for c in cards.values()
             if c["state"] == "완성" and datetime.fromtimestamp(c["mtime"]).strftime("%F") == date]
    return {"n": len(today), "last": max(today)[1] if today else None}


def _parent(root: Path, path: Path, seats: dict) -> str | None:
    """위성팀 보고선 — 명부 `_parent`(없으면 None · 표시 0). 명부 목록에 없는 팀이면 "?" + stderr 1줄(조용한 빈칸 0 · R252)."""
    parent = seats.get("_parent")
    if not parent:
        return None
    known = {"v65" if f.stem == "seats" else f.stem.removeprefix("seats-") for f in (root / ".fable-team").glob("seats*.json")}
    if parent in known:
        return parent
    print(f"WARN {path.name}: _parent={parent!r} 가 명부 목록에 없다 — 보고선 ?", file=sys.stderr)
    return "?"


def team_block(root: Path, path: Path, alive: set, date: str, vds: list, mail: Mail) -> dict:
    seats = json.loads(path.read_text(encoding="utf-8"))
    cells = SeatCells(seats, alive, mail, env.now())
    key = "v65" if path.stem == "seats" else path.stem.removeprefix("seats-")
    block = {"key": key, "label": seats.get("_label") or key, "parent": _parent(root, path, seats), "master": seats.get("_master"),
             "cards_dir": seats.get("_cards"), "tree": seats.get("_tree"), "states": {}, "axes": [], "progress": {},
             "queue": [], "done_today": {"n": 0, "last": None}, "leads": _leads(seats, alive, cells),
             "counts": dict.fromkeys(STATES, 0),
             "oppa_todo": [v["n"] for v in vds if v["state"] == "open" and v["oppa_todo"] and key in v["teams"]]}
    block.update(seats=cells.all(), stalled=cells.rows(), declared=cells.declared())
    if block["master"]:
        block.update(env.inbox(root, block["master"]), pending=env.pending(root, block["master"]))
    if not block["cards_dir"]:
        return block
    base = root / ".worktrees" / seats["_cards_wt"] if seats.get("_cards_wt") else root
    if not (base / block["cards_dir"]).is_dir():
        raise RuntimeError(f"{path.name}: 카드 폴더 없음 — {base / block['cards_dir']}")
    cards = read_cards(base / block["cards_dir"])
    nodes = None
    if block["tree"]:
        if not (base / block["tree"]).is_file():
            raise RuntimeError(f"{path.name}: _tree 파일 없음 — {base / block['tree']}")
        nodes = parse_tree(base / block["tree"])
    for c in cards.values():
        block["counts"][c["state"]] += 1
    block.update(states={n: c["state"] for n, c in cards.items()}, progress=_progress(seats, cards, alive, cells),
                 done_today=_done_today(cards, date), axes=fold(nodes, cards),
                 queue=[{"idx": n, "title": c["title"]} for n, c in sorted(cards.items()) if c["state"] == "대기"][:QUEUE_TOP])
    return block


def _key_label(path: Path) -> tuple[str, str]:
    """실패 칸의 이름표 — 명부 JSON 이 깨져도 팀 키는 파일 이름에서 나온다(라벨만 키로 떨어진다)."""
    key = "v65" if path.stem == "seats" else path.stem.removeprefix("seats-")
    try:
        return key, json.loads(path.read_text(encoding="utf-8")).get("_label") or key
    except Exception:  # noqa: BLE001 — 못 읽는 것이 바로 이 칸의 사유다(team_block 이 그 사유를 낸다)
        return key, key


def team_or_error(root: Path, path: Path, alive: set, date: str, vds: list, mail: Mail) -> dict:
    """한 팀 수집 실패를 «그 팀 칸»에 격리한다 — `{"key","label","error"}` 만(숫자 칸 0).

    없는 팀 값을 0·빈 값·옛 값으로 채우지 않는다(#0 RULE) — 그 팀 칸은 «확인 못 함» 이고, 원인은 stderr `ERROR <명부 이름>: <원인>` 에도 남는다.
    rc 는 부르는 쪽이 정한다(ft-sheet-publish = 부분 발행 2 · 전원 실패 1).
    """
    try:
        return team_block(root, path, alive, date, vds, mail)
    except Exception as e:  # noqa: BLE001 — 한 팀 예외가 전 팀 발행을 멈추지 않게(판정 r554)
        key, label = _key_label(path)
        why = str(e).removeprefix(f"{path.name}: ")  # 명부 이름은 stderr 줄이 이미 말한다
        msg = why if isinstance(e, RuntimeError) else f"{path.name} {type(e).__name__}: {why}"
        print(f"ERROR {path.name}: {msg}", file=sys.stderr)
        return {"key": key, "label": label, "error": msg}


def decision(root: Path, alive: set) -> str:
    p = root / ".fable-team" / "seats-planner.json"
    if not p.exists():
        return "확인 불가(seats-planner.json 없음)"
    name = json.loads(p.read_text(encoding="utf-8")).get("_master")
    if not name:
        return "확인 불가(seats-planner.json 에 _master 없음)"
    return name if name in alive else f"확인 불가({name} tmux 세션 없음)"


def collect(files: list[Path] | None = None) -> dict:
    root, date = env.ft_root(), env.now().strftime("%F")
    ft_sheet_events.reconcile(root)  # 사건 원장 — .committed 만 append(dedup). .prepared 는 건드리지 않는다(시트 «확인 중 N» · 판단 0). dict 는 그대로
    alive = env.tmux_alive()
    vds = env.verdicts(root, date)
    files = files or sorted((root / ".fable-team").glob("seats*.json"))
    mail = Mail(root)
    return {"date": date, "decision": decision(root, alive), "verdicts": vds, "issues": env.gh_issues(root),
            "teams": [team_or_error(root, f, alive, date, vds, mail) for f in files]}
