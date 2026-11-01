#!/usr/bin/env python3
"""현역 팀의 파생 명부를 붙이고, 휴면·삭제 팀의 명부를 되돌릴 수 있게 뗀다."""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_team_lib import TeamPathError, team_names  # noqa: E402
from ft_team_attach_lib import AttachError, root_path, safe  # noqa: E402
from ft_team_attach_ops import apply_team, check_team, needs_publish, notify_daily  # noqa: E402
from ft_team_attach_state import detach, revert  # noqa: E402

def main(argv: list[str]) -> int:
    if not argv:
        print("usage: ft-team-attach.sh (<팀>|--all) --check|--apply|--detach|--revert <스냅샷>", file=sys.stderr)
        return 2
    try:
        root = root_path()
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
                rows, nbad, nunknown = check_team(root, t)
                bad += nbad
                unknown += nunknown
                print(f"{t} " + " · ".join(rows))
            if team == "--all":
                known = set(team_names(root, "전체"))
                extras = sorted(p.stem.removeprefix("seats-") for p in (root / ".fable-team").glob("seats-*.json") if p.stem.removeprefix("seats-") not in known)
                if extras:
                    print(f"명단 밖 파생 {len(extras)}: " + ",".join(extras))
                    bad += len(extras)
            print(f"SUMMARY mismatch={bad} unknown={unknown}")
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
