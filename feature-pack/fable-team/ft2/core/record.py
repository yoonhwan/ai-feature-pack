"""ft2 코어 기록 꼴 — schema v1 (r1576 · PR② 첫 장).

정본 PLAN §추천 schema(216행) 이 정한 최소 의미만 담는다:
version · 팀 · seq · 종류 · command/attempt · work · 본문 참조.
버전 불일치·필수 필드 누락 = 쓰기 거절(`RecordError`)이고 호출자는 기존 자료를 보존한다.
상태 판독(`read_state_guarded`)도 여기서 한다 — 형 검사를 쓰기 «앞» 에 끝내야 하기 때문이다.
처리 결과 낱말은 `ft2/contracts/core/CASES.md` 8낱말 밖으로 나가지 않는다.
"""

import json

SCHEMA_VERSION = 1

RESULT_WORDS = (
    "접수 성공",
    "접수 거부",
    "복구 필요",
    "낡은 실행권",
    "BUSY",
    "용량 부족",
    "완료 유보",
    "회수 결과",
)

REQUIRED_FIELDS = ("schema", "team", "seq", "kind", "command", "attempt", "at", "body", "work")
# r1579: 실행권·세대 종류 추가(세대 교체는 claim 의 gen 으로 표현). schema 1 유지 = 필드 추가만.
KINDS = ("accept", "claim", "start", "effect", "result", "uncertain")
STATE_FIELDS = ("revision", "pending", "attempts")
# 확장 state 칸 — 없으면 기본값 {} 로 채운다(다른 writer 가 병합해 보존한다 · ⓘ).
EXTENDED_STATE_FIELDS = ("generations", "owners", "uncertain")


class RecordError(ValueError):
    """schema 위반·버전 불일치 — 영수 없이 쓰기를 거절한다."""


class CorruptStateError(ValueError):
    """state·journal 이 schema v1 로 읽히지 않는다 = 복구 필요."""


def read_state_guarded(path):
    """state 를 읽어 형까지 검사한다. 없으면 최초 상태. 형이 틀리면 쓰기 «전» 에 `CorruptStateError`."""
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        return {"schema": SCHEMA_VERSION, "revision": 0, "pending": [], "attempts": {}}
    except (ValueError, UnicodeDecodeError) as exc:
        raise CorruptStateError("state 판독 불가: %s" % exc)
    if not isinstance(state, dict) or state.get("schema") != SCHEMA_VERSION:
        raise CorruptStateError("state schema 불일치: %r" % (state if not isinstance(state, dict) else state.get("schema"),))
    missing = [name for name in STATE_FIELDS if name not in state]
    if missing:
        raise CorruptStateError("state 필수 칸 누락: " + ",".join(missing))
    if not isinstance(state["revision"], int) or not isinstance(state["pending"], list) \
            or not isinstance(state["attempts"], dict):
        raise CorruptStateError("state 칸 형 위반: %r" % (sorted(state),))
    for name in EXTENDED_STATE_FIELDS:
        state.setdefault(name, {})
    bad = [name for name in EXTENDED_STATE_FIELDS if not isinstance(state[name], dict)]
    if bad:
        raise CorruptStateError("state 확장 칸 형 위반: " + ",".join(bad))
    return state


def recover_state(state, records):
    """journal 에만 내구화된 claim 세대·기록 수를 state checkpoint 보다 앞세운다(DA R2).
    모든 writer 가 같은 복구 기준을 쓴다 — 옛 gen 거절은 쓰기 0 이라 checkpoint 가 낡아 있기 때문이다."""
    recovered = dict(state, revision=max(state["revision"], len(records)))
    gens, owners = dict(recovered.get("generations") or {}), dict(recovered.get("owners") or {})
    for rec in records:
        gen = rec.get("gen") or 0
        if rec.get("kind") == "claim" and rec.get("work") and gen > gens.get(rec["work"], 0):
            gens[rec["work"]] = gen
            owners[rec["work"]] = {"holder": rec.get("holder"), "gen": gen, "at": rec["at"]}
    return dict(recovered, generations=gens, owners=owners)


def build(team, seq, command, attempt, at, body, work=None, goal=None, kind="accept",
          holder=None, gen=None):
    """schema v1 레코드 1개를 만든다. 만든 뒤 `check` 로 자기 검사를 한다."""
    rec = {
        "schema": SCHEMA_VERSION,
        "team": team,
        "seq": seq,
        "kind": kind,
        "command": command,
        "attempt": attempt,
        "at": at,
        "body": body,
        "work": work,
        "goal": goal,
        "holder": holder,
        "gen": gen,
    }
    check(rec)
    return rec


def check(rec):
    """레코드 1개를 검사한다. 통과하면 True, 아니면 `RecordError`."""
    if not isinstance(rec, dict):
        raise RecordError("레코드가 dict 가 아니다")
    if rec.get("schema") != SCHEMA_VERSION:
        raise RecordError("schema 버전 불일치: %r != %r" % (rec.get("schema"), SCHEMA_VERSION))
    missing = [name for name in REQUIRED_FIELDS if name not in rec]
    if missing:
        raise RecordError("필수 필드 누락: " + ",".join(missing))
    if rec.get("kind") not in KINDS:
        raise RecordError("종류 미상: %r" % (rec.get("kind"),))
    if not isinstance(rec.get("seq"), int) or rec["seq"] < 1:
        raise RecordError("seq 는 1 이상 정수여야 한다: %r" % (rec.get("seq"),))
    if rec.get("gen") is not None and (not isinstance(rec["gen"], int) or rec["gen"] < 1):
        raise RecordError("gen 은 1 이상 정수여야 한다: %r" % (rec.get("gen"),))
    for name in ("team", "command", "attempt", "at"):
        if not isinstance(rec.get(name), str) or not rec[name]:
            raise RecordError("%s 는 비어 있지 않은 문자열이어야 한다" % name)
    return True


def is_contract_result(word):
    """결과 낱말이 계약 8낱말 안인가 (ⓕ)."""
    return word in RESULT_WORDS
