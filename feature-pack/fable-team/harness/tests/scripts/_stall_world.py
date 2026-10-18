"""R320b — ft-stall-scan·ft-penalty 시험용 «가짜 세계» (실 좌석 깨우기·ring·kill 0).

가짜 명부·카드 폴더·jsonl·tmux·mbox·seat-status 를 임시 폴더에 만들고 env 로 건다. 판정 코드는 진짜로 돈다.
"""
import json
import os
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path

BIN = Path(__file__).resolve().parents[3] / "harness/kit/fable-team/bin"
NOW = 1_800_000_000  # 고정 «지금» — FT_NOW 로 건다

STATUS = (
    '#!/bin/sh\nd="$FT_STUB/turn"\ncase "$1" in\n'
    '  turn) s="$2"; [ "$2" = --file ] && s=$(basename "$3" .jsonl); echo "$s" >> "$FT_STUB/turn.calls"; cat "$d/$s" 2>/dev/null || echo "UNKNOWN - - - pane";;\n'
    '  jsonl) echo "$2" >> "$FT_STUB/jsonl.calls"; [ -f "$FT_STUB/jsonl/$2.jsonl" ] && echo "$FT_STUB/jsonl/$2.jsonl" || exit 1;;\nesac\n'
)
TMUX = (
    '#!/bin/sh\ncase "$1" in\n  list-sessions) cat "$FT_STUB/tmux" 2>/dev/null;;\n'
    '  list-panes) awk \'{print $1"|%"NR}\' "$FT_STUB/tmux";;\n'
    '  send-keys) echo "$*" >> "$FT_STUB/tmux.log";;\nesac\n'
)
MBOX = (
    '#!/bin/sh\nfor a; do last="$a"; done\n'
    'case "$1" in\n  send) echo "send|$2|$3|$last|$4" >> "$FT_STUB/mbox.log";;\n  ring) echo "ring|$2|${3:-}" >> "$FT_STUB/mbox.log";;\nesac\n'
)
LINT = '#!/bin/sh\ngrep -q LINTBAD "$1" && exit 1\nexit 0\n'


def _exe(path: Path, body: str) -> Path:
    _ = path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


def iso(minutes_ago: float) -> str:
    return datetime.fromtimestamp(NOW - minutes_ago * 60, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


class World:
    def __init__(self, tmp: Path):
        self.root = tmp / "repo"
        self.stub = tmp / "stub"
        for d in ("turn", "jsonl"):
            (self.stub / d).mkdir(parents=True)
        (self.root / ".fable-team/state").mkdir(parents=True)
        (self.root / ".fable-team/comm").mkdir(parents=True)
        self.env = dict(os.environ)
        self.env.update(
            FT_ROOT=str(self.root), FT_STUB=str(self.stub), FT_NOW=str(NOW),
            FT_SEAT_STATUS=str(_exe(self.stub / "seat-status.sh", STATUS)), FT_TMUX=str(_exe(self.stub / "tmux.sh", TMUX)),
            FT_MBOX_SH=str(_exe(self.stub / "mbox.sh", MBOX)), FT_INDEX_LINT=str(_exe(self.stub / "lint.sh", LINT)),
            FT_MBOX_DIR=str(self.root / ".fable-team/comm"),
        )
        shim = self.stub / "shim"
        shim.mkdir()
        _ = _exe(shim / "tmux", '#!/bin/sh\n[ "$1" = list-sessions ] && cut -d" " -f1 "$FT_STUB/tmux"\n')
        self.env["PATH"] = f"{shim}{os.pathsep}{self.env['PATH']}"
        self.live: list[str] = []
        self.team("t1", "t1-master#1", ["t1-nano#0"])
        self.planner("planner#1")

    def team(self, label: str, master: str, seats: list[str]) -> None:
        rows: dict[str, object] = {"_master": master, "_label": label, "_cards": f"design/{label}/indices", "_cards_wt": f"wt-{label}"}
        for s in [master, *seats]:
            rows[s] = {"role": "master" if s == master else "nano"}
            self.live.append(s)
        _ = (self.root / f".fable-team/seats-{label}.json").write_text(json.dumps(rows))
        self._tmux()

    def planner(self, seat: str) -> None:
        _ = (self.root / ".fable-team/seats-planner.json").write_text(json.dumps({"_master": seat, "_label": "planner", "_cards": "design/planner/indices", "_cards_wt": "wt-planner", seat: {"role": "master"}}))
        self.live.append(seat)
        self._tmux()

    def _tmux(self) -> None:
        _ = (self.stub / "tmux").write_text("".join(f"{s} 0\n" for s in self.live))

    def attach(self, seat: str) -> None:
        _ = (self.stub / "tmux").write_text("".join(f"{s} {1 if s == seat else 0}\n" for s in self.live))

    def cards(self, label: str, names: list[str], body: str = "- 선행: 없음\n") -> None:
        d = self.root / f".worktrees/wt-{label}/design/{label}/indices/대기"
        d.mkdir(parents=True, exist_ok=True)
        for n in names:
            _ = (d / f"{n}.md").write_text(f"# {n}\n{body}")

    def state(self, seat: str, state: str, minutes: float) -> None:
        _ = (self.stub / "turn" / seat).write_text(f"{state} {iso(minutes)} 1000 no jsonl\n")

    def jsonl(self, seat: str, text: str, tool: bool = False) -> None:
        content: list[dict[str, object]] = [{"type": "text", "text": text}]
        if tool:
            content.append({"type": "tool_use", "name": "Bash", "input": {"command": "ls"}})
        recs = [{"type": "system", "subtype": "turn_duration"}, {"type": "assistant", "message": {"content": content}}, {"type": "system", "subtype": "turn_duration"}]
        _ = (self.stub / "jsonl" / f"{seat}.jsonl").write_text("".join(json.dumps(r) + "\n" for r in recs))

    def mail(self, to: str, seq: int, minutes_ago: float) -> None:
        ts = datetime.fromtimestamp(NOW - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")
        with open(self.root / ".fable-team/comm/mailbox.jsonl", "a", encoding="utf-8") as f:
            _ = f.write(json.dumps({"seq": seq, "ts": ts, "to": to, "from": "x", "body": "발주"}, ensure_ascii=False) + "\n")

    def freeze(self) -> None:
        _ = (self.root / ".fable-team/state/RESOURCE_FREEZE").write_text("disk\n")

    def advance(self, seconds: int) -> None:
        self.env["FT_NOW"] = str(int(self.env["FT_NOW"]) + seconds)

    def scan(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=self.env, capture_output=True, text=True, timeout=60)

    def penalty(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(BIN / "ft-penalty.sh"), *args], env=self.env, capture_output=True, text=True, timeout=60)

    def mbox_log(self) -> list[str]:
        p = self.stub / "mbox.log"
        return p.read_text().splitlines() if p.exists() else []

    def tmux_log(self) -> list[str]:
        p = self.stub / "tmux.log"
        return p.read_text().splitlines() if p.exists() else []

    def calls(self, name: str) -> list[str]:
        p = self.stub / name
        return p.read_text().splitlines() if p.exists() else []

    def scan_log(self) -> list[str]:
        p = self.root / ".fable-team/state/stall-scan.log"
        return p.read_text().splitlines() if p.exists() else []


def counts(out: str) -> dict[str, str]:
    first = out.splitlines()[0]
    return dict(kv.split("=", 1) for kv in first.split() if "=" in kv)


__all__ = ["World", "counts", "NOW", "BIN", "iso"]
