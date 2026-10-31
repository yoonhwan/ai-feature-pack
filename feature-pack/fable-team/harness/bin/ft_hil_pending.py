#!/usr/bin/env python3
"""ft_hil_pending.py <HIL_DIR> [--each] — `ft-hil.sh --pending` 본체(r521): h<N> 진입 파일을 한 번에 훑는다.

옛 셸 pending() 과 같은 규칙·같은 출력(바이트):
  센다 = 이름 h<숫자> · 일반 파일(링크 0) · 첫 `# ft-hil-entry plan=` 줄 값이 비지 않음 · <h>.superseded 없음(링크면 대상 기준)
  <h>.ran 없음 = 미실행(h mtime 기준 분) · .ran 마지막 줄이 `^rc=[0-9]* ` 행 = 끝(안 셈) · 아니면 중단/실행 중(마지막 epoch 줄 기준 분 ·
  epoch 줄이 없으면 .ran mtime 기준) · 분 = (지금 - 시각) / 60 을 0 쪽으로 버림(셸 산술과 같음)
  r1124: .ran 은 실행마다 «epoch» + «rc=…» 를 이어 쓴다 — 재실행 중이면 앞 실행의 rc 행이 있어도 «실행 중» 으로 센다
  출력 = --each 면 `h<N> <분>` 줄만 · 아니면 1개 이상일 때 요약 1줄 · 0개 = 출력 0 rc 0(폴더 없음 포함)
r1236 보류: <h>.held 마지막 줄이 `hold <epoch> <좌석> <사유>` 면 보류 — 미실행 목록(--each · 요약)에서 빠진다.
  `--held` = 보류만 `h<N> <분> <사유>` 줄로 · `--each --held` = 미실행 줄 뒤에 `held h<N> <분> <사유>` 줄(뉴스 칸 1회 호출용)
  `--hold h<N> --why <사유>` · `--unhold h<N>` = <h>.held 에 1줄 이어 쓰기(일반 파일) · 없는 h = rc 2 · 표식 0
읽기 실패(폴더·h 파일·.ran 권한 등) = stdout 0 · stderr 1줄 · rc 3 — 조용한 0 아님. 파일 쓰기·삭제 0.
"""
import os
import re
import subprocess
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


def held_why(path):
    """<h>.held 마지막 줄이 `hold <epoch> <좌석> <사유>` 면 사유(빈 사유는 «-») · 아니면 None. 표식 없음 = None."""
    try:
        with open(path + ".held", "rb") as f:
            lines = [x for x in f.read().decode("utf-8", "replace").split("\n") if x.strip()]
    except FileNotFoundError:
        return None
    parts = lines[-1].split(" ", 3) if lines else []
    return (parts[3].strip() or "-") if len(parts) >= 3 and parts[0] == "hold" else None


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
            rows.append((m.group(1), got[0], got[1], held_why(e.path)))
    return rows


def seat():
    if not os.environ.get("TMUX_PANE"):
        return "-"
    try:
        out = subprocess.run(["tmux", "display-message", "-p", "-t", os.environ["TMUX_PANE"], "#S"], capture_output=True, text=True, timeout=3)
        return out.stdout.strip().replace(" ", "_") or "-" if out.returncode == 0 else "-"
    except (OSError, subprocess.SubprocessError):
        return "-"


def mark(d, argv):
    """--hold h<N> --why <사유> | --unhold h<N> → <h>.held 에 1줄 이어 쓰기. 없는 h = rc 2 · 표식 0 · 쓰기 실패 = rc 3."""
    verb, rest = argv[0], argv[1:]
    if not rest or not re.fullmatch(r"h[0-9]+", rest[0]) or (verb == "--hold" and (len(rest) < 3 or rest[1] != "--why")):
        print("usage: ft-hil.sh --hold h<N> --why <사유> | --unhold h<N>", file=sys.stderr)
        return 2
    path = os.path.join(d, rest[0])
    if os.path.islink(path) or not os.path.isfile(path):
        print("REJECT %s 가 없다(진입 파일만 보류할 수 있다): %s" % (rest[0], path), file=sys.stderr)
        return 2
    why = " ".join(" ".join(rest[2:]).split()) or "-"
    line = "hold %d %s %s\n" % (time.time(), seat(), why) if verb == "--hold" else "unhold %d %s\n" % (time.time(), seat())
    try:
        with open(path + ".held", "a", encoding="utf-8") as f:
            f.write(line)
    except OSError as e:
        print("ERROR ft-hil %s 못 씀: %s: %s" % (verb, e.filename, e.strerror), file=sys.stderr)
        return 3
    print("%s %s" % ("보류" if verb == "--hold" else "보류 해제", rest[0]))
    return 0


def main(argv):
    if len(argv) < 2:
        print("usage: ft_hil_pending.py <HIL_DIR> [--each] [--held] | --hold h<N> --why <사유> | --unhold h<N>", file=sys.stderr)
        return 2
    if len(argv) > 2 and argv[2] in ("--hold", "--unhold"):
        return mark(argv[1], argv[2:])
    try:
        rows = scan(argv[1])
    except OSError as e:
        print("ERROR ft-hil --pending 읽기 실패: %s: %s" % (e.filename or argv[1], e.strerror or e), file=sys.stderr)
        return 3
    flags = set(argv[2:])
    live, held = [r for r in rows if r[3] is None], [r for r in rows if r[3] is not None]
    if "--each" in flags or "--held" in flags:
        pre = "held " if "--each" in flags else ""
        sys.stdout.write("".join("h%s %d\n" % (n, a) for n, a, _, _ in live) if "--each" in flags else "")
        if "--held" in flags:
            sys.stdout.write("".join("%sh%s %d %s\n" % (pre, n, a, w) for n, a, _, w in held))
    elif live:
        old = max([0] + [a for _, a, _, _ in live])
        r = sum(1 for *_, run, _w in live if run)
        extra = " (중단/실행 중 %d개 포함)" % r if r else ""
        print("미실행 h %d개%s · 가장 오래된 %d분%s" % (len(live), extra, old, " · 보류 %d개" % len(held) if held else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
