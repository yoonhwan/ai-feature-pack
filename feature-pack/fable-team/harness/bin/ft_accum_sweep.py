#!/usr/bin/env python3
# ft_accum_sweep.py — r1293 하루 1회 누적 정리: 옮기기·목록만 · 지우기 0 (본체 · ft-accum-sweep.sh 가 부른다).
#   항목: ① 헤드라인 기록 <팀>-tick/HEADLINE-log-YYYYMMDD.md 중 이름 날짜 7일 넘음 → <팀>-tick/archive/
#        ② planner-tick TEAM-STATUS.md.bak* 최근 3개만 남김 + 나머지 · VERDICTS-pending*/ORDER*/SUCC* 중 mtime 1일 넘음 → planner-tick/archive/<mtime 날짜>/
#        ③ 자기 기록 state/accum/sweep-YYYYMMDD.log 7일 넘음 → state/accum/archive/
#        ④ 완성 카드 30일 = 목록 파일만(state/accum/cards-done-30d-YYYYMMDD.txt · git 쓰기 0 · 이동은 master 몫 · 최근 30일 «추가 + 완성으로 들어온 이름 바꿈»)
#        ⑤ 백업 폴더 state/v6-uncommitted-backup-* = 폴더마다 크기 1줄(이동·지우기 0)
#   잠금 = state/accum/sweep.lock flock LOCK_NB(겹치면 «앞 실행이 돈다 — 건너뜀» rc 0) · 하루 1회 표식 = state/accum/done-YYYYMMDD(잠금 안)
#   예산 = FT_ACCUM_BUDGET_SEC(70) · 폴더 스캔·git 마다 min(7, 남은초−1) · 넘으면 «예산 초과 — 남은 … 다음 날» 1줄 · 끝 줄은 그대로
#   사람 볼 일 2개만 planner 에 [HIL] 쪽지(판정 불가 · 보관 큼 · 같은 날 같은 종류 1통 표식 hil-<종류>-YYYYMMDD) — rc 0 끝 줄은 로그·stdout 만
#   env(시험용): FT_ACCUM_ROOT FT_ACCUM_NOW FT_ACCUM_BUDGET_SEC FT_ACCUM_ARCHIVE_WARN_GIB FT_ACCUM_SCAN_DELAY_MS FT_ACCUM_SEATS FT_MBOX_SH FT_ACCUM_GIT
#   rc: 0 정상 · 3 판정 불가 있음(끝 줄은 낸다) · 2 루트 없음
import datetime as dt, fcntl, glob, json, os, re, subprocess, sys, time

ROOT = os.environ.get("FT_ACCUM_ROOT", "")
if not ROOT or not os.path.isdir(ROOT):
    print("ERROR FT_ACCUM_ROOT 없음 또는 폴더 아님: %r" % ROOT, file=sys.stderr)
    sys.exit(2)
NOW = int(os.environ.get("FT_ACCUM_NOW") or time.time())
BUDGET = float(os.environ.get("FT_ACCUM_BUDGET_SEC") or 70)
WARN_GIB = float(os.environ.get("FT_ACCUM_ARCHIVE_WARN_GIB") or 5)
DELAY = float(os.environ.get("FT_ACCUM_SCAN_DELAY_MS") or 0) / 1000.0
GIT = os.environ.get("FT_ACCUM_GIT") or "git"
STATE = os.path.join(ROOT, ".fable-team", "state")
ACC = os.path.join(STATE, "accum")
TODAY = dt.datetime.fromtimestamp(NOW).strftime("%Y%m%d")
LOG = os.path.join(ACC, "sweep-%s.log" % TODAY)
DEAD = time.monotonic() + BUDGET
BAD = []   # [(항목, 사유)] — 판정 불가


def left():
    return DEAD - time.monotonic()


def cap():
    r = left() - 1
    return 0 if r < 1 else min(7, r)


def bad(k, e):
    BAD.append((k, e.errno if isinstance(e, OSError) else e))


def guard(k, fn, *a):
    try:
        return fn(*a)
    except OSError as e:
        bad(k, e)
        return None


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write("%s %s\n" % (dt.datetime.fromtimestamp(NOW).strftime("%Y-%m-%dT%H:%M:%S"), msg))
    except OSError:
        pass


def place(src, dstdir):
    """중복 0 — 자리표(O_EXCL)로 경주 0, 같은 이름 있으면 -2·-3 (설계 10-r2)."""
    os.makedirs(dstdir, exist_ok=True)
    base = os.path.basename(src)
    stem, ext = os.path.splitext(base)
    for i in range(1, 100):
        dst = os.path.join(dstdir, base if i == 1 else "%s-%d%s" % (stem, i, ext))
        try:
            os.close(os.open(dst, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
        except FileExistsError:
            continue
        try:
            os.rename(src, dst)
        except OSError:
            try:
                os.unlink(dst)
            except OSError:
                pass
            raise
        return dst
    raise OSError(17, "이름 자리 없음(1~99)")


def age_days(s):
    try:
        d = dt.datetime.strptime(s, "%Y%m%d").date()
    except ValueError:
        return None
    return (dt.datetime.fromtimestamp(NOW).date() - d).days


def tickdirs():
    names = guard("상태 폴더", os.listdir, STATE) or []
    return [os.path.join(STATE, d) for d in sorted(names)
            if d.endswith("-tick") and os.path.isdir(os.path.join(STATE, d))]


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


def done_cards():
    """완성 카드 30일 = 목록만(설계 13-r2) — git 쓰기 0 · 이동은 master 몫."""
    tab = os.path.join(STATE, "directive-roots.tsv")
    if not os.path.isfile(tab):
        return 0
    try:
        with open(tab, encoding="utf-8") as fh:
            rows = [ln.rstrip("\n").split("\t") for ln in fh]
    except OSError as e:
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
            res = subprocess.run([GIT, "-C", repo, "log", r[2], "--since=30.days", "-M", "--diff-filter=AR",
                                  "--name-status", "--pretty=format:"], capture_output=True, text=True, timeout=t)
        except (OSError, subprocess.SubprocessError) as e:
            bad("cards git", e)
            continue
        if res.returncode != 0:
            bad("cards git", "rc=%d %s" % (res.returncode, (res.stderr or "").strip()[:80]))
            continue
        recent = set()
        for ln in res.stdout.splitlines():
            f = ln.split("\t")
            if len(f) > 1 and f[0][:1] in ("A", "R"):
                recent.add(f[-1])
        for card in sorted(glob.glob(os.path.join(repo, r[3], "완성", "*.md"))):
            rel = os.path.relpath(card, repo)
            if rel not in recent:
                out.append(rel)
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


def route():
    sj = os.environ.get("FT_ACCUM_SEATS") or os.path.join(ROOT, ".fable-team", "seats-planner.json")
    try:
        with open(sj, encoding="utf-8") as fh:
            v = json.load(fh)
    except Exception:
        return ""
    return v.get("_hil_route") or v.get("_master") or ""


def send(body, kind):
    """사람 볼 일만 · 같은 날 같은 종류 1통(표식). 실패면 표식 0 = 다음 날 재시도."""
    mark = os.path.join(ACC, "hil-%s-%s" % (kind, TODAY))
    if os.path.exists(mark):
        return
    to = route()
    mbox = os.environ.get("FT_MBOX_SH") or os.path.join(ROOT, ".fable-team", "comm", "mbox.sh")
    if not to or not os.path.isfile(mbox):
        log("ERROR [HIL] 못 보냄 — 수신자 %r · mbox %r" % (to, mbox))
        return
    try:
        res = subprocess.run(["bash", mbox, "send", to, "ft-accum-sweep", body],
                             capture_output=True, text=True, timeout=max(3, cap()))
        ok, rc = res.returncode == 0, res.returncode
    except (OSError, subprocess.SubprocessError) as e:
        ok, rc = False, type(e).__name__
    if not ok:
        log("ERROR [HIL] 발신 실패 %s rc=%s — 표식 0(다음 날 재시도)" % (kind, rc))
        return
    try:
        open(mark, "w").close()
    except OSError:
        pass
    log("[HIL] %s 보냄 to=%s" % (kind, to))


def main():
    try:
        os.makedirs(ACC, exist_ok=True)
        lf = open(os.path.join(ACC, "sweep.lock"), "a")
    except OSError as e:
        print("ERROR 상태 폴더 만들기 실패(%s): %s" % (ACC, e), file=sys.stderr)
        return 2
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("앞 실행이 돈다 — 건너뜀")
        return 0
    done = os.path.join(ACC, "done-%s" % TODAY)
    if os.path.exists(done):
        print("오늘 이미 함 (%s)" % done)
        return 0
    open(done, "w").close()
    h, p, o = sweep_headlines(), sweep_planner_tick(), sweep_own_logs()
    cards = done_cards()
    nb, nbg = backups()
    ag = archive_gib()
    line = ("[누적 정리] 옮김 %d(헤드라인 %d · planner-tick %d · 자기 기록 %d)"
            " · 목록만(완성 카드 %d · 백업 %d곳 %.1fG) · 판정 불가 %d · 보관 합 %.1fG") % (
        h + p + o, h, p, o, cards, nb, nbg, len(BAD), ag)
    log(line)
    print(line)
    for k, v in BAD:
        log("판정 불가 %s %s" % (k, v))
    if BAD:
        heads = "; ".join("%s %s" % (k, v) for k, v in BAD[:3])
        send("[HIL] 누적 정리 판정 불가 %d\n"
             "①막힌 명령: ft-accum-sweep.sh — %s\n"
             "②사유: 그 항목만 건너뛰고 나머지는 돌았다(지우기 0)\n"
             "④선택지: ①원인(권한·경로·git)을 고쳐 다음 날 재실행 ②그 항목을 카드 범위에서 뺀다 ③그대로 둔다\n"
             "자세한 줄: %s" % (len(BAD), heads, LOG), "error")
    if ag > WARN_GIB:
        send("[HIL] 누적 보관 큼: %.1fG — 지우기는 사람 결정\n"
             "①막힌 명령: 없음 — 보관 폴더 합이 경보값 %.1fG 를 넘었다\n"
             "②사유: 보관물의 닫는 사건(지우기)이 사람 결정이라 도구가 거기서 멈춘다\n"
             "④선택지: ①경보값을 올린다 ②오래된 보관을 사람이 지운다 ③archive 를 다른 볼륨으로 옮긴다\n"
             "자세한 줄: %s" % (ag, WARN_GIB, LOG), "big")
    return 3 if BAD else 0


if __name__ == "__main__":
    sys.exit(main())
