#!/usr/bin/env python3
"""ops_intake_write — mini(aina) 접수 카드 작성기. JSON stdin → 카드 1장 + [OPS-NEW] 쪽지 1통.

계약(기획 §3 ③ · §4 · §6):
  · 스키마가 틀리면 rc2 — 카드 0 · 쪽지 0 (조용한 통과 없음)
  · 카드 속 비밀·개인정보는 값 0 — `***`·`<이메일>`·`<전화번호>` 로 가리고 «마스킹 n건: 종류» 만 남긴다
  · 머리에 `secrets_masked: <정수>` 필수 칸 — 이 맥이 이 칸을 못 읽으면 등록 차단(§6)
  · 폭주 한도 — 같은 사용자 10분 5건 · 같은 채널 1시간 30건을 넘으면 rc3 «잠시 뒤» (카드 0)

사용: python3 ops_intake_write.py < card.json        rc 0 ok · 2 스키마/규칙 · 3 한도 · 5 쪽지 실패
env: OPS_INTAKE_ROOT · OPS_MBOX_SH · OPS_MASTER_SEAT · OPS_TOOL_SEAT · FT_NOW(시험) · FT_BIN(비밀 규칙)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import ops_intake_common as c

USER_LIMIT, USER_WINDOW = 5, 600
CHANNEL_LIMIT, CHANNEL_WINDOW = 30, 3600
CARD_RX = re.compile(r"^OPS-(\d{8})-(\d{3})\.md$")


def next_id(today: str) -> str:
    """오늘 날짜의 다음 접수번호 — 있는 카드의 최대값 + 1."""
    seen = [int(m.group(2)) for p in c.sub("inbox").iterdir() if (m := CARD_RX.match(p.name)) and m.group(1) == today]
    return f"OPS-{today}-{(max(seen) + 1) if seen else 1:03d}"


def check_limits(user: str, channel: str) -> tuple[dict, Path, int]:
    """창 안 건수가 한도 이상이면 rc3 — 이번 건은 만들지 않는다."""
    now = c.now_epoch()
    path = c.sub("state") / "limits.json"
    st = c.read_json(path, {"user": {}, "channel": {}})
    for key, val, limit in (("user", user, USER_LIMIT), ("channel", channel, CHANNEL_LIMIT)):
        window = USER_WINDOW if key == "user" else CHANNEL_WINDOW
        stamps = [t for t in st.get(key, {}).get(val, []) if now - int(t) < window]
        st.setdefault(key, {})[val] = stamps
        if len(stamps) >= limit:
            c.write_json(path, st)
            raise c.IntakeError(f"한도 초과 — {key} 최근 {window}초 {len(stamps)}건 · 잠시 뒤 다시", 3)
    return st, path, now


def record(path: Path, st: dict, user: str, channel: str, now: int) -> None:
    for key, val in (("user", user), ("channel", channel)):
        window = USER_WINDOW if key == "user" else CHANNEL_WINDOW
        st.setdefault(key, {})[val] = [t for t in st[key].get(val, []) if now - int(t) < window] + [now]
    c.write_json(path, st)


def card_text(ops_id: str, doc: dict, masked: dict, kinds: list[str]) -> str:
    att = "\n".join(f"- {a}" for a in masked.get("attachments") or []) or "- 없음"
    rows = [
        f"ops_id: {ops_id}",
        f"slack_channel: {doc['slack_channel']}",
        f"thread_ts: {doc['thread_ts']}",
        f"user_id: {doc['user_id']}",
        f"kind: {doc['kind']}",
        f"product: {masked['product']}",
        f"urgency: {masked.get('urgency') or '-'}",
        f"secrets_masked: {len(kinds)}",
        "---",
        "## 제목",
        masked["title"],
        "## 증상·요청",
        masked["symptom"],
        "## 재현",
        masked.get("repro") or "- 없음",
        "## 기대 동작",
        masked.get("expect") or "- 없음",
        "## 첨부",
        att,
        f"[마스킹 {len(kinds)}건: {c.kind_summary(kinds)}]",
        "",
    ]
    return "\n".join(rows)


def main() -> int:
    raw = sys.stdin.read()
    try:
        doc = c.validate(json.loads(raw or "null"))
        today = c.now_iso()[:10].replace("-", "")
        st, path, now = check_limits(doc["user_id"], doc["slack_channel"])
        fields = {k: doc.get(k, "") for k in ("product", "urgency", "title", "symptom", "repro", "expect")}
        masked: dict = {}
        kinds: list[str] = []
        for k, v in fields.items():
            masked[k], hit = c.mask_text(v or "")
            kinds += hit
        masked["attachments"] = []
        for a in doc.get("attachments") or []:
            m, hit = c.mask_text(a)
            masked["attachments"].append(m)
            kinds += hit
        ops_id = next_id(today)
        card = c.sub("inbox") / f"{ops_id}.md"
        card.write_text(card_text(ops_id, doc, masked, kinds), encoding="utf-8")
        body = "\n".join([
            f"[OPS-NEW] {ops_id} · kind={doc['kind']} product={masked['product']}",
            f"카드(mini): {card}",
            f"제목: {masked['title'][:120]}",
            f"마스킹 {len(kinds)}건: {c.kind_summary(kinds)}",
            f"스레드 ts: {doc['thread_ts']} · 채널 {doc['slack_channel']}",
        ])
        try:
            c.mbox_send(c.env_path("OPS_MASTER_SEAT", "byz-opsintake-master-claude#0"), c.env_path("OPS_TOOL_SEAT", "byz-opsintake-tool-cmd#0"), body)
        except c.IntakeError:
            card.unlink(missing_ok=True)  # 쪽지 0 이면 카드도 0 — 다시 오면 같은 번호로 새로 쓴다
            raise
        record(path, st, doc["user_id"], doc["slack_channel"], now)
        print(f"CARD {ops_id} {card} masked={len(kinds)}")
        return 0
    except c.IntakeError as e:
        print(f"STOP {e}", file=sys.stderr)
        return e.rc


if __name__ == "__main__":
    sys.exit(main())
