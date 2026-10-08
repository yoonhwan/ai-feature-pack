#!/usr/bin/env python3
"""byz_morning_magazine — 아침 매거진 CLI (설계 DESIGN-morning-magazine-20261008 §7).

순서: 구조 모델 → 요약 → md·html·PDF → (ops/magazine push) → 표식 확인 → posting → 뿌리 글 → posted → PDF 업로드 → done.
--dry-run = md·html·PDF 를 만들고 슬랙 글을 stdout 에만 낸다(게시·push·상태 쓰기 0).
push 는 기본 켬 — 수동 시험은 --no-push (판정 348). 구조 모델은 수집 모듈(magazine_collect.collect)이 만든다.
"""
import argparse
import hashlib
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path

from magazine_emit import Model
from magazine_git import blob_url, publish_md
from magazine_pdf import html_to_pdf
from magazine_publish import KST, Day, done_ts, last_done, publish_day
from magazine_render import render
from magazine_slack import SLACK_BASE, Target, failure_text, post_root, root_text
from magazine_summary import DEFAULT_CMD, summarize_model
from magazine_window import MagazineError
from mirror_lib import MirrorError, read_token

LOG = logging.getLogger("byz_morning_magazine")
HOME = Path.home()


def parse_args(argv: list[str]) -> argparse.Namespace:
    root = os.environ.get("BYZ_ROOT", "")
    p = argparse.ArgumentParser(description="아침 매거진 발행")
    p.add_argument("--date", help="예정 발행일 YYYY-MM-DD (없으면 예약 모드)")
    p.add_argument("--dry-run", action="store_true", help="md·html·PDF 만 만들고 슬랙 글을 stdout 에 — 게시·push·상태 0")
    p.add_argument("--force", action="store_true", help="done 이어도 전체 재게시")
    p.add_argument("--force-root", action="store_true", help="posting+표식 없음(불명)을 사람이 확인한 뒤 뿌리 글 재게시")
    p.add_argument("--no-push", action="store_true", help="ops/magazine push 끔(수동 시험)")
    p.add_argument("--model-file", help="구조 모델 JSON (수집 모듈 대신 — 시험·재발행용)")
    p.add_argument("--summary-cmd", default=DEFAULT_CMD)
    p.add_argument("--out-dir", default=str(HOME / ".hermes/magazine"))
    p.add_argument("--state", default=str(HOME / ".hermes/state/byz_morning_magazine.json"))
    p.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    p.add_argument("--slack-base", default=SLACK_BASE)
    p.add_argument("--channel", default=os.environ.get("MAGAZINE_CHANNEL", "C0C6MJGRR89"))
    p.add_argument("--mention", default=os.environ.get("MAGAZINE_MENTION", "U0AC2JF0M7D"))
    p.add_argument("--repo", default=os.environ.get("GH_REPO", "SecondWindStudio/byz-agents"))
    p.add_argument("--worktree", default=os.environ.get("MAGAZINE_WORKTREE", f"{root}/.worktrees/ops-magazine"))
    p.add_argument("--repo-root", default=root, help="자료 수집용 git 리포 루트 (기본 $BYZ_ROOT)")
    p.add_argument("--mailbox", default=os.environ.get("MAGAZINE_MAILBOX", ""), help="mbox 사본 jsonl (기본 <repo-root>/.fable-team/comm/mailbox.log.jsonl)")
    return p.parse_args(argv)


def resolve(args: argparse.Namespace, now: datetime | None = None) -> tuple[str, Model | None]:
    """발행일을 «수집 전에» 정한다. --model-file 이면 (모델의 date, 모델), 아니면 window(date|None, now) → (D, None)."""
    if args.model_file:
        model: Model = json.loads(Path(args.model_file).read_text(encoding="utf-8"))
        return str(model["date"]), model
    from magazine_window import window

    return window(args.date, now or datetime.now(KST))[0], None  # 예약=마지막 닫힌 08:00 · 수동 미래 창 raise


def collect_model(args: argparse.Namespace, date: str) -> Model:
    """접점: magazine_collect.collect(date, *, repo, gh_repo, mailbox) + 상태 파일의 마지막 done 으로 건너뛴 날 표시."""
    if not args.repo_root:
        raise MagazineError("수집할 리포 루트가 없어요 — BYZ_ROOT 환경값 또는 --repo-root 필요")
    from magazine_collect import collect
    from magazine_window import skipped_days

    mailbox = Path(args.mailbox or f"{args.repo_root}/.fable-team/comm/mailbox.log.jsonl")
    model = collect(date, repo=Path(args.repo_root), gh_repo=args.repo, mailbox=mailbox)
    skipped = skipped_days(last_done(Path(args.state).expanduser()), date)
    if skipped:
        LOG.error("건너뛴 날: %s (수동 --date 로 발행 가능)", ", ".join(skipped))
        model["skipped_days"] = skipped
    return model


def load_model(args: argparse.Namespace, now: datetime | None = None) -> Model:
    date, model = resolve(args, now)
    return model or collect_model(args, date)


def make_files(model: Model, args: argparse.Namespace) -> tuple[Path, Path, Path, str, list[str]]:
    summary = summarize_model(model, args.summary_cmd)
    md, html = render(model, summary.lines, datetime.now(KST).strftime("%Y-%m-%d %H:%M KST"))
    out = Path(args.out_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    stem = "MAGAZINE-" + str(model["date"]).replace("-", "")
    md_path, html_path, pdf_path = out / f"{stem}.md", out / f"{stem}.html", out / f"{stem}.pdf"
    md_path.write_text(md, encoding="utf-8")
    html_path.write_text(html, encoding="utf-8")
    html_to_pdf(html_path, pdf_path)
    return md_path, html_path, pdf_path, md, summary.lines


def oldest_epoch(date: str) -> float:
    return datetime.strptime(date, "%Y-%m-%d").replace(hour=7, tzinfo=KST).timestamp()


def target(args: argparse.Namespace) -> Target:
    return Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, args.mention)


def report_failure(args: argparse.Namespace, err: Exception) -> None:
    LOG.error("발행 실패: %s: %s", type(err).__name__, err)
    if args.dry_run:
        return
    try:
        post_root(target(args), failure_text(f"{type(err).__name__}: {err}"))
    except MirrorError as e:
        LOG.error("실패 알림 게시도 실패: %s", e)


def run(args: argparse.Namespace) -> int:
    try:
        date, model = resolve(args)
        ts = None if args.force else done_ts(Path(args.state).expanduser(), date)
        if ts is not None:  # §8 순서: 창 → 상태 읽기(done 이면 끝) → 수집… — 이미 발행한 날은 수집·요약·PDF·push 0
            print(f"skip date={date} ts={ts} (이미 발행됨 — 다시 내려면 --force)")
            return 0
        model = model or collect_model(args, date)
        md_path, html_path, pdf_path, md, lines = make_files(model, args)
        hil = len(model["mbox"].get("hil", []))
        push = not (args.no_push or args.dry_run)
        link = blob_url(args.repo, publish_md(Path(args.worktree), md, md_path.name, date), md_path.name) if push else None
    except Exception as e:  # noqa: BLE001 — 어떤 수집·렌더 실패든 «보이게» 알리고 exit 1 (반쪽 매거진 0)
        report_failure(args, e)
        return 1
    text = root_text(date, lines, link, hil, args.mention)
    if args.dry_run:
        print(f"DRY-RUN md={md_path} html={html_path} pdf={pdf_path}\n--- 슬랙 뿌리 글 ---\n{text}")
        return 0
    day = Day(date, text, pdf_path, oldest_epoch(date), hashlib.sha256(md.encode("utf-8")).hexdigest()[:16])
    try:
        res = publish_day(target(args), day, Path(args.state).expanduser(), force=args.force, force_root=args.force_root)
    except (RuntimeError, OSError) as e:
        LOG.error("게시 실패: %s: %s", type(e).__name__, e)
        return 1
    print(f"{res['action']} date={date} ts={res['ts']} md={md_path} pdf={pdf_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(levelname)s %(message)s")
    return run(parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    sys.exit(main())
