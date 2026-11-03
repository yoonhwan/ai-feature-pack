#!/usr/bin/env python3
"""ft_head_lag_skip.py — r1334: 뒤처짐 경보에서 «일이 남지 않은 워크트리» 를 가른다 (ft_head_lag.py 가 부른다 · 읽기 전용).
  base_skipped = 워크트리가 .worktree-info.json 에 적은 선언 base 가 제외 목록 줄기(ops/main-base 등)면 True (A1~A3)
  work_left    = 뒤처진 워크트리에 main 으로 갈 일이 남았나 — 고유 diff 0 · 미커밋 0 · 진행 중 병합 0 이면 False (A5·A6)
git 실패·시간 초과 = 일이 남은 것으로 본다(지금처럼 셈) + warn 1줄 — 조용한 제외 0."""
import json
import os
import re
import subprocess

from ft_head_lag_seats import warn

GIT_SECS = 7
IN_PROGRESS = ("MERGE_HEAD", "REBASE_HEAD", "rebase-merge", "rebase-apply", "CHERRY_PICK_HEAD", "REVERT_HEAD", "sequencer")


def norm_ref(ref):
    """refs/remotes/ · refs/heads/ 를 벗긴 뒤 origin/ 을 벗긴다 — refs/remotes/origin/main = origin/main = main."""
    ref = re.sub(r"^refs/(remotes|heads)/", "", ref.strip())
    return ref[len("origin/"):] if ref.startswith("origin/") else ref


def declared_base(wt):
    """.worktree-info.json 의 base 칸. 파일 없음·base 칸 없음 = None(조용히) · 깨진 JSON·꼴 오류 = None + warn."""
    path = os.path.join(wt, ".worktree-info.json")
    try:
        info = json.load(open(path, encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as e:
        warn(f"선언 base 읽기 실패 {path}: {str(e)[:60]} — 선언 base 제외 0")
        return None  # [W3]
    base = info.get("base") if isinstance(info, dict) else None
    return base if isinstance(base, str) and base.strip() else None


def base_skipped(wt, skip, ref):
    """선언 base 가 제외 줄기 + 기준(ref)과 다른 줄기면 True. 기준과 같은 줄기(origin/main ↔ main)는 이 제외를 쓰지 않는다(A1)."""
    base = declared_base(wt)
    if base is None or norm_ref(base) == norm_ref(ref):
        return False
    return bool(skip.match(base) or skip.match(norm_ref(base)))


def _run(wt, *args):
    """(rc, stdout) — 7초 초과·실행 실패 = (None, '') + warn."""
    try:
        r = subprocess.run(["git", "-C", wt, *args], capture_output=True, text=True, timeout=GIT_SECS)
    except (OSError, subprocess.TimeoutExpired) as e:
        warn(f"git {args[0]} 실패({type(e).__name__}): {wt} — 지금처럼 셈")
        return None, ""
    return r.returncode, r.stdout


def work_left(wt, msha):
    """True = 일이 남았거나 판정 불가(셈 유지). False = merge-base..HEAD 고유 diff 0 ∧ 미커밋 0 ∧ 진행 중 병합 0 (A5)."""
    rc, out = _run(wt, "merge-base", msha, "HEAD")
    if rc is None:
        return True
    if rc:
        warn(f"merge-base 실패 rc={rc}: {wt} — 지금처럼 셈")
        return True  # [W6]
    rc, _ = _run(wt, "diff", "--quiet", "--ignore-submodules=none", out.strip(), "HEAD")
    if rc is None or rc == 1:
        return True
    if rc:
        warn(f"diff 실패 rc={rc}: {wt} — 지금처럼 셈")
        return True
    rc, out = _run(wt, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none")
    if rc is None or out.strip():
        return True
    if rc:
        warn(f"status 실패 rc={rc}: {wt} — 지금처럼 셈")
        return True
    rc, gd = _run(wt, "rev-parse", "--absolute-git-dir")
    if rc is None or rc:   # [W15]
        warn(f"git 폴더 확인 실패: {wt} — 지금처럼 셈")
        return True
    return any(os.path.exists(os.path.join(gd.strip(), m)) for m in IN_PROGRESS)
