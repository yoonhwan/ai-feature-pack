from __future__ import annotations

import json
import os
import plistlib
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from ft_team_lib import team_rel
from ft_team_attach_lib import AttachError, command, directive_ok, origin_teamset_row, paths, safe, set_teamset_row, state_of, teamset_row, tick_status, write

HERE = Path(__file__).resolve().parent

def check_team(root: Path, team: str) -> tuple[list[str], int, int]:
    state_of(root, team)
    p = paths(root, team)
    rel = team_rel(team, root).strip("/")
    lines, bad, unknown = [], 0, 0
    local_file, local = teamset_row(root, team)
    if local is None:
        lines.append(f"S2 빠짐 {local_file}")
        bad += 1
    else:
        ref_exists, remote = origin_teamset_row(root, local_file, team)
        if ref_exists and remote != local:
            lines.append("S2 커밋·push 대기")
            bad += 1
        else:
            lines.append("S2 OK")
    try:
        doc = json.loads(p["seats"].read_text(encoding="utf-8"))
    except FileNotFoundError:
        lines.append("S3 빠짐 seats")
        bad += 1
    except (OSError, ValueError) as e:
        lines.append(f"S3 판정 불가(JSON {type(e).__name__})")
        unknown += 1
    else:
        expected = {"_label": team, "_cards": f"{rel}/indices"}
        diff = [k for k, v in expected.items() if doc.get(k) not in (v, "")] if isinstance(doc, dict) else ["JSON"]
        if not isinstance(doc, dict) or not all(k in doc for k in ("_master", "_cards", "_cards_wt")) or diff:
            lines.append("S3 어긋남 " + ",".join(diff or ["필수 칸"]))
            bad += 1
        elif not p["cards"].is_dir():
            lines.append("S3 어긋남 폴더 없음")
            bad += 1
        else:
            lines.append("S3 OK")
    if directive_ok(root, team, rel, p["directive"]):
        lines.append("S4 OK")
    else:
        lines.append("S4 빠짐 directive-roots.tsv")
        bad += 1
    headline = p["tick"] / "HEADLINE.md"
    if not headline.is_file():
        lines.append("S5 빠짐 HEADLINE.md")
        bad += 1
    elif not re.match(r"^\d{2}:\d{2}", headline.read_text(encoding="utf-8").splitlines()[0] if headline.stat().st_size else ""):
        lines.append("S5 어긋남 HEADLINE.md")
        bad += 1
    else:
        lines.append("S5 OK")
    s6, ok = tick_status(root, team, p)
    lines.append(f"S6 {s6}")
    if not ok:
        bad += 1
    return lines, bad, unknown

def apply_team(root: Path, team: str, own_tick: bool, fix_fields: bool, dry: bool) -> int:
    if state_of(root, team) != "현역":
        raise AttachError(f"REJECT {team} 현역 팀만 --apply 가능")
    p = paths(root, team)
    rel = team_rel(team, root).strip("/")
    changed = 0
    changed += int(set_teamset_row(root, team, [team, "3", "0", "상시"], dry))
    if p["seats"].is_file():
        try:
            doc = json.loads(p["seats"].read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            raise AttachError(f"REJECT 명부 JSON 실패 {p['seats']}: {e}") from None
        if fix_fields:
            for key, value in (("_label", team), ("_cards", f"{rel}/indices"), ("_cards_wt", "")):
                if not doc.get(key):
                    doc[key] = value
    else:
        doc = {"_label": team, "_master": "", "_cards": f"{rel}/indices", "_cards_wt": "", "_doc": "ft-team-attach r1298"}
    if not p["seats"].is_file() or fix_fields:
        changed += int(write(p["seats"], (json.dumps(doc, ensure_ascii=False, indent=2) + "\n").encode(), dry))
    if not directive_ok(root, team, rel, p["directive"]):
        if not rel.startswith("design/teams/"):
            row = f"{team}\t.\torigin/main\t{rel}/indices\n"
            old = p["directive"].read_text(encoding="utf-8") if p["directive"].is_file() else ""
            changed += int(write(p["directive"], (old + row).encode(), dry))
    headline = p["tick"] / "HEADLINE.md"
    if not headline.exists():
        body = f"{datetime.now().strftime('%H:%M')} 헤드라인 없음 · {team} · 좌석 0\n"
        if not dry:
            headline.parent.mkdir(parents=True, exist_ok=True)
        changed += int(write(headline, body.encode(), dry))
    if own_tick:
        changed += own_tick_apply(root, team, p, dry)
    return changed


def needs_publish(root: Path, team: str) -> bool:
    path, local = teamset_row(root, team)
    ref_exists, remote = origin_teamset_row(root, path, team)
    return local is not None and (not ref_exists or remote != local)

def own_tick_apply(root: Path, team: str, p: dict[str, Path], dry: bool) -> int:
    if dry:
        print(f"DRY --own-tick {team}")
        return 0
    tsv = p["team_tsv"]
    text = tsv.read_text(encoding="utf-8") if tsv.is_file() else ""
    exists = any(line.split("\t", 1)[0] == team for line in text.splitlines() if line and not line.startswith("#"))
    changed = 0
    if not exists:
        off = "FT_TICK_MAGAZINE,FT_TICK_LAUNCHD,FT_TICK_DRIFT,FT_TICK_RAISED,FT_TICK_RENAMED,FT_TICK_WT_SWEEP,FT_TICK_NEWS_LEDGER,FT_TICK_NEWS_WATCH,FT_TICK_AUTONOMY"
        row = f"{team}\t{p['seats'].name}\t/tmp/ft-tick-state-{team}\t/tmp/ft-tick-{team}.pid\t/tmp/ft-tick-{team}-\t{off}\tFT_TICK_FIRE_V2=1\n"
        write(tsv, (text + row).encode())
        changed = 1
    template = HERE.parent / "kit/launchd/com.byz.ft-tick-team.plist.template"
    script = safe(root, Path(".fable-team/bin/ft-tick.sh"))
    installer = HERE / "ft-tick-install.sh"
    rendered = p["tick"].parent / f".{team}-tick-rendered.plist"
    doc = plistlib.loads(template.read_bytes())
    values = {
        "__TEAM__": team,
        "__MASTER_MSG__": f"[cron-tick · 팀 master] {team} 팀 점검",
        "__PM_MSG__": f"[cron-tick · 팀 PM] {team} 팀 점검",
        "__SEATS__": str(p["seats"]),
        "__SCRIPT__": str(script),
    }
    def render(value: Any) -> Any:
        if isinstance(value, str):
            for token, replacement in values.items():
                value = value.replace(token, replacement)
            return value
        if isinstance(value, list):
            return [render(item) for item in value]
        if isinstance(value, dict):
            return {key: render(item) for key, item in value.items()}
        return value
    doc = render(doc)
    doc["WorkingDirectory"] = str(root)
    env = doc.setdefault("EnvironmentVariables", {})
    comm = root / ".fable-team/comm"
    env.update({"FT_ROOT": str(root), "FT_TICK_SEATS": str(p["seats"]), "FT_TICK_MBOX": str(comm / "mbox.sh"),
                "FT_MBOX_DIR": str(comm), "FT_TICK_AGENT_ALIVE": str(comm / "ft-agent-alive.sh")})
    rendered.parent.mkdir(parents=True, exist_ok=True)
    rendered.write_bytes(plistlib.dumps(doc, fmt=plistlib.FMT_XML))
    envp = {**os.environ, "FT_TICK_TEAM_TSV": str(tsv), "FT_TICK_PLIST_DIR": str(p["plist"].parent)}
    rc, out, err = command("bash", str(installer), "--team", team, "--script", str(script), "--from", str(rendered), timeout=7, env=envp)
    rendered.unlink(missing_ok=True)
    if rc:
        raise AttachError(f"ERROR ft-tick-install 실패 rc={rc}: {(err or out).strip()[:180]}")
    return changed

def notify_daily(root: Path, recipient: str, bad: int) -> None:
    day = datetime.now().strftime("%F")
    marker = safe(root, Path(f".fable-team/state/team-attach-lint/{day}.sent"))
    if marker.exists():
        return
    if bad:
        mbox = os.environ.get("FT_MBOX_SH") or str(root / ".fable-team/comm/mbox.sh")
        body = f"[ft-team-attach->{recipient}] [정리] 팀 명부 어긋남 {bad} — --all --check 결과를 다시 확인해 주세요"
        rc, out, err = command("bash", mbox, "send", recipient, "ft-team-attach", body, timeout=7)
        if rc:
            rc, out, err = command("bash", mbox, "send", recipient, "ft-team-attach", body, timeout=7)
        if rc:
            raise AttachError(f"ERROR 팀 명부 알림 전송 실패 rc={rc}: {(err or out).strip()[:160]}")
    write(marker, (f"{day}\t{bad}\n").encode())
