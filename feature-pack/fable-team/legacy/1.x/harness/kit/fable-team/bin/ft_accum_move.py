#!/usr/bin/env python3
# ft_accum_move.py — r1293 누적 정리 «옮기기» 세 항목. 옮기기만 한다(지우기 0 · 하드 룰 2).
#   ① 헤드라인 기록 — <팀>-tick/HEADLINE-log-YYYYMMDD.md 중 «이름 날짜 7일 넘음» → <팀>-tick/archive/
#   ② planner-tick  — TEAM-STATUS.md.bak* 최근 3개(mtime)만 남기고 나머지 · VERDICTS-pending*/ORDER*/SUCC* 중 mtime 1일 넘음 → planner-tick/archive/<mtime 날짜>/
#   ③ 자기 기록     — state/accum/sweep-YYYYMMDD.log 7일 넘음 → state/accum/archive/
#   고정 경로로 읽는 이름(HEADLINE.md·HEADLINE-seats.txt·PAUSED·TEAM-STATUS.md·RULE*)은 손대지 않는다.
import datetime as dt, os, re

from ft_accum_common import ACC, LOG, NOW, STATE, age_days, guard, left, place, tickdirs


def sweep_headlines():
    n = 0
    for p in tickdirs():
        for f in sorted(guard("헤드라인", os.listdir, p) or []):
            m = re.match(r"^HEADLINE-log-(\d{8})\.md$", f)
            d = age_days(m.group(1)) if m else None
            if d is None or d <= 7 or left() < 1:
                continue
            if guard("헤드라인", place, os.path.join(p, f), os.path.join(p, "archive")):
                n += 1
    return n


def sweep_planner_tick():
    p = os.path.join(STATE, "planner-tick")
    if not os.path.isdir(p):
        return 0

    def mt(f):
        return os.stat(os.path.join(p, f)).st_mtime

    names = sorted(guard("planner-tick", os.listdir, p) or [])
    st = {f: guard("planner-tick", mt, f) or 0 for f in names}
    baks = [f for f in names if f.startswith("TEAM-STATUS.md.bak")]
    keep = set(sorted(baks, key=lambda f: st[f], reverse=True)[:3])
    n = 0
    for f in names:
        src = os.path.join(p, f)
        hit = (f in baks and f not in keep) or (re.match(r"^(VERDICTS-pending|ORDER|SUCC)", f) and NOW - st[f] >= 86400)
        if not hit or os.path.islink(src) or not os.path.isfile(src) or left() < 1:
            continue
        if guard("planner-tick", place, src, os.path.join(p, "archive", dt.datetime.fromtimestamp(st[f]).strftime("%Y%m%d"))):
            n += 1
    return n


def sweep_own_logs():
    n = 0
    for f in sorted(guard("자기 기록", os.listdir, ACC) or []):
        m = re.match(r"^sweep-(\d{8})\.log$", f)
        d = age_days(m.group(1)) if m else None
        if d is None or d <= 7 or f == os.path.basename(LOG):
            continue
        if guard("자기 기록", place, os.path.join(ACC, f), os.path.join(ACC, "archive")):
            n += 1
    return n
