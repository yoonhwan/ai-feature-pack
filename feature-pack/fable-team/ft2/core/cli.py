"""ft2 코어 전이 CLI (r1595 · PR②-6).

라이브러리로만 있던 착지된 전이를 «비모델 명령 1개» 로 부른다. 동사 1개 = 공개 메서드 1개이고,
출력 = 라이브러리 반환 그대로의 JSON 1줄, rc = 처리 결과 낱말의 계약값이다(모델 판단 0).
낱말 밖 결과는 성공으로 내지 않는다. 인자·동사가 틀리면 쓰기 «전» 에 rc 64 로 끝난다.

    python3 core/cli.py <동사> --root R --team T [--인자 값 …]
    python3 -m core.cli <동사> --root R --team T [--인자 값 …]

읽기 동사 `project` 만 예외다 — 라이브러리 함수 `projection.project` 1개를 그대로 부르고 상태를 바꾸지 않는다(잠금 0).
"""

import importlib.util
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
USAGE = 64
# 처리 결과 낱말 → rc (계약). 표에 없는 낱말은 성공이 아니다 = 1.
RC = {"접수 성공": 0, "회수 결과": 0, "접수 거부": 1, "BUSY": 1, "용량 부족": 1,
      "완료 유보": 1, "낡은 실행권": 1, "복구 필요": 2}
# 동사 → (클래스, 공개 메서드, 필수 인자, 선택 인자). 순서가 곧 호출 인자 순서다.
VERBS = {
    "submit": ("Intake", "submit", ("command", "body"), ("work",)),
    "assign": ("Dispatch", "assign", ("work", "holder"),
               ("pre", "evidence", "resources", "rotation", "gate")),
    "deliver": ("Dispatch", "deliver", ("work",), ("attempt", "mode")),
    "claim": ("Execution", "claim", ("work", "holder"), ("rotation", "confirm_by")),
    "start": ("Execution", "start", ("work", "holder", "gen"), ()),
    "effect": ("Execution", "effect", ("work", "holder", "gen", "effect"), ()),
    "result": ("Execution", "result", ("work", "holder", "gen"), ("word",)),
    "complete": ("Dispatch", "complete", ("work",), ("attempt",)),
    "reassess": ("Dispatch", "reassess", ("work",), ("mode",)),
    "recover": ("Dispatch", "recover", (), ("mode",)),
    "reclaim": ("Journal", "reclaim", (), ()),
    "project": ("Projection", "project", (), ()),      # 읽기 동사 — 잠금·쓰기 0 (r1617)
    "refuse": ("RefuseHistory", "refuse", ("work", "place", "gen", "cause", "artifact", "event"), ("by",)),
    "resolve": ("RefuseHistory", "resolve", ("work", "place", "gen", "cause", "artifact", "event", "why"), ()),
    "record-read": ("TeamRecord", "read", (), ()),     # 읽기 동사 — 잠금·쓰기 0 (r1723)
    "record-write": ("TeamRecord", "write", ("seat", "expect", "fields_file"), ()),
    "close-receipt": ("CloseNext", "receipt", ("seat", "gen", "work", "event", "next_holder", "evidence"),
                      ("next_work", "pre", "resources")),     # r1725 — CLI 에는 probe 가 없다 = 판정 불가
    "seat-done": ("CloseNext", "seat_done", ("seat", "expect", "fields_file"), ()),
    "close-candidates": ("CloseNext", "candidates", ("facts_file",), ()),   # 읽기 동사 — 쓰기 0
    "close-enable": ("CloseNext", "enable", ("seats_file",), ()),
    "reopen": ("Reopen", "reopen", ("revision", "event", "lead"), ("ack",)),   # r1727 — CLI 에는 probe 가 없다
}
LISTS = ("pre", "evidence", "resources")      # 쉼표 = 여러 값
INTS = ("gen", "expect", "revision")
BOOLS = ("rotation",)
GLOBAL = ("root", "team")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_cli_" + name, os.path.join(_HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Usage(Exception):
    """동사·인자·값이 틀렸다 = rc 64 · 쓰기 0."""


def _value(name, raw):
    if name in LISTS:
        return tuple(part for part in raw.split(",") if part)
    if name in BOOLS:
        return raw.lower() in ("1", "true", "yes", "on")
    if name in INTS:
        try:
            return int(raw)
        except ValueError:
            raise Usage("%s 는 정수여야 한다: %r" % (name, raw))
    return raw


def parse(argv):
    """`<동사> --이름 값 …` → (동사, 인자 dict). 모르는 동사·인자·값 빠짐 = Usage."""
    if not argv or argv[0] not in VERBS:
        raise Usage("동사: " + ", ".join(sorted(VERBS)))
    verb, rest = argv[0], argv[1:]
    _cls, _method, required, optional = VERBS[verb]
    known, given, index = required + optional + GLOBAL, {}, 0
    while index < len(rest):
        token = rest[index]
        if not token.startswith("--") or token[2:] not in known or index + 1 >= len(rest):
            raise Usage("인자 꼴: --이름 값 (받은 것 %r)" % (token,))
        given[token[2:]] = _value(token[2:], rest[index + 1])
        index += 2
    missing = [name for name in required + GLOBAL if name not in given]
    if missing:
        raise Usage("값 빠짐: " + ",".join("--" + name for name in missing))
    if "fields_file" in given:                       # r1723: 칸 묶음 = JSON 1개 경로 · 못 읽으면 쓰기 전 64
        given["fields_file"] = _fields_file(given["fields_file"])
    return verb, given


def _fields_file(path):
    try:
        with open(path, encoding="utf-8") as handle:
            fields = json.load(handle)
    except (OSError, ValueError) as exc:
        raise Usage("fields_file 판독 불가: %s" % exc)
    if isinstance(fields, dict):
        return fields
    raise Usage("fields_file 은 JSON 객체 1개여야 한다: %s" % path)


def clock_from_env():
    """FT_NOW 고정 시계 — 있으면 그 값, 없으면 초 단위 현재 시각(코어 기본과 같다)."""
    fixed = os.environ.get("FT_NOW")
    if fixed:
        return lambda: fixed
    return lambda: time.strftime("%Y-%m-%dT%H:%M:%S")


def call(verb, given, clock):
    """동사 1개 → 공개 메서드 1개. 반환은 라이브러리 그대로(JSON 낼 수 있는 꼴)."""
    classes = {"Intake": _load("intake").Intake, "Execution": _load("execution").Execution,
               "Dispatch": _load("dispatch").Dispatch, "TeamRecord": _load("team_record").TeamRecord}
    classes["RefuseHistory"] = _load("refuse_history").RefuseHistory   # r1724 회수 거절 이력
    classes["CloseNext"] = _load("close_next").CloseNext               # r1725 닫기 영수 → 다음 발주
    classes["Reopen"] = _load("reopen").Reopen                         # r1727 재개 = 팀장 1번만
    cls_name, method, required, optional = VERBS[verb]
    root, team = os.path.abspath(given["root"]), given["team"]
    if cls_name == "Projection":                        # 읽기 동사 — 인스턴스·잠금 없이 투영만 읽는다
        return _load("projection").project(root, team)
    if cls_name == "Journal":
        target = _load("journal").Journal(os.path.join(root, ".fable-team", "teams", team, "runtime"))
    else:
        target = classes[cls_name](root, team, clock=clock)
    args = [given[name] for name in required]
    kwargs = {name: given[name] for name in optional if name in given}
    out = getattr(target, method)(*args, **kwargs)
    return out._asdict() if hasattr(out, "_asdict") else dict(out)


def error_word(exc):
    """코어 예외 → 계약 낱말. 모듈 사본(_load)마다 클래스 객체가 달라 낱말 칸 → 클래스 이름으로 가른다
    (dispatch._locked 와 같은 이유·같은 방식). WriterRefused 는 자기 낱말을 갖고 있다."""
    if getattr(exc, "word", ""):
        return exc.word
    return "복구 필요" if type(exc).__name__ == "CorruptStateError" else "접수 거부"


def run(argv):
    """(결과 dict, rc) — 예외도 계약 낱말 하나로 접는다(JSON 1줄 계약은 예외에도 걸린다)."""
    try:
        verb, given = parse(argv)
    except Usage as exc:
        return {"result": "사용법", "reason": str(exc)}, USAGE
    try:
        out = call(verb, given, clock_from_env())
    except ValueError as exc:        # RecordError·CorruptStateError·WriterRefused(코어 사본 클래스)
        out = {"result": error_word(exc), "reason": str(exc),
               "written": bool(getattr(exc, "written", False))}
    word = out.get("result")
    return out, RC.get(word, 1)


def main(argv):
    if argv[:2] == ["slack", "listen"]:   # r1806 Socket Mode 상주 수신기 — 동사 표 밖 진입 1곳(비모델)
        path = os.path.join(os.path.dirname(_HERE), "adapters", "slack", "socket.py")
        spec = importlib.util.spec_from_file_location("ft2_slack_socket", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.main(argv[2:])
    if argv[:1] == ["slack"] and argv[1:2] in (["reply"], ["notify"], ["post"]):   # r1807 · r1923 post 팀 좌석 → 같은 thread 답·알림(비모델)
        path = os.path.join(os.path.dirname(_HERE), "adapters", "slack", "wiring.py")
        spec = importlib.util.spec_from_file_location("ft2_slack_wiring", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.main(argv[1:])
    if argv[:2] == ["slack", "handover-seat"]:   # r1827 좌석 교대 → 열린 thread 담당 후계로(비모델 · retire 가 부른다)
        path = os.path.join(os.path.dirname(_HERE), "adapters", "slack", "binding.py")
        spec = importlib.util.spec_from_file_location("ft2_slack_binding", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.main(argv[2:])
    if argv[:1] == ["keeper"]:          # r1812 끝난 좌석 자동 닫기 — 동사 표 밖 진입 1곳(비모델 · launchd 60초 1바퀴)
        path = os.path.join(os.path.dirname(_HERE), "adapters", "pi", "keeper.py")
        spec = importlib.util.spec_from_file_location("ft2_keeper", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.main(argv[1:])
    out, rc = run(argv)
    sys.stdout.write(json.dumps(out, ensure_ascii=False, sort_keys=True) + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
