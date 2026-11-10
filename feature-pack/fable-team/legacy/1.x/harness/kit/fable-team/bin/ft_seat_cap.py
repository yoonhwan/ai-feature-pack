#!/usr/bin/env python3
"""ft_seat_cap.py --root <ROOT> — 좌석 상한 검사 (R252 · 판정 1949 · ft-nano-spawn.sh 가 세션 열기 «전» 부른다 · 읽기 전용).

env: FT_NANO_PREFIX(`byz-<팀>-nano-`) · FT_TEAM_SEAT_CAP(그 팀 나노 tmux 세션 수 상한 · r666: 나노만 센다 — 팀장·은퇴 팀장 화면은 안 센다) · FT_GROUP_SEAT_CAP(명부 `_parent` 가 같은 팀들의 나노 합) · FT_SEATS_JSON.
두 상한 env 가 다 없으면 검사 0(다른 팀) · rc0 · 출력 0. 통과 rc0 · 거절 `REJECT …` rc1 · 못 세면 `ERROR …` rc1 (조용한 통과 0).
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


def die(kind: str, msg: str) -> NoReturn:
    print(f"{kind} {msg}")
    sys.exit(1)


def cap_of(name):
    raw = os.environ.get(name, "")
    if not raw:
        return None
    if not raw.isdigit() or int(raw) < 1:
        die("ERROR", f"{name}={raw!r} 는 1 이상 정수여야 한다")
    return int(raw)


def sessions():
    try:
        r = subprocess.run(["tmux", "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        die("ERROR", f"tmux 세션 목록 실패({e}) — 좌석 상한을 셀 수 없다")
    if r.returncode:
        if re.search(r"no server|error connecting", r.stderr):
            return []
        die("ERROR", f"tmux list-sessions 실패: {r.stderr.strip()[:80]} — 좌석 상한을 셀 수 없다")
    return r.stdout.split()


def count(names, team):
    # r666: 나노만 센다(팀장·은퇴 팀장 화면·tester etc 제외) — 팀셋 ft_teamset.py 와 같은 접두 기준
    return sum(1 for s in names if s.startswith(f"byz-{team}-nano-"))


def group_teams(root, parent):
    out = []
    for f in sorted((Path(root) / ".fable-team").glob("seats-*.json")):
        try:
            if json.loads(f.read_text(encoding="utf-8")).get("_parent") == parent:
                out.append(f.stem.removeprefix("seats-"))
        except (OSError, ValueError) as e:
            die("ERROR", f"명부 읽기 실패 {f.name}: {e}")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    root = ap.parse_args().root
    team_cap, group_cap = cap_of("FT_TEAM_SEAT_CAP"), cap_of("FT_GROUP_SEAT_CAP")
    if team_cap is None and group_cap is None:
        return
    m = re.fullmatch(r"byz-([a-z0-9]+)-nano-", os.environ.get("FT_NANO_PREFIX", ""))
    if not m:
        die("ERROR", f"FT_NANO_PREFIX={os.environ.get('FT_NANO_PREFIX', '')!r} 에서 팀을 못 읽는다 (byz-<팀>-nano-)")
    team, names = m.group(1), sessions()
    if team_cap is not None and count(names, team) >= team_cap:
        die("REJECT", f"좌석 상한 {team} {count(names, team)}/{team_cap}")
    if group_cap is not None:
        seats = os.environ.get("FT_SEATS_JSON", "")
        try:
            parent = json.loads(Path(seats).read_text(encoding="utf-8")).get("_parent")
        except (OSError, ValueError) as e:
            die("ERROR", f"FT_SEATS_JSON 읽기 실패 {seats!r}: {e}")
        if not parent:
            die("ERROR", f"{seats} 에 _parent 가 없어 위성 합 상한을 셀 수 없다")
        total = sum(count(names, t) for t in sorted(set(group_teams(root, parent)) | {team}))
        if total >= group_cap:
            die("REJECT", f"위성 합 상한 {total}/{group_cap}")


if __name__ == "__main__":
    main()
