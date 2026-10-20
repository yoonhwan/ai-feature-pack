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
from mirror_lib import MirrorError
from post_guard import guarded_post as post

STATE_ENV = "FT_SLACK_STATE_DIR"  # 수신 원장·답 기록이 사는 폴더(기본 ~/.hermes/state)
INBOUND_ENV = "FT_SLACK_INBOUND_LEDGER"  # 원장 파일 하나로 고정(시험)
ANSWERED_ENV = "FT_SLACK_ANSWERED"  # 답 기록 파일 경로
INBOUND_PREFIX = "byz_slack_mbox_inbound."
ANSWERED_NAME = "byz_slack_answered.json"
WINDOW = 7 * 86400  # 수신 데몬이 원장에 기억하는 창과 같다(R242) — 그 밖의 글은 답 자리를 따지지 않는다
SHOW = 3  # 거절 문구에 싣는 최신 글 수 — 답 기록이 비어 처음 켜도 한 줄이 감당하게


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


def refuse_unanswered(name: str, channel: str | None, force: bool) -> None:
    """`--thread <name>` 이 «오빠 새 글» 을 건너뛰는지 검사한다 — 채널을 모르면 원장을 못 읽으니 통과(named_root 가 «--channel 필요» 로 거절)."""
    if not channel:
        return
    pending = unanswered(channel, name)
    if not pending:
        return
    shown = pending[-SHOW:]  # 최신부터 — 쪽지·stderr 한 줄이 감당할 만큼만(나머지는 개수로)
    msg = " · ".join(f"답할 오빠 글 {ts} — reply --to-slack {ts}" for ts in shown)
    if len(pending) > len(shown):
        msg += f" · …외 {len(pending) - len(shown)}건"
    if force:
        print(f"WARN --thread {name} 강제 전송 — {msg}", file=sys.stderr)
        return
    raise MirrorError(f"REJECT --thread {name} 는 옛 뿌리 밑으로 간다 — {msg}")


def reply_to_slack(a: argparse.Namespace, t: Target, text: str) -> int:
    """오빠 글 ts 의 «그 글/그 스레드» 밑에 답하고 답 기록에 남긴다(보낸 뒤에만 기록)."""
    ch, e = inbound_find(a.to_slack)
    root = str(e.get("thread") or a.to_slack)
    ts = post(t.base, t.token, a.channel or ch, text, root, human=True)
    mark_answered(a.to_slack, ts)
    print(f"reply ts={ts} to_slack={a.to_slack} thread={root}")
    return 0
