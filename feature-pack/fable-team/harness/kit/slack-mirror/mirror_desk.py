"""mirror_desk — #byz-planner 로 올라가는 긴급 행을 #byz-desk 에도 «같은 패스에서» 올린다 (r1280).

사건: desk(Claude 좌석)의 수동 relay 가 유일한 다리였고 desk 가 멈추면(11-01 14:33~15:00) 끊겼다. hermes 미러는 Claude 와 무관하게 돈다.
· 새 인자 --desk-channel(기본 빈 값 = 지금 동작 그대로) · 라벨이 HIL·BLOCK·긴급 인 행만 중복 게시(desk_dup) · 글은 늘 사람 멘션.
· 발신자 표(--urgent-from): 결정 대기 경보·API 장애 알림은 «원 글자를 안 바꾸고» 미러 안에서만 긴급으로 다룬다(필터·라벨이 같은 함수).
· 두 채널 exactly-once: 대상 스레드 ts 를 item["threads"] 에 고정해 pending 에 저장하고, 채널별 완료는 item["done"] 에 남긴다.
"""
from __future__ import annotations  # mini python 3.9 — `X | None` 주석 import TypeError 방지

from collections.abc import Callable
from pathlib import Path

import mirror_lib as lib
import mirror_questions as mq
from mirror_deliver import Deliverer

DESK_LABELS = ("HIL", "BLOCK", "긴급")
DEFAULT_URGENT_FROM = "ft-api-outage,ft-decision-count"
NOT_ALARM = "[재개]"  # ft-api-outage 가 좌석마다 보내는 재개 쪽지 — 장애 알림이 아니다


def add_args(p) -> None:
    p.add_argument("--desk-channel", default="", help="긴급 행(HIL·BLOCK·긴급)을 중복 게시할 desk 채널 ID (기본 빈 값 = 안 올림 · r1280)")
    p.add_argument("--desk-mention", default="", help="desk 글에 붙일 Slack 사용자 ID (기본 = --mention)")
    p.add_argument("--urgent-from", default=DEFAULT_URGENT_FROM, help="이 발신자의 행은 미러 안에서 긴급으로 다룬다(쉼표 목록 · desk 채널이 있을 때만)")


def senders(a) -> frozenset[str]:
    if not getattr(a, "desk_channel", ""):
        return frozenset()
    return frozenset(s.strip() for s in str(getattr(a, "urgent_from", DEFAULT_URGENT_FROM)).split(",") if s.strip())


def urgent_from(row: dict[str, object], names: frozenset[str]) -> bool:
    """발신자 표에 있는 행인가 — 수신 필터(is_target)와 라벨 결정(row_label)이 같은 이 함수를 쓴다."""
    if str(row.get("from", "")) not in names:
        return False
    return not lib.classify(str(row.get("body", "")))[1].lstrip().startswith(NOT_ALARM)


def row_label(row: dict[str, object], names: frozenset[str]) -> tuple[str, str]:
    label, text = lib.classify(str(row.get("body", "")))
    return ("긴급", text) if label == "보고" and urgent_from(row, names) else (label, text)


def is_desk_dup(row: dict[str, object], names: frozenset[str]) -> bool:
    return bool(names) and row_label(row, names)[0] in DESK_LABELS


def desk_text(text: str, mention: str) -> str:
    """사람 판정이 0인 정리 글에서는 멘션을 빼고, 그 밖에는 있던 멘션을 보존하거나 추가한다."""
    first = text.split("\n", 1)[0]
    if "[정리]" in first and "할 일 없음" in text and "사람 결정 0" in text:
        return text.replace(f"<@{mention}> ", "", 1) if mention else text
    if not mention or f"<@{mention}>" in text:
        return text
    first, _, rest = text.partition("\n")
    return f"{first}\n<@{mention}> 확인해 주세요" + (f"\n{rest}" if rest else "")


def urgent_text(text: str) -> str:
    return f"[긴급] {text}"


class Desk:
    def __init__(self, a, token: str):
        self.channel, self.mention = a.desk_channel, getattr(a, "desk_mention", "") or a.mention
        self.deliv = Deliverer(a.api_base, token, a.desk_channel, Path(a.state_dir) / f"byz_slack_threads.{a.desk_channel}.json")  # 팀 뿌리 모드 0 — 키 1개 = 스레드 1개

    def text(self, item: dict[str, object]) -> str:
        return desk_text(str(item["text"]), self.mention)

    def dry_print(self, item: dict[str, object]) -> None:
        print(f"[desk-dup {self.channel} thread {item.get('key')}]\n{self.text(item)}\n---")

    def send_both(self, main: Deliverer, item: dict[str, object], resume: bool, save: Callable[[], None] | None,
                  send_main: Callable[[dict[str, object], bool, str, dict[str, object] | None], None] | None = None) -> None:
        """메인 → desk 순서. 채널마다 스레드 ts 를 «먼저» 고정·저장하고, 끝낸 채널은 done 에 남긴다(실패는 그대로 raise · 재시작이 이어간다)."""
        threads, done = item.setdefault("threads", {}), item.setdefault("done", [])
        for name, d, it in (("main", main, item), ("desk", self.deliv, {**item, "text": self.text(item)})):
            if name in done:
                continue
            if name in threads:
                ts, ctx = str(threads[name]), None
            else:
                ts, ctx = d.resolve(it, resume)
                threads[name] = ts
                save and save()
            if name == "main" and send_main:
                send_main(it, resume, str(threads[name]), ctx)
            else:
                d.send_fixed(it, str(threads[name]), resume, ctx)
            done.append(name)
            save and save()


def send_item(mirror, item: dict[str, object], resume: bool, fixed_ts: str | None = None,
              ctx: dict[str, object] | None = None) -> None:
    q = item.get("question")
    if isinstance(q, dict):
        ts = fixed_ts or mirror.deliv.thread_ts(item, resume)
        if mq.on_roster(str(q.get("seat", "")), Path(mirror.planner_seats).parent):
            mq.add(mirror.qpath, int(str(item["seq"])), {**q, "thread_ts": ts})
        mq.update_board(mirror.qpath, mirror.a.api_base, mirror.token, mirror.a.channel, mirror.planner_seats)
    if fixed_ts:
        mirror.deliv.send_fixed(item, fixed_ts, resume, ctx)
    else:
        mirror.deliv.send(item, resume)


def deliver(mirror, st: dict[str, object], item: dict[str, object], resume: bool = False) -> None:
    if mirror.a.dry_run:
        print(f"[thread {item.get('key')}]\n{item['text']}\n---")
        if item.get("desk_dup") and mirror.desk:
            mirror.desk.dry_print(item)
        st["last_seq"] = item["seq"]
    else:
        st["pending"] = item
        lib.save_state(mirror.state_path, st)
        if item.get("desk_dup") and mirror.desk:
            mirror.desk.send_both(mirror.deliv, item, resume, lambda: lib.save_state(mirror.state_path, st), mirror._send_item)
        else:
            mirror._send_item(item, resume)
        st.update(last_seq=item["seq"], pending=None)
        lib.save_state(mirror.state_path, st)
    mirror.posted += 1
