"""R320b — 멈춘 좌석 감지 4종의 «판정» (읽기 전용 · 처리는 ft_stall_scan.py).

r1001 — `lead_heartbeat` = 팀장이 보낸 mbox 쪽지 중 본문 머리 `[정리]` 인 마지막 줄의 ts(팀장 심박 · r1154: 승격분 `[HIL] … (원래 [정리])` 도).
  팀장 좌석의 b·d 경보는 이 심박이 LEAD_HEARTBEAT_MIN(20분) 안이면 0, 끊기면 팀 단위 1통(ft_stall_scan f).


a 대기 카드 있는데 master IDLE · b 선언 뒤 IDLE · c 정책 정지(하네스 1건) · d 답 기다리며 3분+ (멈춘 쪽 = 받는이).
좌석 상태는 ft-seat-status.sh turn(jsonl IDLE/WORKING) 출력을 그대로 쓴다 — pane·mtime 을 쓰지 않는다.
"""
import hashlib  # r1392 — lint 판(ft-index-lint.sh) sha256 = 캐시 열쇠
import json
import os
import re
import tempfile  # r1330 — ref 트리 대기 카드 읽기(임시 폴더)
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from ft_api_outage_util import epoch as api_epoch, is_error  # r1290: API 오류 표식 판정은 그쪽 한 벌(is_error)을 그대로 쓴다
import ft_stall_state as stm  # r1282 — 판정 단계 기한 D · 외부 호출 자식 묶음 정리
from ft_decision_kind import PROMOTED  # r1154: 승격 표식 정규식 한 벌(r1148) — 가져오기 실패는 예외 그대로
from ft_team_lib import basis_ref, roots
from ft_team_lib import rosters as team_rosters

IDLE_MIN = 3.0
LEAD_HEARTBEAT_MIN = 20.0  # 팀장 심박 주기 15분 + 여유 5 — 이보다 오래 조용하면 «멈춤» (r1391)
def role_key(name: str) -> str:
    """우편함 키 = 역할 이름(r1116 · comm/mbox_conf.role_key 와 같은 규칙) — 승계 뒤 옛 번호(planner#165) 앞 [정리] 도 그 역할(planner 현역 #166) 심박이다(r1116b ②)."""
    return re.sub(r"#\d+$", "", name or "")


HEARTBEAT_TOKEN = "[정리]"  # 팀장이 틱마다 보내는 «한 일 정리» 쪽지의 본문 머리
FUTURE = re.compile(r"하겠습니다|할게요|진행하겠|착수하겠|진행할게")
REST = "[완료·휴식]"
REST_MARK = re.compile(r"\[다음 없음\]|막힘 = 사람 답\(\d{10}\.\d{6}\)")  # r1729 — 쉼 심박 표식(첫 줄만 · A1)
LEAD_REST_MAX_MIN = 240.0  # r1729 — 쉼 면제 상한 4시간(A3)
_HB_EXTRA: dict[str, Any] = {}  # r1729 — _hb_line 이 같은 파싱에서 모으는 «쉼 심박 ts · 사건 ts»(읽기 1회)
REF = re.compile(r"indices/(대기|진행|완성)/([\w.\-]+)\.md")
OFF_ROLES = ("stop-ready", "closed")
AGENT = re.compile(r"(?:^|[\s/])(claude|codex)(?:\s|$)")


def run(cmd: list[str], env: dict[str, str] | None = None, timeout: float = 15, cwd: Path | None = None) -> tuple[int, str]:
    return stm.grun(cmd, env, timeout, cwd)  # r1282 — 자식 묶음 정리 · 판정 단계 기한 · r1759 cwd 없음(기본) = 지금 그대로


def load_teams(root: Path, warn: bool = True, active: bool = True, include_orphans: bool = False) -> list[dict[str, Any]]:
    teams: list[dict[str, Any]] = []
    for roster in team_rosters(root, active=active, include_orphans=include_orphans):
        d = roster["doc"] or {}
        team = roster["team"]
        if warn and roster["diag"] != "OK":
            print(f"WARN {team} 판정 불가({roster['diag']}) — stall 좌석 셈 제외")
        seats = {k: v for k, v in d.items() if not k.startswith("_") and isinstance(v, dict)
                 and v.get("role") not in OFF_ROLES and not v.get("_replaced_by") and not v.get("_closed")}
        cards = roster["cards"]
        mrow = d.get(d.get("_master") or "")
        teams.append({"team": team, "master": d.get("_master"), "cards": cards, "seats": set(seats),
                      "master_stop": isinstance(mrow, dict) and mrow.get("role") == "stop-ready", "diag": roster["diag"]})  # r428 — ft-seat-close R297 표기
    return teams


def _roster_rows(root: Path) -> dict[str, dict[str, Any]]:
    """좌석 → 그 좌석 행이 있는 명부 전체(현역·교대 표시 행 모두)."""
    where: dict[str, dict[str, Any]] = {}
    for roster in team_rosters(root):
        d = roster["doc"]
        if not isinstance(d, dict):
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


def other_root_seats(root: Path, warn: bool = True) -> set[str]:
    """r1309 §3-8 — roots.tsv 의 «다른 현역 루트» 좌석 이름(읽기 전용 제외 목록 · 쓰기 0).
    roots.tsv 없음 = 빈 집합(지금 동작) · TEAMS.md 가 없는 루트는 그 .fable-team/seats*.json 좌석 키로 본다.
    한 루트라도 못 읽으면 WARN/ERROR 1줄(조용한 0통 0)."""
    me = Path(root).resolve()
    names: set[str] = set()
    try:
        rows = roots()
    except Exception as e:  # noqa: BLE001 — 명부가 깨졌다: «제외 0» + 1줄
        if warn:
            print(f"ERROR 루트 명부 판정 불가({type(e).__name__}) — 다른 루트 좌석 제외 0")
        return names
    for row in rows:
        if row["state"] != "현역" or Path(row["path"]).resolve() == me:
            continue
        try:
            docs = [r["doc"] for r in team_rosters(Path(row["path"]))]
        except Exception as e:  # noqa: BLE001 — TEAMS.md 없음·깨짐 둘 다 «제외 목록을 그 파일들로»
            docs = _seat_docs(Path(row["path"]))
            if not docs and warn:
                print(f"WARN 다른 루트 {row['name']} 명부 판정 불가({type(e).__name__}) — 좌석 제외 0")
        for d in docs:
            if isinstance(d, dict):
                names |= {k for k in d if not k.startswith("_")}
    return names


def _seat_docs(base: Path) -> list[Any]:
    """그 루트의 .fable-team/seats*.json 본문들(명단 파일 없이 좌석 이름만 볼 때) · 못 읽은 파일은 건너뛴다."""
    out: list[Any] = []
    try:
        files = sorted((base / ".fable-team").glob("seats*.json"))
    except OSError:
        return out
    for f in files:
        try:
            out.append(json.loads(f.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            continue
    return out


def off_roster_live(root: Path, live: Any, teams: list[dict[str, Any]]) -> list[tuple[str, str | None, str]]:
    """r525 — tmux 라이브 좌석 중 명부 루프(load_teams 현역 행 · 팀 master)가 안 보는 것 → (좌석, 계보 현역 master|None, 교대 표시인데 라이브|명부 밖).
    r1309 §3-8: roots.tsv 의 «다른 루트» 명부에 있는 좌석은 «명부 밖» 이 아니다 — 그 루트 stall-scan 이 판정한다."""
    seen = {s for t in teams for s in t["seats"]} | {t["master"] for t in teams}
    where = _roster_rows(root)
    other = other_root_seats(root)
    return [(s, _lineage_master(where, s), "교대 표시인데 라이브") if s in where else (s, None, "명부 밖")
            for s in sorted(set(live) - seen) if s not in other]


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


GATE_SH = '''if [ -f "$1" ]; then . "$1"; fi
if [ "${FT_CARD_FLOW:-1}" = 0 ] || [ "${FT_CARD_CAP:-1}" = 0 ]; then exit 0; fi
exec bash "$2" --team "$3" --root "$4" --gate'''


def card_gate(root: Path, label: str, flow_cmd: str) -> int:
    """r1238 A-r4-2·3 — spawn 이 보는 카드 흐름 상한(ft-card-flow.sh --gate)을 a 후보 팀마다 1회 묻는다. 호출 상한 FT_STALL_GATE_SEC(기본 7초 · 판정 기한 밖).
    → 0 통과(팀 env 의 FT_CARD_FLOW=0·FT_CARD_CAP=0 이면 부르지 않고 0 · spawn 과 같은 스위치 · 팀 env 가 없는 팀도 부른다) · 4 상한 REJECT · 그 밖 = 확인 실패(시간 초과 124).
    우회 env FT_CARD_CAP_OK 는 card-flow 가 판정한다(env 그대로 넘김)."""
    env = root / ".fable-team" / f"bin-{label}" / f"{label}-env.sh"
    try:
        sec = float(os.environ.get("FT_STALL_GATE_SEC") or 7)
    except ValueError:
        sec = 7.0
    rc, _out = stm.grun(["bash", "-c", GATE_SH, "_", str(env), flow_cmd, label, str(root)], None, sec)
    return 124 if rc == 99 else rc


def _texts(rec: dict[str, Any]) -> tuple[list[str], bool]:
    content = (rec.get("message") or {}).get("content")
    if not isinstance(content, list):
        return [], False
    texts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
    tool = any(isinstance(b, dict) and b.get("type") == "tool_use" for b in content)
    return texts + [json.dumps(b.get("input", {}), ensure_ascii=False) for b in content if isinstance(b, dict) and b.get("type") == "tool_use"], tool


def last_turn(path: str, window: int = 524288) -> dict[str, Any]:
    """마지막 턴의 assistant 기록만 본다 → {rest: [완료·휴식] 실재, future: 끝 글이 미래형 선언 · 그 뒤 도구 0, err: 마지막 기록이 API 오류면 그 시각(r1290)}."""
    try:
        size = Path(path).stat().st_size
        with open(path, "rb") as fh:
            fh.seek(max(0, size - window))
            raw = fh.read()
    except OSError:
        return {"rest": False, "future": False, "err": None}
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
    return {"rest": rest, "future": future, "err": _error_at(turn[-1]) if turn else None}


def _error_at(rec: dict[str, Any]) -> float | None:
    """마지막 assistant 기록이 API 오류면 그 시각(epoch) · 아니면 None — 오류 판정은 ft_api_outage_util.is_error 한 벌(r1290)."""
    if not is_error(rec):
        return None
    try:
        return float(api_epoch(rec))
    except (ValueError, KeyError, TypeError):
        return None


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


LINT_MAX_AGE_S = 6 * 3600  # r1392 — 카드 lint 판정 기억 수명(oid·lint 판이 같아도 이보다 오래되면 다시 잰다)
LINT_UNKNOWN = "unknown:lint 미판정"  # r1392 — 실행당 lint 예산을 넘겨 못 잰 장(ready 아님 · a 후보 0 · 조용한 0 아님)
_LINT_STAMP: dict[str, str] = {}


def lint_stamp(lint: str) -> str:
    """r1392 — lint 판 = ft-index-lint.sh 파일 sha256 앞 16. 이 값이 바뀌면 옛 판정은 못 쓴다. 못 읽으면 ""(캐시 안 씀 → 다음 줄에서 그대로 lint)."""
    if lint not in _LINT_STAMP:
        try:
            _LINT_STAMP[lint] = hashlib.sha256(Path(lint).read_bytes()).hexdigest()[:16]
        except OSError:
            _LINT_STAMP[lint] = ""
    return _LINT_STAMP[lint]


def _lint_verdict(card: Path, lint: str, cache: dict[str, dict] | None, oid: str | None,
                  now: float | None, budget) -> str:
    """r1392 — 카드 1장 lint 판정 → ok | blocked | budget(이번 실행 예산 넘김).
    캐시(oid·lint 판 같음 ∧ at 이 LINT_MAX_AGE_S 안)면 프로세스 0, 아니면 budget() 이 허락할 때만 부른다."""
    stamp = lint_stamp(lint)
    hit = cache.get(card.stem) if cache is not None and oid and stamp else None
    t = time.time() if now is None else now
    if isinstance(hit, dict) and hit.get("oid") == oid and hit.get("lint") == stamp \
            and isinstance(hit.get("at"), (int, float)) and not isinstance(hit.get("at"), bool) \
            and 0 <= t - float(hit["at"]) <= LINT_MAX_AGE_S and hit.get("v") in ("ok", "blocked"):
        return str(hit["v"])
    if budget is not None and not budget():
        return "budget"
    v = "ok" if run(["bash", lint, str(card)])[0] == 0 else "blocked"
    if cache is not None and oid and stamp:
        cache[card.stem] = {"oid": oid, "lint": stamp, "v": v, "at": t}
    return v


def card_ready(card: Path, cards_dir: Path, lint: str, stems: dict[str, set[str]] | None = None, text: str | None = None,
               *, cache: dict[str, dict] | None = None, oid: str | None = None, now: float | None = None, budget=None) -> str:
    """대기 카드 1장 → ready | blocked:<이름>(선행 카드가 대기/·진행/ 에 실재 · lint 실패 = blocked:(lint)) | unknown:<조건>(선행 자동 판정 불가 · 정상 대기로 보고 세지 않는다).
    stems·text 를 주면(r1330 ref 트리 읽기) 디스크를 읽지 않는다 — 안 주면 지금처럼 cards_dir·card 파일.
    r1392: cache·oid 를 주면 lint 판정을 기억에서 쓰고, budget() 이 거절하면 LINT_UNKNOWN(선행 판정은 그대로 매번 한다)."""
    verdict = _lint_verdict(card, lint, cache, oid, now, budget)
    if verdict == "budget":
        return LINT_UNKNOWN
    if verdict != "ok":
        return "blocked:(lint)"
    stems = stems if stems is not None else _open_stems(cards_dir)
    body = text if text is not None else card.read_text(encoding="utf-8")
    verdicts = [_prereq(line.removeprefix("- 선행:").strip(), stems, card.stem)
                for line in body.splitlines() if line.startswith("- 선행:")]
    return next((v for v in verdicts if v.startswith("blocked:")), None) or next((v for v in verdicts if v.startswith("unknown:")), "ready")


class RefUnavailable(Exception):
    """r1330 A4 — 대기 카드를 ref 트리에서 못 읽었다(git 실패·상한 넘김·루트 명부 깨짐). 사유 1줄 = 그 팀 «a? … 판정 불가» (조용한 0 아님 · 하드 룰 #0)."""


def _git(args: list[str], cwd: Path, stdin: bytes | None = None) -> tuple[int, bytes, str]:
    """git 1회 → (rc, stdout, stderr 끝 줄 소문자) · 상한 = FT_STALL_GIT_SEC(기본 7초 · 하드 룰 12) · 못 끝내면 RefUnavailable. LC_ALL=C 로 «not a git repository» 문구를 고정한다."""
    try:
        sec = float(os.environ.get("FT_STALL_GIT_SEC") or 7)
    except ValueError:
        sec = 7.0
    # r1282 — git 도 같은 자식 묶음·판정 기한 경로(손자 고아 0 · 판정 기한 넘김 = 판정 불가) · 상한은 FT_STALL_GIT_SEC 그대로
    rc, out, err_text = stm.grun_raw(["git", *args], {**os.environ, "LC_ALL": "C"}, sec, cwd=cwd, stdin_bytes=stdin)
    if rc == 99:
        raise RefUnavailable(f"git 상한 넘김·실행 실패({err_text.strip()[:40]})" if err_text.strip() else "git 상한 넘김")
    lines = err_text.strip().splitlines()
    return rc, out, (lines[-1] if lines else "").lower()


def _ref_stems(cards: Path, ref: str) -> tuple[dict[str, set[str]], dict[str, str]] | None:
    """A1 — ref 트리의 대기/·진행/ 카드 stem + 대기 카드 blob oid(팀마다 ls-tree 1회 · README.md 뺌 · 호출 수는 그대로).
    r1392 — oid 도 같이 받는다(두 번째 호출 0): 캐시가 «카드 본문이 바뀌었나» 를 이 값으로 본다. git 리포 아님 = None(디스크 · oid 없음)."""
    rc, out, err = _git(["ls-tree", "-z", ref, "--", "대기/", "진행/"], cards)
    if rc != 0:
        if "not a git repository" in err:
            return None
        raise RefUnavailable(f"git ls-tree rc={rc} {err[-60:]}")
    stems: dict[str, set[str]] = {"대기": set(), "진행": set()}
    oids: dict[str, str] = {}
    for entry in out.decode("utf-8", "replace").split("\0"):
        meta, _, path = entry.partition("\t")  # <mode> SP <type> SP <oid> TAB <path>
        head = meta.split()
        kind, _, name = path.partition("/")
        if len(head) != 3 or kind not in stems or not name.endswith(".md") or "/" in name or name == "README.md":
            continue
        stems[kind].add(name[:-3])
        if kind == "대기":
            oids[name[:-3]] = head[2]
    return stems, oids


def _ref_bodies(cards: Path, ref: str, names: list[str]) -> dict[str, str]:
    """A2 — 대기 카드 본문 묶음(cat-file --batch 1회). 한 장이라도 못 읽으면 RefUnavailable."""
    rc, out, err = _git(["cat-file", "--batch"], cards, "".join(f"{ref}:./대기/{n}.md\n" for n in names).encode("utf-8"))
    if rc != 0:
        raise RefUnavailable(f"git cat-file rc={rc} {err[-60:]}")
    bodies: dict[str, str] = {}
    pos = 0
    try:
        for n in names:
            eol = out.index(b"\n", pos)
            head = out[pos:eol].split()
            if len(head) != 3 or head[1] != b"blob":
                raise RefUnavailable(f"카드 본문 읽기 실패({n})")
            start = eol + 1
            bodies[n] = out[start:start + int(head[2])].decode("utf-8")
            pos = start + int(head[2]) + 1
    except (ValueError, UnicodeError):
        raise RefUnavailable("카드 본문 해석 실패") from None
    return bodies


def _ref_verdicts(cards: Path, lint: str, root: Path | None, *, cache: dict[str, dict] | None = None,
                  seen: set[str] | None = None, now: float | None = None, budget=None) -> dict[str, str] | None:
    """A1~A3 — 그 팀 대기 카드 → 판정. 기준 ref = roots.tsv «기준 ref»(없으면 origin/main). git 리포 밖 폴더 = None(디스크로).
    r1392 — cache(카드 stem → {oid, lint, v, at}) 를 주면 lint 판정을 기억하기도 하고 쓰기도 한다 · seen 에 이번에 본 stem 을 모은다."""
    try:
        ref = basis_ref(root) if root else "origin/main"
    except Exception as e:  # noqa: BLE001 — 루트 명부 깨짐 = 판정 불가 1줄(조용한 기본값 0)
        raise RefUnavailable(f"루트 명부 판정 불가({e.__class__.__name__})") from None
    found = _ref_stems(cards, ref)
    if found is None:
        return None
    stems, oids = found
    names = sorted(stems["대기"])
    if seen is not None:
        seen.update(names)
    bodies = _ref_bodies(cards, ref, names) if names else {}
    verdicts: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="ft-stall-ref-") as td:  # lint 는 파일을 받는다 — 같은 이름의 임시 파일
        (Path(td) / "대기").mkdir()
        for n in names:
            f = Path(td) / "대기" / f"{n}.md"
            _ = f.write_text(bodies[n], encoding="utf-8")
            verdicts[n] = card_ready(f, cards, lint, stems, bodies[n], cache=cache, oid=oids.get(n), now=now, budget=budget)
    return verdicts


LEDGER_STATES = ("seat", "waiting", "none")
HUMAN_WAIT = ("사람", "면제대기")  # 사람 결정 몫 — 원장 waiting 이면 계속 a 후보 밖
NUDGE_WINDOW_S = 7200  # r1238 A-r4-1 — 그 밖 사유 waiting 카드는 max(원장 updated, 마지막 a 재촉) 뒤 2시간까지 a 후보 밖
CLOCK_SKEW_S = 60  # A-r4b-3 — 시계 오차 허용


def _ledger_row(path: Path, stem: str, now: float) -> dict[str, Any] | None:
    """A-r4-3 — 카드 배정 원장 1장 읽기 → 꼴 검사 통과한 dict · 파일 없음 = None(지금처럼 ready) · 읽기 실패·꼴 위반·미래 updated = RefUnavailable(그 팀 a 0 + «a?» 1줄)."""
    from ft_card_assign_watch import LEGACY, REASONS  # 늦은 가져오기 — ft_penalty ↔ ft_stall_detect 순환 회피
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeError) as e:
        raise RefUnavailable(f"배정 원장 읽기 실패 {stem}({e.__class__.__name__})") from None
    try:
        row = json.loads(raw)
    except ValueError:
        raise RefUnavailable(f"배정 원장 JSON 깨짐 {stem}") from None
    upd = row.get("updated") if isinstance(row, dict) else None
    if not isinstance(row, dict) or row.get("state") not in LEDGER_STATES or isinstance(upd, bool) or not isinstance(upd, (int, float)) \
            or row["state"] == "waiting" and row.get("reason") not in (*REASONS, *LEGACY):
        raise RefUnavailable(f"배정 원장 꼴 위반 {stem}")
    if upd > now + CLOCK_SKEW_S:
        raise RefUnavailable(f"updated 미래 {stem}")
    return row


def _ledger_holds(root: Path, stem: str, now: float, nudged: dict[str, float], notes: list[str]) -> bool:
    """이 ready 카드를 a 후보에서 뺄까 — 원장 waiting 중 사람·면제대기 = 계속 · 그 밖 사유 = now − max(updated, 마지막 a 재촉) < 2시간 · seat·none·원장 없음·옛 «부하» 행 = 지금처럼 후보."""
    from ft_card_assign_watch import LEGACY
    row = _ledger_row(root / ".fable-team/state/card-assign" / f"{stem}.json", stem, now)
    if row is None or row["state"] != "waiting" or row.get("reason") in LEGACY:
        return False
    if row["reason"] in HUMAN_WAIT:
        return True
    last = nudged.get(stem)
    if last is not None and last > now + CLOCK_SKEW_S:  # A-r4b-3 — 미래 재촉 기록은 버리고 기록 없음으로 판정
        del nudged[stem]
        notes.append(f"재촉 기록 미래 값 버림 {stem}")
        last = None
    return now - max(float(row["updated"]), last or 0.0) < NUDGE_WINDOW_S


def waiting_cards(cards: Path | None, lint: str, root: Path | None = None, now: float | None = None,
                  nudged: dict[str, float] | None = None, notes: list[str] | None = None,
                  cache: dict[str, dict] | None = None, seen: set[str] | None = None, budget=None) -> tuple[list[str], int, int]:
    """→ (지금 spawn 할 수 있는 대기 카드 이름들, 선행 미판정 장수, lint 미판정 장수). r1330: git 리포 안이면 기준 ref 트리에서 읽는다(디스크 체크아웃이 뒤처져도 옛 카드 0) · 못 읽으면 RefUnavailable.
    r1238 A: now 를 주면 ready 카드마다 배정 원장(<루트>/.fable-team/state/card-assign/<카드>.json)을 같은 함수로(ref·디스크 두 길 공통) 대조해 뺀다 — 원장 못 읽음·꼴 위반 = RefUnavailable.
    nudged = {카드 stem: 마지막 a 재촉 epoch}(미래 값은 지우고 notes 에 1줄).
    r1392: cache·now 로 lint 판정을 기억해 바뀐 카드만 lint 하고, budget() 이 거절하면 그 장은 LINT_UNKNOWN(ready 아님 · 셋째 값으로 센다)."""
    if not cards:
        return [], 0, 0
    verdicts = _ref_verdicts(cards, lint, root, cache=cache, seen=seen, now=now, budget=budget)
    if verdicts is None:
        d = cards / "대기"
        if not d.is_dir():
            return [], 0, 0
        disks = sorted((c for c in d.glob("*.md") if c.name != "README.md"), key=lambda c: c.stem)
        verdicts = {c.stem: card_ready(c, d.parent, lint, now=now, budget=budget) for c in disks}
        if seen is not None:
            seen.update(c.stem for c in disks)
    ready = [n for n, v in verdicts.items() if v == "ready"]
    if root is not None and now is not None:  # 두 길(디스크·ref 트리) 공통 — 같은 함수
        sink: list[str] = notes if notes is not None else []
        mine = nudged if nudged is not None else {}
        ready = [n for n in ready if not _ledger_holds(root, n, now, mine, sink)]
    missed = sum(1 for v in verdicts.values() if v == LINT_UNKNOWN)
    return ready, sum(1 for v in verdicts.values() if v.startswith("unknown:") and v != LINT_UNKNOWN), missed


OUTAGE_STATUS = ("OK", "OUTAGE", "RECOVERED")  # ft_api_outage.Outage.load 와 같은 꼴 검사
OUTAGE_FRESH_S = 1800  # 데몬이 틱마다 저장 — 30분 넘게 안 바뀐 파일은 데몬이 꺼진 것(영구 보류 0 · once_set_state_needs_closing_event)


def _num(v: object) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def api_outage(root: Path, now: float) -> dict[str, Any]:
    """r1238 B — API 장애 상태 읽기(읽기 전용 · 쓰기 0 · 정본 = <루트>/.fable-team/state/api-outage/seats*.json 틱 데몬마다 1개).
    → {"since": 신선한 OUTAGE 파일 중 가장 이른 since | None, "released": 신선한 OK·RECOVERED 파일 released 최댓값 | None, "notes": [판정 불가·오래됨 1줄씩]}.
    폴더 없음(aifp 루트 등) = 장애 아님 · 깨진 파일(JSON·꼴) = 판정에서 빼고 «판정 불가» 노트 · mtime 30분 넘음 = 판정에서 빼고 «오래됨» 노트 → 남은 파일 0 이면 지금처럼 경보."""
    out: dict[str, Any] = {"since": None, "released": None, "notes": []}
    d = root / ".fable-team/state/api-outage"
    for p in sorted(d.glob("seats*.json")) if d.is_dir() else []:
        try:
            st = json.loads(p.read_text(encoding="utf-8"))
            mt = p.stat().st_mtime
        except (OSError, ValueError):
            out["notes"].append(f"장애 상태 판정 불가 {p.name}")
            continue
        status = st.get("status") if isinstance(st, dict) else None
        if status not in OUTAGE_STATUS or status == "OUTAGE" and not _num(st.get("since")) or status != "OUTAGE" and st.get("released") is not None and not _num(st.get("released")):
            out["notes"].append(f"장애 상태 판정 불가 {p.name}")
            continue
        if now - mt > OUTAGE_FRESH_S:
            out["notes"].append(f"장애 상태 오래됨 {p.name} {(now - mt) / 60:.0f}분 — 경보 그대로")
            continue
        if status == "OUTAGE":
            out["since"] = min(st["since"], out["since"]) if out["since"] is not None else st["since"]
        elif st.get("released"):
            out["released"] = max(st["released"], out["released"] or 0)
    return out


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


def all_stop(root: Path) -> tuple[str, float | None, str]:
    """r1371 — 전팀 정지 표식(<루트>/.fable-team/state/ALL_STOP.json · r626 정본 ft-all-stop.sh) 읽기 «한 곳».
    → ("on", since 초, "") · ("off", None, "") = 파일 없음 · ("unknown", None, 사유) = 깨짐·읽기 실패.
    판정 꼴 = 카드 r1371 §설계 1: 있으면 on · 없으면 off · 깨졌으면 unknown(경보 그대로 + «판정 불가 ALL_STOP» 1줄).
    ★표식의 «정본 판정» 은 ft_all_stop.py(read·원장)다 — 여기서는 «멈춤 경보를 보류할 만큼 확실한가» 만 본다.
    원장(all-stop.log)은 보지 않는다(카드 §구현 범위 — 상태 파일 1개만) · 사람이 파일을 지우면 off 로 돌아온다.
    """
    path = root / ".fable-team/state/ALL_STOP.json"
    if not os.path.lexists(path):
        return "off", None, ""
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return "unknown", None, type(error).__name__
    if not isinstance(doc, dict):
        return "unknown", None, f"JSON {type(doc).__name__}"
    try:
        since = float(doc.get("since"))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return "unknown", None, "since 없음·꼴 틀림"
    return "on", since, ""


def all_stop_note(kind: str, team: str, since: float | None) -> str:
    """r1371 — 보류 노트 1줄 «보류 <f|h|a> <팀> — 전팀 정지(since <HH:MM>)»(감시기 로그·화면 같은 꼴)."""
    hm = time.strftime("%H:%M", time.localtime(since)) if since is not None else "?"
    return f"보류 {kind} {team} — 전팀 정지(since {hm})"


def pending_mail(comm: Path, now: float) -> dict[str, tuple[int, float]]:
    """받는이 → (가장 오래된 미읽음 seq, 그 나이 분). 큐(mailbox.jsonl)에 남은 줄 = 아직 안 읽은 쪽지."""
    out: dict[str, tuple[int, float]] = {}
    try:
        fh = open(comm / "mailbox.jsonl", encoding="utf-8")
    except OSError:
        return out
    with fh:  # r1282 — 줄 단위로 읽으며 200줄마다 판정 기한 검사(기한 예외에도 핸들이 닫힌다)
        for i, line in enumerate(fh):
            if i % 200 == 199:
                stm.check()
            try:
                r = json.loads(line)
                age = (now - datetime.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S").timestamp()) / 60
            except (ValueError, KeyError):
                continue
            if age >= IDLE_MIN and (r["to"] not in out or age > out[r["to"]][1]):
                out[r["to"]] = (int(r["seq"]), age)
    return out


def lead_names(root: Path, master: str | None) -> set[str]:
    """그 팀 명부에서 «현역 role=master» 인 좌석 전부 — 승계 직후 옛·새 둘 다 현역이면 둘 다 인정한다.
    `_replaces` 에만 남은 옛 이름은 현역이 아니다: 인정하지 않는다(DA r1 반례 4·5)."""
    if not master:
        return set()
    for roster in team_rosters(root):
        d = roster["doc"]
        if not isinstance(d, dict):
            continue
        rows = {k for k, v in d.items() if not k.startswith("_") and isinstance(v, dict) and v.get("role") == "master"
                and not v.get("_replaced_by") and not v.get("_closed")}
        if master in rows:  # 내 행이 있는 명부 = 내 팀 명부
            return set(rows)
    return {master}


def _is_heartbeat_body(body: object) -> bool:
    """머리 [정리] ∨ mbox_guard 승격분(머리 [HIL] · 첫 줄 끝 «(원래 [정리])» · r1098) — 판정 정규식은 ft_decision_kind.PROMOTED 한 벌(r1154)."""
    if not isinstance(body, str):
        return False
    head = body.lstrip()
    return head.startswith(HEARTBEAT_TOKEN) or (head.startswith("[HIL]") and bool(PROMOTED.search(head.split("\n", 1)[0].strip()))) or rest_head(body)


def rest_head(body: object) -> bool:
    """r1949 — 쉼 머리 규칙 한 벌(r1729 쉼 면제 · r1647 닫기 대기): 첫 줄 REST_MARK ∧ (머리 [정리]·[다음 없음]·«막힘 = 사람 답(» ∨ 승격 꼴 [HIL]+PROMOTED)."""
    if not isinstance(body, str):
        return False
    first = body.lstrip().split("\n", 1)[0]
    heads = first.startswith((HEARTBEAT_TOKEN, "[다음 없음]", "막힘 = 사람 답(")) or (first.startswith("[HIL]") and bool(PROMOTED.search(first.strip())))
    return heads and bool(REST_MARK.search(first))


def _rest_mark(body: object) -> bool:
    """r1729 — 쉼 표식은 «첫 줄» 에서만 센다(A1 · 반례 ④) · 판정 = rest_head 한 벌(r1949)."""
    return rest_head(body)


def _hb_line(line: str, masters: set[str], recipients: set[str], now: float) -> tuple[float | None, bool, bool]:
    """쪽지 1줄 → (ts, 심박인가, 깨진 줄인가). ts 는 «모든» 줄에서 뽑는다 — 로그를 끝에서 읽으며 창 밖에서 멈추는 기준(r1020)."""
    try:
        r = json.loads(line)
    except ValueError:
        return None, False, True
    if not isinstance(r, dict):
        return None, False, True
    try:
        ts = datetime.strptime(str(r.get("ts"))[:19], "%Y-%m-%dT%H:%M:%S").timestamp()
    except ValueError:
        return None, False, True
    if ts > now + 5:  # 미래 ts = 시계 어긋남 — 신선으로 읽지 않는다
        return ts, False, True
    keys = {role_key(x) for x in masters}  # r1729 — «그 팀장» 과 오간 쪽지 = 사건(A2)
    if r.get("from") != "ft-stall-scan" and (role_key(str(r.get("to"))) in keys or role_key(str(r.get("from"))) in keys):
        _HB_EXTRA.setdefault("ev", []).append(ts)  # 스캐너의 [멈춤] 은 사건이 아니다(반례 ⑧)
    body = r.get("body")
    if not _is_heartbeat_body(body):
        return ts, False, False  # 심박 아닌 쪽지(발주·보고)는 판정 대상이 아니다
    if r.get("from") not in masters or role_key(str(r.get("to"))) not in {role_key(x) for x in recipients}:
        return ts, False, False  # 발신자가 현역 팀장이 아니거나, 받는이가 master/planner «역할» 이 아니면 심박이 아니다(반례 2·4·5)
    if _rest_mark(body):  # r1729 — 쉼 심박(첫 줄 표식 · A1)
        _HB_EXTRA["rest"] = max(ts, _HB_EXTRA.get("rest") or 0.0)
    return ts, True, False


def _lines_from_end(fh, chunk: int = 1 << 16):
    """파일 «끝» 에서 거꾸로 줄을 낸다 — 전체 읽기 0(r1020). 마지막 줄이 개행 없이 끝나도 낸다."""
    fh.seek(0, os.SEEK_END)
    pos, buf = fh.tell(), b""
    while pos > 0:
        step = min(chunk, pos)
        pos -= step
        fh.seek(pos)
        buf = fh.read(step) + buf
        parts = buf.split(b"\n")
        buf = parts[0]
        for raw in reversed(parts[1:]):
            yield raw
    if buf:
        yield buf


def _read_mailbox(path: Path, masters: set[str], recipients: set[str], now: float, budget: float, t0: float) -> tuple[str, float | None, int, int]:
    """안 읽은 쪽지 큐 전체 읽기(작다). → (에러 이유, 최신 심박 ts, 깨진 줄 수, 줄 수)."""
    best, broken, n = None, 0, 0
    try:
        fh = open(path, encoding="utf-8")
    except FileNotFoundError:
        return f"mailbox.jsonl 없음({path})", None, 0, 0
    except OSError as e:
        return f"mailbox.jsonl 읽기 실패 {e.__class__.__name__}", None, 0, 0
    with fh:
        for line in fh:
            n += 1
            if n % 200 == 0:
                stm.check()  # r1282
            if n % 256 == 0 and time.monotonic() - t0 > budget:
                return f"심박 읽기 {budget:g}초 초과(줄 {n})", None, 0, n
            ts, hb, bad = _hb_line(line, masters, recipients, now)
            broken += bad
            if hb and (best is None or ts > best):
                best = ts
    return "", best, broken, n


def _read_mailbox_log(path: Path, masters: set[str], recipients: set[str], now: float, window: float, budget: float, t0: float) -> tuple[str, float | None, int, int]:
    """읽은 쪽지 로그(mailbox.log.jsonl)를 «끝에서» 읽어 심박 창(window 분) 안만 본다 — r1020: recv 가 레코드를 큐→로그로 옮기므로 큐만 보면 심박이 사라진다.
    창 밖 줄에 닿으면 멈춘다(큰 로그 4.4MB 전체 읽기 0 · 예산은 큐와 공유). 로그 파일 없음 = 큐만(ERROR 아님).
    → (에러 이유, 최신 심박 ts, 깨진 줄 수, 줄 수)."""
    best, broken, n = None, 0, 0
    try:
        fh = open(path, "rb")
    except FileNotFoundError:
        return "", None, 0, 0  # 로그 없음 = 큐만 본다(판정 불가 아님)
    except OSError as e:
        return f"mailbox.log.jsonl 읽기 실패 {e.__class__.__name__}", None, 0, 0
    with fh:
        for raw in _lines_from_end(fh):
            line = raw.decode("utf-8", "replace")
            if not line.strip():
                continue
            n += 1
            if n % 200 == 0:
                stm.check()  # r1282
            if n % 256 == 0 and time.monotonic() - t0 > budget:
                return f"심박 읽기 {budget:g}초 초과(줄 {n})", None, 0, n
            ts, hb, bad = _hb_line(line, masters, recipients, now)
            if ts is not None and (now - ts) / 60 > window:
                break  # r1020 창 밖 — 더 옛 줄은 안 본다
            broken += bad
            if hb and (best is None or ts > best):
                best = ts
    return "", best, broken, n


def lead_heartbeat(comm: Path, masters: set[str], recipients: set[str], now: float) -> tuple[str, float | None, str]:
    """팀장 심박 = «현역 팀장» 이 «master 또는 planner» 에게 보낸 쪽지 중 본문 머리 `[정리]` 인 마지막 줄의 ts(epoch · 읽기 전용).
    입력 = 안 읽은 큐(mailbox.jsonl) + 읽은 로그(mailbox.log.jsonl) 둘 다 — 받는 쪽이 recv 하면 레코드가 로그로 옮겨가므로 큐만 보면 제때 보낸 팀장도 «한 번도 안 보냄» 으로 읽힌다(r1020).
    → ("ok", ts|None, "") · ("ERROR", None, 이유) = 판정 불가(큐 없음·읽기 실패·예산 초과·깨진 줄 있음).
    깨진 줄이 하나라도 있으면 «조용한 0통» 으로 넘기지 않고 판정 불가로 돌려준다(DA r1 반례 3) — 그 좌석은 처리 0 + u.
    미래 ts(시계 어긋남)는 «신선» 으로 인정하지 않고 그 줄을 버린다 — 신선으로 읽으면 영영 조용해진다.
    예산 = FT_STALL_HEARTBEAT_BUDGET(기본 7초). 넘으면 부분 결과를 쓰지 않고 판정 불가(7초 룰)."""
    budget = float(os.environ.get("FT_STALL_HEARTBEAT_BUDGET") or 7)
    t0 = time.monotonic()
    err, best, broken, n = _read_mailbox(comm / "mailbox.jsonl", masters, recipients, now, budget, t0)
    if err:
        return "ERROR", None, err
    err, ts, bad, n2 = _read_mailbox_log(comm / "mailbox.log.jsonl", masters, recipients, now, lead_heartbeat_min(), budget, t0)
    if err:
        return "ERROR", None, err
    broken += bad
    n += n2
    if ts is not None and (best is None or ts > best):
        best = ts
    if broken:
        return "ERROR", None, f"쪽지 깨진 줄 {broken}개 — 심박 판정 불가"
    if time.monotonic() - t0 > budget:
        return "ERROR", None, f"심박 읽기 {budget:g}초 초과(줄 {n})"
    return "ok", best, ""


def lead_heartbeat_min() -> float:
    """임계 = FT_LEAD_HEARTBEAT_MIN(기본 20 = 주기 15분 + 여유 5 · r1391). 값이 이상하면 기본을 쓴다."""
    try:
        v = float(os.environ.get("FT_LEAD_HEARTBEAT_MIN") or LEAD_HEARTBEAT_MIN)
    except ValueError:
        return LEAD_HEARTBEAT_MIN
    return v if v > 0 else LEAD_HEARTBEAT_MIN


def lead_rest_max_min() -> float:
    """면제 상한 = FT_LEAD_REST_MAX_MIN(기본 240분 = 4시간 · r1729 A3). 값이 이상하면 기본을 쓴다."""
    try:
        v = float(os.environ.get("FT_LEAD_REST_MAX_MIN") or LEAD_REST_MAX_MIN)
    except ValueError:
        return LEAD_REST_MAX_MIN
    return v if v > 0 else LEAD_REST_MAX_MIN


def lead_rest_state(comm: Path, masters: set[str], recipients: set[str], now: float) -> tuple[str, float | None, float | None]:
    """r1729 — 쉼 심박(A1)과 그 뒤 첫 사건(A2)을 «면제 상한» 창까지 한 번 더 읽어 낸다.
    → ("ok", 쉼 심박 ts|None, 그 뒤 첫 사건 ts|None) · ("ERROR", None, None) = 쉼 로그 판정 불가(깨진 줄·7초 예산 · A4).
    쉼 심박이 상한(FT_LEAD_REST_MAX_MIN · A3)을 넘었으면 ("ok", None, None) = 면제 0(지금 판정 그대로).
    읽기는 lead_heartbeat 와 같은 끝 읽기·예산을 쓰고 로그 창만 상한까지 넓힌다(A4).
    ERROR 는 «면제 0» 이다 — 부르는 쪽(lead_alert)은 이때 지금 판정(경보 후보 = 경보 1)을 그대로 쓴다(A5 · 탐침 ⑬)."""
    budget = float(os.environ.get("FT_STALL_HEARTBEAT_BUDGET") or 7)
    t0 = time.monotonic()
    cap = lead_rest_max_min()
    _HB_EXTRA.clear()  # 같은 파싱에서 모은 쉼·사건은 이번 읽기의 것만 쓴다
    err, _best, broken, _n = _read_mailbox(comm / "mailbox.jsonl", masters, recipients, now, budget, t0)
    if err:
        return "ERROR", None, None
    err, _ts, bad, _n2 = _read_mailbox_log(comm.joinpath("mailbox.log.jsonl"), masters, recipients, now, cap, budget, t0)
    if err:
        return "ERROR", None, None
    if broken + bad:
        return "ERROR", None, None  # 판정 불가 = 처리 0 + u(A4 · 반례 ⑪)
    if time.monotonic() - t0 > budget:
        return "ERROR", None, None
    rest = _HB_EXTRA.get("rest")
    if rest is None or (now - rest) / 60 > cap:
        return "ok", None, None
    ev = [t for t in _HB_EXTRA.get("ev", []) if t > rest]
    return "ok", rest, min(ev) if ev else None


def lead_recipients(root: Path, warn: bool = False) -> set[str]:
    """심박 받는이 = 명부 «전체» 의 현역 role=master + 현역 planner(planner 팀장도 role=master) — DA r2 반례 2.
    자기 팀 _master 로 좁히면 «다른 팀 현역 master 에게 보낸 신선한 [정리]» 를 놓쳐 멀쩡한 팀장이 멈춤으로 읽힌다.
    r1143 — 현역 role=desk 도 받는이다: planner 팀장의 보고처 = desk 라 [정리] 가 전부 desk 앞이다(planner#166~#171 54통)."""
    out: set[str] = set()
    for roster in team_rosters(root):
        d = roster["doc"]
        if not isinstance(d, dict):
            if warn and roster["diag"] != "OK":
                print(f"WARN {roster['team']} 판정 불가({roster['diag']}) — 심박 수신자 셈 제외")
            continue
        out |= {k for k, v in d.items() if not k.startswith("_") and isinstance(v, dict) and v.get("role") in ("master", "desk")
                and not v.get("_replaced_by") and not v.get("_closed")}
    return out


def lead_alert(root: Path, comm: Path, master: str, now: float) -> tuple[bool, float | None, bool]:
    """심박 → 경보 판정 «한 함수» (C6: 이 판정은 scan 이 아니라 여기 산다). → (경보, 심박 나이 분|None, 판정 불가)."""
    state, ts, _why = lead_heartbeat(comm, lead_names(root, master), lead_recipients(root), now)
    if state == "ERROR":
        return False, None, True
    if ts is None or (now - ts) / 60 > lead_heartbeat_min():  # r1729 — 경보 후보일 때만 쉼 면제를 본다(늘 읽기 1회 더는 아니다)
        rstate, rest, first_ev = lead_rest_state(comm, lead_names(root, master), lead_recipients(root), now)
        if rstate == "ok" and rest is not None:  # rstate ERROR = 쉼 로그 판정 불가 → 면제 0 = 지금 판정 그대로(A5 · 진짜 멈춤을 가리지 않는다)
            if first_ev is None:  # 쉼 심박 뒤 사건 0 = 경보 0(A1)
                return False, (now - rest) / 60, False
            return (now - first_ev) / 60 > lead_heartbeat_min(), (now - first_ev) / 60, False  # 사건이 있으면 첫 사건 ts 부터 다시 센다(A2)
    if ts is None:
        return True, None, False  # 심박 창(20분) 안 [정리] 0 = 멈춤 — 로그는 창 안만 읽으므로 «한 번도 안 보냄» 이 아니다(r1143)
    age = (now - ts) / 60
    return age > lead_heartbeat_min(), age, False
