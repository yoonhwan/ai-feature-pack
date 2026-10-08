"""magazine_reattach — 이미 발행된 날의 스레드에 풀 디테일 PDF·쉬운 판 HTML 을 다시 붙인다 (설계 §6 · --reattach rN).

새 뿌리 글 0 — 뿌리 글이 없으면 raise. 답글 첫 줄 `*아침 매거진 D 재첨부 rN*` «정확 일치»를 먼저 찾아 채택(답글 2중 0).
상태 revs.rN = {phase, at, ts(답글), files}: posting → posted → pdf_done → done. 날짜 레코드의 phase/ts 는 건드리지 않는다.
posting 인데 표식이 없으면 자동 재게시 0 → PublishError(사람이 채널을 보고 revs.rN 을 지운다).
"""
import re
from pathlib import Path
from typing import Any

from magazine_attach import attach, file_title
from magazine_publish import Day, PublishError, now_iso, read_state, update_record
from magazine_slack import Target, find_reply_first_line, find_root, post_reply
from mirror_lib import esc

REV = re.compile(r"r[1-9]\d*")


def first_line(date: str, rev: str) -> str:
    return f"*아침 매거진 {date} 재첨부 {rev}*"


def reply_text(date: str, rev: str, warn: str | None) -> str:
    body = [first_line(date, rev), "풀 디테일 PDF 와 쉬운 판 HTML 을 다시 붙였어요 — 위의 앞 PDF 는 요약판이에요"]
    return "\n".join(body + ([esc(warn)] if warn else []))


def rev_record(path: Path, date: str, rev: str) -> dict[str, Any]:
    return read_state(path).get(date, {}).get("revs", {}).get(rev, {})


def rev_done_ts(path: Path, date: str, rev: str) -> str | None:
    """그 rN 이 이미 done 이면 답글 ts, 아니면 None — CLI 가 수집 «전»에 건너뛸지 보는 데 쓴다."""
    rec = rev_record(path, date, rev)
    return str(rec.get("ts", "")) if rec.get("phase") == "done" else None


def _set_rev(path: Path, date: str, rev: str, phase: str, **fields: str) -> None:
    def change(old: dict[str, Any]) -> dict[str, Any]:
        cur = old.get("revs", {}).get(rev, {})
        keep = {"files": cur["files"]} if "files" in cur else {}
        return {**old, "revs": {**old.get("revs", {}), rev: {"phase": phase, "at": now_iso(), **keep, **fields}}}
    update_record(path, date, change, f"{rev} {phase}")


def _set_rev_file(path: Path, date: str, rev: str, kind: str, attempt: dict[str, str]) -> None:
    def change(old: dict[str, Any]) -> dict[str, Any]:
        cur = old.get("revs", {}).get(rev, {})
        new = {**cur, "files": {**cur.get("files", {}), kind: attempt}}
        return {**old, "revs": {**old.get("revs", {}), rev: new}}
    update_record(path, date, change, f"{rev} {kind} 시도")


def _root_ts(t: Target, day: Day, state_path: Path) -> str:
    rec = read_state(state_path).get(day.date, {})
    ts = str(rec["ts"]) if rec.get("phase") == "done" and rec.get("ts") else find_root(t, day.date, day.oldest_epoch)
    if not ts:
        raise PublishError(f"뿌리 글 없음: {day.date} — 재첨부는 새 뿌리 글을 만들지 않아요(처음 발행은 --reattach 없이)")
    return ts


def _reply_ts(t: Target, day: Day, state_path: Path, root: str, rev: str, text: str) -> str:
    rec = rev_record(state_path, day.date, rev)
    if rec.get("phase") in ("posted", "pdf_done") and rec.get("ts"):
        return str(rec["ts"])
    found = find_reply_first_line(t, root, first_line(day.date, rev))
    if found:
        _set_rev(state_path, day.date, rev, "posted", ts=found)
        return found
    if rec.get("phase") == "posting":
        raise PublishError(f"불명 상태: {day.date} {rev} 답글 확인 필요 — 앞 실행이 게시를 시도했는데 스레드에 표식이 없음. 채널을 보고 상태 파일 revs.{rev} 을 지운 뒤 다시")
    _set_rev(state_path, day.date, rev, "posting")
    ts = post_reply(t, root, text)
    _set_rev(state_path, day.date, rev, "posted", ts=ts)
    return ts


def reattach(t: Target, day: Day, state_path: Path, rev: str, text: str, *, force_file: tuple[str, ...] = ()) -> dict[str, str]:
    """반환 {action: skip|reattached, ts(답글)}. text = 답글 본문(첫 줄이 표식)."""
    done = rev_done_ts(state_path, day.date, rev)
    if done is not None:
        return {"action": "skip", "ts": done}
    root = _root_ts(t, day, state_path)
    ts = _reply_ts(t, day, state_path, root, rev, text)
    files = rev_record(state_path, day.date, rev).get("files", {})
    for kind, path in (("pdf", day.pdf), ("html", day.html)):
        if path is None or (kind == "pdf" and rev_record(state_path, day.date, rev).get("phase") == "pdf_done"):
            continue
        attach(t, root, kind, path, file_title(day.date, kind, rev), attempt=files.get(kind),
               save=lambda a, k=kind: _set_rev_file(state_path, day.date, rev, k, a), force=kind in force_file)
        if kind == "pdf":
            _set_rev(state_path, day.date, rev, "pdf_done", ts=ts)
    _set_rev(state_path, day.date, rev, "done", ts=ts)
    return {"action": "reattached", "ts": ts}
