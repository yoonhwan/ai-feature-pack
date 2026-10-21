#!/usr/bin/env python3
"""ft_all_stop.py on "<사유>"|off|status|check — 전팀 정지 스위치 (r626 · 오빠 «자율 상태와 별개로 전팀 정지 상태»).

ALL_STOP.json(JSON: since·by·reason) = <리포 공용 루트>/.fable-team/state/ 파일 1개(PENALTY_STOP 와 같은 폴더 · 그 파일은 읽지도 쓰지도 않는다).
켜짐 = 모든 팀이 «정지»: 오빠·planner 요청에만 답·간단 작업 · 새 골·이슈·spawn·press 0 · 하던 일·할 일은 팀 폴더 STATE.md «정지 직전» 절에.
막기 = nano·role spawn · press 장치 허가(device-acquire)가 `check` 를 부른다. 끄기 = 파일을 ALL_STOP.released-<시각> 로 옮기고 «재개» 통지.
팀 목록·통지·루트 = ft_penalty(load_teams·mail·root) 재사용 — 페널티와 달리 복구 팀 면제 없음(오빠 «전팀»).
env: FT_ROOT(리포 루트) · FT_NOW(시험) · FT_MBOX_SH(쪽지) · FT_ALL_STOP_BY(켠 사람 칸 · 없으면 tmux 세션 이름 · 그것도 없으면 unknown).
rc: 0 통과·성공 · 1 check 켜짐(REJECT) · 2 usage.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from ft_penalty import load_teams, mail, now, root, state_dir

HEAD = "## 정지 직전"


def _file() -> Path:
    return state_dir() / "ALL_STOP.json"


def load() -> dict[str, object] | None:
    p = _file()
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def _iso(ts: object) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(float(ts)))  # type: ignore[arg-type]


def _by() -> str:
    by = os.environ.get("FT_ALL_STOP_BY")
    if by:
        return by
    if os.environ.get("TMUX"):
        p = subprocess.run(["tmux", "display-message", "-p", "#S"], capture_output=True, text=True, timeout=7)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    return "unknown"


def team_rel(label: str) -> str:
    """명부 팀 → 팀 폴더 STATE.md (리포 기준) · harness = design/harness/ · `m.room` 꼴은 점 뒤 이름."""
    name = label.split(".")[-1]
    return "design/harness/STATE.md" if name == "harness" else f"design/teams/{name}/STATE.md"


def _cands(t: dict[str, object]) -> list[Path]:
    """STATE.md 를 볼 자리 = 리포 루트 + 그 팀 카드가 사는 워크트리(명부 `_cards_wt`)."""
    rel, out = team_rel(str(t["team"])), [root() / team_rel(str(t["team"]))]
    cards = t.get("cards")
    for p in Path(str(cards)).parents if cards else []:
        if (p / ".git").exists():
            out.append(p / rel)
            break
    return out


def _template() -> str:
    here = Path(__file__).resolve().parent
    hr = here.parent / "HARNESS_ROOT"
    roots = [here.parent, Path(os.environ.get("FT_HARNESS_ROOT") or "/nonexistent") / "kit/fable-team"]
    if hr.is_file():
        roots.append(Path(hr.read_text(encoding="utf-8").splitlines()[0].strip()) / "kit/fable-team")
    for r in roots:
        if (r / "templates/team/STATE.md").is_file():
            return str(r / "templates/team/STATE.md")
    return "팩 harness/kit/fable-team/templates/team/STATE.md"


def turn_on(reason: str) -> int:
    d = load()
    if d is not None:
        print(f"all_stop=on (이미 켜짐 · since {_iso(d.get('since', 0))} · 사유: {d.get('reason')}) — 변경 0")
        return 0
    state_dir().mkdir(parents=True, exist_ok=True)
    since = int(now())
    _ = _file().write_text(json.dumps({"since": since, "by": _by(), "reason": reason}, ensure_ascii=False), encoding="utf-8")
    sent = []
    for t in load_teams(root()):
        if not t["master"]:
            continue
        rel = team_rel(str(t["team"]))
        make = "" if any(p.is_file() for p in _cands(t)) else f" · {rel} 없으면 {_template()} 틀로 만들기"
        mail(str(t["master"]), f"[전팀 정지] since {_iso(since)} · 사유: {reason} — 정지 — 오빠·planner 요청에만 답·간단 작업 · 새 골·이슈·spawn·press 0 · "
             f"하던 일·할 일을 {rel} «정지 직전» 절에 적기{make} (끄기 = 오빠 `!` 한 줄 · 상태 = ft-all-stop.sh status)")
        sent.append(str(t["master"]))
    print(f"all_stop=on since={since} notified={','.join(sent) or '-'}")
    return 0


def turn_off() -> int:
    d = load()
    if d is None:
        print("all_stop=off (이미 꺼짐) — 변경 0")
        return 0
    dst = state_dir() / f"ALL_STOP.released-{time.strftime('%Y%m%d%H%M%S', time.localtime(now()))}"
    _ = _file().rename(dst)
    sent = []
    for t in load_teams(root()):
        if t["master"]:
            mail(str(t["master"]), f"[전팀 정지 해제] 재개 — {team_rel(str(t['team']))} «정지 직전» 절 읽고 이어감 → 끝났으면 다음 카드(대기/ 맨 위) 착수")
            sent.append(str(t["master"]))
    print(f"all_stop=off released={dst.name} notified={','.join(sent) or '-'}")
    return 0


def status() -> int:
    d = load()
    if d is None:
        print("all_stop=off")
        return 0
    since = float(d.get("since", 0))  # type: ignore[arg-type]
    print(f"all_stop=on since={_iso(since)} by={d.get('by')} reason={d.get('reason')}")
    for t in load_teams(root()):
        hit = [p for p in _cands(t) if p.is_file() and p.stat().st_mtime >= since and HEAD in p.read_text(encoding="utf-8")]
        print(f"team={t['team']} state={'O' if hit else 'X'} file={hit[0] if hit else team_rel(str(t['team']))}")
    return 0


def check() -> int:
    d = load()
    if d is None:
        return 0
    print(f"REJECT 전팀 정지 중(since {_iso(d.get('since', 0))}) — 끄기 전 spawn·press 0 · 사유: {d.get('reason')} (ft-all-stop.sh status)")
    return 1


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    _ = os.environ.setdefault("FT_STALL_FROM", "ft-all-stop")  # ft_penalty.mail 의 보내는 이름
    if cmd == "on" and len(argv) == 2 and argv[1].strip():
        return turn_on(argv[1])
    if cmd in ("off", "status", "check") and len(argv) == 1:
        return {"off": turn_off, "status": status, "check": check}[cmd]()
    print('usage: ft-all-stop.sh on "<사유>"|off|status|check', file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
