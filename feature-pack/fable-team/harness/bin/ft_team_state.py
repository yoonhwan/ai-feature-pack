"""ft_team_state — 팀 상태 판정기 하나(r850): «진행 · 대기 · 쉼 · 확인 불가». 뉴스 지도·요약 첫 줄(ft_news_html)과
시트 뿌리 글 팀 표(ft_board_teams · r785)가 같은 judge() 를 부른다 — 같은 입력이면 세 곳이 같은 글자를 낸다.

  진행 = 턴이 열린 좌석(WORKING·PENDING) ≥1(진행 카드 0 이면 «진행 · 진행 카드 0 · …» 글자로 구분 · r2 계약 개정) ·
         또는 진행 카드 ≥1(카드 폴더 없는 팀은 카드 조건 없음) ∧ 최근 WINDOW_MIN(30)분 안에 턴이 끝난 좌석 ≥1
  쉼   = 진행 카드 0 ∧ 열린 턴 0(좌석 수·30분 안 IDLE 무관) · 카드 폴더 없는 팀은 30분 안 턴도 0 이고 확인 불가 좌석 0 — 좌석 0 이면 «쉼 · 열린 좌석 0»(r785 꼴)
  확인 불가 = 진행이 아니고 턴 판정 못 한 좌석(«?») ≥1 — 사유 «jsonl 없음 N석» 꼴(쉼으로 보지 않는다 · r490)
  대기 = 그 밖(진행 카드 ≥1 · 좌석이 30분 넘게 조용하거나 열린 좌석 0) — «대기 N분 · 기다리는 것 = <master 칸 wait 그대로>» ·
         좌석 0 갈래도 «대기 · 열린 좌석 0 · 기다리는 것 = …»(r2)
옛 판정(«지금 이 순간 WORKING 좌석 수» 하나)은 60초 틱 사이에 턴이 끝난 팀·나노 결과를 기다리는 팀을 «쉬는 팀» 으로 냈다(13:51 ops·knowledge).

판정 한 곳(r5) = team_states(root, …) → {팀: {state·label·wait·live·working·unknown·unknown_reason}} — 뉴스(live_teams·facts·지도)와
시트(ft_board_collect 가 블록에 붙이는 team_state → ft_board_teams)가 이 결과만 쓴다(시트 따로 판정 0).
좌석 = 명부만(seat_set · 계보당 번호가 가장 큰 현역 행 1석 · tmux 목록은 «살아 있나» 에만) ·
판정 전체(명부 탐색·세션 목록·payload 조립·좌석 집합·기다림·카드·jsonl 읽기·턴 판독)는 하위 프로세스 1개(child_teams)에서 팀마다 try 안 —
깨진 원천 하나는 그 팀만 «확인 불가(원천 오류 …)» · 다음 팀 계속 · 원천(tmux 목록·jsonl 위치)은 판정 한 번에 1회만 읽는다(ft_team_turns · r5).
빈 원천(보드 블록의 master 빈 값 · seats 의 [])은 «기다리는 값 모름(원천 모양 오류)» + ERROR 1줄 — 조용한 «모름» 0.

r7 — 부모 = 얇은 감독자(부모 일 0): team_states 는 ①마감 1개 ②payload(경로 문자열만 · 탐색 0) ③run_teams ④받은 줄 → grade() → 반환
한 줄. 부모는 명부를 찾지도(roster_files) 세션 목록을 읽지도(tmux) payload 를 조립하지도(payload_for) ft_team_turns 를 import 하지도 않는다 —
그 셋은 하위 첫 단계로 옮겼다(DA⑥ r6 반례 1~3 이 났던 자리 = 부모가 직접 하던 일). 반환 지점 1 · 모든 갈래가 grade() 를 지난다.
하위 첫 줄 = 팀 목록 줄({"teams": […]}) · 명부 0개 = {"fatal": …} 줄(부모가 raise) · 하위가 알린 무리({"pgid": N})는 반환 직전 함께 걷어낸다.
"""
import json
import logging
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

from ft_board_roster import FIXED_ROLES, lineage, retired_names

LOG = logging.getLogger("ft_team_state")
STATES = ("진행", "대기", "쉼", "확인 불가")
WINDOW_MIN = 30
WAIT_SHAPE = "기다리는 값 모름(원천 모양 오류)"  # r5 — 빈 원천은 «모름» 이 아니라 «모양 오류»
AUTO = "auto"  # alive 자동 — 하위가 세션 목록을 «남은 마감» 안에서 읽는다(r7: 부모가 아니라 하위)
OPEN = ("WORKING", "PENDING")
TERM_S, KILL_S = 6.0, 7.0  # 7초 룰 — 판정 전체 마감(TERM → KILL · 무리째)
CTRL = "~ctrl"  # _parse 가 제어 줄(팀 목록·fatal·err·pgid)을 담는 열쇠 — 팀 이름과 겹치지 않는다
Seat = tuple[str, str, "int | None"]  # (턴 상태, 사유, 마지막 턴 끝 뒤 분 — IDLE 만)


def judge(cards: int | None, seats: list[Seat], wait: str = "") -> tuple[str, str]:
    """(상태, 표시 글자) — cards = 진행 카드 수(None = 카드 폴더 없는 팀) · seats = 그 팀 라이브 좌석들 · wait = master 칸 «기다리는 것»."""
    live, opened = len(seats), sum(s[0] in OPEN for s in seats)
    idle = [s[2] for s in seats if s[0] == "IDLE" and s[2] is not None]
    unknown = [s[1] or f"상태 {s[0]}" for s in seats if s[0] not in (*OPEN, "IDLE")]
    if opened:
        return "진행", f"진행 · {'진행 카드 0 · ' if cards == 0 else ''}일하는 좌석 {opened}/{live}"
    recent = min((n for n in idle if n < WINDOW_MIN), default=None)
    if recent is not None and cards != 0:
        return "진행", f"진행 · {recent}분 전 턴"
    if cards == 0 or (cards is None and not unknown):
        return "쉼", "쉼 · " + ("열린 좌석 0" if not live else "진행 카드 0" if cards == 0 else f"{WINDOW_MIN}분 안 턴 0")
    if unknown:
        return "확인 불가", f"확인 불가({' · '.join(f'{r} {n}석' for r, n in Counter(unknown).items())})"
    waiting = f"기다리는 것 = {wait.strip() or '기다리는 값 모름'}"
    if not live:
        return "대기", f"대기 · 열린 좌석 0 · {waiting}"
    return "대기", f"대기{f' {min(idle)}분' if idle else ''} · {waiting}"


def unknown_why(text: str) -> str:
    """«확인 불가(<사유>)» 칸 → 사유 — 시트 칸이 같은 글자로 judge 에 들어간다."""
    return text[len("확인 불가("):].split(")", 1)[0] or "확인 불가"


def _brief(v) -> str:
    return repr(v)[:40]


def wait_of(t: dict) -> tuple[str, str]:
    """팀 블록(collect dict · 보드 스냅샷 같은 꼴) → (master 칸 «기다리는 것», ERROR 1줄 또는 "") — 뉴스·시트 같은 규칙.
    요구(r5): master = 비지 않은 str · seats = master 칸을 포함한 비지 않은 dict · 칸 = dict.
    빈 원천([] · 0 · "" · null · {}) = «기다리는 값 모름(원천 모양 오류)» + ERROR 1줄(조용한 «모름» 0 · DA⑥ r4 반례 2) ·
    모양이 틀린 값(master 가 str 아님 · seats 가 비지 않은 list·숫자 · 칸이 dict 아님) = TypeError(그 팀 «확인 불가(원천 오류 …)»)."""
    master, seats = t.get("master"), t.get("seats")
    if not isinstance(master, (str, type(None))) or (seats and not isinstance(seats, dict)):
        raise TypeError(f"master·seats 칸 모양 오류(master={type(master).__name__} · seats={type(seats).__name__})")
    if not master or not seats:  # 빈 원천 — [] · 0 · "" · null · {} 는 «모름» 이 아니라 «모양 오류»
        return WAIT_SHAPE, f"팀 {t.get('key') or '?'} 기다림 원천 모양 오류 — master={_brief(master)} · seats={_brief(seats)}"
    cell = seats.get(master)
    if cell is None:
        return "기다림 확인 불가(master 칸 없음)", ""
    if not isinstance(cell, dict):
        raise TypeError(f"master 칸 모양 오류({type(cell).__name__})")
    return str(cell.get("wait") or ""), ""


def master_wait(t: dict) -> str:
    """팀 블록 → master 칸 «기다리는 것» — wait_of 의 글자만(변이 시험이 부른다 · 뉴스·시트 같은 규칙)."""
    return wait_of(t)[0]


def _num(name: str) -> int:
    m = re.search(r"#(\d+)$", name)
    return int(m.group(1)) if m else -1


def seat_set(seats: dict, alive: set[str] | None) -> tuple[list[str], dict[str, Seat]]:
    """좌석 = 명부만(r4) — 현역 행(은퇴 표시·seat-resume 기록 이름 제외) 중 계보(#N 뗀 이름)마다 번호가 가장 큰 1행.
    tmux 목록은 «그 이름 세션이 살아 있나» 에만(명부에 없는 세션을 좌석으로 넣기 0 · DA⑥ r3 반례 4).
    (턴 잴 좌석, 고정 칸) — 죽은 행은 뺀다 · 살아 있는 행 0 = 고른 행 전부 «?»(명부 현역 세션 없음) · alive=None = «?»(tmux 목록 없음) ·
    닫힘·정지레디 = IDLE 분 없음."""
    retired = retired_names(None)
    rows = {n: v for n, v in seats.items() if not n.startswith("_") and isinstance(v, dict) and not v.get("_replaced_by") and n not in retired}
    top: dict[str, str] = {}
    for n in rows:
        if lineage(n) not in top or _num(n) > _num(top[lineage(n)]):
            top[lineage(n)] = n
    chosen = sorted(top.values())
    best = [n for n in chosen if n in (alive or ())]
    if alive is None or (chosen and not best):
        why = "tmux 목록 없음" if alive is None else "명부 현역 세션 없음"
        return [], {n: ("?", why, None) for n in chosen}
    fixed: dict[str, Seat] = {n: ("IDLE", "", None) for n in best if rows[n].get("role") in FIXED_ROLES}
    return [n for n in best if n not in fixed], fixed


def progress_cards(root: Path, roster: Path) -> int | None:
    """명부의 진행 카드 수(_cards · _cards_wt — ft_board_collect 와 같은 폴더 규칙 · 두 폴더에 겹친 카드는 진행으로 세지 않는다).
    _cards 없음 = None · 카드 폴더 없음·명부 깨짐 = 예외(호출자가 «확인 불가» 로 드러낸다 · 조용한 0 금지)."""
    seats = json.loads(roster.read_text(encoding="utf-8"))
    if not seats.get("_cards"):
        return None
    base = root / ".worktrees" / seats["_cards_wt"] if seats.get("_cards_wt") else root
    d = base / seats["_cards"]
    if not d.is_dir():
        raise FileNotFoundError(f"카드 폴더 없음 — {d}")
    stems = {f: {p.stem for p in (d / f).glob("*.md")} for f in ("대기", "진행", "완성")}
    return len(stems["진행"] - stems["대기"] - stems["완성"])


def roster_files(root: Path) -> dict[str, Path]:
    """팀 키 → 명부(seats-<팀>.json · seats.json = v65) — 0개 = RuntimeError(팀 실측 불가)."""
    fable = root / ".fable-team"
    out = {p.name[len("seats-"):-len(".json")]: p for p in fable.glob("seats-*.json")}
    if (fable / "seats.json").is_file():
        out["v65"] = fable / "seats.json"
    if not out:
        raise RuntimeError(f"명부 0개({fable}/seats-*.json) — 팀 실측 불가")
    return out


def snapshot_boards(root: Path) -> dict | None:
    """보드 스냅샷(ft-board collect dict) → 팀 키 → 블록 · 스냅샷 없음·깨짐 = None(기다리는 값 모름) · teams 가 list 아님 = TypeError."""
    from ft_news_status import latest_snapshot
    try:
        data = json.loads(latest_snapshot(root)[0].read_text(encoding="utf-8"))
    except (RuntimeError, OSError, ValueError):
        return None
    teams = data.get("teams") if isinstance(data, dict) else None
    if not isinstance(teams, list):
        raise TypeError(f"보드 스냅샷 teams 모양 오류({type(teams).__name__})")
    return {b["key"]: b for b in teams if isinstance(b, dict) and isinstance(b.get("key"), str)}


def _wait(boards, t: str) -> tuple[str, str]:
    """팀 → (기다리는 것, ERROR 1줄). 스냅샷에 없는 팀 = «»(원천 없음 — 모양 오류가 아니다)."""
    if isinstance(boards, Exception):
        raise boards
    return wait_of(boards[t]) if boards and t in boards else ("", "")


def _verdict(st: str, label: str, rows: dict[str, Seat] | None = None, wait: str = "") -> dict:
    rows = rows or {}
    unk = [v[1] for v in rows.values() if v[0] == "?"]
    return {"state": st, "label": label, "wait": wait, "live": len(rows), "working": sorted(n for n, v in rows.items() if v[0] == "WORKING"),
            "unknown": len(unk), "unknown_reason": " · ".join(f"{r} {unk.count(r)}석" for r in dict.fromkeys(unk))}


def _origin_error(t: str, e: Exception) -> dict:
    """그 팀만 «확인 불가(원천 오류 <예외 이름>: …)» — ERROR 줄은 부모가 낸다(하위 프로세스 로그는 부모 caplog 에 안 잡힌다)."""
    return _verdict("확인 불가", f"확인 불가(원천 오류 {type(e).__name__}: {e})")


def _origin_line(t: str, e: Exception) -> dict:
    return {"team": t, "v": _origin_error(t, e), "err": f"팀 {t} 판정 실패 — {type(e).__name__}: {e}"}


def _spawn(payload_path: str) -> "subprocess.Popen":
    """판정 하위 1개 — 자기 세션(무리 killpg 대상) · close_fds · payload 는 파일 경로로(파이프 교착 0) ·
    stderr 는 부모 것을 그대로 쓴다(PIPE 아님 — 읽지 않는 파이프가 하위를 막는 일 0 · r5 보강 ⓑ1)."""
    code = f"import sys; sys.path.insert(0, {str(Path(__file__).resolve().parent)!r}); import ft_team_turns as m; m.child()"
    return subprocess.Popen([sys.executable, "-c", code, payload_path], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            text=True, start_new_session=True, close_fds=True)


def _signal(pgid: int, sig: int) -> None:
    """프로세스 무리 전체(하위 + 손자) — 이미 끝난 무리는 그대로(ESRCH·EPERM = 삼킨다 · r5 보강 ⓑ2)."""
    try:
        os.killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def _group_alive(pgid: int) -> bool:
    """그 무리에 아직 프로세스가 있나 — ESRCH = 없음(자손 0 확인 · r6 고침 2)."""
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _reap_group(proc, grace: float = 0.2, wait_s: float = 1.0, extra=()) -> None:
    """무리째 정리 — TERM → grace → KILL 되풀이 → «생존 0» 확인하고 돌아간다(최대 wait_s · ESRCH 삼킴).
    extra = 하위가 알린 무리({"pgid": N} 줄 · tmux 호출) — 부모가 거는 무리 = 하위 세션 하나 + 그 아래 손자 무리 전부(r7 고침 3).
    그래도 살아남은 무리 = ERROR 1줄 «무리 잔존 pgid=N»(값은 받은 만큼 쓰고 예외는 내지 않는다)."""
    groups = [proc.pid, *extra]
    for g in groups:
        _signal(g, signal.SIGTERM)
    end = time.monotonic() + grace
    while time.monotonic() < end and any(_group_alive(g) for g in groups):
        time.sleep(0.02)
    end = time.monotonic() + wait_s
    while time.monotonic() < end:
        for g in groups:
            _signal(g, signal.SIGKILL)
        try:
            proc.wait(timeout=0.05)
        except subprocess.TimeoutExpired:
            pass
        if not any(_group_alive(g) for g in groups):  # 리더가 zombie 로 남는 것은 wait 로 걷어낸 뒤에 본다
            return
    for g in groups:
        _signal(g, signal.SIGKILL)
        if _group_alive(g):
            LOG.error("팀 판정 무리 잔존 — pgid=%d(값은 받은 만큼 쓴다)", g)


def _pump(stream, sink: list) -> None:
    """줄마다 (받은 시각, 줄) — «\\n 으로 끝난 줄» 만 남긴다. 마감 순간 잘린 꼬리 줄은 쓰지 않는다(r5 보강 ⓑ1)."""
    try:
        for line in stream:
            if line.endswith("\n"):
                sink.append((time.monotonic(), line))
    except (ValueError, OSError):  # 죽인 뒤 닫힌 파이프
        return


def _parse(lines: list[str]) -> dict[str, dict]:
    """받은 줄 → {팀: 줄} — 마감에 잘린 마지막 줄은 버린다. 팀 줄이 아닌 제어 줄(팀 목록·fatal·err)은 CTRL 열쇠에 모은다."""
    got: dict[str, dict] = {}
    ctrl: list[dict] = []
    for line in lines:
        try:
            one = json.loads(line)
        except ValueError:
            continue
        if not isinstance(one, dict):
            continue
        if isinstance(one.get("team"), str):
            got[one["team"]] = one
        elif "pgid" not in one and any(k in one for k in ("teams", "fatal", "err")):
            ctrl.append(one)
    if ctrl:
        got[CTRL] = ctrl
    return got


def _pgids(lines: list) -> list[int]:
    """(받은 시각, 줄) 전부 → 하위가 알린 무리 번호 — 마감 뒤에 읽힌 줄도 쓴다(이미 생긴 프로세스를 놓치지 않는다 · r7)."""
    out: list[int] = []
    for _at, line in lines:
        try:
            one = json.loads(line)
        except ValueError:
            continue
        if isinstance(one, dict) and isinstance(one.get("pgid"), int):
            out.append(one["pgid"])
    return out


def run_teams(payload: dict, teams: list[str], deadline: float | None = None) -> tuple[dict[str, dict], "str | None"]:
    """payload → (받은 팀 결과 {팀: 줄}, 전 팀 공통 실패 사유 | None). 못 받은 팀은 부르는 쪽이 «시간 초과» 로 채운다.
    deadline = «입구» 에서 정한 절대 시각(monotonic) — 없으면 지금부터 TERM_S(r6 고침 1).
    네 갈래(정상·시간 초과·예외·finally)가 모두 _reap_group 을 지나고, 반환 «직전» 무리 생존 0 을 확인한다(r7 고침 3)."""
    start = time.monotonic()
    dl = start + TERM_S if deadline is None else deadline
    fd, path = tempfile.mkstemp(prefix="ft-team-judge-", suffix=".json")
    proc, out, fail = None, [], None
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({**payload, "deadline": time.time() + max(0.0, dl - time.monotonic())}, fh, ensure_ascii=False, default=str)
        try:
            proc = _spawn(path)
        except OSError as e:  # EMFILE 등 — 지도 전체를 멈추지 않고 «모름» 으로 발행한다
            LOG.error("팀 판정 하위 생성 실패 — 전 팀(%d) 확인 불가: %s: %s", len(teams), type(e).__name__, e)
            fail = f"판정 시작 실패 {e.errno if e.errno is not None else type(e).__name__}"
        if proc is not None:
            pump_out = threading.Thread(target=_pump, args=(proc.stdout, out), daemon=True)
            pump_out.start()
            pump_out.join(max(0.0, dl - time.monotonic()))  # 흘려 받기 — 받은 만큼이 산다
            if pump_out.is_alive():
                _signal(proc.pid, signal.SIGTERM)
                pump_out.join(max(0.0, dl + (KILL_S - TERM_S) - time.monotonic()))
            if pump_out.is_alive():
                _signal(proc.pid, signal.SIGKILL)
            pump_out.join(0.5)
            if not out:  # 하위가 첫 줄(팀 목록)도 못 냈다 — 부모는 팀 집합을 모른다(rosters 인자 팀만 «판정 시작 실패»)
                fail = fail or "판정 시작 실패 0줄"
        return _parse([line for at, line in out if at <= dl]), fail  # 마감 뒤 읽힌 팀 줄은 버린다(r5 보강 ⓑ2)
    finally:
        if proc is not None:
            _reap_group(proc, extra=_pgids(out))  # 정상·시간 초과·예외 모두 같은 정리(r7 고침 3)
        try:
            os.unlink(path)
        except OSError:
            pass


def grade(states: dict[str, dict]) -> str:
    """발행 등급(r5 · r6 고침 4 — 판정 함수가 낸다) — 확인 불가 팀 0 = "" · 1개 이상 = «PARTIAL N팀» · 전원 = «ALL-UNKNOWN».
    뉴스 발행기든 시트(ft-board.py teams)든 이 글자를 같이 쓰고, team_states 가 같은 사유를 ERROR/WARN 으로 남긴다(조용한 확인 불가 0)."""
    if not states:
        return ""
    unknown = sum(1 for v in states.values() if v.get("state") == "확인 불가")
    if not unknown:
        return ""
    return "ALL-UNKNOWN" if unknown == len(states) else f"PARTIAL {unknown}팀"


def child_teams(payload: dict):
    """판정 전체(하위 프로세스 1개) — 팀 하나를 끝낼 때마다 결과 1줄({"team", "v", "err"})을 낸다.
    r7 첫 단계 = 부모가 안 하게 된 셋: ①명부 탐색(전달받은 경로만 쓰면 탐색 0) → 팀 목록 줄 ②세션 목록(AUTO 면 여기서)
    ③payload 조립. 그 뒤 ①명부·좌석 집합·기다림·카드 = 팀마다 try ②원천(tmux 목록 · jsonl 위치) 1회 ③jsonl 읽기·턴 판독·판정 = 팀마다 try.
    어느 단계의 예외든 그 팀만 «확인 불가(원천 오류 …)» · 다음 팀 계속(r5 팀 단위 격리) · 명부 0개만 {"fatal": …} 줄(부모가 raise)."""
    from ft_team_turns import locate, turn_at
    root, now = Path(payload["root"]), datetime.fromisoformat(payload["now"])
    deadline = float(payload.get("deadline") or 0.0)
    try:
        rosters = {t: Path(p) for t, p in payload["rosters"].items()} if payload.get("rosters") else roster_files(root)
    except Exception as e:  # noqa: BLE001 — 명부 0개·명부 폴더 못 읽음 = 발행 0(부모가 raise · 지금 계약 유지)
        yield {"fatal": f"명부 0개 — {type(e).__name__}: {e}"}
        return
    teams = [t for t in (payload.get("teams") or sorted(rosters)) if t in rosters]
    yield {"teams": teams}  # 부모가 «팀 집합» 을 이 줄로 안다(첫 줄)
    alive, alive_why = (set(payload["alive"]) if payload.get("alive") is not None else None), payload.get("alive_why") or "tmux 목록 없음"
    if payload.get("alive_auto"):
        import ft_team_turns as tt
        try:
            budget = max(0.05, min(tt.RESCAN_S, deadline - time.time()))  # 세션 목록은 안쪽 상한(남은 시간을 다 먹지 않는다 · 결과 줄 쓸 틈)
            alive, alive_why = set(tt.tmux_sessions(payload.get("tmux") or "tmux", budget)), ""
        except TimeoutError as e:
            alive, alive_why = None, "tmux 목록 시간 초과"
            yield {"err": f"tmux 세션 목록 시간 초과 — 전 팀 확인 불가: {e}"}
        except (RuntimeError, OSError) as e:
            alive, alive_why = None, "tmux 목록 없음"
            yield {"err": f"tmux 세션 목록 못 읽음 — 명부 이름만 확인 불가: {e}"}
    if alive is None:  # 세션 목록 전멸 = 팀마다 그 사유로 «확인 불가»(명부만으로 «쉼»·«대기» 를 말하지 않는다 · r7)
        for t in teams:
            yield {"team": t, "v": _verdict("확인 불가", f"확인 불가({alive_why})"), "err": ""}
        return
    boards = payload.get("boards")
    if payload.get("boards_mode", "given") == "snapshot":
        try:
            boards = snapshot_boards(root)
        except Exception as e:  # noqa: BLE001 — 모양 오류는 팀마다 _wait 가 «원천 오류» 로 드러낸다
            boards = e
    plan, warnt = {}, {}
    for t in teams:
        try:
            p = rosters[t]
            chosen, fixed = seat_set(json.loads(p.read_text(encoding="utf-8")), alive)
            if alive is None:  # 세션 목록을 못 읽은 사유를 좌석 칸에 그대로(«tmux 목록 시간 초과»)
                fixed = {n: ("?", alive_why, None) for n in fixed}
            wait, err = _wait(boards, t)
            plan[t] = (chosen, fixed, wait, progress_cards(root, p))
            if err:
                warnt[t] = err
        except Exception as e:  # noqa: BLE001 — 팀 단위 격리 ① 명부·좌석 집합·기다림·카드
            yield _origin_line(t, e)
    if not plan:
        return
    seats = sorted({s for v in plan.values() for s in v[0]})
    try:
        where = locate(seats, payload.get("tmux") or "tmux", Path(payload["projects"]))  # 원천 1회(좌석별 하위 0)
    except Exception as e:  # noqa: BLE001 — 원천 통째 실패 = 이 팀들만
        for t in plan:
            yield _origin_line(t, e)
        return
    for t, (chosen, fixed, wait, cards) in plan.items():
        if deadline and time.time() > deadline:  # 마감 넘김 — 못 낸 팀은 부모가 «확인 불가(시간 초과)»
            return
        try:
            rows: dict[str, Seat] = {}
            for s in chosen:
                got_s = turn_at(where[s], now)
                if isinstance(got_s, Exception):
                    raise got_s
                rows[s] = got_s
            rows.update(fixed)
            out = _verdict(*judge(cards, list(rows.values()), wait), rows, wait)
        except Exception as e:  # noqa: BLE001 — 팀 단위 격리 ② jsonl·턴 판독·판정
            yield _origin_line(t, e)
            continue
        yield {"team": t, "v": out, "err": warnt.pop(t, "")}


def _why(e: Exception) -> str:
    """판정 시작 실패 사유 글자 — OSError 는 errno(EMFILE 24), 그 밖은 예외 이름 + 메시지."""
    if isinstance(e, OSError) and e.errno is not None:
        return str(e.errno)
    return f"{type(e).__name__}: {str(e)[:120]}"


def team_states(root: Path, alive=AUTO, now: datetime | None = None, rosters: dict[str, Path] | None = None, boards: dict | None = None,
                session_source=None) -> dict[str, dict]:
    """판정 한 곳(r7) — 팀 → _verdict 칸. 부모 = 얇은 감독자: ①마감 1개(전체 벽시계 ≤ 7초) ②payload(경로 문자열만 · 탐색 0)
    ③run_teams ④받은 줄 → grade() → 반환 «한 줄». 명부 탐색·세션 목록·payload 조립은 하위가 첫 단계로 한다(부모 일 0).
    실패도 전부 같은 끝 줄을 지난다 — 하위 생성 실패 = 전 팀 «확인 불가(판정 시작 실패 <errno>)» · 못 받은 팀 = «확인 불가(시간 초과)» ·
    팀 집합을 못 받으면(하위 0줄) rosters 인자 팀 이름으로 채운다 · 명부 0개만 예외다(발행 0 · 하위의 {"fatal": …} 줄을 보고 raise).
    alive=AUTO 면 하위가 세션 목록을 스스로 읽고, 집합을 주면 그것을 쓴다(시트 collect) · 발행 등급(PARTIAL/ALL-UNKNOWN)은 이 함수가 ERROR/WARN 1줄로 남긴다.
    session_source 는 r7 부터 받기만 한다 — 세션 목록을 부모가 읽으면 반례 2·3 의 자리(마감 밖 tmux·모듈 import)로 돌아간다."""
    if now is None:
        raise TypeError("team_states(now=) 가 필요하다")
    start = time.monotonic()
    teams = sorted(rosters) if rosters else []
    payload = {"root": str(root), "now": now.isoformat(), "teams": teams,
               "rosters": {t: str(p) for t, p in rosters.items()} if rosters else None,
               "alive": None if alive in (AUTO, None) else sorted(alive),
               "alive_auto": alive is AUTO, "alive_why": "tmux 목록 없음" if alive is None else "",
               "boards": boards, "boards_mode": "given" if boards is not None else "snapshot",
               "tmux": os.environ.get("FT_TMUX", "tmux"),
               "projects": os.environ.get("FT_CLAUDE_PROJECTS") or str(Path.home() / ".claude" / "projects")}
    fail, out = None, {}
    try:
        got, fail = run_teams(payload, teams, deadline=start + TERM_S)
    except Exception as e:  # noqa: BLE001 — 정의상 예외 0: 새도 같은 끝 줄로(«판정 시작 실패»)
        got, fail = {}, f"판정 시작 실패 {_why(e)}"
    for c in got.pop(CTRL, []):
        if c.get("fatal"):
            raise RuntimeError(str(c["fatal"]))
        if c.get("err"):
            LOG.error("%s", c["err"])
        if isinstance(c.get("teams"), list) and not teams:
            teams = [str(t) for t in c["teams"]]
    if not teams:
        LOG.error("팀 상태 ALL-UNKNOWN — 팀 이름 미상(하위 0줄 · 명부 인자 없음)")
    for t in teams:
        line = got.get(t)
        if fail:
            out[t] = _verdict("확인 불가", f"확인 불가({fail})")
        elif not isinstance(line, dict) or not isinstance(line.get("v"), dict):
            out[t] = _verdict("확인 불가", "확인 불가(시간 초과)") if line is None else _verdict("확인 불가", "확인 불가(원천 모양 오류)")
        else:
            if line.get("err"):
                LOG.error("%s", line["err"])
            out[t] = line["v"]
    out = dict(sorted(out.items()))
    grade_text = grade(out)
    if grade_text == "ALL-UNKNOWN":
        LOG.error("팀 상태 ALL-UNKNOWN — %d팀 전원 확인 불가(판정 원천 실패 · 발행은 계속)", len(out))
    elif grade_text:
        LOG.warning("팀 상태 %s — 확인 불가 팀이 있다(발행은 계속)", grade_text)
    return out


def idle_minutes(end_iso: str, now: datetime) -> int | None:
    """턴 끝 ISO(UTC «Z» 포함) → now(로컬 naive)까지 분 · 해석 실패·미래 = None (ft_board_seat._turn_end 와 같은 규칙)."""
    try:
        p = datetime.fromisoformat(str(end_iso).replace("Z", "+00:00"))
    except ValueError:
        return None
    p = p.astimezone().replace(tzinfo=None) if p.tzinfo else p
    return None if p > now else int((now - p).total_seconds() // 60)
