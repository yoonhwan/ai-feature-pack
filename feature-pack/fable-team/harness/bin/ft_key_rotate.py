#!/usr/bin/env python3
"""ft_key_rotate.py — 노출 키 교체 도구 본체 (R195). 값은 stdout·stderr·argv·env·임시 파일 어디에도 안 나간다.

사용(껍데기 ft-key-rotate.sh 경유):
  rotate [--paid-check] <KEY>      새 값 = stdin(클립보드). 활성 줄만 교체 + 백업 + 살아 있음 확인
  check-old [--paid-check] <KEY>   최신 백업의 옛 값으로 같은 확인 → REVOKED / STILL-VALID
  restore <KEY>                    최신 백업의 옛 값으로 그 키 줄만 되돌림
  status                           17키 표(교체 시각 · 지금 값 · 옛 값) — 값 0
시험 훅: HOME(zshrc 위치) · FT_KEY_ROTATE_ENV(루트 .env 위치) · PATH 앞 가짜 curl/op.
"""

import os
import re
import sys

import ft_key_rotate_io as fio
from ft_key_rotate_io import apply_all, apply_edits, latest_backup
from ft_key_rotate_lines import active, read_value, restore_line
from ft_key_rotate_table import KEYS, check


def say(*a):
    print(*a, flush=True)


def paths(key):
    return fio.file_paths(KEYS[key][0])


def get_value(key, which):
    p = paths(key)[0]
    src = latest_backup(p, key) if which == "old" else None
    return read_value(src or p, key)


def checked(key, which="now", paid=False):
    return check(key, lambda k: get_value(k, which), paid)


def clean(raw):
    v = raw[:-2] if raw.endswith("\r\n") else raw[:-1] if raw.endswith("\n") else raw
    if not v or re.search(r"\s", v):
        raise ValueError("클립보드 값이 비었거나 공백·줄바꿈 포함")
    return v


def cmd_rotate(key, paid):
    files = paths(key)
    new = clean(sys.stdin.read())
    if len(new) < KEYS[key][1]:
        raise ValueError("길이 %d < 최소 %d" % (len(new), KEYS[key][1]))
    for p in files:
        if read_value(p, key) == new:
            raise ValueError("클립보드가 옛 값 그대로")
    notes = sum(active(p, key)[1] for p in files)
    backups = apply_all(key, files, new, True)
    say("ROTATED %s len=%d files=%d backup=%s" % (key, len(new), len(files), ",".join(backups)))
    if notes:
        say("NOTE 주석 줄 %d개 남음(손대지 않음)" % notes)
    st, label = checked(key, "now", paid)
    say("%s %s %s" % (st, key, label))
    if st == "DEAD":
        say("되돌리기: ft-key-rotate.sh --restore %s" % key)
    say("NOTE 새 터미널·재기동 필요(실행 중 프로세스는 옛 값)")
    return 3 if st == "DEAD" else 5 if st == "CHECK-FAILED" else 0


def cmd_check_old(key, paid):
    if not latest_backup(paths(key)[0], key):
        raise ValueError("백업 없음 — 교체 이력 0")
    st, label = checked(key, "old", paid)
    say(("REVOKED" if st == "DEAD" else "STILL-VALID" if st == "ALIVE" else st), key, label)
    return 4 if st == "ALIVE" else 5 if st == "CHECK-FAILED" else 0


def cmd_restore(key):
    files = paths(key)
    edits = []
    for p in files:
        b = latest_backup(p, key)
        if not b:
            raise ValueError("%s 백업 없음" % os.path.basename(p))
        edits.append((p, restore_line(p, key, b)))
    apply_edits(key, edits, False)
    say("RESTORED %s files=%d" % (key, len(files)))
    return 0


def cmd_status():
    for key in KEYS:
        try:
            p = paths(key)[0]
            b = latest_backup(p, key)
            when = os.path.basename(b).split(".bak-keyrotate-%s-" % key)[-1][:15] if b else "-"
            now = " ".join(checked(key, "now")) if read_value(p, key) is not None else "ABSENT"
            old = "-"
            if b:
                st, label = checked(key, "old")
                old = "REVOKED" if st == "DEAD" else "STILL-VALID" if st == "ALIVE" else st
        except Exception as e:
            when, now, old = "-", "ERROR " + type(e).__name__, "-"
        say("%-34s group=%d rotated=%s now=[%s] old=%s" % (key, KEYS[key][2], when, now, old))
    return 0


def main(argv):
    if not argv:
        say(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    paid = "--paid-check" in rest
    rest = [a for a in rest if a != "--paid-check"]
    try:
        if cmd == "status":
            return cmd_status()
        if len(rest) != 1:
            raise ValueError(
                "usage: ft-key-rotate.sh [--check-old|--restore] [--paid-check] <KEY> | --status"
            )
        if rest[0] not in KEYS:
            raise ValueError("모르는 키 %s" % rest[0])
        key = rest[0]
        return {
            "rotate": lambda: cmd_rotate(key, paid),
            "check-old": lambda: cmd_check_old(key, paid),
            "restore": lambda: cmd_restore(key),
        }[cmd]()
    except (ValueError, OSError, RuntimeError) as e:
        say("REJECT", str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
