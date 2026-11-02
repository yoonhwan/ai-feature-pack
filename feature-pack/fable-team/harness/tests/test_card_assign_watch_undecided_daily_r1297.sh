#!/usr/bin/env bash
if [ -n "${R1297_UNDECIDED_TEST_ACTIVE:-}" ]; then echo "재진입 금지"; exit 3; fi
export R1297_UNDECIDED_TEST_ACTIVE=1 TZ=Asia/Seoul
set -euo pipefail
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
python3 - "$BIN" <<'PY'
import json
import os
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, sys.argv[1])
import ft_card_assign_watch as watch

os.environ["TZ"] = "Asia/Seoul"
time.tzset()


def epoch(day: int, hour: int, minute: int = 0) -> float:
    return time.mktime(datetime(2026, 11, day, hour, minute).timetuple())


def fixture(tmp: str):
    root = Path(tmp) / "root"
    state = root / ".fable-team/state/card-assign"
    state.mkdir(parents=True)
    sent = Path(tmp) / "sent.log"
    mbox = Path(tmp) / "mbox.sh"
    mbox.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$SENT"\nprintf "QUEUED seq=1\\n"\n', encoding="utf-8")
    mbox.chmod(0o755)
    os.environ["SENT"] = str(sent)
    os.environ["FT_MBOX_SH"] = str(mbox)
    return root, state, sent


def state(path: Path) -> dict:
    return json.loads((path / "alarm.state").read_text(encoding="utf-8"))


def sent_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines() if path.exists() else []


with patch.object(watch, "team_master", return_value="byz-planner-master#1"):
    with tempfile.TemporaryDirectory() as tmp:
        root, path, sent = fixture(tmp)
        watch.tick(root, epoch(1, 8), None, "git timeout", [])
        watch.tick(root, epoch(1, 8, 30), None, "root missing", [])
        day = state(path)["undecided_day"]
        assert day == {"day": "2026-11-01", "n": 2, "first": epoch(1, 8), "last": epoch(1, 8, 30),
                       "reasons": {"git timeout": 1, "root missing": 1}}, day
        assert len((path / "undecided.log").read_text(encoding="utf-8").splitlines()) == 2
        assert not sent_lines(sent), sent_lines(sent)
        watch.tick(root, epoch(2, 9), None, "git timeout", [])
        out = sent_lines(sent)
        assert len(out) == 1 and "[정리]" in out[0] and "2026-11-01 2회" in out[0], out
        assert "첫 08:00 · 마지막 08:30" in out[0] and "git timeout 1 · root missing 1" in out[0], out
        assert state(path)["undecided_day"]["day"] == "2026-11-02"
        assert state(path)["undecided_day"]["n"] == 1
print("R5 PASS · 판정 불가 2회 집계 후 날짜 변경 첫 실패에 전날 [정리] 1통")

with patch.object(watch, "team_master", return_value="byz-planner-master#1"):
    with tempfile.TemporaryDirectory() as tmp:
        root, path, sent = fixture(tmp)
        watch.tick(root, epoch(1, 10), None, "git timeout", [])
        watch.tick(root, epoch(2, 10), [], "", [])
        watch.tick(root, epoch(2, 10, 5), [], "", [])
        out = sent_lines(sent)
        assert len(out) == 1 and "[정리]" in out[0] and "2026-11-01 1회" in out[0], out
        log = watch.tick(root, epoch(2, 10, 10), [], "", [])
        assert not any("[정리]" in line for line in log) and len(sent_lines(sent)) == 1, log
print("R6 PASS · 첫 정상 tick에 전날 묶음 1통, 같은 날 반복 tick 억제")
PY
