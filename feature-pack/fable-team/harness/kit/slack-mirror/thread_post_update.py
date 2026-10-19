"""thread_post_update — byz_thread_post `update` (보드 «하루 1 뿌리 글» 갱신 · 판정 421·423 · 설계 §2-3).

`update --key board:<날짜> --text-file <f> [--reply "<1줄>"]`:
  장부에 키 없음 → 뿌리 글 생성(kind=report) · 있음 → `chat.update` 로 뿌리 본문 교체.
  답글 = `--reply` + 장부 `reply_pending`(직전 답글 누락)이 있으면 그것도 함께 — 입력이 같아도 pending 이 있으면 답글을 낸다.
  update 성공 · 답글 실패 = rc 3 + 장부 `reply_pending` 에 그 답글 문구를 남긴다(다음 update 가 «직전 답글 누락 …» 으로 함께 낸다).
  update(또는 뿌리 글 생성) 실패 = raise → rc 1 · 장부 불변(#0 RULE).
`reply --thread <이름>`(r414): 뿌리 ts 를 도구가 소유 — 등록부(slack-threads.json)에 없거나 날짜(KST)·채널이 바뀌면 채널에 뿌리 글을 새로 올려 등록.
"""
import argparse
import json
import os
import re
import sys
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import thread_ledger as lg
from file_guard import check_files
from magazine_slack import Target, upload_file
from mirror_lib import MirrorError, api_call, esc
from post_guard import DEFAULT_ROOT, ROOT_ENV, check, guarded_post as post

KEY = re.compile(r"board:\d{4}-\d{2}-\d{2}")
TS = re.compile(r"\d+\.\d+")
NAME = re.compile(r"[a-z][a-z0-9_-]{0,31}")
KST = ZoneInfo("Asia/Seoul")
THREADS_ENV = "FT_SLACK_THREADS"


def threads_path() -> Path:
    """이름 스레드 등록부 — env FT_SLACK_THREADS, 없으면 <FT_ROOT|기본 루트>/.fable-team/state/slack-threads.json."""
    env = os.environ.get(THREADS_ENV)
    return Path(env) if env else Path(os.environ.get(ROOT_ENV) or DEFAULT_ROOT) / ".fable-team/state/slack-threads.json"


def _load_threads(p: Path) -> dict:
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except ValueError as e:
        raise MirrorError(f"스레드 등록부 손상: {p} ({e})") from e
    if not isinstance(data, dict):
        raise MirrorError(f"스레드 등록부 최상위가 객체 아님: {p}")
    return data


def named_root(t: Target, name: str, channel: str | None) -> tuple[str, str]:
    """이름 → (채널, 뿌리 ts). 없음 ∨ 날짜 ≠ 오늘(KST) ∨ 채널이 다름 → 뿌리 글 `[<이름> 보고 <날짜>]` 1건 + 등록(옛 뿌리는 history)."""
    p, today = threads_path(), datetime.now(KST).date().isoformat()
    reg = _load_threads(p)
    cur = reg.get(name) or {}
    ch = channel or cur.get("channel")
    if not ch:
        raise MirrorError(f"--channel 이 필요하다 — 등록부에 {name} 없음: {p}")
    if cur.get("root_ts") and cur.get("date") == today and cur.get("channel") == ch:
        return ch, cur["root_ts"]
    root = post(t.base, t.token, ch, f"[{name} 보고 {today}]", human=True)
    old = [{k: cur.get(k) for k in ("channel", "root_ts", "date")}] if cur.get("root_ts") else []
    reg[name] = {"channel": ch, "root_ts": root, "date": today, "history": cur.get("history", []) + old}
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(reg, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    os.replace(tmp, p)
    print(f"root {name} ts={root}")
    return ch, root


def cmd_reply(a: argparse.Namespace, target: Callable[[argparse.Namespace], Target]) -> int:
    """`reply (--ts <뿌리 ts> | --thread <이름>) --text-file <파일> [--channel <ID>]` — 스레드에 답글 1개(카드·장부 불요 · 첨부 0). 사람 채널 입구라 1·2묶음 검사를 «항상» 건다."""
    if a.ts is not None and not TS.fullmatch(a.ts):
        raise MirrorError(f"--ts 는 슬랙 ts 꼴(예 1700000000.000100): {a.ts}")
    if a.thread is not None and not NAME.fullmatch(a.thread):
        raise MirrorError(f"--thread 는 소문자 이름(예 desk): {a.thread}")
    body = Path(a.text_file).read_text(encoding="utf-8").strip()
    if not body:
        raise MirrorError(f"본문 파일이 비었다: {a.text_file}")
    text = esc(body)
    check(text, a.channel or "", human=True)  # 뿌리 글 «전» — 본문이 걸리면 뿌리·등록부 불변
    t = target(a)
    ch, root = (a.channel, a.ts) if a.ts is not None else named_root(t, a.thread, a.channel)
    ts = post(t.base, t.token, ch, text, root, human=True)
    print(f"reply ts={ts}")
    return 0


def cmd_attach(a: argparse.Namespace, target: Callable[[argparse.Namespace], Target]) -> int:
    """`attach --key board:<날짜> --file F… --title T` — 그 날 뿌리 글 스레드에 파일 첨부(첫 파일 제목 T · 나머지 `T (파일명)`).
    출력 `link=<첫 파일 permalink> ts=<공유 ts|->` — 장부 불명·업로드·링크 조회 실패는 raise → rc 1(#0 RULE)."""
    if not KEY.fullmatch(a.key):
        raise MirrorError(f"--key 는 board:YYYY-MM-DD 꼴: {a.key}")
    rec = lg.get(Path(a.ledger), a.key)
    if rec is None or not rec.get("root_ts"):
        raise MirrorError(f"장부 불명: {a.key} — 뿌리 글이 먼저 있어야 한다(update)")
    files = check_files(a.file, rec["channel"])  # 업로드 루프 «전» — 비사람 채널의 보드 PDF 는 실재만 본다
    t = target(a)
    t = Target(t.base, t.token, rec["channel"], "")
    first = ""
    for i, c in enumerate(files):  # 검사한 바이트만 올린다
        fid = upload_file(t, rec["root_ts"], Path(c.name), a.title if i == 0 else f"{a.title} ({c.name})", c.content_type, data=c.data)
        first = first or fid
    info = api_call(t.base, t.token, "files.info", {"file": first}, get=True).get("file")
    link = info.get("permalink") if isinstance(info, dict) else None
    if not link:
        raise MirrorError(f"files.info 에 permalink 없음: {first}")
    print(f"link={link} ts={first}")
    return 0


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
        check(body, rec["channel"])
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
