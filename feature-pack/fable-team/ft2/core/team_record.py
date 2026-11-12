"""ft2 팀 기록 1파일 — 쓰기·읽기 (카드 r1723-ft20-team-record-file · 계획 PLAN-ft20-team-record-file-20261112).

팀이 닫혀도 다른 팀이 그 팀 세션·우편함을 열지 않고 상태를 아는 1곳이다(PROPOSAL-reclaim-cycle §3 ③).
자리 = `<root>/.fable-team/teams/<팀>/TEAM-RECORD.md` — runtime/ 옆(안이 아님 · journal 총량·회수 대상 밖).
꼴 = 머리 `# 팀 기록 — <팀>` + `- <칸>: <값>` 줄을 FIELDS 순서로 고정 + 끝 줄 `- 기록 판: <정수>`.
기계 판독은 이 줄 꼴만 본다(표·자유 문단 0 · 꼴 깨짐 = 복구 필요 · 덮어쓰기 0).
ASSIGN·STATE·HANDOFF·LESSONS 는 경로 또는 «없음» 만 둔다(본문 복사 0 = 두 벌 0).
쓰기 = 같은 팀 좌석만(`byz-<팀>-` 접두) · expect = 지금 기록 판(아니면 완료 유보 RETRY) · 팀 runtime
writer.lock 비차단 1회(점유 = BUSY) · 임시 파일 → fsync → rename → 폴더 fsync(반쯤 쓴 기록 0).
읽기 = 잠금·쓰기 0 · 파일 없음 = 접수 거부 «판정 불가 기록 없음».
결과 낱말 = contracts/core 8낱말 안만(새 낱말 0).
"""
import collections
import fcntl
import os
import time

OK, REFUSED, HOLD, BUSY, CORRUPT = "접수 성공", "접수 거부", "완료 유보", "BUSY", "복구 필요"
POINTERS = ("ASSIGN", "STATE", "HANDOFF", "LESSONS")
FIELDS = (
    # PROPOSAL §3 ③ 7칸
    "골좌표", "휴면 시각", "마지막 결정", "열린 일", "받을 쪽지 처리 규칙", "재개설 순서", "인계서 경로",
    # 대조표 A1 몫 3칸
    "진행 카드", "열린 h", "미커밋",
    # §3 ① 3단계 자리 4칸(채우기 = 휴면 카드 몫 · 여기선 칸만)
    "휴면 revision", "세대", "마지막 단계", "중단 복구 위치",
) + POINTERS
REVISION = "기록 판"
NONE = "없음"
Result = collections.namedtuple("Result", "result team revision status fields written path reason",
                                defaults=(None, None, None, None, False, None, ""))


class TeamRecord:
    """팀 1곳의 기록 파일. 다른 팀 좌석은 읽기만 한다."""

    def __init__(self, root, team, clock=None, on_step=None):
        self.root, self.team = os.path.abspath(root), team
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step = on_step or (lambda step: None)
        self.dir = os.path.join(self.root, ".fable-team", "teams", team)
        self.path = os.path.join(self.dir, "TEAM-RECORD.md")
        self.lock_path = os.path.join(self.dir, "runtime", "writer.lock")

    def read(self):
        """잠금 0 · 쓰기 0. 없음 = 접수 거부 · 꼴 깨짐 = 복구 필요."""
        try:
            with open(self.path, encoding="utf-8") as handle:
                text = handle.read()
        except FileNotFoundError:
            return self._out(REFUSED, reason="판정 불가 기록 없음: %s" % self.path)
        except (OSError, UnicodeDecodeError) as exc:
            return self._out(CORRUPT, reason="팀 기록 판독 불가: %s" % exc)
        try:
            fields, revision = self._parse(text)
        except ValueError as exc:
            return self._out(CORRUPT, reason=str(exc))
        return self._out(OK, revision, fields=fields)

    def write(self, seat, expect, fields):
        """검사(쓰기 전) → writer.lock 비차단 → 판 대조 → 원자 교체."""
        problem = self._problem(seat, expect, fields)
        if problem:
            return self._out(REFUSED, reason=problem)
        lock = self._try_lock()
        if lock is None:
            return self._out(BUSY, reason="writer.lock 점유 = 기다리지 않는다")
        try:
            return self._write_locked(expect, fields)
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
            lock.close()

    def _write_locked(self, expect, fields):
        current = self.read()
        if current.result == CORRUPT:
            return current
        revision = current.revision if current.result == OK else 0
        if self._stale(expect, revision):
            return self._out(HOLD, revision, status="RETRY",
                             reason="기록 판 불일치 %r != %r = 다시 읽어라(쓰기 0)" % (expect, revision))
        ordered = {name: fields[name] for name in FIELDS}
        self._atomic_write(self._render(ordered, revision + 1))
        return self._out(OK, revision + 1, fields=ordered, written=True)

    def _problem(self, seat, expect, fields):
        """쓰기 전 거절 사유 1개(없으면 빈 문자열)."""
        if not self._seat_ok(seat):
            return "좌석 %r 은 팀 %s 좌석(byz-%s-)이 아니다 — 다른 팀은 읽기만" % (seat, self.team, self.team)
        if isinstance(expect, bool) or not isinstance(expect, int):
            return "expect 는 정수 기록 판이어야 한다: %r" % (expect,)
        if not isinstance(fields, dict):
            return "칸 묶음은 dict 여야 한다"
        missing = [name for name in FIELDS if name not in fields]
        extra = sorted(name for name in fields if name not in FIELDS)
        if missing or extra:
            return "칸 불일치 — 빠짐 %s · 모름 %s" % (missing, extra)
        for name in FIELDS:
            value = fields[name]
            if not isinstance(value, str):
                return "%s 값은 문자열이어야 한다" % name
            if self._empty(value):
                return "%s 빈 칸 — 해당 없음 = «0» 또는 «없음(사유)»" % name
            if "\n" in value or "\r" in value:
                return "%s 값은 한 줄만 — 본문 복사 0(경로로 가리킨다)" % name
        for name in POINTERS:
            if not self._pointer_ok(fields[name]):
                return "%s 경로 없음: %r — 경로 또는 «없음» 만" % (name, fields[name])
        return ""

    def _seat_ok(self, seat):
        """변이 M1 자리 — 같은 팀 접두만 쓴다."""
        return isinstance(seat, str) and seat.startswith("byz-%s-" % self.team)

    def _stale(self, expect, revision):
        """변이 M2 자리 — 읽어 둔 판이 낡았는가."""
        return expect != revision

    def _empty(self, value):
        """변이 M4 자리 — 빈 칸 검사."""
        return not value.strip()

    def _pointer_ok(self, value):
        if value == NONE or value.startswith(NONE + "("):
            return True
        path = value if os.path.isabs(value) else os.path.join(self.root, value)
        return os.path.exists(path)

    def _render(self, fields, revision):
        lines = ["# 팀 기록 — %s" % self.team]
        lines += ["- %s: %s" % (name, fields[name]) for name in FIELDS]
        lines.append("- %s: %d" % (REVISION, revision))
        return "\n".join(lines) + "\n"

    def _parse(self, text):
        lines = text.split("\n")
        names = FIELDS + (REVISION,)
        if lines[-1:] != [""] or len(lines) != len(names) + 2 or lines[0] != "# 팀 기록 — %s" % self.team:
            raise ValueError("팀 기록 꼴 깨짐(머리·줄 수): %s" % self.path)
        fields = {}
        for name, line in zip(names, lines[1:-1]):
            head = "- %s: " % name
            if not line.startswith(head) or not line[len(head):].strip():
                raise ValueError("팀 기록 꼴 깨짐(칸 %s): %r" % (name, line))
            fields[name] = line[len(head):]
        revision = fields.pop(REVISION)
        if not revision.isdigit() or int(revision) < 1:
            raise ValueError("기록 판이 정수가 아니다: %r" % revision)
        return fields, int(revision)

    def _atomic_write(self, text):
        os.makedirs(self.dir, exist_ok=True)
        tmp = "%s.tmp.%d" % (self.path, os.getpid())
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        self.on_step("after_tmp_fsync")
        self._commit(tmp, text)

    def _commit(self, tmp, text):
        """변이 M3 자리 — rename 으로만 바꾼다(반쯤 쓴 기록 0)."""
        self.on_step("before_rename")
        os.replace(tmp, self.path)
        self.on_step("after_rename")
        fd = os.open(self.dir, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        self.on_step("after_dir_fsync")

    def _try_lock(self):
        """팀 runtime writer.lock 비차단 1회 — 점유 중이면 None(dispatch·lifecycle 과 같은 잠금)."""
        os.makedirs(os.path.dirname(self.lock_path), exist_ok=True)
        handle = open(self.lock_path, "a+", encoding="utf-8")
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return None
        return handle

    def _out(self, result, revision=None, status=None, fields=None, written=False, reason=""):
        return Result(result, self.team, revision, status, fields, written, self.path, reason)
