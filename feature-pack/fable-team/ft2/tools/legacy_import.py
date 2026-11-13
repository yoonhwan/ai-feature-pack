#!/usr/bin/env python3
"""ft 2.0 1.x→2.0 가져오기 도구 (카드 r1774 · DESIGN legacy-import-r1774 §4~§6).

입력 = r1676 꼴 reconcile.json 의 decision=«옮김» 행. 행마다 원본 바이트를 읽어 held 사본
(`<루트>/.fable-team/state/ft20-switch/<팀>.held/<cat>/<이름>`)을 두고, core/legacy_import.py 로 import 줄 1개를 더한다.
원본 삭제·이동 0 · 표식 쓰기 0 · 쓰는 runtime = `--team` 하나뿐(경로 인자 없음).

    python3 tools/legacy_import.py --root R --team T --reconcile <reconcile.json> [--dry-run | --precheck] [--rehold]
--rehold(r1875) = «held 사본 sha 다름» 행 중 아직 import 안 된 key 만 옛 held → `<이름>.prev-<ts>` 뒤 다시 쓴다.

끝 1줄 = «가져온 수 N · 건너뜀 M(이미 가져옴 a · 겹침 b) · 용량 거절 e · 누락 c · 원본 sha 변화 d · revision 전->후».
rc 0 = 누락·sha 변화·용량 거절 0 · 1 = 누락·sha 변화·팀 거부·용량 거절 · 2 = 판정 불가·복구 필요 · 64 = 인자.
"""
import argparse
import collections
import hashlib
import importlib.util
import json
import os
import re
import sys
import time

_CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core", "legacy_import.py")
TARGET = re.compile(r"^2\.0 (?:record: |intake: )?(card/(?:r\d+|(?!r\d+[-_]|.*\.md$)[^/\n\t]+)|mbox/\d+|seat/.+)$")  # r1811 이름 열쇠
USAGE = 64
_ts = lambda: time.strftime("%Y%m%dT%H%M%S")  # noqa: E731 — r1875 .prev 꼬리(시험이 바꾼다)


def _core():
    spec = importlib.util.spec_from_file_location("ft2_tool_legacy_import_core", _CORE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Skip(Exception):
    """그 행은 가져오지 못한다(누락 사유 1낱말)."""


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def _key(row):
    """target_id → (key, cat, 이름 몸통). 꼴이 다르면 Skip."""
    hit = TARGET.match(str(row.get("target_id") or ""))
    if not hit:
        raise Skip("대상 미상")
    target = hit.group(1)
    cat = {"card": "card", "mbox": "intake", "seat": "seat"}[target.split("/", 1)[0]]
    return (target if cat != "intake" else "intake/" + target), cat, target.split("/", 1)[1]


def _name(row, cat, stem):
    name = {"card": os.path.basename(str(row.get("loc") or "")), "intake": "mbox-%s.json" % stem,
            "seat": "%s.json" % stem}[cat]
    if not name or "/" in name or name in (".", "..") or "\n" in name or "\t" in name:
        raise Skip("이름 불가")
    return name


def _src(row, name):
    """r1831 I1 — loc 끝 이름 = held 이름이면 폴더만(원본 경로 = src + "/" + held 이름) · 다르면(intake 등) loc 그대로."""
    loc = str(row.get("loc"))
    head, tail = os.path.split(loc)
    return head if head and tail == name else loc


def line_size(team, seq, at, row, nbytes=99999999, core=None):
    """원본 없이 import 줄 크기만 잰다(실제 build_line·line_bytes) — 꼴이 다르면 None."""
    try:
        key, cat, stem = _key(row)
        name = _name(row, cat, stem)
    except Skip:
        return None
    core = core or _core()
    rec = core.build_line(team, seq, at, dict(key=key, body=cat + "/" + name, src=_src(row, name),
                                              sha256="0" * 64, bytes=nbytes))
    return core.journal.line_bytes(rec)


def _mail_line(path, seq):
    if not os.path.exists(path):
        path = os.path.join(os.path.dirname(path), "mailbox.log.jsonl")
    with open(path, "rb") as handle:
        for line in handle:
            try:
                if json.loads(line).get("seq") == seq:
                    return line                 # 원본 줄 바이트 그대로(끝 LF 포함 · DA R1)
            except (ValueError, AttributeError):
                continue
    raise Skip("원본 없음")


def _source(root, cards, team, row, cat, stem, meta=None):
    """원본 바이트 1개. 없거나 팀 밖이면 Skip. 명부 = meta.seats(r1811 대조기가 푼 이름) · 없으면 seats-<팀>.json."""
    loc = str(row.get("loc") or "")
    try:
        if cat == "card":
            path = os.path.join(cards, loc) if os.path.exists(os.path.join(cards, loc)) else os.path.join(root, loc)
            with open(path, "rb") as handle:
                return handle.read()
        if cat == "intake":
            return _mail_line(os.path.join(root, loc.split("#", 1)[0]), int(stem))
        if os.path.basename(loc) != os.path.basename(str((meta or {}).get("seats") or "seats-%s.json" % team)):
            raise Skip("팀 밖")
        with open(os.path.join(root, loc), encoding="utf-8") as handle:
            seats = json.load(handle)
        if stem not in seats:
            raise Skip("원본 없음")
        return json.dumps(seats[stem], sort_keys=True, ensure_ascii=False).encode("utf-8")
    except (OSError, ValueError):
        raise Skip("원본 없음")


def _team_of(meta, rows):
    """reconcile 의 팀 — meta.team · 없으면 rules 의 seats-<팀>.json · 카드 loc 의 design/<팀>/. 여러 팀 = 쉼표로 묶음."""
    if meta.get("team"):
        return str(meta["team"])
    found = set(re.findall(r"seats-([\w-]+)\.json", json.dumps(meta.get("rules") or [], ensure_ascii=False)))
    for row in rows:
        hit = re.match(r"design/([^/]+)/", str(row.get("loc") or "")) if row.get("cat") == "카드" else None
        found |= {hit.group(1)} if hit else set()
    return ",".join(sorted(found))


def _held(path, data, dry):
    """held 사본 — 같은 이름이 있으면 sha 대조(다름 = False). 없으면 tmp → fsync → rename → 폴더 fsync."""
    if os.path.lexists(path):
        with open(path, "rb") as handle:
            return _sha(handle.read()) == _sha(data)
    if dry:
        return True
    tmp_dir = os.path.join(os.path.dirname(os.path.dirname(path)), ".tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = os.path.join(tmp_dir, os.path.basename(path))
    with open(tmp, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)
    fd = os.open(os.path.dirname(path), os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
    return True


def _prev(path):
    """r1875 옛 held → <이름>.prev-<ts>(충돌 = .1·.2 순번) · link 라 덮어쓰기 0."""
    base = dst = "%s.prev-%s" % (path, _ts())
    while True:
        try:
            os.link(path, dst)
            break
        except FileExistsError:
            dst = "%s.%d" % (base, int(dst[len(base) + 1:] or 0) + 1)
    os.unlink(path)
    return dst


def _inventory(meta):
    """r1875 수집값 {loc: sha256} — 못 읽으면 빈 dict(그 행 = 판정 불가)."""
    try:
        with open(str(meta.get("inventory") or ""), encoding="utf-8") as handle:
            return {str(item.get("loc")): item.get("sha256") for item in json.load(handle)["items"]}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return {}


def main(argv, caps=None, on_step=None, out=None):
    out, step, say = out or sys.stdout, on_step or (lambda name: None), (lambda text: out.write(text + "\n"))
    parser = argparse.ArgumentParser(prog="legacy_import.py")
    for name in ("--root", "--team", "--reconcile"):
        parser.add_argument(name, required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--precheck", action="store_true")
    parser.add_argument("--rehold", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:                           # argparse 오류(2) = 64 · --help = 0
        return USAGE if exc.code else 0
    try:
        with open(args.reconcile, encoding="utf-8") as handle:
            data = json.load(handle)
        meta, rows = data["meta"], [row for row in data["rows"] if row.get("decision") == "옮김"]
    except (OSError, ValueError, KeyError, TypeError) as exc:
        say("판정 불가 · reconcile 판독 불가: %s" % exc)
        return 2
    team, root = _team_of(meta, rows), os.path.abspath(args.root)
    if team != args.team:
        say("접수 거부 · reconcile 팀 %r ≠ --team %r = 쓰기 0" % (team, args.team))
        return 1
    core = _core()
    imp = core.LegacyImport(root, args.team, on_step=step, caps=caps)
    try:
        if imp.lc is None and not args.precheck:
            raise core.record.CorruptStateError("runtime 없음: %s" % imp.runtime)
        before = imp.revision() if imp.lc else None
    except ValueError as exc:
        say("복구 필요 · %s = 쓰기 0" % exc)
        return 2
    cards, held_root = str(meta.get("cards_root") or root), os.path.join(
        root, ".fable-team", "state", "ft20-switch", args.team + ".held")
    plan, inv = [], _inventory(meta) if args.rehold else {}
    for row in rows:
        try:
            key, cat, stem = _key(row)
            name = _name(row, cat, stem)
            plan.append((row, key, cat, stem, name, _source(root, cards, args.team, row, cat, stem, meta), ""))
        except Skip as why:
            plan.append((row, row.get("target_id"), None, None, None, None, str(why)))
    args.dry_run, say = args.dry_run or args.precheck, (lambda text: None) if args.precheck else say  # r1831 쓰기 0 · 1줄
    limit = (imp.lc.rs.journal if imp.lc else core.journal.Journal(imp.runtime)).line_max
    n = a = b = e = broken = top = 0
    reasons, stop = collections.Counter(), None
    for row, key, cat, stem, name, data, why in plan:
        size = 0 if why else line_size(args.team, 9999999, "2026-01-01T00:00:00", row, len(data), core)  # 보수 seq
        top = max(top, size)
        if why or stop:
            reasons[why or stop + " 뒤"] += 1
            say("누락 %s: %s" % (key, why or stop + " 뒤"))
            continue
        if imp.lc is None:                              # precheck · runtime 없음 = 줄 크기만 잰다(쓰기 0)
            reasons.update(["줄 > %d" % limit] if size > limit else [])
            n += size <= limit
            continue
        if not _held(held := os.path.join(held_root, cat, name), data, args.dry_run):
            if args.rehold and key in (imp.lc._state_records()[0].get("imported") or {}):
                a += 1                                  # DA r1875 R1: held·import 둘 다 손 0
                say("이미 가져옴 %s: 원본 바뀜 = 보존" % key)
                continue
            if not args.rehold or inv.get(str(row.get("loc"))) != _sha(data):
                broken += 1
                say("판정 불가 %s: 원본 sha ≠ inventory 수집값 = 그 행 쓰기 0" % key if args.rehold
                    else "복구 필요 %s: held 사본 sha 다름 = 그 행 쓰기 0" % key)
                continue
            if not args.dry_run:
                say("held 다시 씀 %s: 옛 사본 = %s" % (key, os.path.basename(_prev(held))))
                _held(held, data, False)
        step("after_held")
        res = imp.put(dict(key=key, body=cat + "/" + name, src=_src(row, name), sha256=_sha(data),
                           bytes=len(data)), args.dry_run)
        status = res.status if res.result == core.OK else res.result
        if status in (core.IMPORTED, core.ALREADY, core.OVERLAP):
            n, a, b = n + (status == core.IMPORTED), a + (status == core.ALREADY), b + (status == core.OVERLAP)
            if status == core.OVERLAP:
                say("건너뜀 %s: %s" % (key, res.reason))
        elif status == "용량 부족":
            e, stop = 1, "용량 부족"
            say("용량 거절 %s: %s" % (key, res.reason))
        else:                                           # I2 줄 크기 거절 = 그 행만 누락 · 그 밖 = 멈춤
            size_refused = status == core.REFUSED and re.match(r"줄 \d+ 바이트 > \d+", res.reason or "")
            stop = None if size_refused else status
            broken += not size_refused
            reasons.update(["줄 > %d" % limit] if size_refused else [])
            say("누락 %s: %s" % (key, res.reason.split(" = ")[0]) if size_refused else "%s %s: %s" % (status, key, res.reason))
    c = len(plan) - n - a - b - e
    if args.precheck:
        detail = "(%s)" % " · ".join("%s %d" % item for item in sorted(reasons.items())) if reasons else ""
        out.write("가져올 수 %d · 누락 %d%s · 최대 줄 %d 바이트 / %d\n" % (n, c, detail, top, limit))
        return 2 if broken else 1 if c else 0
    changed = 0
    for row, key, cat, stem, name, data, why in plan:
        if data is not None:
            try:
                changed += _source(root, cards, args.team, row, cat, stem, meta) != data
            except Skip:
                changed += 1
    try:
        after = imp.revision()
    except ValueError:
        after, broken = "판정 불가", broken + 1
    if reasons:
        say("누락 사유: " + " · ".join("%s %d" % item for item in sorted(reasons.items())))
    say("가져온 수 %d · 건너뜀 %d(이미 가져옴 %d · 겹침 %d) · 용량 거절 %d · 누락 %d · 원본 sha 변화 %d · revision %s->%s%s"
        % (n, a + b, a, b, e, c, changed, before, after, " · dry-run" if args.dry_run else ""))
    return 2 if broken else 1 if (c or changed or e) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
