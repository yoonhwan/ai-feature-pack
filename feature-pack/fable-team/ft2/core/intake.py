"""ft2 코어 입구 — 접수 · 영수 · 같은 command 조회 (r1576 · PR② 첫 장).

내구화 순서(PLAN §210): 본문 tmp → 파일 fsync → bodies rename → 폴더 fsync → journal fsync
→ state checkpoint → 성공 영수. 영수는 이 순서 뒤에만 난다. 실패(§211): FULL 은 DEFERRED 보존,
영수 미확정이면 같은 command ID 조회가 먼저다(새 attempt 0).
"""

import collections
import fcntl
import importlib.util
import json
import os
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_core_record", os.path.join(_HERE, "record.py"))
record = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(record)

RESULT_OK, RESULT_HOLD, RESULT_FULL, RESULT_CORRUPT = "접수 성공", "완료 유보", "용량 부족", "복구 필요"
RESULT_BUSY = "BUSY"
DURABLE_OPS = ("body_tmp_write", "body_file_fsync", "body_rename", "body_dir_fsync",
               "journal_write", "journal_fsync", "receipt")
Receipt = collections.namedtuple("Receipt", "result command attempt revision written body_ref reason",
                                 defaults=(None, None, None, False, None, ""))


CorruptStateError = record.CorruptStateError


def duplicate_commands(records):
    """command 별 기록 수 — 2 이상이면 중복 접수(ⓑ·ⓒ 검사)."""
    counts = collections.Counter(rec["command"] for rec in records)
    return {command: count for command, count in counts.items() if count > 1}


def order_violations(ops):
    """내구화 순서 검사(ⓐ). 빈 목록 = 통과. 영수가 journal fsync 앞에 오면 잡힌다."""
    missing = [name for name in DURABLE_OPS if name not in ops]
    out = ["누락: " + ",".join(missing)] if missing else []
    for before, after in zip(DURABLE_OPS, DURABLE_OPS[1:]):
        if before in ops and after in ops and ops.index(before) > ops.index(after):
            out.append("순서 뒤집힘: %s 뒤에 %s" % (before, after))
    return out


class Intake:
    """팀 runtime 1곳의 입구. 실패·미확정은 성공으로 응답하지 않는다."""
    def __init__(self, root, team, capacity=8, on_step=None, clock=None):
        self.team = team
        self.capacity = capacity
        self.on_step = on_step or (lambda step: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.runtime = os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "runtime")
        self.state_path = os.path.join(self.runtime, "state.json")
        self.journal_path = os.path.join(self.runtime, "journal.jsonl")
        self.ops_path = os.path.join(self.runtime, "ops.jsonl")
        self.bodies = os.path.join(self.runtime, "bodies")
        self.tmp = os.path.join(self.runtime, "tmp")
        self.lock_path = os.path.join(self.runtime, "writer.lock")
        self._ensure()

    def _lock_file_path(self):
        return self.lock_path                      # 팀별 잠금 — 팀 전역 잠금 0(ⓔ)

    def _try_lock(self):
        """writer.lock 비차단 시도 — 잡으면 핸들, 점유 중이면 None(기다리지 않는다 · ⓗ)."""
        handle = open(self._lock_file_path(), "a+", encoding="utf-8")
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return None
        return handle

    def _unlock(self, handle):
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()

    def body_path(self, command):
        return os.path.join(self.bodies, command + ".body")

    def _ensure(self):
        for path in (self.runtime, self.bodies, self.tmp):
            os.makedirs(path, exist_ok=True)

    def _ops(self, op):
        with open(self.ops_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"op": op}, ensure_ascii=False) + "\n")

    def records(self):
        """journal 을 판독한다. schema 가 어긋난 줄은 `CorruptStateError`(기존 자료 보존)."""
        if not os.path.exists(self.journal_path):
            return []
        out = []
        with open(self.journal_path, encoding="utf-8") as handle:
            for line in handle:
                if not line.strip():
                    continue
                try:
                    rec = json.loads(line)
                    record.check(rec)
                except (ValueError, record.RecordError) as exc:
                    raise CorruptStateError("journal 판독 불가: %s" % exc)
                out.append(rec)
        return out

    def _state(self):
        return record.read_state_guarded(self.state_path)

    def _prior_receipt(self, records, command):
        """입구 판독은 kind=accept 만 접수로 본다(ⓙ · 실행권 줄은 영수가 아니다)."""
        return next((rec for rec in reversed(records)
                     if rec["command"] == command and rec["kind"] == "accept"), None)

    def _orphan_body(self, command):
        return os.path.exists(self.body_path(command))

    def _pending(self, records, state):
        """용량 기준 = 내구화된 journal(+state 투영). state 만 세면 checkpoint 없는 crash 뒤가 빈다.
        실행권·착수·결과 줄은 접수가 아니므로 세지 않는다(ⓙ)."""
        accepted = [rec["command"] for rec in records if rec["kind"] == "accept"]
        return list(dict.fromkeys(accepted + list(state["pending"])))

    def _full(self, pending):
        return len(pending) >= self.capacity

    def _durable_body(self, command, body):
        tmp = os.path.join(self.tmp, command + ".body.tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(body)
            handle.flush()
            self._ops("body_tmp_write")
            os.fsync(handle.fileno())
        self._ops("body_file_fsync")
        os.replace(tmp, self.body_path(command))
        self._ops("body_rename")
        _fsync_dir(self.bodies)
        self._ops("body_dir_fsync")
        return os.path.relpath(self.body_path(command), self.runtime)

    def _append_journal(self, rec):
        record.check(rec)
        with open(self.journal_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            self._ops("journal_write")
            os.fsync(handle.fileno())
        self._ops("journal_fsync")
        _fsync_dir(self.runtime)

    def _write_state(self, state):
        tmp = os.path.join(self.tmp, "state.json.tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(state, handle, ensure_ascii=False, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.state_path)
        _fsync_dir(self.runtime)
        self._ops("state_write")

    def submit(self, command, body, work=None):
        """같은 팀 writer.lock 을 «비차단» 으로 잡고 접수한다. 점유 중이면 BUSY·쓰기 0(ⓗ)."""
        lock = self._try_lock()
        if lock is None:
            return Receipt(RESULT_BUSY, command, reason="writer.lock 점유 = 기다리지 않는다(BUSY)")
        try:
            return self._submit_locked(command, body, work)
        finally:
            self._unlock(lock)

    def _submit_locked(self, command, body, work=None):
        """잠금 안의 접수 본체 — 영수는 내구화가 끝난 뒤에만 난다."""
        try:
            state, records = self._state(), self.records()
        except CorruptStateError as exc:
            self._ops("read_state_guarded")
            return Receipt(RESULT_CORRUPT, command, reason=str(exc))
        prior = self._prior_receipt(records, command)
        if prior is not None:
            return Receipt(RESULT_HOLD, command, prior["attempt"], state["revision"], reason="같은 command 기록 = 재부여 0")
        if self._orphan_body(command):
            return Receipt(RESULT_HOLD, command, None, state["revision"], reason="본문만 남음 = 영수 미확정")
        pending = self._pending(records, state)
        if self._full(pending):
            return Receipt(RESULT_FULL, command, None, state["revision"], reason="pending %d >= 상한 %d" % (len(pending), self.capacity))
        attempt = "%s#a%d" % (command, state["attempts"].get(command, 0) + 1)
        body_ref = self._durable_body(command, body)
        self.on_step("after_body")
        seq = (records[-1]["seq"] if records else 0) + 1
        self._append_journal(record.build(self.team, seq, command, attempt, self.clock(), body_ref, work))
        self.on_step("after_journal")
        new_state = self._next_state(state, command, pending)
        self._write_state(new_state)
        self.on_step("after_state")
        self._ops("receipt")
        return Receipt(RESULT_OK, command, attempt, new_state["revision"], True, body_ref)

    def _next_state(self, state, command, pending):
        """교체가 아닌 «병합» — 세대·owner·불명 표시 등 확장 칸을 보존한다(ⓘ)."""
        return dict(state, revision=state["revision"] + 1, pending=pending + [command],
                    attempts=dict(state["attempts"],
                                  **{command: state["attempts"].get(command, 0) + 1}))

    def lookup(self, command):
        """같은 command ID 조회 — 영수 유실·crash 뒤 판정은 이 하나로 한다(새 attempt 0)."""
        try:
            state, records = self._state(), self.records()
        except CorruptStateError as exc:
            return Receipt(RESULT_CORRUPT, command, reason=str(exc))
        prior = self._prior_receipt(records, command)
        if prior is not None:
            return Receipt(RESULT_OK, command, prior["attempt"], state["revision"], reason="journal 기록 = 판정")
        if self._orphan_body(command):
            return Receipt(RESULT_HOLD, command, None, state["revision"], reason="본문만 남음 = 영수 미확정")
        return None


def _fsync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)
