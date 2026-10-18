#!/usr/bin/env python3
"""ft_penalty.py on|status|resume <팀>|off|check [<팀>] — 전 세션 정지 페널티 (R320b · 오빠 판정 2170).

PENALTY_STOP(JSON: since·reason·order·resumed) = 파일 1개. 있으면 nano·role spawn 은 «재개된 팀»만 통과(successor 는 검사 0).
해제는 resume <팀> 규칙으로만 — 그 팀의 마지막 stall-scan 결과(신선 10분 안)에 b=0 ∧ d=0 이고, 그 팀 master 가 페널티 쪽지 «뒤» 턴을 1회 이상 끝냈을 때(TURN_END > since)만 «재개됨» 칸에 넣는다.
a 는 페널티 중 세지 않는다(스스로 spawn 을 막으므로) — 재개 뒤 첫 틱부터 다시 센다. 복구 팀(EXEMPT = harness·planner)은 정지 대상이 아니다(쪽지·check·재개 목록 제외).
env: FT_ROOT(리포 루트) · FT_NOW(시험) · FT_MBOX_SH(쪽지) · FT_STALL_FROM(보내는 이름).
rc: 0 통과 · 3 REJECT(check) · 1 재개 불가·실패 · 2 usage.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from ft_stall_detect import load_teams

FRESH_S = 600
EXEMPT = ("harness", "planner")  # 복구 담당 팀 — 정지 대상 아님


def root() -> Path:
    r = os.environ.get("FT_ROOT")
    if r:
        return Path(r)
    out = subprocess.run(["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True)
    return Path(out.stdout.strip()).parent


def now() -> float:
    return float(os.environ.get("FT_NOW") or time.time())


def state_dir() -> Path:
    return root() / ".fable-team/state"


def load() -> dict[str, object] | None:
    p = state_dir() / "PENALTY_STOP"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def mail(to: str, body: str) -> None:
    sh = os.environ.get("FT_MBOX_SH") or str(root() / ".fable-team/comm/mbox.sh")
    subprocess.run(["bash", sh, "send", to, os.environ.get("FT_STALL_FROM", "ft-stall-scan"), body, "--urgent"], capture_output=True, text=True, timeout=30)


def turn_on(reason: str) -> int:
    if load() is not None:
        print("penalty=on (이미 켜짐)")
        return 0
    teams = load_teams(root())
    teams = [t for t in teams if t["team"] not in EXEMPT]
    order = [t["team"] for t in teams]
    (state_dir()).mkdir(parents=True, exist_ok=True)
    _ = (state_dir() / "PENALTY_STOP").write_text(json.dumps({"since": int(now()), "reason": reason, "order": order, "resumed": []}, ensure_ascii=False), encoding="utf-8")
    for t in teams:
        if t["master"]:
            mail(t["master"], "[페널티] 전 세션 정지 — 새 발주·spawn 0 · 진행 중 도구 호출은 끝내고 멈춤 · 사유: " + reason + " · 재개는 팀 순서대로 `ft-penalty.sh resume <팀>` (stall 0 확인 뒤)")
    print(f"penalty=on teams={','.join(order)}")
    return 0


def status() -> int:
    d = load()
    if d is None:
        print("penalty=off")
        return 0
    resumed = list(d.get("resumed") or [])  # type: ignore[arg-type]
    pending = [t for t in d.get("order") or [] if t not in resumed]  # type: ignore[union-attr]
    print(f"penalty=on since={d.get('since')} resumed={','.join(resumed) or '-'} pending={','.join(pending) or '-'} reason={d.get('reason')}")
    return 0


def check(team: str) -> int:
    d = load()
    if d is None or team in EXEMPT or (team and team in (d.get("resumed") or [])):  # type: ignore[operator]
        return 0
    print(f"REJECT penalty 전 세션 정지 중 — 팀={team or '미상'} 은 아직 재개 전 (ft-penalty.sh status · 사유: {d.get('reason')})")
    return 3


def resume(team: str) -> int:
    d = load()
    if d is None:
        print("penalty=off — 재개할 것 없음")
        return 0
    last = state_dir() / "stall-scan.last.json"
    try:
        snap = json.loads(last.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"재개 불가 — 최근 stall-scan 결과 없음({last.name}) · 먼저 ft-stall-scan.sh 를 돌려라")
        return 1
    if now() - float(snap.get("ts", 0)) > FRESH_S:
        print(f"재개 불가 — stall-scan 결과가 낡았다({int(now() - float(snap.get('ts', 0)))}초) · 다시 돌려라")
        return 1
    c = snap.get("teams", {}).get(team)
    if c is None:
        print(f"재개 불가 — stall-scan 결과에 팀 {team} 없음 (scan 에 안 잡힌 팀)")
        return 1
    if int(c.get("b", 0)) + int(c.get("d", 0)):
        print(f"재개 불가 — 팀 {team} stall 남음 b={c.get('b')} d={c.get('d')} (해결 확인 뒤 다시)")
        return 1
    end = c.get("master_end")
    if end is None or float(end) <= float(d.get("since", 0)):
        print(f"재개 불가 — 팀 {team} master 가 페널티 쪽지 뒤 턴을 아직 안 끝냄(TURN_END ≤ since) · master 가 쪽지를 읽고 한 턴 돈 뒤 다시")
        return 1
    resumed = list(d.get("resumed") or [])  # type: ignore[arg-type]
    if team not in resumed:
        resumed.append(team)
    d["resumed"] = resumed
    if all(t in resumed for t in d.get("order") or []):  # type: ignore[union-attr]
        (state_dir() / "PENALTY_STOP").unlink()
        print(f"resumed={team} · 전 팀 재개 → PENALTY_STOP 삭제")
    else:
        _ = (state_dir() / "PENALTY_STOP").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
        print(f"resumed={team} · 남은 팀 {','.join(t for t in d.get('order') or [] if t not in resumed)}")  # type: ignore[union-attr]
    for t in load_teams(root()):
        if t["team"] == team and t["master"]:
            mail(t["master"], f"[페널티 해제] 팀 {team} 재개 — 발주·spawn 가능. 멈춘 좌석이 다시 생기면 같은 페널티다.")
    return 0


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    if cmd == "on":
        reason = argv[argv.index("--reason") + 1] if "--reason" in argv[:-1] else "수동"
        return turn_on(reason)
    if cmd == "status":
        return status()
    if cmd == "check":
        return check(argv[1] if len(argv) > 1 else "")
    if cmd == "resume" and len(argv) > 1:
        return resume(argv[1])
    if cmd == "off":
        p = state_dir() / "PENALTY_STOP"
        if p.exists():
            p.unlink()
        print("penalty=off")
        return 0
    print("usage: ft-penalty.sh on [--reason <사유>]|status|resume <팀>|off|check [<팀>]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
