#!/usr/bin/env python3
"""byz_proposal_publish — 제안서 md 를 슬랙 기존 채널에 발행한다 (제안서 흐름 2단계 끝 · 설계 §3).

뿌리 글 = 첫 줄 `*제안서 <팀>/<slug>*` + 제안서 칸 3줄(결론·오빠가 결정할 것·되돌림 — 요약 LLM 0) → 스레드에 md + 쉬운 판 HTML 첨부(판정 357).
`--revision rN` = 같은 스레드 답글(첫 줄 `*제안서 <팀>/<slug> rN*`) + 새 첨부. 한 제안서 = 슬랙 스레드 1개.
상태 파일 {<팀>/<slug>: {root_ts, revs: {r0, r1…: {phase, at, ts, md_hash, html, files}}}} 의 phase: posting(게시 «전» 기록) → posted(글 ts 받자마자) → done(첨부 완료).
원문은 «한 번만» 읽는다(칸·해시·HTML·첨부가 같은 바이트). 같은 rN 에 다른 원문이 오면 raise — 세부는 proposal_files.py.
글을 쓰기 «전» 항상 원격에서 «정확한 첫 줄» 을 찾는다 — 있으면 그 ts 채택(응답 유실·상태 쓰기 실패·상태 분실 복구).
posting 인데 원격 표식이 없으면 자동 재게시 0 → exit 1 (사람이 채널을 보고 --force-post). 슬랙 실패는 전부 raise(#0 RULE).
--dry-run = 글 텍스트를 stdout 에만 낸다(토큰·게시·상태 0).
"""
import argparse
import logging
import os
import re
import sys
import tempfile
import time
from pathlib import Path

import proposal_eli5
import resume_block as rb
import thread_ledger as lg
import thread_unit as tu
from magazine_attach import AttachError
from magazine_slack import SLACK_BASE, Target, eli5_warning_line, find_first_line
from mirror_lib import MirrorError, esc, paged, post, read_token
from mirror_summary import DEFAULT_CMD
from proposal_files import attach_all, check_pinned, make_html, md_hash
from proposal_state import PublishError, read_state, set_phase

LOG = logging.getLogger("byz_proposal_publish")
HOME = Path.home()
MAX_LINES = 120
STATUS_OK = re.compile(r"^(초안|컨펌 대기|수정 요청 r[1-9]\d*)$")
NAME = re.compile(r"^PROPOSAL-([a-z0-9-]+)-\d{8}\.md$")


def _section_first(lines: list[str], head: str) -> str:
    """`## head` 절의 첫 비어 있지 않은 줄 — 없으면 raise(칸 누락)."""
    try:
        i = next(n for n, ln in enumerate(lines) if ln.strip() == f"## {head}")
    except StopIteration:
        raise PublishError(f"제안서에 「## {head}」 칸이 없다") from None
    for ln in lines[i + 1:]:
        if ln.startswith("## "):
            break
        if ln.strip():
            return ln.strip()
    raise PublishError(f"제안서 「## {head}」 칸이 비어 있다")


def parse(path: Path) -> dict[str, str]:
    return parse_text(path, path.read_text(encoding="utf-8"))


def parse_text(path: Path, text: str) -> dict[str, str]:
    """이미 읽은 원문(text)을 파싱한다 — publish 는 파일을 «한 번만» 읽고 이 함수로 칸을 뽑는다(DA R2 ⑤)."""
    m = NAME.match(path.name)
    if not m:
        raise PublishError(f"파일 이름이 PROPOSAL-<slug>-YYYYMMDD.md 가 아니다: {path.name}")
    lines = text.splitlines()
    if len(lines) > MAX_LINES:
        raise PublishError(f"제안서가 {len(lines)}줄 > {MAX_LINES}줄 — 부록 파일로 나눈다")
    head = lines[: next((n for n, ln in enumerate(lines) if ln.startswith("## ")), len(lines))]
    statuses = [ln[len("- 상태:"):].strip() for ln in head if ln.startswith("- 상태:")]
    if len(statuses) > 1:
        raise PublishError(f"머리의 「- 상태:」 줄이 {len(statuses)}개 — 정확히 1개여야 한다(첫 줄만 믿지 않는다): {statuses}")
    status = statuses[0] if statuses else ""
    if not STATUS_OK.match(status):
        raise PublishError(f"머리줄 상태 「{status or '없음'}」 은 발행 대상이 아니다(초안|컨펌 대기|수정 요청 rN)")
    return {"key": f"{path.resolve().parent.name}/{m.group(1)}", "status": status,
            "결론": _section_first(lines, "결론"), "오빠가 결정할 것": _section_first(lines, "오빠가 결정할 것"),
            "되돌림": _section_first(lines, "되돌림")}


def first_line(key: str, rev: str) -> str:
    return f"*제안서 {key}*" if rev == "r0" else f"*제안서 {key} {rev}*"


def text_of(p: dict[str, str], rev: str, warn: str | None = None, block: str | None = None) -> str:
    lines = [first_line(p["key"], rev)] + [f"{k}: {esc(p[k])}" for k in ("결론", "오빠가 결정할 것", "되돌림")]
    return "\n".join(lines + ([esc(eli5_warning_line(warn))] if warn else []) + ([block] if block else []))


def find_reply(t: Target, root_ts: str, line: str) -> str | None:
    """스레드 답글 중 봇이 쓴 첫 줄 «정확 일치» 글의 ts — 뿌리 글 자신과 다른 rN 답글은 채택하지 않는다."""
    msgs = paged(t.base, t.token, "conversations.replies", {"channel": t.channel, "ts": root_ts, "limit": 200})
    hits = [str(m["ts"]) for m in msgs if m.get("bot_id") and str(m["ts"]) != root_ts and str(m.get("text", "")).split("\n", 1)[0] == line]
    return min(hits, default=None)


def _root_ts(t: Target, key: str, st_path: Path, lookback: float) -> str:
    rec = read_state(st_path).get(key, {})
    if rec.get("root_ts"):
        return str(rec["root_ts"])
    found = find_first_line(t, first_line(key, "r0"), time.time() - lookback * 86400)
    if not found:
        raise PublishError(f"뿌리 글 없음: {key} — 먼저 r0(--revision 없이) 발행")
    return found


def publish(t: Target, md: Path, rev: str, st_path: Path, *, force_post: bool = False, force_file: str = "", lookback: float = 60.0,
            cmd: str = DEFAULT_CMD, cache_dir: Path = HOME / ".hermes/state/proposal", build=proposal_eli5.build,
            block: str | None = None) -> dict[str, str]:
    data = md.read_bytes()  # ★한 번 읽기★ — 칸·해시·HTML·첨부가 전부 이 바이트에서 나온다(읽은 뒤 파일이 바뀌어도 어긋나지 않는다)
    text = data.decode("utf-8")
    p, h = parse_text(md, text), md_hash(data)
    key, line = p["key"], first_line(p["key"], rev)
    rec = read_state(st_path).get(key, {}).get("revs", {}).get(rev, {})
    check_pinned(key, rev, rec, h)  # 캐시·키 판단 «전» — 같은 rN 의 원문 불변 확인
    phase = rec.get("phase", "")
    if phase == "done":
        return {"action": "skip", "ts": rec.get("ts", "")}
    html, info = make_html(key, rev, h, text, rec, cmd, cache_dir, build)
    base = {"md_hash": h, "html": info}
    root = _root_ts(t, key, st_path, lookback) if rev != "r0" else ""
    if phase == "posted" and rec.get("ts"):
        ts = rec["ts"]
    else:
        found = find_reply(t, root, line) if rev != "r0" else find_first_line(t, line, time.time() - lookback * 86400)
        if found:
            LOG.info("%s %s 원격 표식 채택 ts=%s (재게시 0)", key, rev, found)
            ts = found
        elif phase == "posting" and not force_post:
            raise PublishError(f"불명: {key} {rev} 글 확인 필요 — 앞 실행이 게시를 시도했는데 채널에 표식이 없음. 채널 확인 뒤 --force-post")
        else:
            set_phase(st_path, key, rev, "posting", **base)
            warn = (info.get("reason") or "원인 불명") if info["phase"] == "omitted" else None
            ts = post(t.base, t.token, t.channel, text_of(p, rev, warn, block), root or None)
        set_phase(st_path, key, rev, "posted", ts=ts, **base)
    with tempfile.TemporaryDirectory() as td:  # 같은 읽기 스냅샷의 md 를 올린다(HTML 도 같은 바이트에서 만들어졌다)
        snap = Path(td) / md.name
        snap.write_bytes(data)
        attach_all(t, root or ts, key, rev, h, [("md", snap), ("html", html)], st_path, base, force_file)
    set_phase(st_path, key, rev, "done", ts=ts, **base)
    return {"action": "published", "ts": ts}


def parse_args(argv: list[str]) -> argparse.Namespace:
    a = argparse.ArgumentParser(description="제안서 슬랙 발행")
    a.add_argument("proposal", help="design/<팀>/PROPOSAL-<slug>-YYYYMMDD.md")
    a.add_argument("--revision", help="rN(N>=1) — 같은 스레드 답글 + 새 첨부")
    a.add_argument("--dry-run", action="store_true", help="글 텍스트만 stdout — 토큰·게시·상태 0")
    a.add_argument("--force-post", action="store_true", help="posting+표식 없음(불명)을 사람이 채널에서 확인한 뒤 재게시")
    a.add_argument("--force-file", choices=("md", "html"), help="sharing+표식 없음(불명) 첨부를 사람이 채널에서 확인한 뒤 새로 올림")
    a.add_argument("--summary-cmd", default=DEFAULT_CMD, help="쉬운 판(eli5) 풀이용 LLM 명령")
    a.add_argument("--cache-dir", default=str(HOME / ".hermes/state/proposal"), help="쉬운 판 HTML 캐시(이름에 원문 hash)")
    a.add_argument("--state", default=str(HOME / ".hermes/state/byz_proposal_publish.json"))
    a.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    a.add_argument("--slack-base", default=SLACK_BASE)
    a.add_argument("--channel", default=os.environ.get("PROPOSAL_CHANNEL", "C0C6MJGRR89"))
    a.add_argument("--card", required=True, help="이 제안서의 카드(인덱스) 파일 — 스레드 장부 키·카드 `- 슬랙:` 줄의 근거")
    a.add_argument("--team", help="카드 경로에 design/<팀>/ 이 없을 때")
    a.add_argument("--ledger", default=str(lg.DEFAULT))
    a.add_argument("--issue", default=rb.NONE, help="이어가기 블록 Issue 칸 (없으면 없음)")
    a.add_argument("--seat", required=True, help="담당 좌석(재개 칸의 근거)")
    a.add_argument("--next", dest="next_", default="", help="다음 칸 (기본 = 제안서의 「오빠가 결정할 것」)")
    a.add_argument("--resume-script", required=True, help="ft-resume-cmd.sh 경로")
    a.add_argument("--lookback-days", type=float, default=60.0, help="원격 표식을 찾을 채널 history 창")
    return a.parse_args(argv)


def block_of(args: argparse.Namespace, md: Path) -> str:
    p = parse(md)
    return rb.block(args.issue, args.card, args.seat, rb.canon_ref(md), args.next_ or f"오빠 결정 — {p['오빠가 결정할 것']}",
                    rb.resume_for(args.seat, args.resume_script))


def run(args: argparse.Namespace) -> int:
    rev = args.revision or "r0"
    if rev != "r0" and not re.fullmatch(r"r[1-9]\d*", rev):
        print(f"ERROR --revision 은 rN(N>=1): {rev}", file=sys.stderr)
        return 1
    try:
        md = Path(args.proposal)
        if args.dry_run:
            print(text_of(parse(md), rev, block=block_of(args, md)))
            return 0
        block, card, ledger = block_of(args, md), Path(args.card), Path(args.ledger).expanduser()
        lg.load(ledger)  # 장부가 없거나 손상이면 게시 «전» 에 raise
        tu.note_attempt(card, args.channel)  # 게시 의도는 tracked 카드에 먼저 남긴다
        t = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
        res = publish(t, md, rev, Path(args.state).expanduser(), force_post=args.force_post, force_file=args.force_file or "",
                      lookback=args.lookback_days, cmd=args.summary_cmd, cache_dir=Path(args.cache_dir).expanduser(), block=block)
        tu.ensure_root(card, args.team, ledger, args.channel, read_state(Path(args.state).expanduser())[parse(md)["key"]]["root_ts"])
    except (PublishError, AttachError, MirrorError, OSError, ValueError) as e:
        print(f"ERROR {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    print(f"{res['action']} {parse(md)['key']} {rev} ts={res['ts']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(levelname)s %(message)s")
    return run(parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    sys.exit(main())
