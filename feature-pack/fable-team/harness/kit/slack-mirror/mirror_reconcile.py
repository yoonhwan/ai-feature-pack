"""desk 방과 mbox 전송 기록의 주기 대조."""
from __future__ import annotations

import os
import sys

import mirror_backlog as bl
import mirror_deliver
import mirror_desk as desk
import mirror_lib as lib
import mirror_marker as markers

INTERVAL_ENV = "FT_RECONCILE_SEC"
WINDOW_ENV = "FT_RECONCILE_WINDOW_SEC"
FIRST_ENV = "FT_RECONCILE_FIRST_SEC"
MAX_ENV = "FT_RECONCILE_MAX"
MIN_AGE_SEC = 120
RECHECK_MAX = 10


def _setting(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError as e:
        raise lib.MirrorError(f"{name} 형식 오류") from e


def _epoch(row: dict[str, object]) -> float | None:
    try:
        return float(str(row["ts"]))
    except (KeyError, TypeError, ValueError):
        return None


def _team(row: dict[str, object]) -> str:
    sender = str(row.get("from", ""))
    parts = sender.split("-")
    return parts[1] if len(parts) > 1 and parts[0] == "byz" else sender


def _expects(row: dict[str, object], mirror) -> bool:
    return bl.is_target(row, mirror.seat, mirror.urgent, mirror.urgent_senders) and desk.wants_desk(
        row, mirror.urgent_senders, True
    )


def _contains(mirror, threads: dict[str, str], roots: list[tuple[str, str]] | None,
              key: str, seq: int, cursor: str | None) -> tuple[bool, str | None, list[tuple[str, str]] | None]:
    marker = f"bodies/{seq}.txt@mbox"
    ts = threads.get(key)
    if ts:
        params: dict[str, object] = {"channel": mirror.desk.channel, "ts": ts, "limit": 200}
        if cursor:
            params["cursor"] = cursor
        payload = lib.api_call(mirror.a.api_base, mirror.token, "conversations.replies", params, get=True)
        messages = payload.get("messages", [])
        texts = [str(m.get("text", "")) for m in messages if isinstance(m, dict)] if isinstance(messages, list) else []
        if markers.has_marker(texts, marker):
            return True, None, roots
        if payload.get("has_more"):
            meta = payload.get("response_metadata")
            next_cursor = str(meta.get("next_cursor", "")) if isinstance(meta, dict) else ""
            if not next_cursor:
                raise lib.MirrorError("conversations.replies has_more 이지만 next_cursor 가 없음")
            return False, next_cursor, roots
        return False, None, roots
    if roots is None:
        roots = lib.channel_roots(mirror.a.api_base, mirror.token, mirror.desk.channel, limit=100)
    return any(markers.has_marker([text], marker) for _, text in roots), None, roots


def _alert(mirror, missing: dict[str, dict[str, object]], new: list[str], sent: dict[str, int],
           arrived: dict[str, int], now: float) -> None:
    by_team: dict[str, list[int]] = {}
    for seq in new:
        item = missing[seq]
        by_team.setdefault(str(item["team"]), []).append(int(seq))
    lines = ["[긴급] 결정 요청 누락 대조 — planner 에 보냈는데 desk 방에 없음:"]
    for team in sorted(by_team):
        nums = sorted(by_team[team])
        seqs = ",".join(f"#{n}" for n in nums[:5])
        if len(nums) > 5:
            seqs += f" 외 {len(nums) - 5}건"
        lines.append(f"{team} 보냄 {sent.get(team, 0)} · 도착 {arrived.get(team, 0)} · 빠짐 {seqs}")
    lines.extend((f"<@{mirror.desk.mention}> 확인해 주세요", f"(mirror · #RECON-{int(now)})"))
    lib.post(mirror.a.api_base, mirror.token, mirror.desk.channel, "\n".join(lines))


def reconcile(mirror, st: dict[str, object], now: float) -> None:
    """due 대조를 수행한다. 호출 전 reconcile_at을 저장해 실패 뒤 즉시 재시도하지 않는다."""
    interval = _setting(INTERVAL_ENV, 600)
    if interval <= 0 or now - float(st.get("reconcile_at", 0) or 0) < interval:
        return
    st["reconcile_at"] = now
    lib.save_state(mirror.state_path, st)

    first = bool(st.get("reconcile_first", True))
    window = _setting(FIRST_ENV, 86400) if first else _setting(WINDOW_ENV, 7200)
    maximum = max(0, _setting(MAX_ENV, 20))
    start, mature = now - window, now - MIN_AGE_SEC
    last_seq = int(str(st.get("last_seq", 0)))
    cursor = min(int(str(st.get("reconcile_cursor", 0))), last_seq)
    rows = sorted(mirror.rows, key=lambda r: int(str(r.get("seq", 0))))
    threads = mirror_deliver.load_threads(mirror.desk.deliv.threads_path)
    held = {str(k): v for k, v in dict(st.get("reconcile_held") or {}).items() if isinstance(v, dict)}
    missing = {str(k): v for k, v in dict(st.get("reconcile_missing") or {}).items() if isinstance(v, dict)}
    alarmed = {str(k): float(v) for k, v in dict(st.get("reconcile_alarmed") or {}).items()
               if now - float(v) < 86400}
    missing = {str(k): v for k, v in missing.items()
               if isinstance(v, dict) and now - float(v.get("first_epoch", now)) < 86400}
    roots = None
    sent: dict[str, int] = {}
    arrived: dict[str, int] = {}

    def inspect(seq: str, team: str, key: str, held_cursor: str | None = None) -> None:
        nonlocal roots
        sent[team] = sent.get(team, 0) + 1
        found, next_cursor, roots = _contains(mirror, threads, roots, key, int(seq), held_cursor)
        if found:
            missing.pop(seq, None)
            held.pop(seq, None)
            arrived[team] = arrived.get(team, 0) + 1
        elif next_cursor:
            held[seq] = {"key": key, "team": team, "cursor": next_cursor}
        else:
            missing.setdefault(seq, {"team": team, "key": key, "first_epoch": now})
            held.pop(seq, None)

    # 기존 누락표와 이어갈 페이지는 새 후보와 별도인 10건 예산을 쓴다.
    rechecks = sorted({*missing, *held}, key=int)[:RECHECK_MAX]
    for seq in rechecks:
        item = held.get(seq) or missing.get(seq)
        if not isinstance(item, dict):
            continue
        inspect(seq, str(item.get("team", "")), str(item.get("key", "")),
                str(item.get("cursor")) if item.get("cursor") else None)

    new_checked = 0
    for row in rows:
        seq = int(str(row.get("seq", 0)))
        if seq <= cursor or seq > last_seq:
            continue
        when = _epoch(row)
        if not _expects(row, mirror):
            cursor = seq
            continue
        if when is None or when < start:
            cursor = seq
            continue
        if when > mature:
            break
        if str(seq) in missing or str(seq) in held:
            cursor = seq
            continue
        if new_checked >= min(maximum, RECHECK_MAX):
            break
        body = str(row.get("body", ""))
        text = lib.classify(body)[1]
        key, team = lib.thread_key(row, text), _team(row)
        inspect(str(seq), team, key)
        cursor = seq
        new_checked += 1

    st["reconcile_cursor"] = cursor
    st["reconcile_held"] = held
    st["reconcile_missing"] = missing
    st["reconcile_alarmed"] = alarmed
    st["reconcile_first"] = first
    remaining = any(cursor < int(str(r.get("seq", 0))) <= last_seq and _epoch(r) is not None and
                    start <= float(_epoch(r)) <= now and _expects(r, mirror) for r in rows)
    unprocessed = any(int(str(r.get("seq", 0))) > last_seq and _epoch(r) is not None and
                       start <= float(_epoch(r)) <= now and _expects(r, mirror) for r in rows)
    if first and not remaining and not held and not unprocessed:
        st["reconcile_first"] = False

    new = sorted((seq for seq in missing if seq not in alarmed), key=int)
    if new:
        _alert(mirror, missing, new, sent, arrived, now)
        for seq in new:
            alarmed[seq] = now
        st["reconcile_alarmed"] = alarmed
    lib.save_state(mirror.state_path, st)
    teams = ",".join(f"{team}:{sent[team]}/{arrived.get(team, 0)}" for team in sorted(sent)) or "-"
    print(f"reconcile window={window} cursor={cursor} teams={teams} missing={len(missing)} new={len(new)} held={len(held)}", file=sys.stderr)
