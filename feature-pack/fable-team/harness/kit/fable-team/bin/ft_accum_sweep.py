#!/usr/bin/env python3
# ft_accum_sweep.py — r1293 하루 1회 누적 정리 진입(옮기기·목록만 · 지우기 0). 실제 일은 세 모듈:
#   ft_accum_common.py(설정·예산·place·log) · ft_accum_move.py(헤드라인·planner-tick·자기 기록) · ft_accum_scan.py(완성 카드 목록·백업·보관 크기)
#   잠금 = state/accum/sweep.lock flock LOCK_NB(겹치면 «앞 실행이 돈다 — 건너뜀» rc 0) · 하루 1회 표식 = state/accum/done-YYYYMMDD(잠금 안)
#   사람 볼 일 2개만 planner 에 [HIL] 쪽지(판정 불가 · 보관 큼 · 같은 날 같은 종류 1통 표식 hil-<종류>-YYYYMMDD) — rc 0 끝 줄은 로그·stdout 만
#   env: FT_ACCUM_ROOT FT_ACCUM_NOW FT_ACCUM_BUDGET_SEC FT_ACCUM_ARCHIVE_WARN_GIB FT_ACCUM_SCAN_DELAY_MS FT_ACCUM_SEATS FT_MBOX_SH FT_ACCUM_GIT
#   rc: 0 정상 · 3 판정 불가 있음(끝 줄은 낸다) · 2 루트 없음 · stdout 마지막 1줄 = 끝 줄
import fcntl, json, os, subprocess, sys

from ft_accum_common import ACC, BAD, LOG, ROOT, TODAY, WARN_GIB, cap, log
from ft_accum_move import sweep_headlines, sweep_own_logs, sweep_planner_tick
from ft_accum_scan import archive_gib, backups, done_cards


def route():
    """수신자 = seats-planner.json _hil_route → _master. 없으면 안 보내고 로그(옛 이름으로 대신 보내지 않음)."""
    sj = os.environ.get("FT_ACCUM_SEATS") or os.path.join(ROOT, ".fable-team", "seats-planner.json")
    try:
        with open(sj, encoding="utf-8") as fh:
            v = json.load(fh)
    except (OSError, ValueError):
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
