"""thread_post_args — byz_thread_post CLI 인자 (분리 · 200줄 한도). 6칸 블록 인자는 전부 필수 — 값이 없으면 호출자가 문자 `없음`."""
import argparse
from pathlib import Path

import thread_ledger as lg
from magazine_slack import SLACK_BASE

HOME = Path.home()
CHANNEL = "C0C6MJGRR89"


def parse(argv: list[str]) -> argparse.Namespace:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--card", help="카드(인덱스) 파일 — 단위 ID 의 근거")
    common.add_argument("--team")
    common.add_argument("--ledger", default=str(lg.DEFAULT))
    common.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    common.add_argument("--hermes-env", default=str(HOME / ".hermes/.env"))
    common.add_argument("--slack-base", default=SLACK_BASE)
    common.add_argument("--channel", default=CHANNEL)
    blk = argparse.ArgumentParser(add_help=False)
    for n in ("issue", "seat", "canon", "next"):  # 6칸 — 값이 없으면 호출자가 문자 `없음`
        blk.add_argument(f"--{n}", required=True)
    blk.add_argument("--resume-script", required=True, help="ft-resume-cmd.sh 경로")
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start", parents=[common, blk])
    s.add_argument("--text", required=True)
    s.add_argument("--file", action="append", default=[])
    g = sub.add_parser("progress", parents=[common, blk])
    g.add_argument("--text", required=True)
    g.add_argument("--file", action="append", default=[])
    r = sub.add_parser("result", parents=[common, blk])
    r.add_argument("--verdict", help="<판정문 경로>#§N — 결과 1줄 = 그 §N 제목 줄")
    r.add_argument("--landed", help="랜딩 sha")
    r.add_argument("--text", default="", help="소급(--legacy-root) 전용 사실 1줄")
    r.add_argument("--legacy-root", help="소급 1회용: 옛 뿌리 글 ts")
    r.add_argument("--unit-id", help="소급 전용 단위 ID(카드가 없을 때)")
    r.add_argument("--bot", choices=("hermes", "yoonhwan"), default="yoonhwan", help="소급 전용")
    sub.add_parser("check", parents=[common])
    rp = sub.add_parser("repair", parents=[common])
    rp.add_argument("--root", help="사람이 아는 뿌리 글 ts — 카드 줄이 「시도」 이거나 없을 때만(답글 ts 거부)")
    u = sub.add_parser("update", parents=[common], help="보드 뿌리 글 갱신(하루 1글)")
    u.add_argument("--key", required=True, help="board:<YYYY-MM-DD>")
    u.add_argument("--text-file", required=True)
    u.add_argument("--reply", default="", help="변화 답글 1줄")
    rpl = sub.add_parser("reply", parents=[common], help="아무 스레드에 답글 1개(desk 입구 · 카드·장부 불요)")
    rpl.add_argument("--ts", required=True, help="뿌리 글 ts")
    rpl.add_argument("--text-file", required=True)
    t = sub.add_parser("attach", parents=[common], help="보드 뿌리 글 스레드에 파일 첨부(시트 PDF) — 첫 파일 링크를 출력")
    t.add_argument("--key", required=True, help="board:<YYYY-MM-DD>")
    t.add_argument("--file", action="append", required=True)
    t.add_argument("--title", required=True)
    a = p.parse_args(argv)
    if a.cmd not in ("update", "attach", "reply") and not (a.card or getattr(a, "unit_id", None)):
        p.error("--card 가 필요하다")
    return a
