#!/usr/bin/env python3
"""byz_thread_post — 슬랙 «단위» 글의 단일 입구 (판정 404 · 설계 §3). start | progress | result | check | repair | --init.

한 단위 = 한 스레드: start 가 뿌리 글 1개(첨부는 그 스레드 답글) · progress/result 는 같은 스레드 답글. 모든 글 꼬리에 이어가기 블록 2줄.
게시 «전» 카드에 `- 슬랙: <ch> · 시도 <ISO>` 를 쓰고 성공하면 `- 슬랙: <ch> <root_ts>` + 장부 기록(카드 줄이 «게시 대상» 표식).
슬랙 실패·장부 손상·블록 칸 누락은 전부 raise → exit 1 (#0 RULE). kind=report 는 이 도구로 지정할 수 없다(매거진 발행기만).
"""
import argparse
import logging
import mimetypes
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import resume_block as rb
import thread_ledger as lg
from magazine_slack import Target, find_reply_first_line, upload_file
from mirror_lib import MirrorError, esc, paged, post
from thread_card import CardError, read_line, unit_id, verdict_title, write_line
from thread_post_args import parse

KST = ZoneInfo("Asia/Seoul")
LOOKBACK_DAYS = 60


class ThreadError(MirrorError):
    pass


def token_of(path: Path, name: str) -> str:
    """`NAME=값` 줄의 값 — 값은 어디에도 출력하지 않는다(오류 문구에는 이름만)."""
    try:
        for ln in path.read_text(encoding="utf-8").splitlines():
            if ln.startswith(f"{name}=") and ln.split("=", 1)[1].strip():
                return ln.split("=", 1)[1].strip().strip("'\"")
    except OSError as e:
        raise ThreadError(f"토큰 파일 읽기 실패: {path} ({type(e).__name__})") from e
    raise ThreadError(f"토큰 파일에 {name} 없음: {path}")


def target(a: argparse.Namespace) -> Target:
    hermes = getattr(a, "bot", "yoonhwan") == "hermes"
    tok = token_of(Path(a.hermes_env if hermes else a.token_file).expanduser(), "SLACK_BOT_TOKEN" if hermes else "YOONHWAN_BOT_TOKEN")
    return Target(a.slack_base, tok, a.channel, "")


def block_of(a: argparse.Namespace) -> str:
    canon = a.canon if a.canon == rb.NONE else rb.canon_ref(a.canon)
    return rb.block(a.issue, a.card or rb.NONE, a.seat, canon, a.next, rb.resume_for(a.seat, a.resume_script))


def marker(uid: str) -> str:
    return f"[{esc(uid)}]"


def attach(t: Target, root_ts: str, files: list[str]) -> None:
    for f in files:
        p = Path(f)
        upload_file(t, root_ts, p, p.name, mimetypes.guess_type(p.name)[0] or "application/octet-stream")


def record(a: argparse.Namespace, uid: str) -> dict:
    rec = lg.get(Path(a.ledger), uid)
    if rec is None or not rec.get("root_ts"):
        raise ThreadError(f"장부 불명: {uid} — `byz_thread_post.py repair --card {a.card}`")
    return rec


def cmd_start(a: argparse.Namespace) -> int:
    uid, card, ledger = unit_id(a.card, a.team), Path(a.card), Path(a.ledger)
    if (old := lg.get(ledger, uid)) is not None:
        print(f"REJECT {uid} 는 이미 시작됨 root_ts={old.get('root_ts')}", file=sys.stderr)
        return 1
    if read_line(card) is not None:
        raise ThreadError(f"카드에 이미 「- 슬랙:」 줄이 있다 — 새로 시작하지 말고 repair: {card}")
    for f in a.file:
        if not Path(f).is_file():
            raise ThreadError(f"첨부 파일 없음: {f}")
    text = f"{marker(uid)}\n{esc(a.text)}\n{block_of(a)}"  # 블록 칸 누락은 카드·원격에 아무것도 쓰기 «전» 에 raise
    write_line(card, f"- 슬랙: {a.channel} · 시도 {datetime.now(KST).isoformat(timespec='seconds')}")
    t = target(a)
    root = post(t.base, t.token, t.channel, text)
    write_line(card, f"- 슬랙: {a.channel} {root}")
    lg.create(ledger, uid, channel=a.channel, root_ts=root, kind="unit", card_path=a.card)
    attach(t, root, a.file)
    print(f"started {uid} root_ts={root}")
    return 0


def cmd_progress(a: argparse.Namespace) -> int:
    uid = unit_id(a.card, a.team)
    rec = record(a, uid)
    t = target(a)
    ts = post(t.base, t.token, rec["channel"], f"{esc(a.text)}\n{block_of(a)}", rec["root_ts"])
    lg.update(Path(a.ledger), uid, card_path=a.card, progress=ts)
    attach(Target(t.base, t.token, rec["channel"], ""), rec["root_ts"], a.file)
    print(f"progress {uid} ts={ts}")
    return 0


def _legacy_record(a: argparse.Namespace, uid: str) -> dict:
    """소급 1회용: 장부에 없으면 옛 뿌리 글 ts 로 만든다(kind=unit)."""
    return lg.get(Path(a.ledger), uid) or lg.create(Path(a.ledger), uid, channel=a.channel, root_ts=a.legacy_root, kind="unit", card_path=a.card or rb.NONE)


def cmd_result(a: argparse.Namespace) -> int:
    if a.legacy_root and not a.text.strip():
        raise ThreadError("소급(--legacy-root)은 --text 사실 1줄이 필요하다")
    if not a.legacy_root and not a.verdict:
        raise ThreadError("--verdict <판정문#§N> 이 필요하다 — 결과 1줄은 그 §N 제목 줄")
    uid = a.unit_id or unit_id(a.card, a.team)
    rec = _legacy_record(a, uid) if a.legacy_root else record(a, uid)
    if rec.get("kind") == "report":
        raise ThreadError(f"{uid} 는 보고서(kind=report) — 결과 답글 대상이 아니다")
    if rec.get("results"):
        print(f"already {uid} results={rec['results']}")
        return 0
    line = esc(a.text if a.legacy_root else verdict_title(a.verdict))
    head, block = f"[결과] {esc(uid)}", block_of(a)
    t = target(a)
    t = Target(t.base, t.token, rec["channel"], "")
    ts = find_reply_first_line(t, rec["root_ts"], head)  # 앞 실행이 보내고 장부만 못 썼으면 재발송 0
    if ts is None:
        ts = post(t.base, t.token, t.channel, f"{head}\n{line}\n{'랜딩 ' + a.landed if a.landed else '랜딩 없음'}\n{block}", rec["root_ts"])
    lg.update(Path(a.ledger), uid, card_path=a.card, result=ts)
    print(f"result {uid} ts={ts}")
    return 0


def cmd_check(a: argparse.Namespace) -> int:
    card = read_line(Path(a.card))
    if card is None:
        return 0
    uid = unit_id(a.card, a.team)
    try:
        rec = lg.get(Path(a.ledger), uid)
    except lg.LedgerError as e:
        print(f"UNKNOWN 장부 오류: {e} — repair --card {a.card}", file=sys.stderr)
        return 3
    if card[1] is None or rec is None or not rec.get("root_ts"):
        print(f"UNKNOWN {uid} — repair --card {a.card}", file=sys.stderr)
        return 3
    if rec.get("kind") == "report" or rec.get("results"):
        return 0
    print(f"NO_RESULT {uid} 결과 답글 없음", file=sys.stderr)
    return 1


def cmd_repair(a: argparse.Namespace) -> int:
    uid, card, ledger = unit_id(a.card, a.team), Path(a.card), Path(a.ledger)
    line = read_line(card)
    if line is None:
        raise ThreadError(f"카드에 「- 슬랙:」 줄이 없다(게시 대상 아님): {card}")
    ch, ts = line
    if ts is None:  # «시도» 만 — 채널 최근 글에서 첫 줄 표식 1건만 복구
        t = target(a)
        oldest = f"{datetime.now(KST).timestamp() - LOOKBACK_DAYS * 86400:.6f}"
        msgs = paged(t.base, t.token, "conversations.history", {"channel": ch, "oldest": oldest, "limit": 200})
        hits = sorted(str(m["ts"]) for m in msgs if m.get("bot_id") and str(m.get("text", "")).split("\n", 1)[0] == marker(uid))
        if len(hits) != 1:
            print(f"HUMAN {uid} 표식 글 {len(hits)}건 — 사람이 채널을 확인한다", file=sys.stderr)
            return 1
        ts = hits[0]
        write_line(card, f"- 슬랙: {ch} {ts}")
    cur = lg.load(ledger).get(uid)
    if cur is None:
        lg.create(ledger, uid, channel=ch, root_ts=ts, kind="unit", card_path=a.card)
    elif cur.get("root_ts") != ts:
        raise ThreadError(f"장부 root_ts({cur.get('root_ts')}) ≠ 카드 줄({ts}) — 사람이 확인한다")
    print(f"repaired {uid} root_ts={ts}")
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="%(asctime)s %(levelname)s %(message)s")
    argv = sys.argv[1:] if argv is None else argv
    try:
        if "--init" in argv:
            path = Path(argv[argv.index("--ledger") + 1] if "--ledger" in argv else lg.DEFAULT)
            print(f"{'created' if lg.init(path) else 'exists'} {path}")
            return 0
        a = parse(argv)
        return {"start": cmd_start, "progress": cmd_progress, "result": cmd_result, "check": cmd_check, "repair": cmd_repair}[a.cmd](a)
    except (MirrorError, CardError, OSError, ValueError) as e:
        print(f"ERROR {type(e).__name__}: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
