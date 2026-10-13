"""ft_news_io — 뉴스 초안의 실제 입력 읽기(판정 원장 · 카드 본문 · 첫 커밋 시각 · 쪽지)와 CLI (R118a). 쓰는 쪽은 ft-news-draft.sh."""
import json
import logging
import resource
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
import ft_news_haiku as nh  # noqa: E402
from ft_board_collect import collect  # noqa: E402
from ft_news_draft import generate  # noqa: E402


def read_ledger(root: Path, now: datetime) -> list[str]:
    """planner 판정 원장(VERDICTS-planner-*-YYYYMMDD.md) 중 전날·오늘 파일의 줄. 줄마다 시각이 없어 창은 파일 날짜 단위(전날 08:00 보다 넓다)."""
    wt = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8")).get("_cards_wt", "")
    since = (now - timedelta(days=1)).strftime("%Y%m%d")
    files = sorted(p for p in (root / ".worktrees" / wt / "design" / "planner").glob("VERDICTS-planner-*-*.md") if p.stem[-8:] >= since)
    return [ln for p in files for ln in p.read_text(encoding="utf-8").splitlines()]


def _card_roots(root: Path):
    """(팀 키, 카드 폴더 절대경로, 그 폴더가 든 워크트리) — 명부마다 _cards(_cards_wt)."""
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        seats = json.loads(f.read_text(encoding="utf-8"))
        if seats.get("_cards"):
            base = root / ".worktrees" / seats["_cards_wt"] if seats.get("_cards_wt") else root
            yield ("v65" if f.stem == "seats" else f.stem.removeprefix("seats-")), base / seats["_cards"], base


def read_texts(root: Path) -> dict:
    """{(팀 키, 카드 id): 본문} — 대기·진행·완성 폴더 전부."""
    return {(key, p.stem): p.read_text(encoding="utf-8") for key, cards, _ in _card_roots(root)
            for p in cards.glob("*/*.md") if p.parent.name in ("대기", "진행", "완성")}


def read_added(root: Path) -> dict:
    """{(팀 키, 카드 id): 카드 파일을 처음 커밋한 시각(초)} — 팀마다 git log 1번."""
    out: dict = {}
    for key, cards, base in _card_roots(root):
        rel = cards.relative_to(base)
        log = subprocess.run(["git", "-C", str(base), "log", "--diff-filter=A", "--name-only", "--format=@%at", "--", str(rel)],
                             capture_output=True, text=True, timeout=60, check=True).stdout
        ts = 0
        for ln in log.splitlines():
            if ln.startswith("@"):
                ts = int(ln[1:])
            elif ln.endswith(".md") and ts:
                k = (key, Path(ln).stem)
                out[k] = min(out.get(k, ts), ts)
    return out


def read_mails(root: Path) -> list[str]:
    comm = root / ".fable-team" / "comm"
    return [ln for fn in ("mailbox.jsonl", "mailbox.log.jsonl") if (comm / fn).exists()
            for ln in (comm / fn).read_text(encoding="utf-8").splitlines()]


def main(argv: list[str]) -> int:
    dry, args = "--dry-run" in argv, [a for a in argv if a != "--dry-run"]
    root, now, calls = env.ft_root(), datetime.now(), []
    out = Path(args[args.index("--out-dir") + 1]) if "--out-dir" in args else root / "design" / "planner" / "news"

    def fetch(body: bytes, timeout: float) -> bytes:
        calls.append(1)
        return nh.proxy_fetch(body, timeout)

    def send(msg: str) -> None:
        to = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8"))["_master"]
        subprocess.run(["bash", str(root / ".fable-team" / "comm" / "mbox.sh"), "send", to, "ft-news-draft", msg], check=True)

    store, t0 = root / ".fable-team" / "state" / "news-draft" / "store", time.monotonic()
    rc = generate(out, collect_fn=collect, ledger_fn=lambda: read_ledger(root, now), texts_fn=lambda: read_texts(root),
                  mails_fn=lambda: read_mails(root), easy_fn=lambda its: nh.easy_sentences(its, fetch=fetch, store=store),
                  send=send, dry_run=dry, now=now, added_fn=lambda: read_added(root))
    rss_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024 / 1024  # macOS = bytes
    print(f"ft-news-draft rc={rc} 호출 {len(calls)} · {time.monotonic() - t0:.1f}초 · 메모리 {rss_mb:.0f}MB · 출력 {out}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
