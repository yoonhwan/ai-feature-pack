#!/usr/bin/env python3
"""ft_key_rotate.py — 노출 키 교체 도구 본체 (R195). 값은 stdout·stderr·argv·env·임시 파일 어디에도 안 나간다.

사용(껍데기 ft-key-rotate.sh 경유):
  rotate [--paid-check] <KEY>      새 값 = stdin(클립보드). 활성 줄만 교체 + 백업 + 살아 있음 확인
  check-old [--paid-check] <KEY>   최신 백업의 옛 값으로 같은 확인 → REVOKED / STILL-VALID
  restore <KEY>                    최신 백업의 옛 값으로 그 키 줄만 되돌림
  status                           17키 표(교체 시각 · 지금 값 · 옛 값) + 묶음 × 단계 × 상태(값 0)
  resume <묶음> [--plan F] [--from-clipboard [--field ENV]]   불명은 조회로 확정한 뒤에만 다음 단계 · 값 출처 = 로컬 활성 줄 또는 재복사(지문 대조)
  abandon <묶음> --reason R --owner O --when W               중단 — 완료 표식 0 · 담당·재개 조건·남은 복사본 표 보존
rotate 옵션: --plan <JSON>(외부 단계 · byz-keys 가 준다) · --allow-open "<planner 범위 1줄>"(다른 묶음이 열려 있을 때)
시험 훅: HOME(zshrc 위치) · FT_KEY_ROTATE_ENV(루트 .env 위치) · FT_KEY_ROTATE_STATE(journal 폴더) · PATH 앞 가짜 curl/op.
"""

import os
import re
import sys

import ft_key_rotate_bundle as bun
import ft_key_rotate_io as fio
import ft_key_rotate_journal as jr
from ft_key_rotate_io import apply_edits, latest_backup
from ft_key_rotate_lines import active, read_value, restore_line, swap_line
from ft_key_rotate_steps import fields, load_plan, rep
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


GUIDE = "토큰만 복사(앞뒤 공백·줄바꿈 없이) 후 같은 줄 다시"


def reject_reason(v):
    """거절 이유 — 개수·위치만(값 글자 0)."""
    if not v:
        return "클립보드 값이 비었음\n" + GUIDE
    nl, tab = len(re.findall(r"[\r\n]", v)), v.count("\t")
    total = len(re.findall(r"\s", v))
    lead = len(v) if not v.strip() else len(v) - len(v.lstrip())
    trail = 0 if not v.strip() else len(v) - len(v.rstrip())
    return "클립보드 값에 공백·줄바꿈 포함: 공백 %d · 탭 %d · 줄바꿈 %d · 길이 %d · 위치 앞 %d · 가운데 %d · 뒤 %d\n%s" % (
        total - nl - tab, tab, nl, len(v), lead, total - lead - trail, trail, GUIDE
    )


def clean(raw):
    v = raw[:-2] if raw.endswith("\r\n") else raw[:-1] if raw.endswith("\n") else raw
    if not v or re.search(r"\s", v):
        raise ValueError(reject_reason(v))
    return v


def cmd_rotate(key, paid, plan_path=None, allow_open=None):
    files = paths(key)
    new = clean(sys.stdin.read())
    if len(new) < KEYS[key][1]:
        raise ValueError("길이 %d < 최소 %d" % (len(new), KEYS[key][1]))
    for p in files:
        if read_value(p, key) == new:
            raise ValueError("클립보드가 옛 값 그대로")
    notes = sum(active(p, key)[1] for p in files)
    edits = [(p, swap_line(p, key, new)) for p in files]  # 쓰기 «전» 거절은 시도를 열기 전에
    plan = load_plan(plan_path, KEYS[key][3])
    b, att, fresh = bun.begin(key, plan, allow_open)
    if fresh:
        bun.mark_dead_old(b, att, key, checked)
    box = {}
    bun.rotate_local(b, att, key, files, edits, new, box)
    say("ROTATED %s len=%d files=%d backup=%s" % (key, len(new), len(files), ",".join(box["backups"])))
    if notes:
        say("NOTE 주석 줄 %d개 남음(손대지 않음)" % notes)
    vals = bun.values_of(b, jr.current(b)[1])
    res = bun.drive(b, att, dict(vals, **{key: new}), plan, checked, paid, say, box)
    st, label = box.get("verify") or checked(key, "now", paid)
    say("%s %s %s" % (st, key, label))
    if res == "ok":
        bun.maybe_end(b, att)
    elif res == "wait":
        say("NOTE 묶음 %s 의 나머지 필드(%s) 교체 뒤 확인" % (b, ",".join(k for k in fields(b) if k != key)))
    say(bun.final_line(b))
    if st == "DEAD":
        say("되돌리기: ft-key-rotate.sh --restore %s" % key)
    say("NOTE 새 터미널·재기동 필요(실행 중 프로세스는 옛 값)")
    return 3 if st == "DEAD" else 5 if st == "CHECK-FAILED" else 6 if res in (jr.UNKNOWN, jr.NOT_RUN) else 0


def cmd_check_old(key, paid):
    if not latest_backup(paths(key)[0], key):
        raise ValueError("백업 없음 — 교체 이력 0")
    st, label = checked(key, "old", paid)
    say(("REVOKED" if st == "DEAD" else "STILL-VALID" if st == "ALIVE" else st), key, label)
    b = KEYS[key][3]
    if key == rep(b) and jr.current(b)[1]:
        bun.record_old_key(b, st, label)
        say(bun.final_line(b))
    return 4 if st == "ALIVE" else 5 if st == "CHECK-FAILED" else 0


def cmd_resume(b, plan_path, paid, clip, field):
    res = bun.resume(b, load_plan(plan_path, b), checked, paid, clip, field, say)
    say(bun.final_line(b))
    if res == "value":
        say("NOTE 새 값 필요 — 재복사 후 --resume %s --from-clipboard [--field ENV] (지문이 같을 때만 진행)" % b)
    return 6 if res in ("value", jr.UNKNOWN, jr.NOT_RUN) else 0


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
    for line in jr.status_lines():
        say(line)
    return 0


def main(argv):
    if not argv:
        say(__doc__)
        return 2
    cmd, rest = argv[0], list(argv[1:])
    try:
        paid = bun.opt(rest, "--paid-check", True)
        clip, plan, allow = bun.opt(rest, "--from-clipboard", True), bun.opt(rest, "--plan"), bun.opt(rest, "--allow-open")
        field, why, owner, when = (bun.opt(rest, o) for o in ("--field", "--reason", "--owner", "--when"))
        if cmd == "status":
            return cmd_status()
        if len(rest) != 1:
            raise ValueError(
                "usage: ft-key-rotate.sh [--check-old|--restore] [--paid-check] <KEY> | --status | --resume|--abandon <묶음>"
            )
        if cmd in ("resume", "abandon"):
            if not fields(rest[0]):
                raise ValueError("모르는 묶음 %s" % rest[0])
            if cmd == "abandon":
                return bun.abandon(rest[0], why, owner, when, say) or 0
            return cmd_resume(rest[0], plan, paid, clean(sys.stdin.read()) if clip else None, field)
        if rest[0] not in KEYS:
            raise ValueError("모르는 키 %s" % rest[0])
        key = rest[0]
        return {
            "rotate": lambda: cmd_rotate(key, paid, plan, allow),
            "check-old": lambda: cmd_check_old(key, paid),
            "restore": lambda: cmd_restore(key),
        }[cmd]()
    except (ValueError, OSError, RuntimeError) as e:
        say("REJECT", str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
