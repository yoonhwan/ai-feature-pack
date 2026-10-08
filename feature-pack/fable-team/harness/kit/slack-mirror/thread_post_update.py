"""thread_post_update — byz_thread_post `update` (보드 «하루 1 뿌리 글» 갱신 · 판정 421·423 · 설계 §2-3).

`update --key board:<날짜> --text-file <f> [--reply "<1줄>"]`:
  장부에 키 없음 → 뿌리 글 생성(kind=report) · 있음 → `chat.update` 로 뿌리 본문 교체.
  답글 = `--reply` + 장부 `reply_pending`(직전 답글 누락)이 있으면 그것도 함께 — 입력이 같아도 pending 이 있으면 답글을 낸다.
  update 성공 · 답글 실패 = rc 3 + 장부 `reply_pending` 에 그 답글 문구를 남긴다(다음 update 가 «직전 답글 누락 …» 으로 함께 낸다).
  update(또는 뿌리 글 생성) 실패 = raise → rc 1 · 장부 불변(#0 RULE).
"""
import argparse
import re
import sys
from collections.abc import Callable
from pathlib import Path

import thread_ledger as lg
from magazine_slack import Target
from mirror_lib import MirrorError, api_call, esc, post

KEY = re.compile(r"board:\d{4}-\d{2}-\d{2}")


def cmd_update(a: argparse.Namespace, target: Callable[[argparse.Namespace], Target]) -> int:
    if not KEY.fullmatch(a.key):
        raise MirrorError(f"--key 는 board:YYYY-MM-DD 꼴: {a.key}")
    body = Path(a.text_file).read_text(encoding="utf-8")
    if not body.strip():
        raise MirrorError(f"본문 파일이 비었다: {a.text_file}")
    t, ledger = target(a), Path(a.ledger)
    rec = lg.get(ledger, a.key)
    if rec is None:
        root = post(t.base, t.token, a.channel, body)
        lg.create(ledger, a.key, channel=a.channel, root_ts=root, kind="report", card_path="없음")
        print(f"created {a.key} root_ts={root}")
        pending = None
    else:
        api_call(t.base, t.token, "chat.update", {"channel": rec["channel"], "ts": rec["root_ts"], "text": body})
        print(f"updated {a.key} root_ts={rec['root_ts']}")
        pending = rec.get("reply_pending")
    lines = ([f"직전 답글 누락 — {pending}"] if pending else []) + ([esc(a.reply)] if a.reply else [])
    if not lines:
        return 0
    text, rec = "\n".join(lines), lg.get(ledger, a.key)
    try:
        ts = post(t.base, t.token, rec["channel"], text, rec["root_ts"])
    except MirrorError as e:
        lg.set_field(ledger, a.key, "reply_pending", text)
        print(f"REPLY_PENDING {a.key} — {e} (다음 update 가 «직전 답글 누락» 으로 함께 낸다)", file=sys.stderr)
        return 3
    lg.set_field(ledger, a.key, "reply_pending", None)
    print(f"reply {a.key} ts={ts}")
    return 0
