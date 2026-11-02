"""ft_news_desk_relay — desk 쪽지 relay 의 «간격 검사 + 보낸 것으로 셈» (r1348 · ft_news_desk.py 에서 분리 · 동작 변경 0 은 relay()).

간격(설계 1): 마지막 relay 시각 = <state>/relay-last.txt(epoch 초 1줄 · 일반 파일). 지금 − 마지막 < FT_DESK_RELAY_GAP_MIN(기본 120)분이면 relay 0.
  하루 상한 12통(DAY_CAP)은 그대로 둔 이중 안전 — 24시간 ÷ 12 = 120분이라 상한이 «자정 뒤 2시간» 에 다 쓰이지 않게 고르게 편다.
  relay 가 성공한 뒤에만 이 파일을 갱신한다(실패 = 불변 · mark_sent).
보낸 것으로 셈(설계 N10): relay 도구가 «QUEUED seq=…» 를 낸 뒤 늦게 끝나 시간 상한에 걸려도 쪽지는 이미 들어갔다 — 실패로 세면 수·digest 가 안 올라 같은 쪽지를 매 틱 다시 보낸다.
"""
import logging
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

from ft_news_desk_blocks import DOING_CHARS, _timeout

LOG = logging.getLogger("ft_news_desk")
GAP_MIN_DEFAULT = 120.0   # 하루 12통 ÷ 24시간 = 120분 간격
QUEUED = re.compile(r"\bQUEUED seq=\d+")


def gap_min() -> float:
    try:
        return float(os.environ.get("FT_DESK_RELAY_GAP_MIN", GAP_MIN_DEFAULT))
    except ValueError:
        return GAP_MIN_DEFAULT


def _last_path(state: Path) -> Path:
    return state / "relay-last.txt"


def _last_epoch(state: Path) -> float | None:
    """마지막 relay 시각(epoch 초) — 파일 없음 = None(처음 · 보낸다) · 깨짐 = WARN 1줄 + None(보낸다 · 다음 성공이 새로 쓴다)."""
    try:
        raw = _last_path(state).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    except OSError as e:
        LOG.warning("relay-last.txt 못 읽음 — 간격 검사 없이 진행: %s", e)
        return None
    try:
        return float(raw)
    except ValueError:
        LOG.warning("relay-last.txt 값이 숫자가 아니다(%r) — 간격 검사 없이 진행", raw[:40])
        return None


def gap_hold(state: Path, now: datetime) -> str:
    """간격 안이면 사유 한 줄(relay 0) · 아니면 빈 글."""
    last = _last_epoch(state)
    if last is None:
        return ""
    gap = (now.timestamp() - last) / 60
    return f"간격 {gap:.0f}분 < {gap_min():.0f} — relay 0" if gap < gap_min() else ""


def mark_sent(state: Path, now: datetime) -> None:
    _last_path(state).write_text(f"{now.timestamp():.0f}\n", encoding="utf-8")


def _text(raw: bytes | str | None) -> str:
    return raw.decode("utf-8", "replace") if isinstance(raw, bytes) else (raw or "")


def relay(root: Path, path: Path, seat: str, summary: str) -> None:
    """mbox relay 1회 — rc≠0 = RuntimeError · 시간 상한에 걸렸어도 «QUEUED seq=» 가 이미 나왔으면 보낸 것으로 센다(WARN 1줄)."""
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    limit = _timeout("FT_DESK_TOOL_TIMEOUT") * 2
    try:
        done = subprocess.run(["bash", mbox, "relay", seat, "ft-news-desk", str(path), summary], capture_output=True, text=True, timeout=limit)
    except subprocess.TimeoutExpired as e:
        if QUEUED.search(_text(e.stdout)):
            LOG.warning("desk relay 시간 상한 %.0f초에 걸렸으나 QUEUED seq 확인 — 보낸 것으로 셈", limit)
            return
        raise RuntimeError(f"mbox.sh 실행 실패: 시간 초과 {limit:.0f}초(QUEUED 확인 0)") from e
    except OSError as e:
        raise RuntimeError(f"mbox.sh 실행 실패: {e}") from e
    if done.returncode != 0:
        raise RuntimeError(f"desk relay 실패 rc={done.returncode} {(done.stderr or done.stdout).strip()[:DOING_CHARS]}")
