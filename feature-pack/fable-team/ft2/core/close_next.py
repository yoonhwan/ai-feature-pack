"""ft2 닫기 영수 → 다음 발주·다음 카드 (카드 r1725 · 계획 PLAN-ft20-master-close-receipt-next-dispatch-20261112 · R1·보정 2).
나노 닫기 영수(실제 부재 = 주입 probe) «그 사건» 에서 대기 work 1개를 배정(dispatch)·같은 attempt 전달(deliver)한다 ·
주기 호출 0 · spawn·tmux·kill = 호출자. dispatch.py 불변 — 그 1잠금(`_locked` · k=3) 안에서 `_assign`·`_deliver` 를 그대로
부른다. 영수 상태·영수 키 done(`close:<팀>:<event>` · 보정 2) = `record.recover_state` 한 곳. 재접수 = R1 3갈래(영수만 →
배정·전달 · 배정만 → 같은 attempt 전달만 · 전달 완료 → 쓰기 0). 켜기 = 표식 CLOSE-NEXT.enabled(dry-run 통과 때만).
arch·DA 완료 = TeamRecord 1판 · close_request=false. 회수 후보 = r1561 ⓖ 4조건 읽기. 결과 낱말 = 계약 8낱말 안만.
"""
import collections
import importlib.util
import json
import os
import time

_SPEC = importlib.util.spec_from_file_location("ft2_core_dispatch", os.path.join(os.path.dirname(
    os.path.abspath(__file__)), "dispatch.py"))
dispatch = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(dispatch)
record, team_record = dispatch.record, dispatch._load("team_record", "ft2_core_team_record")   # 같은 폴더 로더
OK, HOLD, REFUSED, BUSY, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "BUSY", "복구 필요"
NONE_NEXT, ROLES = "[다음 없음]", ("arch", "da")
FACTS = ("산출 완료", "원격 보존", "팀장 인수", "남은 일 팀장 몫")      # r1561 ⓖ 회수 후보 4조건
Close = collections.namedtuple("Close", "result next attempt holder close_request candidate written revision reason",
                               defaults=(None,) * 5 + (False, None, ""))


class CloseNext:
    """팀 1곳의 닫기 영수 처리. 잠금·판독·쓰기는 품은 Dispatch(→ Execution → Intake)와 같은 것을 쓴다."""

    def __init__(self, root, team, clock=None, on_step=None, probe=None, dispatch_cls=None):
        self.root, self.team, self.probe = os.path.abspath(root), team, probe
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step = on_step or (lambda step: None)
        self.d = (dispatch_cls or dispatch.Dispatch)(root, team, clock=self.clock, on_step=self.on_step)
        self.rs = self.d.rs
        self.marker = os.path.join(self.root, ".fable-team", "teams", team, "CLOSE-NEXT.enabled")

    def receipt(self, seat, gen, work, event, next_holder, evidence, next_work=None, pre=(), resources=()):
        """닫기 영수 1건 → 다음 카드 배정 + 다음 세션 전달(1잠금). 출력 next = 배정한 work 또는 «[다음 없음]»."""
        problem = self._problem(seat, gen, work, event, next_holder)
        if problem:
            return Close(REFUSED, reason=problem)
        out = self.d._locked(self._receipt, work, seat, gen, event, next_holder, tuple(evidence), next_work,
                             tuple(pre), tuple(resources), k=3)
        return out if isinstance(out, Close) else Close(out.result, written=out.written, reason=out.reason)

    def seat_done(self, seat, expect, fields_file):
        """arch·DA 완료 = 팀 기록 1판 + «완료» 1줄 · 닫기 요청 0. 다른 역할 = 접수 거부(나노 = 닫기 영수)."""
        if self._role(seat) not in ROLES:
            return Close(REFUSED, close_request=False, reason="완료 줄 경로 아님(나노 = 닫기 영수): %r" % (seat,))
        out = team_record.TeamRecord(self.root, self.team, clock=self.clock, on_step=self.on_step).write(
            seat, expect, fields_file)
        return Close(out.result, close_request=False, written=out.written, revision=out.revision, reason=out.reason)

    def candidates(self, facts_file):
        """좌석마다 ⓖ 4조건 → candidate · 빠진 조건 이름. 읽기만(state·owner 쓰기 0 · 카드 owner = 팀장 유지)."""
        facts, problem = self._facts(facts_file)
        if problem:
            return Close(REFUSED, reason=problem)
        missing = {seat: [name for name in FACTS if not (isinstance(row, dict) and row.get(name) is True)]
                   for seat, row in facts.items()}
        return Close(OK, candidate={seat: {"candidate": not names, "missing": names} for seat, names in missing.items()})

    def enable(self, seats_file):
        """켜기 전 dry-run — 지금 좌석 전부로 candidates 1회 · 후보 중 일하는 좌석이 있으면 켜지 않는다(표식 0)."""
        found = self.candidates(seats_file)
        if found.result != OK:
            return found
        facts = self._facts(seats_file)[0]
        try:
            owners = self.d.ex._state_records()[0].get("owners") or {}
        except ValueError as exc:
            return Close(getattr(exc, "word", CORRUPT), reason=str(exc))
        holders = {row.get("holder") for row in owners.values()}
        looks = {seat: self._working(seat, facts[seat], holders)
                 for seat, row in found.candidate.items() if row["candidate"]}
        unknown, busy = sorted(s for s, v in looks.items() if v is None), sorted(s for s, v in looks.items() if v)
        if unknown:
            return Close(HOLD, candidate=found.candidate, reason="판정 불가 · 생존 판독 실패 %s = 표식 0" % " ".join(unknown))
        if busy:
            return Close(REFUSED, candidate=found.candidate, reason="켜기 거절 · 일하는 좌석 " + " ".join(busy))
        self._mark()
        return Close(OK, candidate=found.candidate, written=True, reason="켜기 표식 " + self.marker)

    def _receipt(self, context, work, seat, gen, event, holder, evidence, next_work, pre, resources):
        state, records = context
        if not os.path.exists(self.marker):
            return Close(HOLD, reason="켜기 전(dry-run 미통과) = 쓰기 0")
        seen = (state.get("close_receipts") or {}).get(event)
        if seen is not None:
            return self._resume(state, records, event, seen, (evidence, pre, resources))
        refused = self._absent(seat)
        if refused:
            return Close(refused[0], reason=refused[1])
        nxt, problem = self._pick_next(state, records, next_work, evidence, pre, resources)
        if problem:
            return Close(REFUSED, reason=problem)
        rec = record.build(self.team, self._seq(state, records), "close:" + event, event, self.clock(), seat,
                           "close:%s:%s" % (self.team, event), kind="close_receipt", holder=holder, gen=gen,
                           extra={"event": event, "seat": seat, "next": nxt, "closed_work": work})
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        self.on_step("after_close_receipt_journal")
        new = record.recover_state(state, records + [rec])
        self.rs._write_state(dict(new, revision=max(new["revision"], state["revision"] + 1)))
        self.on_step("after_state")
        return self._chain(nxt, holder, evidence, pre, resources)

    def _resume(self, state, records, event, seen, args):
        """R1 3갈래 — probe 는 다시 부르지 않는다(부재는 영수 줄에 이미 내구화됨). 전달 완료 = 영수 키 done
        (recover_state 가 세움 · 회수로 배정·전달 줄이 base 로 접혀도 남는다 · 보정 2)."""
        nxt = seen.get("next")
        delivered = "close:%s:%s" % (self.team, event) in (state.get("done") or {})
        intent = {"state": "delivered"} if delivered or not nxt else self.d._intent(records, nxt)
        if not intent:                                          # 영수만 — 배정·전달을 잇는다
            return self._chain(nxt, seen.get("holder"), *args)
        if intent.get("state") == "pending":                    # 배정만 — 같은 attempt 전달만(새 배정 0)
            return self._grant(self.d._deliver(self.d.ex._state_records(), nxt, intent.get("attempt"), "intent"), nxt)
        return Close(HOLD, nxt or NONE_NEXT, reason="재접수 — 같은 사건 = 쓰기 0")

    def _chain(self, nxt, holder, evidence, pre, resources):
        if nxt is None:
            return Close(OK, NONE_NEXT, written=True, reason="발주 0")
        grant = self.d._assign(self.d.ex._state_records(), nxt, holder, pre, evidence, resources, False)
        if grant.result != OK:
            return self._grant(grant, nxt)
        return self._grant(self.d._deliver(self.d.ex._state_records(), nxt, grant.attempt, "intent"), nxt)

    def _grant(self, grant, nxt):
        return Close(grant.result, nxt, grant.attempt, grant.holder, written=grant.written,
                     revision=grant.revision, reason=grant.reason)

    def _absent(self, seat):
        """실제 부재 확인 — 닫기 도구 rc0 만으로는 부재가 아니다(A2). 판독 실패 = 판정 불가 1줄(하드 룰 20)."""
        try:
            seen = self.probe(seat) if self.probe else "판독기 없음"
        except Exception as exc:                                # 판독기는 호출자 것 — 어떤 실패도 쓰기 0
            return HOLD, "판정 불가 · %s" % exc
        if seen == "absent":
            return None
        if seen == "alive":
            return REFUSED, "부재 확인 없음"
        return HOLD, "판정 불가 · %s" % seen

    def _pick_next(self, state, records, next_work, evidence, pre, resources):
        """대기 카드 = accept 줄 있고 dispatch 줄 없는 work · accept seq 순 · 첫 «배정 가능»(Dispatch._eligible).
        카드 = 문자열 work 만 · Slack 접수 accept 의 dict work(route·slack payload)는 대기 카드가 아니다(r1881)."""
        waiting = list(dict.fromkeys(rec["work"] for rec in records if rec["kind"] == "accept" and rec.get("work")
                                     and isinstance(rec["work"], str)
                                     and not self.d._assigned(records, rec["work"])))
        if next_work is not None:
            why = "대기 카드 아님" if next_work not in waiting else self.d._eligible(state, next_work, pre, evidence,
                                                                               resources)
            return (None, "배정 불가 %s: %r" % (why, next_work)) if why else (next_work, "")
        ready = [work for work in waiting if not self.d._eligible(state, work, pre, evidence, resources)]
        return (ready[0] if ready else None), ""

    def _working(self, seat, row, holders):
        """일하는 좌석 = owner holder 또는 (probe = alive ∧ 진행 work 있음) · 판독 실패 = None(판정 불가)."""
        if seat in holders:
            return True
        if not (isinstance(row, dict) and row.get("진행 work")) or self.probe is None:
            return False
        try:
            return {"alive": True, "absent": False}.get(self.probe(seat))
        except Exception:                                       # 판독기는 호출자 것
            return None

    def _problem(self, seat, gen, work, event, holder):
        if isinstance(gen, bool) or not isinstance(gen, int) or gen < 1:
            return "세대는 1 이상 정수: %r" % (gen,)
        for name, value in (("seat", seat), ("work", work), ("event", event), ("next_holder", holder)):
            if not isinstance(value, str) or not value.strip():
                return "%s 빈 값: %r" % (name, value)
        return ""

    def _role(self, seat):
        head = "byz-%s-" % self.team
        return seat[len(head):].split("-")[0] if isinstance(seat, str) and seat.startswith(head) else ""

    def _seq(self, state, records):
        return (records[-1]["seq"] if records else (state.get("journal_base") or {}).get("upto", 0)) + 1

    def _facts(self, source):
        if isinstance(source, dict):
            return source, ""
        try:
            with open(source, encoding="utf-8") as handle:
                facts = json.load(handle)
        except (OSError, ValueError, TypeError) as exc:
            return None, "판정 불가 · 좌석 사실 판독 불가: %s" % exc
        return (facts, "") if isinstance(facts, dict) else (None, "판정 불가 · 좌석 사실은 JSON 객체 1개")

    def _mark(self):
        """표식 원자 쓰기(임시 → fsync → rename)."""
        os.makedirs(os.path.dirname(self.marker), exist_ok=True)
        tmp = "%s.tmp.%d" % (self.marker, os.getpid())
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write("enabled %s\n" % self.clock())
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, self.marker)
