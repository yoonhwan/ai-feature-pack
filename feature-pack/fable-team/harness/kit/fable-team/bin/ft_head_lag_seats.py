#!/usr/bin/env python3
"""ft_head_lag_seats.py — R243: 워크트리 → tmux pane 세션 이름 → 팀 → 명부 `_master` (ft_head_lag.py 가 부른다 · 읽기 전용)."""
import json
import os
import re
import shlex
import subprocess
import sys


def warn(msg):
    print(f"WARN {msg}", file=sys.stderr)


def skip_regex():
    """제외 브랜치 정규식 — FT_HEAD_SYNC_SKIP 이 우선, 없으면 같은 폴더 ft-head-skip.txt(한 줄 = 정규식 1개 · # 주석). 못 읽거나 0줄이면 ValueError(기본값으로 넘기지 않는다)."""
    env = os.environ.get("FT_HEAD_SYNC_SKIP")
    if env:
        return re.compile(env)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft-head-skip.txt")
    try:
        lines = [ln.strip() for ln in open(path, encoding="utf-8")]
    except OSError as e:
        raise ValueError(f"제외 목록 읽기 실패 {path}: {e}")
    pats = [ln for ln in lines if ln and not ln.startswith("#")]
    if not pats:
        raise ValueError(f"제외 목록 {path} 에 정규식 줄이 없다")
    return re.compile("^(" + "|".join(pats) + ")$")


def panes():
    cmd = ["tmux", *shlex.split(os.environ.get("FT_HEAD_LAG_TMUX_ARGS", "")), "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.TimeoutExpired) as e:
        warn(f"tmux 실행 실패({e}) — 좌석 매핑 없음")
        return []
    if r.returncode and not re.search(r"no server|error connecting", r.stderr):
        warn(f"tmux list-panes 실패: {r.stderr.strip()[:80]}")
    return [ln.split("\t", 1) for ln in r.stdout.splitlines() if "\t" in ln]


def seats_by_wt(all_real):
    by = {w: set() for w in all_real}
    for sess, path in panes():
        p = os.path.realpath(path)
        hit = [w for w in all_real if p == w or p.startswith(w + os.sep)]
        if hit:
            by[max(hit, key=len)].add(sess)   # 가장 깊은 워크트리 = 그 pane 의 주인(루트 체크아웃이 .worktrees/ 를 품는다)
    return by


def team_of(sess):
    m = re.match(r"byz-([a-z0-9]+)-", sess)
    return m.group(1) if m else ("v65" if sess.startswith("ft-v65-") else None)


def master_of(root, team):
    f = os.path.join(root, ".fable-team", "seats.json" if team == "v65" else f"seats-{team}.json")
    try:
        return json.load(open(f)).get("_master") or warn(f"{f} 에 _master 없음")
    except (OSError, ValueError) as e:
        warn(f"명부 읽기 실패 {f}: {e}")
