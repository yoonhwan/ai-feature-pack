#!/usr/bin/env python3
"""ft_postboot_measure.py — r868: 재부팅 직후 기준선(BASELINE-postboot-20261025.md 00:33)과 같은 명령으로 2시간마다 재측정.
오빠 지시(10-25 00:3x) «재부팅 직후 기준선 대비 같은 명령 2시간 주기 재측정 → 쌓이는 원인별 닫는 사건 설계».
읽기 전용 — 부르는 명령은 CMDS 10개뿐(kill·rm·worktree 변경 0). 명령마다 7초 상한(FT_POSTBOOT_CMD_TIMEOUT · 전역 하드 룰 12
— env 가 7 을 넘겨도 min(env, 7)), lsof +L1 만 크기 비례(min(고정비 + 7초 × ceil(프로세스/500), 70초 천장)).
넘으면 그 칸 «시간 초과»(tmux 는 «오류(시간 초과)») · 실패 «실패(…)» · tmux 접속 실패 «오류(사유)» · lsof 불완전/incomplete 경고 «불완전(사유) 참고=값» — 0·빈 칸으로 숨김 0(#0 RULE).
세션 수는 `tmux ls -F '#{session_id}'` 의 id 줄만 센다(이름에 개행이 있어도 1개) · «no server running» 판정은 «줄 머리»에 있어야 한다(경로 속 같은 글자 = 접속 오류).
하루 요약 기본 자리 = 상태 파일과 같은 폴더(쓰기 범위 = 상태 폴더 안) · 다른 자리는 FT_POSTBOOT_SUMMARY_DIR 로만.
로그 닫는 사건 — stdout/err 는 상태 파일 옆 postboot-measure.log 1개(plist) · 날이 바뀐 첫 회(하루 요약)에 비우고 그 밖엔 1MiB 넘으면 회전.
사용: ft-postboot-measure.sh            → 1회 측정 · 상태 파일 1행 · 날이 바뀐 첫 회면 전날 요약 1장 · stdout 1줄
      ft-postboot-measure.sh --summary  → 오늘 요약 1장 지금(측정 0)
env: FT_ROOT(필수) · FT_NOW(시계 · 시험) · FT_POSTBOOT_SUMMARY_DIR(요약 폴더 · 기본 <루트>/design/teams/planner/postboot) · FT_POSTBOOT_KEEP_DAYS(14)."""
import math
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft_postboot_report as rep  # noqa: E402

TIMEOUT_CELL = "시간 초과"
TMUX_TIMEOUT = "오류(시간 초과)"   # tmux 칸의 실패 형식은 «오류(사유)» 하나로 통일(시간 초과도 오류다)
MAX_BASE = 7.0        # 명령 1회 절대 상한(전역 하드 룰 12) — env 로 이 값을 넘길 수 없다
BATCH = 500           # lsof 크기 비례 기준량(프로세스)
MAX_CAP = 70.0        # 크기 비례 천장
LOG_MAX = 1048576     # 측정 잡 로그 1MiB 회전(넘으면 스스로 닫는다)
LOG_NAME = "postboot-measure.log"
DF_PATH = "/System/Volumes/Data"
PS_ARGS = ["ps", "-axo", "pid=,rss=,pcpu=,args="]


def cmds(root):
    return {"uptime": ["uptime"], "boot": ["sysctl", "-n", "kern.boottime"], "swap": ["sysctl", "-n", "vm.swapusage"],
            "mem": ["memory_pressure"], "df": ["df", "-k", DF_PATH], "ps": PS_ARGS, "tmux": ["tmux", "ls", "-F", "#{session_id}"],
            "wt": ["git", "-C", root, "worktree", "list", "--porcelain"], "lsof": ["lsof", "-nP", "+L1"],
            "colima": ["colima", "status"]}


def base_cap(val):
    """명령 1회 상한 — env 값은 min(env, 7). 없음·해석 불가·0 이하는 7초."""
    try:
        v = float(val)
    except (TypeError, ValueError):
        return MAX_BASE
    return min(v, MAX_BASE) if v > 0 else MAX_BASE


def lsof_cap(procs, base):
    """lsof +L1 는 프로세스 수에 비례 — min(고정비 + 7초 × ceil(프로세스/500), 70초) · 프로세스 수 모르면 고정비만(크기 아는 배치만 늘린다)."""
    if not procs:
        return base
    return min(base + MAX_BASE * math.ceil(procs / BATCH), MAX_CAP)


def run(argv, cap, on_timeout=TIMEOUT_CELL):
    """(rc, stdout, stderr) 또는 셀 문자열(시간 초과·실패). 쓰기 0 — argv 는 CMDS 에서만 온다."""
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=cap, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return on_timeout
    except OSError as e:
        return "실패(%s)" % type(e).__name__
    return p.returncode, p.stdout, p.stderr


def num(out, pat, conv=float):
    m = re.search(pat, out)
    if not m:
        raise ValueError("해석 실패")
    return conv(m.group(1))


def classify_ps(out):
    n = {"claude": 0, "node": 0, "python": 0, "pi": 0, "limactl": 0, "next": 0}
    rss = {"claude": 0, "pi": 0}
    cpu_next = 0.0
    procs = 0
    for ln in out.splitlines():
        f = ln.split(None, 3)
        if len(f) < 4:
            continue
        procs += 1
        name = os.path.basename(f[3].split()[0])
        if f[3].startswith("next-server"):
            n["next"] += 1
            cpu_next += float(f[2])
            continue
        key = "python" if name.lower().startswith("python") else name
        if key in n:
            n[key] += 1
        if key in rss:
            rss[key] += int(f[1])
    return procs, n, rss, cpu_next


def parse_lsof(out):
    by = {}
    for ln in out.splitlines()[1:]:
        f = ln.split(None, 9)
        if len(f) >= 9 and f[4] == "REG" and f[6].isdigit():
            k = "%s:%s" % (f[0], f[1])
            by[k] = by.get(k, 0) + int(f[6])
    top = sorted(by.items(), key=lambda kv: -kv[1])[:5]
    return round(sum(by.values()) / 1048576), " ".join("%s=%d" % (k, round(v / 1048576)) for k, v in top) or "없음"


def cell(res, parse):
    if isinstance(res, str):
        return res
    rc, out, err = res
    try:
        return parse(rc, out, err)
    except (ValueError, IndexError) as e:
        return "실패(rc=%d %s)" % (rc, str(e)[:40])


def ok_rc(rc, err):
    if rc != 0:
        raise ValueError("rc≠0 " + err.strip()[:30])


def measure(root, now, base):
    c = cmds(root)
    row: dict = {"ts": str(now), "at": time.strftime("%Y-%m-%d %H:%M", time.localtime(now))}
    ps = run(c["ps"], base)
    procs = None
    if isinstance(ps, tuple) and ps[0] == 0:
        procs, n, rss, cpu_next = classify_ps(ps[1])
        row.update(procs=procs, claude_n=n["claude"], claude_rss_mib=rss["claude"] // 1024, node_n=n["node"],
                   python_n=n["python"], pi_n=n["pi"], pi_rss_mib=rss["pi"] // 1024, limactl_n=n["limactl"],
                   next_n=n["next"], next_cpu="%.1f" % cpu_next)
    else:
        v = ps if isinstance(ps, str) else "실패(rc=%d)" % ps[0]
        row.update({k: v for k in rep.PS_KEYS})
    boot = cell(run(c["boot"], base), lambda rc, o, e: (ok_rc(rc, e), num(o, r"sec = (\d+)", int))[1])
    row["boot_min"] = (now - boot) // 60 if isinstance(boot, int) else boot
    row["load15"] = cell(run(c["uptime"], base), lambda rc, o, e: (ok_rc(rc, e), "%.2f" % num(o, r"load averages?: [\d.]+,? [\d.]+,? ([\d.]+)"))[1])
    row["swap_used_mib"] = cell(run(c["swap"], base), lambda rc, o, e: (ok_rc(rc, e), round(num(o, r"used = ([\d.]+)M")))[1])
    row["mem_free_pct"] = cell(run(c["mem"], base), lambda rc, o, e: (ok_rc(rc, e), num(o, r"free percentage: (\d+)%", int))[1])
    row["disk_avail_gib"] = cell(run(c["df"], base), lambda rc, o, e: (ok_rc(rc, e), "%.1f" % (int(o.splitlines()[-1].split()[3]) / 1048576))[1])
    row["tmux_n"] = cell(run(c["tmux"], base, TMUX_TIMEOUT), tmux_n)
    row["worktrees_n"] = cell(run(c["wt"], base), lambda rc, o, e: (ok_rc(rc, e), sum(1 for x in o.splitlines() if x.startswith("worktree ")))[1])
    ls = run(c["lsof"], lsof_cap(procs, base))
    d = cell(ls, lambda rc, o, e: lsof_row(rc, o, e))
    row["deleted_mib"], row["deleted_top"] = d if isinstance(d, tuple) else (d, d)
    row["colima"] = cell(run(c["colima"], base), colima_state)
    return row


def tmux_n(rc, out, err):
    """tmux ls -F '#{session_id}' — id 줄($N)만 세션으로 센다(이름에 개행이 있어도 1개).
    «no server running» 은 «줄 머리»에 있을 때만 세션 0(경로 속 같은 글자는 접속 오류). 그 밖 실패 = «오류(사유)»(0 숨김 0)."""
    if rc == 0:
        return sum(1 for x in out.splitlines() if re.match(r"^\$\d+$", x.strip()))
    txt = err.strip() or out.strip()
    if re.search(r"(?m)^\s*no server running\b", txt):
        return 0   # 서버 없음 = 세션 0(진짜 0)
    return "오류(rc=%d %s)" % (rc, (txt.splitlines()[0] if txt else "사유 없음")[:40])


def lsof_row(rc, out, err):
    """lsof +L1 — rc≠0 이거나 stderr 에 incomplete 경고가 있으면 stdout 이 있어도 «불완전(사유) 참고=값»(0 으로 숨김 0).
    stdout 이 없으면 참고=0(계약: 불완전이면 참고값을 반드시 남긴다)."""
    txt = err.strip() or out.strip()
    why = (txt.splitlines()[0] if txt else "사유 없음")[:40]
    if rc == 0 and not re.search(r"incomplete", txt, re.I):
        return parse_lsof(out)
    mib, top = parse_lsof(out) if out.strip() else (0, "없음")
    return "불완전(rc=%d %s) 참고=%d" % (rc, why, mib), top


def log_path(state):
    return os.path.join(os.path.dirname(state), LOG_NAME)


def manage_log(path, rotate=None):
    """측정 잡 로그의 닫는 사건 — rotate(요약 쓴 날 시각)면 비우고, 그 밖엔 1MiB 넘으면 회전. 반환 = «비움»/«회전»/«-»."""
    try:
        size = os.path.getsize(path)
    except OSError:
        return "-"
    if rotate:
        mark = "# 하루 요약 %s — 로그 비움(닫는 사건)" % time.strftime("%Y-%m-%d", time.localtime(rotate))
        act = "비움"
    elif size > LOG_MAX:
        mark = "# 로그 회전 — %d bytes > %d, 오래된 줄 버림(닫는 사건)" % (size, LOG_MAX)
        act = "회전"
    else:
        return "-"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(mark + "\n")
    return act


def colima_state(rc, out, err):
    txt = (out + err).strip()
    if rc == 0 and "is running" in txt:
        return "실행"
    last = re.findall(r'msg="([^"]+)"', txt)
    return "중지(rc=%d %s)" % (rc, (last[-1] if last else txt.splitlines()[-1] if txt else "")[:40])


def main(argv):
    root = os.environ.get("FT_ROOT")
    if not root or not os.path.isdir(root):
        print("ERROR ft-postboot-measure: FT_ROOT 없음 또는 폴더 아님 (%r) — launchd plist 의 FT_ROOT 확인" % root, file=sys.stderr)
        return 2
    now = int(os.environ.get("FT_NOW") or time.time())
    base = base_cap(os.environ.get("FT_POSTBOOT_CMD_TIMEOUT", "7"))
    state = os.path.join(root, ".fable-team", "state", "postboot-measure.tsv")
    sumdir = os.environ.get("FT_POSTBOOT_SUMMARY_DIR") or os.path.dirname(state)
    log = log_path(state)
    if argv[1:] == ["--summary"]:
        try:
            dst = rep.write_summary(state, sumdir, now, None)
        except (OSError, RuntimeError) as e:
            print("ERROR ft-postboot-measure: 요약 실패 — %s: %s" % (type(e).__name__, e), file=sys.stderr)
            print("postboot-measure summary=%s log=%s" % ("실패(%s)" % type(e).__name__, manage_log(log, now)))
            return 1
        print("postboot-measure summary=%s log=%s" % (dst, manage_log(log, now)))
        return 0
    if argv[1:]:
        print("usage: ft-postboot-measure.sh [--summary]", file=sys.stderr)
        return 2
    row = measure(root, now, base)
    rc, summ = 0, "-"
    try:
        prev_day = rep.append_row(state, row, now, int(os.environ.get("FT_POSTBOOT_KEEP_DAYS", "14")))
        summ = rep.write_summary(state, sumdir, now, prev_day) if prev_day else "-"
        logst = manage_log(log, now if prev_day else None)
    except (OSError, RuntimeError) as e:  # 상태 기록·요약 실패 — 이 회차만 실패로 적는다
        print("ERROR ft-postboot-measure: 상태 기록 실패 — %s: %s" % (type(e).__name__, e), file=sys.stderr)
        rc, summ, logst = 1, "실패(%s)" % type(e).__name__, "-"
    tos = sum(1 for k, v in row.items() if v == TIMEOUT_CELL and k != "deleted_top")
    print("postboot-measure at=%s boot=%sm disk=%sGi swap=%sM load15=%s claude=%s tmux=%s wt=%s deleted=%sM timeouts=%d summary=%s log=%s" % (
        row["at"], row["boot_min"], row["disk_avail_gib"], row["swap_used_mib"], row["load15"], row["claude_n"],
        row["tmux_n"], row["worktrees_n"], row["deleted_mib"], tos, summ, logst))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
