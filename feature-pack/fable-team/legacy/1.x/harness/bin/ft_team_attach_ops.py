from __future__ import annotations

import json
import os
import plistlib
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from ft_team_lib import basis_ref, rosters, team_rel
from ft_team_attach_lib import AttachError, cards_path, command, directive_ok, origin_teamset_row, paths, safe, set_teamset_row, state_of, teamset_row, tick_status, tick_table, write
from ft_team_main_assign import ensure_team   # r1322 G5 — 새 팀 배정표 틀(render 와 같은 함수)

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
        cards = cards_path(root, doc)
        if not isinstance(doc, dict) or not all(k in doc for k in ("_master", "_cards", "_cards_wt")):
            lines.append("S3 어긋남 필수 칸")
            bad += 1
        elif not doc.get("_label"):
            lines.append("S3 어긋남 _label")
            bad += 1
        elif cards is None or not cards.is_dir():
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
    s6, s6ok = tick_status(root, team, p)
    lines.append(f"S6 {s6}")
    if s6ok is None:
        unknown += 1
    elif not s6ok:
        bad += 1
    return lines, bad, unknown

def apply_team(root: Path, team: str, own_tick: bool, fix_fields: bool, dry: bool) -> int:
    if state_of(root, team) != "현역":
        raise AttachError(f"REJECT {team} 현역 팀만 --apply 가능")
    pre = own_tick_precheck(root, team) if own_tick else None  # 쓰기 0 — 반쪽 상태 0(r1314)
    try:
        changed = int(ensure_team(root, team, dry))   # r1322 G5 — 새 팀 배정표 틀(있으면 무변경 · dry 면 쓰기 0)
    except OSError as e:
        raise AttachError(f"{team} ASSIGN.md 판정 불가 · {' '.join(str(e).split())[:120]}") from None
    p = paths(root, team, include_tick=own_tick)
    rel = team_rel(team, root).strip("/")
    changed += int(set_teamset_row(root, team, [team, "3", "0", "상시"], dry, keep_existing=True))
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
            row = f"{team}\t.\t{basis_ref(root)}\t{rel}/indices\n"   # r1309: 기준 ref = roots.tsv 칸(없으면 origin/main — 지금 동작)
            old = p["directive"].read_text(encoding="utf-8") if p["directive"].is_file() else ""
            changed += int(write(p["directive"], (old + row).encode(), dry))
    headline = p["tick"] / "HEADLINE.md"
    if not headline.exists():
        body = f"{datetime.now().strftime('%H:%M')} 헤드라인 없음 · {team} · 좌석 0\n"
        if not dry:
            headline.parent.mkdir(parents=True, exist_ok=True)
        changed += int(write(headline, body.encode(), dry))
    if own_tick:
        changed += own_tick_apply(root, team, p, dry, pre)
    return changed


def needs_publish(root: Path, team: str) -> bool:
    path, local = teamset_row(root, team)
    ref_exists, remote = origin_teamset_row(root, path, team)
    return local is not None and (not ref_exists or remote != local)

def own_tick_precheck(root: Path, team: str) -> tuple[dict[str, Any], Path, Path]:
    """--own-tick 사전 확인 — 템플릿(bin 안)·설치기·틱 표의 팀 행. 어느 하나라도 없으면 쓰기 전에 REJECT(r1314)."""
    template = HERE / "ft-tick-team.plist"
    if not template.is_file():
        raise AttachError(f"REJECT 팀 틱 템플릿 없음: {template}")
    try:
        doc = plistlib.loads(template.read_bytes())
    except (OSError, ValueError) as e:
        raise AttachError(f"REJECT 팀 틱 템플릿 읽기 실패 {template}: {e}") from None
    installer = HERE / "ft-tick-install.sh"
    if not installer.is_file():
        raise AttachError(f"REJECT 설치기 없음: {installer}")
    table = tick_table(root)
    rows = [line.rstrip("\n").split("\t") for line in table.read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")]
    if not any(row and row[0] == team for row in rows):
        raise AttachError(f"REJECT 팀 틱 행 없음 — 팩 kit/fable-team/bin/team-tick-env.tsv 에 {team} 행 추가 PR → 설치 → 다시 ({table})")
    return doc, table, installer

def own_tick_apply(root: Path, team: str, p: dict[str, Path], dry: bool, pre: tuple[dict[str, Any], Path, Path] | None) -> int:
    if dry:
        print(f"DRY --own-tick {team}")
        return 0
    if pre is None:
        raise AttachError(f"REJECT 사전 확인 없이 --own-tick: {team}")
    doc, table, installer = pre
    plist = p["plist"]
    before = plist.read_bytes() if plist.is_file() else None
    script = safe(root, Path(".fable-team/bin/ft-tick.sh"))
    rendered = p["tick"].parent / f".{team}-tick-rendered.plist"
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
    envp = {**os.environ, "FT_TICK_TEAM_TSV": str(table), "FT_TICK_PLIST_DIR": str(plist.parent)}
    rc, out, err = command("bash", str(installer), "--team", team, "--script", str(script), "--from", str(rendered), timeout=7, env=envp)
    rendered.unlink(missing_ok=True)
    if rc:
        if before is None:
            if plist.is_file():
                plist.rename(plist.with_name(plist.name + ".failed-" + datetime.now().strftime("%Y%m%d-%H%M%S")))
        elif plist.is_file() and plist.read_bytes() != before:
            plist.write_bytes(before)
        raise AttachError(f"ERROR ft-tick-install 실패 rc={rc}: {(err or out).strip()[:180]}")
    return int(before is None or plist.read_bytes() != before)

def notify_daily(root: Path, recipient: str, bad: int) -> None:
    """r1376 — 표식 1곳(<root>/.fable-team/state/team-attach-lint/<날>.sent) · 받는 이 = 보내기 직전 명부 _master · 실패 = 거절 줄 전체."""
    day = datetime.now().strftime("%F")
    marker = safe(root, Path(f".fable-team/state/team-attach-lint/{day}.sent"))
    if marker.exists():
        print(f"team-roster-lint already sent {day} ({marker})")
        return
    if bad:
        docs = [r["doc"] for r in rosters(root) if isinstance(r["doc"], dict) and r["doc"].get("_master")]
        to = next((str(d["_master"]) for d in docs if recipient == d["_master"] or recipient in d), recipient)
        if to != recipient:
            print(f"INFO 받는 이 명부 다시 읽음 {recipient} → {to}")
        mbox = os.environ.get("FT_MBOX_SH") or str(root / ".fable-team/comm/mbox.sh")
        body = f"[ft-team-attach->{to}] [정리] 팀 명부 어긋남 {bad} — --all --check 결과를 다시 확인해 주세요"
        rc, out, err = command("bash", mbox, "send", to, "ft-team-attach", body, timeout=7)
        if rc:
            rc, out, err = command("bash", mbox, "send", to, "ft-team-attach", body, timeout=7)
        if rc:   # WARN 줄은 싣지 않는다 — «REJECT» 로 시작하는 줄 전체(없으면 마지막 줄)
            lines = [x.strip() for x in f"{err}\n{out}".splitlines() if x.strip()]
            why = next((x for x in lines if x.startswith("REJECT")), lines[-1] if lines else "(출력 없음)")
            raise AttachError(f"NOTIFY-FAIL rc={rc} {why}")
    write(marker, (f"{day}\t{bad}\n").encode())
