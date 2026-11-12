"""ft2 회수 거절 처리 이력 키 — (카드 r1724 · 계획 PLAN-ft20-reclaim-refuse-history-key-20261112 · R1 보정).

회수 거절마다 처리 이력 키 `<work>|<place>#<gen>|<cause>|<artifact>` 로 팀 runtime 의 journal·state(기존
사건 이력 · 새 원장 0)에 누적한다. 자동 해소 1 + 재시도 1 → 완료 유보 · 사람 요청 키당 1회 · 재기동·재접수
초기화 0 · 해소 사건(새 근거 · 권한 결정)에서만 재시도 1회를 연다.
키의 자리/세대 = 회수 «대상» 자리다. 요청·집행한 쪽(실행기·팀장·후계)은 `by` 칸에만 적는다(키 불변).
판정 = `record._fold_refusal` 하나(단일 재생 경로 · 계획 1-1절). journal 에는 입력 사건만 적고 결과값은
적지 않는다. 쓰기 순서 = writer.lock(비차단 · 점유 = BUSY) → recover_state → 사건 멱등 선검사(같은 fold)
→ journal 1줄 → recover_state(records + 새 줄) → state. 어디서 끊겨도 다음 판독이 같은 함수로 같은 값을 낸다.
결과 낱말 = contracts/core 8낱말 안만(새 낱말 0).
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


intake = _load("intake", "ft2_core_intake")
record = intake.record                      # journal 이 쓰는 그 모듈 — 접기·예외가 한 사본이다
OK, HOLD, REFUSED, BUSY, CORRUPT = "접수 성공", "완료 유보", "접수 거부", "BUSY", "복구 필요"
WHYS = ("새 근거", "권한 결정")                # 새 판본 = 새 키라 해소 사건이 아니다
Refusal = collections.namedtuple(
    "Refusal", "result key next request_human attempts held open_retries written revision reason",
    defaults=(None, None, False, None, None, None, False, None, ""))


class RefuseHistory:
    """팀 runtime 1곳의 회수 거절 이력. 경로·잠금·판독은 입구(Intake)와 같은 것을 쓴다."""
    CLIENT = intake.Intake

    def __init__(self, root, team, clock=None, on_step=None):
        self.team, self.on_step = team, on_step or (lambda step: None)
        self.clock = clock or (lambda: time.strftime("%Y-%m-%dT%H:%M:%S"))
        self.rs = self.CLIENT(root, team, on_step=self.on_step)

    def key_of(self, work, place, gen, cause, artifact):
        return "%s|%s#%s|%s|%s" % (work, place, gen, cause, artifact)

    def refuse(self, work, place, gen, cause, artifact, event, by=None):
        """거절 1건 — 출력 next = 자동 해소 | 재시도 | 유보 · request_human = 이 호출이 사람 요청을 세웠는가."""
        return self._call("refuse", (work, place, gen, cause, artifact), event, {"by": by},
                          self._key_for(work, place, gen, cause, artifact, by))

    def resolve(self, work, place, gen, cause, artifact, event, why):
        """해소 사건 1건 — why ∈ WHYS 만 · 같은 사건 두 번 = 쓰기 0 · 해소 1건 = 재시도 1회."""
        if why not in WHYS:
            return Refusal(REFUSED, reason="해소 사유는 %s 만: %r" % (" | ".join(WHYS), why))
        return self._call("resolve", (work, place, gen, cause, artifact), event, {"why": why},
                          self.key_of(work, place, gen, cause, artifact))

    def _key_for(self, work, place, gen, cause, artifact, by):
        """변이 M4 자리 — 요청·집행한 쪽(by)은 키에 넣지 않는다(후계 교체 = 초기화 0)."""
        return self.key_of(work, place, gen, cause, artifact)

    def _call(self, kind, parts, event, extra, key):
        problem = self._problem(parts, event)
        if problem:
            return Refusal(REFUSED, reason=problem)
        lock = self.rs._try_lock()
        if lock is None:
            return Refusal(BUSY, key, reason="writer.lock 점유 = 기다리지 않는다")
        try:
            self.rs.journal.reserve(1)                          # 첫 쓰기 전 예약(lifecycle 과 같은 꼴)
            return self._apply(kind, parts[0], key, event, extra)
        except ValueError as exc:      # 모듈 사본마다 클래스가 달라 낱말 칸으로 가른다(lifecycle 과 같다)
            return Refusal(getattr(exc, "word", CORRUPT), key, written=getattr(exc, "written", False),
                           reason=str(exc))
        finally:
            self.rs._unlock(lock)

    def _problem(self, parts, event):
        """키 4칸(work · place#gen · cause · artifact)과 사건 id — 빈 값·«|» = 접수 거부 · 쓰기 0."""
        work, place, gen, cause, artifact = parts
        if isinstance(gen, bool) or not isinstance(gen, int) or gen < 0:
            return "세대는 0 이상 정수: %r" % (gen,)
        for name, value in (("work", work), ("place", place), ("cause", cause), ("artifact", artifact),
                            ("event", event)):
            if not isinstance(value, str) or not value.strip() or "|" in value:
                return "%s 빈 값 또는 «|» 포함: %r" % (name, value)
        return ""

    def _apply(self, kind, work, key, event, extra):
        records = self.rs.records()
        state = record.recover_state(self.rs._state(), records)
        seq = (records[-1]["seq"] if records else (state.get("journal_base") or {}).get("upto", 0)) + 1
        rec = record.build(self.team, seq, key, "%s:%s" % (kind, event), self.clock(), "", work, kind=kind,
                           extra=dict(extra, key=key, event=event))
        if record._fold_refusal(state["refusals"], rec) == state["refusals"]:   # 같은 사건 = 재접수
            return self._out(HOLD, key, state, False, "재접수", "같은 사건 %s = 쓰기 0 · 사람 요청 0" % event)
        self.rs._append_journal(rec)
        self.on_step("after_journal")
        self.on_step("after_%s_journal" % kind)
        new = record.recover_state(state, records + [rec])
        new = dict(new, revision=max(new["revision"], state["revision"] + 1))
        self.rs._write_state(new)
        self.on_step("after_state")
        last = new["refusals"][key]["last"] if kind == "refuse" else None
        word = HOLD if last and last["next"] == "유보" else OK
        return self._out(word, key, new, True, last["next"] if last else None, "",
                         bool(last and last["request_human"]))

    def _out(self, word, key, state, written, step, reason, request=False):
        row = state["refusals"].get(key) or {}
        return Refusal(word, key, step, request, row.get("attempts", 0), row.get("held", False),
                       row.get("open_retries", 0), written, state["revision"], reason)
