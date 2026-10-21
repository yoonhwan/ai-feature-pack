# mbox_ops 가 send·relay «앞»에서 부르는 desk 경로 판정 호출(r660 · 판정 1125 · DA⑥ r1 ⓒ).
# ★규칙 0★ — 판정은 판정기 하나(ft_desk_route_gate.py)가 한다. 키트 ft-mbox.py 도 같은 파일을 부른다(두 벌 금지).
#   판정 자리 = python send 층(셸·python 직접·relay 전부 이 한 곳을 지난다) · 판정기 없음·실행 실패 = REJECT(fail-closed · 사유 1줄).
#   유일한 예외 = 판정기 «파일 자체가 없을 때» 의 설치 순서 가드(이름에 -desk- 가 걸린 쪽지만 막는다) — 그 밖에는 언제나 판정기를 부른다.
import os
import subprocess
import sys
import tempfile

HINT = "desk 는 planner 에게만 보내고, desk 에는 planner 가 보냅니다(planner 안내서 27줄) — 그 밖 길은 planner 를 거치세요."
NAME = "ft_desk_route_gate.py"


def judge_path():
    """FT_DESK_GATE(시험·명시) → <루트>/.fable-team/LIVE_BIN 폴더 → <루트>/.fable-team/bin → 빈 값."""
    g = os.environ.get("FT_DESK_GATE") or ""
    if g:
        return g
    d = os.path.dirname(os.path.abspath(__file__))          # <루트>/.fable-team/comm
    live = ""
    try:
        with open(os.path.join(d, "..", "LIVE_BIN"), encoding="utf-8") as f:
            live = f.readline().strip()
    except OSError:
        live = ""
    cands = ([os.path.join(live, NAME)] if live.startswith("/") else []) + [os.path.join(d, "..", "bin", NAME)]
    for c in cands:
        if os.path.isfile(c):
            return c
    return ""


def seats_dir():
    """명부 자리 — FT_SEATS_JSON(시험·명시) → <루트>/.fable-team(= comm 폴더의 부모)."""
    sj = os.environ.get("FT_SEATS_JSON") or ""
    return os.path.dirname(os.path.abspath(sj)) if sj else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def verdict(to, frm, body, attach="", comm=""):
    """통과면 None, 막으면 (reason, hint). 판정기 부재·예외 = REJECT(fail-closed)."""
    comm = comm or os.environ.get("FT_MBOX_DIR") or os.path.dirname(os.path.abspath(__file__))
    gate = judge_path()
    if not gate or not os.path.isfile(gate):
        if "-desk-" in to or "-desk-" in frm:
            return ("DESK_ROUTE_GATE_MISSING 판정기 없음(%s) — 설치 순서 · desk 쪽지 통과 0" % (gate or "?"), HINT)
        sys.stderr.write("WARN desk 경로 판정기 없음(%s) — 설치 순서 · desk 무관 쪽지 통과\n" % (gate or "?"))
        return None
    tmp = []
    try:
        bf = _tmp(body)
        af = _tmp(attach) if attach else ""
        tmp = [x for x in (bf, af) if x]
        cmd = [sys.executable, gate, "--to", to, "--from", frm, "--body-file", bf, "--seats-dir", seats_dir(), "--comm", comm]
        if af:
            cmd += ["--attach", af]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
    except Exception as e:                                   # noqa: BLE001 — 어떤 고장도 «통과»가 아니다
        return ("DESK_ROUTE_GATE_ERROR %s — desk 경로 판정 실패" % type(e).__name__, HINT)
    finally:
        for x in tmp:
            try:
                os.unlink(x)
            except OSError:
                pass
    for line in (r.stderr or "").splitlines():
        if line.startswith("WARN "):
            sys.stderr.write(line + "\n")
    if r.returncode == 0:
        return None
    rej = next((ln for ln in (r.stdout or "").splitlines() if ln.startswith("REJECT ")), "")
    if rej:
        return ("DESK_ROUTE " + rej[7:].strip(), HINT)
    return ("DESK_ROUTE_GATE_ERROR rc=%d %s" % (r.returncode, (r.stderr or "").strip()[:120]), HINT)


def _tmp(text):
    fd, p = tempfile.mkstemp(prefix="ft-desk-route.", suffix=".txt")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    return p
