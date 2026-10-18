"""ft_news_ledger — 오빠 원장(PLAN-oppa-ledger.md) 한 파일에서 «마지막 발행 뒤 바뀐 줄만» 뉴스 1개 만들어 발행 (R125 · 판정 1437). 쓰는 쪽은 ft-news-ledger.sh · ft-tick.sh.

줄 키 = 칸(`## N.`) · 소제목(`### `) · 표 첫 칸(순번 칸 제외)/목록·문단 줄 전체. 뉴스는 «커밋된» 판 둘(기준선 ↔ 지금)의 차이만 — 미커밋 수정·안 바뀐 줄은 싣지 않는다.
기준선(state/news-ledger/last.sha)은 «전 판» 발행 성공(rc 0) 뒤에만 옮긴다(3500B 넘으면 칸 경계로 n/N 판 · ft_news_ledger_text.py) · 첫 실행 = 기준선만. 원장 문장 그대로라 Haiku 0.
알림 = «(오빠)» 판정인데 원장 본문에 번호가 없으면 planner 에 한 틱 1통 묶음(뉴스 본문 0 · ft_news_ledger_notify.py).
env: FT_ROOT · FT_LEDGER_REPO(기본 <루트>/.worktrees/v6-realtime-live) · FT_LEDGER_PATH · FT_NEWS_DIR · FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_MBOX
"""
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
from ft_news_ledger_notify import notify  # noqa: E402
from ft_news_digest import maybe_send  # noqa: E402
from ft_news_ledger_text import MAX_BYTES, Lines, build_blocks, render_parts  # noqa: E402,F401  (MAX_BYTES 는 시험이 발행 도구 한도와 대조)
from ft_news_post import is_draft, news_now, pending_now, publish  # noqa: E402
from ft_news_status import interval_s, last_status, mark_status, status_or_none  # noqa: E402
from ft_news_watch import check_stale, locked  # noqa: E402

LOG = logging.getLogger("ft_news_ledger")
HERE = Path(__file__).resolve().parent
SECTION = re.compile(r"^##\s+(\d+(?:-\d+)?)\.\s*(.*)")
NOW_LINE = re.compile(r"^\*\*지금 전체 상태\*\*\s*:\s*(.+)")
VERDICT_ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*(\d{1,2}):([\dx]{2})\s*\|\s*(.*?)\s*\|?\s*$")
SKIP_KEY_HEADERS = {"순번"}


def _cells(ln: str) -> list[str]:
    return [c.strip() for c in ln.strip().strip("|").split("|")]


def parse_ledger(text: str) -> Lines:
    """{(칸, 소제목, 줄 키): 값 칸들}. 표 = 순번 칸을 뺀 첫 칸이 키 · 목록·문단 = 줄 전체가 키(값 비어 있음)."""
    out: Lines = {}
    cell, sub, header = "", "", None
    rows = text.splitlines()
    for i, ln in enumerate(rows):
        if m := SECTION.match(ln):
            cell, sub, header = m[1], "", None
        elif ln.startswith("###"):
            sub, header = ln.lstrip("# ").strip(), None
        elif not cell:
            if m := NOW_LINE.match(ln):
                out[("now", "", "지금 전체 상태")] = (m[1].strip(),)
        elif ln.startswith("|"):
            nxt = rows[i + 1] if i + 1 < len(rows) else ""
            if re.match(r"^\|[\s:|-]+\|$", nxt.strip()) and header is None:
                header = _cells(ln)
            elif not re.match(r"^\|[\s:|-]+\|$", ln.strip()):
                _row(out, cell, sub, header or [], _cells(ln))
        elif ln.strip() and not ln.startswith((">", "#", "---")):
            header = None
            out.setdefault((cell, sub, re.sub(r"^[-*]\s+", "", ln.strip())), ())
    return out


def _row(out: Lines, cell: str, sub: str, header: list[str], cols: list[str]) -> None:
    ki = next((i for i, h in enumerate(header) if h not in SKIP_KEY_HEADERS), 0)
    key = cols[ki] if ki < len(cols) and cols[ki] else "|".join(cols)
    while (cell, sub, key) in out:
        key += " "  # 같은 소제목 안에서 키가 겹치면 공백으로 구분(순서대로 짝지어진다)
    out[(cell, sub, key)] = tuple(c for i, c in enumerate(cols) if i != ki and c)


def _join(vals: tuple[str, ...]) -> str:
    return " · ".join(vals)


def diff_ledger(old: Lines, new: Lines) -> list[tuple[str, str]]:
    """[(새로|바뀜|빠짐, 한 줄)] — 새 판 순서대로 새로·바뀜, 이어서 빠짐. 안 바뀐 줄은 없다."""
    out = []
    for k, v in new.items():
        if k not in old:
            out.append(("새로", f"{k[2].strip()} — {_join(v)}" if v else k[2].strip()))
        elif old[k] != v:
            out.append(("바뀜", f"{k[2].strip()}: {_join(old[k])} → {_join(v)}"))
    out += [("빠짐", f"{k[2].strip()} (원장에서 빠짐)") for k in old if k not in new]
    return out


def _git(repo: Path, *a: str) -> str:
    done = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False)
    if done.returncode != 0:
        raise RuntimeError(f"git {a[0]} 실패: {done.stderr.strip()[:200]}")
    return done.stdout


def run() -> int:
    root = env.ft_root()
    state = root / ".fable-team" / "state" / "news-ledger"
    with locked(state) as got:
        if not got:
            LOG.info("다른 뉴스 실행이 일하는 중 — 건너뜀")
            return 0
        rc, why = _run(root, state)
        if interval_s() > 0:
            check_stale(root, state, news_now(), why)
        return rc


def stale_only() -> int:
    """게시 방아쇠와 독립된 정지 감시(H1) — v65 틱이 FT_TICK_NEWS_LEDGER=0 이어도 매 루프 부른다 · 게시 0."""
    root = env.ft_root()
    state = root / ".fable-team" / "state" / "news-ledger"
    with locked(state) as got:
        if got and interval_s() > 0:
            check_stale(root, state, news_now(), "원장 커밋 0 또는 뉴스 방아쇠 정지")
    return 0


def stall_cell(root: Path) -> str:
    """뉴스 첫 줄의 `stall=N` 칸(R320b) = ft-stall-scan 이 남긴 stall-scan.log «마지막 줄»(요약)의 `stall=N a=.. b=.. c=.. d=..`. 로그 없음·읽기 실패 = 칸 없음(뉴스는 막지 않는다)."""
    try:
        last = (root / ".fable-team" / "state" / "stall-scan.log").read_text(encoding="utf-8").splitlines()[-1]
    except (OSError, IndexError):
        return ""
    return " ".join(last.split()[:5]) if last.startswith("stall=") else ""


def reclaim_cell(root: Path) -> str:
    """뉴스 첫 줄의 `reclaimed=N` 칸(R332) = ft-resource-reclaim --preventive 가 reclaim.log 에 남긴 «마지막 `PREVENTIVE reclaimed=N …` 요약줄»의 N(꼬리 64KB 만 읽음). 로그 없음·요약 없음·경합 줄(`skipped=lock`) = 칸 생략이 아니라 `reclaimed=미관측` 명시(0 으로 읽히지 않게 · DA⑥ H3) · 뉴스는 막지 않는다."""
    try:
        with (root / ".fable-team" / "state" / "reclaim.log").open("rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 65536))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return "reclaimed=미관측"
    for line in reversed(tail.splitlines()):
        hit = re.match(r"PREVENTIVE reclaimed=(\d+)\b", line)
        if hit:
            return f"reclaimed={hit.group(1)}"
    return "reclaimed=미관측"


def decision_line(root: Path) -> str:
    """뉴스 첫 줄(R214 · 판정 1804) = ft-decision-count.sh 한 줄 + stall 칸(R320b) + reclaimed 칸(R332). planner 좌석표가 없는 루트(팀 밖·시험)는 줄 없음 · 도구 실패는 ERROR 로그(뉴스는 막지 않는다)."""
    if not (root / ".fable-team" / "seats-planner.json").is_file():
        return ""
    text = ""
    try:
        done = subprocess.run(["bash", str(HERE / "ft-decision-count.sh")], capture_output=True, text=True, timeout=7, env={**os.environ, "FT_ROOT": str(root)})
        if done.returncode != 0:
            LOG.error("결정 대기열 줄 건너뜀: rc=%s %s", done.returncode, done.stderr.strip()[:120])
        else:
            text = done.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        LOG.error("결정 대기열 줄 건너뜀: %s", e)
    return " · ".join(x for x in (text, stall_cell(root), reclaim_cell(root)) if x)


def _run(root: Path, state: Path) -> tuple[int, str]:
    repo = Path(os.environ.get("FT_LEDGER_REPO") or root / ".worktrees" / "v6-realtime-live")
    rel = os.environ.get("FT_LEDGER_PATH") or "design/planner/PLAN-oppa-ledger.md"
    news = Path(os.environ.get("FT_NEWS_DIR") or root / "design" / "planner" / "news")
    try:
        cur = _git(repo, "log", "-1", "--format=%H", "--", rel).strip()
        if not cur:
            raise RuntimeError(f"{rel} 가 커밋되지 않았다(뉴스는 커밋된 판만)")
        base_f = state / "last.sha"
        base = base_f.read_text(encoding="utf-8").strip() if base_f.exists() else ""
        try:
            notify(root, _git(repo, "show", f"{cur}:{rel}"), state)
        except Exception as e:  # 알림 실패가 뉴스를 막지 않는다
            LOG.error("알림 건너뜀: %s", e)
        status = status_or_none(root, news_now())
        why = "스냅샷 오래됨" if interval_s() > 0 and (status is None or status[0][1][0].startswith("(세션 상태 스냅샷")) else "원장 커밋 0"
        if base == cur:
            return _status_only(news, state, rel, cur, status, why) if interval_s() > 0 else (0, why)
        diff = diff_ledger(parse_ledger(_git(repo, "show", f"{base}:{rel}")), parse_ledger(new_text := _git(repo, "show", f"{cur}:{rel}"))) if base else []
        now = pending_now(state, base, cur) if diff else news_now()
        if diff and interval_s() > 0 and status is None:  # 필수 절을 못 만들면 게시·기준선 전진 0 — 재시도 가능(H2)
            return 1, why
        extra, new = (status[0],) if status else (), parse_ledger(new_text) if diff else {}
        parts = render_parts(now, new, diff, rel, extra, decision_line(root)) if diff else []
    except (RuntimeError, OSError, ValueError) as e:
        LOG.error("원장 뉴스 실패: %s", e)
        return 1, "원장 읽기 실패"
    rc, posts = publish(news, state, parts, now, cur)
    if rc == 0 and parts and status and not is_draft():
        mark_status(state, status[1], now)
    if rc == 0 and parts and not is_draft():
        maybe_send(root, state, now, diff, build_blocks(new, diff, extra), status, len(parts), posts)
    return rc or (1 if interval_s() > 0 and status is None else 0), (f"게시 실패 rc={rc}" if rc else why)


def _status_only(news: Path, state: Path, rel: str, cur: str, status, why: str) -> tuple[int, str]:
    """원장 새 커밋이 없을 때 — 주기가 지났고 절 digest 가 마지막 발행과 다를 때만 그 절 1판(판정 1430 «바뀐 것만»)."""
    if status is None:
        return 1, why
    block, digest = status
    last = last_status(state)
    if last and (last[0] == digest or (news_now() - last[1]).total_seconds() < interval_s()):
        return 0, why
    now = pending_now(state, "status", digest)
    rc, posts = publish(news, state, render_parts(now, {}, [], rel, (block,)), now, cur)
    if rc == 0 and not is_draft():
        mark_status(state, digest, now)
        maybe_send(env.ft_root(), state, now, [], build_blocks({}, [], (block,)), status, 1, posts)
    return rc, (f"게시 실패 rc={rc}" if rc else why)


def main(argv: list[str]) -> int:
    return {(): run, ("run",): run, ("stale",): stale_only}.get(tuple(argv[:1]), lambda: 2)()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
