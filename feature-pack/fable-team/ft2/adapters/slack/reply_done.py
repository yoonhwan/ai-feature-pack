"""ft2 Slack 답글 = 그 thread 앞 글 완료 (r1872). publish `_settle`(게시 확정 3곳)만 부른다 · 멱등.

같은 workspace·channel·thread 에서 답글이 가리키는 글 ts 이하로 접수된 Slack 글 중 완료 아님 ∧ 배정 계보 0 인 것만
`Dispatch.complete` 1회씩. 덮는 글이 있으면(기확정 재확인 포함 · R1b) «용량 부족» 글을 ts 오래된 순으로 연 칸 수만큼
SlackRoute 복구 client 로 다시 접수한다(route 보존 · R1a · 같은 command 재부여 0 = intake `_prior_receipt`). 상한 값·코어 손 0 · 실패 = «판정 불가» 1줄 + 게시 결과 그대로(하드 룰 20).
"""
import importlib.util, os, re, sys  # noqa: E401

_HERE = os.path.dirname(os.path.abspath(__file__))

def _load(alias, path):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(_HERE, path))
    spec.loader.exec_module(module := importlib.util.module_from_spec(spec))
    return module

dispatch = _load("ft2_core_dispatch", os.path.join("..", "..", "core", "dispatch.py"))
receive, route = _load("ft2_slack_receive", "receive.py"), _load("ft2_slack_route", "route.py")
SLACK = re.compile(r"^slack:([^:]+):([^:]+):([^:]+)$")

def _ts(value):  # Slack ts «초.마이크로» — float 정밀도 손실 없이 비교
    return tuple(int(part or 0) for part in str(value).split("."))

def _targets(state, records, key, ts):
    done, owners = state.get("done") or {}, state.get("owners") or {}
    assigned = {rec.get("work") for rec in records if rec["kind"] == "dispatch"}
    out = []
    for rec in (rec for rec in records if rec["kind"] == "accept" and isinstance(rec.get("work"), dict)):
        slack, route, command = rec["work"].get("slack") or {}, rec["work"].get("route") or {}, rec["command"]
        own, thread = str(slack.get("ts") or ""), str(route.get("thread") or slack.get("ts") or "")
        if not own or [slack.get("workspace"), slack.get("channel")] != key[:2]:
            continue
        if thread != key[2] or _ts(own) > _ts(ts) or command in owners or command in assigned:
            continue  # 다른 thread · 답글 뒤 글 · 배정된 일 = 손 0
        out.append(command)
    hit = list(dict.fromkeys(out))  # R1b — 이미 완료된 글도 «이 답글이 덮는 글» 로 센다(재접수 reconcile 근거)
    return hit, [command for command in hit if command not in done]

def _requeue(root, team, desk):
    state, records = desk.ex._state_records()
    room = desk.rs.capacity - len(dispatch.record.remaining(state, records))
    inbox = receive.SlackReceive(root, ack=lambda event: None, team=team)
    route.SlackRoute(root, receive=inbox, team=team)  # R1a — RoutingClient 가 route 장부의 thread·목적지를 영수에 남긴다
    full = sorted((e for e in inbox.latest().values() if e.get("state") == receive.FULL and e.get("key")),
                  key=lambda e: _ts(e["key"][2]))
    again = [inbox._recover(e["command"], entry=e) for e in full[:max(room, 0)]]
    return [v["command"] for v in again if v.get("state") == receive.DISPATCHED]

def settle(root, team, row):
    """게시 확정 1줄 → 판정 1개(state · completed · requeued). 예외는 이 함수 밖으로 나가지 않는다."""
    found = SLACK.match(str(row.get("command") or ""))
    if not found or not row.get("key"):
        return {"state": "대상 아님", "completed": [], "requeued": []}
    try:
        desk = dispatch.Dispatch(root, team)
        completed, (hit, todo) = [], _targets(*desk.ex._state_records(), list(row["key"]), found.group(3))
        for command in todo:
            grant = desk.complete(command)
            if grant.result == dispatch.OK:
                completed.append(command)
            elif grant.reason != "이미 완료 기록":
                raise RuntimeError("%s %s %s" % (command, grant.result, grant.reason))
        requeued = _requeue(root, team, desk) if hit else []  # R1b — 기확정 재확인도 남은 재접수를 멱등 reconcile
        return {"state": "완료" if completed else "완료 0", "completed": completed, "requeued": requeued}
    except Exception as exc:  # 하드 룰 20 — 판정 불가 1줄 · 게시 결과는 그대로
        line = "판정 불가: r1872 답글 완료 %s — %s" % (row.get("command"), exc)
        print(line, file=sys.stderr)
        return {"state": "판정 불가", "reason": line, "completed": [], "requeued": []}
