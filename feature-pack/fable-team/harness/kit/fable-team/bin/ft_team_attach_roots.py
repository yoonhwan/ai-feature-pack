#!/usr/bin/env python3
"""r1309 — 루트 하나의 launchd plist 2장(틱·stall-scan) «렌더·덮기 전 사본·되돌림» (기획 3184 §3-5·§3-6·§3-7·§3-10).

env: FT_ROOTS_TSV(기계 루트 명부) · FT_TICK_PLIST_DIR(plist 폴더 · 기본 ~/Library/LaunchAgents) · FT_TICK_LAUNCHCTL(launchctl 자리 · 시험 스텁).
"""
from __future__ import annotations

import hashlib
import json
import os
import plistlib
import time
from datetime import datetime
from pathlib import Path
from typing import Any

from ft_team_lib import roots, roots_tsv
from ft_team_attach_lib import AttachError, command
from ft_tick_lock import LOCK_ENVS, labels, lock_conflicts, plist_dir, root_lock

HERE = Path(__file__).resolve().parent
def _row_checked(base: Path, name: str) -> tuple[dict[str, Any], dict[str, str]]:
    """roots.tsv 그 루트 행 + 잠금 경로 3개 — 행 없음·경로 불일치·스크립트 없음 = 3(판정 불가)."""
    row = next((r for r in roots() if r["name"] == name), None)
    if row is None:
        raise AttachError(f"ERROR 루트 명부 판정 불가: {name} 행이 없다({roots_tsv()})", 3)
    if Path(str(row["path"])).resolve() != Path(base).resolve():
        raise AttachError(f"ERROR 루트 명부 판정 불가: {name} 경로가 {row['path']} 인데 렌더 대상이 {base}", 3)
    for script in (base / ".fable-team/bin/ft-tick.sh", base / ".fable-team/bin/ft-stall-scan.sh"):
        if not script.is_file():
            raise AttachError(f"ERROR 루트 설치 전 — 스크립트가 없다: {script}", 3)
    return row, root_lock(name, row)


def _docs(base: Path, name: str) -> dict[str, dict[str, Any]]:
    _row, lock = _row_checked(base, name)
    common = {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin", "FT_ROOT": str(base)}
    tick, stall = labels(name)
    comm = base / ".fable-team/comm"
    tick_env = {**common, **lock, "FT_TICK_SEATS": _seats(base),
                "FT_TICK_MBOX": str(comm / "mbox.sh"), "FT_MBOX_DIR": str(comm), "FT_TICK_AGENT_ALIVE": str(comm / "ft-agent-alive.sh")}
    stall_env = {**common, "FT_MBOX_SH": str(comm / "mbox.sh"), "FT_MBOX_DIR": str(comm)}
    return {
        tick: {"Label": tick, "ProgramArguments": ["/bin/bash", str(base / ".fable-team/bin/ft-tick.sh")], "WorkingDirectory": str(base),
               "RunAtLoad": True, "KeepAlive": True, "StandardOutPath": f"/tmp/ft-tick-{name}.log",
               "StandardErrorPath": f"/tmp/ft-tick-{name}.log", "EnvironmentVariables": tick_env},
        stall: {"Label": stall, "ProgramArguments": ["/opt/homebrew/bin/bash", str(base / ".fable-team/bin/ft-stall-scan.sh")],
                "WorkingDirectory": str(base), "StartInterval": 120, "RunAtLoad": False,
                "StandardOutPath": f"/tmp/ft-stall-scan-{name}.log", "StandardErrorPath": f"/tmp/ft-stall-scan-{name}.log",
                "EnvironmentVariables": stall_env},
    }


def _seats(base: Path) -> str:
    rc, out, _err = command("python3", str(HERE / "ft_team_lib.py"), "seats-file", str(base))
    return out.strip() if rc == 0 and out.strip() else str(base / ".fable-team/seats.json")


def render(name: str, base: Path, dry: bool = False) -> list[Path]:
    """루트 틱·stall-scan plist 를 렌더한다 — 덮기 전 사본을 먼저 남기고(삭제 0), 잠금 경로가 겹치면 쓰기 0 REJECT."""
    docs = _docs(base, name)
    tick = labels(name)[0]
    missing = [k for k in LOCK_ENVS if not docs[tick]["EnvironmentVariables"].get(k)]
    if missing:
        raise AttachError(f"REJECT 루트 틱 plist 에 잠금 경로가 없다: {','.join(missing)}")
    folder = plist_dir(base)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    snap = base / ".fable-team/state/root-attach" / f"{stamp}-{name}"
    written: list[Path] = []
    plan = [(label, folder / f"{label}.plist", plistlib.dumps(doc, fmt=plistlib.FMT_XML)) for label, doc in docs.items()]
    for label, target, data in plan:
        if label == tick:
            bad = lock_conflicts(docs[tick]["EnvironmentVariables"], folder, skip=target if target.exists() else None)
            if bad:
                raise AttachError("REJECT 루트 틱 잠금 경로 중복: " + " · ".join(bad))
        if not dry:
            if target.is_file():
                before = target.read_bytes()
                (snap / "before").mkdir(parents=True, exist_ok=True)
                (snap / "before" / f"{label}.plist").write_bytes(before)
            folder.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        written.append(target)
        print(("DRY " if dry else "RENDERED ") + str(target))
    if not dry:
        snap.mkdir(parents=True, exist_ok=True)
        manifest = {"root": name, "stamp": stamp, "snapshot": str(snap), "restored": False,
                    "files": [{"label": label, "path": str(target),
                               "before_exists": (snap / "before" / f"{label}.plist").is_file(),
                               "before_sha": _sha(snap / "before" / f"{label}.plist") if (snap / "before" / f"{label}.plist").is_file() else None,
                               "after_sha": _sha_bytes(data)} for label, target, data in plan]}
        (snap / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"SNAPSHOT {snap} files={len(plan)} 삭제=0")
    return written


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _loaded(label: str, lc: str) -> tuple[bool, str]:
    rc, out, err = command(lc, "print", f"gui/{os.getuid()}/{label}")
    if rc == 0:
        return True, out
    return (False, "") if "Could not find service" in out + err or "not find" in out + err else (False, f"판정 불가 rc={rc}")


def _wait_gone(label: str, lc: str, budget: float = 7.0) -> str:
    """bootout 뒤 «정말 내려갔는지» 확인 — print 가 실패할 때까지 0.2초 간격(7초 룰). 안 내려가면 ERROR 1줄."""
    end = time.monotonic() + budget
    while time.monotonic() < end:
        loaded, why = _loaded(label, lc)
        if why:
            return why
        if not loaded:
            return ""
        time.sleep(0.2)
    return f"bootout 뒤에도 적재 상태({label})"


def revert(name: str, snapshot: Path | None = None, base: Path | None = None) -> int:
    """덮기 전 사본으로 되돌린다 — 복원 → bootout → «내려간 것» 확인 → bootstrap(§3-6). 두 번째 되돌림 = REJECT."""
    lc = os.environ.get("FT_TICK_LAUNCHCTL", "launchctl")
    if base is None:
        row = next((r for r in roots() if r["name"] == name), None)
        if row is None:
            raise AttachError(f"ERROR 루트 명부 판정 불가: {name} 행이 없다({roots_tsv()})", 3)
        base = Path(str(row["path"]))
    if snapshot is None:
        folder = base / ".fable-team/state/root-attach"
        snaps = sorted(p for p in folder.glob(f"*-{name}") if (p / "manifest.json").is_file()) if folder.is_dir() else []
        if not snaps:
            raise AttachError(f"ERROR 되돌림 판정 불가: 사본 없음({folder}/*-{name})", 3)
        snapshot = snaps[-1]
    data = json.loads((snapshot / "manifest.json").read_text(encoding="utf-8"))
    if data.get("restored"):
        raise AttachError(f"REJECT 이미 되돌린 사본: {snapshot}")
    stamp = str(data.get("stamp") or datetime.now().strftime("%Y%m%d-%H%M%S"))
    for item in data.get("files", []):
        target = Path(item["path"])
        if target.is_file() and _sha(target) != item["after_sha"]:
            raise AttachError(f"REJECT 되돌림 전 sha256 불일치: {target}")
        if item["before_exists"]:
            before = snapshot / "before" / f"{item['label']}.plist"
            if _sha(before) != item["before_sha"]:
                raise AttachError(f"REJECT 사본 sha256 불일치: {before}")
    for item in data.get("files", []):
        label, target = item["label"], Path(item["path"])
        loaded, why = _loaded(label, lc)
        if why:
            raise AttachError(f"ERROR launchctl 판정 불가({label}): {why}", 3)
        if loaded:
            rc, out, err = command(lc, "bootout", f"gui/{os.getuid()}/{label}")
            if rc:
                raise AttachError(f"ERROR launchctl bootout 실패 rc={rc}: {(err or out).strip()[:120]}")
            why = _wait_gone(label, lc)
            if why:
                raise AttachError(f"ERROR bootout 확인 실패({label}): {why}")
        if item["before_exists"]:
            target.write_bytes((snapshot / "before" / f"{label}.plist").read_bytes())
            rc, out, err = command(lc, "bootstrap", f"gui/{os.getuid()}", str(target))
            if rc:
                raise AttachError(f"ERROR launchctl bootstrap 실패 rc={rc}: {(err or out).strip()[:120]}")
        elif target.is_file():                       # 처음에 없던 plist = 옮긴다(삭제 0)
            target.replace(target.with_name(target.name + f".disabled-{stamp}"))
    data["restored"] = True
    data["restored_at"] = datetime.now().isoformat(timespec="seconds")
    (snapshot / "manifest.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"REVERT {name} 사본 복원 · bootout→확인→bootstrap · 삭제=0 (snapshot={snapshot})")
    return 0
