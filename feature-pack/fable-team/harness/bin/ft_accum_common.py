#!/usr/bin/env python3
# ft_accum_common.py — r1293 누적 정리 «공통 바탕»(설정·예산·판정 불가·옮기기·날짜). 실행 진입 아님 — 셋이 import 한다.
#   설정 = env FT_ACCUM_ROOT(필수) FT_ACCUM_NOW FT_ACCUM_BUDGET_SEC(70) FT_ACCUM_ARCHIVE_WARN_GIB(5) FT_ACCUM_SCAN_DELAY_MS FT_ACCUM_GIT
#   place() = 덮어쓰기 0(자리표 O_EXCL · 같은 이름 -2·-3) · guard()/bad() = 판정 불가 모으기 · log() = state/accum/sweep-YYYYMMDD.log
#   GITQ = git -c core.quotepath=off — 다른 머신 기본(core.quotepath=true)에서 한글 «완성» 경로가 따옴표·8진으로 새지 않게
import datetime as dt, os, sys, time

ROOT = os.environ.get("FT_ACCUM_ROOT", "")
if not ROOT or not os.path.isdir(ROOT):
    print("ERROR FT_ACCUM_ROOT 없음 또는 폴더 아님: %r" % ROOT, file=sys.stderr)
    sys.exit(2)
NOW = int(os.environ.get("FT_ACCUM_NOW") or time.time())
BUDGET = float(os.environ.get("FT_ACCUM_BUDGET_SEC") or 70)
WARN_GIB = float(os.environ.get("FT_ACCUM_ARCHIVE_WARN_GIB") or 5)
DELAY = float(os.environ.get("FT_ACCUM_SCAN_DELAY_MS") or 0) / 1000.0
GIT = os.environ.get("FT_ACCUM_GIT") or "git"
GITQ = [GIT, "-c", "core.quotepath=off"]
STATE = os.path.join(ROOT, ".fable-team", "state")
ACC = os.path.join(STATE, "accum")
TODAY = dt.datetime.fromtimestamp(NOW).strftime("%Y%m%d")
LOG = os.path.join(ACC, "sweep-%s.log" % TODAY)
DEAD = time.monotonic() + BUDGET
BAD = []   # [(항목, 사유)] — 판정 불가


def left():
    return DEAD - time.monotonic()


def cap():
    """외부 호출 1회 상한 = min(7, 남은초−1) — 하드 룰 12 (설계 12-r2)."""
    r = left() - 1
    return 0 if r < 1 else min(7, r)


def bad(k, e):
    BAD.append((k, e.errno if isinstance(e, OSError) else e))


def guard(k, fn, *a):
    """OSError 는 그 항목만 «판정 불가» 로 남기고 계속 — 조용한 0 금지(하드 룰 20)."""
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
    """중복 0 — 자리표(O_EXCL)로 경주 0, 같은 이름 있으면 -2·-3 (설계 10-r2). 실제 옮김 = os.rename."""
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
    """YYYYMMDD 이름 날짜 → 오늘과의 날 수(못 읽으면 None)."""
    try:
        d = dt.datetime.strptime(s, "%Y%m%d").date()
    except ValueError:
        return None
    return (dt.datetime.fromtimestamp(NOW).date() - d).days


def tickdirs():
    """state 아래 <팀>-tick 폴더들 — 헤드라인 기록·보관 크기 대상."""
    names = guard("상태 폴더", os.listdir, STATE) or []
    return [os.path.join(STATE, d) for d in sorted(names)
            if d.endswith("-tick") and os.path.isdir(os.path.join(STATE, d))]
