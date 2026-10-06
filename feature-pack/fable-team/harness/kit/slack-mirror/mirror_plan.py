"""mirror_plan — 오빠 글 1건의 «계획»(수신자·본문·되묻기)을 처음 한 번 정한다. 정본: DESIGN-slack-inbound-820.md §5."""
import argparse
from pathlib import Path

import mirror_inbound as ib
import mirror_lib as lib
import mirror_questions as mq

CONFIRM = {"확인", "확인했어요", "확인함", "ok", "OK"}


def plan(a: argparse.Namespace, token: str, qpath: Path, m: dict[str, object]) -> dict[str, object]:
    text, thread = ib.unescape(str(m.get("text", ""))).strip(), str(m["thread_ts"])
    planner = ib.planner_seat(Path(a.seats_file))
    base: dict[str, object] = {"thread": thread, "done": {}, "attempt": {}, "q": None}
    if not thread:
        return {**base, "recips": [planner], "text": f"오빠 새 글 (Slack) — 원문:\n{text}"}
    data = mq.load(qpath)
    opened, given = mq.in_thread(data, thread), mq.in_thread(data, thread, "delivered")
    qs = opened + given
    hit = mq.Q_PREFIX.match(text)
    if hit:  # 번호를 적었으면 그 질문이거나, 없으면 «추정하지 않고» 되묻는다
        text = text[hit.end():]
        qs = [(s, e) for s, e in qs if s == int(hit.group(1))]
        if not qs:
            return {**base, "recips": [planner], "ask": f"Q{hit.group(1)} 질문이 이 스레드에 없어요 — 열린 질문 번호를 확인해 주세요",
                    "text": f"오빠(Slack) 글인데 질문 번호 Q{hit.group(1)} 를 찾지 못했어요 — 원문:\n{text}"}
    if len(qs) > 1:
        return {**base, "recips": [planner], "ask": "질문이 여러 개 열려 있어요 — 「Q질문번호 답」 형태로 다시 답해 주세요",
                "text": f"오빠(Slack) 글인데 질문이 {len(qs)}개라 좌석을 정하지 못했어요 — 원문:\n{text}"}
    if len(qs) == 1:
        seq, e = qs[0]
        who = [str(e["seat"])] + ([planner] if planner != e["seat"] else [])
        answer = ib.resolve_pick(text, list(e.get("options", [])))
        plan = {**base, "recips": who, "q": seq, "text": f"오빠(Slack) 발화 — 원문 · {e['key']} 스레드 · 질문 Q{seq}:\n{answer}"}
        if text in CONFIRM and not opened:
            plan["confirm"] = seq
        return plan
    seat = ib.inferred_seat(lib.paged(a.api_base, token, "conversations.replies", {"channel": a.channel, "ts": thread, "limit": 200}))
    who = [seat] + ([planner] if planner != seat else []) if seat else [planner]
    return {**base, "recips": who, "text": f"오빠(Slack) 발화 (추정: 열린 질문 없음) — 원문:\n{text}"}
