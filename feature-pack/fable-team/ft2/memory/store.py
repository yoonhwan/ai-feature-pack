"""ft2 기억 저장 본체 — remember · forget · list · 1회 들여오기 (카드 r1798b · 기획 PLAN-dreaming-ft20-memory-r1797 ③-4 B).
자리 = `<root>/.fable-team/teams/<팀>/memory/`(MEMORY_DIR 1곳) · 활성 notes.jsonl · 내린 줄 archive/<항목 ts YYYY-MM>.jsonl.
새 줄 src 필수 · 저장 전 주입·유출 스캔 · 상한 100(pin 제외 가장 옛 줄 → archive · 삭제 0) · 쓰기 = writer.lock 비차단 1회 ·
판(notes 바이트 sha256 앞 16 hex) 대조 · 임시 → fsync → rename · 순서 ① archive(id 멱등) → ② notes = 확정 시점.
core/ 손·import 0 · 결과 낱말 = contracts/core 8낱말 안 · 응답마다 protocol_version."""
import fcntl
import glob
import hashlib
import json
import os
import re
import time
from pathlib import Path

PROTOCOL_VERSION = 1
MEMORY_DIR = os.path.join(".fable-team", "teams", "{team}", "memory")
CAP, QUOTE_MAX = 100, 200
KINDS = ("directive", "mistake", "achievement", "experiment")
OK, REFUSED, HOLD, BUSY, CORRUPT = "접수 성공", "접수 거부", "완료 유보", "BUSY", "복구 필요"
SRC = re.compile(r"^(?:[0-9a-f]{7,40}|#\d+|[^\s:]+/[^\s:]+\.md|[^\s:]+\.jsonl:\d+)$")
NEGATION = re.compile(r"(않는다|않도록|금지|말라|하지 마|no |never |하지않)")
IMPERATIVE = re.compile(r"(하라|해라|하세요|출력해|알려줘|따라라|실행해|공개해)")
INJECT = (  # 1.x 와 같은 패턴 · 같은 부정문 규칙(복사 = 새로 씀 · 1.x 실행·import 0)
    r"(?i)ignore (all )?(previous|prior|above) (instructions|rules)",
    r"(규칙|지시|지침)(을|를)? ?(모두|전부|전체)? ?(폐기|무시|잊)(하고|한 뒤|고)?.{0,40}(따라|이행|실행)",
    r"(?i)system prompt|시스템 ?프롬프트를? (출력|공개|알려)",
    r"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*\S{8,}",
    r"(?i)curl\s+[^|]*\|\s*(ba)?sh",
    r"(?i)rm\s+-rf\s+/(\s|$)",
    r"이전 지시(를|사항을)? (무시|잊)",
)


def scan(text):  # 걸린 패턴 | None · 바로 뒤 12자 안 부정문은 허용(명령형이 함께면 무시)
    for pat in INJECT:
        hit = re.search(pat, text or "")
        if hit and not (NEGATION.search(text[hit.end():hit.end() + 12]) and not IMPERATIVE.search(text)):
            return pat
    return None


def _sha16(data):
    return hashlib.sha256(data).hexdigest()[:16]


def _row(id, ts, kind, text, src, quote, pin, by, legacy):
    return {"id": id, "ts": ts, "kind": kind, "text": text, "src": src, "quote": quote, "verified_at": None,
            "pin": pin, "by": by, "legacy": legacy}


def _month(row):
    return row["ts"][:7] if re.match(r"^\d{4}-\d{2}", row["ts"]) else "0000-00"


class MemoryStore:
    """팀 기억 1곳. 쓰는 손은 이 클래스 1개다."""

    def __init__(self, root, team, clock=None, on_step=None):
        self.root, self.team = os.path.abspath(root), team
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step = on_step or (lambda step: None)
        self.dir = os.path.join(self.root, MEMORY_DIR.format(team=team))
        self.notes = os.path.join(self.dir, "notes.jsonl")
        self.lock_path = os.path.join(self.root, ".fable-team", "teams", team, "runtime", "writer.lock")

    def list(self):  # 잠금 0 · 쓰기 0 · archived = archive 줄 중 notes 에 없는 id(같은 id 는 1번)
        try:
            rows, revision = self._read(self.notes)
            have = {r["id"] for r in rows}
            archived = [r for r in self._archive_rows() if r["id"] not in have and not have.add(r["id"])]
        except ValueError as exc:
            return self._out(CORRUPT, reason=str(exc))
        return self._out(OK, revision, active=rows, archived=archived)

    def remember(self, seat, kind, text, src, quote=None, expect=None):
        problem = self._problem(seat, kind, text, quote) or ("" if self._src_ok(src) else
                                                             "src 꼴 밖 %r — 커밋 sha · #seq · .md 경로 · .jsonl:<줄>" % (src,))
        if problem:
            return self._out(REFUSED, reason=problem)
        ts = self.clock()
        key = json.dumps([ts, seat, kind, text, src], ensure_ascii=False).encode()
        row = _row(_sha16(key), ts, kind, text, src, quote, False, seat, False)
        return self._apply(expect, lambda rows: (rows + [row], [], ""), id=row["id"])

    def forget(self, seat, note_id, expect=None):  # archive 로 내린다(삭제 아님) · pin 은 거부
        def mutate(rows):
            hit = [r for r in rows if r["id"] == note_id]
            if not hit or hit[0]["pin"]:
                return rows, [], "pin 줄은 내리지 않는다" if hit else "활성 줄에 없는 id %r" % (note_id,)
            return [r for r in rows if r["id"] != note_id], hit, ""
        return self._apply(expect, mutate, id=note_id)

    def import_legacy(self, seat, path, expect=None):  # 1.x 노트 → legacy:true(src null) · id = 줄 번호·바이트 · 2회째 0줄
        try:
            raw = Path(path).read_bytes().split(b"\n")
            items = [(n, line, json.loads(line)) for n, line in enumerate(raw, 1) if line.strip()]
        except (OSError, ValueError) as exc:
            return self._out(REFUSED, reason="1.x 노트 판독 불가: %s" % exc)
        for n, _, old in items:
            problem = self._problem(seat, old.get("kind"), old.get("text"), None)
            if problem:
                return self._out(REFUSED, reason="1.x 노트 %s:%d — %s = 들여오기 0" % (path, n, problem))
        news = [_row(_sha16(b"%d\0" % n + line), str(old.get("ts") or ""), old["kind"], old["text"], None, None,
                     bool(old.get("pin")), seat, True) for n, line, old in items]

        def mutate(rows):
            have = {r["id"] for r in rows} | {r["id"] for r in self._archive_rows()}
            return rows + [r for r in news if r["id"] not in have], [], ""
        return self._apply(expect, mutate)

    def _problem(self, seat, kind, text, quote):
        if not isinstance(seat, str) or not seat.strip() or kind not in KINDS:
            return "seat 없음 또는 kind 밖 %r — %s" % (kind, "|".join(KINDS))
        if not isinstance(text, str) or not text.strip() or "\n" in text:
            return "text 는 빈 칸 없는 한 줄"
        if quote is not None and (not isinstance(quote, str) or len(quote) > QUOTE_MAX or "\n" in quote):
            return "quote 는 %d자 안 한 줄" % QUOTE_MAX
        hit = scan(text) or scan(quote or "")
        return "주입·유출 유도 문장 = 저장 0 (%s)" % hit if hit else ""

    def _src_ok(self, src):  # 변이 M1 자리
        return isinstance(src, str) and bool(SRC.search(src))

    def _stale(self, expect, revision):  # 변이 M3 자리
        return expect != revision

    def _apply(self, expect, mutate, id=None):  # 잠금 → 판 대조 → 변경 → 상한 밀어내기 → 두 파일 확정
        lock = self._try_lock()
        if lock is None:
            return self._out(BUSY, reason="writer.lock 점유 = 기다리지 않는다")
        try:
            rows, revision = self._read(self.notes)
            if self._stale(expect, revision):
                return self._out(HOLD, revision, reason="판 불일치 %r != %r = 다시 읽어라(쓰기 0)" % (expect, revision))
            new, moved, problem = mutate(rows)
            if problem or new == rows:
                return self._out(REFUSED if problem else OK, revision, reason=problem, id=id)
            spill = [r for r in new if not r["pin"]][:max(0, len(new) - CAP)]
            new = [r for r in new if r not in spill]
            self._commit(new, moved + spill)
            return self._out(OK, self._read(self.notes)[1], written=True, id=id)
        except ValueError as exc:
            return self._out(CORRUPT, reason=str(exc))
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()

    def _commit(self, rows, moved):  # 변이 M4 자리 — ① archive → ② notes(확정 시점) · 순서 바꿈 = 유실 길
        self._archive_all(moved)
        self.on_step("between_files")
        self._replace(self.notes, rows)

    def _archive_all(self, moved):  # 변이 M2 자리 — 항목 ts 의 달 파일로 옮긴다(삭제 0)
        for month in sorted({_month(r) for r in moved}):
            path = os.path.join(self.dir, "archive", month + ".jsonl")
            have = self._read(path)[0]
            fresh = self._fresh({r["id"] for r in have}, [r for r in moved if _month(r) == month])
            if fresh:
                self._replace(path, have + fresh)

    def _fresh(self, have, items):  # 변이 M5 자리 — 이미 있는 id 는 덧붙이지 않는다(재시도 멱등)
        return [r for r in items if r["id"] not in have]

    def _archive_rows(self):
        return [r for path in sorted(glob.glob(os.path.join(self.dir, "archive", "*.jsonl")))
                for r in self._read(path)[0]]

    def _read(self, path):
        data = Path(path).read_bytes() if os.path.exists(path) else b""
        try:
            return [json.loads(line) for line in data.splitlines() if line.strip()], _sha16(data)
        except ValueError as exc:
            raise ValueError("기억 파일 꼴 깨짐 %s: %s" % (path, exc))

    def _replace(self, path, rows):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = "%s.tmp.%d" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
            handle.flush()
            os.fsync(handle.fileno())
        self.on_step("before_rename")
        os.replace(tmp, path)
        fd = os.open(os.path.dirname(path), os.O_RDONLY)  # 폴더 fsync = rename 내구화
        os.fsync(fd)
        os.close(fd)

    def _try_lock(self):
        os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)
        handle = open(self.lock_path, "a+", encoding="utf-8")
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except OSError:
            handle.close()
            return None

    def _out(self, result, revision=None, written=False, reason="", **extra):
        return dict({"protocol_version": PROTOCOL_VERSION, "result": result, "team": self.team,
                     "revision": revision, "written": written, "reason": reason}, **extra)
