"""ft_sat_rt — ft-sat-nano 실행 엔진 (r902 r7 · DECISION-r902-design-final 고침 3).

마감(단조 시계) · 원격 호출 rcall(멱등 표 · 재시도 = rc255 ∧ 출력 0바이트 1회 · 멱등 스크립트만) ·
장부(opened/delivered/forgotten · 기록 먼저 · 실패 = rc2 원격 0) · 커널 잠금(flock) · 값 검사.
시간으로 «상대 쪽 끝남»을 증명하는 코드는 0 — 시계는 우리 쪽 마감과 쪽지 intent 창에만 쓴다.
"""
import contextlib
import fcntl
import os
import re
import shlex
import signal
import subprocess
import time


class Fail(Exception):
    def __init__(self, rc, msg):
        super().__init__(msg)
        self.rc = rc
        self.msg = msg


# ── 설정 — 10진 정수만(int(x, 10)) · 범위 밖 rc2 (7초/70초 · 하드 룰 12) ──
def cfg_int(name, default, lo, hi):
    raw = os.environ.get(name, str(default))
    if not re.fullmatch(r"[0-9]{1,3}", raw):
        raise Fail(2, f"설정 오류: {name}={raw!r} — 10진 정수만")
    v = int(raw, 10)
    if not lo <= v <= hi:
        raise Fail(2, f"설정 오류: {name}={v} — {lo}~{hi} 만(7초/70초 룰)")
    return v


def config():
    return {"tmo": cfg_int("SAT_TMO", 7, 1, 7), "total": cfg_int("SAT_TOTAL", 70, 1, 70),
            "resend_max": cfg_int("SAT_RESEND_MAX", 3, 1, 9)}


def now():
    """쪽지 intent 창 판정용 벽시계 — SAT_FAKE_NOW 는 시험 전용(창 경과를 고정한다)."""
    fake = os.environ.get("SAT_FAKE_NOW", "")
    if fake:
        if not re.fullmatch(r"[0-9]{1,12}", fake):
            raise Fail(2, f"설정 오류: SAT_FAKE_NOW={fake!r}")
        return float(fake)
    return time.time()


class Deadline:
    """총 마감 하나 — 단계 전·명령 끝에 check · 자식 마감 = min(TMO, 남은 시간) · 남은 시간 0 이하면 자식 실행 0."""

    def __init__(self, total, tmo, clock=time.monotonic):
        self.total, self.tmo, self.clock = total, tmo, clock
        self.t0 = clock()

    def left(self):
        return self.total - (self.clock() - self.t0)

    def check(self, stage):
        if self.left() <= 0:
            raise Fail(5, f"총 마감 {self.total}초 초과(단계: {stage})")

    def child_timeout(self, stage="원격 호출"):
        left = self.left()
        if left <= 0:
            raise Fail(5, f"총 마감 {self.total}초 초과(단계: {stage} · 자식 실행 0)")
        return min(self.tmo, left)


# ── 값 검사 — 규칙 밖이면 rc2 · 원격 호출 0 ──
RE = {"name": r"[A-Za-z0-9][A-Za-z0-9._#-]{0,95}", "run": r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}",
      "sock": r"/[A-Za-z0-9._/-]{1,200}",
      "root": r"[A-Za-z0-9][A-Za-z0-9._/-]{0,63}", "model": r"[A-Za-z0-9][A-Za-z0-9._/:@-]{0,127}",
      "seats": r"[A-Za-z0-9._#-]+(,[A-Za-z0-9._#-]+)*", "mpy": r"[A-Za-z0-9_$/{}.-]+"}


def valid(kind, v):
    return re.fullmatch(RE[kind], v or "") is not None and (kind == "seats" or ".." not in v)


def need(kind, v, label):
    if not valid(kind, v):
        raise Fail(2, f"{label} 값이 규칙 밖이다(원격 호출 0): {v!r}")


# ── 자식 실행 · 원격 호출 ──
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=6", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3"]
PATH_PREFIX = "export PATH=/opt/homebrew/bin:$HOME/.local/bin:$PATH; "


def run_child(argv, timeout, stdin=None):
    """자식 1개를 자기 프로세스 묶음으로 띄우고 마감에 묶음째 끝낸다 → (rc, out bytes, err str) · 마감 = rc124."""
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL if stdin is None else subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = p.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(p.pid, signal.SIGKILL)
        p.wait()
        return 124, b"", f"시간 초과 {timeout:.1f}초"
    return p.returncode, out, err.decode("utf-8", "replace")


def remote_cmd(script, args):
    return PATH_PREFIX + "bash -c " + shlex.quote(script) + " _" + "".join(" " + shlex.quote(a) for a in args)


def rcall(dl, script, *args, stdin=None, idem=True):
    """원격 고정 스크립트 + 인용한 인자 · 재시도 = 멱등 스크립트 ∧ rc255 ∧ 출력 0바이트 일 때 1회뿐."""
    argv = ["ssh", *SSH_OPTS, os.environ.get("MINI", "mini"), remote_cmd(script, args)]
    rc, out, err = 255, b"", ""
    for _ in (1, 2):
        rc, out, err = run_child(argv, dl.child_timeout(), stdin)
        if not (idem and rc == 255 and out == b""):
            break
    return rc, out, err


# ── 장부 — 기록 먼저 · open/write/flush/fsync 어느 예외든 rc2 ──
def state_dir():
    return os.environ.get("SAT_STATE_DIR") or os.path.expanduser("~/.fable-team/sat")


def spath(name):
    return os.path.join(state_dir(), name)


def ensure_state():
    try:
        os.makedirs(state_dir(), exist_ok=True)
    except Exception as e:
        raise Fail(2, f"상태 폴더 생성 실패: {state_dir()} ({e})")


def append_line(path, line):
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
    except Exception as e:
        raise Fail(2, f"기록 실패({path}: {e}) — 원격 호출 0")


LOCK_WAIT = 5.0
_held = []  # 지금 이 프로세스가 쥔 장부 잠금 fd — 장부 쓰기는 이 안에서만(R1)


def in_time(dl, stage, msg):
    """장부 잠금 대기·쓰기·삭제 «전» 마감 검사 — 넘었으면 rc4(기록 유지)."""
    if dl.left() <= 0:
        raise Fail(4, f"총 마감 {dl.total}초 초과({stage}) — {msg}")


@contextlib.contextmanager
def ledger(dl):
    """R1 — opened.flock 을 명령 시작~끝 내내 쥔다(open·close·--adopt·--forget) · 대기 상한 min(5, 남은 마감)."""
    path = spath("opened.flock")
    in_time(dl, "장부 잠금 대기 전", "원격 0 · 기록 유지")
    wait = min(LOCK_WAIT, dl.left())
    fd = flock_try(path, wait)
    if fd is None:
        in_time(dl, "장부 잠금 대기", "원격 0 · 기록 유지 · 다시 실행")
        raise Fail(1, f"다른 open/close 진행 중(장부 잠금을 {wait:.1f}초 안에 못 잡았다) — 원격 0: {path}")
    _held.append(fd)
    try:
        yield
    finally:
        _held.remove(fd)
        os.close(fd)


def flock_try(path, wait=5.0):
    """커널 잠금 — 쥔 프로세스가 죽으면 커널이 푼다(회수 코드 0) · fd 는 자식에 상속 0 · 열기 실패 = rc2."""
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    except OSError as e:
        raise Fail(2, f"기록 실패(잠금 파일 열기 {path}: {e}) — 원격 0")
    end = time.monotonic() + wait
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except OSError:
            if time.monotonic() > end:
                os.close(fd)
                return None
            time.sleep(0.05)


def read_rows(name):
    try:
        with open(spath(name), encoding="utf-8") as f:
            return [ln.rstrip("\n").split("\t") for ln in f if ln.strip()]
    except FileNotFoundError:
        return []
    except Exception as e:
        raise Fail(2, f"장부 읽기 실패({name}: {e})")


# opened.tsv = name run dir ts session_id created pane_path socket — 정확히 8칸 · 열쇠 = run(R1)
# 신원 3칸·소켓 칸 4칸이 모두 차면 confirmed · 모두 비면 pending «열기 불확실» · 일부만 참 = 장부 손상(rc6)
NCOL = 8


def same_run(r, run):
    return len(r) > 1 and r[1] == run


def opened_find(name):
    """공용 줄 찾기(task·fetch·close·--forget) — 없음 = None · 같은 이름/run 줄이 둘 이상·칸 수 ≠ 8 = rc6(건드림 0)."""
    rows = read_rows("opened.tsv")
    hit = [r for r in rows if r[0] == name]
    if not hit:
        return None
    if len(hit) != 1 or len(hit[0]) != NCOL or sum(1 for r in rows if same_run(r, hit[0][1])) != 1:
        raise Fail(6, f"장부 손상 — 건드림 0(같은 이름 줄 {len(hit)}개 · 칸 {len(hit[0])}개 · 정확히 1줄·{NCOL}칸이어야): {name}")
    if any(hit[0][4:NCOL]) and not confirmed(hit[0]):
        raise Fail(6, f"장부 손상 — 건드림 0(신원·소켓 4칸이 일부만 찼다 · 전부 참 = 확인됨 · 전부 빔 = pending 만): {name}")
    return hit[0]


def confirmed(row):
    return len(row) == NCOL and all(row[4:NCOL])


def _must_hold():
    if not _held:
        raise Fail(2, "장부 잠금 없이 쓰기(코드 결함) — 기록 그대로")


def opened_add(row):
    _must_hold()
    append_line(spath("opened.tsv"), "\t".join(row))


def _opened_rewrite(run, fn):
    """run 이 같은 «한 줄만» 바꾼다(fn 이 None 이면 지움) · 그런 줄이 정확히 1개가 아니면 rc6."""
    _must_hold()
    rows = read_rows("opened.tsv")
    if sum(1 for r in rows if same_run(r, run)) != 1:
        raise Fail(6, f"장부 손상 — run={run} 줄이 정확히 1개가 아니다 · 건드림 0")
    new = [r for r in (fn(r) if same_run(r, run) else r for r in rows) if r is not None]
    tmp = spath("opened.tsv.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("".join("\t".join(r) + "\n" for r in new))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, spath("opened.tsv"))
    except Exception as e:
        raise Fail(2, f"기록 실패(opened.tsv: {e})")


def opened_del(run):
    _opened_rewrite(run, lambda r: None)


def opened_set_ident(run, sid, created, path, sock):
    _opened_rewrite(run, lambda r: r[:4] + [sid, created, path, sock])


def forgotten_add(row, why):
    """forgotten.tsv(추가 전용) = 시각 · 좌석/사용자 · run · 원 줄 전체(8칸) · why."""
    who = os.environ.get("FT_SEAT") or os.environ.get("USER", "?")
    append_line(spath("forgotten.tsv"), "\t".join([time.strftime("%Y-%m-%dT%H:%M:%S%z"), who, row[1], *row, why]))


# delivered.tsv(추가 전용) = mini:<seq> · intent|done|dead · epoch · pid · n(누적 발신 시도) — 같은 키의 마지막 행이 상태
def delivered_last(key):
    last = None
    for r in read_rows("delivered.tsv"):
        if r[0] == key and len(r) >= 5:
            last = (r[1], float(r[2]), int(r[4], 10))
    return last


def delivered_put(key, state, n):
    append_line(spath("delivered.tsv"), f"{key}\t{state}\t{int(now())}\t{os.getpid()}\t{n}")
