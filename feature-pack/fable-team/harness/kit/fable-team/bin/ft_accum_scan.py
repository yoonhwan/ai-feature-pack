#!/usr/bin/env python3
# ft_accum_scan.py — r1293 누적 정리 «보기만» 세 항목. 쓰기 0 · 옮기기·지우기 0.
#   ④ 완성 카드 30일 = 목록 파일만(state/accum/cards-done-30d-YYYYMMDD.txt) — 카드 목록 = ref 의 git ls-tree(작업 트리 아님!) ·
#      최근 30일 도착 = git log --since=30.days -M --diff-filter=AR(추가 + 완성으로 들어온 이름 바꿈) · git 쓰기 0 · 이동은 master 몫
#   ⑤ 백업 폴더 state/v6-uncommitted-backup-* = 폴더마다 크기 1줄(이동·지우기 0) · ⑥ 보관 합(archive) = 경보 판정용 크기
#   git 호출은 전부 GITQ(core.quotepath=off) + min(7, 남은초−1)초 상한(설계 12-r2).
import os, subprocess, time

from ft_accum_common import ACC, BAD, DELAY, GITQ, NOW, ROOT, STATE, TODAY, bad, cap, guard, left, log, tickdirs


def _git(args, t):
    """git 1회 — 상한 t 초. 실패·시간 초과는 그 항목만 판정 불가(다른 항목 계속)."""
    return subprocess.run(GITQ + args, capture_output=True, text=True, timeout=t)


def done_cards():
    tab = os.path.join(STATE, "directive-roots.tsv")
    if not os.path.isfile(tab):
        return 0
    try:
        with open(tab, encoding="utf-8") as fh:
            rows = [ln.rstrip("\n").split("\t") for ln in fh]
    except (OSError, ValueError) as e:   # ValueError = UnicodeDecodeError(비 UTF-8 표) — 조용한 0 금지
        bad("완성 카드", e)
        return 0
    out = []
    for i, r in enumerate(rows):
        if len(r) < 4:
            continue
        repo = os.path.normpath(os.path.join(ROOT, r[1] or "."))
        t = cap()
        if t <= 0:
            print("예산 초과 — 남은 완성 카드 루트 %d곳 다음 날" % (len(rows) - i))
            log("예산 초과 cards 루트 %d곳" % (len(rows) - i))
            break
        try:
            res = _git(["-C", repo, "log", r[2], "--since=30.days", "-M", "--diff-filter=AR",
                        "--name-status", "--pretty=format:", "--", r[3]], t)   # ★r1317 카드 폴더로 좁힘(ls-tree :53 과 같은 값)
            if res.returncode != 0:
                bad("cards git", "rc=%d %s" % (res.returncode, (res.stderr or "").strip()[:80]))
                continue
            recent = set()
            for ln in res.stdout.splitlines():
                f = ln.split("\t")
                if len(f) > 1 and f[0][:1] in ("A", "R"):
                    recent.add(f[-1])
            t = cap()
            if t <= 0:
                print("예산 초과 — 남은 완성 카드 루트 %d곳 다음 날" % (len(rows) - i))
                log("예산 초과 cards 루트 %d곳" % (len(rows) - i))
                break
            tree = _git(["-C", repo, "ls-tree", "-r", "--name-only", r[2], "--", r[3]], t)   # ★ref 기준(작업 트리 아님)
        except (OSError, subprocess.SubprocessError) as e:
            bad("cards git", e)
            continue
        if tree.returncode != 0:
            bad("cards git", "rc=%d %s" % (tree.returncode, (tree.stderr or "").strip()[:80]))
            continue
        for card in tree.stdout.splitlines():
            if "/완성/" in card and card.endswith(".md") and card not in recent:
                out.append(card)
    if out:
        try:
            with open(os.path.join(ACC, "cards-done-30d-%s.txt" % TODAY), "w", encoding="utf-8") as fh:
                fh.write("".join(x + "\n" for x in out))
        except OSError as e:
            bad("완성 카드 목록", e)
    return len(out)


def dir_gib(p, budget):
    """p 아래 합계 GiB · 마감 넘으면 «자른 값, True» — 항목마다 시각 확인(설계 17-r3)."""
    end = time.monotonic() + max(0.0, budget)
    tot = 0
    stack = [p]
    while stack:
        if time.monotonic() >= end:
            return tot / 1073741824.0, True
        try:
            entries = list(os.scandir(stack.pop()))
        except OSError:
            continue
        for e in entries:
            if time.monotonic() >= end:
                return tot / 1073741824.0, True
            if DELAY:
                time.sleep(DELAY)
            try:
                if e.is_dir(follow_symlinks=False):
                    stack.append(e.path)
                else:
                    tot += e.stat(follow_symlinks=False).st_size
            except OSError:
                continue
    return tot / 1073741824.0, False


def backups():
    names = sorted(guard("백업", os.listdir, STATE) or [])
    dirs = [d for d in names if d.startswith("v6-uncommitted-backup") and os.path.isdir(os.path.join(STATE, d))]
    done, tot = 0, 0.0
    for d in dirs:
        if left() < 2:
            print("예산 초과 — 남은 백업 %d곳 다음 날" % (len(dirs) - done))
            log("예산 초과 백업 %d곳" % (len(dirs) - done))
            break
        g, cut = dir_gib(os.path.join(STATE, d), cap())
        tot += g
        done += 1
        log("백업 %s %s%.2fGiB" % (d, "≥" if cut else "", g))
    return done, tot


def archive_gib():
    tot = 0.0
    for p in [os.path.join(ACC, "archive")] + [os.path.join(d, "archive") for d in tickdirs()]:
        if not os.path.isdir(p) or left() < 2:
            continue
        g, cut = dir_gib(p, cap())
        tot += g
        if cut:
            log("보관 스캔 잘림 %s ≥%.2fGiB" % (p, g))
    return tot
