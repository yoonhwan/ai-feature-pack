#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_auto.py — r1717 A11 착지 갈래 집행의 두 조각(둘 다 다른 도구가 import 한다 · 동사 없음).
land_fill(state, seat, sec, master)  ← ft-nano-close-due.sh: 착지 갈래 줄의 자리표시(--result · --recv)를 A10 값으로 채울 수 있나.
  다 서야 채운다 — 그 좌석 마지막 «- 완료:» 줄이 «좌석 계속» 아님 · 남은 일 «잔여 없음»(A15) · 같은 Q 의 «- 착지:» 줄 · 지금 rec 의 전달 기록 · 세션 기록 파일 실재.
  → ({args(--result <세션 기록> --recv <seq>), rec, set, pr}, "") | (None, «빠짐=<항목> 채울 이=<좌석|팀장>»)
land_close(ln, tried, stamp, close, run, root)  ← ft_stall_scan.py auto_close(FT_NANO_AUTO_CLOSE=1): «갈래=착지기록» 줄 1개를 1회 집행 → 로그 줄들.
  ⓐ 명부 role=nano 만 ⓑ 집행 직전 «착지 sha 가 origin/<target> 의 조상» 재확인(git 7초) ⓒ ft-nano-close 그 좌석 1회뿐(가지 삭제·다른 세션 kill 0)
  ⓓ ⓑ 실패·rc≠0(rc 1 REJECT 는 닫기 도구가 직접 알린다) = ft-critical-notify(없으면 팀장 «[자동 닫기 실패]») ⓔ 닫히면 로그 «auto-close CLOSED … 갈래=착지기록».
  같은 실패를 되풀이하지 않는 열쇠 = (좌석 · set · rec) — 옛 꼴 상태값(set 만)은 rec 없는 열쇠라 새 rec 에서 1회 다시."""
from __future__ import annotations

import json
import os
import re
import shlex

from ft_nano_record import DONE_RX, HERE, LAND_RX, SET_RX, Ctx, Unjudged, left_free, left_of, marks, rec_of
from ft_nano_record import run as git_run
from ft_nano_record_notify import send


def land_fill(state, seat, sec, master=""):
    done = [ln for ln in sec for m in [DONE_RX.match(ln)] if m and m.group(1) == seat]
    q10 = re.search(r"병합 상태:\s*착지\s+([0-9a-f]{10})", done[-1]) if done else None
    if not q10:
        return None, f"빠짐=착지 뒤 완료 줄 채울 이={seat}"
    if "좌석 계속" in done[-1]:
        return None, "빠짐=닫을 좌석 아님(좌석 계속) 채울 이=팀장"
    if not left_free(left_of(done[-1]), master):   # r1717-mut:autoleft
        return None, f"빠짐=남은 일({left_of(done[-1])}) 채울 이={seat}"
    try:
        close = json.loads((state / "land-record-notified.json").read_text(encoding="utf-8")).get("close") or {}
    except (OSError, ValueError, AttributeError):
        close = {}
    ent = next(((k.rsplit("|", 1)[-1], v) for k, v in close.items() if k.startswith(seat + "|") and k.rsplit("|", 1)[-1].startswith(q10.group(1))), None)
    full = [g for ln in sec for m in [LAND_RX.match(ln)] for g in [m.group(1) if m else ""] if g and (g.startswith(q10.group(1)) or q10.group(1).startswith(g))]
    m = marks(sec, seat, ent[0] if ent else max(full or [q10.group(1)], key=len))
    if not (m["s"] and m["l"]):
        return None, f"빠짐={'세트 줄' if not m['s'] else '착지 줄'} 채울 이={seat}"
    if not ent or ent[1].get("rec") != rec_of(m):
        return None, f"빠짐=닫기 요청 전달 채울 이={seat}"
    if not os.path.isfile(str(ent[1].get("result") or "")):
        return None, f"빠짐=세션 기록 채울 이={seat}"
    args = f"--result {shlex.quote(str(ent[1]['result']))} --recv {ent[1].get('seq')}"
    return {"args": args, "rec": rec_of(m), "set": SET_RX.search(m["s"]).group(1), "pr": ent[1].get("pr")}, ""


def alert(ctx, seat, master, rec, what):   # ⓓ — r1718 A1 도구가 있으면 그쪽으로 · 없으면 팀장 1통
    tool = os.environ.get("FT_CRITICAL_NOTIFY") or str(HERE / "ft-critical-notify.sh")
    if os.path.isfile(tool):
        git_run(["bash", tool, "ft-stall-scan", seat, "--event", f"auto-close:{rec}", "--what", f"자동 닫기 실패 — {what}", "--next", "REJECT 원문대로 고친 뒤 닫기 명령을 다시", "--where", seat], env=dict(os.environ))
    elif master:
        send(ctx, master, "ft-stall-scan", f"[자동 닫기 실패] {seat} {what}")


def ancestor(ctx, seat, rec):   # ⓑ — 전달 기록(그 rec) → 장부 줄 → Q 가 origin/<target> 의 조상인가 · → "" | 실패 사유
    hit = next(((k, v) for k, v in ctx.store()["close"].items() if k.startswith(seat + "|") and v.get("rec") == rec), None)
    e = next((e for e in ctx.ledger() if hit and e["landed"] == hit[0].rsplit("|", 1)[-1] and e.get("pr") == hit[1].get("pr")), None)
    if not e:
        return "조상 확인 불가(전달 기록·장부 줄 없음)"
    rc, _o, _e = git_run(["git", "-C", str(e.get("repo") or ""), "merge-base", "--is-ancestor", e["landed"], f"refs/remotes/origin/{e.get('target') or 'main'}"])
    return "" if rc == 0 else f"착지 sha {e['landed'][:10]} 조상 확인 rc={'-' if rc is None else rc}"


def land_close(ln, tried, stamp, close, run, root=None):
    tok = {t.split("=", 1)[0]: t.split("=", 1)[1] for t in ln.split(" — ", 1)[0].split() if "=" in t}
    seat, cmd, key = (ln.split() + ["", "", ""])[2], ln.split(" — ", 1)[-1], f"{tok.get('set', '')}|{tok.get('rec', '')}"
    if not (seat and tok.get("set") and tok.get("rec") and cmd.startswith("bash ") and " --landed-pr " in cmd):
        return [f"{stamp} 판정 불가 auto-close 줄 해석 실패 — {ln[:120]}"]
    if tried.get(seat) == key:
        return []
    try:
        ctx = Ctx(root)
        doc = ctx.seats((seat.split("-") + ["", ""])[1])
    except Unjudged as e:
        return [f"{stamp} 판정 불가 auto-close {seat} {e}"]
    role, master = (doc.get(seat) or {}).get("role") if isinstance(doc.get(seat), dict) else None, str(doc.get("_master") or "")
    if role != "nano":   # r1717-mut:autorole
        return [f"{stamp} 판정 불가 auto-close 역할 {seat} role={role or '-'} — 집행 0"]
    bad = ancestor(ctx, seat, tok["rec"])
    if bad:
        tried[seat] = key
        alert(ctx, seat, master, tok["rec"], bad)
        return [f"{stamp} auto-close 실패 {seat} 갈래=착지기록 — {bad} · 집행 0"]
    crc, cout = run(["bash", close, *shlex.split(cmd)[2:]], {**os.environ, "FT_NANO_AUTO_CLOSE": "1"}, 70)
    closed = next((x for x in cout.splitlines() if x.startswith("CLOSED")), "")
    if crc == 0 and closed:
        tried.pop(seat, None)
        return [f"{stamp} auto-close {closed} 갈래=착지기록 rec={tok['rec']}"]
    tried[seat] = key
    first = (cout.strip().splitlines() or [""])[0][:120]
    if crc != 1:
        alert(ctx, seat, master, tok["rec"], f"rc={crc} — {first}")
    return [f"{stamp} auto-close 실패 {seat} rc={crc} 갈래=착지기록 — {first}"]
