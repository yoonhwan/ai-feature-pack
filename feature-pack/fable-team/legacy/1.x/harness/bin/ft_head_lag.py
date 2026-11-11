#!/usr/bin/env python3
"""ft_head_lag.py — R243: main 보다 뒤처진 워크트리 → 그 워크트리에 앉은 팀 master 에 mbox 1통(팀당). ft-head-lag.sh 가 부른다.
읽기 + mbox 발신만 한다(최신화·병합·push 0). 팀 = tmux pane 의 세션 이름(byz-<팀>-… / ft-v65-…) → 명부 `_master`."""
import argparse
import fcntl
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I 은 스크립트 폴더를 path 에 넣지 않는다
from ft_head_lag_seats import load_state, master_of, seats_by_wt, skip_regex, team_of, warn
from ft_head_lag_skip import base_skipped, work_left
from ft_head_lag_stop import plan, record   # r1492 — 정지 팀(penalty·전팀 정지) 좌석은 쪽지로 깨우지 않는다


def git(repo, *a):
    r = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True)
    return r.returncode, r.stdout.strip()


def worktrees(repo):
    wts, cur = [], {}
    for line in git(repo, "worktree", "list", "--porcelain")[1].splitlines() + [""]:
        if not line:
            if cur.get("path") and os.path.isdir(cur["path"]):
                wts.append(cur)
            cur = {}
        elif line.startswith("worktree "):
            cur["path"] = line[9:]
        elif line.startswith("branch refs/heads/"):
            cur["branch"] = line[18:]
    return wts


def lag(wt, msha):
    rc, n = git(wt, "rev-list", "--count", f"HEAD..{msha}")
    if rc:
        warn(f"rev-list 실패: {wt}")
        return None
    if n == "0":
        return None
    return int(n), min(int(t) for t in git(wt, "log", "--format=%ct", f"HEAD..{msha}")[1].split())


def fmt(secs):
    return f"{secs // 3600}시간" if secs >= 3600 else f"{secs // 60}분"


def build(items, msha):
    items = sorted(items, key=lambda s: -s["secs"])
    out = [f"[베이스 뒤처짐] main {msha[:10]} 위에 있지 않은 워크트리 {len(items)}곳 (이 팀 좌석이 앉은 곳):"]
    out += [f"- {os.path.basename(s['path'])}({s['branch']}) {s['path']} · main 보다 {s['n']}커밋 · {fmt(s['secs'])}" for s in items[:8]]   # R749: 절대 경로 — 어디서 쳐야 하는지
    if len(items) > 8:
        out.append(f"- 외 {len(items) - 8}곳")
    where = items[0]["path"] if len(items) == 1 else "위 각 줄의 경로"
    # R882: 실행 지시 0 — 이 쪽지가 좌석마다 도구 실행을 낳으면 전수 스캔이 겹쳐 폭주한다(02:5x 14개). 앉은 좌석이 자기 워크트리만 스스로
    out.append(f"조치: 그 워크트리 안에서(cd {where}) 앉은 좌석이 자기 일 사이에 스스로 받는다 — 미커밋 0 이면 그 자리에서 merge --no-edit {msha} (merge 만 · rebase·force 0 · 남의 워크트리 대신 맞추기 0) · 팩(ai-feature-pack) 작업 폴더는 이 알림과 무관 · 충돌이면 그 팀 arch 에 · 옛 베이스 병합은 병합 게이트가 거절한다(R243/R749/R882)")
    return "\n".join(out)


def send(root, master, body):
    mbox = os.environ.get("FT_HEAD_LAG_MBOX") or os.path.join(root, ".fable-team", "comm", "mbox.sh")
    try:
        r = subprocess.run(["bash", mbox, "send", master, os.environ.get("FT_HEAD_LAG_FROM", "ft-head-lag"), body], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        warn(f"mbox 발신 실패 {master}: {e}")
        return None
    m = re.search(r"seq=(\d+)", r.stdout)
    if r.returncode or not m:
        warn(f"mbox 발신 실패 {master} rc={r.returncode}: {(r.stdout + r.stderr).strip()[:120]}")
        return None
    return int(m.group(1))


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    for k in ("event", "cron", "summary"):
        g.add_argument(f"--{k}", action="store_true")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--bin", required=True)
    a = ap.parse_args()
    now = int(os.environ.get("FT_HEAD_LAG_NOW") or time.time())
    rc, msha = git(a.repo, "rev-parse", "--verify", "-q", a.base + "^{commit}")
    if rc:
        print(f"ERROR 기준 {a.base} 확인 실패", file=sys.stderr)
        return 4
    try:
        skip = skip_regex()
    except (ValueError, re.error) as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 4
    wts = worktrees(a.repo)
    stale, scanned, keep = [], set(), set()
    try:
        bsec = float(os.environ.get("FT_HEAD_LAG_BUDGET", "7"))   # r1700: 훑기 예산(초) — r1688 실측 7초
    except ValueError:
        bsec = 7.0                                              # ⓖ abc 같은 값 = 기본 7초
    t0, bad = time.monotonic(), 0
    for i, w in enumerate(wts):
        br, r = w.get("branch"), None
        if br and br.startswith("nano/"):   # r1700 ⓐ: 나노 가지 워크트리는 훑지 않는다(이 도구만 · ft-head-skip.txt 불변)
            keep.add(os.path.realpath(w["path"]))
            continue
        if bsec <= 0 or time.monotonic() - t0 > bsec:   # r1700 ⓑ: 예산 넘으면 멈춘다 — 못 훑은 곳은 «판정 불가»
            bad = sum(1 for x in wts[i:] if x.get("branch") and not x["branch"].startswith("nano/") and not skip.match(x["branch"]))
            keep.update(os.path.realpath(x["path"]) for x in wts[i:])
            break
        if br and not skip.match(br) and not base_skipped(w["path"], skip, a.base):   # r1334: 선언 base 가 제외 줄기면 빼고
            r = lag(w["path"], msha)
            if r and not work_left(w["path"], msha):   # r1334: 일이 남지 않은 착지 끝 워크트리도 뺀다
                r = None
            scanned.add(os.path.realpath(w["path"]))
        else:
            keep.add(os.path.realpath(w["path"]))
        if r:
            stale.append({"path": w["path"], "real": os.path.realpath(w["path"]), "branch": br, "n": r[0], "secs": max(0, now - r[1])})
    if bad:
        print(f"판정 불가 {bad}곳(훑기 예산 {bsec:g}초)", file=sys.stderr)   # 하드 룰 20: 못 훑음 = 1줄
    if a.summary:
        if stale:
            o = max(stale, key=lambda s: (s["secs"], s["n"]))
            print(f"베이스 뒤처짐 {len(stale)}곳(가장 오래 {os.path.basename(o['path'])} {o['n']}커밋·{fmt(o['secs'])})" + (f" · 판정 불가 {bad}곳" if bad else ""))
        return 0
    root = os.environ.get("FT_ROOT") or os.path.dirname(git(a.repo, "rev-parse", "--path-format=absolute", "--git-common-dir")[1])
    sdir = os.path.join(root, ".fable-team", "state")
    os.makedirs(sdir, exist_ok=True)
    sf = os.path.join(sdir, "head-lag.json")
    minutes = 0 if a.event else int(os.environ.get("FT_HEAD_LAG_MIN", "60"))
    remind = int(os.environ.get("FT_HEAD_LAG_REMIND_H", "6")) * 3600
    with open(sf + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        st = load_state(sf, {s["real"] for s in stale} | keep)   # R836 키 = 워크트리 하나 · r1700 ⓒ: 못 훑은 곳·나노 건너뜀 기록은 지우지 않는다
        by =seats_by_wt([os.path.realpath(w["path"]) for w in wts])
        groups = plan(root, stale, st, by, minutes, now, remind)   # r1492 — 문턱·팀 단위 정지 보류(held) 판정은 그쪽 한 자리
        sent, failed = {}, set()
        for m, items in groups.items():
            seq = send(root, m, build(items, msha))
            for s in items:
                if seq:
                    sent.setdefault(s["real"], (seq, set()))[1].add(m)   # r1492 — 워크트리별로 받는이를 모두 남긴다
                else:
                    failed.add(s["real"])
        for real, (seq, ms) in sent.items():
            if real not in failed:
                st[real] = record(st.get(real, {}), seq, ms, now)   # r1492 — 보낸 받는이의 held 만 지운다
        tmp = f"{sf}.{os.getpid()}"
        json.dump({"v": 2, "seats": st}, open(tmp, "w"), ensure_ascii=False)   # R836 r3: 판 번호로 새·옛을 가른다(키 글자 해석 0)
        os.replace(tmp, sf)
    return 5 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
