#!/usr/bin/env python3
"""ft_postboot_report.py — r868 측정 상태 파일(.fable-team/state/postboot-measure.tsv) 쓰기 + 하루 요약 1장(열 묶음).
상태 파일 닫는 사건 = 기록할 때마다 KEEP_DAYS 지난 행을 뺀다(원자 교체). 요약은 날마다 1장(같은 날 덮어쓰기) · 커밋 0 —
요약을 추적 경로에 올리는 것은 arch·master(측정 잡은 git 쓰기 0) — 기본 자리 = 상태 파일과 같은 폴더(쓰기 범위 = 상태 폴더 안) · 다른 자리는 FT_POSTBOOT_SUMMARY_DIR 로만. 기준선 = BASELINE-postboot-20261025.md «원시 출력 (00:33:05)»."""
import os
import time

COLS = ["ts", "at", "boot_min", "disk_avail_gib", "swap_used_mib", "mem_free_pct", "load15", "procs", "claude_n",
        "claude_rss_mib", "node_n", "python_n", "pi_n", "pi_rss_mib", "limactl_n", "next_n", "next_cpu", "tmux_n",
        "worktrees_n", "deleted_mib", "deleted_top", "colima"]
PS_KEYS = ["procs", "claude_n", "claude_rss_mib", "node_n", "python_n", "pi_n", "pi_rss_mib", "limactl_n", "next_n", "next_cpu"]
# (칸, 이름, 기준선 값 — None = 기준선에 없음) · 앞 9줄 = 기준선 표 항목 · 뒤 = 원인 4 보조 줄
ROWS = [("disk_avail_gib", "디스크 여유 GiB", 182), ("swap_used_mib", "스왑 사용 MiB", 0), ("mem_free_pct", "메모리 여유 %", 91),
        ("load15", "부하 load 15분", 9.71), ("claude_n", "claude 프로세스", 18), ("next_n", "웹 next-server 수", 0),
        ("colima", "colima 상태", None), ("tmux_n", "tmux 세션", 6), ("worktrees_n", "워크트리", 441),
        ("deleted_mib", "① 지운 채 쥔 파일 MiB(lsof +L1)", None), ("deleted_top", "① 쥔 프로세스 상위 5(이름:pid=MiB)", None),
        ("pi_n", "② pi 프로세스", 11), ("pi_rss_mib", "② pi RSS MiB", None), ("claude_rss_mib", "② claude RSS MiB", None),
        ("node_n", "② node 프로세스", 18), ("python_n", "② python 프로세스", 20), ("procs", "② 전체 프로세스", 695),
        ("next_cpu", "③ next-server CPU %", None), ("limactl_n", "④ limactl 프로세스", 2), ("boot_min", "부팅 뒤 경과 분", 11)]
HEAD = "# r868 postboot-measure 상태 — 행 = 측정 1회 · KEEP_DAYS 지난 행은 다음 기록 때 빠짐(닫는 사건)"


def day(ts):
    return time.strftime("%Y-%m-%d", time.localtime(int(ts)))


def read_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as fh:
        lines = [x.rstrip("\n") for x in fh if not x.startswith("#")]
    if not lines or lines[0].split("\t") != COLS:
        raise RuntimeError("상태 파일 머리가 COLS 와 다름: %s — 옮기거나 지우고 다시(조용한 덮어쓰기 0)" % path)
    return [dict(zip(COLS, x.split("\t"))) for x in lines[1:] if x]


def atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.tmp-%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def last_day(path):
    """직전 행의 날짜(읽기 전용 · 없거나 읽기 실패면 None) — 상태 쓰기가 실패해도 로그 닫는 사건의 날 경계를 안다."""
    try:
        rows = read_rows(path)
    except (OSError, RuntimeError):
        return None
    return day(rows[-1]["ts"]) if rows else None


def append_row(path, row, now, keep_days):
    """1행 추가 + 보관 기간 밖 행 정리. 반환 = 직전 행의 날짜(오늘과 다를 때만 · 그날 요약을 쓸 차례) 또는 None."""
    rows = read_rows(path)
    prev = day(rows[-1]["ts"]) if rows else None
    cut = now - keep_days * 86400
    rows = [r for r in rows if int(r["ts"]) >= cut] + [{k: str(row.get(k, "")) for k in COLS}]
    body = [HEAD, "\t".join(COLS)] + ["\t".join(r[k].replace("\t", " ") for k in COLS) for r in rows]
    atomic_write(path, "\n".join(body) + "\n")
    return prev if prev and prev != day(now) else None


def diff(last, base):
    try:
        d = float(last) - float(base)
    except (TypeError, ValueError):
        return "—"
    return ("+%.1f" % d if d > 0 else ("%.1f" % d).replace("-", "−")) if d else "0"


def write_summary(path, sumdir, now, which_day):
    d = which_day or day(now)
    rows = [r for r in read_rows(path) if day(r["ts"]) == d]
    hdr = ["항목", "기준선 (재부팅 직후 00:33)"] + ["%s · 부팅 %s분" % (r["at"][11:], r["boot_min"]) for r in rows] + ["차이 (마지막 − 기준선)"]
    out = ["# 재부팅 기준선 재측정 요약 — %s (r868 · 측정 %d회)" % (d, len(rows)), "",
           "> 원본 = `.fable-team/state/postboot-measure.tsv` · 기준선 = design/teams/planner/BASELINE-postboot-20261025.md 원시 출력 00:33",
           "> «시간 초과»·«실패(…)» 칸은 그대로 둔다(0·빈 칸으로 숨김 0). 이 파일은 측정 잡이 커밋하지 않는다.", "",
           "| " + " | ".join(hdr) + " |", "|" + "---|" * len(hdr)]
    for key, name, base in ROWS:
        vals = [r.get(key, "").replace("|", "/") for r in rows]   # 실패 원문의 | 가 표를 깨지 않게
        last = vals[-1] if vals else None
        b = "—" if base is None else str(base)
        out.append("| " + " | ".join([name, b] + vals + [diff(last, base) if base is not None else "—"]) + " |")
    dst = os.path.join(sumdir, "SUMMARY-postboot-%s.md" % d)
    atomic_write(dst, "\n".join(out) + "\n")
    return dst
