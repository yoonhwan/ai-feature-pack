"""magazine_publish — 슬랙 발행 상태기계. 같은 날 뿌리 글은 최대 1개 (설계 §5 · DA HOLD-M1 교정).

상태 파일 {날짜: {phase, at, ts, pdf, sha}} 의 phase: posting(게시 «전» 기록) → posted(ts 받자마자) → done(PDF 완료).
뿌리 글을 쓰기 «전» 항상 채널 history 에서 날짜 표식을 찾는다 — 있으면 그 ts 를 채택(응답 유실·상태 쓰기 실패·상태 분실 복구).
posting 인데 표식이 없으면 자동 재게시 0 → PublishError(사람이 채널을 보고 --force-root).
"""
import json
import logging
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from magazine_slack import Target, find_root, post_root, upload_pdf
from mirror_lib import save_state

LOG = logging.getLogger("byz_morning_magazine")
KST = ZoneInfo("Asia/Seoul")


class PublishError(RuntimeError):
    pass


@dataclass(frozen=True)
class Day:
    date: str
    text: str
    pdf: Path
    oldest_epoch: float
    md_sha: str = ""


def read_state(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise PublishError(f"상태 파일 읽기 실패: {path} ({type(e).__name__})") from e
    if not isinstance(data, dict):
        raise PublishError(f"상태 파일 형식 오류: {path}")
    return data


def last_done(path: Path) -> str | None:
    """마지막으로 발행 완료(done)된 날짜 — 건너뛴 날 계산의 기준."""
    return max((d for d, r in read_state(path).items() if r.get("phase") == "done"), default=None)


def done_ts(path: Path, date: str) -> str | None:
    """그날이 이미 done 이면 그 뿌리 글 ts, 아니면 None — CLI 가 수집 «전»에 건너뛸지 보는 데 쓴다."""
    rec = read_state(path).get(date, {})
    return rec.get("ts", "") if rec.get("phase") == "done" else None


def set_phase(path: Path, date: str, phase: str, **fields: str) -> None:
    try:
        state = read_state(path)
        state[date] = {"phase": phase, "at": datetime.now(KST).isoformat(timespec="seconds"), **fields}
        save_state(path, state)  # type: ignore[arg-type]
    except OSError as e:
        raise PublishError(f"상태 쓰기 실패({phase}): {path} ({type(e).__name__})") from e


def _unknown(date: str) -> PublishError:
    return PublishError(f"불명 상태: {date} 뿌리 글 확인 필요 — 앞 실행이 게시를 시도했는데 채널에 표식이 없음. 채널을 보고 --force-root")


def _root_ts(t: Target, day: Day, state_path: Path, phase: str, force: bool, force_root: bool) -> str:
    found = None if force else find_root(t, day.date, day.oldest_epoch)
    if found:
        LOG.info("%s 뿌리 글 표식 채택 ts=%s (재게시 0)", day.date, found)
        set_phase(state_path, day.date, "posted", ts=found)
        return found
    if phase == "posting" and not force_root:
        raise _unknown(day.date)
    set_phase(state_path, day.date, "posting")
    ts = post_root(t, day.text)
    set_phase(state_path, day.date, "posted", ts=ts)
    return ts


def publish_day(t: Target, day: Day, state_path: Path, *, force: bool = False, force_root: bool = False) -> dict[str, str]:
    """반환 {action: skip|published, ts}. 우선순위: done=건너뜀 · posted=PDF 만 재시도 · posting=표식 확인부터."""
    rec = {} if force else read_state(state_path).get(day.date, {})
    phase = rec.get("phase", "")
    if phase == "done":
        return {"action": "skip", "ts": rec.get("ts", "")}
    ts = rec["ts"] if phase == "posted" and rec.get("ts") else _root_ts(t, day, state_path, phase, force, force_root)
    upload_pdf(t, ts, day.pdf, f"아침 매거진 {day.date}")
    set_phase(state_path, day.date, "done", ts=ts, pdf=str(day.pdf), sha=day.md_sha)
    return {"action": "published", "ts": ts}
