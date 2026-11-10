"""ft2 코어 진행 구분·골 마감 — (r1594 · PR② 다섯째 장).

계약 사례 10(진행 구분)·11(마감 경합)을 제품 코드로 재생한다. «진짜 진척과 heartbeat·외부 대기를
가르고, 낡은 revision 으로는 골을 닫지 않는다» 가 정본 PLAN 의 두 전이다.
시계 = journal seq(논리 tick) — 별도 시계 파일 0. 진행 1줄이 tick 1 이므로 `progress_age` 도
`stall_after` 도 tick 단위다(문턱 수치는 계약값이 아니다 · CASES.md §비채택 10).
`heartbeat` 는 `progress_at` 을 밀지 않는다(재무장 0 · 사례 10 D). `external_wait` 는 시한이 필수이고
시한 안이면 멈춤이 아니다(사례 10 C — 시한은 «남은 tick» 으로 받아 절대 tick 으로 보존한다).
마감 = revision 대조(RETRY) → pending·owners·uncertain 잔여 대조(거절) → close 1줄(done["goal:<골>"]).
ft2 의 `state.pending` 은 용량 장부라 스스로 비지 않는다 — 마감 판정은 `done` 에 없는 접수만
«남은 pending» 으로 세고, command 와 work 가 다를 수 있으므로 accept 줄로 command → work 사상을 먼저 한다
(DA 회차 1 R2 반례).
마감 표식은 `done["goal:<골>"]` 한 곳이다(r1594 arch 결정) — journal 회수 판정이 work 단위
`_work_closed` 이므로 close 줄의 work 도 그 자리여야 회수 대상이 된다. 그래서 close 줄의 work =
`goal:<골>` 이고 같은 transaction 이 그 표식을 세운다(성공할 때만 1줄 · RETRY·거절은 쓰기 0).
blockers 낱말은 원자료 `cases_c.py:99-146` 값 그대로다(`PENDING_NOT_ZERO` · `GRANTED` · `STARTED` ·
`UNCERTAIN` · `<낱말>:<키>`). 결과 낱말은 `contracts/core` 7군(8낱말) 밖으로 나가지 않는다(새 낱말 0).
잠금 = 팀별 writer.lock «비차단» 1회(dispatch 와 같은 꼴 · 점유 중 = BUSY · 쓰기 0).
회수 규칙은 journal 그대로다 — 진행·마감 줄의 work 가 `_work_closed` 를 만족하면 그 segment 가 회수된다.
"""
import collections
import importlib.util
import os
import time

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(_HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake = _load("record", "ft2_core_record"), _load("intake", "ft2_core_intake")
OK, HOLD, REFUSED, BUSY, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "BUSY", "복구 필요"
PROGRESS_KINDS = ("progress", "heartbeat", "external_wait")
Tick = collections.namedtuple("Tick", "result lane tick deadline written revision reason",
                              defaults=(None, None, None, None, False, None, ""))
Scan = collections.namedtuple("Scan", "result lanes stalled_lanes tick revision written reason",
                              defaults=(None, None, None, None, None, False, ""))
Close = collections.namedtuple("Close", "result goal status revision blockers written reason",
                               defaults=(None, None, None, None, None, False, ""))


class Lifecycle:
    """팀 runtime 1곳의 진행 구분·마감. 경로·잠금·판독은 입구(Intake)와 같은 것을 쓴다."""
    CLIENT = intake.Intake

    def __init__(self, root, team, clock=None, on_step=None):
        self.team, self.on_step = team, on_step or (lambda step: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.rs = self.CLIENT(root, team, on_step=self.on_step)

    def progress(self, work, lane, kind, deadline=None):
        """lane 진행 1줄 — `progress` | `heartbeat` | `external_wait(시한 필수 · 남은 tick)`."""
        return self._locked(self._progress, Tick(HOLD), work, lane, kind, deadline)

    def scan(self, stall_after=3):
        """진척 나이만 센다 — heartbeat 는 세지 않고, 시한 안 외부 대기는 멈춤이 아니다(읽기 전용)."""
        return self._locked(self._scan, Scan(HOLD), stall_after, k=0)

    def close(self, goal, revision):
        """골 마감 — 읽어 둔 revision 이 낡았으면 RETRY(쓰기 0), 남은 일이 있으면 거절, 아니면 close 1줄."""
        return self._locked(self._close, Close(HOLD, goal), goal, revision)

    def _locked(self, body, fail, *args, k=1):
        lock, word, written = self.rs._try_lock(), BUSY, False
        reason = "writer.lock 점유 = 기다리지 않는다"
        try:
            if lock is not None:
                if k:
                    self.rs.journal.reserve(k)                  # 첫 쓰기 전 호출 단위 합산 예약
                return body(self._state_records(), *args)
        except ValueError as exc:      # 모듈 사본(_load)마다 클래스가 달라 낱말 칸으로 가른다
            word, reason = getattr(exc, "word", CORRUPT), str(exc)
            written = getattr(exc, "written", False)
        finally:
            if lock is not None:
                self.rs._unlock(lock)
        return fail._replace(result=word, written=written, reason=reason)

    def _progress(self, context, work, lane, kind, deadline):
        state, records = context
        if not lane or kind not in PROGRESS_KINDS:
            return Tick(REFUSED, lane, reason="진행 줄 거절: lane=%r kind=%r" % (lane, kind))
        if kind == "external_wait" and not (isinstance(deadline, int) and deadline >= 1):
            return Tick(REFUSED, lane, reason="외부 대기 = 시한 필수(남은 tick ≥ 1)")
        tick = self._tick(records) + 1
        kind = self._kind_of(kind)
        at = tick + deadline if kind == "external_wait" else None
        row = self._touch(dict(self._lanes(state).get(lane) or {}), kind, tick, at)
        rec = record.build(self.team, tick, lane, "%s#t%d" % (lane, tick), self.clock(), kind, work,
                           kind="progress", extra={"lane": lane, "tick": tick, "tick_kind": kind,
                                                   "wait_deadline": at})
        rev = self._write(state, records, rec, {"lanes": {lane: row}})
        self.on_step("after_progress")
        return Tick(OK, lane, tick, row["wait_deadline"], True, rev)

    def _kind_of(self, kind):
        """기록에 남는 진행 종류 — 변이 M1(heartbeat 를 progress 로 세기)의 자리."""
        return kind

    def _touch(self, row, kind, tick, deadline):
        """lane 1칸 갱신 — heartbeat 는 progress_at 을 밀지 않는다(재무장 0). deadline = 절대 tick."""
        return record._lane_row(row, kind, tick, deadline)

    def _scan(self, context, stall_after):
        state, records = context
        tick, lanes = self._tick(records), {}
        for lane, row in sorted(self._lanes(state).items()):
            age, kept = tick - row["progress_at"], row.get("wait_deadline")
            if row.get("external_wait") and kept is not None and tick <= kept:
                lanes[lane] = {"stalled": False, "reason": "EXTERNAL_WAIT_WITHIN_DEADLINE",
                               "wait_deadline": kept, "progress_age": age}
                continue
            stalled = age >= stall_after
            lanes[lane] = {"stalled": stalled, "reason": "PROGRESS_STALE" if stalled else "PROGRESS_FRESH",
                           "wait_deadline": kept, "progress_age": age,
                           "heartbeat_age": tick - row["heartbeat_at"], "rearm": row["rearm"]}
        return Scan(result=HOLD, lanes=lanes, stalled_lanes=sorted(
            lane for lane, row in lanes.items() if row["stalled"]), tick=tick,
            revision=state["revision"], reason="" if lanes else "lane 기록 0")

    def _close(self, context, goal, revision):
        state, records = context
        if not goal:
            return Close(REFUSED, goal, "REFUSED", state["revision"], [], False, "골 이름 없음")
        key = self._goal_key(goal)
        if key in (state.get("done") or {}):
            return Close(HOLD, goal, "CLOSED", state["revision"], [], False, "이미 마감 = 멱등(쓰기 0)")
        if self._revision_stale(state, revision):
            return Close(HOLD, goal, "RETRY", state["revision"], [], False,
                         "revision 불일치 %r != %r = 다시 읽어라(쓰기 0)"
                         % (revision, state["revision"]))
        blockers = self._blockers(state, records)
        if blockers:
            return Close(HOLD, goal, "REFUSED", state["revision"], blockers, False,
                         "남은 일 %d = 마감 거절(쓰기 0)" % len(blockers))
        tick = self._tick(records) + 1
        rec = record.build(self.team, tick, key, "%s#close" % goal, self.clock(), "", key,
                           kind="close", extra={"tick": tick, "goal": goal})
        rev = self._write(state, records, rec, {"done": {key: {"attempt": None, "at": rec["at"],
                                                           "marker": "", "tick": tick}}})
        self.on_step("after_close")
        return Close(OK, goal, "CLOSED", rev, [], True)

    def _goal_key(self, goal):
        """마감 줄의 work — `goal:<골>`. journal 회수 판정(work 단위)과 같은 자리에 둔다(r1594 arch)."""
        return "goal:%s" % goal

    def _revision_stale(self, state, revision):
        return state["revision"] != revision

    def _blockers(self, state, records):
        """원자료 blockers 값 그대로 — pending · owners(GRANTED/STARTED) · uncertain."""
        done = state.get("done") or {}
        pending = [work for work in self._pending_works(state, records) if work not in done]
        blockers = ["PENDING_NOT_ZERO:%d" % len(pending)] if pending else []
        for work in sorted(state.get("owners") or {}):
            blockers.append("%s:%s" % (self._owner_word(records, work), work))
        blockers += ["UNCERTAIN:%s" % work for work in sorted(state.get("uncertain") or {})]
        return blockers

    def _pending_works(self, state, records):
        """«남은 일» — intake 용량 상한과 **같은** 장부(`record.remaining` · 회수된 접수·done work 제외).
        command 이름이 work 와 달라도 마감 판정이 맞도록 accept 줄로 command → work 사상을 먼저 한다."""
        by_command = {rec["command"]: rec.get("work") for rec in records if rec["kind"] == "accept"}
        return [by_command.get(command) or command for command in record.remaining(state, records)]

    def _owner_word(self, records, work):
        """착수 기록이 있으면 STARTED · 실행권만 있으면 GRANTED(원자료 낱말)."""
        return "STARTED" if [rec for rec in records
                             if rec["kind"] == "start" and rec.get("work") == work] else "GRANTED"

    def _state_records(self):
        return record.recover_state(self.rs._state(), self.rs.records()), self.rs.records()

    def _write(self, state, records, rec, extra=None):
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        self.on_step("after_%s_journal" % rec["kind"])
        new_state = dict(state, revision=state["revision"] + 1)
        for name, value in (extra or {}).items():
            new_state[name] = {**(state.get(name) or {}), **value}
        self.rs._write_state(new_state)
        self.on_step("after_state")
        return new_state["revision"]

    def _tick(self, records):
        return records[-1]["seq"] if records else 0

    def _lanes(self, state):
        return dict(state.get("lanes") or {})
