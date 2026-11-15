#!/usr/bin/env python3
# pyright: basic
"""r1757 — 승계 끝 옛 좌석 자동 닫기(ft_stall_scan 회차 갈래 · 판정·kill 조건은 ft-seat-close 그대로).

후보(A1 · 일곱 다 참): role=stop-ready ∧ _replaced_by 값 ∧ _closed 없음 ∧ 옛 세션 있음 ∧ 후계(사슬 끝) 세션 있음
∧ 재개 기록 <ZC_RESUME_DIR|~/.claude/state/seat-resume>/<옛>.json ∧ 옛 session_attached = 0.
켜짐(FT_SUCC_AUTO_CLOSE=1) = 후보마다 ft-seat-close.sh 1회(25초 · 회차 상한 3석) · 꺼짐 = «후보 … (꺼짐)» 줄만.
rc 1·3 = 같은 옛 좌석 FT_SUCC_RETRY_S(3600초) 동안 재시도 0(state/succ-auto-close.json · 임시→mv) · 조회 실패 = 그 좌석만 판정 불가 1줄.
"""
import json
import os
from pathlib import Path

CAP = 3


def _tail(rows: dict[str, dict], old: str) -> str:
    """_replaced_by 사슬의 마지막 좌석(고리 = 처음 다시 만난 자리에서 멈춤)."""
    seen, cur = {old}, rows[old]["_replaced_by"]
    while isinstance(rows.get(cur), dict) and isinstance(rows[cur].get("_replaced_by"), str) and rows[cur]["_replaced_by"] and cur not in seen:
        seen.add(cur)
        cur = rows[cur]["_replaced_by"]
    return cur


def _alive(tmux: list[str], run, seat: str) -> bool | None:
    rc, _out = run([*tmux, "has-session", "-t", f"={seat}"], None, 7)
    return True if rc == 0 else False if rc == 1 else None


def _attached(tmux: list[str], run, seat: str) -> int | None:
    rc, out = run([*tmux, "display-message", "-p", "-t", f"={seat}", "#{session_attached}"], None, 7)
    return int(out.strip()) if rc == 0 and out.strip().isdigit() else None


def candidates(root: Path, tmux: list[str], run, stamp: str, me: str) -> tuple[list[tuple[str, str]], list[str]]:
    """A1·A4 — [(옛, 후계)] 오래된 순(후계 opened_at · 없으면 명부 순 뒤) + 판정 불가 줄."""
    rows, order, lines = {}, [], []
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            lines.append(f"{stamp} 판정 불가 succ-close {f.name} 명부 못 읽음 {e.__class__.__name__}")
            continue
        for k, v in (d.items() if isinstance(d, dict) else []):
            if not k.startswith("_") and isinstance(v, dict):
                rows.setdefault(k, v)
                order.append(k)
    rdir = Path(os.environ.get("ZC_RESUME_DIR") or Path.home() / ".claude/state/seat-resume")
    out = []
    for old in dict.fromkeys(order):
        v = rows[old]
        if v.get("role") != "stop-ready" or not isinstance(v.get("_replaced_by"), str) or not v["_replaced_by"] or v.get("_closed") or old == me:
            continue
        if not (rdir / f"{old}.json").is_file():
            continue
        new = _tail(rows, old)
        a_old = _alive(tmux, run, old)
        a_new = _alive(tmux, run, new) if a_old else False
        att = _attached(tmux, run, old) if a_old and a_new else 0
        if a_old is None or a_new is None or att is None:
            lines.append(f"{stamp} 판정 불가 succ-close {old} tmux 조회 실패")
            continue
        if a_old and a_new and att == 0:
            out.append((old, new))
    at = {o: str((rows.get(n) or {}).get("opened_at") or "") for o, n in out}
    out.sort(key=lambda p: (at[p[0]] == "", at[p[0]]))
    return out, lines


def succ_close(root: Path, state_dir: Path, now: float, tmux: list[str], run, stamp: str, here: Path) -> list[str]:
    """A2·A3·A5 — 회차 1회 · 돌려준 줄 = 로그·출력."""
    me = ""
    if os.environ.get("TMUX_PANE"):
        rc, out = run([*tmux, "display-message", "-p", "-t", os.environ["TMUX_PANE"], "#{session_name}"], None, 7)
        me = out.strip() if rc == 0 else ""
    cands, lines = candidates(root, tmux, run, stamp, me)
    if os.environ.get("FT_SUCC_AUTO_CLOSE") != "1":
        return lines + [f"{stamp} succ-close 후보 {o} → {n} (꺼짐)" for o, n in cands]
    sf, wait = state_dir / "succ-auto-close.json", float(os.environ.get("FT_SUCC_RETRY_S") or 3600)
    try:
        tried = dict(json.loads(sf.read_text(encoding="utf-8")))
    except (OSError, ValueError, TypeError):
        tried = {}
    tool, n_call = os.environ.get("FT_SEAT_CLOSE_BIN") or str(here / "ft-seat-close.sh"), 0
    for old, new in cands:
        if n_call >= CAP:
            break
        t = tried.get(old)
        if isinstance(t, dict) and now - float(t.get("at", 0)) < wait:
            continue
        rc, out = run(["bash", tool, old, "--reason", f"승계 끝 자동 닫기 → {new}"], None, 25, cwd=root)
        n_call += 1
        lines.append(f"{stamp} succ-close {old} rc={rc} — {(out.strip().splitlines() or [''])[0][:120]}")
        _ = tried.update({old: {"rc": rc, "at": now}}) if rc in (1, 3) else tried.pop(old, None)
    try:
        sf.parent.mkdir(parents=True, exist_ok=True)
        (sf.parent / (sf.name + ".tmp")).write_text(json.dumps(tried), encoding="utf-8")
        os.replace(sf.parent / (sf.name + ".tmp"), sf)
    except OSError as e:
        lines.append(f"{stamp} WARN succ-close 상태 파일 쓰기 실패: {e}")
    return lines
