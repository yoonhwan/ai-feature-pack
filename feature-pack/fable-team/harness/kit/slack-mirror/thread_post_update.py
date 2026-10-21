"""thread_post_update — byz_thread_post `update` (보드 «하루 1 뿌리 글» 갱신 · 판정 421·423 · 설계 §2-3).

`update --key board:<날짜> --text-file <f> [--reply "<1줄>"]`:
  장부에 키 없음 → 뿌리 글 생성(kind=report) · 있음 → `chat.update` 로 뿌리 본문 교체.
  답글 = `--reply` + 장부 `reply_pending`(직전 답글 누락)이 있으면 그것도 함께 — 입력이 같아도 pending 이 있으면 답글을 낸다.
  update 성공 · 답글 실패 = rc 3 + 장부 `reply_pending` 에 그 답글 문구를 남긴다(다음 update 가 «직전 답글 누락 …» 으로 함께 낸다).
  update(또는 뿌리 글 생성) 실패 = raise → rc 1 · 장부 불변(#0 RULE).
`reply --thread <이름>`(r414): 뿌리 ts 를 도구가 소유 — 등록부(slack-threads.json)에 없거나 날짜(KST)·채널이 바뀌면 채널에 뿌리 글을 새로 올려 등록.
`reply --to-slack <오빠 글 ts>`(r558): 뿌리 = 수신 원장(byz_slack_mbox_inbound.<ch>.json)의 그 글 `thread` 값(빈 값 = 그 글) — 오빠 새 글 밑에 답한다.
  셈 = 인자(r661): `--asked N --answered M [--left "<한 줄>"]` — 답 본문에 머리말을 쓰지 않는다. `--asked`・`--answered` 는 필수 · `M<N` 이면 `--left` 필수로 본문 끝에 «아직 못 한 것: …» 1줄 · 본문에 옛 머리말 «요청 N개 중 M개 답함» 이 있으면 REJECT.
`reply (--ts|--to-slack)` 방 글 꼴 거절(r617): 본문이 승인 묶음·상태 알림·뉴스 꼴이면 rc2 + «방 글은 post --to desk» 1줄 — 스레드 = 주제 대화 전용(`--force-thread` 면 경고 후 게시 · env `FT_SLACK_TOPIC_ONLY` 빈 값이면 끔).
`post (--to <등록부 이름> | --channel <ID>) (--text|--text-file)`(r561): 방에 «최상위 글 1개» — thread_ts 없음 · 등록부·답 기록 쓰기 0 · 첨부 0. 승인·뉴스·알림은 스레드가 아니라 방 글이고, 스레드는 주제 대화 전용이다.
  답 기록(byz_slack_answered.json) 밖에 «그 이름 스레드 계보 좌석에 이미 전달 · 창(7일) 안 · 답 기록 없음» 오빠 글이 있으면 `--thread` 는 REJECT(`--force-thread` 면 경고 후 전송) — 인계서·메모리 규칙에 기대지 않는다.
  상태 폴더 = env FT_SLACK_STATE_DIR(기본 ~/.hermes/state) · 원장 파일 = env FT_SLACK_INBOUND_LEDGER · 답 기록 = env FT_SLACK_ANSWERED. 원장은 «읽기만» 한다.
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
import thread_reply_slack as trs
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
    """`reply (--ts <뿌리 ts> | --thread <이름> | --to-slack <오빠 글 ts>) (--text|--text-file) [--channel <ID>]` — 스레드에 답글 1개(카드·장부 불요 · 첨부 0). 사람 채널 입구라 1·2묶음 검사를 «항상» 건다."""
    if a.ts is not None and not TS.fullmatch(a.ts):
        raise MirrorError(f"--ts 는 슬랙 ts 꼴(예 1700000000.000100): {a.ts}")
    if a.to_slack is not None and not TS.fullmatch(a.to_slack):
        raise MirrorError(f"--to-slack 는 오빠 글 ts 꼴(예 1700000000.000100): {a.to_slack}")
    if a.thread is not None and not NAME.fullmatch(a.thread):
        raise MirrorError(f"--thread 는 소문자 이름(예 desk): {a.thread}")
    body = (a.text if a.text is not None else Path(a.text_file).read_text(encoding="utf-8")).strip()
    if not body:
        raise MirrorError(f"본문이 비었다: {a.text_file or '--text'}")
    text = esc(body)
    check(text, a.channel or "", human=True)  # 뿌리 글 «전» — 본문이 걸리면 뿌리·등록부 불변
    if a.ts is not None or a.to_slack is not None:  # 답글 길도 스레드 = 주제 대화 전용(r617)
        if trs.refuse_room_post(body, a.force_thread):
            return 2  # 게시 0 — 방 글은 post --to desk
    t = target(a)
    if a.to_slack is not None:
        return trs.reply_to_slack(a, t, text)
    if a.thread is not None:
        ch = a.channel or str((_load_threads(threads_path()).get(a.thread) or {}).get("channel") or "")
        trs.refuse_unanswered(a.thread, ch, a.force_thread)  # 뿌리 글·등록부를 건드리기 «전» 에 거절
    ch, root = (a.channel, a.ts) if a.ts is not None else named_root(t, a.thread, a.channel)
    ts = post(t.base, t.token, ch, text, root, human=True)
    print(f"reply ts={ts}")
    return 0


def topic_channel(a: argparse.Namespace) -> str:
    """`--channel <ID>` 직접 또는 `--to <등록부 이름>` → 등록부 채널. 모르는 이름은 추측하지 않고 거절."""
    if a.channel is not None:
        return str(a.channel)
    if not NAME.fullmatch(str(a.to)):
        raise MirrorError(f"--to 는 소문자 이름(예 desk): {a.to}")
    ch = str((_load_threads(threads_path()).get(a.to) or {}).get("channel") or "")
    if not ch:
        raise MirrorError(f"등록부에 없는 이름: {a.to} — {threads_path()} (방 채널을 모른다 · 게시 0)")
    return ch


def cmd_post(a: argparse.Namespace, target: Callable[[argparse.Namespace], Target]) -> int:
    """`post (--to <등록부 이름> | --channel <ID>) (--text|--text-file)` — 방에 새 글 1개(thread_ts 없음). 장부·등록부·답 기록 쓰기 0."""
    body = (a.text if a.text is not None else Path(a.text_file).read_text(encoding="utf-8")).strip()
    if not body:
        raise MirrorError(f"본문이 비었다: {a.text_file or '--text'}")
    ch = topic_channel(a)
    text = esc(body)
    check(text, ch, human=True)  # 사람 채널 — 글 «전» 거절(게시 0)
    t = target(a)
    ts = post(t.base, t.token, ch, text, None, human=True)
    print(f"POSTED {ts}")
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
