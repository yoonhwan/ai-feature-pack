#!/usr/bin/env python3
"""Remove the top-level ``ProcessType`` entry from the operating consumer plist (design arch-20261016-opa-popup-design-r15
§2.4 S0/S2 + errata §2 acceptance conditions 1-12).

What it does, in this order, and nothing else:
  1. read the plist (a regular XML file) and classify it: ``ProcessType`` = ``Background`` (edit), no such top-level
     key (nothing to do, exit 0), anything else (refused, exit 3);
  2. confirm that ``com.airag.consumer`` is NOT loaded and IS disabled in launchd, by reading only (``list`` and
     ``print-disabled``; each call at most 7.0 s, no retry) - otherwise no edit at all (exit 4);
  3. copy the plist to the backup directory and compare sha256 of original and copy (exit 5);
  4. build a candidate beside the plist (a name that does not end in ``.plist``), then check it: ``plutil -lint``,
     the top-level key names are exactly the original ones minus ``ProcessType``, every remaining value hash is
     unchanged, permissions and owner equal the original (exit 6);
  5. publish the candidate with one atomic rename (exit 7 if that fails; the operating file is then untouched);
  6. re-read the operating file and repeat the checks; on any failure (or a signal) restore the backup atomically
     and compare hashes (exit 8; a failed restore is exit 9 with the backup location printed).
The edit removes the key element and its value element from the original bytes; every other byte (comments,
order, spacing) stays as it was.

Never done here: any launchd change, loading or unloading of the job, ``op``, the token file, the template, the
runtime, reading any value out. Output is key names, fixed sentences and PASS/FAIL only. No interactive input.

Exit codes: 0 done / already without the key, 2 usage or test-mode violation, 3 input refused, 4 launchd state not
as required (nothing edited), 5 backup failed (nothing edited), 6 candidate check failed (operating file untouched),
7 publish failed or the plist changed meanwhile (untouched), 8 post-check failed and the backup was restored,
9 restore failed (state uncertain - human decision), 130/143 interrupted by INT/TERM (cleaned up; if the edit was
already published it was restored first, otherwise the operating file never changed).

Test mode: ``--selftest --plist F --backup-dir D --launchctl CMD [--plutil CMD]`` (all three of the first are
required, none is accepted without ``--selftest``). A path that is the operating plist / backup directory is refused.
"""

from __future__ import annotations

import contextlib
import hashlib
import os
from pathlib import Path
from typing import Any
import plistlib
import pwd
import signal
import stat
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from xml.parsers import expat

LABEL = "com.airag.consumer"
KEY = "ProcessType"
EXPECTED = "Background"
CALL_S = 7.0       # one external read call (launchctl / plutil): 7.0 s, no retry
TOTAL_S = 60.0     # whole run, all external calls included
LAUNCHCTL = "/bin/launchctl"
PLUTIL = "/usr/bin/plutil"
READ_VERBS = ("list", "print-disabled")
OK, USAGE, REFUSED, STATE, BACKUP, CANDIDATE, PUBLISH, RESTORED, RESTORE_FAILED = 0, 2, 3, 4, 5, 6, 7, 8, 9
USAGE_TEXT = ("usage: plist_edit.py   (test mode only: --selftest --plist FILE --backup-dir DIR --launchctl CMD "
              "[--plutil CMD])\n")


class Refuse(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code, self.message = code, message


class Interrupted(Exception):
    def __init__(self, signum: int):
        super().__init__(signum)
        self.signum = signum


def say(text: str) -> None:
    print(text, flush=True)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ------------------------------------------------------------------------------------------------ context
class Context:
    def __init__(self, plist: Path, backup_dir: Path, launchctl: str, plutil: str, selftest: bool):
        self.plist, self.backup_dir, self.launchctl, self.plutil, self.selftest = plist, backup_dir, launchctl, plutil, selftest
        self.call_s = self.seconds("PLIST_EDIT_CALL_S", CALL_S)
        self.deadline = time.monotonic() + TOTAL_S
        self.temps: list[Path] = []
        self.published = False
        self.defer = False
        self.pending: int | None = None

    def seconds(self, name: str, default: float) -> float:
        if self.selftest and os.environ.get(name):
            return float(os.environ[name])
        return default

    def hook(self, name: str) -> bool:
        """Test-mode switches only (PLIST_EDIT_INJECT=a,b); never honoured in production."""
        return self.selftest and name in os.environ.get("PLIST_EDIT_INJECT", "").split(",")

    def pause(self, name: str) -> None:
        if self.hook(name):
            Path(os.environ["PLIST_EDIT_PAUSE_FILE"]).write_text(f"{os.getpid()} {name}\n", encoding="utf-8")
            time.sleep(30)

    @contextlib.contextmanager
    def deferred(self):
        """Signals that arrive inside are held until the block ends (rename + state flag are one step)."""
        self.defer = True
        try:
            yield
        finally:
            self.defer = False
        if self.pending is not None:
            raise Interrupted(self.pending)


def home_directories() -> list[Path]:
    homes = [Path(pwd.getpwuid(os.getuid()).pw_dir)]
    if os.environ.get("HOME"):
        homes.append(Path(os.environ["HOME"]))
    return homes


def operating_plist() -> Path:
    return home_directories()[0] / "Library" / "LaunchAgents" / f"{LABEL}.plist"


def operating_backup_dir() -> Path:
    return home_directories()[0] / ".local" / "share" / "airag-plist-backup"


def _inside(path: Path, base: Path) -> bool:
    path, base = path.resolve(), base.resolve()
    return path == base or base in path.parents


def build_context(argv: list[str]) -> Context:
    given: dict[str, str] = {}
    selftest = False
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--selftest" and not selftest:
            selftest = True
            index += 1
        elif arg in ("--plist", "--backup-dir", "--launchctl", "--plutil") and arg not in given and index + 1 < len(argv):
            given[arg] = argv[index + 1]
            index += 2
        else:
            raise Refuse(USAGE, "알 수 없거나 겹치는 인자입니다.")
    if not selftest:
        if given:
            raise Refuse(USAGE, "경로 인자는 시험 모드(--selftest)에서만 쓸 수 있습니다.")
        return Context(operating_plist(), operating_backup_dir(), LAUNCHCTL, PLUTIL, False)
    if not {"--plist", "--backup-dir", "--launchctl"} <= set(given):
        raise Refuse(USAGE, "시험 모드는 --plist --backup-dir --launchctl 을 모두 지정해야 합니다.")
    plist, backup_dir = Path(given["--plist"]), Path(given["--backup-dir"])
    for home in home_directories():
        agents = home / "Library" / "LaunchAgents"
        if _inside(plist, agents) or plist.resolve() == (agents / f"{LABEL}.plist").resolve():
            raise Refuse(USAGE, "시험 모드에 운영 plist 경로가 지정되어 거부합니다.")
        if _inside(backup_dir, home / ".local" / "share" / "airag-plist-backup"):
            raise Refuse(USAGE, "시험 모드에 운영 백업 경로가 지정되어 거부합니다.")
    launchctl = given["--launchctl"]
    if not os.path.isabs(launchctl) or Path(launchctl).resolve() == Path(LAUNCHCTL).resolve():
        raise Refuse(USAGE, "시험 모드의 launchctl 은 가짜 도구의 절대 경로여야 합니다.")
    return Context(plist, backup_dir, launchctl, given.get("--plutil", PLUTIL), True)


# ------------------------------------------------------------------------------------------------ reading
def scan_top_level(data: bytes) -> tuple[str | None, list[dict[str, Any]]]:
    """Root element name under ``plist`` and, for every child of the root dict, its tag, text and byte span."""
    depth = 0
    root: str | None = None
    child: dict[str, Any] | None = None
    children: list[dict[str, Any]] = []
    parser = expat.ParserCreate()

    def start(name, attrs):
        nonlocal depth, root, child
        depth += 1
        if depth == 2:
            root = name
        elif depth == 3:
            child = {"tag": name, "text": "", "start": parser.CurrentByteIndex}

    def end(name):
        nonlocal depth, child
        if depth == 3 and child is not None:
            child["end"] = data.index(b">", parser.CurrentByteIndex) + 1
            children.append(child)
            child = None
        depth -= 1

    def text(chunk):
        if depth == 3 and child is not None and child["tag"] == "key":
            child["text"] += chunk

    parser.StartElementHandler, parser.EndElementHandler, parser.CharacterDataHandler = start, end, text
    parser.Parse(data, True)
    pairs = []
    if root == "dict":
        if len(children) % 2 or any(c["tag"] != "key" for c in children[0::2]) or any(c["tag"] == "key" for c in children[1::2]):
            raise ValueError("malformed dict")
        pairs = [{"key": k["text"], "key_span": (k["start"], k["end"]), "tag": v["tag"], "value_span": (v["start"], v["end"])}
                 for k, v in zip(children[0::2], children[1::2])]
    return root, pairs


def digests(document: dict[str, Any]) -> dict[str, str]:
    return {name: sha(plistlib.dumps(value, fmt=plistlib.FMT_XML, sort_keys=True)) for name, value in document.items()}


def classify(data: bytes) -> tuple[str, tuple[int, int] | None, list[str], dict[str, str]]:
    """('edit', span, key names, remaining value hashes) or ('absent', None, ...); Refuse(REFUSED) for the rest."""
    try:
        root, pairs = scan_top_level(data)
        document = plistlib.loads(data)
    except Exception:
        raise Refuse(REFUSED, "plist 를 읽을 수 없습니다(XML 형식이 아니거나 깨짐).") from None
    if root != "dict" or not isinstance(document, dict):
        raise Refuse(REFUSED, "plist 의 루트가 딕셔너리가 아닙니다.")
    names = [pair["key"] for pair in pairs]
    if sorted(set(names)) != sorted(document):
        raise Refuse(REFUSED, "plist 의 최상위 키를 일관되게 읽지 못했습니다.")
    hits = [pair for pair in pairs if pair["key"] == KEY]
    if len(hits) > 1:
        raise Refuse(REFUSED, f"최상위 {KEY} 키가 중복되어 있습니다.")
    remaining = digests({k: v for k, v in document.items() if k != KEY})
    if not hits:
        return "absent", None, names, remaining
    hit = hits[0]
    if hit["tag"] != "string" or type(document[KEY]) is not str:
        raise Refuse(REFUSED, f"{KEY} 값의 형이 문자열이 아닙니다.")
    if document[KEY] != EXPECTED:
        raise Refuse(REFUSED, f"{KEY} 값이 예상({EXPECTED})이 아닙니다.")
    return "edit", (hit["key_span"][0], hit["value_span"][1]), [n for n in names if n != KEY], remaining


def cut(data: bytes, span: tuple[int, int]) -> bytes:
    """Remove the key + value elements and, when they sit on their own lines, their indentation and line break."""
    start, end = span
    lead = start
    while lead > 0 and data[lead - 1:lead] in (b" ", b"\t"):
        lead -= 1
    tail = end
    while data[tail:tail + 1] in (b" ", b"\t"):
        tail += 1
    own_line = (lead == 0 or data[lead - 1:lead] == b"\n") and data[tail:tail + 1] in (b"\n", b"\r")
    if own_line:
        tail += 2 if data[tail:tail + 2] == b"\r\n" else 1
        return data[:lead] + data[tail:]
    return data[:start] + data[end:]


def shape_ok(data: bytes, names: list[str], hashes: dict[str, str]) -> bool:
    try:
        root, pairs = scan_top_level(data)
        document = plistlib.loads(data)
    except Exception:
        return False
    return (root == "dict" and isinstance(document, dict) and [p["key"] for p in pairs] == names
            and KEY not in document and digests(document) == hashes)


def meta(info: os.stat_result) -> tuple[int, int, int]:
    return stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid


# ------------------------------------------------------------------------------------------------ external reads
def run_tool(ctx: Context, argv: list[str]):
    cap = min(ctx.call_s, ctx.deadline - time.monotonic())
    if cap <= 0:
        return None
    try:
        return subprocess.run(argv, capture_output=True, timeout=cap, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None


def launchctl_read(ctx: Context, verb: str):
    if verb not in READ_VERBS:
        raise AssertionError("launchd is read-only here")
    argv = [ctx.launchctl, verb] + ([f"gui/{os.getuid()}"] if verb == "print-disabled" else [])
    return run_tool(ctx, argv)


def require_stopped(ctx: Context) -> None:
    done = launchctl_read(ctx, "list")
    lines = done.stdout.decode("utf-8", "replace").splitlines() if done is not None and done.returncode == 0 else []
    if not lines or lines[0].split()[:1] != ["PID"]:
        raise Refuse(STATE, "launchd 에 적재되어 있는지 확인하지 못했습니다(편집 0).")
    if any(line.split()[-1:] == [LABEL] for line in lines[1:]):
        raise Refuse(STATE, "consumer 가 이미 적재되어 있습니다(편집 0) — 기존 HIL 경로로 넘깁니다.")
    done = launchctl_read(ctx, "print-disabled")
    value = None
    if done is not None and done.returncode == 0:
        for line in done.stdout.decode("utf-8", "replace").splitlines():
            if f'"{LABEL}"' in line and "=>" in line:
                value = line.split("=>", 1)[1].strip().lower()
    if value is None:
        raise Refuse(STATE, "consumer 의 정지(disabled) 상태를 확인하지 못했습니다(편집 0).")
    if value not in ("disabled", "true"):
        raise Refuse(STATE, "consumer 가 정지 상태가 아닙니다(편집 0).")


# ------------------------------------------------------------------------------------------------ writing
def make_backup(ctx: Context, original_sha: str) -> Path:
    path = None
    try:
        ctx.backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(ctx.backup_dir, 0o700)
        info = os.stat(ctx.backup_dir)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise OSError
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = ctx.backup_dir / f"{LABEL}.plist.{stamp}-{os.getpid()}.bak"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(ctx.plist.read_bytes())
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(path, 0o600)
        if ctx.hook("backup_corrupt"):
            with open(path, "ab") as handle:
                handle.write(b"x")
        if sha(path.read_bytes()) != original_sha or sha(ctx.plist.read_bytes()) != original_sha:
            raise OSError
        if stat.S_IMODE(os.stat(path).st_mode) != 0o600:
            raise OSError
    except OSError:
        if path is not None:
            with contextlib.suppress(OSError):
                path.unlink()
        raise Refuse(BACKUP, "백업을 만들지 못했거나 해시가 일치하지 않습니다(편집 0).") from None
    return path


def write_beside(ctx: Context, data: bytes, original_meta: tuple[int, int, int], marker: str | None = None) -> Path:
    """Write ``data`` to a new temporary file next to the plist (name ends in .tmp), with the original's permissions/owner."""
    fd, name = tempfile.mkstemp(prefix=f".{LABEL}.edit-", suffix=".tmp", dir=ctx.plist.parent)
    path = Path(name)
    ctx.temps.append(path)
    with os.fdopen(fd, "wb") as handle:
        if marker:
            ctx.pause(marker)
        mode, uid, gid = original_meta
        os.fchmod(handle.fileno(), mode)
        info = os.fstat(handle.fileno())
        if (info.st_uid, info.st_gid) != (uid, gid):
            os.fchown(handle.fileno(), uid, gid)
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def restore(ctx: Context, backup: Path, original_sha: str, original_meta: tuple[int, int, int]) -> bool:
    """Put the backup back atomically and compare hashes. True only if the operating file is the original again."""
    ctx.defer = True
    try:
        data = backup.read_bytes()
        if sha(data) != original_sha:
            return False
        path = write_beside(ctx, data, original_meta)
        if ctx.hook("restore_fail"):
            raise OSError
        os.replace(path, ctx.plist)
        fsync_directory(ctx.plist.parent)
        return sha(ctx.plist.read_bytes()) == original_sha and meta(os.stat(ctx.plist)) == original_meta
    except OSError:
        return False
    finally:
        ctx.defer = False


# ------------------------------------------------------------------------------------------------ the run
def execute(ctx: Context) -> int:
    try:
        info = os.lstat(ctx.plist)
        if not stat.S_ISREG(info.st_mode):
            raise OSError
        original = ctx.plist.read_bytes()
    except OSError:
        raise Refuse(REFUSED, "plist 를 읽을 수 없거나 일반 파일이 아닙니다.") from None
    original_sha, original_meta = sha(original), meta(info)
    kind, span, names, hashes = classify(original)
    if kind == "absent":
        say(f"입력: PASS — 최상위 {KEY} 항목이 이미 없습니다(변경 0·백업 0). 키 이름: {', '.join(names)}")
        return OK
    say(f"입력: PASS — 최상위 {KEY} 항목 하나({EXPECTED})를 지울 대상입니다. 남을 키 이름: {', '.join(names)}")
    require_stopped(ctx)
    say("전제: PASS — launchd 에 적재되어 있지 않고 정지(disabled) 상태입니다(읽기 조회만).")
    backup = make_backup(ctx, original_sha)
    say(f"백업: PASS — 복사본 sha256 일치(권한 600). 위치: {backup}")
    assert span is not None
    candidate_bytes = cut(original, span)
    if ctx.hook("candidate_other"):
        candidate_bytes = candidate_bytes.replace(b"<true/>", b"<false/>", 1)
    try:
        candidate = write_beside(ctx, candidate_bytes, original_meta, "pause_candidate")
        if ctx.hook("candidate_chmod"):
            os.chmod(candidate, 0o666)
    except OSError:
        raise Refuse(CANDIDATE, "후보 파일을 만들지 못했습니다(운영 파일 불변).") from None
    lint = run_tool(ctx, [ctx.plutil, "-lint", str(candidate)])
    if lint is None or lint.returncode != 0:
        raise Refuse(CANDIDATE, "후보 plutil -lint 실패(운영 파일 불변).")
    say("후보 lint: PASS")
    written = candidate.read_bytes()
    if not shape_ok(written, names, hashes):
        raise Refuse(CANDIDATE, "후보 검증 실패 — 키 이름 목록 또는 나머지 값 해시가 다릅니다(운영 파일 불변).")
    if meta(os.stat(candidate)) != original_meta:
        raise Refuse(CANDIDATE, "후보의 권한·소유자가 원본과 다릅니다(운영 파일 불변).")
    say(f"후보 검증: PASS — 키 이름이 {KEY} 하나만 줄었고 나머지 값 해시 불변, 권한·소유자 동일.")
    candidate_sha = sha(written)
    ctx.pause("pause_publish")
    if sha(ctx.plist.read_bytes()) != original_sha:
        raise Refuse(PUBLISH, "실행 중 plist 가 바뀌어 게시하지 않습니다(운영 파일 불변).")
    stopped: int | None = None
    failure = None
    try:
        with ctx.deferred():
            try:
                if ctx.hook("publish_fail"):
                    raise OSError
                os.replace(candidate, ctx.plist)
            except OSError:
                raise Refuse(PUBLISH, "게시(rename)에 실패했습니다(운영 파일 불변).") from None
            ctx.published = True
    except Interrupted as stop:
        stopped = stop.signum
    if stopped is None:
        try:
            ctx.pause("pause_after_publish")
            if ctx.hook("post_corrupt"):
                ctx.plist.write_bytes(ctx.plist.read_bytes().replace(b"<true/>", b"<false/>", 1))
            if ctx.hook("post_chmod"):
                os.chmod(ctx.plist, 0o666)
            fsync_directory(ctx.plist.parent)
            after = ctx.plist.read_bytes()
            if sha(after) != candidate_sha or not shape_ok(after, names, hashes) or meta(os.stat(ctx.plist)) != original_meta:
                failure = "사후 재검증 실패"
        except Interrupted as stop:
            stopped = stop.signum
        except Exception:
            failure = "사후 재검증 오류"
    if stopped is None and failure is None:
        say("사후 재검증: PASS — 게시된 파일이 후보와 같고 키·값 해시·권한·소유자가 맞습니다.")
        say(f"완료: 최상위 {KEY} 항목 하나를 지웠습니다. 키 이름: {', '.join(names)}")
        return OK
    if not ctx.published:
        raise Interrupted(stopped if stopped is not None else signal.SIGTERM)
    if restore(ctx, backup, original_sha, original_meta):
        say(f"복원: PASS — {failure or '신호 수신'}으로 백업을 되돌렸고 해시가 일치합니다.")
        return 128 + stopped if stopped is not None else RESTORED
    say(f"복원: FAIL — 운영 plist 가 원본인지 확인하지 못했습니다. 백업 위치: {backup}")
    return RESTORE_FAILED


def main(argv: list[str]) -> int:
    ctx = None

    def on_signal(signum, frame):
        if ctx is not None and ctx.defer:
            ctx.pending = signum
            return
        raise Interrupted(signum)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    try:
        ctx = build_context(argv)
        return execute(ctx)
    except Refuse as refusal:
        say(f"중단: {refusal.message}")
        if refusal.code == USAGE:
            sys.stderr.write(USAGE_TEXT)
        return refusal.code
    except Interrupted as stop:
        say("중단: 신호를 받아 정리하고 끝냅니다(운영 파일 불변).")
        return 128 + stop.signum
    except Exception:
        say("중단: 예기치 못한 오류(값은 출력하지 않습니다). 운영 파일은 게시 전이면 불변입니다.")
        return 1
    finally:
        for path in ctx.temps if ctx is not None else []:
            with contextlib.suppress(OSError):
                path.unlink()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
