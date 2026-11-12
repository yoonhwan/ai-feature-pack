"""ft2 재개 사건 1건 → 팀장 1번만 열기 (카드 r1727 · 계획 PLAN-ft20-team-reopen-from-record-20261112 · R1·R2 보정).

재개 키 = `<휴면 revision R>|<재개 사건 id>`. «연다» = 팀장 개설 의도 1줄(reopen · phase=intent)을 내구화하고 팀장
좌석 이름을 돌려주는 것이다. 실제 spawn·tmux 는 호출자 몫이고 코어는 같은 키로 의도를 두 번 만들지 않는다.
lifecycle.py 는 고치지 않는다 — Lifecycle 을 품고 그 writer.lock 비차단 1회(`_locked`) 안에서만 쓴다(잠금 안 공개
메서드 0). R 대조 = r1723 `TeamRecord.read()` 의 `휴면 revision` 칸 + 휴면 3단계 영수 줄 «R=…»(A7 · 셋 같음만 진행 ·
못 읽음 = 판정 불가 · 쓰기 0). 큐 행은 dispatch 줄 있는 work 에 `dispatched` 표시(필요한 좌석에서 뺀다 · 중복 배정 0).
같은 키 재접수(R1) = 현재 R 대조 → booted 면 재접수 → intent 면 probe 가 명시적 absent 일 때만 같은 이름으로 다시 연다.
단일 재생 = `record._fold_reopen` 하나(intent 가 휴면 표식 + 단계 영수 4키를 풀고 lifted 에 남김 · booted = done).
부팅 보고 = 같은 동사의 ack 1번만. 필요한 좌석 = 열린 work 목록(역할 결정 = 팀장). cron·클론·자동 재개설 0.
결과 낱말 = contracts/core 8낱말 안만(새 낱말 0).
"""
import collections
import importlib.util
import os
import time

_SPEC = importlib.util.spec_from_file_location("ft2_core_lifecycle", os.path.join(os.path.dirname(
    os.path.abspath(__file__)), "lifecycle.py"))
lifecycle = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(lifecycle)
record, team_record = lifecycle.record, lifecycle._load("team_record", "ft2_core_team_record")   # 같은 폴더 로더
OK, HOLD, REFUSED = "접수 성공", "완료 유보", "접수 거부"
Out = collections.namedtuple("Out", "result lead open phase load seats_needed written revision reason",
                             defaults=(None, False, None, None, None, False, None, ""))


class Reopen:
    """팀 1곳의 재개. 잠금·판독·쓰기는 품은 Lifecycle(→ Intake)과 같은 것을 쓴다."""

    def __init__(self, root, team, clock=None, on_step=None, probe=None, lifecycle_cls=None, record_cls=None):
        self.root, self.team, self.probe = os.path.abspath(root), team, probe
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.on_step = on_step or (lambda step: None)
        self.lc = (lifecycle_cls or lifecycle.Lifecycle)(root, team, clock=self.clock, on_step=self.on_step)
        self.rs, self.record_cls = self.lc.rs, record_cls or team_record.TeamRecord

    def reopen(self, revision, event, lead, ack=None):
        """재개 1건(ack 없음) 또는 부팅 보고 1건(ack 있음). 출력 open = 호출자가 팀장을 열어야 하는가."""
        problem = self._problem(revision, event, lead, ack)
        if problem:
            return Out(REFUSED, reason=problem)
        return self.lc._locked(self._reopen, Out(HOLD), revision, event, lead, ack)

    def _reopen(self, context, revision, event, lead, ack):
        state, records = context
        key = "%s|%s" % (revision, event)
        row = (state.get("reopens") or {}).get(key)
        if ack is not None:
            return self._boot(state, records, key, row, ack)
        if row is not None:
            return self._again(state, records, row, revision)
        if self.lc._dormant_key() not in (state.get("done") or {}):   # 다른 키로 팀장 2번째 개설 0
            return Out(HOLD, reason="휴면 아님 = 쓰기 0")
        stale = self._current(revision, records)
        if stale:
            return stale
        new, records = self._write(state, records, key, {"revision": revision, "event": event, "lead": lead,
                                                         "phase": "intent"})
        return self._opened(new, records, lead, True, "")

    def _again(self, state, records, row, revision):
        """같은 키 재접수(R1) — 쓰기 0 · 저장된 lead 유지(새 이름 0)."""
        stale = self._current(revision, records)   # 저장 키도 현재 R 대조(3단계와 같은 판독)
        if stale:
            return stale._replace(lead=row["lead"])
        if row["phase"] == "booted":
            return Out(HOLD, row["lead"], False, "booted", reason="재접수 — 부팅 보고 받음 = 쓰기 0")
        seen = self._look(row["lead"])
        if seen == "absent":
            return self._opened(state, records, row["lead"], False, "재접수 — 팀장 부재 = 같은 이름으로 다시 연다")
        reason = "재접수 — 팀장 살아 있음 = 쓰기 0" if seen == "alive" else "판정 불가 · %s = 쓰기 0" % seen
        return Out(HOLD, row["lead"], False, "intent", reason=reason)

    def _boot(self, state, records, key, row, ack):
        """부팅 보고 1통 — 키가 있고 phase = intent 일 때만 booted 1줄 · 같은 ack 두 번 = 쓰기 0."""
        if row is None:
            return Out(REFUSED, reason="재개 키 없음 = 부팅 보고 0: %s" % key)
        if row["phase"] != "intent":
            return Out(HOLD, row["lead"], False, row["phase"], reason="재접수 — 부팅 보고 이미 받음 = 쓰기 0")
        new, _records = self._write(state, records, key, {"lead": row["lead"], "phase": "booted", "ack": ack})
        return Out(OK, row["lead"], False, "booted", written=True, revision=new["revision"])

    def _current(self, revision, records):
        """A7 — 팀 기록 `휴면 revision` · 휴면 영수 R · 키의 R 셋이 같아야 진행. 다름 = 낡은 재개(접수 거부) ·
        팀 기록 못 읽음 또는 영수 줄 없음(회수로 사라짐 포함) = 판정 불가(하드 룰 20) · 어느 쪽도 쓰기 0."""
        out = self.record_cls(self.root, self.team).read()
        if out.result != OK:
            return Out(HOLD, reason="판정 불가 · %s" % out.reason)
        current = (out.fields or {}).get("휴면 revision", "")
        if current.strip() != str(revision):
            return Out(REFUSED, reason="낡은 재개 R=%s ≠ 팀 기록 휴면 revision %s = 쓰기 0" % (revision, current))
        receipt = self._receipt_r(records)
        if receipt is None:
            return Out(HOLD, reason="판정 불가 · 휴면 영수(team-record) 줄 없음 = 쓰기 0")
        if receipt != str(revision):
            return Out(REFUSED, reason="휴면 영수 R=%s ≠ 팀 기록·키 R=%s = 쓰기 0" % (receipt, revision))
        return None

    def _receipt_r(self, records):
        """휴면 3단계 영수의 R — 같은 잠금 안 journal 의 마지막 team-record close 줄 본문 «R=…» · 없음 = None."""
        key = self.lc._step_key("team-record")
        bodies = [rec.get("body") or "" for rec in records if rec["kind"] == "close" and rec.get("work") == key]
        words = [word[2:] for word in (bodies[-1].split() if bodies else ()) if word.startswith("R=")]
        return words[0] if words else None

    def _look(self, lead):
        """팀장 생존 판독 — 판독기는 호출자 것 · 어떤 실패도 부재가 아니다."""
        try:
            return self.probe(lead) if self.probe else "판독기 없음"
        except Exception as exc:
            return "판독 실패 %s" % exc

    def _write(self, state, records, key, extra):
        seq = (records[-1]["seq"] if records else (state.get("journal_base") or {}).get("upto", 0)) + 1
        rec = record.build(self.team, seq, "reopen:" + key, extra["phase"], self.clock(), extra["lead"],
                           "goal:reopen:%s:%s" % (self.team, key), kind="reopen", extra=dict(extra, key=key))
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        self.on_step("after_reopen_journal")
        new = record.recover_state(state, records + [rec])
        new = dict(new, revision=max(new["revision"], state["revision"] + 1))
        self.rs._write_state(new)
        self.on_step("after_state")
        return new, records + [rec]

    def _opened(self, state, records, lead, written, reason):
        load = self._load_list(state, records)
        return Out(OK, lead, True, "intent", load, load["open_work"], written, state["revision"], reason)

    def _load_list(self, state, records):
        """탑재 목록(읽기) — 팀 기록 칸 전부 · HANDOFF·LESSONS 경로 · 열린 일 · 휴면 중 쌓인 큐(command 1행).
        큐 = journal accept 줄 + state 접수 장부 두 곳을 command 로 묶는다(같은 요청 = 같은 행)."""
        fields = self.record_cls(self.root, self.team).read().fields or {}
        works = {rec["command"]: rec.get("work") for rec in records if rec["kind"] == "accept"}
        rows = [rec["command"] for rec in records if rec["kind"] == "accept"] + list(state.get("pending") or [])
        left = set(record.remaining(state, records))
        sent = {rec.get("work") for rec in records if rec["kind"] == "dispatch" and rec.get("work")}
        queue = [{"command": command, "work": works.get(command), "dispatched": works.get(command) in sent}
                 for command in dict.fromkeys(rows) if command in left]   # 배정된 work = 표시(다시 배정 0)
        open_work = list(dict.fromkeys(row["work"] or row["command"] for row in queue if not row["dispatched"]))
        return {"record": fields, "HANDOFF": fields.get("HANDOFF"), "LESSONS": fields.get("LESSONS"),
                "open_work": open_work, "queue": queue}

    def _problem(self, revision, event, lead, ack):
        if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
            return "휴면 revision 은 0 이상 정수: %r" % (revision,)
        for name, value in (("event", event), ("lead", lead)) + ((("ack", ack),) if ack is not None else ()):
            if not isinstance(value, str) or not value.strip() or "|" in value:
                return "%s 빈 값 또는 «|» 포함: %r" % (name, value)
        return ""
