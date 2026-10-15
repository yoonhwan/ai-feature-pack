"""mirror_plan — 오빠 글 1건의 «계획»(수신자·본문)을 처음 한 번 정한다. 정본: DESIGN-slack-inbound-820.md §5 · DESIGN-slack-readonly-share-20261008 §4-r2 B.

planner 수신자는 이름이 아니라 역할 표식 `@planner` — 이름은 보낼 때마다 live_planner 가 정한다(승계 뒤 미전달 건도 현역에게 간다).
슬랙에 질문을 되던지지 않는다(되묻기 0) — 번호를 못 찾거나 질문이 여럿이면 원문 그대로 @planner 에 보낸다.
"""
import argparse
import sys
from pathlib import Path

import mirror_deliver as md
import mirror_inbound as ib
import mirror_lib as lib
import mirror_questions as mq
import mirror_share as ms

CONFIRM = {"확인", "확인했어요", "확인함", "ok", "OK"}
PLANNER = ms.PLANNER_ROLE


def is_team_thread(a: argparse.Namespace, thread: str) -> bool:
    """스레드 맵에서 이 thread_ts 의 키가 `team:` 로 시작하나 — 팀 뿌리 글 판별."""
    threads = md.load_threads(Path(a.state_dir) / f"byz_slack_threads.{a.channel}.json")
    return any(k.startswith("team:") and v == thread for k, v in threads.items())


def thread_link(a: argparse.Namespace, token: str, thread: str) -> str:
    try:
        return str(lib.api_call(a.api_base, token, "chat.getPermalink", {"channel": a.channel, "message_ts": thread}, get=True)["permalink"])
    except lib.MirrorError as e:  # 보이게: 링크 대신 ts
        print(f"ERROR: 스레드 링크 조회 실패: {e} — ts 로 대신 적음", file=sys.stderr)
        return f"ts={thread}"


def plan(a: argparse.Namespace, token: str, qpath: Path, m: dict[str, object]) -> dict[str, object]:
    p = _plan(a, token, qpath, m)
    if not getattr(a, "to_key", ""):
        return p
    # --to-key 고정 모드(R205 H1 · R238): 질문 좌석·추정 좌석 포함 모든 수신이 명부 키가 가리키는 좌석 1곳뿐이다. 질문 상태(delivered·confirm 종료)는
    # «그 좌석에 전달됨» 이 아니라 desk 도달이므로 전진시키지 않는다 — 질문 보드는 원래 좌석 경로의 몫이다.
    return {**{k: v for k, v in p.items() if k != "confirm"}, "recips": [PLANNER], "q": None}


def _plan(a: argparse.Namespace, token: str, qpath: Path, m: dict[str, object]) -> dict[str, object]:
    text, thread = ib.unescape(str(m.get("text", ""))).strip(), str(m["thread_ts"])
    base: dict[str, object] = {"thread": thread, "done": {}, "attempt": {}, "q": None}
    if not thread:
        return {**base, "recips": [PLANNER], "text": f"오빠 새 글 (Slack) — 원문:\n{text}"}
    data = mq.load(qpath)
    opened, given = mq.in_thread(data, thread), mq.in_thread(data, thread, "delivered")
    qs = opened + given
    hit = mq.Q_PREFIX.match(text)
    if hit:  # 번호를 적었으면 그 질문이거나, 없으면 «추정하지 않고» 원문 그대로 planner 에게(해석 실패 사실을 본문 1줄로)
        text = text[hit.end():]
        qs = [(s, e) for s, e in qs if s == int(hit.group(1))]
        if not qs:
            return {**base, "recips": [PLANNER], "text": f"오빠(Slack) 글인데 질문 번호 Q{hit.group(1)} 를 찾지 못했어요 — 원문:\n{text}"}
    if len(qs) > 1:
        return {**base, "recips": [PLANNER], "text": f"오빠(Slack) 글인데 질문이 {len(qs)}개라 좌석을 정하지 못했어요 — 원문:\n{text}"}
    if len(qs) == 1:
        seq, e = qs[0]
        answer = ib.resolve_pick(text, list(e.get("options", [])))
        plan = {**base, "recips": [str(e["seat"]), PLANNER], "q": seq, "text": f"오빠(Slack) 발화 — 원문 · {e['key']} 스레드 · 질문 Q{seq}:\n{answer}"}
        if text in CONFIRM and not opened:
            plan["confirm"] = seq
        return plan
    if is_team_thread(a, thread):  # 팀 뿌리 글 스레드(판정 623 r2-A): 질문 없는 스레드 — 마지막 봇 글로 좌석을 추정하지 않고 planner 에게만 원문 + 스레드 링크
        return {**base, "recips": [PLANNER], "text": f"오빠(Slack) 팀 스레드 답글 — 원문:\n{text}\n스레드: {thread_link(a, token, thread)}"}
    seat = ib.inferred_seat(lib.paged(a.api_base, token, "conversations.replies", {"channel": a.channel, "ts": thread, "limit": 200}))
    return {**base, "recips": [seat, PLANNER] if seat else [PLANNER], "text": f"오빠(Slack) 발화 (추정: 열린 질문 없음) — 원문:\n{text}"}
