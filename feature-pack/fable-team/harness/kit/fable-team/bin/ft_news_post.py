"""ft_news_post — 뉴스 판 발행 도구 호출 + 첫 시도 머리 시각 고정 + 초안 모드 (ft_news_ledger.py 에서 분리 · 동작 변경 0 · R209).

기준선(last.sha)은 «전 판 rc 0 + 실제 게시» 일 때만 옮긴다 — 실패 판 뒤는 다음 틱이 같은 차이로 이어 발행 · 초안(FT_NEWS_MODE=draft)은 파일만 쓰고 기준선을 옮기지 않는다.
env: FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_NEWS_MODE(auto|draft)
"""
import hashlib
import json
import logging
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

LOG = logging.getLogger("ft_news_ledger")


class _MissingGate:
    """ft_goal_gate 설치 누락(H1④) — 무장 표식이 있으면 발행 거절(fail-closed) · 없으면 경고 후 진행. 같은 판별을 한 곳(여기)에 둔다 — ft_news_publish·ft_news_ledger 도 이 객체를 쓴다."""

    def __init__(self, err: Exception) -> None:
        self.why = f"골 표 문 모듈 없음 — 설치 순서({err})"

    def armed(self, state_dir: Path) -> bool:
        return (state_dir / "goal-gate.armed").is_file()

    def problem(self, body: str, state_dir: Path) -> str:
        return self.why

    def verify_bundle(self, parts: list[str]) -> str:
        return self.why

    def refuse(self, state_dir: Path, who: str, why: str) -> bool:
        on = self.armed(state_dir)
        LOG.error("골 표 문 %s: %s (%s)", "REJECT" if on else "WOULD-REJECT", why, who)
        if on:
            try:
                state_dir.mkdir(parents=True, exist_ok=True)
                with (state_dir / "mbox-guard-goal.log").open("a", encoding="utf-8") as f:
                    f.write(f"{datetime.now(timezone.utc):%Y-%m-%dT%H:%M:%SZ} REJECT news={who} {why[:200]}\n")
            except OSError as e:
                LOG.warning("골 표 문 로그 쓰기 실패: %s", e)
            _notify_minimal(state_dir.parents[1], who, why)  # 게이트 본체 없이도 가는 최소 통지(H4)
        return on

    def goal_block(self, state_dir: Path) -> str:
        if self.refuse(state_dir, "render", self.why):
            raise RuntimeError(self.why)
        return ""

    def write_receipt(self, state_dir: Path, parts: list[str]) -> str:
        return ""

    def is_done(self, state_dir: Path, body: str) -> bool:
        return False

    def finish(self, state_dir: Path, parts: list[str], status: str, reason: str = "") -> None:
        return None

    def mark_done(self, state_dir: Path, body: str) -> None:
        return None


def _notify_minimal(root: Path, who: str, why: str) -> bool:
    """게이트 본체(ft_goal_gate)가 없을 때의 [긴급] 통지 — mbox.sh send 1회 · 같은 (진입점+사유 전체) 지문은 10분 안 1번(ft_goal_gate.notify_planner 와 같은 지문·같은 표) · 실패는 로그만(거절은 유지)."""
    state = root / ".fable-team" / "state"
    key, stamp = hashlib.sha1(f"{who}\n{why}".encode()).hexdigest()[:16], state / "goal-notify.json"
    try:
        seen = json.loads(stamp.read_text(encoding="utf-8")) if stamp.exists() else {}
        if time.time() - seen.get(key, 0) < 10 * 60:
            return False
        master = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"]
        mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
        body = f"[긴급] 뉴스 발행 거절 — 골 표\n진입점: {who}\n{why[:280]}\n조치: ft_goal_gate 설치 순서 점검(게이트 본체 없음)"
        done = subprocess.run(["bash", mbox, "send", master, "ft-news-ledger", body], capture_output=True, check=False, timeout=15)
        if done.returncode == 0:
            stamp.parent.mkdir(parents=True, exist_ok=True)
            stamp.write_text(json.dumps({**seen, key: time.time()}), encoding="utf-8")
        return done.returncode == 0
    except (OSError, KeyError, ValueError, subprocess.TimeoutExpired) as e:
        LOG.warning("planner 거절 알림 실패(게이트 본체 없음): %s", e)
        return False


try:
    import ft_goal_gate as goal_gate  # noqa: E402
except ImportError as _e:
    goal_gate = _MissingGate(_e)


def teams_block() -> str:
    """뉴스 첫 판 골 표 뒤 «팀별 완성 진행» 블록(R458 · ft_goal_table.render_teams) — 실패 = WARN + 빈 글(새 거절 게이트 0 · 뉴스를 멈추지 않는다 · 골 6)."""
    try:
        import ft_goal_table as gt  # noqa: E402
        return gt.render_teams()
    except (ImportError, RuntimeError, OSError, ValueError) as e:
        LOG.warning("팀별 완성 진행 블록 없이 발행: %s", e)
        return ""


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
    # R362 — 판 묶음 «전체» 를 보내기 전에 검증(초안 모드 포함) + 묶음별 검증 영수증 열기(이미 완료·다른 본문이면 문제) · 무장이면 전체 발행 0 + planner [긴급] 1통 · 기준선·처리 기록 불변
    if why := goal_gate.verify_bundle(parts) or goal_gate.write_receipt(state.parent, parts):
        if goal_gate.refuse(state.parent, f"bundle {cur[:10]}", why):
            LOG.error("REJECT 골 표 없음 — %s · 발행 0", why)
            return 3, []
    cmd = shlex.split(os.environ.get("FT_NEWS_PUBLISH") or f"bash {HERE / 'ft-news-publish.sh'}")
    posts: list[Receipt | None] = []
    for i, body in enumerate(parts, 1):
        path = news / (f"NEWS-{now:%Y%m%d-%H%M}" + (f"-p{i}" if len(parts) > 1 else "") + ".md")
        path.write_text(body, encoding="utf-8")
        if is_draft():  # 초안만 — 게시 0 · 파일은 남긴다(planner 가 다듬어 발행) · 기준선(last.sha)은 «실제 게시» 만 옮긴다
            continue
        if goal_gate.is_done(state.parent, body):  # 이미 나가고 기록까지 끝난 판 — 묶음 재시도가 다시 올리지 않는다
            continue
        done = subprocess.run([*cmd, str(path), "--at", f"{now:%Y-%m-%d %H:%M}"], check=False, stdout=subprocess.PIPE, text=True, encoding="utf-8")
        sys.stdout.write(done.stdout)
        if (rc := done.returncode) != 0:
            LOG.error("발행 도구 rc=%s (%d/%d판) — 기준선 그대로(다음 틱이 같은 차이를 다시 낸다)", rc, i, len(parts))
            goal_gate.finish(state.parent, parts, "failed", f"{i}/{len(parts)}판 발행 도구 rc={rc}")  # 닫는 사건 — 실패 · 같은 묶음 재시도가 이어 받는다
            path.unlink(missing_ok=True)
            return rc, []
        if (got := _receipt(done.stdout)) != {}:
            posts.append(got)
    if is_draft() and parts:
        goal_gate.finish(state.parent, parts, "drafted")  # 닫는 사건 — 초안 모드 종료
        return 0, []
    state.mkdir(parents=True, exist_ok=True)
    (state / "last.sha").write_text(cur + "\n", encoding="utf-8")
    (state / "pending.stamp").unlink(missing_ok=True)
    goal_gate.finish(state.parent, parts, "complete")  # 닫는 사건 — 전 판 발행(기준선 이동 뒤)
    return 0, posts
