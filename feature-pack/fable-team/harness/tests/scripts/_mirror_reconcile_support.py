"""r1294 fake mirror fixtures shared by focused tests."""
import json
import re
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

KIT = Path(__file__).resolve().parents[2] / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import mirror_lib as lib
from _slack_fakes import FakeSlack

TO = "byz-planner-arch#2"
FROM = "byz-planner-master-claude#146"
DESK = "CDESK"


@pytest.fixture(name="slack")
def slack():
    fake = FakeSlack()
    yield fake
    fake.srv.shutdown()


def row(seq, body, ts, to=TO, sender=FROM):
    return {"seq": seq, "ts": str(ts), "to": to, "from": sender,
            "body": f"[{sender}->{to}] {body}"}


def rig(tmp_path, slack, rows=(), last=50, state=None):
    path = tmp_path / "threads.json"
    path.write_text(json.dumps({"threads": {}}), encoding="utf-8")
    sp = tmp_path / "state.json"
    sp.write_text(json.dumps({"last_seq": last, "pending": None, **(state or {})}), encoding="utf-8")
    return SimpleNamespace(a=SimpleNamespace(api_base=slack.base), token="test", rows=list(rows),
                           state_path=sp, seat=re.compile(r"^byz-planner-arch#\d+$"), urgent=None,
                           urgent_senders=frozenset(), desk=SimpleNamespace(channel=DESK, mention="U123",
                           deliv=SimpleNamespace(threads_path=path)))


def save_thread(mirror, key, slack, seq=None, marker_root=False, channel=DESK):
    text = f"bodies/{seq}.txt@mbox" if seq is not None and marker_root else "desk root"
    root = lib.api_call(slack.base, "test", "chat.postMessage", {"channel": channel, "text": text})["ts"]
    if seq is not None and not marker_root:
        lib.api_call(slack.base, "test", "chat.postMessage", {"channel": channel,
                     "text": f"bodies/{seq}.txt@mbox", "thread_ts": root})
    data = json.loads(mirror.desk.deliv.threads_path.read_text(encoding="utf-8"))
    data["threads"][key] = root
    mirror.desk.deliv.threads_path.write_text(json.dumps(data), encoding="utf-8")
    return root


def key_for(r):
    return lib.thread_key(r, lib.classify(r["body"])[1])
