"""ft2 코어 배정·전달·완료 재평가 — (r1581 · PR② 셋째 장).

정본 PLAN §병렬 배정(84·85·206행): «선행이 끝난 작업만 배정 · 배정과 전달 의도를 한 번에 내구화 ·
crash 뒤 같은 attempt 재전달 · 수신 실행 1회 억제 · 완료 뒤 재평가·반환·owner 복구». 원자 경계
(DA R1 · 나노 임의 선택 0) = 팀별 writer.lock «비차단» 1회(점유 중 = BUSY · 쓰기 0) 안에서 state·
journal 을 다시 읽어 선행 all-of 와 공유 자원 예약을 판정하고, 세대는 실행권의 `_claim_plan` 과
«같은» 함수로 정한다. 잠금 안에서 공개 `Execution.claim`·`Intake.submit` 을 부르지 않는다(재획득 =
BUSY). 전달 = deliver 1줄 · 완료 = complete 1줄(완료 + 재평가 표식) + reassess 1줄(재평가·반환·owner
복구). 복구는 «전달 의도» 와 «표식 있는 complete» 만 훑는다(전체 훑기 0 · 예약 없는 완료는 D7 로 제외).
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


record, intake, execution = (_load("record", "ft2_core_record"), _load("intake", "ft2_core_intake"),
                             _load("execution", "ft2_core_execution"))
OK, HOLD, REFUSED, BUSY, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "BUSY", "복구 필요"
Grant = collections.namedtuple("Grant", "result work stage attempt gen holder revision written released reason",
                               defaults=(None,) * 7 + (False, "", ""))


class Dispatch:
    CLIENT, REQUIRED_EVIDENCE = intake.Intake, ("v1", "v2")

    def __init__(self, root, team, clock=None, on_step=None, execution_cls=None):
        self.team, self.on_step = team, on_step or (lambda step: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.ex = (execution_cls or execution.Execution)(root, team, clock=self.clock, on_step=self.on_step)
        self.rs = self.ex.rs

    def assign(self, work, holder, pre=(), evidence=(), resources=(), rotation=False, gate="all-of"):
        return self._locked(self._assign, work, holder, pre, evidence, resources, rotation)

    def deliver(self, work, attempt=None, mode="intent"):
        """전달 1줄 — `intent` = 의도가 pending 인 같은 attempt · `scan` = 같은 attempt 재전달(재시도)."""
        return self._locked(self._deliver, work, attempt, mode)

    def complete(self, work, attempt=None):
        return self._locked(self._complete, work, attempt, k=2)

    def reassess(self, work, mode="marker"):
        """반환·owner 복구 = 재평가 1줄. 미확정(UNCERTAIN) 작업의 반환은 «접수 거부» 다(ⓐ)."""
        return self._locked(self._reassess, work, mode)

    def recover(self, mode="marker"):
        """crash 복구 1잠금 — 배정 줄로 예약·전달 의도를 되살려 같은 attempt 로 전달하고, 표식 있는
        complete 중 재평가 없는 것만 재평가한다(전체 훑기 0)."""
        return self._locked(self._recover, None, mode, k=self._recover_k(),
                            empty={"delivered": [], "reassessed": [], "reason": "writer.lock 점유/복구 필요"})

    def _recover(self, context, _work, mode):
        """전달 의도와 표식 있는 complete 만 — 예약·완료·재평가는 잠금 안 판독(recover_state)이 겹쳐 읽는다."""
        state, records = context
        intents = dict.fromkeys(rec["work"] for rec in records if rec["kind"] == "dispatch")
        delivered = [g for g in (self._deliver(self.ex._state_records(), work, None, "intent")
                                 for work in intents) if g.written]
        reassessed = [work for work in self._pending_reassess(state)
                      if self._reassess(self.ex._state_records(), work, mode).written]
        return {"delivered": [g.attempt for g in delivered], "reassessed": reassessed}

    def _recover_k(self):
        """recover 1호출의 append 상한 = 전달 의도 남은 work 수 + 재평가 남은 work 수(DA R2-①)."""
        try:
            state, records = self.ex._state_records()
        except ValueError:
            return 1                                  # 잠금 안 판독이 같은 오류를 다시 낸다
        return len({rec["work"] for rec in records if rec["kind"] == "dispatch"}) + len(self._pending_reassess(state))

    def _locked(self, body, work, *args, k=1, empty=None):
        lock, word, reason = self.rs._try_lock(), BUSY, "writer.lock 점유 = 기다리지 않는다"
        written = False
        try:
            if lock is not None:
                self.rs.journal.reserve(k)                  # DA R2-①: 첫 쓰기 전 호출 단위 합산 예약
                out = body(self.ex._state_records(), work, *args)
                return out if empty is None else dict(out, result=OK)   # R2-③: 기존 칸 + result
        except ValueError as exc:      # 모듈 사본(_load)마다 클래스가 달라 낱말 칸으로 가른다
            word, reason = getattr(exc, "word", CORRUPT), str(exc)
            written = getattr(exc, "written", False)
        finally:
            if lock is not None:
                self.rs._unlock(lock)
        if empty is not None:
            return dict(empty, result=word, reason=reason)
        return Grant(word, work, reason=reason, written=written)

    def _assign(self, context, work, holder, pre, evidence, resources, rotation):
        state, records = context
        reason = self._eligible(state, work, pre, evidence, resources)
        if not reason and not self._accepted(records, work):        # r1616: 접수 영수 없는 일은 배정 0
            reason = "영수-없음"
        if reason:
            return Grant(REFUSED, work, "reject", reason=reason)
        gen, hold, owner = self.ex._claim_plan(state, records, work, holder, rotation)
        if hold is not None:
            return Grant(HOLD, work, "uncertain", gen=hold.get("gen"), holder=holder,
                         revision=state["revision"], reason=hold.get("reason", "결과 미확정 = 배정 0"))
        attempt = "a%d" % (len([r for r in records if r["kind"] == "dispatch" and r.get("work") == work]) + 1)
        rec = record.build(self.team, (records[-1]["seq"] if records else 0) + 1, work, attempt, owner["at"], work, work,
                           kind="dispatch", holder=holder, gen=gen,
                           extra={"resources": list(resources), "pre": list(pre), "intent": {"attempt": attempt,
                                                                                            "state": "pending"}})
        rev = self._write(state, records, rec, {
            "generations": {work: gen}, "owners": {work: owner},
            "reservations": {res: {"work": work, "attempt": attempt} for res in resources}})
        self.on_step("after_dispatch")
        return Grant(OK, work, "dispatched", attempt, gen, holder, rev, True)

    def _deliver(self, context, work, attempt=None, mode="intent"):
        state, records = context
        intent = self._intent(records, work)
        attempt = attempt or intent.get("attempt")
        if mode == "intent" and (intent.get("state") != "pending" or attempt != intent.get("attempt")):
            return Grant(HOLD, work, "no-intent", attempt, revision=state["revision"],
                         reason="전달 의도 없음 = 전달 0(이미 전달됐거나 미기록)")
        if not attempt:
            return Grant(REFUSED, work, "deliver", reason="전달할 attempt 없음")
        rec = record.build(self.team, (records[-1]["seq"] if records else 0) + 1, work, attempt, self.clock(), work, work,
                           kind="deliver", holder=intent.get("holder"), gen=intent.get("gen"),
                           extra={"mode": mode})
        sent = list((state.get("deliveries") or {}).get(work) or [])
        rev = self._write(state, records, rec, {"deliveries": {work: sent + [attempt]}})
        return Grant(OK, work, "delivered", attempt, intent.get("gen"), intent.get("holder"), rev, True)

    def _complete(self, context, work, attempt):
        state, records = context
        if work in (state.get("uncertain") or {}):     # r1624: 미확정 = 완료 유보(쓰기 0 · 계약 case07)
            return Grant(HOLD, work, "uncertain", attempt, revision=state["revision"],
                         reason="결과 미확정 = 완료 유보")
        if work in (state.get("done") or {}):
            return Grant(HOLD, work, "complete", attempt, revision=state["revision"], reason="이미 완료 기록")
        owner, assigned = dict((state.get("owners") or {}).get(work) or {}), self._assigned(records, work)
        if owner and not assigned:
            return Grant(REFUSED, work, "complete", revision=state["revision"],
                         reason="배정 계보 없는 실행권 owner = 완료 거절(쓰기 0)")
        marker, at = ("required" if assigned else ""), self.clock()
        rec = record.build(self.team, (records[-1]["seq"] if records else 0) + 1, work, attempt or "arranged", at, work, work,
                           kind="complete", holder=owner.get("holder"), gen=owner.get("gen"),
                           extra={"marker": marker, "after": attempt})
        rev = self._write(state, records, rec, {"done": {work: {"attempt": attempt, "at": at, "marker": marker}}})
        self.on_step("after_complete")
        grant = self._reassess(self.ex._state_records(), work, "contract") if marker else None
        return Grant(OK, work, "complete", attempt, owner.get("gen"), owner.get("holder"),
                     grant.revision if grant else rev, True, grant.released if grant else "")

    def _reassess(self, context, work, mode="marker"):
        state, records = context
        if work in (state.get("uncertain") or {}):
            return Grant(REFUSED, work, "reassess", revision=state["revision"], reason="미확정 반환 거부")
        done = dict((state.get("done") or {}).get(work) or {})
        if work in (state.get("reassess_done") or {}):
            return Grant(HOLD, work, "reassess", revision=state["revision"], reason="이미 재평가 = 멱등")
        if done.get("marker") != "required":
            return Grant(REFUSED, work, "reassess", revision=state["revision"], reason="재평가 표식 없음")
        kept, owners = (state.get("reservations") or {}), dict(state.get("owners") or {})
        owner, held = dict(owners.get(work) or {}), [res for res, row in kept.items() if row.get("work") == work]
        rec = record.build(self.team, (records[-1]["seq"] if records else 0) + 1, work, done.get("attempt") or "arranged",
                           self.clock(), work, work, kind="reassess", holder=owner.get("holder"),
                           gen=owner.get("gen"), extra={"after": done.get("attempt"), "mode": mode,
                                                        "released": held, "owner_recovered": bool(owner)})
        drops = {"owners": {k: v for k, v in owners.items() if k != work},
                 "reservations": {k: v for k, v in kept.items() if v.get("work") != work}}
        rev = self._write(state, records, rec, {
            "reassess_done": {work: {"after": done.get("attempt"), "mode": mode}},
            "released": {work: {"res": held, "count": len(held)}},
            "owners_recovered": {work: {"owner": owner.get("holder"), "attempt": done.get("attempt")}}},
            replace=drops)
        return Grant(OK, work, "reassess", done.get("attempt"), owner.get("gen"), owner.get("holder"),
                     rev, True, held)

    def _eligible(self, state, work, pre, evidence, resources=()):
        """계약 = all-of · 증거 충족 · 공유 자원 빔(팀 마감 «잔여 0» 은 증거가 아니다 · ⓑ · 잠금 안 판독)."""
        done, taken = (state.get("done") or {}), (state.get("reservations") or {})
        if work in done or work in (state.get("uncertain") or {}):
            return "state-완료" if work in done else "uncertain"
        if not all(name in done for name in pre):
            return "pre-all"
        if not set(self.REQUIRED_EVIDENCE) <= set(evidence):
            return "ver-all"
        return "resource" if [res for res in resources if res in taken] else ""

    def _accepted(self, records, work):
        """접수 영수 = 같은 work 를 남긴 accept 줄(`intake.submit(command, body, work)`) — 없으면 배정 0(r1616)."""
        return any(rec["kind"] == "accept" and rec.get("work") == work for rec in records)

    def _assigned(self, records, work):
        """배정 계보 = journal 의 dispatch 줄(자원 목록이 비어도 «배정» 이다 · 다른 실행권 owner 와 구별)."""
        return any(rec["kind"] == "dispatch" and rec.get("work") == work for rec in records)

    def _intent(self, records, work):
        out = {}
        for rec in [rec for rec in records if rec.get("work") == work]:
            if rec["kind"] == "dispatch":
                out = dict(rec.get("intent") or {}, gen=rec.get("gen"), holder=rec.get("holder"))
            elif rec["kind"] == "deliver" and out.get("attempt") == rec.get("attempt"):
                out = dict(out, state="delivered")
        return out

    def _pending_reassess(self, state):
        """표식 있는 complete 중 재평가 없는 것만 — 예약 없는 완료는 대상이 아니다(D7 · M6)."""
        return [work for work, row in (state.get("done") or {}).items()
                if row.get("marker") == "required" and work not in (state.get("reassess_done") or {})]

    def _write(self, state, records, rec, extra=None, replace=None):
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        self.on_step("after_%s_journal" % rec["kind"])
        new_state = {**state, "revision": state["revision"] + 1, **(replace or {})}
        for name, value in (extra or {}).items():
            new_state[name] = {**(state.get(name) or {}), **value}
        self.rs._write_state(new_state)
        self.on_step("after_state")
        return new_state["revision"]

