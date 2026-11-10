"""ft2 팀 상태 투영 — (r1596 · PR② 일곱째 장).

정본 ROUTE §3 PR② «팀 상태(투영 + 업무 구역 · journal replay)» 의 앞 장이다. 하는 일은 셋뿐이다:
① 팀 runtime 의 state·journal 을 읽는다(쓰기 0 · 잠금 0) ② `record.recover_state` 로 journal 을
앞세워 «지금 팀이 무엇을 하나» 를 작업별 1행으로 접는다 ③ 그 1개를 낸다.
읽기만 하므로 같은 runtime 이면 몇 번 만들어도 같은 결과다(멱등). 회수 뒤에는 옛 줄이 지워지므로
base checkpoint(`journal_base.proj`) 위에 남은 suffix 만 접는다 — 그 판단은 `recover_state` 가 이미
하고 이 파일은 그 결과를 «투영 꼴» 로 옮기기만 한다(투영이 state 를 따로 앞서지 않는다).
판독이 안 되면(state·journal 손상 · state.json.tmp 잔여) 숨기지 않고 `복구 필요` 1줄 + 작업 0 으로
드러내고, runtime 이 아직 없으면 `접수 성공` + 작업 0 + 사유 1줄이다(없는 팀은 손상이 아니다) —
`docs/rules/no_silent_fallback.md`(추측 0).
결과 낱말은 계약 8낱말(`접수 성공` · `복구 필요`) 밖으로 나가지 않는다(새 낱말 0).
"""
import importlib.util
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(_HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, journal = _load("record", "ft2_core_record"), _load("journal", "ft2_core_journal")
OK, CORRUPT = "접수 성공", "복구 필요"


def runtime_path(root, team):
    """팀 runtime 1곳 — 코어 입구(`Intake`)와 같은 자리. 읽기만 한다(폴더 생성 0)."""
    return os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "runtime")


def row(work, state):
    """작업 1개 → 투영 1행. 없는 칸은 기본값(담당 None · 세대 0 · 전달 [] · 완료·미확정 False)."""
    return {"owner": (state.get("owners") or {}).get(work),
            "gen": (state.get("generations") or {}).get(work) or 0,
            "deliveries": list((state.get("deliveries") or {}).get(work) or []),
            "done": work in (state.get("done") or {}),
            "uncertain": work in (state.get("uncertain") or {})}


def works_of(state):
    """투영에 나오는 작업 이름 — 담당·세대·전달·완료·미확정 5칸 어디에든 있으면 1행이다."""
    names = set()
    for name in ("generations", "owners", "deliveries", "done", "uncertain"):
        names |= set(state.get(name) or {})
    return sorted(names)


def project(root, team):
    """팀 상태 투영 1개 = {result, team, revision, pending, works, reason}. 쓰기·잠금 0."""
    runtime = runtime_path(root, team)
    if not os.path.isdir(runtime):
        return _empty(team, OK, "runtime 없음: %s" % runtime)
    node = journal.Journal(runtime, rec=record)
    try:
        state, records = node.state(), node.records()
        state = record.recover_state(state, records)     # journal_base.proj 위에서 앞선다(r1584)
    except record.CorruptStateError as exc:              # 손상 checkpoint(suffix 불연속)도 여기로 온다
        return _empty(team, CORRUPT, str(exc))
    return {"result": OK, "team": team, "revision": state["revision"], "pending": len(state["pending"]),
            "works": {work: row(work, state) for work in works_of(state)}, "reason": ""}


def _empty(team, word, reason):
    """투영 0 꼴 — 판독 불가·runtime 없음에서도 사유 1줄은 남긴다(숨김 0)."""
    return {"result": word, "team": team, "revision": 0, "pending": 0, "works": {}, "reason": reason}
