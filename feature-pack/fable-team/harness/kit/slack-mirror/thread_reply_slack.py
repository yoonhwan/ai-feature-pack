"""thread_reply_slack — `reply` 의 오빠 글 자리 찾기(r558): `--to-slack <오빠 글 ts>` 와 `--thread` 거절 검사.

정본 = design/harness/indices/진행/r558-desk-slack-reply-goes-to-oppa-post-thread.md.
수신 원장(`byz_slack_mbox_inbound.<채널>.json` · 수신 데몬이 쓴다)은 «읽기만» 한다 — 답 기록은 따로 작은 파일 1개(`byz_slack_answered.json`).
값: env FT_SLACK_STATE_DIR(기본 ~/.hermes/state) · FT_SLACK_INBOUND_LEDGER(시험) · FT_SLACK_ANSWERED(시험).
"""
import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

from magazine_slack import Target
from mirror_lib import MirrorError, esc, thread_texts
from post_guard import guarded_post as post
from thread_room_shape import ROOM_HINT, refuse_room_post, room_shaped, topic_only  # noqa: F401 — 판정 정본은 한 파일(r617)

STATE_ENV = "FT_SLACK_STATE_DIR"  # 수신 원장·답 기록이 사는 폴더(기본 ~/.hermes/state)
INBOUND_ENV = "FT_SLACK_INBOUND_LEDGER"  # 원장 파일 하나로 고정(시험)
ANSWERED_ENV = "FT_SLACK_ANSWERED"  # 답 기록 파일 경로
INBOUND_PREFIX = "byz_slack_mbox_inbound."
ANSWERED_NAME = "byz_slack_answered.json"
WINDOW = 7 * 86400  # 수신 데몬이 원장에 기억하는 창과 같다(R242) — 그 밖의 글은 답 자리를 따지지 않는다
SHOW = 3  # 거절 문구에 싣는 최신 글 수 — 답 기록이 비어 처음 켜도 한 줄이 감당하게
TOPIC_ENV = "FT_SLACK_TOPIC_ONLY"  # 주제 전용 이름들 — 판정 정본 = thread_room_shape(r617)
TOPIC_DEFAULT = "desk"
ROOT_HEAD = 400  # 거절 문구에 싣는 뿌리 원문 길이 — 답하는 사람이 «그 글을 읽게»(r585)
OLD_DECL = re.compile(r"요청\s*\d+\s*개\s*중\s*\d+\s*개\s*답함")  # 오빠가 빼라고 한 옛 머리말(r661) — 이제 글에 쓰지 않는다
BARE = re.compile(r"r\d+|#\d+|\b[A-Z][A-Za-z]*\d+[A-Za-z]*")  # 번호·약어 꼴(r558·#123·K4b · 줄 단위 검사)
LEFT_LINE = "아직 못 한 것: "  # 덜 답했을 때만 글 끝 1줄(r661) — 그 밖에는 본문에 아무것도 안 붙는다
USAGE = "쓰는 법: 물어본 수·답한 수는 --asked·--answered · 덜 답했으면 --left \"<한 줄>\" · 번호 대신 쉬운 말"


def state_dir() -> Path:
    return Path(os.environ.get(STATE_ENV) or "~/.hermes/state").expanduser()


def inbound_ledger(channel: str) -> Path:
    env = os.environ.get(INBOUND_ENV)
    return Path(env) if env else state_dir() / f"{INBOUND_PREFIX}{channel}.json"


def answered_path() -> Path:
    env = os.environ.get(ANSWERED_ENV)
    return Path(env) if env else state_dir() / ANSWERED_NAME


def _read_json(p: Path) -> dict:
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except ValueError as e:
        raise MirrorError(f"상태 파일 손상: {p} ({e})") from e
    return data if isinstance(data, dict) else {}


def _write_json(p: Path, data: dict) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    os.replace(tmp, p)


def answered() -> dict:
    return _read_json(answered_path()).get("answered") or {}


def mark_answered(oppa_ts: str, reply_ts: str) -> None:
    data = _read_json(answered_path())
    data.setdefault("answered", {})[oppa_ts] = reply_ts
    _write_json(answered_path(), data)


def inbound_find(oppa_ts: str) -> tuple[str, dict]:
    """오빠 글 ts → (채널, 원장 항목). 모르는 ts 는 추측하지 않고 거절한다 — 옛 뿌리로 보내기 0."""
    env = os.environ.get(INBOUND_ENV)
    files = [Path(env)] if env else sorted(state_dir().glob(f"{INBOUND_PREFIX}*.json"))
    for p in files:
        e = (_read_json(p).get("ledger") or {}).get(oppa_ts)
        if isinstance(e, dict):
            return p.name[len(INBOUND_PREFIX):-len(".json")], e
    raise MirrorError(f"수신 원장에 없는 오빠 글 ts: {oppa_ts} — 원장 {', '.join(str(p) for p in files) or '없음'}")


def lineage(seat: str) -> str:
    """좌석 계보 = `#N` 뗀 이름(`magazine_collect_mbox.lineage` 와 같은 규칙 · 승계 뒤에도 같은 계보)."""
    return str(seat).split("#", 1)[0]


def in_lineage(seat: str, name: str) -> bool:
    return name in re.split(r"[-_]", lineage(seat))


def unanswered(channel: str, name: str) -> list[str]:
    """그 이름 스레드 계보 좌석에 이미 전달됐고 · 창 안이며 · 답 기록이 없는 오빠 글 ts(오름차순)."""
    done, now = answered(), time.time()
    ledger = _read_json(inbound_ledger(channel)).get("ledger") or {}
    out = []
    for ts, e in ledger.items():
        if not isinstance(e, dict) or ts in done:
            continue
        if not any(in_lineage(v, name) for v in (e.get("done") or {}).values()):
            continue
        try:
            if float(ts) < now - WINDOW:
                continue
        except ValueError:
            continue
        out.append(ts)
    return sorted(out)


def refuse_topic(name: str, force: bool) -> None:
    """주제 전용 이름이면 답 안 된 글 유무와 무관하게 거절 — 스레드 = 주제 대화 전용 · 방 글 = post(r561)."""
    if name not in topic_only():
        return
    msg = f"{name} 스레드는 주제 대화 전용 — 방 글은 post --to {name} · 오빠 글 답은 reply --to-slack <ts>"
    if force:
        print(f"WARN --thread {name} 강제 전송 — {msg}", file=sys.stderr)
        return
    raise MirrorError(f"REJECT --thread {name} — {msg}")


def refuse_unanswered(name: str, channel: str | None, force: bool) -> None:
    """`--thread <name>` 이 «오빠 새 글» 을 건너뛰는지 검사한다 — 채널을 모르면 원장을 못 읽으니 통과(named_root 가 «--channel 필요» 로 거절)."""
    refuse_topic(name, force)  # 주제 전용(기본 desk) = 답 안 된 글 유무와 무관하게 거절(r561)
    if not channel:
        return
    pending = unanswered(channel, name)
    if not pending:
        return
    shown = pending[-SHOW:]  # 최신부터 — 쪽지·stderr 한 줄이 감당할 만큼만(나머지는 개수로)
    msg = " · ".join(f"답할 오빠 글 {ts} — reply --to-slack {ts}" for ts in shown)
    msg += " (승인·질문 묶음 = post --to desk)"  # 묶음 글은 스레드가 아니라 방(r617)
    if len(pending) > len(shown):
        msg += f" · …외 {len(pending) - len(shown)}건"
    if force:
        print(f"WARN --thread {name} 강제 전송 — {msg}", file=sys.stderr)
        return
    raise MirrorError(f"REJECT --thread {name} 는 옛 뿌리 밑으로 간다 — {msg}")


def root_text(base: str, token: str, channel: str, root: str) -> str:
    """오빠 글 스레드 첫 글(뿌리) 원문 — 7초 상한·재시도 1, 실패는 REJECT(조용히 게시 0)."""
    try:
        texts = thread_texts(base, token, channel, root, limit=1)
    except MirrorError as e:
        raise MirrorError(f"REJECT 뿌리 글 읽기 실패 ts={root} — 답 0 ({e})") from e
    body = texts[0].strip() if texts else ""
    if not body:
        raise MirrorError(f"REJECT 뿌리 글 비었음 ts={root} — 답 0")
    return body


def _complaint(text: str, lines: list[str], asked: int | None, answered: int | None, left: str | None) -> str:
    """본문이 걸리는 이유 1줄(사람 말) — 안 걸리면 빈 문자열. 번호·약어만 3줄+ 판정은 r558 그대로."""
    bare = sum(1 for ln in lines if BARE.search(ln))
    if OLD_DECL.search(text):
        return "«요청 N개 중 M개 답함» 머리말은 오빠가 빼라고 했어요 — 셈은 --asked·--answered 로 주세요"
    if asked is None or answered is None:
        return "오빠 글에 물어본 개수·답한 개수를 --asked·--answered 로 알려 주세요(예 --asked 3 --answered 3)"
    if bare >= 3 and bare * 2 > len(lines):
        return "번호·약어만 늘어놓았어요 — 쉬운 말로"
    if answered < asked and not (left or "").strip():
        return f"오빠 글에 물어본 게 {asked}개인데 {answered}개만 답했어요. 못 한 {asked - answered}개를 --left 에 한 줄로 적어 주세요"
    return ""


def check_body(text: str, root: str, asked: int | None, answered: int | None, left: str | None) -> str:
    """게시 전 본문 검사(r661: 셈은 인자) — 옛 머리말 · 셈 · 번호만 · 걸리면 뿌리 원문 + 쓰는 법을 붙여 REJECT.
    통과하면 게시할 본문 — 덜 답했으면 끝에 «아직 못 한 것: <left>» 1줄만 붙고, 그 밖에는 입력 그대로."""
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    why = _complaint(text, lines, asked, answered, left)
    if why:
        head = re.sub(r"\s+", " ", root).strip()[:ROOT_HEAD]
        raise MirrorError(f"REJECT 답 — {why}\n--- 오빠 글(뿌리) 앞 {ROOT_HEAD}자 ---\n{head}\n--- {USAGE}")
    if asked is None or answered is None or answered >= asked:
        return text
    return text.rstrip() + "\n" + LEFT_LINE + re.sub(r"\s+", " ", left or "").strip()


def reply_to_slack(a: argparse.Namespace, t: Target, text: str) -> int:
    """오빠 글 ts 의 «그 글/그 스레드» 밑에 답한다 — 게시 «전» 뿌리 원문을 읽어 본문을 검사한다(r585 · r661 셈은 인자)."""
    ch, e = inbound_find(a.to_slack)
    root = str(e.get("thread") or a.to_slack)
    channel = a.channel or ch
    left = getattr(a, "left", None)
    text = check_body(text, root_text(t.base, t.token, channel, root), getattr(a, "asked", None),
                      getattr(a, "answered", None), esc(left) if left else None)
    ts = post(t.base, t.token, channel, text, root, human=True)
    mark_answered(a.to_slack, ts)
    print(f"reply ts={ts} to_slack={a.to_slack} thread={root}")
    return 0
