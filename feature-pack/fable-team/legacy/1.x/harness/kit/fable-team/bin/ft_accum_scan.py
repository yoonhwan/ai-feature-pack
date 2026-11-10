#!/usr/bin/env python3
# ft_accum_scan.py — r1293 누적 정리 «보기만» 세 항목. 쓰기 0 · 옮기기·지우기 0.
#   ④ 완성 카드 30일 = 목록 파일만(state/accum/cards-done-30d-YYYYMMDD.txt) — 카드 목록 = ref 의 git ls-tree(작업 트리 아님!) ·
#      최근 30일 도착 = git log --since=30.days -M --diff-filter=AR(추가 + 완성으로 들어온 이름 바꿈) · git 쓰기 0 · 이동은 master 몫
#      ★r1317: 경로를 git 이 먹는 «실제 완성 폴더» 로 좁히고(_done_scope — 글롭은 폴더에 걸면 0줄), 30일을 7.5일
#      배치 4개로 쪼개 부른다(_recent — 하드 룰 12 «넘으면 먼저 쪼갠다»). 글롭 행이 0줄이면 조용한 0 이 아니라 판정 불가.
#   ⑤ 백업 폴더 state/v6-uncommitted-backup-* = 폴더마다 크기 1줄(이동·지우기 0) · ⑥ 보관 합(archive) = 경보 판정용 크기
#   git 호출은 전부 GITQ(core.quotepath=off) + min(7, 남은초−1)초 상한(설계 12-r2).
import os, re, subprocess, time

from ft_accum_common import ACC, BAD, DELAY, GITQ, NOW, ROOT, STATE, TODAY, bad, cap, guard, left, log, tickdirs

WIN_H = 720       # 보는 창 = 30일(«N.hours» — git 이 정수로 받는다)
CHUNK_H = 180     # 한 배치 = 7.5일 — 30일을 한 번에 훑지 않는다(외부 호출 1회 7초 · 설계 12-r2)
_GLOB = re.compile(r"[*?\[]")


def _done_scope(spec):
    """표의 카드 폴더 → (git 에 줄 «실제 경로», 완성 카드 거르는 조각).
    ★글롭은 «폴더» 에 걸면 git 이 그 안을 안 본다 — «design/teams/*/indices» 는 글롭이 파일 전체 경로에
      맞추어져 0줄이고(실측 · r1317 결함 A), ls-tree 는 글롭을 아예 안 먹는다 → 글롭이 있으면 글롭 앞
      «실제 접두»(design/teams)로 받아 파이썬에서 «/indices/완성/» 만 거른다(조용한 0 금지).
    글롭이 없으면 완성 폴더까지 좁힌다 — 계약은 «완성 폴더로 도착한 카드» 뿐이다(결함 B · 30일 6초대 → 배치)."""
    m = _GLOB.search(spec)
    if not m:
        return spec + "/완성", "/완성/"
    return spec[:m.start()].rstrip("/"), spec[m.end():] + "/완성/"


def _recent(repo, ref, dirs):
    """최근 30일 «완성 폴더로 도착(A/R)» 이름 — 7.5일 배치 + 배치마다 재시도 1(하드 룰 12).
    반환 (이름집합, 사유) — 사유가 비어 있지 않으면 그 행은 판정 불가(부분 결과로 목록을 만들지 않는다)."""
    got = set()
    wins = [(min(CHUNK_H * (k + 1), WIN_H), CHUNK_H * k) for k in range((WIN_H + CHUNK_H - 1) // CHUNK_H)]
    for k, (since, until) in enumerate(wins):
        args = ["-C", repo, "log", ref, "--since=%d.hours" % since]
        if until:
            args.append("--until=%d.hours" % until)
        args += ["-M", "--diff-filter=AR", "--name-status", "--pretty=format:", "--"] + dirs
        for attempt in (1, 2):
            t = cap()
            if t <= 0:
                t = 1.0 if attempt == 2 else 0.0   # 예산이 거의 끝나도 «쪼갠 배치의 재시도» 는 1초(최대 2회 = +2초)
            if t <= 0:
                print("예산 초과 — 남은 완성 카드 배치 %d개 다음 날" % (len(wins) - k))
                log("예산 초과 cards 배치 %d개" % (len(wins) - k))
                return got, "예산 초과(배치 %d개 남음)" % (len(wins) - k)
            try:
                res = _git(args, t)
            except subprocess.TimeoutExpired:
                log("완성 카드 배치 %d~%d시간 전 시간 초과 — 재시도 %d" % (since, until, attempt))
                continue
            except OSError as e:
                return got, "git 실행 실패 %s" % e
            if res.returncode != 0:
                return got, "rc=%d %s" % (res.returncode, (res.stderr or "").strip()[:80])
            for ln in res.stdout.splitlines():
                f = ln.split("\t")
                if len(f) > 1 and f[0][:1] in ("A", "R"):
                    got.add(f[-1])
            break
        else:
            return got, "배치 %d~%d시간 전 시간 초과(재시도 1 포함)" % (since, until)
    return got, ""


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
        base, tail = _done_scope(r[3])
        if not base:
            bad("cards git", "표 경로에 글롭 앞 접두가 없다: %r" % r[3])
            continue
        t = cap()
        if t <= 0:
            print("예산 초과 — 남은 완성 카드 루트 %d곳 다음 날" % (len(rows) - i))
            log("예산 초과 cards 루트 %d곳" % (len(rows) - i))
            break
        try:
            tree = _git(["-C", repo, "ls-tree", "-r", "--name-only", r[2], "--", base], t)   # ★ref 기준(작업 트리 아님)
        except (OSError, subprocess.SubprocessError) as e:
            bad("cards git", e)
            continue
        if tree.returncode != 0:
            bad("cards git", "rc=%d %s" % (tree.returncode, (tree.stderr or "").strip()[:80]))
            continue
        cards = [c for c in tree.stdout.splitlines()
                 if c.startswith(base.rstrip("/") + "/") and tail in c and c.endswith(".md")]
        if not cards:
            log("완성 카드 0줄 — 행 %r 경로 %r" % (r[3], base))
            if _GLOB.search(r[3]):   # 글롭 행이 0줄 = 경로가 안 먹었다(조용한 0 금지) — 오류로 센다
                bad("cards git", "완성 카드 0줄(글롭 행) %r — 경로 확인" % r[3])
            continue
        recent, why = _recent(repo, r[2], sorted({os.path.dirname(c) for c in cards}))
        if why:
            bad("cards git", "%s — 행 %r" % (why, r[3]))
            continue
        kept = [c for c in cards if c not in recent]
        log("완성 카드 행 %r — 발견 %d장 · 최근 30일 도착 %d · 목록 %d" % (r[3], len(cards), len(cards) - len(kept), len(kept)))
        out += kept
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
