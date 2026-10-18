"""magazine_collect_open — 열린 행 (설계 DESIGN-magazine-full-detail §2 D6).

창 끝 시점의 진행/·대기/ 카드 · REQUEST-LEDGER 의 닫히지 않은 행 · 마지막 줄이 HOLD/REJECT 인 DA 파일 · state/*/BREACH.md.
git 은 읽기 전용, ref 마다 창 끝 sha 기준. 같은 경로가 여러 ref 에 있으면 앞 ref.
"""
import re
from datetime import datetime
from pathlib import Path

import magazine_card_shape as shape
from magazine_collect_detail import TITLE_RE, blob, first_wins, git, name_status, sections
from magazine_window import MagazineError

LEDGER = "design/harness/REQUEST-LEDGER.md"
CARD_RE = re.compile(r"^design/(?:teams/)?([^/]+)/indices/(진행|대기|완성)/([^/]+\.md)$")   # R382: design/teams/<팀>/ 꼴도 팀 이름으로 읽는다
DA_GLOB = "design/*/DA-*.md"
TAIL = 3
LEDGER_CELLS = 7  # | R1 | 접수 | 요청자 | 증상 | Issue | 오빠 값 | 반영 sha |


def _cards(repo: Path, infos: list[dict[str, object]]) -> list[dict[str, object]]:
    found: list[tuple[dict[str, object], str, str, str]] = []
    for info in infos:
        for p in git(repo, "ls-tree", "-r", "--name-only", str(info["end_sha"]), "--", "design").split("\n"):
            m = CARD_RE.match(p)
            if m:
                found.append((info, m.group(1), m.group(2), p))
    closed = {(team, p.rsplit("/", 1)[-1]) for _, team, state, p in found if state == "완성"}
    rows = [(info, team, state, p) for info, team, state, p in found if state != "완성" and (team, p.rsplit("/", 1)[-1]) not in closed]
    out = [_card(repo, info, team, state, p) for info, team, state, p in rows]
    return first_wins(out, ("team", "name"))


def _card(repo: Path, info: dict[str, object], team: str, state: str, path: str) -> dict[str, object]:
    text = blob(repo, path, str(info["end_sha"]))
    title = next((m.group(1).strip() for ln in text.split("\n")[:3] if (m := TITLE_RE.match(ln))), path)
    status = next((s.body for s in sections(text) if s.head.startswith("상태")), "")
    tail = [ln.strip() for ln in status.split("\n") if ln.strip()][-TAIL:]
    return {"team": team, "state": state, "path": path, "title": title, "tail": tail, "name": path.rsplit("/", 1)[-1]}


def _requests(repo: Path, infos: list[dict[str, object]], report: bool) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    """(정상 열린 행, 형식 미달 행) — 형식 미달은 report 모드에서만 생기고 아니면 raise."""
    last: MagazineError | None = None
    for info in infos:
        try:
            text = blob(repo, LEDGER, str(info["end_sha"]))
        except MagazineError as e:
            last = e
            continue
        return _parse(text, report)
    raise last or MagazineError(f"{LEDGER} 를 읽을 ref 가 없어요")


def _parse(text: str, report: bool) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    rows: list[dict[str, str]] = []
    bad: list[dict[str, object]] = []
    for no, line in enumerate(text.split("\n"), 1):
        if not line.startswith("| R"):
            if report and _is_data_row(line):  # ID 칸이 빈/다른 데이터 행이 '| R' 필터로 조용히 사라지지 않게(DA r1 Q2)
                _flag(bad, f"(빈 ID) 줄 {no}", len(_cells(line)))
            continue
        cells = _cells(line)
        if len(cells) != LEDGER_CELLS:
            if not report:
                raise MagazineError(f"REQUEST-LEDGER 행의 열 수가 {len(cells)} 예요(기대 {LEDGER_CELLS}): {line[:60]}")
            _flag(bad, line.split("|")[1].strip(), len(cells))  # 첫 칸 그대로(행 내용은 추정·채우지 않는다)
        elif (row := _request(cells)):
            rows.append(row)
    return rows, bad


def _is_data_row(line: str) -> bool:
    """'|' 로 시작하는 줄 중 머리글(첫 칸 '#')·구분선/빈 줄(원문 줄이 전부 `|-: `)이 아닌 줄 — 끝 '|' 없는 줄도 원문 기준이라 놓치지 않는다(DA r2)."""
    if not line.startswith("|") or set(line.strip()) <= set("|-: "):
        return False
    cells = _cells(line)
    return not (cells and cells[0] == "#")


def _flag(bad: list[dict[str, object]], row_id: str, n: int) -> None:
    shape.request_report_line(row_id, n, LEDGER_CELLS)
    bad.append({"id": row_id, "cells": n})


def _cells(line: str) -> list[str]:
    cells = [c.strip() for c in line.split("|")][1:-1]
    while len(cells) > LEDGER_CELLS and cells[-1] == "":  # 사람이 손으로 쓴 표라 끝에 빈 칸이 더 붙은 행이 있다(실측 R25)
        cells.pop()
    return cells


def _request(cells: list[str]) -> dict[str, str] | None:
    if cells[5].startswith("닫힘"):
        return None
    return {"id": cells[0], "text": f"{cells[3]} → {cells[5]}" if cells[5] else cells[3]}


def _holds(repo: Path, infos: list[dict[str, object]], span: list[str]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for info in infos:
        log = git(repo, "log", str(info["end_sha"]), *span, "--diff-filter=A", "--name-status", "--format=%x01%H", "--", DA_GLOB)
        for _, path in name_status(log):
            lines = [ln.strip(" *#`") for ln in blob(repo, path, str(info["end_sha"])).split("\n") if ln.strip()]
            if lines and lines[-1].startswith(("HOLD", "REJECT")):
                out.append({"path": path, "verdict": lines[-1]})
    return first_wins(out, ("path",))


def _breaches(byz_root: Path) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for p in sorted(Path(byz_root, "state").glob("*/BREACH.md")):
        try:
            out.append({"path": str(p.relative_to(byz_root)), "text": p.read_text(encoding="utf-8")})
        except OSError as e:
            raise MagazineError(f"BREACH 읽기 실패: {p} ({type(e).__name__})") from e
    return out


def collect_open(repo: Path, infos: list[dict[str, object]], byz_root: Path, start: datetime, end: datetime) -> dict[str, object]:
    span = [f"--since={start.isoformat()}", f"--until={end.isoformat()}"]
    report = shape.report_mode()
    cards = [{k: v for k, v in c.items() if k != "name"} for c in _cards(Path(repo), infos)]
    requests, malformed_requests = _requests(Path(repo), infos, report)
    return {
        "cards": cards,
        "requests": requests,
        "malformed_requests": malformed_requests,
        "holds": _holds(Path(repo), infos, span),
        "breaches": _breaches(Path(byz_root)),
    }
