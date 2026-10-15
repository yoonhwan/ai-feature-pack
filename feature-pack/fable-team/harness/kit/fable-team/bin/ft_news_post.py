"""ft_news_post — 뉴스 판 발행 도구 호출 + 첫 시도 머리 시각 고정 + 초안 모드 (ft_news_ledger.py 에서 분리 · 동작 변경 0 · R209).

기준선(last.sha)은 «전 판 rc 0 + 실제 게시» 일 때만 옮긴다 — 실패 판 뒤는 다음 틱이 같은 차이로 이어 발행 · 초안(FT_NEWS_MODE=draft)은 파일만 쓰고 기준선을 옮기지 않는다.
env: FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_NEWS_MODE(auto|draft)
"""
import logging
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")
HERE = Path(__file__).resolve().parent
POSTED = re.compile(r"^ft-news-publish: 발행 완료 ts=(\d+\.\d+) channel=([A-Z][A-Z0-9]*) permalink=(\S+)$")  # 줄 «전체» 일치만 — 본문 인용 줄을 결과로 오인하지 않는다
SAME_LINE = "ft-news-publish: 같은 내용 — 발행 0"
Receipt = dict[str, str | None]


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


def _receipt(out: str) -> Receipt | None:
    """발행 도구 stdout → 마지막 «결과 줄» 1개만 해석 — 새 글/채택 {ts, channel, permalink|None} · 같은 내용 {} · 해석 실패 None (R217).

    결과 줄 = 줄 전체가 성공 줄 형식이거나 «같은 내용» 줄인 것. 성공 줄이 2개 이상이면 충돌 = 해석 실패(어느 쪽이 실제 결과인지 모른다)."""
    results = [m for m, ln in ((POSTED.match(ln), ln) for ln in out.splitlines()) if m or ln == SAME_LINE]  # 성공 줄 = Match · 같은 내용 줄 = None
    if not results or sum(1 for m in results if m) > 1:
        return None
    last = results[-1]
    return {"ts": last[1], "channel": last[2], "permalink": None if last[3] == "-" else last[3]} if last else {}


def publish(news: Path, state: Path, parts: list[str], now: datetime, cur: str) -> tuple[int, list[Receipt | None]]:
    """판을 순서대로 발행 — «전 판 rc 0» 일 때만 기준선을 옮긴다(실패 판 뒤는 다음 틱이 같은 차이로 이어 발행).

    돌려주는 값 = (rc, 판마다 이번 호출의 새 글 영수증 — 같은 내용 판은 빼고, stdout 해석 실패 판은 None). 도구 stdout 은 화면에도 그대로 흘린다."""
    news.mkdir(parents=True, exist_ok=True)
    cmd = shlex.split(os.environ.get("FT_NEWS_PUBLISH") or f"bash {HERE / 'ft-news-publish.sh'}")
    posts: list[Receipt | None] = []
    for i, body in enumerate(parts, 1):
        path = news / (f"NEWS-{now:%Y%m%d-%H%M}" + (f"-p{i}" if len(parts) > 1 else "") + ".md")
        path.write_text(body, encoding="utf-8")
        if is_draft():  # 초안만 — 게시 0 · 파일은 남긴다(planner 가 다듬어 발행) · 기준선(last.sha)은 «실제 게시» 만 옮긴다
            continue
        done = subprocess.run([*cmd, str(path), "--at", f"{now:%Y-%m-%d %H:%M}"], check=False, stdout=subprocess.PIPE, text=True, encoding="utf-8")
        sys.stdout.write(done.stdout)
        if (rc := done.returncode) != 0:
            LOG.error("발행 도구 rc=%s (%d/%d판) — 기준선 그대로(다음 틱이 같은 차이를 다시 낸다)", rc, i, len(parts))
            path.unlink(missing_ok=True)
            return rc, []
        if (got := _receipt(done.stdout)) != {}:
            posts.append(got)
    if is_draft() and parts:
        return 0, []
    state.mkdir(parents=True, exist_ok=True)
    (state / "last.sha").write_text(cur + "\n", encoding="utf-8")
    (state / "pending.stamp").unlink(missing_ok=True)
    return 0, posts
