from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime
from pathlib import Path

from ft_team_attach_lib import AttachError, command, digest, paths, safe, set_teamset_row, state_of, write

def tree_digest(path: Path) -> str:
    h = hashlib.sha256()
    if path.is_dir():
        for file in sorted(p for p in path.rglob("*") if p.is_file()):
            h.update(str(file.relative_to(path)).encode())
            h.update(file.read_bytes())
    else:
        h.update(path.read_bytes())
    return h.hexdigest()

def replace_tsv(path: Path, team: str, remove: bool) -> bytes:
    before = path.read_bytes() if path.exists() else b""
    lines = before.decode("utf-8").splitlines(keepends=True)
    if remove:
        lines = [line for line in lines if line.startswith("#") or not line.split("\t", 1)[0] == team]
    return before if not remove else ("".join(lines)).encode()

def move_record(src: Path, dst: Path) -> dict[str, str]:
    if not src.exists():
        return {}
    if dst.exists():
        raise AttachError(f"REJECT 되돌림 대상이 이미 있다: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    info = {"src": str(src), "dst": str(dst), "sha256": tree_digest(src)}
    os.replace(src, dst)
    return info

def detach(root: Path, team: str) -> int:
    state = state_of(root, team)
    if state == "현역":
        raise AttachError(f"REJECT 현역 팀은 --detach 할 수 없다: {team}")
    p = paths(root, team)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    snap = safe(root, Path(f".fable-team/state/team-attach/{stamp}-{team}"))
    if snap.exists():
        raise AttachError(f"REJECT 스냅샷이 이미 있다: {snap}")
    snap.mkdir(parents=True)
    teamset = safe(root, Path(os.environ.get("FT_TEAMSET_MD") or "design/TEAMSET.md"))
    directive_before = p["directive"].read_bytes() if p["directive"].exists() else b""
    tsv_before = p["team_tsv"].read_bytes() if p["team_tsv"].exists() else b""
    teamset_before = teamset.read_bytes() if teamset.exists() else b""
    (snap / "directive.before").write_bytes(directive_before)
    (snap / "team-tick.before").write_bytes(tsv_before)
    (snap / "TEAMSET.before").write_bytes(teamset_before)
    manifest = {"team": team, "stamp": stamp, "snapshot": str(snap), "moved": [],
                "teamset": str(teamset), "teamset_before_exists": teamset.exists(),
                "teamset_before_sha": hashlib.sha256(teamset_before).hexdigest(),
                "directive": str(p["directive"]), "directive_before_exists": p["directive"].exists(),
                "directive_before_sha": hashlib.sha256(directive_before).hexdigest(),
                "tick_tsv": str(p["team_tsv"]), "tick_tsv_before_exists": p["team_tsv"].exists(),
                "tick_tsv_before_sha": hashlib.sha256(tsv_before).hexdigest(), "plist_loaded": False, "restored": False}
    manifest_path = snap / "manifest.json"
    write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    moved = []
    retired = root / ".fable-team/retired"
    seats_dst = retired / f"{p['seats'].name}.{stamp}"
    tick_dst = root / ".fable-team/state/retired" / f"{team}-tick.{stamp}"
    for src, dst in ((p["seats"], seats_dst), (p["tick"], tick_dst)):
        item = move_record(src, dst)
        if item:
            moved.append(item)
            manifest["moved"] = moved
            write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    launchctl = os.environ.get("FT_TICK_LAUNCHCTL", "launchctl")
    loaded = False
    plist = p["plist"]
      tsv_rows = [line.rstrip("\n").split("\t") for line in p["team_tsv"].read_text(encoding="utf-8").splitlines()
                  if line and not line.startswith("#")] if p["team_tsv"].is_file() else []
      configured = plist.exists() or any(row and row[0] == team for row in tsv_rows)
      disabled = plist.with_name(plist.name + f".disabled-{stamp}")
      if configured:
          rc, out, err = command(launchctl, "list")
          if rc:
              raise AttachError(f"ERROR launchctl 판정 불가 rc={rc}: {(err or out).strip()[:120]}", 3)
          labels = {line.split()[-1] for line in out.splitlines() if line.split()}
          loaded = f"com.byz.ft-tick-{team}" in labels
        manifest["plist_loaded"] = loaded
        write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
          if plist.exists() and disabled.exists():
              raise AttachError(f"REJECT disabled plist 가 이미 있다: {disabled}")
        if loaded:
              rc, out, err = command(launchctl, "bootout", f"gui/{os.getuid()}/com.byz.ft-tick-{team}")
            if rc:
                raise AttachError(f"ERROR launchctl bootout 실패 rc={rc}: {(err or out).strip()[:120]}")
          if plist.exists():
              item = move_record(plist, disabled)
              if item:
                  moved.append(item)
                  manifest["moved"] = moved
                  write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    if teamset.exists():
        set_teamset_row(root, team, [team, "0", "0", f"휴면 {stamp}"])
    if p["team_tsv"].exists():
        replace_tsv(p["team_tsv"], team, True)
        text = "".join(line for line in p["team_tsv"].read_text(encoding="utf-8").splitlines(keepends=True)
                       if line.startswith("#") or line.split("\t", 1)[0] != team)
        write(p["team_tsv"], text.encode())
    if p["directive"].exists():
        text = "".join(line for line in p["directive"].read_text(encoding="utf-8").splitlines(keepends=True)
                       if line.startswith("#") or line.split("\t", 1)[0] != team)
        write(p["directive"], text.encode())
    manifest.update({"moved": moved, "teamset_after_sha": digest(teamset) if teamset.exists() else None,
                     "directive_after_sha": digest(p["directive"]) if p["directive"].exists() else None,
                     "tick_tsv_after_sha": digest(p["team_tsv"]) if p["team_tsv"].exists() else None})
    write(manifest_path, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())
    print(f"DETACH {team} snapshot={snap} moved={len(manifest['moved'])} 삭제=0")
    return 0

def revert(root: Path, path: Path) -> int:
    manifest_path = path / "manifest.json" if path.is_dir() else path
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if data.get("restored"):
        raise AttachError(f"REJECT 이미 복원된 스냅샷: {manifest_path}")
    for key, after_key in (("teamset", "teamset_after_sha"), ("directive", "directive_after_sha"), ("tick_tsv", "tick_tsv_after_sha")):
        target = safe(root, Path(data[key]))
        expected = data.get(after_key)
        if expected is not None and (not target.is_file() or digest(target) != expected):
            raise AttachError(f"REJECT 복원 전 sha256 불일치: {target}")
        if expected is None and target.exists():
            raise AttachError(f"REJECT 복원 전 경로가 비어 있지 않다: {target}")
    moved = data.get("moved", [])
    for item in moved:
        src, dst = safe(root, Path(item["src"])), safe(root, Path(item["dst"]))
        if not dst.exists() or src.exists() or tree_digest(dst) != item["sha256"]:
            raise AttachError(f"REJECT 복원 파일 sha256·경로 불일치: {dst}")
    for item in reversed(moved):
        src, dst = safe(root, Path(item["src"])), safe(root, Path(item["dst"]))
        src.parent.mkdir(parents=True, exist_ok=True)
        os.replace(dst, src)
    snap = manifest_path.parent
    for key, backup, exists_key in (("teamset", "TEAMSET.before", "teamset_before_exists"),
                                    ("directive", "directive.before", "directive_before_exists"),
                                    ("tick_tsv", "team-tick.before", "tick_tsv_before_exists")):
        target = safe(root, Path(data[key]))
        before = (snap / backup).read_bytes()
        if data[exists_key]:
            write(target, before)
        elif target.exists():
            moved_file = snap / f"{backup}.after"
            if moved_file.exists():
                raise AttachError(f"REJECT 복원 보관 경로가 이미 있다: {moved_file}")
            os.replace(target, moved_file)
    if data.get("plist_loaded"):
        plist = next((Path(m["src"]) for m in data.get("moved", []) if Path(m["src"]).suffix == ".plist"), None)
        if plist:
            rc, out, err = command(os.environ.get("FT_TICK_LAUNCHCTL", "launchctl"), "bootstrap", f"gui/{os.getuid()}", str(plist))
            if rc:
                raise AttachError(f"ERROR launchctl bootstrap 실패 rc={rc}: {(err or out).strip()[:120]}")
    data["restored"] = True
    data["restored_at"] = datetime.now().isoformat(timespec="seconds")
    write(manifest_path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode())
    print(f"REVERT {data['team']} sha256 일치 · 삭제=0")
    return 0
