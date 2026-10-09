#!/usr/bin/env python3
"""byz_morning_magazine — 아침 매거진 CLI (설계 DESIGN-morning-magazine-20261008 §7).

순서: 구조 모델 → 요약 → 쉬운 판(eli5) → md·html·여러 쪽 PDF → (ops/magazine push) → 표식 확인 → posting → 뿌리 글 → posted
      → 풀 디테일 PDF 첨부 → pdf_done → 쉬운 판 PDF 첨부 → done. (eli5 실패 = ERROR + 뿌리 글·PDF 근거 절에 같은 경고 줄, PDF 는 계속 — 설계 §5)
--dry-run = 파일을 만들고 슬랙 글을 stdout 에만 낸다(게시·push·상태 쓰기 0).
--reattach rN = 이미 발행된 날의 스레드에 답글 + 풀 디테일 PDF·쉬운 판 PDF 를 다시 붙인다(새 뿌리 글 0 · --force·--force-root 와 배타).
push 는 기본 켬 — 수동 시험은 --no-push (판정 348). 구조 모델은 수집 모듈(magazine_collect.collect)이 만든다.
"""
import argparse
import hashlib
import json
import logging
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import thread_ledger as lg
from magazine_block import block_for, planner_seats, record
from magazine_card_shape import bad_lines
from magazine_eli5_decisions import split_verdicts
from magazine_eli5_pdf import write_eli5
from magazine_emit import Model
from magazine_git import blob_url, publish_md
from magazine_pdf import html_to_pdf
from magazine_publish import KST, Day, done_ts, last_done, publish_day
from magazine_cli_args import parse_args
from magazine_reattach import reattach, rev_done_ts, reply_text
from magazine_render_full import build_eli5, render_full
from magazine_slack import Target, eli5_warning_line, failure_text, post_root, root_text
from magazine_summary import summarize_model
from magazine_window import MagazineError
from mirror_lib import MirrorError, read_token

LOG = logging.getLogger("byz_morning_magazine")


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


@dataclass(frozen=True)
class Made:
    md_path: Path
    html_path: Path
    pdf_path: Path
    eli5_path: Path | None
    md: str
    lines: list[str]
    pages: int
    warn: str | None  # 쉬운 판 실패 경고 1줄(뿌리 글·답글·PDF 근거 절에 같은 줄)
    malformed: str | None = None  # 형식 미달 카드·요청 행 경고 1~2줄(뿌리 글 — PDF 첫 화면과 같은 줄)
    eli5_pdf: Path | None = None  # 슬랙에 붙는 쉬운 판(eli5_path 의 HTML 은 out 폴더에만 남는다)


def make_files(model: Model, args: argparse.Namespace) -> Made:
    summary = summarize_model(model, args.summary_cmd, planner_seats(args))
    eli5, cause = build_eli5(model, args.summary_cmd, summary.lines)  # PDF 렌더 «전»에 확정 — 실패 원인이 PDF 근거 절에 들어간다
    out = Path(args.out_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    stem = "MAGAZINE-" + str(model["date"]).replace("-", "")
    eli5_path, eli5_pdf, cause = write_eli5(eli5, cause, out, stem, str(model["date"]), html_to_pdf)  # 쉬운 판은 PDF 로 붙인다(슬랙은 HTML 을 소스 글자로 보임)
    warn = eli5_warning_line(cause) if cause is not None else None
    md, html = render_full(model, summary.lines, datetime.now(KST).strftime("%Y-%m-%d %H:%M KST"), warn)
    md_path, html_path, pdf_path = out / f"{stem}.md", out / f"{stem}.html", out / f"{stem}.pdf"
    md_path.write_text(md, encoding="utf-8")
    html_path.write_text(html, encoding="utf-8")
    pages = html_to_pdf(html_path, pdf_path, f"아침 매거진 {model['date']}")
    return Made(md_path, html_path, pdf_path, eli5_path, md, summary.lines, pages, warn, bad_lines(model), eli5_pdf)  # 카드 줄 · 요청 행 줄(별 줄) — 0 이면 None


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


def sha16(md: str) -> str:
    return hashlib.sha256(md.encode("utf-8")).hexdigest()[:16]


def run_reattach(args: argparse.Namespace) -> int:
    """run() 의 «첫 분기» — done skip·publish_day·--force 보다 앞(설계 §6 F2). 새 뿌리 글 0."""
    state, rev = Path(args.state).expanduser(), args.reattach
    try:
        date, model = resolve(args)
        if date != args.date:
            raise MagazineError(f"--date {args.date} 와 모델 날짜 {date} 가 달라요")
        ts = rev_done_ts(state, date, rev)
        if ts is not None:
            print(f"skip date={date} rev={rev} ts={ts} (이미 재첨부됨)")
            return 0
        made = make_files(model or collect_model(args, date), args)
    except Exception as e:  # noqa: BLE001 — 수집·렌더 실패도 «보이게» 알리고 exit 1
        report_failure(args, e)
        return 1
    day = Day(date, "", made.pdf_path, oldest_epoch(date), sha16(made.md), made.eli5_pdf)
    if args.dry_run:
        print(f"DRY-RUN reattach rev={rev} pdf={made.pdf_path} pages={made.pages} html={made.eli5_path or '-'} eli5pdf={made.eli5_pdf or '-'}\n--- 슬랙 답글 ---\n{reply_text(date, rev, made.warn)}")
        return 0
    try:
        res = reattach(target(args), day, state, rev, reply_text(date, rev, made.warn), force_file=tuple(args.force_file))
    except (RuntimeError, OSError) as e:
        LOG.error("재첨부 실패: %s: %s", type(e).__name__, e)
        return 1
    print(f"{res['action']} date={date} rev={rev} ts={res['ts']} pdf={made.pdf_path} pages={made.pages} html={made.eli5_path or '-'} eli5pdf={made.eli5_pdf or '-'}")
    return 0


def run(args: argparse.Namespace) -> int:
    if args.reattach:
        return run_reattach(args)
    try:
        date, model = resolve(args)
        ts = None if args.force else done_ts(Path(args.state).expanduser(), date)
        if ts is not None:  # §8 순서: 창 → 상태 읽기(done 이면 끝) → 수집… — 이미 발행한 날은 수집·요약·PDF·push 0
            if not args.dry_run:
                record(args, date, ts)  # 게시는 됐는데 앞 실행이 장부를 못 쓴 경우를 여기서 메운다(이미 있으면 그대로)
            print(f"skip date={date} ts={ts} (이미 발행됨 — 재첨부는 --reattach rN, 새 뿌리 글은 --force)")
            return 0
        model = model or collect_model(args, date)
        made = make_files(model, args)
        hil = len(model["mbox"].get("hil", []))
        push = not (args.no_push or args.dry_run)
        link = blob_url(args.repo, publish_md(Path(args.worktree), made.md, made.md_path.name, date), made.md_path.name) if push else None
        block = block_for(args, made.md_path.name, hil, push)
        if not args.dry_run:
            lg.load(Path(args.ledger).expanduser())  # 장부가 없거나 손상이면 게시 «전» 에 raise(빈 장부 흡수 0)
    except Exception as e:  # noqa: BLE001 — 어떤 수집·렌더 실패든 «보이게» 알리고 exit 1 (반쪽 매거진 0)
        report_failure(args, e)
        return 1
    decided = None if made.warn else len(split_verdicts(model["verdicts"])[0])  # 쉬운 판 첫 장 «오빠가 내린 결정» 건수(뿌리 글 안내 줄)
    text = root_text(date, made.lines, link, hil, args.mention, made.warn, block, planner_seats(args), made.malformed, decided)
    shown = f"md={made.md_path} pdf={made.pdf_path} pages={made.pages} html={made.eli5_path or '-'} eli5pdf={made.eli5_pdf or '-'}"
    if args.dry_run:
        print(f"DRY-RUN {shown}\n--- 슬랙 뿌리 글 ---\n{text}")
        return 0
    day = Day(date, text, made.pdf_path, oldest_epoch(date), sha16(made.md), made.eli5_pdf)
    try:
        res = publish_day(target(args), day, Path(args.state).expanduser(), force=args.force, force_root=args.force_root, force_file=tuple(args.force_file))
    except (RuntimeError, OSError) as e:
        LOG.error("게시 실패: %s: %s", type(e).__name__, e)
        return 1
    try:
        record(args, date, res["ts"], replace=args.force or args.force_root)
    except (RuntimeError, OSError) as e:
        LOG.error("장부 기록 실패: %s: %s", type(e).__name__, e)
        return 1
    print(f"{res['action']} date={date} ts={res['ts']} {shown}")
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(levelname)s %(message)s")
    return run(parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    sys.exit(main())
