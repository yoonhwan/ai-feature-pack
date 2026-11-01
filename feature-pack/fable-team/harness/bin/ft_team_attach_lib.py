from __future__ import annotations

import hashlib
import os
import re
import subprocess
from pathlib import Path

from ft_team_lib import team_names, team_rel

_ORIGIN_TEAMSET: dict[tuple[str, str], tuple[bool, dict[str, list[str]]]] = {}
_LAUNCHD_LIST: tuple[int, set[str], str] | None = None

class AttachError(RuntimeError):
    def __init__(self, message: str, rc: int = 1):
        super().__init__(message)
        self.rc = rc

def command(*args: str, timeout: float = 7, env: dict[str, str] | None = None) -> tuple[int, str, str]:
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)
    except (OSError, subprocess.SubprocessError) as e:
        return 99, "", str(e)
    return p.returncode, p.stdout, p.stderr

def root_path() -> Path:
    raw = os.environ.get("FT_ROOT")
    if raw:
        return Path(raw).resolve()
    rc, out, err = command("git", "rev-parse", "--show-toplevel")
    if rc:
        raise AttachError(f"ERROR 리포 루트 판정 불가: {err.strip()[:160]}", 3)
    return Path(out.strip()).resolve()

def safe(root: Path, path: Path) -> Path:
    full = (path if path.is_absolute() else root / path).resolve()
    if os.environ.get("FT_TEAM_ATTACH_SANDBOX") == "1" and full != root and root not in full.parents:
        raise AttachError(f"REJECT 샌드박스 루트 밖 경로: {full}")
    return full

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path: Path, data: bytes, dry: bool = False) -> bool:
    if path.exists() and path.read_bytes() == data:
        return False
    if not dry:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return True

def table_rows(path: Path) -> tuple[str, list[tuple[int, list[str]]]]:
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    lines = text.splitlines()
    section = next((i for i, line in enumerate(lines) if line.startswith("##") and "표 2" in line), None)
    if section is None:
        return text, []
    end = next((i for i in range(section + 1, len(lines)) if lines[i].startswith("##")), len(lines))
    rows = []
    for i in range(section + 1, end):
        line = lines[i]
        if line.startswith("|") and not re.fullmatch(r"\|[\s:|-]+\|?", line):
            rows.append((i, [c.strip().strip("`") for c in line.strip().strip("|").split("|")]))
    return text, rows

def teamset_row(root: Path, team: str) -> tuple[Path, list[str] | None]:
    path = safe(root, Path(os.environ.get("FT_TEAMSET_MD") or "design/TEAMSET.md"))
    _, rows = table_rows(path)
    return path, next((cells for _, cells in rows if cells and cells[0] == team), None)

def set_teamset_row(root: Path, team: str, cells: list[str], dry: bool = False) -> bool:
    path = safe(root, Path(os.environ.get("FT_TEAMSET_MD") or "design/TEAMSET.md"))
    text, rows = table_rows(path)
    lines = text.splitlines()
    row = "| " + " | ".join(cells) + " |"
    old = next(((i, vals) for i, vals in rows if vals and vals[0] == team), None)
    if old:
        i, vals = old
        if vals == cells:
            return False
        lines[i] = row
    else:
        section = next((i for i, line in enumerate(lines) if line.startswith("##") and "표 2" in line), None)
        if section is None:
            lines += ["", "## 표 2 — 팀별 덮어쓰기", "| 팀 | 나노 상한 | tester | arch 상시 |", "|---|---|---|---|"]
            section = len(lines) - 4
        insert = next((i for i in range(section + 1, len(lines)) if lines[i].startswith("##")), len(lines))
        lines.insert(insert, row)
    return write(path, ("\n".join(lines).rstrip() + "\n").encode(), dry)

def paths(root: Path, team: str, include_tick: bool = True) -> dict[str, Path]:
    rel = team_rel(team, root).strip("/")
    seats = root / ".fable-team" / ("seats.json" if team == "v65" else f"seats-{team}.json")
    expanded = os.path.expandvars(rel)
    if "$FT_HARNESS_ROOT" in expanded:
        raise AttachError(f"ERROR 팀 폴더 판정 불가: FT_HARNESS_ROOT 없음({rel})", 3)
    cards = Path(expanded) / "indices"
    if not cards.is_absolute():
        cards = root / cards
    if include_tick:
        tsv = Path(os.environ.get("FT_TICK_TEAM_TSV") or ".fable-team/bin/team-tick-env.tsv")
        plist_dir = os.environ.get("FT_TICK_PLIST_DIR")
    else:
        tsv = Path(".fable-team/bin/team-tick-env.tsv")
        plist_dir = None
    if not plist_dir:
        plist_dir = str(root / ".fable-team/state/launchd") if os.environ.get("FT_TEAM_ATTACH_SANDBOX") == "1" else str(Path.home() / "Library/LaunchAgents")
    return {
        "seats": safe(root, seats),
        "cards": safe(root, cards),
        "directive": safe(root, Path(".fable-team/state/directive-roots.tsv")),
        "tick": safe(root, Path(f".fable-team/state/{team}-tick")),
        "team_tsv": safe(root, tsv),
        "plist": safe(root, Path(plist_dir) / f"com.byz.ft-tick-{team}.plist"),
    }

def state_of(root: Path, team: str) -> str:
    for state in ("현역", "휴면", "삭제"):
        if team in team_names(root, state):
            return state
    raise AttachError(f"ERROR 팀 명단 판정 불가: {team}", 3)

def directive_ok(root: Path, team: str, rel: str, path: Path) -> bool:
    if rel.startswith("design/teams/"):
        return True
    return any(len(row := line.rstrip("\n").split("\t")) >= 4 and row[0] == team for line in path.read_text(encoding="utf-8").splitlines(keepends=True)) if path.is_file() else False

def tick_status(root: Path, team: str, p: dict[str, Path]) -> tuple[str, bool]:
    rows = [line.rstrip("\n").split("\t") for line in p["team_tsv"].read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")] if p["team_tsv"].is_file() else []
    tsv = any(row and row[0] == team for row in rows)
    plist = p["plist"].is_file()
    if not tsv and not plist:
        return "전용 틱 없음", True
    if tsv != plist:
        return "TSV·plist 어긋남", False
    global _LAUNCHD_LIST
    if _LAUNCHD_LIST is None:
        rc, out, err = command(os.environ.get("FT_TICK_LAUNCHCTL", "launchctl"), "list")
        labels = {line.split()[-1] for line in out.splitlines() if line.split()}
        _LAUNCHD_LIST = (rc, labels, err)
    rc, labels, err = _LAUNCHD_LIST
    if rc:
        return f"판정 불가(launchctl {err.strip()[:80] or f'rc={rc}'})", False
    return ("전용 틱 OK", True) if f"com.byz.ft-tick-{team}" in labels else ("launchctl 실행 안 됨", False)

def origin_teamset_row(root: Path, path: Path, team: str) -> tuple[bool, list[str] | None]:
    key = (str(root), str(path))
    if key not in _ORIGIN_TEAMSET:
        rel = path.relative_to(root) if root in path.parents else Path("design/TEAMSET.md")
        rc, out, _ = command("git", "-C", str(root), "show", f"origin/main:{rel}")
        rows = table_rows_from_text(out)[1] if rc == 0 else []
        _ORIGIN_TEAMSET[key] = (rc == 0, {row[0]: row for row in rows if row})
    exists, rows = _ORIGIN_TEAMSET[key]
    return exists, rows.get(team)

def table_rows_from_text(text: str) -> tuple[str, list[list[str]]]:
    lines = text.splitlines()
    section = next((i for i, line in enumerate(lines) if line.startswith("##") and "표 2" in line), None)
    if section is None:
        return text, []
    end = next((i for i in range(section + 1, len(lines)) if lines[i].startswith("##")), len(lines))
    return text, [[c.strip().strip("`") for c in line.strip().strip("|").split("|")] for line in lines[section + 1:end] if line.startswith("|") and not re.fullmatch(r"\|[\s:|-]+\|?", line)]
