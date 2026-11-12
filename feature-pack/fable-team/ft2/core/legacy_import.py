"""ft2 1.x→2.0 가져오기 쓰는 모듈 (카드 r1774 · DESIGN legacy-import-r1774 §1~§3 · 보정 1 R1~R3).

import 줄 1개 = 1.x «옮김» 행 1개다(work=None · holder=None). 용량 장부(remaining)·투영 가용 좌석에 안 잡힌다.
한 행 = Lifecycle writer.lock 비차단 1회(`_locked(k=0)`). body 순서(R2): ① 잠금 안 판독값으로 멱등·겹침 판정(쓰기 0)
② 이미 가져옴·겹침이면 그대로 돌아간다 ③ 새 키일 때만 `journal.reserve(1)` ④ append → recover_state → write_state.
겹침(R3) = 남은 accept 줄과 회수된 영수(journal_base.receipts)를 함께 본다. 기존 줄·영수·state 칸은 바꾸지 않는다.
결과 = 기존 ∪ 가져옴(카드 계약 6). 결과 낱말 = contracts/core 8낱말 안만(새 낱말 0).
"""
import collections
import importlib.util
import os
import time

_SPEC = importlib.util.spec_from_file_location("ft2_core_lifecycle", os.path.join(os.path.dirname(
    os.path.abspath(__file__)), "lifecycle.py"))
lifecycle = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(lifecycle)
record, intake = lifecycle.record, lifecycle.intake
journal = intake.journal
OK, HOLD, REFUSED, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "복구 필요"
IMPORTED, ALREADY, OVERLAP, UNKNOWN = "가져옴", "이미 가져옴", "겹침", "판정 불가"
CARD_FIELDS = ("pending", "attempts", "generations", "owners", "deliveries", "done")
Out = collections.namedtuple("Out", "result key status written revision reason",
                             defaults=(None, None, False, None, ""))


def runtime_of(root, team):
    return os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "runtime")


def build_line(team, seq, at, row):
    """import 줄 1개(schema 1 · 필드 추가만). row = {key, body(held 상대 경로), src, sha256, bytes}."""
    return record.build(team, seq, "import", "import", at, row["body"], kind="import",
                        extra={"key": row["key"], "src": row["src"], "sha256": row["sha256"], "bytes": row["bytes"]})


class LegacyImport:
    """팀 runtime 1곳에 import 줄을 더한다. runtime 이 없으면 만들지 않는다(복구 필요)."""

    def __init__(self, root, team, clock=None, on_step=None, caps=None):
        self.team, self.on_step = team, on_step or (lambda step: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.runtime = runtime_of(root, team)
        self.lc = None
        if os.path.isfile(os.path.join(self.runtime, "state.json")):
            self.lc = lifecycle.Lifecycle(root, team, clock=self.clock, on_step=self.on_step)
            if caps:                                    # 시험용 총량·segment 인자(Intake 가 받는 것 그대로)
                self.lc.rs = intake.Intake(root, team, on_step=self.on_step, clock=self.clock, **caps)

    def revision(self):
        """잠금 없는 읽기 — 손상이면 CorruptStateError 를 그대로 올린다."""
        return self.lc._state_records()[0]["revision"]

    def put(self, row, dry=False):
        if self.lc is None:
            return Out(CORRUPT, row.get("key"), UNKNOWN, reason="runtime 없음 = 새 runtime 을 만들지 않는다")
        return self.lc._locked(self._put, Out(HOLD, row.get("key")), row, dry, k=0)

    def _put(self, context, row, dry):
        state, records = context
        key, rev = row["key"], state["revision"]
        if key in (state.get("imported") or {}):
            return Out(OK, key, ALREADY, False, rev, ALREADY)
        where = self._overlap(state, records, key)
        if where:
            return Out(OK, key, OVERLAP, False, rev, "겹침 " + where)
        seq = (records[-1]["seq"] if records else (state.get("journal_base") or {}).get("upto") or 0) + 1
        rec = build_line(self.team, seq, self.clock(), row)
        size, limit = journal.line_bytes(rec), self.lc.rs.journal.line_max
        if size > limit:                                # 칸을 잘라 쓰지 않는다
            return Out(REFUSED, key, UNKNOWN, False, rev, "줄 %d 바이트 > %d = 쓰기 0" % (size, limit))
        self.lc.rs.journal.reserve(1)                   # 새 키만 예약(R2) · 모자라면 WriterRefused «용량 부족»
        if dry:
            return Out(OK, key, IMPORTED, False, rev, "dry-run")
        self.lc.rs._append_journal(rec)
        self.on_step("after_journal")
        raw = self.lc.rs._state()                       # 다른 칸 = 디스크 값 그대로(owners.rotation 등 보존)
        folded = record.recover_state(raw, records + [rec])
        new = dict(raw, imported=folded["imported"], revision=max(folded["revision"], raw["revision"] + 1, rev + 1))
        self.lc.rs._write_state(new)
        self.on_step("after_state")
        return Out(OK, key, IMPORTED, True, new["revision"], "")

    def _overlap(self, state, records, key):
        """1.x ID 가 기존 2.0 ID 와 겹치는 자리(없으면 빈 문자열). seat = imported 만 본다."""
        cat, _sep, name = key.partition("/")
        accepts = [rec for rec in records if rec["kind"] == "accept"]
        receipts = (state.get("journal_base") or {}).get("receipts") or {}
        if cat == "card":
            for field in CARD_FIELDS:
                if name in (state.get(field) or ()):
                    return "state." + field
            if any(name in (rec.get("work"), rec["command"]) for rec in accepts):
                return "accept 줄"
        if cat == "intake" and any(rec["command"] == name for rec in accepts):
            return "accept 줄"
        if cat in ("card", "intake") and name in receipts:
            return "journal_base.receipts"
        return ""
