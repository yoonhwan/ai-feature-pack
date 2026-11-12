# pyright: basic
"""R320b — ft_stall_scan 상태 파일·중복 실행 잠금·자기 로그 10분 가드.

stall-scan.json = {handled: {좌석: 처리 시각}, prev: [지난 실행 감지 키], seats: {좌석 캐시 — ft_stall_seats}}.
launchd 가 120초마다 1회 실행하므로 앞 실행이 아직 돌면(첫 실행·압력 시 느림) 새 실행은 조용히 건너뛴다(rc 0 · 한 줄).
"""
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

REPEAT_S = 600


def load(state_dir: Path) -> dict:
    try:
        return json.loads((state_dir / "stall-scan.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


NUDGE_KEEP_S = 7200  # r1238 A-r4b-1 — a 재촉 기록은 2시간이 지나면 막는 힘이 없으니 지운다


def nudged_load(st: dict) -> dict[str, float]:
    """r1238 A-r4b-1 — 저장본의 a_card_nudged {카드 stem: 마지막 a 재촉 epoch}. 필드 없는 옛 상태·dict 아님 = 빈 사전 · 숫자 아닌 값은 그 항목만 버린다."""
    raw = st.get("a_card_nudged")
    if not isinstance(raw, dict):
        return {}
    return {str(k): float(v) for k, v in raw.items() if isinstance(v, (int, float)) and not isinstance(v, bool)}


def save(state_dir: Path, handled: dict, prev: list[str], seats: dict, nudged: dict[str, float] | None = None, now: float | None = None,
         lint: dict[str, dict] | None = None) -> None:
    """nudged 를 주면 같이 저장한다 — now 를 주면 2시간 넘은 항목은 지운다(후보에서 빠졌다고 지우지 않는다 · 카드가 폴더에서 사라진 항목도 이 2시간 안에 사라진다).
    r1392 — lint(카드 stem → {oid, lint, v, at}) 를 주면 같이 저장한다(원자 쓰기 · 부르는 쪽이 지울 카드를 먼저 빼고 넘긴다)."""
    doc: dict = {"handled": handled, "prev": prev, "seats": seats}
    if nudged is not None:
        doc["a_card_nudged"] = {k: v for k, v in nudged.items() if now is None or now - v <= NUDGE_KEEP_S}
    if lint is not None:
        doc["lint"] = lint
    _write(state_dir, doc)


def lint_load(st: dict) -> dict[str, dict]:
    """r1392 — 저장본의 lint 칸(카드 stem → {oid, lint, v, at}) 을 산 것만 살립니다. 읽는 쪽(ft_stall_detect._lint_verdict)이 꼴을 매번 다시 보므로 여기서는 dict 여지만 본다."""
    raw = st.get("lint") if isinstance(st, dict) else None
    return {str(k): v for k, v in raw.items() if isinstance(v, dict)} if isinstance(raw, dict) else {}


def _write(state_dir: Path, doc: dict) -> None:
    """stall-scan.json 원자 쓰기(tmp → os.replace · 실패하면 옛 파일 그대로)."""
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "stall-scan.json"
    tmp = path.with_name(f"stall-scan.json.tmp{os.getpid()}")
    try:
        _ = tmp.write_text(json.dumps(doc), encoding="utf-8")
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def recent_in_log(state_dir: Path, seat: str, now: float) -> bool:
    """ft-mbox ring 의 outstanding 억제를 우회하므로 자기 로그(act=… to=<좌석>)도 본다 — 10분 안에 처리했으면 True."""
    try:
        tail = (state_dir / "stall-scan.log").read_text(encoding="utf-8").splitlines()[-400:]
    except OSError:
        return False
    for line in tail:
        if f" to={seat} " in line + " ":
            try:
                if now - time.mktime(time.strptime(line[:19], "%Y-%m-%dT%H:%M:%S")) < REPEAT_S:
                    return True
            except ValueError:
                continue
    return False


@contextmanager
def single_run(state_dir: Path):
    """한 번에 한 실행 — 잠금이 잡혀 있으면 None."""
    state_dir.mkdir(parents=True, exist_ok=True)
    with open(state_dir / "stall-scan.lock", "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        yield True


# r1282 — 판정 단계 기한 D + 외부 호출 자식 묶음(프로세스 그룹) 정리.
# D = env FT_STALL_SCAN_TOTAL_S(기본 60 · 10~70 밖·숫자 아님 = 60) · 시작 = main() 진입 · 판정 단계(find)에만 적용 · 처리 단계는 호출별 timeout 만.
class JudgeTimeout(Exception):
    pass


_J: dict = {"on": False, "t0": 0.0, "d": 60.0, "k": 0, "n": 0, "fail": 0}


def judge_budget() -> float:
    try:
        v = float(os.environ.get("FT_STALL_SCAN_TOTAL_S") or 60)
    except ValueError:
        return 60.0
    return v if 10 <= v <= 70 else 60.0


def check() -> None:
    """판정 단계 중 경과 > D 면 판정 불가. 판정 밖(on=False)이면 아무것도 안 한다."""
    if _J["on"] and time.monotonic() - _J["t0"] > _J["d"]:
        raise JudgeTimeout


def progress(n: int) -> None:
    """좌석 하나 판정에 들어가기 전: 경과 검사 → 좌석 수 k(들어간 좌석) 올림."""
    _J["n"] = n
    check()
    _J["k"] += 1


def judge_done() -> None:
    check()
    _J["on"] = False


def begin() -> None:
    """판정 단계 시작 — 기준 시각 t0 = main() 진입(잠금·판정 전)."""
    _J.update(on=True, t0=time.monotonic(), d=judge_budget(), k=0, n=0, fail=0)


def lint_budget() -> bool:
    """r1392 — 이 실행에서 lint 를 더 불러도 되나: 판정 단계 경과 ≤ D/2 (판정 밖이면 늘 허용). 넘으면 그 실행의 남은 카드는 «lint 미판정» 으로 두고 다음 실행이 이어서 잰다."""
    return not _J["on"] or time.monotonic() - _J["t0"] <= _J["d"] / 2


def save_seats(state_dir: Path, seats: dict, lint: dict[str, dict] | None = None) -> None:
    """r1282 단계 2 — 판정 불가로 끝난 실행의 «좌석 → jsonl 경로 캐시» 만 저장: 지금 stall-scan.json 을 읽어 seats 칸만 바꾼다
    (handled·prev·a_card_nudged 등 다른 칸 그대로 · 파일 없음·깨짐 = {"seats": …} 만) · tmp → os.replace(원자 · 실패하면 옛 파일 그대로).
    r1392 — lint 칸(그때까지 잰 카드)도 같은 원자 쓰기로 한 번에 저장한다(기한을 넘겨도 한 일은 남는다)."""
    doc = load(state_dir)
    doc = dict(doc) if isinstance(doc, dict) else {}
    doc["seats"] = seats
    if lint is not None:
        doc["lint"] = lint
    _write(state_dir, doc)


def judged(fn, state_dir: Path, on_timeout=None) -> int:
    """fn() 을 판정 기한 안에서 돌린다(begin() 이 t0 를 세운 뒤 부른다) — 기한 넘김 = 처리 0 · 1줄(stdout + stall-scan.log) · rc 3.
    r1282 단계 2: on_timeout() = 좌석 캐시 저장(handled·prev 등은 0) · 실패하면 줄 꼬리에 «좌석 캐시 저장 실패(<예외 이름>)» (rc 3 그대로)."""
    _J.update(k=0, n=0, fail=0)
    try:
        return fn()
    except JudgeTimeout:
        _J["on"] = False
        extra = f" · 자식 묶음 정리 실패 {_J['fail']}건" if _J["fail"] else ""
        if on_timeout:
            try:
                on_timeout()
            except Exception as e:  # noqa: BLE001 — 저장 실패도 판정 불가 줄에 보인다(조용한 통과 0 · 하드 룰 20)
                extra += f" · 좌석 캐시 저장 실패({e.__class__.__name__})"
        line = f"stall-scan 판정 불가 — 판정 기한 {_J['d']:g} s 초과(좌석 {_J['k']}/{_J['n']} · 처리 0){extra}"
        print(line)
        with open(state_dir / "stall-scan.log", "a", encoding="utf-8") as fh:
            _ = fh.write(line + "\n")
        return 3
    finally:
        _J["on"] = False


def _alive(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def reap(p: subprocess.Popen, grace: float) -> None:
    """그 호출의 그룹에 남은 프로세스가 있으면 TERM → grace → KILL → 회수. 못 지우면 stderr 1줄(조용한 통과 0)."""
    pgid = p.pid
    for sig, wait in ((signal.SIGTERM, grace), (signal.SIGKILL, 0.5)):
        _ = p.poll()
        if not _alive(pgid):
            return
        try:
            os.killpg(pgid, sig)
        except OSError:
            pass
        end = time.monotonic() + wait
        while time.monotonic() < end:
            _ = p.poll()
            if not _alive(pgid):
                break
            time.sleep(0.02)
    _ = p.poll()
    if _alive(pgid):
        _J["fail"] += 1
        print(f"ft_stall: 자식 묶음 정리 실패 pgid={pgid}", file=sys.stderr)


def grun_raw(cmd: list[str], env: dict[str, str] | None = None, timeout: float = 15, cwd: Path | None = None,
             stdin_bytes: bytes | None = None) -> tuple[int, bytes, str]:
    """외부 호출 1개(바이트) — 자식 묶음(새 세션) · 시간 초과·정상 종료 뒤 남은 그룹은 정리 · 시간 초과 = rc 99.
    판정 단계(on)에서는 절대 만료 E = min(시작 + timeout, t0 + D − 1.0): E 가 이미 지났으면 부르지 않고 JudgeTimeout,
    E 가 기한 때문에 정해졌고 그 E 에 잘렸으면 JudgeTimeout(호출 실패 «제외» 로 넘기지 않는다).
    → (rc, stdout 바이트, stderr 글자) · git 처럼 cwd·stdin·바이트 stdout 이 필요한 호출이 같은 기한·정리 경로를 쓴다(r1330 _git)."""
    judging = _J["on"]
    call_end = time.monotonic() + timeout
    end = min(call_end, _J["t0"] + _J["d"] - 1.0) if judging else call_end
    if judging and end - time.monotonic() <= 0:
        raise JudgeTimeout
    grace = 0.5 if judging else 1.0
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE if stdin_bytes is not None else None, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, env=env, cwd=str(cwd) if cwd else None, start_new_session=True)
    except OSError as e:
        return 99, b"", str(e)
    try:
        out, err = p.communicate(input=stdin_bytes, timeout=max(end - time.monotonic(), 0.001))
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGTERM)
        except OSError:
            pass
        reap(p, grace)
        try:
            _ = p.communicate(timeout=1)
        except (subprocess.TimeoutExpired, OSError, ValueError):
            pass
        if judging and end < call_end:
            raise JudgeTimeout
        return 99, b"", f"timeout {timeout:g}s"
    reap(p, grace)
    return p.returncode, out or b"", (err or b"").decode("utf-8", "replace")


def grun(cmd: list[str], env: dict[str, str] | None = None, timeout: float = 15, cwd: Path | None = None) -> tuple[int, str]:
    """글자 꼴 grun — grun_raw 를 감싼다(stdout 만 글자로). cwd 없음(기본) = 부른 쪽 폴더 그대로(r1759 A5)."""
    rc, out, _err = grun_raw(cmd, env, timeout, cwd)
    return rc, out.decode("utf-8", "replace")
