#!/usr/bin/env python3
"""ft_all_stop.py on "<사유>"|off|status|check [--succession <구> <새>] — 전팀 정지 스위치 (r626 · 오빠 «자율 상태와 별개로 전팀 정지 상태»).

ALL_STOP.json(JSON: since·by·reason·notify_failed) = <리포 공용 루트>/.fable-team/state/ 파일 1개(PENALTY_STOP 와 같은 폴더 · 그 파일은 읽지도 쓰지도 않는다).
켜짐 = 모든 팀이 «정지»: 오빠·planner 요청에만 답·간단 작업 · 새 골·이슈·spawn·press 0 · 하던 일·할 일은 팀 폴더 STATE.md «정지 직전» 절에.
막기 = nano·role spawn · tmux-spawn · press 게이트·장치 허가가 `check` 를, 승계 도구가 `check --succession <구> <새>` 를 부른다(진짜 승계 = 구 좌석이 명부에 있고 새 이름이 같은 계보 #N+1 만 통과).
끄기 = 파일을 ALL_STOP.released-<시각> 로 옮기고 «재개» 통지. 상태 파일이 깨졌으면(JSON 아님·dict 아님·폴더·못 읽음) «정지(읽기 이상)» 로 본다 — 조용한 통과 0.
통지는 rc 를 돌려받는다 — 실패 수신자는 그 상태 파일 notify_failed 에 남기고 rc 3 · 같은 on/off 를 다시 치면 상태는 그대로 두고 실패분만 다시 보낸다.
위협 모델(카드 «DA⑥ r1 HOLD → 고침»): 같은 uid 좌석의 고의 우회(변수 간접·명부 위조·가짜 tmux)는 밖 · 표준 도구·평범한 한 줄·깨진 상태·통지 실패는 안.
팀 목록·루트 = ft_penalty(load_teams·now·root·state_dir) 재사용 — 페널티와 달리 복구 팀 면제 없음(오빠 «전팀»).
env: FT_ROOT(리포 루트) · FT_NOW(시험) · FT_MBOX_SH(쪽지) · FT_ALL_STOP_BY(켠 사람 칸 · 없으면 tmux 세션 이름 · 그것도 없으면 unknown).
rc: 0 통과·성공 · 1 check 켜짐(REJECT) · 2 usage · 3 상태는 바뀜·통지 일부 실패.
"""
import glob
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from ft_penalty import load_teams, now, root, state_dir

HEAD = "## 정지 직전"
Broken = str  # 읽기 이상 사유


def _file() -> Path:
    return state_dir() / "ALL_STOP.json"


def read(p: Path) -> dict[str, object] | Broken | None:
    """없음 = None · 정상 = dict · 깨짐(폴더·못 읽음·JSON 아님·dict 아님) = 사유 문자열."""
    if not os.path.lexists(p):
        return None
    try:
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return f"{type(e).__name__}"
    return d if isinstance(d, dict) else f"JSON {type(d).__name__}"


def _iso(ts: object) -> str:
    try:
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(float(ts)))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return "?"


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
    rel = team_rel(str(t["team"]))
    out = [root() / rel]
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


def send(to: str, body: str) -> bool:
    sh = os.environ.get("FT_MBOX_SH") or str(root() / ".fable-team/comm/mbox.sh")
    try:
        p = subprocess.run(["bash", sh, "send", to, "ft-all-stop", body, "--urgent"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return False
    return p.returncode == 0


def _on_body(t: dict[str, object], since: object, reason: object) -> str:
    rel = team_rel(str(t["team"]))
    make = "" if any(p.is_file() for p in _cands(t)) else f" · {rel} 없으면 {_template()} 틀로 만들기"
    return (f"[전팀 정지] since {_iso(since)} · 사유: {reason} — 정지 — 오빠·planner 요청에만 답·간단 작업 · 새 골·이슈·spawn·press 0 · "
            f"하던 일·할 일을 {rel} «정지 직전» 절에 적기{make} (끄기 = 오빠 `!` 한 줄 · 상태 = ft-all-stop.sh status)")


def _off_body(t: dict[str, object]) -> str:
    return f"[전팀 정지 해제] 재개 — {team_rel(str(t['team']))} «정지 직전» 절 읽고 이어감 → 끝났으면 다음 카드(대기/ 맨 위) 착수"


def notify(p: Path | None, d: dict[str, object], only: list[str] | None, body) -> tuple[list[str], list[str]]:  # type: ignore[no-untyped-def]
    """명부 팀장에게 보냄(only = 이 좌석만) → (보낸 것, 실패) · 실패는 그 상태 파일(p) notify_failed 에 남긴다."""
    sent, failed = [], []
    for t in load_teams(root()):
        m = str(t["master"] or "")
        if m and (only is None or m in only):
            (sent if send(m, body(t)) else failed).append(m)
    d["notify_failed"] = failed
    if p is not None:
        _ = p.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
    return sent, failed


def _report(head: str, sent: list[str], failed: list[str]) -> int:
    print(f"{head} notified={','.join(sent) or '-'}")
    if failed:
        print(f"상태 바뀜 · 통지 실패 {len(failed)}: {','.join(failed)} — 같은 명령을 다시 치면 실패분만 다시 보낸다")
        return 3
    return 0


def turn_on(reason: str) -> int:
    p = _file()
    d = read(p)
    if isinstance(d, str):
        print(f"all_stop=on(읽기 이상: {d}) — 변경 0 · 고치려면 off 뒤 다시 on")
        return 0
    if d is not None:
        retry = [str(x) for x in d.get("notify_failed") or []]  # type: ignore[union-attr]
        if not retry:
            print(f"all_stop=on (이미 켜짐 · since {_iso(d.get('since'))} · 사유: {d.get('reason')}) — 변경 0")
            return 0
        sent, failed = notify(p, d, retry, lambda t: _on_body(t, d.get("since"), d.get("reason")))
        return _report(f"all_stop=on (이미 켜짐 · 실패분 재통지 {len(retry)})", sent, failed)
    state_dir().mkdir(parents=True, exist_ok=True)
    d = {"since": int(now()), "by": _by(), "reason": reason, "notify_failed": []}
    _ = p.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")  # 막기는 통지 «전»부터
    sent, failed = notify(p, d, None, lambda t: _on_body(t, d["since"], reason))
    return _report(f"all_stop=on since={d['since']}", sent, failed)


def _last_released() -> Path | None:
    got = sorted(glob.glob(str(state_dir() / "ALL_STOP.released-*")))
    return Path(got[-1]) if got else None


def turn_off() -> int:
    p = _file()
    if not os.path.lexists(p):
        last = _last_released()
        d = read(last) if last else None
        retry = [str(x) for x in d.get("notify_failed") or []] if isinstance(d, dict) else []  # type: ignore[union-attr]
        if not retry or last is None or not isinstance(d, dict):
            print("all_stop=off (이미 꺼짐) — 변경 0")
            return 0
        sent, failed = notify(last, d, retry, _off_body)
        return _report(f"all_stop=off (이미 꺼짐 · 실패분 재통지 {len(retry)})", sent, failed)
    dst = state_dir() / f"ALL_STOP.released-{time.strftime('%Y%m%d%H%M%S', time.localtime(now()))}"
    d = read(p)
    p.rename(dst)
    rec = None if dst.is_dir() else dst  # 깨진 상태가 폴더였으면 실패 기록 자리 없음(화면·rc 만)
    sent, failed = notify(rec, d if isinstance(d, dict) else {"broken": d}, None, _off_body)
    return _report(f"all_stop=off released={dst.name}" + ("" if isinstance(d, dict) else f" (깨진 상태 치움: {d})"), sent, failed)


def status() -> int:
    d = read(_file())
    if d is None:
        print("all_stop=off")
        return 0
    if isinstance(d, str):
        print(f"all_stop=on(읽기 이상: {d}) — check 는 정지로 본다 · 치우기 = off")
        return 0
    since = d.get("since", 0)
    print(f"all_stop=on since={_iso(since)} by={d.get('by')} reason={d.get('reason')} notify_failed={','.join(map(str, d.get('notify_failed') or [])) or '-'}")  # type: ignore[arg-type]
    for t in load_teams(root()):
        hit = [p for p in _cands(t) if p.is_file() and p.stat().st_mtime >= float(since) and HEAD in p.read_text(encoding="utf-8")]  # type: ignore[arg-type]
        print(f"team={t['team']} state={'O' if hit else 'X'} file={hit[0] if hit else team_rel(str(t['team']))}")
    return 0


def true_succession(old: str, new: str) -> bool:
    """새 이름 = 구 좌석 계보 #N+1 이고, 구 좌석이 명부(seats*.json)의 좌석 키 또는 역할 칸(`_` 키) 값."""
    m = re.fullmatch(r"(.+)#([0-9]+)", old)
    if not m or new != f"{m.group(1)}#{int(m.group(2)) + 1}":
        return False
    for f in glob.glob(str(root() / ".fable-team/seats*.json")):
        try:
            d = json.loads(Path(f).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(d, dict) and (old in d or any(k.startswith("_") and v == old for k, v in d.items())):
            return True
    return False


def check(succ: list[str]) -> int:
    d = read(_file())
    if d is None:
        return 0
    if isinstance(d, str):
        print(f"REJECT 전팀 정지 중(상태 파일 읽기 이상: {d}) — 끄기 전 spawn·press 0 · 치우기 = 오빠 `!` ft-all-stop.sh off")
        return 1
    if succ and true_succession(succ[0], succ[1]):
        print(f"INFO 전팀 정지 중이나 진짜 승계({succ[0]} → {succ[1]})라 통과 — 같은 자리 교대(순증 0)", file=sys.stderr)
        return 0
    print(f"REJECT 전팀 정지 중(since {_iso(d.get('since'))}) — 끄기 전 spawn·press 0 · 사유: {d.get('reason')} (ft-all-stop.sh status)"
          + (f" · 승계 예외 아님(구 좌석 명부·계보 #N+1 둘 다 맞아야 · {succ[0]} → {succ[1]})" if succ else ""))
    return 1


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    if cmd == "on" and len(argv) == 2 and argv[1].strip():
        return turn_on(argv[1])
    if cmd == "check" and (len(argv) == 1 or (len(argv) == 4 and argv[1] == "--succession")):
        return check(argv[2:])
    if cmd in ("off", "status") and len(argv) == 1:
        return turn_off() if cmd == "off" else status()
    print('usage: ft-all-stop.sh on "<사유>"|off|status|check [--succession <구 좌석> <새 좌석>]', file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
