"""ft2 코어 실행권·세대 — claim · start · effect · result · uncertain (r1579 · PR② 둘째 장).
정본 PLAN §작업별 실행권(204·213행)만 담는다. 작업/효과 범위별 holder·gen(epoch)을 기록하고 세대가 바뀐 뒤
옛 gen 의 쓰기는 «낡은 실행권» 으로 거절한다(쓰기 0 · revision 불변). 효과 «의도» 를 먼저 내구화하고,
의도만 기록된 작업은 «완료 유보»(UNCERTAIN)로 보존하며 재실행하지 않는다 — 같은 세대로 다시 들어온 효과
재호출도 결과 미확정이다. 세대 교체(rotation)는 구 실행자 종료·권한 회수를 확인한 호출만 쓴다(PLAN 213)이고,
journal 세대는 checkpoint 보다 앞서도 유효본이다(DA R2). 같은 팀 writer 는 모두 같은
writer.lock 을 «비차단» 으로 잡는다 — 점유 중이면 BUSY(팀별 잠금). 결과 낱말은 8낱말 밖으로 나가지 않는다. schema 는 1 그대로다(필드 추가만). 미확정 표식은 확인 시한까지 기록에 싣는다.
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
OK, HOLD, STALE, BUSY = "접수 성공", "완료 유보", "낡은 실행권", "BUSY"
CORRUPT, REFUSED, RECOVERED = "복구 필요", "접수 거부", "회수 결과"
Grant = collections.namedtuple(
    "Grant", "result work gen holder revision written stage confirm_by reason",
    defaults=(None, None, None, None, False, None, None, ""))


def accepted(records, work):
    """접수 영수 = 같은 work 를 남긴 accept 줄 — 배정·실행권 입구가 함께 보는 한 곳(r1632 ⓓ)."""
    return any(rec["kind"] == "accept" and rec.get("work") == work for rec in records)


class Execution:
    """팀 runtime 1곳의 실행권. 경로·판독·내구화·잠금은 입구(Intake)와 같은 것을 쓴다."""
    CLIENT = intake.Intake

    def __init__(self, root, team, clock=None, on_step=None):
        self.team = team
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step = on_step or (lambda step: None)
        self.rs = self.CLIENT(root, team, on_step=self.on_step)

    def claim(self, work, holder, rotation=False, confirm_by=None):
        """작업 범위의 실행권을 새 세대로 받는다. rotation = 구 실행자 종료·권한 회수 확인됨."""
        try:
            lock = self.rs._try_lock()
            if lock is None:
                return Grant(BUSY, work, holder=holder, reason="writer.lock 점유 = 기다리지 않는다")
            try:
                state, records = self._state_records()
                if not accepted(records, work):        # r1632: 접수 영수 없는 일은 실행권 0(쓰기 0)
                    return Grant(REFUSED, work, holder=holder, reason="접수 영수 없음 · intake.submit 먼저")
                if work in (state.get("done") or {}):  # r1901: 완료된 일 = 실행권 0(쓰기 0 · owner 잔존 0)
                    return Grant(REFUSED, work, holder=holder, reason="완료된 일 = 실행권 0 · 새 일은 새 접수")
                dormant = self._dormant_marker(state)  # r1714: 휴면 표식 뒤 접수 = 닫는 세대 실행권 0(쓰기 0)
                if dormant:
                    return Grant(REFUSED, work, holder=holder, reason="휴면 표식 %s = 접수 거부" % dormant)
                gen, hold, owner = self._claim_plan(state, records, work, holder, rotation)
                if hold is not None:
                    if hold.get("marked"):
                        return Grant(HOLD, work, hold.get("gen"), holder, state["revision"], False,
                                     "uncertain", hold.get("confirm_by"), "결과 미확정 = 재실행 0")
                    return self._mark(state, records, work, holder, hold, confirm_by or self._confirm_by())
                rec = record.build(self.team, self._seq(records), work, "%s#g%d" % (holder, gen), owner["at"],
                                   "", work, kind="claim", holder=holder, gen=gen)
                generations = dict(self._field(state, "generations"), **{work: gen})
                rev = self._write(state, records, rec, {"generations": generations,
                                                        "owners": dict(self._field(state, "owners"), **{work: owner})})
                self.on_step("after_claim")
                return Grant(OK, work, gen, holder, rev, True, "claimed")
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(getattr(exc, "word", CORRUPT), work, holder=holder, written=getattr(exc, "written", False), reason=str(exc))

    def _dormant_marker(self, state):
        """휴면 표식 = `lifecycle.close("dormant:<팀>", R)` 가 세운 `goal:dormant:<팀>` 1줄(r1714)."""
        key = "goal:dormant:%s" % self.team
        return key if key in (state.get("done") or {}) else None

    def start(self, work, holder, gen):
        return self._step(work, holder, gen, "start", "")

    def effect(self, work, holder, gen, effect, run=None):
        """효과 «의도» 를 먼저 내구화한 뒤 대역을 실행한다(crash = 완료 유보 · 재실행 0)."""
        grant = self._step(work, holder, gen, "effect", effect)
        if grant.result == OK and run is not None:
            run()
            self.on_step("after_effect")
        return grant

    def result(self, work, holder, gen, word=RECOVERED):
        """결과 확정. 계약 8낱말 밖의 낱말은 «접수 거부» 다(ⓕ)."""
        if not record.is_contract_result(word):
            return Grant(REFUSED, work, gen, holder, reason="계약 밖 결과 낱말: %r" % (word,))
        return self._step(work, holder, gen, "result", "", drop=True)

    def mark_uncertain(self, work, holder, gen, reason, confirm_by=None):
        """무응답·crash 를 «완료 유보» 로 보존한다(확인 시한 기록 · 재실행 0)."""
        try:
            lock = self.rs._try_lock()
            if lock is None:
                return Grant(BUSY, work, gen, holder, reason="writer.lock 점유 = 기다리지 않는다")
            try:
                state, records = self._state_records()
                if not self._gen_matches(state, work, gen):
                    return Grant(STALE, work, gen, holder, state["revision"], False, "uncertain",
                                 reason="낡은 실행권 = 쓰기 0")
                return self._mark(state, records, work, holder, {"gen": gen, "reason": reason},
                                  confirm_by or self._confirm_by())
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(getattr(exc, "word", CORRUPT), work, gen, holder, written=getattr(exc, "written", False), reason=str(exc))

    def _step(self, work, holder, gen, kind, body, drop=False):
        """gen 대조 → 미확정 확인 → journal → state. 잠금은 쓰기 동안만 잡는다."""
        try:
            lock = self.rs._try_lock()
            if lock is None:
                return Grant(BUSY, work, gen, holder, reason="writer.lock 점유 = 기다리지 않는다")
            try:
                state, records = self._state_records()
                if not self._gen_matches(state, work, gen):
                    return Grant(STALE, work, gen, holder, state["revision"], False, kind,
                                 reason="낡은 실행권 = 쓰기 0")
                # 쓰기 단계의 gen 은 이미 내구화된 실행권이라 «회전 확인» 은 끝났다(DA R2).
                hold = self._hold(state, records, work, gen, True, closing=kind == "result")
                if hold is not None:
                    if hold.get("marked") or kind == "result":
                        return Grant(HOLD, work, gen, holder, state["revision"], False, kind,
                                     hold.get("confirm_by"), "결과 미확정 = 재실행 0")
                    return self._mark(state, records, work, holder, hold, self._confirm_by())
                rec = record.build(self.team, self._seq(records), work, "%s#g%d" % (holder, gen),
                                   self.clock(), body, work, kind=kind, holder=holder, gen=gen)
                extra = {}
                if drop:
                    extra = {"owners": {k: v for k, v in self._field(state, "owners").items() if k != work},
                             "uncertain": {k: v for k, v in self._field(state, "uncertain").items() if k != work}}
                rev = self._write(state, records, rec, extra)
                self.on_step("after_" + kind)
                return Grant(OK, work, gen, holder, rev, True, kind)
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(getattr(exc, "word", CORRUPT), work, gen, holder, written=getattr(exc, "written", False), reason=str(exc))

    def _claim_plan(self, state, records, work, holder, rotation=False):
        """잠금 안 판정(쓰기 0) — (세대, 미확정, owner 칸)을 돌려준다. 배정(dispatch)도 이 함수를 쓴다.
        `hold` 가 있으면 배정·실행권 부여는 없다(claim 은 표식을 남기고, 배정은 결과만 돌려준다)."""
        gen = self._field(state, "generations").get(work, 0) + 1
        hold = self._hold(state, records, work, gen, rotation)
        if hold is not None:
            return gen, hold, None
        owner = {"holder": holder, "gen": gen, "at": self.clock(), "rotation": bool(rotation)}
        return gen, None, owner

    def _hold(self, state, records, work, gen, rotation=False, closing=False):
        """미확정 판정(PLAN 213) — 효과 의도 뒤 결과가 없으면 재실행하지 않는다.
        `rotation` = 구 실행자 종료·권한 회수 확인됨. `closing` = 지금 쓰는 것이 «결과 확정» 이라
        자기 효과 의도를 막지 않는다(DA R1)."""
        marked = self._field(state, "uncertain").get(work)
        if marked is not None:
            return dict(marked, marked=True)
        last_result = max([rec["seq"] for rec in records
                           if rec.get("work") == work and rec["kind"] == "result"] or [0])
        for rec in records:
            if rec.get("work") != work or rec["seq"] < last_result:
                continue
            if rec["kind"] == "effect" and not closing:
                return {"marked": False, "gen": rec.get("gen"), "reason": "효과 의도 뒤 결과 미확정"}
            if rec["kind"] == "start" and rec.get("gen") != gen and not rotation:
                return {"marked": False, "gen": rec.get("gen"), "reason": "착수 뒤 결과 미확정"}
        return None

    def _mark(self, state, records, work, holder, hold, confirm_by):
        at, gen = self.clock(), hold.get("gen")
        rec = record.build(self.team, self._seq(records), work, "%s#g%s" % (holder, gen), at,
                           hold.get("reason", ""), work, kind="uncertain", holder=holder, gen=gen,
                           extra={"confirm_by": confirm_by})
        marker = {"gen": gen, "holder": holder, "at": at, "confirm_by": confirm_by,
                  "reason": hold.get("reason", "")}
        rev = self._write(state, records, rec,
                          {"uncertain": dict(self._field(state, "uncertain"), **{work: marker})})
        self.on_step("after_uncertain")
        return Grant(HOLD, work, gen, holder, rev, True, "uncertain", confirm_by, marker["reason"])

    def _confirm_by(self):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() + 300))

    def _state_records(self):
        """journal 에만 내구화된 claim 세대를 유효본으로 되살린다(DA R2). revision 은 기록 수가 하한 —
        두 writer 를 통틀어 엄격 증가를 지킨다."""
        state, records = self.rs._state(), self.rs.records()
        return record.recover_state(state, records), records

    def _gen_matches(self, state, work, gen):
        return self._field(state, "generations").get(work) == gen

    def _write(self, state, records, rec, extra=None):
        """journal 내구화 → state checkpoint → revision 1 증가(입구와 같은 순서)."""
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        new_state = dict(state, revision=state["revision"] + 1)
        new_state.update(extra or {})
        self.rs._write_state(new_state)
        return new_state["revision"]

    def _seq(self, records):
        return (records[-1]["seq"] if records else 0) + 1

    def _field(self, state, name):
        return dict(state.get(name) or {})
