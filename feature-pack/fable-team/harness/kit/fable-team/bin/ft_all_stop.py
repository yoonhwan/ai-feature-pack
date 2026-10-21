#!/usr/bin/env python3
"""ft_all_stop.py on "<사유>"|off|status|check [--succession <구> <새>] — 전팀 정지 스위치 (r626 · 오빠 «자율 상태와 별개로 전팀 정지 상태»).

ALL_STOP.json(JSON: since·by·reason·notify_failed) = <리포 공용 루트>/.fable-team/state/ 파일 1개(PENALTY_STOP 와 같은 폴더 · 그 파일은 읽지도 쓰지도 않는다).
켜짐 = 모든 팀이 «정지»: 오빠·planner 요청에만 답·간단 작업 · 새 골·이슈·spawn·press 0 · 하던 일·할 일은 팀 폴더 STATE.md «정지 직전» 절에.
막기 = nano·role spawn · tmux-spawn · press 게이트·장치 허가가 `check` 를, 승계 도구가 `check --succession <구> <새>` 를 부른다(진짜 승계 = 구 좌석이 명부에 있고 새 이름이 같은 계보 #N+1 만 통과).
끄기 = 파일을 ALL_STOP.released-<시각> 로 옮기고 «재개» 통지. 상태 파일이 깨졌으면(JSON 아님·dict 아님·폴더·못 읽음) «정지(읽기 이상)» 로 본다 — 조용한 통과 0.
★DA⑥ r2 재설계: «없음 = 꺼짐» 가정 0★ — 원장 <state>/all-stop.log(덧붙이기 전용 · `<시각>\ton|off\t<by>\t<사유>[\tnotify_failed=…]`)에 on·off 가 상태 변경 «전» 1줄.
  판정: 상태 폴더 없음 = 정지(사람 확인) · 상태 파일 있음 = 정지 · 원장 마지막 on = 정지(상태 파일이 사라져도) · 원장 깨짐 = 정지 · ★원장 없음 = 정지(r4)★ · 꺼짐 = 원장 마지막 off 뿐.
  init(설치 전용 · install.sh --apply) = 상태 폴더 + 원장 첫 줄 «<시각>\toff\tinstall\tinit»(이미 있으면 그대로).
통지는 rc 를 돌려받는다 — on 실패분은 상태 파일 notify_failed · off 실패분은 원장 off 줄 notify_failed · rc 3 · 같은 on/off 를 다시 치면 실패분만 다시 보낸다.
승계 예외 = 새 이름이 구 좌석 계보 #N+1 ∧ 구 좌석이 어느 명부에 현역 행(닫힘 표시 없음)으로 있음 ∧ 구 좌석 tmux 세션이 지금 살아 있음(목록 못 읽음 = 예외 0).
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
from ft_team_lib import TeamPathError, team_rows_ref

HEAD = "## 정지 직전"
LOG = "all-stop.log"  # 원장(덧붙이기 전용) — 꺼짐의 유일한 증거 = 마지막 off 줄 (DA⑥ r2 재설계)
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
    """명부 팀 → 팀 폴더 STATE.md (리포 기준) · `m.room` 꼴은 점 뒤 이름.
    r688: 폴더 = 명단(<FT_TEAMS_REF 기본 origin/main>:design/TEAMS.md) 칸 — 팀 폴더 글자 0 · 꼴3(`$FT_HARNESS_ROOT/…`)은 리포 안 같은 자리 · 명단 못 읽음·팀 없음 = TeamPathError."""
    name = label.split(".")[-1]
    rows = team_rows_ref(os.environ.get("FT_TEAMS_REF") or "origin/main", root())
    if name not in rows:
        raise TeamPathError(f"ERROR {name} 은 팀 명단(TEAMS.md)에 없다 — STATE.md 자리를 못 푼다")
    return re.sub(r"^(\$FT_HARNESS_ROOT/|\$\{FT_HARNESS_ROOT\}/)", "", rows[name]) + "STATE.md"


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
            try:
                text = body(t)
            except TeamPathError as e:  # r688 H1: 명단 밖 팀 하나가 뒤 팀 통지를 끊지 않게 — 그 팀장 = 실패(재통지 경로) · 대체 자리 0
                print(f"통지 본문 못 만듦 {m}: {e}", file=sys.stderr)
                failed.append(m)
                continue
            (sent if send(m, text) else failed).append(m)
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


def ledger() -> tuple[str, list[str]] | Broken | None:
    """원장 마지막 줄 → (on|off, 그 줄 notify_failed) · 원장 없음 = None · 깨짐(못 읽음·빈 원장·꼴 틀림) = 사유."""
    p = state_dir() / LOG
    if not os.path.lexists(p):
        return None
    try:
        lines = [x for x in p.read_text(encoding="utf-8").splitlines() if x.strip()]
    except (OSError, ValueError) as e:
        return f"{type(e).__name__}"
    if not lines:
        return "빈 원장"
    f = lines[-1].split("\t")
    if len(f) < 4 or f[1] not in ("on", "off"):
        return "마지막 줄 꼴 틀림"
    nf = next((x[len("notify_failed="):] for x in f[4:] if x.startswith("notify_failed=")), "")
    return f[1], [x for x in nf.split(",") if x]


def log(kind: str, by: str, reason: str, failed: list[str] | None = None) -> None:
    """원장 덧붙이기 1줄 — `<시각>\ton|off\t<by>\t<사유>[\tnotify_failed=<좌석들>]`."""
    cells = [time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now())), kind, by, " ".join(str(reason).split())]
    if failed is not None:
        cells.append("notify_failed=" + ",".join(failed))
    with open(state_dir() / LOG, "a", encoding="utf-8") as f:
        _ = f.write("\t".join(cells) + "\n")


def judge() -> tuple[str, str, dict[str, object] | None]:
    """→ (off|stop|hard, 사유, 상태 dict) — «없음 = 꺼짐» 가정 0: 꺼짐 증거 = 원장 마지막 off 줄뿐(원장 없음 = 정지 · r4)."""
    sd = state_dir()
    if not sd.is_dir():
        return "hard", f"상태 폴더 없음({sd}) — 사람 확인", None
    d, lg = read(_file()), ledger()
    if isinstance(d, str):
        return "hard", f"상태 파일 읽기 이상: {d}", None
    if isinstance(lg, str):
        return "hard", f"원장 읽기 이상({LOG}: {lg}) — 사람 확인", None
    if d is not None:
        return "stop", f"since {_iso(d.get('since'))}", d
    if lg is None:  # r4(DA⑥ r3): 기록 없음 = 언제나 정지 — «처음 설치» 추측 0 · 설치(install.sh --apply)가 init 줄을 남긴다
        return "hard", f"원장 없음({LOG}) — 설치(install.sh --apply)가 init 줄을 남겨야 한다 · 사람 확인", None
    if lg[0] == "on":
        return "stop", f"상태 파일 사라짐 — off 는 ft-all-stop.sh 로만 · 원장 마지막 줄 on", None
    return "off", "", None


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
    log("on", str(d["by"]), reason)  # 원장 먼저 — 상태 파일이 사라져도 «켜짐» 이 남는다
    _ = p.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")  # 막기는 통지 «전»부터
    sent, failed = notify(p, d, None, lambda t: _on_body(t, d["since"], reason))
    return _report(f"all_stop=on since={d['since']}", sent, failed)


def turn_off() -> int:
    p, sd = _file(), state_dir()
    lg = ledger()
    if not sd.is_dir() or (os.path.lexists(p) and p.is_dir()) or isinstance(lg, str):
        why = "상태 폴더 없음" if not sd.is_dir() else ("상태 경로가 폴더" if isinstance(lg, tuple) or lg is None else f"원장 읽기 이상({lg})")
        print(f"REJECT off 못 함 — {why}({sd}) · 옮김 0 · 사람 확인")
        return 1
    if not os.path.lexists(p) and lg is not None and lg[0] == "off":
        retry = lg[1]
        if not retry:
            print("all_stop=off (이미 꺼짐) — 변경 0")
            return 0
        sent, failed = notify(None, {}, retry, _off_body)
        log("off", _by(), "실패분 재통지", failed)
        return _report(f"all_stop=off (이미 꺼짐 · 실패분 재통지 {len(retry)})", sent, failed)
    d = read(p)
    log("off", _by(), "끄기")  # 원장 먼저 — 그 뒤 상태 파일을 옮긴다
    note = ""
    if os.path.lexists(p):
        dst = sd / f"ALL_STOP.released-{time.strftime('%Y%m%d%H%M%S', time.localtime(now()))}"
        p.rename(dst)
        note = f" released={dst.name}" + ("" if isinstance(d, dict) else f" (깨진 상태 치움: {d})")
    else:
        note = " (상태 파일 없이 원장 on 이던 것을 끔)" if lg else " (원장 없던 것을 끔 — 이 off 줄이 첫 기록)"
    sent, failed = notify(None, {}, None, _off_body)
    if failed:
        log("off", _by(), "통지 실패", failed)
    return _report(f"all_stop=off{note}", sent, failed)


def status() -> int:
    kind, why, d = judge()
    if kind == "off":
        print("all_stop=off")
        return 0
    if d is None:
        print(f"all_stop=on({'읽기 이상 — ' if kind == 'hard' else ''}{why}) — check 는 정지로 본다 · 치우기 = 오빠 `!` ft-all-stop.sh off")
        return 0
    since = d.get("since", 0)
    print(f"all_stop=on since={_iso(since)} by={d.get('by')} reason={d.get('reason')} notify_failed={','.join(map(str, d.get('notify_failed') or [])) or '-'}")  # type: ignore[arg-type]
    for t in load_teams(root()):
        try:
            cands = _cands(t)
        except TeamPathError as e:  # r688 H1: 그 팀 줄에 사유 · 다른 팀 줄은 계속
            print(f"team={t['team']} state=X file=명단 못 풂({e})")
            continue
        hit = [p for p in cands if p.is_file() and p.stat().st_mtime >= float(since) and HEAD in p.read_text(encoding="utf-8")]  # type: ignore[arg-type]
        print(f"team={t['team']} state={'O' if hit else 'X'} file={hit[0] if hit else team_rel(str(t['team']))}")
    return 0


def _alive(seat: str) -> bool | None:
    """tmux 세션 생존 — True 살아 있음 · False 없음 · None 세션 목록 못 읽음."""
    try:
        p = subprocess.run(["tmux", "has-session", "-t", f"={seat}"], capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode == 0:
        return True
    return False if "can't find session" in p.stderr else None


def succession(old: str, new: str) -> tuple[bool, str]:
    """진짜 승계 = 새 이름이 구 좌석 계보 #N+1 ∧ 구 좌석 tmux 세션이 지금 살아 있음 · 명부 행이 닫힘 표시면 예외 0."""
    m = re.fullmatch(r"(.+)#([0-9]+)", old)
    if not m or new != f"{m.group(1)}#{int(m.group(2)) + 1}":
        return False, "새 이름이 구 좌석 계보 #N+1 아님"
    alive = _alive(old)
    if alive is None:
        return False, "tmux 세션 목록 못 읽음"
    if not alive:
        return False, f"구 좌석 세션 없음({old})"
    rows = []
    for f in glob.glob(str(root() / ".fable-team/seats*.json")):
        try:
            row = json.loads(Path(f).read_text(encoding="utf-8")).get(old)
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(row, dict):
            rows.append(row)
    if not rows:  # r4(DA⑥ r3): 명부 밖 이름 = 거절 — tmux 세션만으로는 좌석 증거가 아니다
        return False, f"구 좌석이 어느 명부에도 현역 행으로 없음({old})"
    for row in rows:
        role = str(row.get("role") or "")
        if role in ("closed", "stop-ready") or role.endswith("-retired") or row.get("_replaced_by") or row.get("_closed"):
            return False, f"명부 행 닫힘 표시(role={role or '-'})"
    return True, ""


def check(succ: list[str]) -> int:
    kind, why, _d = judge()
    if kind == "off":
        return 0
    if kind == "stop" and succ:
        ok, no = succession(succ[0], succ[1])
        if ok:
            print(f"INFO 전팀 정지 중이나 진짜 승계({succ[0]} → {succ[1]} · 구 좌석 세션 살아 있음)라 통과 — 같은 자리 교대(순증 0)", file=sys.stderr)
            return 0
        why += f" · 승계 예외 아님({no} · {succ[0]} → {succ[1]})"
    tail = " · 사람 확인" if kind == "hard" else " (ft-all-stop.sh status)"
    reason = f" · 사유: {_d.get('reason')}" if _d else ""
    print(f"REJECT 전팀 정지 중({why}) — 끄기 전 spawn·press 0{reason}{tail}")
    return 1


def init() -> int:
    """설치용(install.sh --apply) — 상태 폴더 + 원장 첫 줄(init). 원장이 이미 있으면 그대로(멱등) · 상태 파일이 있으면 init 줄은 on."""
    sd = state_dir()
    sd.mkdir(parents=True, exist_ok=True)
    if os.path.lexists(sd / LOG):
        print(f"ALL-STOP init 그대로 — 원장 있음({sd / LOG})")
        return 0
    kind = "on" if os.path.lexists(_file()) else "off"
    log(kind, "install", "init")
    print(f"ALL-STOP init {kind} — 원장 첫 줄({sd / LOG})")
    return 0


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    if cmd == "on" and len(argv) == 2 and argv[1].strip():
        return turn_on(argv[1])
    if cmd == "check" and (len(argv) == 1 or (len(argv) == 4 and argv[1] == "--succession")):
        return check(argv[2:])
    if cmd in ("off", "status", "init") and len(argv) == 1:
        return {"off": turn_off, "status": status, "init": init}[cmd]()
    print('usage: ft-all-stop.sh on "<사유>"|off|status|init|check [--succession <구 좌석> <새 좌석>]', file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
