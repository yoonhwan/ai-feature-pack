#!/usr/bin/env python3
"""magazine_doc — 오빠 원장(planner 정리 md) 한 장을 «아침 매거진 한 쪽» HTML 로 바꿔 Slack 매거진 채널에 1회 발행 (R117 · 판정 1424 · R259 판정 1988).

칸 구성 = design/harness/GUIDE-magazine-20261016.md §1(magazine_brief · magazine_brief_html) — ①끝낸 일 축하(r867 · magazine_celebrate · 창 안 완성만 · 쉬운 풀이 = 외부 호출 7초 룰) ②남은 일 풀 설명 · 발행 전 지침 검사(magazine_guide_check) + 상대 날짜 가드(R202).
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
from magazine_brief_html import REMAINING, render
from magazine_celebrate import fill as fill_done
from magazine_date_guard import check as date_guard
from magazine_doc_md import Doc, DocError, parse_doc
from magazine_guide_check import check as guide_check
from magazine_slack import SLACK_BASE, Target, permalink, post_root, upload_file
from magazine_summary import PROXY_URL
from magazine_window import MagazineError
from mirror_lib import MirrorError, read_token, save_state
from root_readback_guard import Post, readback

try:
    from magazine_goal import block as goal_block, html_section, procs_block, teams_block
except ImportError as _err:  # R362 H1 — 설치 누락: 무장 표식(FT_ROOT/.fable-team/state/goal-gate.armed)이 있으면 발행 거절 · 없으면 골 표 없이 진행(로그)
    _why = str(_err)  # except 블록이 끝나면 _err 이름이 지워진다 — 아래 함수가 쓸 값은 여기서 잡는다

    def goal_block() -> str:
        if Path(os.environ.get("FT_ROOT", "/nonexistent"), ".fable-team/state/goal-gate.armed").is_file():
            subprocess.run(["bash", str(Path(os.environ["FT_ROOT"], ".fable-team/bin/ft-goal-table.sh")), "notify", os.environ["FT_ROOT"], "magazine", f"magazine_goal 설치 누락({_why})"], capture_output=True, check=False, timeout=21)
            raise MirrorError(f"골 표 모듈 없음 — magazine_goal 설치 누락({_why})")
        logging.getLogger("magazine_doc").warning("골 표 모듈 없음(비무장) — 골 표 없이 진행: %s", _why)
        return ""
    html_section, teams_block, procs_block = (lambda goal: ""), (lambda: ""), (lambda: "")

HOME = Path.home()
LOG = logging.getLogger("magazine_doc")
ROOT_POINTER = "윗부분은 끝낸 일 축하, 아랫부분은 남은 일 풀 설명 — 한 쪽짜리 HTML 이 스레드에 붙어 있어요."
TABLE_LINE = "결론은 HTML 첫 절에 있어요(표 꼴이라 슬랙엔 싣지 않음)"  # r894 F1 — 표 꼴 결론은 뿌리 글에 싣지 않는다(숨김 0 · WARN 1줄)


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


def table_ish(text: str) -> bool:
    """표 꼴인가 — `|---|` 또는 `|` 2개 이상(r894 F1 · 슬랙은 표를 못 그린다)."""
    return "|---|" in text or text.count("|") >= 2


def conclusion_line(conclusion: str) -> str:
    """뿌리 글 2번째 줄 = 원장 결론 한 줄(굵게 표시 걷음). 표 꼴이면 싣지 않고 HTML 안내 1줄 + WARN(HTML 쪽 결론은 그대로)."""
    line = " ".join(conclusion.replace("**", "").split())
    if line and table_ish(line):
        LOG.warning("뿌리 글 결론 줄 생략 — 표 꼴(슬랙은 표를 못 그린다) · HTML 첫 절에 그대로: %s", line[:80])
        return TABLE_LINE
    return line


def root_text(date: str, conclusion: str = "") -> str:
    """슬랙 뿌리 글 = 첫 줄 + 원장 결론 한 줄 + HTML 안내 — 최대 3줄(r894 · 슬랙은 표를 못 그린다). 골 표·팀 표·절차 블록은 HTML 에만.
    첫 줄은 그대로(뿌리 글 «첫 줄 정확 일치» 탐색) · 결론이 표 꼴이면 conclusion_line 이 안내 줄로 바꾼다(F1)."""
    lines = (f"매거진 {date} · 오빠 확인판", conclusion_line(conclusion), ROOT_POINTER)
    return "\n".join(x for x in lines if x)


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


def publish(args: argparse.Namespace, key: str, date: str, html_path: Path, conclusion: str = "") -> tuple[str, str]:
    """(출력 줄, 뿌리 글 ts). 상태 키 = 원본 sha:경로. root_ts 를 올린 직후 기록해 업로드만 실패한 재실행이 뿌리 글을 또 만들지 않는다."""
    state_path = Path(args.state).expanduser()
    state = load_state(state_path)
    rec = cast(dict[str, object], state.get(key) or {})
    if rec.get("uploaded"):
        return f"skip {key} root_ts={rec['root_ts']} (이미 발행됨)", str(rec["root_ts"])
    target = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
    root_ts = str(rec.get("root_ts") or post_root(target, root_text(date, conclusion)))
    if not rec.get("root_ts"):  # 방금 올린 뿌리 글만 되읽기(이미 검사한 재샐행 글은 다시 안 본다)
        readback(Post(target.base, target.token, target.channel, root_ts, f"magazine:{date}"))  # r1004 — 위반이면 지우고 raise → 상태 기록 0(다음 새샐행이 새 글)
    state[key] = {"root_ts": root_ts, "uploaded": False, "date": date}
    state_path.parent.mkdir(parents=True, exist_ok=True)
    save_state(state_path, state)
    upload_file(target, root_ts, html_path, f"매거진 {date} · 오빠 확인판", "text/html")
    state[key] = {"root_ts": root_ts, "uploaded": True, "date": date, "at": os.environ.get("FT_NEWS_NOW") or time.strftime("%Y-%m-%d %H:%M")}  # r851 C1 — 원장 닫힌 줄 내림의 «발행 성공» 시각
    save_state(state_path, state)
    return f"published date={date} {key} root_ts={root_ts} html={html_path.name}", root_ts  # 08:15 점검(ft-magazine-check.sh)이 «published date=<오늘>» 줄을 찾는다


def run(args: argparse.Namespace) -> int:
    full, text = read_source(args.src_repo, args.src_sha, args.src_path)
    doc = parse_doc(text)
    date = args.date or doc_date(doc)  # --date 가 판 날짜(제목에 날짜 없는 오빠 원장) · 둘 다 없으면 doc_date 가 DocError
    prev, note = load_previous(load_state(Path(args.state).expanduser()), args.src_repo, args.src_path, full, read_source)
    brief = build_brief(doc, date, full[:10], prev, note)
    fill_done(brief, args.src_repo, args.done_ref, args.eli5_cmd)  # r867 ① 축하 칸(인덱스 카드만 · r4) — 지침·날짜 가드 «전»에 채워 같은 검사를 받는다
    blocked = date_guard(brief.as_doc(), args.publish)  # 상대 날짜(오늘·내일…)가 판에 실리면 발행 0 — 게시 전에 거절(R202)
    flagged = guide_check(brief, args.publish)  # 지침 §3·§4-1 위반 — 같은 규칙(R259)
    if blocked or (flagged and args.publish):
        return 1
    goal = "\n".join(x for x in (goal_block(), teams_block(), procs_block()) if x)  # R458 팀별 완성 진행 · r644 표준절차 골 = 골 표 바로 뒤(HTML 만 · r894 뿌리 글엔 0) · R362 — 게시·상태 쓰기 «전»: 무장이면 렌더·판정 실패 = 발행 실패 경로(rc1) · 비무장이면 WOULD-REJECT 로그 + 골 표 없이
    out = Path(args.out_dir).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    html_path = out / f"MAGAZINE-DOC-{date}-{full[:10]}.html"
    html_path.write_text(render(brief).replace(REMAINING, html_section(goal) if goal else "", 1), encoding="utf-8")  # 골 표 = ② 남은 일 머리 바로 뒤
    root_warn = 1 if table_ish(" ".join(brief.conclusion.split())) else 0  # r894 F1 — 표 꼴 결론을 뿌리 글에서 뺀 사실은 결과 줄 warn 에도 센다(숨김 0 · 게시 거절은 아니다)
    print(f"{'DRY-RUN' if args.dry_run else 'PUBLISH'} warn={flagged + root_warn} elapsed={time.monotonic() - start:.1f}s html={html_path}")
    if args.dry_run:
        print(f"--- 슬랙 뿌리 글 ---\n{root_text(date, brief.conclusion)}\nSLACK 링크 없음(드라이런)")
        return 0
    line, root_ts = publish(args, f"{full}:{args.src_path}", date, html_path, brief.conclusion)
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
    p.add_argument("--done-ref", default="HEAD", help="축하 칸 git 이력 기준(원장 사본의 origin/main 동기 HEAD)")
    p.add_argument("--eli5-cmd", default=PROXY_URL, help="쉬운 풀이 호출 — http(s):// 면 프록시 Messages 직접, 아니면 stdin→stdout 명령")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    try:
        return run(parse_args(argv))
    except (MirrorError, DocError, MagazineError) as e:  # MagazineError = 축하 칸 git 실패(r867 · 반쪽 축하 0)
        LOG.error("발행 실패: %s: %s", type(e).__name__, e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
