"""ft2 코어 실행권·세대 — claim · start · effect · result · uncertain (r1579 · PR② 둘째 장).

정본 PLAN §작업별 실행권(204·213행)만 담는다. 작업/효과 범위별 holder·gen(epoch)을 기록하고,
세대가 바뀐 뒤 옛 gen 의 쓰기는 «낡은 실행권» 으로 거절한다(쓰기 0 · revision 불변).
효과 «의도» 를 먼저 내구화하고, 의도만 기록된 작업은 «완료 유보»(UNCERTAIN)로 보존하며
재실행하지 않는다. 세대 교체(rotation)는 구 실행자 종료·권한 회수를 확인한 호출만 쓴다 —
확인 없이 다시 부르면 미확정이다(PLAN 213: 종료·회수를 확인하지 못하면 새 holder 도 같은
효과를 실행하지 않는다).
같은 팀 runtime 의 writer 는 모두 같은 팀 writer.lock 을 «비차단» 으로 잡는다. 점유 중이면
기다리지 않고 BUSY 다(팀별 잠금 · 팀 전역 잠금 0 · 입구 Intake.submit 과 같은 잠금).

결과 낱말은 record.RESULT_WORDS 8개 밖으로 나가지 않는다. 종류는 stage 로 구분한다:
실행권/기록 성공 = «접수 성공» · 결과 확정 = «회수 결과» · 미확정 = «완료 유보» ·
옛 세대 = «낡은 실행권» · 잠금 점유 = BUSY · 손상 = «복구 필요».
schema 는 1 그대로다(필드 추가만) — 확장 state 칸(generations·owners·uncertain)은
read_state_guarded 가 기본값 {} 로 채우므로 옛 state 도 읽히고 다른 writer 가 보존한다.
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


record = _load("record", "ft2_core_record")
intake = _load("intake", "ft2_core_intake")

OK, HOLD, STALE, BUSY = "접수 성공", "완료 유보", "낡은 실행권", "BUSY"
CORRUPT, REFUSED, RECOVERED = "복구 필요", "접수 거부", "회수 결과"
CONFIRM_SECONDS = 300
Grant = collections.namedtuple(
    "Grant", "result work gen holder revision written stage confirm_by reason",
    defaults=(None, None, None, None, False, None, None, ""))


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
                state, records = self.rs._state(), self.rs.records()
                gen = self._gens(state).get(work, 0) + 1
                hold = self._hold(state, records, work, gen, rotation)
                if hold is not None:
                    if hold.get("marked"):
                        return Grant(HOLD, work, hold.get("gen"), holder, state["revision"],
                                     False, "uncertain", hold.get("confirm_by"),
                                     "결과 미확정 = 재실행 0")
                    return self._mark(state, records, work, holder, hold, confirm_by or self._confirm_by())
                at = self.clock()
                owner = {"holder": holder, "gen": gen, "at": at, "rotation": bool(rotation)}
                rec = record.build(self.team, self._seq(records), work, "%s#g%d" % (holder, gen), at, "",
                                   work, kind="claim", holder=holder, gen=gen)
                rev = self._write(state, records, rec, {
                    "generations": dict(self._gens(state), **{work: gen}),
                    "owners": dict(self._owners(state), **{work: owner})})
                self.on_step("after_claim")
                return Grant(OK, work, gen, holder, rev, True, "claimed")
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(CORRUPT, work, holder=holder, reason=str(exc))

    def start(self, work, holder, gen):
        """착수 기록. 옛 세대면 «낡은 실행권» 이고 아무것도 쓰지 않는다."""
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
                state, records = self.rs._state(), self.rs.records()
                if not self._gen_matches(state, work, gen):
                    return Grant(STALE, work, gen, holder, state["revision"], False, "uncertain",
                                 reason="낡은 실행권 = 쓰기 0")
                hold = {"gen": gen, "reason": reason}
                return self._mark(state, records, work, holder, hold, confirm_by or self._confirm_by())
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(CORRUPT, work, gen, holder, reason=str(exc))

    def _step(self, work, holder, gen, kind, body, drop=False):
        """gen 대조 → 미확정 확인 → journal → state. 잠금은 쓰기 동안만 잡는다."""
        try:
            lock = self.rs._try_lock()
            if lock is None:
                return Grant(BUSY, work, gen, holder, reason="writer.lock 점유 = 기다리지 않는다")
            try:
                state, records = self.rs._state(), self.rs.records()
                if not self._gen_matches(state, work, gen):
                    return Grant(STALE, work, gen, holder, state["revision"], False, kind,
                                 reason="낡은 실행권 = 쓰기 0")
                hold = self._hold(state, records, work, gen)
                if hold is not None:
                    return Grant(HOLD, work, gen, holder, state["revision"], False, kind,
                                 hold.get("confirm_by"), "결과 미확정 = 재실행 0")
                rec = record.build(self.team, self._seq(records), work, "%s#g%d" % (holder, gen),
                                   self.clock(), body, work, kind=kind, holder=holder, gen=gen)
                extra = {}
                if drop:
                    extra = {"owners": {k: v for k, v in self._owners(state).items() if k != work},
                             "uncertain": {k: v for k, v in self._uncertain(state).items() if k != work}}
                rev = self._write(state, records, rec, extra)
                self.on_step("after_" + kind)
                return Grant(OK, work, gen, holder, rev, True, kind)
            finally:
                self.rs._unlock(lock)
        except intake.CorruptStateError as exc:
            return Grant(CORRUPT, work, gen, holder, reason=str(exc))

    def _hold(self, state, records, work, gen, rotation=False):
        """미확정 판정 — 같은 세대의 진행 기록은 «우리 진행», 다른 세대의 미완 기록은 crash 다."""
        marked = self._uncertain(state).get(work)
        if marked is not None:
            return dict(marked, marked=True)
        kinds = ("effect",) if rotation else ("start", "effect")
        last_result = max([rec["seq"] for rec in records
                           if rec.get("work") == work and rec["kind"] == "result"] or [0])
        for rec in records:
            if rec.get("work") == work and rec["seq"] > last_result and rec["kind"] in kinds \
                    and rec.get("gen") != gen:
                return {"marked": False, "gen": rec.get("gen"),
                        "reason": "착수·효과 의도 뒤 결과 미확정"}
        return None

    def _mark(self, state, records, work, holder, hold, confirm_by):
        at, gen = self.clock(), hold.get("gen")
        rec = record.build(self.team, self._seq(records), work, "%s#g%s" % (holder, gen), at,
                           hold.get("reason", ""), work, kind="uncertain", holder=holder, gen=gen)
        marker = {"gen": gen, "holder": holder, "at": at, "confirm_by": confirm_by,
                  "reason": hold.get("reason", "")}
        rev = self._write(state, records, rec, {"uncertain": dict(self._uncertain(state), **{work: marker})})
        self.on_step("after_uncertain")
        return Grant(HOLD, work, gen, holder, rev, True, "uncertain", confirm_by, marker["reason"])

    def _confirm_by(self):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() + CONFIRM_SECONDS))

    def _gen_matches(self, state, work, gen):
        return self._gens(state).get(work) == gen

    def _write(self, state, records, rec, extra=None):
        """journal 내구화 → state checkpoint → revision 1 증가(입구와 같은 순서)."""
        self.rs._append_journal(rec)
        new_state = dict(state, revision=state["revision"] + 1)
        new_state.update(extra or {})
        self.rs._write_state(new_state)
        return new_state["revision"]

    def _seq(self, records):
        return (records[-1]["seq"] if records else 0) + 1

    def _gens(self, state):
        return dict(state.get("generations") or {})

    def _owners(self, state):
        return dict(state.get("owners") or {})

    def _uncertain(self, state):
        return dict(state.get("uncertain") or {})
