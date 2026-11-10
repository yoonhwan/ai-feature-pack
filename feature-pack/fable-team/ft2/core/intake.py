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
_SPEC_J = importlib.util.spec_from_file_location("ft2_core_journal", os.path.join(_HERE, "journal.py"))
journal = importlib.util.module_from_spec(_SPEC_J)
_SPEC_J.loader.exec_module(journal)

RESULT_OK, RESULT_HOLD, RESULT_FULL, RESULT_CORRUPT = "접수 성공", "완료 유보", "용량 부족", "복구 필요"
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
    def __init__(self, root, team, capacity=8, on_step=None, clock=None,
                 segment_cap=65536, total_cap=8388608, reserve=532480, state_slack=4096, line_max=512):
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
        # r1584: journal 판독·쓰기·회전·총량은 journal.Journal 한 곳이 한다(세 writer 가 이 객체를 쓴다).
        self.journal = journal.Journal(self.runtime, segment_cap=segment_cap, total_cap=total_cap,
                                      reserve=reserve, state_slack=state_slack, line_max=line_max,
                                      ops=self._ops, on_step=self.on_step, rec=record)

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
        """journal 을 판독한다 — 닫힌 segment(N 오름차순) + 활성 파일 한 줄 순서. seq 역행은 CorruptStateError."""
        return self.journal.records()

    def _state(self):
        return self.journal.state()

    def _prior_receipt(self, records, command):
        """입구 판독은 kind=accept 만 접수로 본다(ⓙ · 실행권 줄은 영수가 아니다).
        회수된 accept 영수는 base(receipts)에서 읽는다(DA R1 ⑥) — 회수 전후 재접수 결과가 같다."""
        found = next((rec for rec in reversed(records)
                      if rec["command"] == command and rec["kind"] == "accept"), None)
        if found is not None:
            return found
        base = (self.journal.cached_state.get("journal_base") or {}).get("receipts") or {}
        return {"attempt": base[command], "command": command, "kind": "accept"} if command in base else None

    def _orphan_body(self, command):
        return os.path.exists(self.body_path(command))

    def _pending(self, records, state):
        """용량 기준 = 내구화된 journal(+state 투영). state 만 세면 checkpoint 없는 crash 뒤가 빈다.
        실행권·착수·결과 줄은 접수가 아니므로 세지 않는다(ⓙ). 회수된 접수(journal_base.receipts)는
        «남은 일» 이 아니므로 용량에서도 뺐다(r1616 · 원천 시쇬 case_08 = 정리 뒤 새 8건 성공)."""
        accepted = [rec["command"] for rec in records if rec["kind"] == "accept"]
        folded = (state.get("journal_base") or {}).get("receipts") or {}
        return [cmd for cmd in dict.fromkeys(accepted + list(state["pending"])) if cmd not in folded]

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

    def _append_journal(self, rec, envelope=None):
        """journal 1줄 내구화 — 총량 예약을 «줄이기 전» 에 판정한다(scalar 부족이면 WriterRefused)."""
        self.journal.append(rec, envelope)

    def _write_state(self, state):
        self.journal.write_state(state)

    def submit(self, command, body, work=None):
        """같은 팀 writer.lock 을 «비차단» 으로 잡고 접수한다. 점유 중이면 BUSY·쓰기 0(ⓗ)."""
        lock = self._try_lock()
        if lock is None:
            return Receipt("BUSY", command, reason="writer.lock 점유 = 기다리지 않는다(BUSY)")
        try:
            return self._submit_locked(command, body, work)
        finally:
            self._unlock(lock)

    def _submit_locked(self, command, body, work=None):
        """잠금 안의 접수 본체 — 영수는 내구화가 끝난 뒤에만 난다."""
        try:
            state, records = self._state(), self.records()
            state = record.recover_state(state, records)      # DA R2: 내구 journal 이 기준(공통 writer)
            prior = self._prior_receipt(records, command)
            if prior is not None:
                return Receipt(RESULT_HOLD, command, prior["attempt"], state["revision"], reason="같은 command 기록 = 재부여 0")
            if self._orphan_body(command):
                return Receipt(RESULT_HOLD, command, None, state["revision"], reason="본문만 남음 = 영수 미확정")
            pending = self._pending(records, state)
            if self._full(pending):
                return Receipt(RESULT_FULL, command, None, state["revision"], reason="pending %d >= 상한 %d" % (len(pending), self.capacity))
            attempt = "%s#a%d" % (command, state["attempts"].get(command, 0) + 1)
            new_state = self._next_state(state, command, pending)
            seq = (records[-1]["seq"] if records else 0) + 1
            rec = record.build(self.team, seq, command, attempt, self.clock(),
                               os.path.relpath(self.body_path(command), self.runtime), work)
            envelope = self.journal.envelope_for(new_state)
            if not self.journal.admits_submit(body, rec, envelope):     # DA R2: 본문 tmp «전» 총량 판정
                return Receipt(RESULT_FULL, command, None, state["revision"],
                               reason="총량 한계 초과 = 쓰기 0")
            body_ref = self._durable_body(command, body)
            self.on_step("after_body")
            self._append_journal(rec, envelope)
            self.on_step("after_journal")
            self._write_state(new_state)
            self.on_step("after_state")
            self._ops("receipt")
            return Receipt(RESULT_OK, command, attempt, new_state["revision"], True, body_ref)
        except CorruptStateError as exc:
            self._ops("read_state_guarded")
            return Receipt(RESULT_CORRUPT, command, reason=str(exc))

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
