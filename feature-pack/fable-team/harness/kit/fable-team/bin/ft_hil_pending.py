#!/usr/bin/env python3
"""ft_hil_pending.py <HIL_DIR> [--each] — `ft-hil.sh --pending` 본체(r521): h<N> 진입 파일을 한 번에 훑는다.

옛 셸 pending() 과 같은 규칙·같은 출력(바이트):
  센다 = 이름 h<숫자> · 일반 파일(링크 0) · 첫 `# ft-hil-entry plan=` 줄 값이 비지 않음 · <h>.superseded 없음(링크면 대상 기준)
  <h>.ran 없음 = 미실행(h mtime 기준 분) · .ran 마지막 줄이 `^rc=[0-9]* ` 행 = 끝(안 셈) · 아니면 중단/실행 중(마지막 epoch 줄 기준 분 ·
  epoch 줄이 없으면 .ran mtime 기준) · 분 = (지금 - 시각) / 60 을 0 쪽으로 버림(셸 산술과 같음)
  r1124: .ran 은 실행마다 «epoch» + «rc=…» 를 이어 쓴다 — 재실행 중이면 앞 실행의 rc 행이 있어도 «실행 중» 으로 센다
  출력 = --each 면 `h<N> <분>` 줄만 · 아니면 1개 이상일 때 요약 1줄 · 0개 = 출력 0 rc 0(폴더 없음 포함)
읽기 실패(폴더·h 파일·.ran 권한 등) = stdout 0 · stderr 1줄 · rc 3 — 조용한 0 아님. 파일 쓰기·삭제 0.
"""
import os
import re
import sys
import time

NAME = re.compile(r"h([0-9]+)", re.ASCII)
MARK = b"# ft-hil-entry plan="
DONE = re.compile(rb"^rc=[0-9]* ", re.MULTILINE)
EPOCH = re.compile(rb"[0-9]+")


def minutes(now, t):
    d = now - t
    return d // 60 if d >= 0 else -((-d) // 60)


def has_plan(data):
    for line in data.split(b"\n"):
        if line.startswith(MARK):
            return line != MARK
    return False


def age_of(path, now):
    """(분, 실행 중 여부) = 셈 · None = 안 셈(계획 표식 없음 · 대체됨 · 끝남)."""
    with open(path, "rb") as f:
        if not has_plan(f.read()):
            return None
    if os.path.exists(path + ".superseded"):
        return None
    ran = path + ".ran"
    if not os.path.exists(ran):
        return minutes(now, int(os.lstat(path).st_mtime)), False
    with open(ran, "rb") as f:
        data = f.read()
    lines = [x for x in data.split(b"\n") if x]
    if lines and DONE.match(lines[-1]):
        return None
    starts = [x for x in lines if EPOCH.fullmatch(x)]
    t = int(starts[-1]) if starts else int(os.lstat(ran).st_mtime)
    return minutes(now, t), True


def scan(d):
    try:
        entries = sorted(os.scandir(d), key=lambda e: e.name)
    except FileNotFoundError:
        return []
    now, rows = int(time.time()), []
    for e in entries:
        m = NAME.fullmatch(e.name)
        if not m or e.is_symlink() or not e.is_file(follow_symlinks=False):
            continue
        got = age_of(e.path, now)
        if got:
            rows.append((m.group(1), got[0], got[1]))
    return rows


def main(argv):
    if len(argv) < 2:
        print("usage: ft_hil_pending.py <HIL_DIR> [--each]", file=sys.stderr)
        return 2
    try:
        rows = scan(argv[1])
    except OSError as e:
        print("ERROR ft-hil --pending 읽기 실패: %s: %s" % (e.filename or argv[1], e.strerror or e), file=sys.stderr)
        return 3
    if len(argv) > 2 and argv[2] == "--each":
        sys.stdout.write("".join("h%s %d\n" % (n, a) for n, a, _ in rows))
    elif rows:
        old = max([0] + [a for _, a, _ in rows])
        r = sum(1 for *_, run in rows if run)
        extra = " (중단/실행 중 %d개 포함)" % r if r else ""
        print("미실행 h %d개%s · 가장 오래된 %d분" % (len(rows), extra, old))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
