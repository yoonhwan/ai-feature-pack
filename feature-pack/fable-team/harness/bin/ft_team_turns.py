"""ft_team_turns — 좌석 턴 판독 원천(원천 1회) + 판정 하위 1개(결과 흘려 받기) — r850 r5.

read_turns() = 이 프로세스 안에서 좌석 → (턴 상태, 사유, 마지막 턴 끝 뒤 분). tmux pane 목록 1회 · 좌석 → jsonl 위치는
find_jsonls 1회(좌석별 셸·하위 프로세스 0) · 이름표가 머리 1MB 밖인 좌석(승계)만 pane cwd 폴더에서 재탐색(RESCAN_S 5초 ·
«값 쓰기 직전» 마감 확인). 좌석을 읽다 만난 예외는 그 좌석 자리에 그대로 담아 돌려준다 — 판정하는 쪽이 그 팀만 «원천 오류» 로 드러낸다.

run_teams() 은 ft_team_state 로 옮겼다(r7) — 부모(ft_team_state)가 판정 하위를 띄우고 흘려 받는 일을 다 한다. 이 파일은 하위 쪽
(명부·pane·jsonl 열기 · 판독)과 외부 호출 1회를 자기 무리로 돌리는 _run_group 만 갖는다 — 무리 번호는 부모에 알린다({"pgid": N} 줄 · r7 고침 3).
팀마다 하위를 띄우던 r4 꼴은 파일 핸들 한도에서 생성 실패가 지도 전체를 멈췄다(DA⑥ r4 반례 1). 하위 생성 실패(OSError · EMFILE) = 전 팀
«확인 불가(판정 시작 실패 <errno>)» + ERROR 1줄 — 예외 전파 0 · 지도는 그 값으로 발행(반례 2).
계약(정직한 한계) — 느린 원천이 마감을 먹으면 그 «뒤 순서» 팀만 «확인 불가(시간 초과)» 가 된다(다른 팀을 틀린 값으로 바꾸지 않는다 · 모름만).
"""
import json
import logging
import re
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from ft_api_outage_util import find_jsonls
from ft_seat_turn import turn_of_file
from ft_team_state import OPEN, Seat, _group_alive, _reap_group, _signal, idle_minutes

LOG = logging.getLogger("ft_team_turns")
HERE = Path(__file__).resolve().parent
TERM_S, KILL_S = 6.0, 7.0  # 7초 룰 — 판정 전체 마감(TERM → KILL · 무리째)
RESCAN_S = 5.0  # 안쪽 재탐색 마감(바깥 마감 안에서 다른 좌석 판독 몫을 남긴다)
NAME_TAIL = 1 << 20
NAME_RE = re.compile(rb'"(?:agentName|customTitle)":"([^"\\]*)"')
_REPORT = None  # 하위가 자기 무리 번호를 부모에 알리는 통로(sys.stdout) — child() 가 켜고, 부모 프로세스에서는 None


def _last_name(path: Path) -> str:
    with path.open("rb") as fh:
        fh.seek(max(0, fh.seek(0, 2) - NAME_TAIL))
        names = NAME_RE.findall(fh.read())
    return names[-1].decode("utf-8", "replace") if names else ""


def rescan(missing: list[str], panes: list[tuple[str, str]], projects: Path, taken: set[str], deadline: float, days: int = 2) -> tuple[dict[str, str], set[str]]:
    """이름으로 못 찾은 좌석 → pane cwd 폴더(find_jsonls 와 같은 인코딩)의 최근 days 일 파일 중 «꼬리 마지막 이름표 == 좌석» 인 최신 1개.
    (찾은 것, 시간 초과로 못 본 좌석) — 다른 좌석이 잡은 파일(taken)은 건너뛴다 · pane 목록은 이미 읽은 1회 값."""
    cwd: dict[str, str] = {}
    for s, c in panes:
        cwd.setdefault(s, c)  # 세션의 첫 pane(find_jsonls 와 같은 선택)
    found: dict[str, str] = {}
    for i, s in enumerate(missing):
        if s not in cwd:
            continue
        d = projects / re.sub(r"[^A-Za-z0-9]", "-", cwd[s])
        try:
            files = sorted(((p.stat().st_mtime, p) for p in d.glob("*.jsonl") if str(p) not in taken), reverse=True)
        except OSError:
            continue
        for mtime, p in files:
            if time.monotonic() > deadline:  # 꼬리 읽기는 남은 시간 안에서만 시작
                return found, set(missing[i:]) - set(found)
            if time.time() - mtime >= days * 86400:
                break
            try:
                name = _last_name(p)
            except OSError:  # 읽는 사이 지워진 파일
                continue
            if time.monotonic() > deadline:  # 값을 쓰기 직전 마감 — 넘긴 뒤 얻은 값은 버린다(DA⑥ r1 ②)
                return found, set(missing[i:]) - set(found)
            if name == s:
                found[s] = str(p)
                taken.add(str(p))
                break
    return found, set()


def locate(seats: list[str], tmux: str, projects: Path, budget_s: float = RESCAN_S) -> dict[str, "str | Seat"]:
    """좌석 → jsonl 경로 | («?», 사유, None) — pane 목록 1회 · jsonl 위치 1회 · 이름으로 못 찾은 좌석만 재탐색(원천 1회 · r5).
    턴 읽기는 판정하는 쪽이 팀마다 따로 한다(turn_at) — 느린 팀 하나가 앞 팀 결과를 먹지 않는다."""
    panes = list_panes_group(tmux, RESCAN_S)  # 원천 1회(자기 무리 · 5초 상한 · 판정 마감은 부모가 따로 잡는다) — 팀·좌석마다 다시 읽지 않는다 · 자기 무리(자손 0)
    found = find_jsonls(list(seats), tmux, projects, panes=panes)
    missing, late = [s for s in seats if s not in found], set()
    if missing:
        more, late = rescan(missing, panes, projects, set(found.values()), time.monotonic() + budget_s)
        found |= more
    return {s: found.get(s) or ("?", "시간 초과" if s in late else "jsonl 없음", None) for s in seats}


def turn_at(where: "str | Seat", now: datetime) -> "Seat | Exception":
    """jsonl 경로 → Seat | 그 좌석을 읽다 만난 예외(그 팀만 «원천 오류» — r5 팀 단위 격리)."""
    if not isinstance(where, str):
        return where
    try:
        st, end = turn_of_file(where)[:2]
    except Exception as e:  # noqa: BLE001 — 깨진 jsonl 한 줄 = 그 좌석(그 팀)만
        return e
    return (st, "" if st in (*OPEN, "IDLE") else "턴 기록 없음", idle_minutes(end, now) if st == "IDLE" else None)


def read_turns(seats: list[str], tmux: str, projects: Path, now: datetime, budget_s: float = RESCAN_S) -> dict[str, "Seat | Exception"]:
    """좌석 → Seat | 예외 — locate() 한 번 + turn_at() 좌석마다(판정 밖에서 좌석 한 줄만 볼 때)."""
    return {s: turn_at(w, now) for s, w in locate(seats, tmux, projects, budget_s).items()}


def seat_turns_now(seats: list[str], tmux: str, projects: Path, now: datetime, budget_s: float = RESCAN_S) -> dict[str, Seat]:
    """read_turns() 의 좌석 칸 꼴(예외 → «?» 사유 «읽기 실패») — 판정 밖에서 좌석 한 줄만 볼 때 쓴다."""
    read = read_turns(seats, tmux, projects, now, budget_s)
    return {s: v if isinstance(v, tuple) else ("?", f"읽기 실패({type(v).__name__})", None) for s, v in read.items()}


def _report_pgid(pgid: int) -> None:
    """하위가 자기 무리 번호를 부모에 알린다(r7 고침 3) — 부모가 반환 «직전» 이 무리도 같이 걷어낸다(자손 0).
    부모 프로세스에서는 _REPORT 가 None 이라 아무 일도 안 한다."""
    if _REPORT is None:
        return
    try:
        _REPORT.write(json.dumps({"pgid": pgid}) + "\n")
        _REPORT.flush()
    except (OSError, ValueError):  # 부모가 이미 죽인 뒤 닫힌 파이프
        return


def _run_group(args: list[str], budget_s: float) -> tuple[str, str, int, bool]:
    """외부 호출 1회를 «새 무리» 로 — 마감(budget_s) 넘기면 무리째 정리하고 흔적 0 으로 돌려준다(r6 고침 2).
    (표준출력, 표준오류, rc, 시간 초과 여부) · 무리 번호는 부모에 알린다(r7 — 부모 마감에 죽어도 손자가 안 남는다)."""
    proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            start_new_session=True, close_fds=True)
    _report_pgid(proc.pid)
    try:
        out, err = proc.communicate(timeout=max(0.0, budget_s))
        _signal(proc.pid, signal.SIGKILL)  # 호출이 끝났어도 남은 손자는 무리째 걷어낸다
        if _group_alive(proc.pid):
            _reap_group(proc, grace=0.0, wait_s=0.3)
        return out, err, proc.returncode, False
    except subprocess.TimeoutExpired:
        _reap_group(proc)
        return "", "", -1, True


def tmux_sessions(tmux: str, budget_s: float = RESCAN_S) -> list[str]:
    """tmux 세션 이름 전부 — 자기 무리에서 · 서버 없음 = [] · 그 밖 실패 = RuntimeError · 마감 넘김 = TimeoutError(r6 고침 1·2)."""
    out, err, rc, late = _run_group([tmux, "ls", "-F", "#{session_name}"], budget_s)
    if late:
        raise TimeoutError(f"tmux 세션 목록 시간 초과({budget_s:.1f}초)")
    if rc != 0:
        if "no server running" in err:
            return []
        raise RuntimeError(f"tmux ls 실패 rc={rc}: {err.strip()[:120]}")
    return out.split()


def list_panes_group(tmux: str, budget_s: float = RESCAN_S) -> list[tuple[str, str]]:
    """tmux pane 전부 → [(세션 이름, pane cwd)] — 같은 무리 도우미(자손 0) · 마감 넘김 = TimeoutError."""
    out, _err, _rc, late = _run_group([tmux, "list-panes", "-a", "-F", "#{session_name}\t#{pane_current_path}"], budget_s)
    if late:
        raise TimeoutError(f"tmux pane 목록 시간 초과({budget_s:.1f}초)")
    return [(s, cwd) for s, cwd in (ln.split("\t", 1) for ln in out.splitlines() if "\t" in ln)]


def child() -> None:
    """하위 프로세스 본문 — argv[1] = payload 파일 경로. 팀 결과 1줄(JSON)씩 stdout 으로 흘려 보낸다.
    무리 번호 줄({"pgid": N})도 같은 stdout 으로 — 부모가 반환 직전 그 무리까지 걷어낸다(r7 고침 3)."""
    global _REPORT
    _REPORT = sys.stdout
    payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    for line in lines(payload):
        sys.stdout.write(json.dumps(line, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def lines(payload: dict):
    """payload → 팀 결과 줄들 — 판정 본문은 ft_team_state.child_teams(지연 import: 서로 부른다)."""
    import ft_team_state as st
    yield from st.child_teams(payload)
