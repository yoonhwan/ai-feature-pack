"""ft_news_ledger — 오빠 원장(PLAN-oppa-ledger.md) 한 파일에서 «마지막 발행 뒤 바뀐 줄만» 뉴스 1개 만들어 발행 (R125 · 판정 1437). 쓰는 쪽은 ft-news-ledger.sh · ft-tick.sh.

줄 키 = 칸(`## N.`) · 소제목(`### `) · 표 첫 칸(순번 칸 제외)/목록·문단 줄 전체. 뉴스는 «커밋된» 판 둘(기준선 ↔ 지금)의 차이만 — 미커밋 수정·안 바뀐 줄은 싣지 않는다.
기준선(state/news-ledger/last.sha)은 «전 판» 발행 성공(rc 0) 뒤에만 옮긴다(3500B 넘으면 칸 경계로 n/N 판 · ft_news_ledger_text.py) · 첫 실행 = 기준선만. 원장 문장 그대로라 Haiku 0.
알림 = 원장 지금 커밋 뒤에 생긴 판정 줄이 있으면 planner 에 판정마다 1통(뉴스 본문 0).
env: FT_ROOT · FT_LEDGER_REPO(기본 <루트>/.worktrees/v6-realtime-live) · FT_LEDGER_PATH · FT_NEWS_DIR · FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_MBOX
"""
import json
import logging
import os
import re
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
from ft_news_ledger_text import MAX_BYTES, Lines, render_parts  # noqa: E402,F401  (MAX_BYTES 는 시험이 발행 도구 한도와 대조)

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


def _now() -> datetime:
    v = os.environ.get("FT_NEWS_NOW")
    return datetime.strptime(v, "%Y-%m-%d %H:%M") if v else datetime.now()


def notify(root: Path, repo: Path, rel: str, sha: str, state: Path) -> None:
    """원장 지금 커밋 뒤에 생긴 판정 줄(시각 `HH:Mx` 는 윗값으로 비교) → planner 에 판정마다 1통(서명 = 판정 번호 · 1회). 실패는 ERROR 만 — 뉴스를 막지 않는다."""
    seats = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))
    wt = seats.get("_cards_wt")
    if not wt:
        return
    at = datetime.fromisoformat(_git(repo, "log", "-1", "--format=%cI", sha).strip()).replace(tzinfo=None)
    sent_f = state / "notified.txt"
    sent = set(sent_f.read_text(encoding="utf-8").split()) if sent_f.exists() else set()
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    for f in sorted((root / ".worktrees" / wt / "design" / "planner").glob("VERDICTS-planner-*-*.md")):
        day = datetime.strptime(f.stem[-8:], "%Y%m%d")
        for ln in f.read_text(encoding="utf-8").splitlines():
            m = VERDICT_ROW.match(ln)
            when = m and day.replace(hour=int(m[2]), minute=min(59, int(m[3].replace("x", "9"))))
            if not m or when <= at or m[1] in sent:
                continue
            msg = f"[원장 갱신 확인] 판정 {m[1]} 뒤 원장 갱신 0 — 반영됐나요? ({m[4][:60]})"
            if subprocess.run(["bash", mbox, "send", seats["_master"], "ft-news-ledger", msg], capture_output=True, check=False).returncode != 0:
                LOG.error("알림 쪽지 실패 판정 %s — 다음 틱에 다시", m[1])
                continue
            sent.add(m[1])
            state.mkdir(parents=True, exist_ok=True)
            sent_f.write_text("\n".join(sorted(sent)) + "\n", encoding="utf-8")


def run() -> int:
    root = env.ft_root()
    repo = Path(os.environ.get("FT_LEDGER_REPO") or root / ".worktrees" / "v6-realtime-live")
    rel = os.environ.get("FT_LEDGER_PATH") or "design/planner/PLAN-oppa-ledger.md"
    news = Path(os.environ.get("FT_NEWS_DIR") or root / "design" / "planner" / "news")
    state = root / ".fable-team" / "state" / "news-ledger"
    try:
        cur = _git(repo, "log", "-1", "--format=%H", "--", rel).strip()
        if not cur:
            raise RuntimeError(f"{rel} 가 커밋되지 않았다(뉴스는 커밋된 판만)")
        base_f = state / "last.sha"
        base = base_f.read_text(encoding="utf-8").strip() if base_f.exists() else ""
        try:
            notify(root, repo, rel, cur, state)
        except Exception as e:  # 알림 실패가 뉴스를 막지 않는다
            LOG.error("알림 건너뜀: %s", e)
        if base == cur:
            return 0
        diff = diff_ledger(parse_ledger(_git(repo, "show", f"{base}:{rel}")), parse_ledger(new_text := _git(repo, "show", f"{cur}:{rel}"))) if base else []
        now = _pending_now(state, base, cur) if diff else _now()
        parts = render_parts(now, parse_ledger(new_text), diff, rel) if diff else []
    except (RuntimeError, OSError, ValueError) as e:
        LOG.error("원장 뉴스 실패: %s", e)
        return 1
    return _publish(news, state, parts, now, cur)


def _pending_now(state: Path, base: str, cur: str) -> datetime:
    """같은 차이(기준선→지금 커밋)를 다시 낼 때는 첫 시도의 머리 시각을 쓴다 — 재실행 분이 달라도 먼저 올라간 판이 «같은 글» 로 채택된다."""
    f = state / "pending.stamp"
    got = f.read_text(encoding="utf-8").split(maxsplit=2) if f.exists() else []
    if got[:2] == [base, cur]:
        return datetime.strptime(got[2].strip(), "%Y-%m-%d %H:%M")
    now = _now()
    state.mkdir(parents=True, exist_ok=True)
    f.write_text(f"{base} {cur} {now:%Y-%m-%d %H:%M}\n", encoding="utf-8")
    return now


def _publish(news: Path, state: Path, parts: list[str], now: datetime, cur: str) -> int:
    """판을 순서대로 발행 — «전 판 rc 0» 일 때만 기준선을 옮긴다(실패 판 뒤는 다음 틱이 같은 차이로 이어 발행)."""
    news.mkdir(parents=True, exist_ok=True)
    cmd = shlex.split(os.environ.get("FT_NEWS_PUBLISH") or f"bash {HERE / 'ft-news-publish.sh'}")
    for i, body in enumerate(parts, 1):
        path = news / (f"NEWS-{now:%Y%m%d-%H%M}" + (f"-p{i}" if len(parts) > 1 else "") + ".md")
        path.write_text(body, encoding="utf-8")
        if (rc := subprocess.run([*cmd, str(path), "--at", f"{now:%Y-%m-%d %H:%M}"], check=False).returncode) != 0:
            LOG.error("발행 도구 rc=%s (%d/%d판) — 기준선 그대로(다음 틱이 같은 차이를 다시 낸다)", rc, i, len(parts))
            path.unlink(missing_ok=True)
            return rc
    state.mkdir(parents=True, exist_ok=True)
    (state / "last.sha").write_text(cur + "\n", encoding="utf-8")
    (state / "pending.stamp").unlink(missing_ok=True)
    return 0


def main(argv: list[str]) -> int:
    return run() if argv[:1] in ([], ["run"]) else 2


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
