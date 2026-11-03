"""ft_news_desk_relay — desk 쪽지 relay 의 «간격 검사 + 보낸 것으로 셈» (r1348 · ft_news_desk.py 에서 분리 · 동작 변경 0 은 relay()).

간격(설계 1): 마지막 relay 시각 = <state>/relay-last.txt(epoch 초 1줄 · 일반 파일). 지금 − 마지막 < FT_DESK_RELAY_GAP_MIN(기본 120)분이면 relay 0.
  하루 상한 12통(DAY_CAP)은 그대로 둔 이중 안전 — 24시간 ÷ 12 = 120분이라 상한이 «자정 뒤 2시간» 에 다 쓰이지 않게 고르게 편다.
  relay 가 성공한 뒤에만 이 파일을 갱신한다(실패 = 불변 · mark_sent).
보낸 것으로 셈(설계 N10 · R3 · R4): relay 가 늦게 끝나 시간 상한에 걸려도 쪽지가 이미 들어갔으면(수신 영수증 줄 전체 또는 mailbox.jsonl) 실패로 세지 않는다 — 실패로 세면 수·digest 가 안 올라 같은 쪽지를 매 틱 다시 보낸다.
"""
import json
import logging
import math
import os
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path

from ft_news_desk_blocks import DOING_CHARS, _timeout

LOG = logging.getLogger("ft_news_desk")
GAP_MIN_DEFAULT = 120.0   # 하루 12통 ÷ 24시간 = 120분 간격
MAILBOX_S = 7            # 시간 초과 뒤 mailbox.jsonl 확인 상한(7초 룰)
MAILBOX_TAIL = 2_000_000  # 끝에서 이만큼 바이트만 읽는다


def gap_min() -> float:
    try:
        return float(os.environ.get("FT_DESK_RELAY_GAP_MIN", GAP_MIN_DEFAULT))
    except ValueError:
        return GAP_MIN_DEFAULT


def _last_path(state: Path) -> Path:
    return state / "relay-last.txt"


def _read_epoch(path: Path) -> float | None:
    """epoch 초 1줄 — 없음 = None · 깨짐·nan·inf = WARN 1줄 + None."""
    try:
        raw = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    except OSError as e:
        LOG.warning("%s 못 읽음: %s", path.name, e)
        return None
    try:
        v = float(raw)
    except ValueError:
        v = math.nan
    if not math.isfinite(v):
        LOG.warning("%s 값이 유한한 숫자가 아니다(%r)", path.name, raw[:40])
        return None
    return v


def _last_epoch(state: Path) -> float | None:
    """마지막 relay 시각(epoch 초) — relay-last.txt › 없거나 깨졌으면 last-sent.txt 수정 시각(설치 직후에 relay-last 없이 10분 뒤 또 보내던 것 · R1) › 둘 다 없으면 None(첫 relay 허용)."""
    if (v := _read_epoch(_last_path(state))) is not None:
        return v
    try:
        return (state / "last-sent.txt").stat().st_mtime
    except OSError:
        return None


def gap_hold(state: Path, now: datetime) -> str:
    """간격 안이면 사유 한 줄(relay 0) · 아니면 빈 글."""
    last = _last_epoch(state)
    if last is None:
        return ""
    gap = (now.timestamp() - last) / 60
    return f"간격 {gap:.0f}분 < {gap_min():.0f} — relay 0" if gap < gap_min() else ""


def mark_sent(state: Path, now: datetime, elapsed: float = 0.0) -> None:
    """relay «성공 뒤» 시각 = 틱 시작 시각 + 틱 경과 초(전문 조립이 2분 걸려도 실제 간격이 줄지 않는다 · R2)."""
    _last_path(state).write_text(f"{now.timestamp() + max(elapsed, 0.0):.0f}\n", encoding="utf-8")


def _text(raw: bytes | str | None) -> str:
    return raw.decode("utf-8", "replace") if isinstance(raw, bytes) else (raw or "")


def _receipt(out: str, seat: str) -> bool:
    """영수증 = 줄 «전체» 가 `QUEUED seq=<n> to=<desk 좌석> ` 로 시작 — 본문 인용·다른 수신자 줄은 아니다(R4)."""
    return re.search(rf"^QUEUED seq=\d+ to={re.escape(seat)}(?:\s|$)", out, re.M) is not None


def _mailbox_path(root: Path) -> Path:
    return Path(os.environ.get("FT_DESK_MAILBOX") or root / ".fable-team" / "comm" / "mailbox.jsonl")


def delivered(root: Path, seat: str, summary: str, note: Path, since: float) -> bool:
    """시간 초과 뒤 mailbox.jsonl(끝 2MB)에 «같은 수신자 · 발신 ft-news-desk · 이번 시도 시각 뒤 · 같은 본문 첫 줄(또는 같은 전문 파일)» 줄이 있나 — 실 mbox.sh 는 QUEUED 줄을 문 두드림 «뒤» 에 찍어 시간 초과면 stdout 이 비기 때문(R3). 7초 안에."""
    t0, first = time.monotonic(), summary.splitlines()[0].strip() if summary.strip() else ""
    try:
        with _mailbox_path(root).open("rb") as f:
            f.seek(0, 2)
            f.seek(max(f.tell() - MAILBOX_TAIL, 0))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError as e:
        LOG.warning("mailbox.jsonl 못 읽음 — 보냈는지 판정 불가: %s", e)
        return False
    for ln in reversed(lines):
        if time.monotonic() - t0 > MAILBOX_S:
            LOG.warning("mailbox.jsonl 확인 %d초 초과 — 보냈는지 판정 불가", MAILBOX_S)
            return False
        try:
            d = json.loads(ln)
            when = datetime.fromisoformat(str(d.get("ts"))).timestamp()
        except (ValueError, TypeError):
            continue
        if when < since:
            return False   # 이 시도 이전 줄 — 더 거슬러 볼 것 없다
        body = str(d.get("body", ""))
        if d.get("to") == seat and d.get("from") == "ft-news-desk" and (body.splitlines()[:1] == [first] or str(d.get("body_full", "")) == str(note)):
            return True
    return False


def relay(root: Path, path: Path, seat: str, summary: str) -> None:
    """mbox relay 1회 — rc≠0 = RuntimeError · 시간 상한에 걸렸을 때: 출력에 «QUEUED seq=n to=<seat>» 줄 전체가 있거나 mailbox.jsonl 에 이번 쪽지가 이미 들어 있으면 보낸 것으로 센다(WARN 1줄)."""
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    limit, since = _timeout("FT_DESK_TOOL_TIMEOUT") * 2, time.time() - 1
    try:
        done = subprocess.run(["bash", mbox, "relay", seat, "ft-news-desk", str(path), summary], capture_output=True, text=True, timeout=limit)
    except subprocess.TimeoutExpired as e:
        if _receipt(_text(e.stdout), seat) or delivered(root, seat, summary, path, since):
            LOG.warning("desk relay 시간 상한 %.0f초에 걸렸으나 보낸 것 확인 — 보낸 것으로 셈", limit)
            return
        raise RuntimeError(f"mbox.sh 실행 실패: 시간 초과 {limit:.0f}초(보낸 것 확인 0)") from e
    except OSError as e:
        raise RuntimeError(f"mbox.sh 실행 실패: {e}") from e
    if done.returncode != 0:
        raise RuntimeError(f"desk relay 실패 rc={done.returncode} {(done.stderr or done.stdout).strip()[:DOING_CHARS]}")
