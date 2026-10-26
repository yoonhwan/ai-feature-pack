"""R320b — 멈춘 좌석 감지 4종의 «판정» (읽기 전용 · 처리는 ft_stall_scan.py).

a 대기 카드 있는데 master IDLE · b 선언 뒤 IDLE · c 정책 정지(하네스 1건) · d 답 기다리며 3분+ (멈춘 쪽 = 받는이).
좌석 상태는 ft-seat-status.sh turn(jsonl IDLE/WORKING) 출력을 그대로 쓴다 — pane·mtime 을 쓰지 않는다.
"""
import json
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

IDLE_MIN = 3.0
FUTURE = re.compile(r"하겠습니다|할게요|진행하겠|착수하겠|진행할게")
REST = "[완료·휴식]"
REF = re.compile(r"indices/(대기|진행|완성)/([\w.\-]+)\.md")
OFF_ROLES = ("stop-ready", "closed")
AGENT = re.compile(r"(?:^|[\s/])(claude|codex)(?:\s|$)")


def run(cmd: list[str], env: dict[str, str] | None = None, timeout: float = 15) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 99, str(e)
    return r.returncode, r.stdout


def load_teams(root: Path) -> list[dict[str, Any]]:
    teams: list[dict[str, Any]] = []
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        label = d.get("_label") or ("v65" if f.name == "seats.json" else f.stem.removeprefix("seats-"))
        seats = {k: v for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)
                 and v.get("role") not in OFF_ROLES and not v.get("_replaced_by") and not v.get("_closed")}
        cards = root / ".worktrees" / d["_cards_wt"] / d["_cards"] if d.get("_cards_wt") and d.get("_cards") else (root / d["_cards"] if d.get("_cards") else None)
        mrow = d.get(d.get("_master") or "")
        teams.append({"team": label, "master": d.get("_master"), "cards": cards, "seats": set(seats),
                      "master_stop": isinstance(mrow, dict) and mrow.get("role") == "stop-ready"})  # r428 — ft-seat-close R297 표기
    return teams


def _roster_rows(root: Path) -> dict[str, dict[str, Any]]:
    """좌석 → 그 좌석 행이 있는 명부 전체(현역·교대 표시 행 모두)."""
    where: dict[str, dict[str, Any]] = {}
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        where.update({k: d for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)})
    return where


def _lineage_master(where: dict[str, dict[str, Any]], seat: str) -> str | None:
    """`_replaced_by` 사슬 끝 좌석이 있는 명부의 `_master` (끝을 못 찾으면 처음 명부) · 자기 자신이면 None."""
    end = seat
    for _ in range(10):
        nxt = (where.get(end) or {}).get(end, {}).get("_replaced_by")
        if not nxt:
            break
        end = nxt
    m = (where.get(end) or where[seat]).get("_master")
    return m if m and m != seat else None


def off_roster_live(root: Path, live: Any, teams: list[dict[str, Any]]) -> list[tuple[str, str | None, str]]:
    """r525 — tmux 라이브 좌석 중 명부 루프(load_teams 현역 행 · 팀 master)가 안 보는 것 → (좌석, 계보 현역 master|None, 교대 표시인데 라이브|명부 밖)."""
    seen = {s for t in teams for s in t["seats"]} | {t["master"] for t in teams}
    where = _roster_rows(root)
    return [(s, _lineage_master(where, s), "교대 표시인데 라이브") if s in where else (s, None, "명부 밖")
            for s in sorted(set(live) - seen)]


def _agent_pid(pid: str, kids: dict[str, list[str]], args: dict[str, str]) -> str | None:
    todo, seen = [pid], set()
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        if AGENT.search(args.get(p, "")):
            return p
        todo += kids.get(p, [])
    return None


def _pane_agents(tmux: list[str], ps: list[str]) -> dict[str, str]:
    """tmux 세션 이름 → 그 pane 프로세스(자신+자손) 중 claude|codex pid (ps 1회 + list-panes 1회)."""
    kids: dict[str, list[str]] = {}
    args: dict[str, str] = {}
    for line in run([*ps, "-A", "-o", "pid=,ppid=,args="])[1].splitlines():
        p = line.split(None, 2)
        if len(p) == 3:
            args[p[0]] = p[2]
            kids.setdefault(p[1], []).append(p[0])
    out: dict[str, str] = {}
    for line in run([*tmux, "list-panes", "-a", "-F", "#{session_name}|#{pane_pid}"])[1].splitlines():
        name, _, pid = line.rpartition("|")
        a = _agent_pid(pid, kids, args) if name and name not in out else None
        if a:
            out[name] = a
    return out


def agent_sessions(tmux: list[str], ps: list[str]) -> set[str]:
    """r525 — pane 프로세스(자신+자손)에 claude|codex 가 도는 tmux 세션 이름."""
    return set(_pane_agents(tmux, ps))


def ctx_pct(ctx_cmd: str, seat: str) -> int | None:
    """ft-claude-context.sh <좌석> → 사용률 % · 7초 상한 · 실패·숫자 아님 = None(추측 0)."""
    rc, out = run(["bash", ctx_cmd, seat], timeout=7)
    return int(out.strip()) if rc == 0 and out.strip().isdigit() else None


def turn_info(status_cmd: str, seat: str, path: str = "") -> tuple[str, float | None]:
    """ft-seat-status.sh turn 출력(STATE TURN_END ISO …) → (STATE, TURN_END epoch|None). DURATION_MS 는 나이가 아니다. 읽기 실패·UNKNOWN = ("UNKNOWN", None)."""
    rc, out = run(["bash", status_cmd, "turn", "--file", path] if path else ["bash", status_cmd, "turn", seat])
    p = out.split()
    if rc or not p:
        return "UNKNOWN", None
    end = None
    if len(p) > 1 and p[1] != "-":
        try:
            end = datetime.strptime(p[1][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            pass
    return p[0], end


def idle_minutes(status_cmd: str, seat: str, now: float) -> float | None:
    """IDLE 이면 지금 − TURN_END 분 · 그 밖(WORKING·PENDING·UNKNOWN·측정 불가)은 None."""
    state, end = turn_info(status_cmd, seat)
    return (now - end) / 60 if state == "IDLE" and end is not None else None


def spawn_capacity(root: Path, label: str, cap_cmd: str) -> str:
    """그 팀이 «지금 nano 를 열 수 있나» = 실제 spawn 과 같은 판정(ft_seat_cap.py: 팀 상한 + 위성 그룹 합 상한)을 팀 env 로 그대로 호출.
    "ok"(여유 또는 상한 env 없음) · "full"(REJECT 상한) · "unknown"(ERROR·판정기 없음 — 조용히 통과시키지 않는다)."""
    env = root / ".fable-team" / f"bin-{label}" / f"{label}-env.sh"
    if not env.exists():
        return "ok"  # 팀 env 가 없는 팀(v65 등)은 spawn 도 상한 검사 0
    if not Path(cap_cmd).exists():
        return "unknown"
    rc, out = run(["bash", "-c", '. "$1" && exec python3 "$2" --root "$3"', "_", str(env), cap_cmd, str(root)])
    if rc == 0:
        return "ok"
    return "full" if out.startswith("REJECT") else "unknown"


def _texts(rec: dict[str, Any]) -> tuple[list[str], bool]:
    content = (rec.get("message") or {}).get("content")
    if not isinstance(content, list):
        return [], False
    texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    tool = any(isinstance(b, dict) and b.get("type") == "tool_use" for b in content)
    return texts + [json.dumps(b.get("input", {}), ensure_ascii=False) for b in content if isinstance(b, dict) and b.get("type") == "tool_use"], tool


def last_turn(path: str, window: int = 524288) -> dict[str, Any]:
    """마지막 턴의 assistant 기록만 본다 → {rest: [완료·휴식] 실재, future: 끝 글이 미래형 선언 · 그 뒤 도구 0}."""
    try:
        size = Path(path).stat().st_size
        with open(path, "rb") as fh:
            fh.seek(max(0, size - window))
            raw = fh.read()
    except OSError:
        return {"rest": False, "future": False}
    recs: list[dict[str, Any]] = []
    for line in raw.split(b"\n"):
        try:
            recs.append(json.loads(line))
        except ValueError:
            continue
    ends = [i for i, r in enumerate(recs) if r.get("type") == "system" and r.get("subtype") == "turn_duration"]
    start = ends[-2] + 1 if len(ends) > 1 else 0
    turn = [r for r in recs[start:(ends[-1] + 1 if ends else len(recs))] if r.get("type") == "assistant"]
    rest = any(REST in t for r in turn for t in _texts(r)[0])
    future = False
    if turn:
        texts, tool = _texts(turn[-1])
        future = bool(texts) and not tool and bool(FUTURE.search(texts[-1].strip()[-100:]))
    return {"rest": rest, "future": future}


def _open_stems(cards_dir: Path) -> dict[str, set[str]]:
    """대기/·진행/ 에 실재하는 카드 stem — 목록으로 대조한다(대소문자 무시 파일시스템에서 exists() 는 «정확 일치» 가 아니다)."""
    return {k: {p.stem for p in (cards_dir / k).glob("*.md") if p.name != "README.md"} for k in ("대기", "진행")}


def _prereq(text: str, stems: dict[str, set[str]], me: str) -> str:
    """선행 줄 본문 1개 → ready | blocked:<이름> | unknown:<조건 40자>. 자동 판정 못 하는 글자(PR #N · 판정 N · 자유 문장)가 남으면 unknown — ready 로 되돌리지 않는다."""
    if not text or text.startswith("없음"):
        return "ready"
    for kind, name in REF.findall(text):
        if kind in stems and name in stems[kind]:
            return f"blocked:{name}"
    rest = REF.sub(" ", text)
    open_names = (stems["대기"] | stems["진행"]) - {me}
    for tok in re.findall(r"[\w.\-]+", rest):
        if tok.strip(".-") in open_names:
            return f"blocked:{tok.strip('.-')}"
    rest = rest.strip(" \t·,.;:—-()[]")
    return f"unknown:{rest[:40]}" if rest else "ready"


def card_ready(card: Path, cards_dir: Path, lint: str) -> str:
    """대기 카드 1장 → ready | blocked:<이름>(선행 카드가 대기/·진행/ 에 실재 · lint 실패 = blocked:(lint)) | unknown:<조건>(선행 자동 판정 불가 · 정상 대기로 보고 세지 않는다)."""
    if run(["bash", lint, str(card)])[0] != 0:
        return "blocked:(lint)"
    stems = _open_stems(cards_dir)
    verdicts = [_prereq(line.removeprefix("- 선행:").strip(), stems, card.stem)
                for line in card.read_text(encoding="utf-8").splitlines() if line.startswith("- 선행:")]
    return next((v for v in verdicts if v.startswith("blocked:")), None) or next((v for v in verdicts if v.startswith("unknown:")), "ready")


def waiting_cards(cards: Path | None, lint: str) -> tuple[list[str], int]:
    """→ (지금 spawn 할 수 있는 대기 카드 이름들, 선행 미판정 장수)."""
    d = cards / "대기" if cards else None
    if not d or not d.is_dir():
        return [], 0
    verdicts = {c.stem: card_ready(c, d.parent, lint) for c in sorted(d.glob("*.md")) if c.name != "README.md"}
    return [n for n, v in verdicts.items() if v == "ready"], sum(1 for v in verdicts.values() if v.startswith("unknown:"))


def policy_stop(root: Path, now: float, hold_cmd: str = "") -> str | None:
    """c 정책 정지 — RESOURCE_FREEZE 실재 또는 SPAWN_HOLD 가 «지금 유효»(R320 ft-spawn-hold.sh status --check <판정> rc0 · 기한·해제 조건 판정은 그쪽이 정본).
    판정기가 없거나 못 돌면 «정지 판정 불가» 로 센다(조용히 0 으로 두지 않는다 · #0 RULE) — 그 글은 `ERROR` 로 시작한다(r428).
    --check 는 측정 실패(status rc4 «ERROR hold …»)도 rc3 으로 감싸 돌려준다 → rc3 이라도 본문에 `ERROR hold` 가 있으면 판정 실패다(정지 없음으로 읽지 않는다)."""
    st = root / ".fable-team/state"
    if (st / "RESOURCE_FREEZE").exists():
        return "RESOURCE_FREEZE 실재"
    hold = st / "SPAWN_HOLD"
    if not hold.exists():
        return None
    try:
        verdict = str(json.loads(hold.read_text(encoding="utf-8"))["verdict"])
    except (OSError, ValueError, KeyError):
        return "ERROR SPAWN_HOLD 실재(판정 번호 읽기 실패) · 정지 판정 불가"
    if not hold_cmd or not Path(hold_cmd).exists():
        return f"ERROR SPAWN_HOLD 실재 hold={verdict} (ft-spawn-hold.sh 판정기 없음 — 유효 여부 판정 불가)"
    rc, out = run(["bash", hold_cmd, "status", "--check", verdict])
    if rc == 0:
        return f"SPAWN_HOLD 유효 · 정지 중(hold={verdict}) · 독촉 0"
    if rc == 3 and "ERROR hold" not in out:
        return None
    return f"ERROR SPAWN_HOLD 판정 실패 rc={rc} hold={verdict} {out.strip()[-80:]}"


def pending_mail(comm: Path, now: float) -> dict[str, tuple[int, float]]:
    """받는이 → (가장 오래된 미읽음 seq, 그 나이 분). 큐(mailbox.jsonl)에 남은 줄 = 아직 안 읽은 쪽지."""
    out: dict[str, tuple[int, float]] = {}
    try:
        lines = (comm / "mailbox.jsonl").read_text(encoding="utf-8").splitlines()
    except OSError:
        return out
    for line in lines:
        try:
            r = json.loads(line)
            age = (now - datetime.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 60
        except (ValueError, KeyError):
            continue
        if age >= IDLE_MIN and (r["to"] not in out or age > out[r["to"]][1]):
            out[r["to"]] = (int(r["seq"]), age)
    return out
