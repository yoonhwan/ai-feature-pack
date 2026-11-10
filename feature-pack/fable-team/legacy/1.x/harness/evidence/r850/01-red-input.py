"""r850 빨강 먼저 — 고치기 전 판(origin/main f1cbd005 bin)에 ⓐ·ⓓ 입력을 넣어 옛 판정을 찍는다.
usage: python3 red_r850.py <옛 bin 폴더> <임시 폴더>"""
import json
import os
import re
import sys
from pathlib import Path

old_bin, tmp = Path(sys.argv[1]), Path(sys.argv[2])
sys.path[:0] = [str(old_bin)]
import ft_news_html as fh  # noqa: E402


def enc(c):
    return re.sub(r"[^A-Za-z0-9]", "-", c)


def jsonl(p, names, end):
    rows = [{"type": "custom-title", "customTitle": names[0]}]
    if len(names) > 1:
        rows.append({"type": "assistant", "message": {"content": [{"type": "text", "text": "채움" * 400_000}]}})
    rows += [{"type": "user", "message": {"content": "일"}}, {"type": "assistant", "message": {"content": []}},
             {"type": "system", "subtype": "turn_duration", "timestamp": end, "durationMs": 1000}]
    rows += [{"type": "custom-title", "customTitle": n} for n in names[1:]]
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in rows), encoding="utf-8")


root, projects = tmp / "root", tmp / "projects"
(root / ".fable-team").mkdir(parents=True)
for team in ("x", "f"):
    (root / "cards" / team / "진행").mkdir(parents=True)
    (root / "cards" / team / "진행" / f"c-{team}.md").write_text("# 진행\n", encoding="utf-8")
    (root / ".fable-team" / f"seats-{team}.json").write_text(json.dumps({"_cards": f"cards/{team}"}), encoding="utf-8")
seats = {"byz-x-master#1": ("2026-10-24T13:50:00", ["byz-x-master#1"]), "byz-x-nano#0": ("2026-10-24T13:51:00", ["byz-x-nano#0"]),
         "byz-f-master#2": ("2026-10-24T13:40:00", ["byz-f-master#1", "byz-f-master#2"])}
panes = []
for s, (end, names) in seats.items():
    cwd = f"/wt/{s.split('#')[0]}"
    jsonl(projects / enc(cwd) / f"{s.replace('#', '_')}.jsonl", names, end)
    panes.append(f"{s}\t{cwd}")
tmux = tmp / "tmux"
tmux.write_text("#!/bin/sh\ncat <<'EOF'\n" + "\n".join(panes) + "\nEOF\n", encoding="utf-8")
tmux.chmod(0o755)
os.environ.update(FT_TMUX=str(tmux), FT_CLAUDE_PROJECTS=str(projects), FT_NEWS_NOW="2026-10-24 14:00")
fh._sessions = lambda: list(seats)
live = fh.live_teams(root)
print("live =", json.dumps(live, ensure_ascii=False))
print("facts =", json.dumps(fh.facts(live, "모름"), ensure_ascii=False))
