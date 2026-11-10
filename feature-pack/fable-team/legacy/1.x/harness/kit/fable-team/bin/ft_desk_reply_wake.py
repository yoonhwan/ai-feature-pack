#!/usr/bin/env python3
# pyright: basic
"""ft_desk_reply_wake.py — r1574: desk 승인 질문의 오빠 답글을 비모델(ft-stall-scan 120초 주기)이 찾아 desk 를 깨운다.
CLI: (인자 없음) 점검 · `--register <질문ts> <h번호> <sha40>` 등록(desk 가 Slack 질문 글을 올린 직후 · 끝 시각 = 등록 + 24h)
점검 = 열린 줄마다 ft_oppa_slack_check 1회(7초 · 재시도 1) → SLACK-OK 이면 seats-planner.json `_desk` 로 `[오빠 답글] h<N> ts=<답글> → 실행 차례` 1통(같은 답글 ts = 1통).
끝 = h 실행 기록(<HIL_DIR>/h<N>.ran) 생성 또는 끝 시각 경과(경과는 `_master` 로 `[답글 없음 24시간]` 1통) · 장부 = <루트>/.fable-team/state/desk-reply-wait.jsonl(open|notified|closed).
env: FT_ROOT · FT_NOW · FT_MBOX_SH · FT_SEATS_PLANNER · FT_SLACK_CHECK · HIL_DIR · FT_DESK_REPLY_LEDGER · FT_DESK_REPLY_MAX(4)
rc: 0 정상 · 1 발신·쓰기 실패 · 2 판정 불가(루트·장부·명부) · 3 등록 거절
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

TS, SHA, HN = re.compile(r"[0-9]+\.[0-9]{6}$"), re.compile(r"[0-9a-f]{40}$"), re.compile(r"h[0-9]+$")
TO, MAX, DAY = 7, 4, 86400  # 1회 7초·재시도 1(하드 룰 12) · 한 주기 4줄(≤56초) · 24시간


def bad(m: str) -> None:
    print("ft-desk-reply-wake 판정 불가 — " + m, file=sys.stderr)


def ledger(p: Path, rows: list | None = None) -> list | None:  # rows 없으면 읽기(못 읽으면 None) · 주면 원자적 쓰기
    try:
        if rows is None:
            return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.exists() else []
        p.parent.mkdir(parents=True, exist_ok=True)
        t = p.with_suffix(p.suffix + ".tmp")
        t.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
        os.replace(t, p)
        return rows
    except (OSError, json.JSONDecodeError):
        return None


def send(base: Path, to: str, body: str) -> int:  # 0 = mbox 접수
    sh = os.environ.get("FT_MBOX_SH") or str(base / ".fable-team/comm/mbox.sh")
    try:
        return subprocess.run(["bash", sh, "send", to, "ft-desk-reply-wake", body], capture_output=True, text=True, timeout=30).returncode
    except (OSError, subprocess.SubprocessError):
        return 1


def judge(cmd: str, q: str, sha: str) -> tuple[int, str]:  # 7초 · 재시도 1
    last = (1, "점검 도구 실행 실패")
    for _ in range(2):
        try:
            r = subprocess.run([sys.executable, cmd, q, sha], capture_output=True, text=True, timeout=TO)
        except subprocess.SubprocessError:
            last = (124, "조회 %d초 초과" % TO)
            continue
        if r.returncode == 0:
            return 0, r.stdout
        last = (r.returncode, (r.stdout or r.stderr))
    return last


def register(led: Path, a: list, now: float) -> int:  # ⓐ 등록 · 실패는 «감시 등록 실패» 1줄(조용한 0 금지)
    h = a[1] if len(a) > 1 and HN.match(a[1]) else ("h" + a[1] if len(a) > 1 and a[1].isdigit() else "")
    row = {"q_ts": a[0] if a else "", "h": h, "sha": a[2].lower() if len(a) > 2 else "", "at": int(now), "deadline": int(now + DAY), "state": "open"}
    rows = ledger(led)
    if len(a) != 3 or not TS.match(row["q_ts"]) or not h or not SHA.match(row["sha"]):
        print("감시 등록 실패 — 사용: --register <질문ts(1794295513.494289)> <h번호> <sha40>", file=sys.stderr)
        return 3
    if rows is None or ledger(led, rows + [row]) is None:
        print("감시 등록 실패 — 장부를 못 읽었거나 못 씀: %s" % led, file=sys.stderr)
        return 3
    print("등록 %s q_ts=%s 끝=%d" % (h, row["q_ts"], row["deadline"]))
    return 0


def main(argv: list) -> int:
    base = Path(os.environ["FT_ROOT"]) if os.environ.get("FT_ROOT") else Path.cwd()
    if not (base / ".fable-team").is_dir():
        bad("루트를 못 풂(FT_ROOT 없음 · cwd 에 .fable-team/ 없음)")
        return 2
    led = Path(os.environ.get("FT_DESK_REPLY_LEDGER") or base / ".fable-team/state/desk-reply-wait.jsonl")
    now = float(os.environ.get("FT_NOW") or time.time())
    if argv[1:2] == ["--register"]:
        return register(led, argv[2:], now)
    rows = ledger(led)
    if rows is None:
        bad("장부를 못 읽음(JSON 아님·권한): %s" % led)
        return 2
    try:
        raw = json.loads(Path(os.environ.get("FT_SEATS_PLANNER") or base / ".fable-team/seats-planner.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        bad("명부를 못 읽음(seats-planner.json)")
        return 2
    seat = {k: v for k, v in raw.items() if isinstance(v, str)} if isinstance(raw, dict) else {}
    check = os.environ.get("FT_SLACK_CHECK") or str(Path(__file__).resolve().parent / "ft_oppa_slack_check.py")
    hil, maxn = Path(os.environ.get("HIL_DIR") or "/tmp"), int(os.environ.get("FT_DESK_REPLY_MAX") or MAX)
    opened = sent = shut = nbad = 0
    for row in rows:
        h, q, st = row.get("h"), row.get("q_ts"), row.get("state")
        if st == "closed":
            continue
        if not isinstance(h, str) or not isinstance(q, str):
            bad("장부 줄 꼴 아님: %s" % json.dumps(row, ensure_ascii=False)[:120])
            nbad += 1
            continue
        if (hil / (h + ".ran")).exists():  # ⓒ h 실행 기록 = 그 줄 닫힘
            row["state"], row["closed"] = "closed", "executed"
            shut += 1
            continue
        if now >= float(row.get("deadline") or 0):  # ⓒ 24시간 경과 = 닫고 planner master 1통
            if not seat.get("_master") or send(base, seat["_master"], "[답글 없음 24시간] %s ts=%s → 장부 줄 닫힘" % (h, q)):
                bad("쪽지 발신 실패·수신자 없음 — %s 줄은 열린 채로 둔다" % h)
                nbad += 1
                continue
            row["state"], row["closed"] = "closed", "timeout"
            shut += 1
            continue
        if opened >= maxn:  # 한 주기 조회 상한(감시 예산) — 끝나지 않은 줄(open·notified)을 오래된 것부터
            break
        opened += 1
        if not seat.get("_desk"):  # ⓓ 현역 desk 없음 = 알림 기록 0 · 다음 주기 재시도
            bad("_desk 없음 — %s 알림 0(다음 주기 재시도)" % h)
            nbad += 1
            continue
        rc, out = judge(check, q, row.get("sha") or "")
        m = re.search(r"reply=([0-9]+\.[0-9]+)$", out.strip().splitlines()[-1]) if rc == 0 and out.strip() else None
        if not m:  # ⓓ 조회 실패·토큰 없음 = «판정 불가» 1줄 · 알림 완료 기록 0
            bad("%s %s" % (h, (out.strip().splitlines() or ["SLACK-OK 줄 없음"])[-1][:160]))
            nbad += 1
            continue
        if row.get("notified_ts") == m.group(1):  # ⓑ 중복 억제 키 = 질문 ts·답글 ts(다른 답글 ts 면 1통 더)
            continue
        if send(base, seat["_desk"], "[오빠 답글] %s ts=%s → 실행 차례" % (h, m.group(1))):
            bad("쪽지 발신 실패 — %s 알림 0(다음 주기 재시도)" % h)
            nbad += 1
            continue
        row["notified_ts"], row["notified_at"], row["state"] = m.group(1), int(now), "notified"
        sent += 1
    if ledger(led, rows) is None:
        return 1
    print("desk-reply-wake 열린=%d 알림=%d 닫힘=%d 판정불가=%d" % (opened, sent, shut, nbad))
    return 1 if nbad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
