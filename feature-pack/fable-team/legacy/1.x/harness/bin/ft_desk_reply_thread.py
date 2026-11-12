#!/usr/bin/env python3
# pyright: basic
"""ft_desk_reply_thread.py — r1764: desk 감시 장부의 세 번째 갈래(스레드 새 글)와 수동 닫기.
CLI(ft_desk_reply_wake.py 가 넘긴다):
  `--register-thread <스레드 ts> <사유키>` = kind=thread 줄 등록(끝 시각 = 등록 + 24h · 같은 ts 같은 키 = 멱등 · 다른 키 = rc3)
  `--close <질문ts|사유키> [--reason <낱말>]` = 열린 줄(종류 무관) 닫기 · closed=«manual:<사유>» · 키가 열린 줄 여럿이면 전부 · 0개 = rc3
점검(ft_desk_reply_wake.scan 이 부른다): thread 줄마다 `ft_oppa_slack_check.py --reply-only <ts> --after <notified_ts|q_ts>` 1회
  → 그 시각 «뒤» 첫 오빠 글 1개 → `_desk` 로 `[오빠 새 글] <사유키> ts=<글>` 1통 · notified_ts 갱신 · 줄은 열린 채(다음 글이 오면 또 1통).
  끝 시각 경과 = 조용히 closed(«expired») · 쪽지 0.
장부 잠금·읽기·쓰기·쪽지·루트는 ft_desk_reply_wake.py 것을 h 로 받는다(같은 줄에서 겹치지 않게 한 파일이 잠금을 쥔다).
"""
import json
import re
import subprocess
import sys

TO, DAY = 7, 86400  # 7초·재시도 1(하드 룰 12) · 24시간
TS, KEY = re.compile(r"[0-9]+\.[0-9]{6}$"), re.compile(r"[a-z0-9][a-z0-9._-]{0,63}$")  # r1591 KEY 와 같은 꼴


def bad(m: str) -> None:
    print("ft-desk-reply-thread 판정 불가 — " + m, file=sys.stderr)


def judge_after(check: str, q: str, after: str) -> tuple[int, str]:  # 7초 · 재시도 1 · rc3 = 새 글 없음(정상 열린 줄)
    last = (1, "점검 도구 실행 실패")
    for _ in range(2):
        try:
            r = subprocess.run([sys.executable, check, "--reply-only", q, "--after", after], capture_output=True, text=True, timeout=TO)
        except subprocess.SubprocessError:
            last = (124, "조회 %d초 초과" % TO)
            continue
        if r.returncode in (0, 3):
            return r.returncode, (r.stdout or r.stderr)
        last = (r.returncode, (r.stdout or r.stderr))
    return last


def register_thread(h, a: list, now: float) -> int:  # A1 · 같은 ts 같은 키 = 멱등 · 다른 키 = 거절
    row = {"q_ts": a[0] if a else "", "kind": "thread", "key": a[1] if len(a) > 1 else "", "at": int(now), "deadline": int(now + DAY), "state": "open"}
    if len(a) != 2 or not TS.match(row["q_ts"]) or not KEY.match(row["key"]):
        print("감시 등록 실패 — 사용: --register-thread <스레드 ts(1794295513.494289)> <사유키(r1590)>", file=sys.stderr)
        return 3
    try:
        fh = h.lock(h.led)
    except OSError as e:
        print("감시 등록 실패 — 장부 잠금 실패(%s): %s" % (type(e).__name__, h.led), file=sys.stderr)
        return 3
    try:
        rows = h.ledger(h.led)
        if rows is None:
            print("감시 등록 실패 — 장부를 못 읽음: %s" % h.led, file=sys.stderr)
            return 3
        old = next((r for r in rows if r.get("q_ts") == row["q_ts"]), None)
        if old is not None:
            if old.get("kind") == "thread" and old.get("key") == row["key"]:
                print("등록 %s q_ts=%s 끝=%s (이미 등록 — 중복 0)" % (row["key"], row["q_ts"], old.get("deadline")))
                return 0
            print("감시 등록 실패 — 같은 스레드 ts 가 다른 값으로 이미 등록됨(%s)" % (old.get("key") or old.get("h")), file=sys.stderr)
            return 3
        if not h.ledger(h.led, rows + [row]):
            print("감시 등록 실패 — 장부 쓰기 실패: %s" % h.led, file=sys.stderr)
            return 3
    finally:
        fh.close()
    print("등록 %s q_ts=%s 끝=%d" % (row["key"], row["q_ts"], row["deadline"]))
    return 0


def scan_threads(h, rows: list, now: float) -> tuple[dict, int, int, int]:  # A2·A3 · (바꿀 칸, 알림, 닫힘, 판정불가)
    up: dict[str, dict] = {}
    sent = shut = nbad = 0
    open_rows = [(i, r) for i, r in enumerate(rows) if r.get("kind") == "thread" and r.get("state") != "closed"]
    for _, row in open_rows[: max(1, h.maxn)]:
        q, key = row.get("q_ts"), row.get("key")
        if not isinstance(q, str) or not isinstance(key, str) or not TS.match(q) or not KEY.match(key):
            bad("thread 줄 꼴 아님: %s" % json.dumps(row, ensure_ascii=False)[:120])
            nbad += 1
            continue
        if now >= float(row.get("deadline") or 0):  # A3 끝 시각 경과 = 조용히 닫힘(쪽지 0)
            up[q] = {"state": "closed", "closed": "expired"}
            shut += 1
            continue
        tgt = h.seat.get("_desk")
        if not tgt:
            bad("_desk 없음 — %s 알림 0(다음 주기 재시도)" % key)
            nbad += 1
            continue
        rc, out = judge_after(h.check, q, row.get("notified_ts") or q)  # A2 «이 시각 뒤» 첫 오빠 글
        if rc == 3:  # 새 글 없음 = 정상 열린 줄
            continue
        m = re.search(r"reply=([0-9]+\.[0-9]+)$", out.strip().splitlines()[-1]) if rc == 0 and out.strip() else None
        if not m:  # A6 조회 실패·토큰 없음 = «판정 불가» 1줄 · 기록 0 · 다음 주기 재시도
            bad("%s %s" % (key, (out.strip().splitlines() or ["REPLY-SEEN 줄 없음"])[-1][:160]))
            nbad += 1
            continue
        if row.get("notified_ts") == m.group(1):
            continue
        if h.send(h.base, tgt, "[오빠 새 글] %s ts=%s" % (key, m.group(1))):
            bad("쪽지 발신 실패 — %s 알림 0(다음 주기 재시도)" % key)
            nbad += 1
            continue
        up[q] = {"notified_ts": m.group(1), "notified_at": int(now)}  # 줄은 열린 채(다음 글이 오면 또 1통)
        sent += 1
    return up, sent, shut, nbad


def close(h, a: list, now: float) -> int:  # A4 · 잠금 안에서 다시 읽고 쓰기 · 0개 = rc3(장부 바이트 그대로)
    args, reason = list(a), "cli"
    if "--reason" in args:
        i = args.index("--reason")
        if len(args) != i + 2 or not KEY.match(args[i + 1]):
            print("감시 닫기 실패 — 사용: --close <질문ts|사유키> [--reason <낱말>]", file=sys.stderr)
            return 3
        reason, args = args[i + 1], args[:i]
    if len(args) != 1 or not (TS.match(args[0]) or KEY.match(args[0])):
        print("감시 닫기 실패 — 사용: --close <질문ts|사유키> [--reason <낱말>]", file=sys.stderr)
        return 3
    tgt = args[0]
    try:
        fh = h.lock(h.led)
    except OSError as e:
        print("감시 닫기 실패 — 장부 잠금 실패(%s): %s" % (type(e).__name__, h.led), file=sys.stderr)
        return 1
    try:
        rows = h.ledger(h.led)
        if rows is None:
            print("감시 닫기 실패 — 장부를 못 읽음: %s" % h.led, file=sys.stderr)
            return 1
        n = 0
        for r in rows:
            if r.get("state") != "closed" and tgt in (r.get("q_ts"), r.get("key"), r.get("h")):
                r.update({"state": "closed", "closed": "manual:" + reason})
                n += 1
        if not n:
            print("감시 닫기 실패 — 열린 줄 없음: %s" % tgt, file=sys.stderr)
            return 3
        if not h.ledger(h.led, rows):
            print("감시 닫기 실패 — 장부 쓰기 실패: %s" % h.led, file=sys.stderr)
            return 1
        print("닫힘 %d줄 — %s (manual:%s)" % (n, tgt, reason))
        return 0
    finally:
        fh.close()


def main(argv: list) -> int:  # 단독 실행은 하지 않는다 — 갈래 호출자는 ft_desk_reply_wake.py 하나다
    print("ft_desk_reply_thread 사용: ft_desk_reply_wake.py --register-thread <ts> <사유키> | --close <질문ts|사유키> [--reason <낱말>]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
