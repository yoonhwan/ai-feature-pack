#!/usr/bin/env python3
"""magazine_doc — 오빠 확인 문서(planner 정리 md) 한 장을 스위스 HTML 1종으로 묶어 Slack 매거진 채널에 1회 발행 (R117 · 판정 1424).

본문은 원문 그대로(표·목록 → HTML), Haiku 프록시가 각 칸·팀 머리의 «쉬운 한 문단»만 쓴다(magazine_hermes — 실패 칸은 «쉬운 요약 실패(사유)» + ERROR).
--dry-run = HTML 만 만들고 게시·상태 쓰기 0 · --publish = 뿌리 글 1개 + 스레드에 HTML 1개(같은 원본 sha 면 skip).
"""
import argparse
import html
import json
import logging
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import cast

from magazine_doc_md import Cell, Doc, DocError, parse_doc, to_html
from magazine_hermes import Easy, easy_all
from magazine_slack import SLACK_BASE, Target, post_root, upload_file
from mirror_lib import MirrorError, read_token, save_state
from mirror_summary import DEFAULT_URL

HOME = Path.home()
TEMPLATE = Path(__file__).with_name("magazine_swiss_template.html")
LOG = logging.getLogger("magazine_doc")


def doc_date(doc: Doc) -> str:
    found = re.search(r"\d{4}-\d{2}-\d{2}", doc.title)
    if not found:
        raise DocError(f"제목에서 날짜(YYYY-MM-DD)를 못 찾았어요: {doc.title}")
    return found.group(0)


def read_source(repo: str, sha: str, path: str) -> tuple[str, str]:
    """(40자 sha, 원문). git 실패는 raise."""
    def git(*a: str) -> str:
        done = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True, encoding="utf-8", check=False)
        if done.returncode != 0:
            raise MirrorError(f"git {a[0]} 실패: {done.stderr.strip()[:200]}")
        return done.stdout
    full = git("rev-parse", "--verify", f"{sha}^{{commit}}").strip()
    return full, git("show", f"{full}:{path}")


def easy_block(e: Easy) -> str:
    if e.text is not None:
        return f'<p class="easy">{html.escape(e.text)}</p>'
    return f'<p class="easy fail">쉬운 요약 실패({html.escape(e.error or "사유 없음")})</p>'


def _section(n: int, cell: Cell, e: Easy) -> str:
    return (f'  <section id="{cell.key}" class="section"><div class="grid section-head"><span class="section-index">{n:02d}</span>'
            f'<h2 class="section-title">{html.escape(cell.title)}</h2></div>\n    {easy_block(e)}\n    <div class="body">{to_html(cell.body)}</div></section>')


def _team(n: int, cell: Cell, e: Easy) -> str:
    return (f'    <details class="row" id="{cell.key}"><summary><span class="no">{n:02d}</span><span class="hd">{html.escape(cell.title)}</span>'
            f'<span class="chev" aria-hidden="true">›</span></summary><div class="det">{easy_block(e)}\n      <div class="body">{to_html(cell.body)}</div></div></details>')


def render_html(doc: Doc, easy: dict[str, Easy], date: str, src: str) -> str:
    n = len(doc.cells)
    jump = "".join(f'<a href="#{c.key}">{html.escape(c.title.strip("★"))}</a>' for c in doc.cells) + ('<a href="#teams">팀별 전체</a>' if doc.teams else "")
    month, day = int(date[5:7]), int(date[8:10])
    values = {
        "TITLE": html.escape(f"매거진 {date} · 오빠 확인판"), "DATE": date, "HERO": f"{month}월 {day}일", "SRC": html.escape(src),
        "INTRO": html.escape(doc.intro.replace("\n", " ")), "JUMP": jump,
        "CELLS": "\n".join(_section(i, c, easy[c.key]) for i, c in enumerate(doc.cells, 1)),
        "TEAMS": "\n".join(_team(n + i, t, easy[t.key]) for i, t in enumerate(doc.teams, 1)),
        "TEAMS_INDEX": f"{n + 1:02d}", "TEAM_COUNT": str(len(doc.teams)),
    }
    page = TEMPLATE.read_text(encoding="utf-8")
    if not doc.teams:  # 팀 0 이면 팀 구역 제목·버튼째 그리지 않는다
        page = re.sub(r'  <section id="teams".*?</section>\n', "", page, flags=re.S)
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], page)


def root_text(date: str) -> str:
    return f"매거진 {date} · 오빠 확인판\n쉬운 말 요약과 원문 전체가 담긴 HTML 이 스레드에 붙어 있어요."


def load_state(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def publish(args: argparse.Namespace, key: str, date: str, html_path: Path) -> str:
    """상태 키 = 원본 sha:경로. root_ts 를 올린 직후 기록해 업로드만 실패한 재실행이 뿌리 글을 또 만들지 않는다."""
    state_path = Path(args.state).expanduser()
    state = load_state(state_path)
    rec = cast(dict[str, object], state.get(key) or {})
    if rec.get("uploaded"):
        return f"skip {key} root_ts={rec['root_ts']} (이미 발행됨)"
    target = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
    root_ts = str(rec.get("root_ts") or post_root(target, root_text(date)))
    state[key] = {"root_ts": root_ts, "uploaded": False}
    state_path.parent.mkdir(parents=True, exist_ok=True)
    save_state(state_path, state)
    upload_file(target, root_ts, html_path, f"매거진 {date} · 오빠 확인판", "text/html")
    state[key] = {"root_ts": root_ts, "uploaded": True}
    save_state(state_path, state)
    return f"published date={date} {key} root_ts={root_ts} html={html_path.name}"  # 08:15 점검(ft-magazine-check.sh)이 «published date=<오늘>» 줄을 찾는다


def run(args: argparse.Namespace) -> int:
    full, text = read_source(args.src_repo, args.src_sha, args.src_path)
    doc = parse_doc(text)
    date = args.date or doc_date(doc)  # --date 가 판 날짜(제목에 날짜 없는 오빠 원장) · 둘 다 없으면 doc_date 가 DocError
    out = Path(args.out_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    easy = easy_all(doc.cells + doc.teams, args.proxy_url)
    page = render_html(doc, easy, date, full[:10])
    html_path = out / f"MAGAZINE-DOC-{date}-{full[:10]}.html"
    html_path.write_text(page, encoding="utf-8")
    failed = sum(1 for e in easy.values() if e.error)
    print(f"{'DRY-RUN' if args.dry_run else 'PUBLISH'} calls={len(easy)} elapsed={time.monotonic() - start:.1f}s failed={failed} html={html_path}")
    if args.dry_run:
        print(f"--- 슬랙 뿌리 글 ---\n{root_text(date)}")
        return 0
    print(publish(args, f"{full}:{args.src_path}", date, html_path))
    return 0


def _iso_date(text: str) -> str:
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        raise argparse.ArgumentTypeError(f"YYYY-MM-DD 가 아니에요: {text}")
    return text


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--src-repo", required=True)
    p.add_argument("--src-sha", required=True)
    p.add_argument("--src-path", required=True)
    p.add_argument("--date", type=_iso_date, help="판 날짜 YYYY-MM-DD — 없으면 문서 제목에서 찾는다(둘 다 없으면 오류)")
    p.add_argument("--out-dir", default=str(HOME / ".hermes/magazine"))
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="HTML 만 — 게시·상태 쓰기 0")
    mode.add_argument("--publish", action="store_true", help="뿌리 글 1개 + 스레드에 HTML 1개")
    p.add_argument("--proxy-url", default=DEFAULT_URL, help="쉬운 문단 호출 — cliproxy Messages 주소(Haiku)")
    p.add_argument("--state", default=str(HOME / ".hermes/state/magazine-doc.json"))
    p.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    p.add_argument("--slack-base", default=SLACK_BASE)
    p.add_argument("--channel", default="C0C6MJGRR89")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    try:
        return run(parse_args(argv))
    except (MirrorError, DocError) as e:
        LOG.error("발행 실패: %s: %s", type(e).__name__, e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
