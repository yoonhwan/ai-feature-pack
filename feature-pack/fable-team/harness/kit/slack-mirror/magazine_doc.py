#!/usr/bin/env python3
"""magazine_doc — 오빠 원장(planner 정리 md) 한 장을 «아침 매거진 한 쪽» HTML 로 바꿔 Slack 매거진 채널에 1회 발행 (R117 · 판정 1424 · R259 판정 1988).

칸 구성 = design/harness/GUIDE-magazine-20261016.md §1(magazine_brief · magazine_brief_html) · 외부 호출 0(쉬운 말 문단 없음) · 발행 전 지침 검사(magazine_guide_check) + 상대 날짜 가드(R202).
--dry-run = HTML 만 만들고 게시·상태 쓰기 0(위반은 WARN) · --publish = 위반 1건이라도 있으면 발행 0·rc 1 · 아니면 뿌리 글 1개 + 스레드에 HTML 1개(같은 원본 sha 면 skip).
"""
import argparse
import json
import logging
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import cast

from magazine_brief import build_brief
from magazine_brief_diff import load_previous
from magazine_brief_html import render
from magazine_date_guard import check as date_guard
from magazine_doc_md import Doc, DocError, parse_doc
from magazine_guide_check import check as guide_check
from magazine_slack import SLACK_BASE, Target, permalink, post_root, upload_file
from mirror_lib import MirrorError, read_token, save_state

try:
    from magazine_goal import block as goal_block, html_section, teams_block, with_root
except ImportError as _err:  # R362 H1 — 설치 누락: 무장 표식(FT_ROOT/.fable-team/state/goal-gate.armed)이 있으면 발행 거절 · 없으면 골 표 없이 진행(로그)
    _why = str(_err)  # except 블록이 끝나면 _err 이름이 지워진다 — 아래 함수가 쓸 값은 여기서 잡는다

    def goal_block() -> str:
        if Path(os.environ.get("FT_ROOT", "/nonexistent"), ".fable-team/state/goal-gate.armed").is_file():
            subprocess.run(["bash", str(Path(os.environ["FT_ROOT"], ".fable-team/bin/ft-goal-table.sh")), "notify", os.environ["FT_ROOT"], "magazine", f"magazine_goal 설치 누락({_why})"], capture_output=True, check=False, timeout=21)
            raise MirrorError(f"골 표 모듈 없음 — magazine_goal 설치 누락({_why})")
        logging.getLogger("magazine_doc").warning("골 표 모듈 없음(비무장) — 골 표 없이 진행: %s", _why)
        return ""
    html_section, with_root, teams_block = (lambda goal: ""), (lambda text, goal: text), (lambda: "")

HOME = Path.home()
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


def root_text(date: str, goal: str = "") -> str:
    """goal = 자율 골 표 블록(R362) — 첫 줄 바로 뒤. 첫 줄은 그대로(뿌리 글 «첫 줄 정확 일치» 탐색)."""
    return with_root(f"매거진 {date} · 오빠 확인판\n오빠 할 일과 지난 판 뒤로 바뀐 것을 한 쪽에 모은 HTML 이 스레드에 붙어 있어요.", goal)


def load_state(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def link_line(args: argparse.Namespace, root_ts: str) -> str:
    """발행 결과의 슬랙 주소 1줄 — 실패는 사유를 줄에 적는다(발행 성공은 그대로 · 조용한 생략 0)."""
    try:
        target = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
        return f"SLACK {permalink(target, root_ts)}"
    except (MirrorError, KeyError) as e:
        LOG.warning("슬랙 링크 못 만듦: %s: %s", type(e).__name__, e)
        return f"SLACK 링크 못 만듦 — {type(e).__name__}: {e}"


def publish(args: argparse.Namespace, key: str, date: str, html_path: Path, goal: str = "") -> tuple[str, str]:
    """(출력 줄, 뿌리 글 ts). 상태 키 = 원본 sha:경로. root_ts 를 올린 직후 기록해 업로드만 실패한 재실행이 뿌리 글을 또 만들지 않는다."""
    state_path = Path(args.state).expanduser()
    state = load_state(state_path)
    rec = cast(dict[str, object], state.get(key) or {})
    if rec.get("uploaded"):
        return f"skip {key} root_ts={rec['root_ts']} (이미 발행됨)", str(rec["root_ts"])
    target = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
    root_ts = str(rec.get("root_ts") or post_root(target, root_text(date, goal)))
    state[key] = {"root_ts": root_ts, "uploaded": False, "date": date}
    state_path.parent.mkdir(parents=True, exist_ok=True)
    save_state(state_path, state)
    upload_file(target, root_ts, html_path, f"매거진 {date} · 오빠 확인판", "text/html")
    state[key] = {"root_ts": root_ts, "uploaded": True, "date": date}
    save_state(state_path, state)
    return f"published date={date} {key} root_ts={root_ts} html={html_path.name}", root_ts  # 08:15 점검(ft-magazine-check.sh)이 «published date=<오늘>» 줄을 찾는다


def run(args: argparse.Namespace) -> int:
    full, text = read_source(args.src_repo, args.src_sha, args.src_path)
    doc = parse_doc(text)
    date = args.date or doc_date(doc)  # --date 가 판 날짜(제목에 날짜 없는 오빠 원장) · 둘 다 없으면 doc_date 가 DocError
    prev, note = load_previous(load_state(Path(args.state).expanduser()), args.src_repo, args.src_path, full, read_source)
    brief = build_brief(doc, date, full[:10], prev, note)
    blocked = date_guard(brief.as_doc(), args.publish)  # 상대 날짜(오늘·내일…)가 판에 실리면 발행 0 — 게시 전에 거절(R202)
    flagged = guide_check(brief, args.publish)  # 지침 §3·§4-1 위반 — 같은 규칙(R259)
    if blocked or (flagged and args.publish):
        return 1
    goal = "\n".join(x for x in (goal_block(), teams_block()) if x)  # R458 팀별 완성 진행 = 골 표 바로 뒤(뿌리 글·HTML 같은 절) · R362 — 게시·상태 쓰기 «전»: 무장이면 렌더·판정 실패 = 발행 실패 경로(rc1) · 비무장이면 WOULD-REJECT 로그 + 골 표 없이
    out = Path(args.out_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    html_path = out / f"MAGAZINE-DOC-{date}-{full[:10]}.html"
    html_path.write_text(render(brief).replace("</h1>", "</h1>\n" + html_section(goal), 1) if goal else render(brief), encoding="utf-8")
    print(f"{'DRY-RUN' if args.dry_run else 'PUBLISH'} warn={flagged} elapsed={time.monotonic() - start:.1f}s html={html_path}")
    if args.dry_run:
        print(f"--- 슬랙 뿌리 글 ---\n{root_text(date, goal)}\nSLACK 링크 없음(드라이런)")
        return 0
    line, root_ts = publish(args, f"{full}:{args.src_path}", date, html_path, goal)
    print(line)
    print(link_line(args, root_ts))
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
