#!/usr/bin/env python3
"""byz_proposal_publish — 제안서 md 를 슬랙 기존 채널에 발행한다 (제안서 흐름 2단계 끝 · 설계 §3).

뿌리 글 = 첫 줄 `*제안서 <팀>/<slug>*` + 제안서 칸 3줄(결론·오빠가 결정할 것·되돌림 — 요약 LLM 0) → 스레드에 md 첨부.
`--revision rN` = 같은 스레드 답글(첫 줄 `*제안서 <팀>/<slug> rN*`) + 새 md 첨부. 한 제안서 = 슬랙 스레드 1개.
상태 파일 {<팀>/<slug>: {root_ts, revs: {r0, r1…: {phase, at, ts}}}} 의 phase: posting(게시 «전» 기록) → posted(글 ts 받자마자) → done(첨부 완료).
글을 쓰기 «전» 항상 원격에서 «정확한 첫 줄» 을 찾는다 — 있으면 그 ts 채택(응답 유실·상태 쓰기 실패·상태 분실 복구).
posting 인데 원격 표식이 없으면 자동 재게시 0 → exit 1 (사람이 채널을 보고 --force-post). 슬랙 실패는 전부 raise(#0 RULE).
--dry-run = 글 텍스트를 stdout 에만 낸다(토큰·게시·상태 0).
"""
import argparse
import json
import logging
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from magazine_slack import SLACK_BASE, Target, find_first_line, upload_file
from mirror_lib import MirrorError, esc, paged, post, read_token, save_state

LOG = logging.getLogger("byz_proposal_publish")
HOME = Path.home()
KST = ZoneInfo("Asia/Seoul")
MAX_LINES = 120
STATUS_OK = re.compile(r"^(초안|컨펌 대기|수정 요청 r[1-9]\d*)$")
NAME = re.compile(r"^PROPOSAL-([a-z0-9-]+)-\d{8}\.md$")


class PublishError(RuntimeError):
    pass


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
    m = NAME.match(path.name)
    if not m:
        raise PublishError(f"파일 이름이 PROPOSAL-<slug>-YYYYMMDD.md 가 아니다: {path.name}")
    lines = path.read_text(encoding="utf-8").splitlines()
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


def text_of(p: dict[str, str], rev: str) -> str:
    return "\n".join([first_line(p["key"], rev)] + [f"{k}: {esc(p[k])}" for k in ("결론", "오빠가 결정할 것", "되돌림")])


def read_state(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise PublishError(f"상태 파일 읽기 실패: {path} ({type(e).__name__})") from e
    if not isinstance(data, dict):
        raise PublishError(f"상태 파일 형식 오류: {path}")
    return data


def set_phase(path: Path, key: str, rev: str, phase: str, **fields: str) -> None:
    try:
        st = read_state(path)
        rec = st.setdefault(key, {"revs": {}})
        rec.setdefault("revs", {})[rev] = {"phase": phase, "at": datetime.now(KST).isoformat(timespec="seconds"), **fields}
        if rev == "r0" and fields.get("ts"):
            rec["root_ts"] = fields["ts"]
        save_state(path, st)  # type: ignore[arg-type]
    except OSError as e:
        raise PublishError(f"상태 쓰기 실패({phase}): {path} ({type(e).__name__})") from e


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


def publish(t: Target, p: dict[str, str], md: Path, rev: str, st_path: Path, *, force_post: bool = False, lookback: float = 60.0) -> dict[str, str]:
    key, line = p["key"], first_line(p["key"], rev)
    rec = read_state(st_path).get(key, {}).get("revs", {}).get(rev, {})
    phase = rec.get("phase", "")
    if phase == "done":
        return {"action": "skip", "ts": rec.get("ts", "")}
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
            set_phase(st_path, key, rev, "posting")
            ts = post(t.base, t.token, t.channel, text_of(p, rev), root or None)
        set_phase(st_path, key, rev, "posted", ts=ts)
    upload_file(t, root or ts, md, f"제안서 {key} {rev} ({p['status']})", "text/markdown")
    set_phase(st_path, key, rev, "done", ts=ts)
    return {"action": "published", "ts": ts}


def parse_args(argv: list[str]) -> argparse.Namespace:
    a = argparse.ArgumentParser(description="제안서 슬랙 발행")
    a.add_argument("proposal", help="design/<팀>/PROPOSAL-<slug>-YYYYMMDD.md")
    a.add_argument("--revision", help="rN(N>=1) — 같은 스레드 답글 + 새 첨부")
    a.add_argument("--dry-run", action="store_true", help="글 텍스트만 stdout — 토큰·게시·상태 0")
    a.add_argument("--force-post", action="store_true", help="posting+표식 없음(불명)을 사람이 채널에서 확인한 뒤 재게시")
    a.add_argument("--state", default=str(HOME / ".hermes/state/byz_proposal_publish.json"))
    a.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    a.add_argument("--slack-base", default=SLACK_BASE)
    a.add_argument("--channel", default=os.environ.get("PROPOSAL_CHANNEL", "C0C6MJGRR89"))
    a.add_argument("--lookback-days", type=float, default=60.0, help="원격 표식을 찾을 채널 history 창")
    return a.parse_args(argv)


def run(args: argparse.Namespace) -> int:
    rev = args.revision or "r0"
    if rev != "r0" and not re.fullmatch(r"r[1-9]\d*", rev):
        print(f"ERROR --revision 은 rN(N>=1): {rev}", file=sys.stderr)
        return 1
    try:
        md = Path(args.proposal)
        p = parse(md)
        if args.dry_run:
            print(text_of(p, rev))
            return 0
        t = Target(args.slack_base, read_token(Path(args.token_file).expanduser()), args.channel, "")
        res = publish(t, p, md, rev, Path(args.state).expanduser(), force_post=args.force_post, lookback=args.lookback_days)
    except (PublishError, MirrorError, OSError) as e:
        print(f"ERROR {type(e).__name__}: {e}", file=sys.stderr)
        return 1
    print(f"{res['action']} {p['key']} {rev} ts={res['ts']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(levelname)s %(message)s")
    return run(parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    sys.exit(main())
