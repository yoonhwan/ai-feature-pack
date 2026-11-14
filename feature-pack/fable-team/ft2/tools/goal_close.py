#!/usr/bin/env python3
"""ft 2.0 goal-close 모듈 판 도구(r1940) — render · install · pin · promote · rollback. 인자 꼴 = `--이름 값`.

모듈 = 글·표뿐(팩 `feature-pack/fable-team/goal-close/`). 설치 루트 = `~/.claude/fable-team/goal-close/`(env FT2_GC_ROOT):
`versions/<판>/` · `CURRENT` 1줄 · `install-log.jsonl`. 팀이 쓰는 판 = 명부 `_goal_close` → 없으면 `CURRENT`(고른 판이 미설치면 판정 불가 · 다른 판으로 안 넘어감).
필수 기준은 이 도구 옆 `contracts/goal-close/INVARIANTS.tsv` 만 읽는다(후보 패키지 안 목록·env 덮어쓰기 0). 바깥 호출 0 · 파일 1개 64KB 상한.
종료 코드: 0 = 됨 · 1 = 판정 불가(쓰기 0) · 2 = 사용법.
"""
import glob, hashlib, json, os, re, shutil, sys, time  # noqa: E401

HERE = os.path.dirname(os.path.abspath(__file__))
INVARIANTS = os.path.join(os.path.dirname(HERE), "contracts", "goal-close", "INVARIANTS.tsv")
LIMIT, KEEP, CELL, NAME = 64 * 1024, 3, "_goal_close", re.compile(r"^gc-(\d+)\.(\d+)$")
FLAGS = ("root", "team", "role", "phrase", "version", "pkg")


class Unknown(Exception):
    """판정 불가 = rc 1 · 쓰기 0."""


def gc_root():
    return os.environ.get("FT2_GC_ROOT") or os.path.expanduser("~/.claude/fable-team/goal-close")


def _bytes(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read(LIMIT + 1)
    except OSError as exc:
        raise Unknown("못 읽음 %s (%s)" % (path, exc.__class__.__name__))
    if len(data) > LIMIT:
        raise Unknown("64KB 초과 %s" % path)
    return data


def _read(path):
    try:
        return _bytes(path).decode("utf-8")
    except UnicodeError:
        raise Unknown("UTF-8 아님 %s" % path)


def _roster(root, team):
    return os.path.join(root, ".fable-team", "seats-%s.json" % team)


def _pin(root, team):
    """명부의 팀 고정값 — 칸 없음 = None · 명부 없음·깨짐 = 판정 불가."""
    try:
        doc = json.loads(_read(_roster(root, team)))
    except ValueError:
        doc = None
    if not isinstance(doc, dict):
        raise Unknown("명부 깨짐 %s" % _roster(root, team))
    return doc.get(CELL)


def _current(gc):
    return (_read(os.path.join(gc, "CURRENT")).strip() or None) if os.path.exists(os.path.join(gc, "CURRENT")) else None


def _log(gc, op, version, prev, team):
    line = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "op": op, "version": version, "prev": prev, "team": team, "rc": 0}
    with open(os.path.join(gc, "install-log.jsonl"), "a", encoding="utf-8") as handle:
        handle.write(json.dumps(line, ensure_ascii=False) + "\n")


def _before(gc, team, ops):
    """기록의 앞 값 — 그 선택자(team 또는 None=CURRENT)를 마지막으로 바꾼 줄의 prev."""
    rows = [json.loads(x) for x in (_read(os.path.join(gc, "install-log.jsonl")) if os.path.exists(os.path.join(gc, "install-log.jsonl")) else "").splitlines() if x.strip()]
    last = [row for row in rows if row.get("op") in ops and row.get("team") == team]
    if not last:
        raise Unknown("되돌릴 기록 없음(%s)" % (team or "CURRENT"))
    return last[-1].get("prev")


def _pick(gc, root, team, version=None):
    want = version or _pin(root, team) or _current(gc)
    if not (isinstance(want, str) and NAME.match(want) and os.path.isdir(os.path.join(gc, "versions", want))):
        raise Unknown("판 없음 %r(team %s)" % (want, team))
    return want


def selected(gc, root, team, version=None):
    """그 팀이 쓰는 판 이름 — 판정 불가 = None."""
    try:
        return _pick(gc, root, team, version)
    except Unknown:
        return None


def _phrase(root, team, key, slots, version=None):
    ver = _pick(gc_root(), root, team, version)
    for cells in (line.split("\t") for line in _read(os.path.join(gc_root(), "versions", ver, "phrases.tsv")).splitlines()):
        if len(cells) == 2 and cells[0] == key:
            text = cells[1]
            for name, value in (slots or {}).items():
                text = text.replace("{%s}" % name, value) if isinstance(value, str) and value.strip() else text
            if "{" in text or "}" in text:
                raise Unknown("빈칸 못 채움 %s" % key)
            return ver, text
    raise Unknown("키 없음 %s(%s)" % (key, ver))


def phrase(root, team, role, key, slots):
    """빈칸을 채운 문장 + ` gc=<판> · ` — 못 읽으면 None(부르는 쪽이 내장 문구로 간다 · launch 와 같은 프로세스 · 파일 읽기뿐)."""
    try:
        return "%s gc=%s · " % tuple(reversed(_phrase(root, team, key, slots)))
    except (Unknown, OSError, ValueError):
        return None


def _core(folder, role):
    """역할 파일의 «핵심» 구역만 — render 가 내는 글과 필수 기준(`core:<역할>`)이 보는 글이 같다(DA R1)."""
    text = _read(os.path.join(folder, "roles", "%s.md" % os.path.basename(role)))
    if "## 핵심" not in text:
        raise Unknown("«핵심» 없음 roles/%s.md" % role)
    return text.split("## 핵심", 1)[1].split("\n## ", 1)[0].strip()


def check(pkg):
    """후보 폴더 검사 → 판 이름. MODULE.json sha256 + 도구 옆 필수 기준 · 후보 안에 같은 이름 목록이 있으면 그 자체로 거부."""
    try:
        meta = json.loads(_read(os.path.join(pkg, "MODULE.json")))
        ver, files = meta["version"], dict(meta["files"])
    except (ValueError, KeyError, TypeError):
        raise Unknown("MODULE.json 깨짐")
    found = sorted(os.path.relpath(os.path.join(d, n), pkg).replace(os.sep, "/") for d, _, names in os.walk(pkg) for n in names if (d, n) != (pkg, "MODULE.json"))
    if not (isinstance(ver, str) and NAME.match(ver)) or found != sorted(files) or any(os.path.basename(rel) == os.path.basename(INVARIANTS) for rel in found):
        raise Unknown("판 이름·파일 목록 다름 또는 패키지 안 필수 기준 파일(%s)" % ver)
    for rel, sha in files.items():
        if hashlib.sha256(_bytes(os.path.join(pkg, rel))).hexdigest() != sha:
            raise Unknown("sha256 다름 %s" % rel)
    rows = [line.split("\t") for line in _read(os.path.join(pkg, "phrases.tsv")).splitlines()]
    for line in (x for x in _read(INVARIANTS).splitlines() if x.strip() and not x.startswith("#")):
        (kind, _, name), need = line.split("\t")[0].partition(":"), line.split("\t")[-1]
        have = {"exists": lambda: name in files, "file": lambda: name in files and need in _read(os.path.join(pkg, name)), "core": lambda: need in _core(pkg, name),
                "phrase": lambda: any(len(row) == 2 and row[0] == name and need in row[1] for row in rows)}
        if kind not in have or not have[kind]():
            raise Unknown("필수 구 없음 %s:%s «%s»" % (kind, name, need))
    return ver


def install(args):
    """판 폴더만 놓는다(선택자 불변) · 옛 판은 3개까지 — 넘는 가장 옛 판은 이름만 바꾼다(삭제 0)."""
    gc, pkg = gc_root(), os.path.abspath(args["pkg"])
    ver = check(pkg)
    dest = os.path.join(gc, "versions", ver)
    if os.path.exists(dest):
        raise Unknown("이미 있음 %s" % ver)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copytree(pkg, dest + ".tmp-%d" % os.getpid())
    os.replace(dest + ".tmp-%d" % os.getpid(), dest)
    olds = sorted((n for n in os.listdir(os.path.dirname(dest)) if NAME.match(n) and n not in (ver, _current(gc))), key=lambda n: tuple(map(int, NAME.match(n).groups())))
    for name in olds[:max(0, len(olds) - KEEP)]:
        os.replace(os.path.join(gc, "versions", name), os.path.join(gc, "versions", "%s.old-%d" % (name, int(time.time()))))
    _log(gc, "install", ver, None, None)
    return "gc=%s sha=%s 설치 · 선택자 불변" % (ver, hashlib.sha256(_bytes(os.path.join(dest, "MODULE.json"))).hexdigest()[:8])


def _set_cell(root, team, value):
    """명부 그 1칸만 줄 단위로 바꾼다(다른 칸 값 그대로 · JSON 다시 직렬화 0) → 앞 값. value None = 칸 지움. 줄 꼴이 아니면 판정 불가(쓰기 0).
    기존 칸은 그 줄의 들여쓰기·쉼표·줄 끝을 그대로 잇는다 — 마지막 칸이어도 된다(DA R2). 마지막 칸을 지울 때만 앞 줄 쉼표 1개를 떼다."""
    path, prev = _roster(root, team), _pin(root, team)
    lines, before = _read(path).splitlines(True), json.loads(_read(path))
    at = next((i for i, line in enumerate(lines) if line.lstrip().startswith('"%s"' % CELL)), None)
    if at is None:
        at = next((i + 1 for i, line in enumerate(lines) if line.strip() == "{"), 0)
        lines[at:at] = [] if value is None else ['  "%s": %s%s\n' % (CELL, json.dumps(value), "" if "".join(lines[at:]).strip() == "}" else ",")]
    else:
        old, comma = lines[at], lines[at].rstrip().endswith(",")
        lines[at:at + 1] = [] if value is None else [old[:len(old) - len(old.lstrip())] + '"%s": %s%s' % (CELL, json.dumps(value), "," if comma else "") + old[len(old.rstrip("\r\n")):]]
        if value is None and not comma and at and lines[at - 1].rstrip().endswith(","):
            lines[at - 1] = lines[at - 1].rstrip()[:-1] + lines[at - 1][len(lines[at - 1].rstrip("\r\n")):]
    try:
        after = json.loads("".join(lines))
        same = after.get(CELL) == value and {k: v for k, v in after.items() if k != CELL} == {k: v for k, v in before.items() if k != CELL}
    except (ValueError, AttributeError):
        same = False
    if not same:
        raise Unknown("명부 1칸 쓰기 불가(줄 꼴 아님) %s" % path)
    with open(path + ".tmp", "wb") as handle:
        handle.write("".join(lines).encode("utf-8"))
    os.replace(path + ".tmp", path)
    return prev


def _pins(root):
    """«고정값 남은 팀» 1줄 — 명부들을 훑는다(못 읽는 명부는 건너뜀)."""
    found = []
    for path in sorted(glob.glob(os.path.join(root, ".fable-team", "seats-*.json"))):
        team = os.path.basename(path)[len("seats-"):-len(".json")]
        try:
            found += ["%s=%s" % (team, _pin(root, team))] if _pin(root, team) else []
        except Unknown:
            continue
    return "고정값 남은 팀: " + (" ".join(found) or "없음")


def pin(args):
    gc, root, team = gc_root(), os.path.abspath(args["root"]), args["team"]
    ver = _pick(gc, root, team, args["version"])
    _log(gc, "pin", ver, _set_cell(root, team, ver), team)
    return "gc=%s team=%s" % (_pick(gc, root, team), team)


def promote(args, version=None):
    gc, root = gc_root(), os.path.abspath(args["root"])
    ver, prev = _pick(gc, root, "", version or args["version"]), _current(gc)
    with open(os.path.join(gc, "CURRENT.tmp"), "w", encoding="utf-8") as handle:
        handle.write(ver + "\n")
    os.replace(os.path.join(gc, "CURRENT.tmp"), os.path.join(gc, "CURRENT"))
    _log(gc, "rollback" if version else "promote", ver, prev, None)
    return "gc=%s CURRENT\n%s" % (ver, _pins(root))


def rollback(args):
    gc, root, team = gc_root(), os.path.abspath(args["root"]), args.get("team")
    back = _before(gc, team, ("pin", "promote", "rollback"))
    if not team:
        return promote(args, back or "없음")
    if back is not None:
        _pick(gc, root, team, back)
    _log(gc, "rollback", back, _set_cell(root, team, back), team)
    return "gc=%s team=%s" % (_pick(gc, root, team), team)


def render(args):
    gc, root, team = gc_root(), os.path.abspath(args["root"]), args["team"]
    ver = _pick(gc, root, team, args.get("version"))
    text = _phrase(root, team, args["phrase"], args, ver)[1] if args.get("phrase") else _core(os.path.join(gc, "versions", ver), args["role"])
    return "gc=%s sha=%s\n%s" % (ver, hashlib.sha256(_bytes(os.path.join(gc, "versions", ver, "MODULE.json"))).hexdigest()[:8], text)


VERBS = {"render": render, "install": install, "pin": pin, "promote": promote, "rollback": rollback}


def main(argv):
    names, values = argv[1::2], argv[2::2]
    if not argv or argv[0] not in VERBS or len(names) != len(values) or any(n[:2] != "--" or n[2:] not in FLAGS for n in names):
        print("사용법: goal_close.py render|install|pin|promote|rollback --이름 값 … (이름 = %s)" % " ".join(FLAGS))
        return 2
    try:
        print(VERBS[argv[0]](dict(zip((n[2:] for n in names), values))))
    except KeyError as exc:
        print("사용법: 값 빠짐 --%s" % exc.args[0])
        return 2
    except (Unknown, OSError, ValueError) as exc:
        print("판정 불가 · %s" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
