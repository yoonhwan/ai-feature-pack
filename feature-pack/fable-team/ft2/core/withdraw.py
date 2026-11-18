"""ft2 코어 접수 철회 (r1925b) — 배정·전달 전인 접수 1건을 사유 줄과 함께 뺀다.

쓰기 순서(잠금 안): 총량 예약 → bodies/<C>.body → bodies/<C>.<attempt>.withdrawn rename(폴더 fsync)
→ journal withdraw 1줄 fsync → state(pending 에서 C 제거 · withdrawn[attempt]) → «철회 성공».
rename 뒤 journal 전 crash = 다음 withdraw 가 journal 부터 잇는다 · 철회 = attempt 단위(재접수 = 새 attempt).
"""

import importlib.util
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("ft2_core_intake", os.path.join(_HERE, "intake.py"))
intake = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(intake)
record = intake.record
# 이 work 에 이 줄이 하나라도 있으면 «배정·전달된 일» 이다(철회 거부).
BLOCKING = ("dispatch", "deliver", "uncertain", "result", "complete", "close", "close_receipt", "progress")

OK, USAGE, REFUSED, HOLD, BUSY, CORRUPT = "철회 성공", "사용법", "접수 거부", "완료 유보", "BUSY", "복구 필요"


def _out(word, command, reason, attempt=None, revision=None, written=False):   # 기존 JSON 1줄 꼴(result·reason)
    return dict(result=word, command=command, attempt=attempt, revision=revision, written=written, reason=reason)


def _assigned(state, records, work):
    """배정·전달·실행 기록 이름 1개 — journal 줄 kind 먼저, 다음 state 칸. 없으면 ''."""
    kind = next((rec["kind"] for rec in records if rec["kind"] in BLOCKING and rec.get("work") == work), "")
    held = any(isinstance(row, dict) and row.get("work") == work for row in (state.get("reservations") or {}).values())
    found = kind or next((name for name in ("owners", "deliveries", "done") if work in (state.get(name) or {})), "")
    return found or ("reservations" if held else "")


class Withdraw:
    """팀 runtime 1곳의 접수 철회. 잠금·journal·본문 경로는 입구(Intake)와 같은 것을 쓴다."""
    def __init__(self, root, team, clock=None, **caps):
        self.gate = intake.Intake(root, team, clock=clock, **caps)

    def withdraw(self, command, why):
        if not isinstance(why, str) or not why.strip() or "\n" in why or "\r" in why or len(why) > 200:
            return _out(USAGE, command, "사유 = 공백 아닌 1줄 · 200자 이하 = 쓰기 0")
        if (lock := self.gate._try_lock()) is None:
            return _out(BUSY, command, "writer.lock 점유 = 기다리지 않는다(BUSY)")
        try:
            return self._locked(command, why)
        except ValueError as exc:      # CorruptStateError·WriterRefused·RecordError(코어 사본 클래스)
            return _out(getattr(exc, "word", "") or CORRUPT, command, str(exc),
                        written=bool(getattr(exc, "written", False)))
        finally:
            self.gate._unlock(lock)

    def _locked(self, command, why):
        gate = self.gate
        records = gate.records()
        state = record.recover_state(gate._state(), records)
        prior = gate._prior_receipt(records, command)          # 마지막 attempt = suffix accept · 없으면 base 영수
        if prior is None:
            return _out(REFUSED, command, "접수 기록 없음 = 쓰기 0")
        attempt, withdrawn = prior["attempt"], state.get("withdrawn") or {}
        if attempt in withdrawn:
            return _out(HOLD, command, "이미 철회 = 멱등(쓰기 0)", attempt, state["revision"])
        work = prior.get("work") if isinstance(prior.get("work"), str) else None
        seen = _assigned(state, records, work or command)
        if seen:
            return _out(REFUSED, command, "배정·전달된 일 = 철회 거부 (%s)" % seen, attempt, state["revision"])
        moved = "bodies/%s.%s.withdrawn" % (command, attempt)
        rec = record.build(gate.team, (records[-1]["seq"] if records else 0) + 1, command, attempt, gate.clock(),
                           why, work, kind="withdraw", extra={"why": why, "moved": moved})
        new_state = dict(state, revision=state["revision"] + 1,
                         pending=[cmd for cmd in state["pending"] if cmd != command],
                         withdrawn=dict(withdrawn, **{attempt: {"command": command, "why": why, "body": moved}}))
        gate.journal.reserve(1)                                # 본문 rename «전» 총량 판정(부족 = 쓰기 0)
        if os.path.exists(gate.body_path(command)):
            os.replace(gate.body_path(command), os.path.join(gate.runtime, moved))
            intake._fsync_dir(gate.bodies)
        gate.on_step("withdraw_after_rename")
        gate.journal.append(rec, gate.journal.envelope_for(new_state))
        gate.on_step("withdraw_after_journal")
        gate.journal.write_state(new_state)
        return _out(OK, command, why, attempt, new_state["revision"], True)
