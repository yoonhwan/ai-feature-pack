"""ft_monitor_snap_goal — 모니터 스냅샷 «골» 칸(카드 폴더 · 골좌표 결속 · 기다림 줄) (r2409 · 카드 K1·K3).

카드 «- 골좌표: <번호> · <이름 또는 서술>» 과 planner 원장 «## 골 진행» 표를 «이름 먼저 · 번호 다음» 으로 결속한다
(원장 번호와 카드 번호가 어긋나는 판이 있다 · 540장 실측). 못 붙인 카드는 지우지 않고 그 글 그대로의 키로 남긴다.
원천 부재(카드 폴더 없음)는 예외로 올린다 — 부르는 쪽이 그 두 칸만 unknown 으로 적는다(정상 빈 목록과 구별).
"""
from __future__ import annotations  # mini python 3.9.6

import re
from pathlib import Path

from ft_monitor_snap_src import cell, env, iso, run, unk

FOLDERS = ("대기", "진행", "완성")
REASON = ("- 대기 사유:", "- 배정: 대기(", "- 선행:")
GOAL_NO = re.compile(r"^(\d+)\s*[·—:\-]\s*(.*)$")  # 카드 «- 골좌표: 6 · 하네스 운영 정리» — 번호 + 나머지


def bind_goal(text: str, goals: dict) -> str:
    """카드 «골좌표» 글 → 원장 골 이름 (공통 식별자 = 이름 먼저 · 번호 다음 — 원장 번호와 카드 번호가 어긋나는 판이 있다).
    못 붙이면 남은 글 그대로 = «원장에 없는 골» 키(버리지 않는다)."""
    m = GOAL_NO.match(text.strip())
    no, rest = (m.group(1), m.group(2).strip()) if m else ("", text.strip())
    hits = [g for g in goals if g and g in rest]
    if hits:
        return max(hits, key=len)
    same = [g for g in goals if no and str(goals[g].get("no") or "") == no]
    return same[0] if len(same) == 1 else (rest or text.strip())


def cards(root: Path) -> dict:
    """{카드 id: {state, goal, reasons}} — design/**/indices/{대기,진행,완성}/*.md («- 골좌표:» 머리 12줄)."""
    out: dict = {}
    design = Path(env("FT_MONITOR_CARDS_DESIGN", str(root / "design"), root))
    if not design.is_dir():
        raise FileNotFoundError(str(design))  # 원천 부재 = unknown(정상 빈 목록으로 적지 않는다)
    for path in sorted(design.glob("**/indices/*/*.md")):
        if path.parent.name not in FOLDERS:
            continue
        try:
            with path.open(encoding="utf-8") as f:
                lines = [f.readline().rstrip("\n") for _ in range(40)]
        except (OSError, UnicodeDecodeError):
            continue
        goal = next((l.split(":", 1)[1].strip() for l in lines[:12] if l.startswith("- 골좌표:")), "")
        why = [next((l.split(":", 1)[1].strip() for l in lines if l.startswith(p)), "") for p in REASON]
        out[path.stem] = {"state": path.parent.name, "goal": goal, "reasons": [r for r in why if r]}
    return out


def goal_facts(root: Path, at: str, card_map: dict, goals: dict | None = None) -> dict:
    """골별 대기·진행·완성 카드 목록 + 완성 카드의 origin/main 착지 시각(git 1회 · 실패 = unknown)."""
    rc, out = run(["git", "-C", str(root), "log", "--format=C%ct", "--name-only", "-n", "600", "origin/main",
                   "--", "design"], root)
    if rc != 0:
        return unk("git -C %s log origin/main -- design rc=%s" % (root, rc), at)
    landed: dict = {}
    stamp = None
    for line in out.splitlines():
        if line.startswith("C") and line[1:].strip().isdigit():
            stamp = float(line[1:])
        elif line.strip() and stamp is not None:
            landed.setdefault(line.strip(), stamp)
    per_goal: dict = {}
    for cid, info in sorted(card_map.items()):
        if not info["goal"]:
            continue
        goal = bind_goal(info["goal"], goals or {})
        slot = per_goal.setdefault(goal, {"대기": [], "진행": [], "완성": [], "착지": {}})
        slot[info["state"]].append(cid)
        if info["state"] == "완성":
            ts = next((v for k, v in landed.items() if Path(k).stem == cid), None)
            slot["착지"][cid] = iso(ts) if ts else None
    return cell(per_goal, "카드 폴더 design/*/indices/{대기,진행,완성} + git origin/main 착지", at)


def waiting(root: Path, at: str, card_map: dict, goals: dict | None = None) -> dict:
    """골별 «서 있는 이유» 줄(카드 «- 대기 사유:» «- 배정: 대기(…)» «- 선행:») — 완성 카드는 뺀다."""
    out: dict = {}
    for cid, info in sorted(card_map.items()):
        if info["goal"] and info["reasons"] and info["state"] != "완성":
            out.setdefault(bind_goal(info["goal"], goals or {}), []).extend(f"{cid}: {r}" for r in info["reasons"])
    return cell(out, "카드 «- 대기 사유:» «- 배정: 대기(…)» «- 선행:» 줄", at)
