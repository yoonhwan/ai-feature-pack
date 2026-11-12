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
# r1594: 진행 구분(progress)·골 마감(close) 추가 — lifecycle.py 만 쓴다. r1724: refuse·resolve — refuse_history.py 만.
KINDS = ("accept", "claim", "start", "effect", "result", "uncertain",
         "dispatch", "deliver", "execute", "complete", "reassess", "progress", "close", "refuse", "resolve")
STATE_FIELDS = ("revision", "pending", "attempts")
# 확장 state 칸 — 없으면 기본값 {} 로 채운다(다른 writer 가 병합해 보존한다 · ⓘ).
EXTENDED_STATE_FIELDS = ("generations", "owners", "uncertain", "deliveries", "reservations",
                         "done", "reassess_done", "released", "owners_recovered", "executed",
                         "journal_base", "refusals")   # r1584: 회수 base checkpoint · r1724: 거절 처리 이력


class RecordError(ValueError):
    """schema 위반·버전 불일치 — 영수 없이 쓰기를 거절한다."""


class CorruptStateError(ValueError):
    """state·journal 이 schema v1 로 읽히지 않는다 = 복구 필요."""


class WriterRefused(CorruptStateError):
    """쓰기 전 총량 거절(r1584) — word = 계약 낱말, written = 이 호출에서 journal 줄이 내구화됐는가."""

    def __init__(self, word, reason="", written=False):
        super().__init__(reason or word)
        self.word, self.written = word, written


def read_state_guarded(path):
    """state 를 읽어 형까지 검사한다. 없으면 최초 상태. 형이 틀리면 쓰기 «전» 에 `CorruptStateError`."""
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except FileNotFoundError:
        state = {"schema": SCHEMA_VERSION, "revision": 0, "pending": [], "attempts": {}}
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


def _lane_row(row, kind, tick, deadline):
    """progress 줄 1개를 lane 1칸으로 접는다 — heartbeat 는 progress_at 을 밀지 않는다(재무장 0).
    external_wait 는 시한(절대 tick)을 보존하고, 시한 안인지는 scan 이 판정한다."""
    out = dict(row or {"progress_at": tick or 0, "heartbeat_at": 0, "external_wait": False,
                       "wait_deadline": None, "rearm": 0})
    if kind == "progress":
        out["progress_at"] = tick
    elif kind == "heartbeat":
        out["heartbeat_at"] = tick
    elif kind == "external_wait":
        out["external_wait"], out["wait_deadline"] = True, deadline
    return out


def _fold_refusal(refusals, rec):
    """r1724 처리 이력 판정의 유일한 구현(순수 · 같은 사건 = 입력 그대로). 거절 1 자동 해소 · 2 재시도 ·
    3+ 열린 재시도 1 소비 또는 유보(사람 요청 키당 1회) · 해소 1건 = 열린 재시도 +1. 쓰기·재생이 이 함수를 같이 쓴다."""
    key, event = rec.get("key"), rec.get("event")
    row = dict(refusals.get(key) or {"attempts": 0, "auto_done": False, "requested": False, "held": False,
                                     "events": [], "resolutions": [], "open_retries": 0, "last": None})
    if rec["kind"] == "refuse":
        if event in row["events"]:
            return refusals
        row.update(events=row["events"] + [event], attempts=row["attempts"] + 1, auto_done=True)
        step, request = ("자동 해소" if row["attempts"] == 1 else "재시도"), False
        if row["attempts"] > 2 and row["open_retries"] > 0:
            row["open_retries"] -= 1
        elif row["attempts"] > 2:
            step, request = "유보", not row["requested"]
            row["requested"] = True
        row["held"], row["last"] = step == "유보", {"event": event, "next": step, "request_human": request}
    else:
        if event in [res["event"] for res in row["resolutions"]]:
            return refusals
        row["resolutions"] = row["resolutions"] + [{"event": event, "why": rec.get("why")}]
        row["open_retries"] += 1
    return dict(refusals, **{key: row})


def remaining(state, records):
    """«남은 일» 장부 — 접수 command(활성 journal + state.pending) 중 회수된 영수(receipts)와 done work 를 뺀 것.
    intake 용량 상한과 lifecycle 마감 판정이 «같은» 곳을 보게 하는 한 점이다(r1616 보정 2)."""
    by_command = {rec["command"]: rec.get("work") for rec in records if rec["kind"] == "accept"}
    by_command.update({cmd: by_command.get(cmd) for cmd in state.get("pending") or []
                       if isinstance(cmd, str) and cmd not in by_command})
    folded, done = (state.get("journal_base") or {}).get("receipts") or {}, state.get("done") or {}
    return [cmd for cmd, work in by_command.items()
            if cmd not in folded and not (isinstance(work, str) and work in done)]


def recover_state(state, records):
    """journal 을 정본으로 삼아 state checkpoint 를 앞선다(DA R2 · R1) — checkpoint 전 crash 복구.
    잠금 안 판독(모든 writer)이 이 함수를 지나므로 recover 호출 여부와 무관하게 전달·완료·재평가가 보인다:
    세대·owner·예약(배정 줄) · 전달(전달 줄) · 완료 표식(완료 줄) · 재평가 결과(재평가 줄) · 미확정 표식 ·
    진행 칸(진행 줄 · r1594) · 마감 표식(마감 줄 = done["goal:<골>"] · r1594).
    뒤 기록이 앞 기록을 덮는다(결과 확정은 owner·미확정을 지우고, 재평가는 반환·owner 복구를 남긴다).
    r1584(DA R1 ①②): state.journal_base = {upto,count,proj,receipts} 가 있으면 proj 9칸에서 시작해
    seq > upto 줄만 접는다. suffix 첫 줄은 upto+1 이어야 한다(아니면 복구 필요). base 없으면 오늘과 같다."""
    base = dict(state.get("journal_base") or {})
    upto, count, proj = base.get("upto") or 0, base.get("count") or 0, dict(base.get("proj") or {})
    rows = [rec for rec in records if rec["seq"] > upto] if upto else list(records)
    if upto and rows and rows[0]["seq"] != upto + 1:
        raise CorruptStateError("journal suffix seq 불연속: %r != %r" % (rows[0]["seq"], upto + 1))
    gens, owners = dict(proj.get("generations") or {}), dict(proj.get("owners") or {})
    kept, sent = dict(proj.get("reservations") or {}), dict(proj.get("deliveries") or {})
    done, reassessed = dict(proj.get("done") or {}), dict(proj.get("reassess_done") or {})
    released, recovered = dict(proj.get("released") or {}), dict(proj.get("owners_recovered") or {})
    uncertain = dict(proj.get("uncertain") or {})
    lanes = dict(state.get("lanes") or {})
    refusals = dict(proj.get("refusals") or {})       # r1724: 시작값 = checkpoint · state.refusals 는 쓰지 않는다
    for rec in rows:
        work, kind, gen = rec.get("work"), rec["kind"], rec.get("gen") or 0
        if kind in ("claim", "dispatch") and work and gen > gens.get(work, 0):
            gens[work], owners[work] = gen, {"holder": rec.get("holder"), "gen": gen, "at": rec["at"]}
        if kind == "dispatch" and work:
            for res in rec.get("resources") or []:
                kept.setdefault(res, {"work": work, "attempt": rec.get("attempt")})
        elif kind == "deliver" and work:
            sent[work] = list(sent.get(work) or []) + [rec.get("attempt")]
        elif kind == "uncertain" and work:
            uncertain[work] = {"gen": gen, "holder": rec.get("holder"), "at": rec["at"],
                               "confirm_by": rec.get("confirm_by"), "reason": rec.get("body")}
        elif kind == "result" and work:
            owners.pop(work, None)
            uncertain.pop(work, None)
        elif kind == "complete" and work:
            done[work] = {"attempt": rec.get("after"), "at": rec["at"], "marker": rec.get("marker") or ""}
        elif kind == "reassess" and work:
            reassessed[work] = {"after": rec.get("after"), "mode": rec.get("mode")}
            released[work] = {"res": rec.get("released") or [], "count": len(rec.get("released") or [])}
            recovered[work] = {"owner": rec.get("holder"), "attempt": rec.get("after")}
            owners.pop(work, None)
            kept = {res: row for res, row in kept.items() if row.get("work") != work}
        elif kind == "progress" and work and rec.get("lane"):
            lanes[rec["lane"]] = _lane_row(lanes.get(rec["lane"]), rec.get("tick_kind"),
                                           rec.get("tick"), rec.get("wait_deadline"))
        elif kind == "close" and work:
            done[work] = {"attempt": rec.get("attempt"), "at": rec["at"], "marker": ""}
        elif kind in ("refuse", "resolve") and work:
            refusals = _fold_refusal(refusals, rec)
    return dict(state, revision=max(state["revision"], count + len(rows)), generations=gens, owners=owners,
                reservations=kept, deliveries=sent, done=done, reassess_done=reassessed,
                released=released, owners_recovered=recovered, uncertain=uncertain, lanes=lanes, refusals=refusals)


def build(team, seq, command, attempt, at, body, work=None, goal=None, kind="accept",
          holder=None, gen=None, extra=None):
    """schema v1 레코드 1개를 만든다. 만든 뒤 `check` 로 자기 검사를 한다.
    `extra` = r1581 확장 칸(예약·전달 의도·재평가 표식). 필드 추가만이고 schema 는 1 그대로다."""
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
    rec.update(extra or {})
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
