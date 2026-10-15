"""ft_news_post — 뉴스 판 발행 도구 호출 + 첫 시도 머리 시각 고정 + 초안 모드 (ft_news_ledger.py 에서 분리 · 동작 변경 0 · R209).

기준선(last.sha)은 «전 판 rc 0 + 실제 게시» 일 때만 옮긴다 — 실패 판 뒤는 다음 틱이 같은 차이로 이어 발행 · 초안(FT_NEWS_MODE=draft)은 파일만 쓰고 기준선을 옮기지 않는다.
env: FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_NEWS_MODE(auto|draft)
"""
import logging
import os
import shlex
import subprocess
from datetime import datetime
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")
HERE = Path(__file__).resolve().parent


def news_now() -> datetime:
    v = os.environ.get("FT_NEWS_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now()


def pending_now(state: Path, base: str, cur: str) -> datetime:
    """같은 차이(기준선→지금 커밋)를 다시 낼 때는 첫 시도의 머리 시각을 쓴다 — 재실행 분이 달라도 먼저 올라간 판이 «같은 글» 로 채택된다."""
    f = state / "pending.stamp"
    got = f.read_text(encoding="utf-8").split(maxsplit=2) if f.exists() else []
    if got[:2] == [base, cur]:
        return datetime.strptime(got[2].strip(), "%Y-%m-%d %H:%M")
    now = news_now()
    state.mkdir(parents=True, exist_ok=True)
    f.write_text(f"{base} {cur} {now:%Y-%m-%d %H:%M}\n", encoding="utf-8")
    return now


def is_draft() -> bool:
    return os.environ.get("FT_NEWS_MODE") == "draft"


def publish(news: Path, state: Path, parts: list[str], now: datetime, cur: str) -> int:
    """판을 순서대로 발행 — «전 판 rc 0» 일 때만 기준선을 옮긴다(실패 판 뒤는 다음 틱이 같은 차이로 이어 발행)."""
    news.mkdir(parents=True, exist_ok=True)
    cmd = shlex.split(os.environ.get("FT_NEWS_PUBLISH") or f"bash {HERE / 'ft-news-publish.sh'}")
    for i, body in enumerate(parts, 1):
        path = news / (f"NEWS-{now:%Y%m%d-%H%M}" + (f"-p{i}" if len(parts) > 1 else "") + ".md")
        path.write_text(body, encoding="utf-8")
        if is_draft():  # 초안만 — 게시 0 · 파일은 남긴다(planner 가 다듬어 발행) · 기준선(last.sha)은 «실제 게시» 만 옮긴다
            continue
        if (rc := subprocess.run([*cmd, str(path), "--at", f"{now:%Y-%m-%d %H:%M}"], check=False).returncode) != 0:
            LOG.error("발행 도구 rc=%s (%d/%d판) — 기준선 그대로(다음 틱이 같은 차이를 다시 낸다)", rc, i, len(parts))
            path.unlink(missing_ok=True)
            return rc
    if is_draft() and parts:
        return 0
    state.mkdir(parents=True, exist_ok=True)
    (state / "last.sha").write_text(cur + "\n", encoding="utf-8")
    (state / "pending.stamp").unlink(missing_ok=True)
    return 0
