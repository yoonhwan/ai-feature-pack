#!/usr/bin/env python3
"""현역 팀의 파생 명부를 붙이고, 휴면·삭제 팀의 명부를 되돌릴 수 있게 뗀다."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_team_lib import RootsError, TeamPathError, roots, roots_info, team_names  # noqa: E402
from ft_team_attach_lib import AttachError, root_path, safe  # noqa: E402
from ft_team_attach_ops import apply_team, check_team, needs_publish, notify_daily  # noqa: E402
from ft_team_attach_roots import render as render_root_plists, revert as revert_root_plists  # noqa: E402
from ft_tick_lock import plist_dir  # noqa: E402
from ft_team_attach_state import detach, revert  # noqa: E402


def _other_roots(root: Path) -> list[tuple[str, Path]]:
    """roots.tsv 의 «다른 현역 루트» (이름, 경로) — 명부 판정 불가는 빈 목록(지금 동작)."""
    me = Path(root).resolve()
    try:
        return [(str(r["name"]), Path(str(r["path"]))) for r in roots()
                if r["state"] == "현역" and Path(str(r["path"])).resolve() != me]
    except (RootsError, OSError):
        return []


def _extra_rows(root: Path) -> tuple[list[str], list[str]]:
    """명단 밖 파생 → (다른 루트 몫 목록(OK), 정말 명단 밖 목록).
    r1309 X3: 그 팀의 ft-tick plist ProgramArguments 가 다른 현역 루트 아래를 가리키면 «다른 루트 틱 OK» ·
    plist 가 있는데 다른 경로(옛 사본)를 가리키면 «어긋남»(명단 밖과 같은 bad 로 센다)."""
    known = set(team_names(root, "전체"))
    extras = sorted(p.stem.removeprefix("seats-") for p in (root / ".fable-team").glob("seats-*.json") if p.stem.removeprefix("seats-") not in known)
    others, stray = [], []
    for team in extras:
        plist = plist_dir(root) / f"com.byz.ft-tick-{team}.plist"
        if not plist.is_file():
            (others if team in {n for n, _p in _other_roots(root)} else stray).append(team)
            continue
        script = _program(plist)
        under = next((n for n, p in _other_roots(root) if script and _within(script, p)), None)
        if under:
            others.append(team)
        else:
            print(f"어긋남 {team} — plist ProgramArguments 가 다른 현역 루트 아래가 아니다({script or '비었음'})")
            stray.append(team)
    return others, stray


def _program(plist: Path) -> str:
    import plistlib
    try:
        doc = plistlib.loads(plist.read_bytes())
    except (OSError, ValueError):
        return ""
    args = doc.get("ProgramArguments") if isinstance(doc, dict) else None
    return str(args[-1]) if isinstance(args, list) and args else ""


def _within(script: str, base: Path) -> bool:
    try:
        Path(script).resolve().relative_to(Path(base).resolve())
    except ValueError:
        return False
    return True

def main(argv: list[str]) -> int:
    if not argv:
        print("usage: ft-team-attach.sh (<팀>|--all) --check|--apply|--detach|--revert <스냅샷>", file=sys.stderr)
        return 2
    try:
        root = root_path()
        if argv[0] in ("--root-render", "--root-revert"):   # r1309: 루트 plist 렌더(잠금 3개 필수·중복 REJECT·덮기 전 사본)·되돌림(bootout→확인→bootstrap)
            if len(argv) < 2:
                print("usage: ft-team-attach.sh --root-render|--root-revert <루트이름> [<사본폴더>] [--dry-run]", file=sys.stderr)
                return 2
            rows = roots()
            row = next((r for r in rows if str(r["name"]) == argv[1]), None)
            if row is None:
                raise AttachError(f"ERROR 루트 명부 판정 불가: {argv[1]} 행이 없다", 3)
            name, base = str(row["name"]), Path(str(row["path"]))
            if argv[0] == "--root-render":
                render_root_plists(name, base, dry="--dry-run" in argv[2:])
                return 0
            return revert_root_plists(name, Path(argv[2]) if len(argv) > 2 and not argv[2].startswith("--") else None, base)
        if argv[0] == "--revert":
            if len(argv) < 2:
                print("usage: ft-team-attach.sh --revert <스냅샷>", file=sys.stderr)
                return 2
            return revert(root, safe(root, Path(argv[1])))
        actions = ("--check", "--apply", "--detach")
        if argv[0] in actions and len(argv) > 1:
            action, team, rest = argv[0], argv[1], argv[2:]
        else:
            team, action, rest = argv[0], argv[1] if len(argv) > 1 else "", argv[2:]
        opts = set(rest)
        own_tick = "--own-tick" in opts
        fix_fields = "--fix-fields" in opts
        dry = "--dry-run" in opts
        notify = argv[argv.index("--notify") + 1] if "--notify" in argv else None
        teams = team_names(root) if team == "--all" else [team]
        if team != "--all" and team not in team_names(root, "전체"):
            raise AttachError(f"ERROR 팀 명단 판정 불가: {team}", 3)
        if action == "--check":
            bad = unknown = 0
            for t in teams:
                try:
                    rows, nbad, nunknown = check_team(root, t)
                except AttachError as e:
                    print(f"{t} 판정 불가({str(e).removeprefix('ERROR ')})")
                    unknown += 1
                    continue
                bad += nbad
                unknown += nunknown
                print(f"{t} " + " · ".join(rows))
            if team == "--all":
                others, stray = _extra_rows(root)   # r1309 X3: plist ProgramArguments 가 다른 현역 루트 아래면 «다른 루트 틱 OK»
                if others:
                    print(f"다른 루트 틱 OK {len(others)}: " + ",".join(others))
                if stray:
                    print(f"명단 밖 파생 {len(stray)}: " + ",".join(stray))
                    bad += len(stray)
            print(f"SUMMARY mismatch={bad} unknown={unknown}")
            try:
                print(roots_info())   # r1309 X2: 루트 명부 없음 = «INFO 루트 명부 없음» + 지금 동작 그대로
            except RootsError as e:
                print(f"{e}")
            if notify:
                notify_daily(root, notify, bad)
            return 3 if unknown else 1 if bad else 0
        if action == "--apply":
            n = sum(apply_team(root, t, own_tick, fix_fields, dry) for t in teams)
            print(f"APPLY 팀={len(teams)} 변경={n}")
            pending = [t for t in teams if needs_publish(root, t)]
            if pending:
                print(f"TEAMSET.md 행 {' '.join(pending)} 는 커밋·push 전까지 상한 판정 불가(rc3)")
            return 0
        if action == "--detach" and team != "--all":
            return detach(root, team)
        print("usage: ft-team-attach.sh (<팀>|--all) --check|--apply|--detach|--revert <스냅샷>", file=sys.stderr)
        return 2
    except AttachError as e:
        print(str(e))
        return e.rc
    except (OSError, ValueError, TeamPathError) as e:
        print(f"ERROR 팀 명단 판정 불가: {e}")
        return 3

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
