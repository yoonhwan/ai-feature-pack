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
    # --channel 은 부모를 둘로 — parents= 는 Action 객체를 공유해 set_defaults 가 전 서브명령 기본값을 바꾼다(r474)
    chan = argparse.ArgumentParser(add_help=False)
    chan.add_argument("--channel", default=CHANNEL)
    chan_reply = argparse.ArgumentParser(add_help=False)
    chan_reply.add_argument("--channel", default=None)  # --thread 는 등록부 채널 · --ts 는 아래에서 옛 기본값
    blk = argparse.ArgumentParser(add_help=False)
    for n in ("issue", "seat", "canon", "next"):  # 6칸 — 값이 없으면 호출자가 문자 `없음`
        blk.add_argument(f"--{n}", required=True)
    blk.add_argument("--resume-script", required=True, help="ft-resume-cmd.sh 경로")
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("start", parents=[common, chan, blk])
    s.add_argument("--text", required=True)
    s.add_argument("--file", action="append", default=[])
    g = sub.add_parser("progress", parents=[common, chan, blk])
    g.add_argument("--text", required=True)
    g.add_argument("--file", action="append", default=[])
    r = sub.add_parser("result", parents=[common, chan, blk])
    r.add_argument("--verdict", help="<판정문 경로>#§N — 결과 1줄 = 그 §N 제목 줄")
    r.add_argument("--landed", help="랜딩 sha")
    r.add_argument("--text", default="", help="소급(--legacy-root) 전용 사실 1줄")
    r.add_argument("--legacy-root", help="소급 1회용: 옛 뿌리 글 ts")
    r.add_argument("--unit-id", help="소급 전용 단위 ID(카드가 없을 때)")
    r.add_argument("--bot", choices=("hermes", "yoonhwan"), default="yoonhwan", help="소급 전용")
    sub.add_parser("check", parents=[common, chan])
    rp = sub.add_parser("repair", parents=[common, chan])
    rp.add_argument("--root", help="사람이 아는 뿌리 글 ts — 카드 줄이 「시도」 이거나 없을 때만(답글 ts 거부)")
    u = sub.add_parser("update", parents=[common, chan], help="보드 뿌리 글 갱신(하루 1글)")
    u.add_argument("--key", required=True, help="board:<YYYY-MM-DD>")
    u.add_argument("--text-file", required=True)
    u.add_argument("--reply", default="", help="변화 답글 1줄")
    rpl = sub.add_parser("reply", parents=[common, chan_reply], help="아무 스레드에 답글 1개(desk 입구 · 카드·장부 불요)")
    root = rpl.add_mutually_exclusive_group(required=True)
    root.add_argument("--ts", help="뿌리 글 ts(손으로 아는 스레드)")
    root.add_argument("--thread", help="이름 스레드(예 desk) — 뿌리는 등록부 slack-threads.json 이 소유(r414)")
    root.add_argument("--to-slack", help="오빠 글 ts — 수신 원장에서 그 글의 스레드 뿌리를 찾아 그 밑에 단다(r558)")
    rpl.add_argument("--text-file")
    rpl.add_argument("--text", help="본문 1개 — 쪽지 끝 «답 = …» 줄 그대로(r558)")
    rpl.add_argument("--force-thread", action="store_true", help="--thread 로 보내되 «답 안 된 오빠 글» 검사를 건너뛴다(명시 · stderr WARN · r558)")
    po = sub.add_parser("post", parents=[common, chan_reply], help="방에 새 글 1개(스레드 아님) — 승인·뉴스·알림(r561)")
    po.add_argument("--to", help="등록부(slack-threads.json) 이름 예 desk — 그 채널 «방» 에 올린다")
    po.add_argument("--text")
    po.add_argument("--text-file")
    t = sub.add_parser("attach", parents=[common, chan], help="보드 뿌리 글 스레드에 파일 첨부(시트 PDF) — 첫 파일 링크를 출력")
    t.add_argument("--key", required=True, help="board:<YYYY-MM-DD>")
    t.add_argument("--file", action="append", required=True)
    t.add_argument("--title", required=True)
    a = p.parse_args(argv)
    if a.cmd == "reply":
        if (a.text is None) == (a.text_file is None):
            p.error("reply 는 --text 또는 --text-file 중 하나가 필요하다")
        if a.ts is not None and a.channel is None:
            a.channel = CHANNEL  # 기존 --ts 호출 불변 — --to-slack 의 채널은 수신 원장이 정한다
    if a.cmd == "post":
        if (a.to is None) == (a.channel is None):
            p.error("post 는 --to <등록부 이름> 또는 --channel <ID> 중 하나가 필요하다")
        if (a.text is None) == (a.text_file is None):
            p.error("post 는 --text 또는 --text-file 중 하나가 필요하다")
    if a.cmd not in ("update", "attach", "reply", "post") and not (a.card or getattr(a, "unit_id", None)):
        p.error("--card 가 필요하다")
    return a
