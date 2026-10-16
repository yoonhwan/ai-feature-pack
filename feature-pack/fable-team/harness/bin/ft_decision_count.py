"""ft_decision_count.py — planner 가 오빠께 알려야 할 «결정 대기열» 을 한 줄로 센다 (R214 · 오빠 판정 1804).

출력 1줄: `결정 인터뷰 N건 · 스크립트 N건 · 팀 대기 N건(가장 오래 <팀 좌석> N분)`
  결정 인터뷰 = 인박스 ②[HIL]·③판정 요청 미닫힘(obligation_closed 그대로) + MERGE-QUEUE 상태 «대기» 행 + AUTONOMY-QUEUE 행
  스크립트 = ft-hil.sh --pending (R186 표식) · 팀 대기 = 인박스 ①~④·미상 미닫힘 중 다른 팀 좌석('#' 있는 이름)이 보낸 것
--detail 항목별 목록 · --alarm 30분(FT_DECISION_WAIT_MIN) 넘은 팀 대기 seq 마다 planner 에 쪽지 1통(상태 파일로 seq 당 1회).
읽기 실패 = stderr ERROR + rc 4 (숫자 지어내기 0). 시험 env: FT_ROOT · FT_DECISION_{NOW,MBOX,FROM,MERGE_QUEUE,AUTONOMY_QUEUE} · HIL_DIR.
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_decision_alarm import ReadError, alarm, first_line  # noqa: E402
from ft_flag_off import open_flags, scan  # noqa: E402
from ft_inbox_core import MUST_REPORT, R, lineage, obligation_closed, qpath, read_q  # noqa: E402

T0 = time.monotonic()
BUDGET_S = 2.0  # 도구 1회 전체 예산(R214 완료 조건) — tmux 조회는 남은 예산만큼만 기다린다
HERE = os.path.dirname(os.path.abspath(__file__))
NO_MARK = "(자율 큐 처리 표식 없음)"


def planner():
    try:
        with open(f"{R}/.fable-team/seats-planner.json", encoding="utf-8") as f:
            p = json.load(f)
        return p["_master"], p.get("_cards_wt", "")
    except (OSError, ValueError, KeyError) as e:
        raise ReadError(f"planner 좌석표 {type(e).__name__} {e}")


def table(env, name, wt):
    """(데이터 행 목록, 머리 칸 목록) — 파일이 없으면 None."""
    cand = [os.environ[env]] if os.environ.get(env) else [f"{R}/design/planner/{name}", f"{R}/.worktrees/{wt}/design/planner/{name}"]
    path = next((c for c in cand if os.path.isfile(c)), None)
    if path is None:
        return None
    try:
        with open(path, encoding="utf-8") as f:
            rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in f if ln.lstrip().startswith("|")]
    except (OSError, ValueError) as e:
        raise ReadError(f"{name} 읽기 실패: {type(e).__name__} {e}")
    rows = [r for r in rows if not all(re.fullmatch(r":?-+:?", c) for c in r)]
    if not rows:
        raise ReadError(f"{name} 에 표가 없다(원천 손상): {path}")  # 헤더만 있는 빈 표(=0)와 구분
    return rows[1:], rows[0]


def column(name, t, col):
    """필수 칸의 위치 — 칸이 없거나 그 칸에 못 미치는 행이 있으면 ReadError(조용한 0 금지)."""
    rows, head = t
    if col not in head:
        raise ReadError(f"{name} 표 머리에 «{col}» 칸이 없다: {head}")
    i = head.index(col)
    if any(len(r) <= i for r in rows):
        raise ReadError(f"{name} 에 «{col}» 칸보다 짧은 행이 있다")
    return i


def merge_waiting(t):
    i = column("MERGE-QUEUE", t, "상태")
    return sum(1 for r in t[0] if r[i].startswith("대기"))


def autonomy_open(t):
    if "처리됨" not in t[1]:
        return len(t[0]), NO_MARK
    i = column("AUTONOMY-QUEUE", t, "처리됨")
    return sum(1 for r in t[0] if not r[i]), ""


def minutes(ts, now):
    t = datetime.fromisoformat(ts)
    return int((now - (t.astimezone().replace(tzinfo=None) if t.tzinfo else t)).total_seconds() // 60)


def inbox(me, now):
    if not os.path.exists(qpath(me)):
        raise ReadError(f"인박스 큐 없음: {qpath(me)}")
    try:
        rows = [x for x in read_q(qpath(me)) if not obligation_closed(x)]
    except (OSError, ValueError, KeyError) as e:
        raise ReadError(f"인박스 {type(e).__name__} {e}")
    decide = sum(1 for x in rows if x["cls"] in ("②", "③"))
    other = [x for x in rows if x["cls"] in MUST_REPORT and "#" in x["from"] and lineage(x["from"]) != lineage(me)]
    sessions = live_sessions() if other else set()  # tmux 조회는 실행당 1회
    team = [x for x in other if x["from"] in sessions]  # 은퇴·죽은 좌석의 쪽지는 팀 대기가 아니다(메모로만)
    return decide, sorted(((x["seq"], x["from"], minutes(x["ts"], now), x["body_path"]) for x in team), key=lambda t: -t[2]), len(other) - len(team)


def left():
    """전체 예산에서 남은 초 — 외부 조회(tmux·ft-hil.sh)는 min(자기 상한, 이 값)만 기다린다."""
    return max(0.1, BUDGET_S - (time.monotonic() - T0))


def live_sessions():
    """현역 좌석 = tmux 세션 실재만(명부의 _replaced_by 없음만으로는 현역이 아니다). 센서 오류·시간 초과·실행 불가는 «세션 없음» 이 아니다 → ReadError."""
    try:
        p = subprocess.run([os.environ.get("FT_DECISION_TMUX", "tmux"), "list-sessions", "-F", "#{session_name}"], capture_output=True, text=True, timeout=left())
    except subprocess.TimeoutExpired:
        raise ReadError(f"tmux list-sessions 가 전체 예산 {BUDGET_S:g}s 안에 끝나지 않음")
    except OSError as e:
        raise ReadError(f"tmux 실행 불가: {e}")
    if p.returncode == 0:
        return set(p.stdout.splitlines())
    if re.search(r"no server running on|error connecting to [^\n]*\(No such file or directory\)", p.stderr):
        return set()  # tmux 서버 자체가 없음 = 세션 0 (정상) — Permission denied 등 그 밖의 connecting 오류는 아래 rc4
    raise ReadError(f"tmux list-sessions rc={p.returncode} {p.stderr.strip()[:120]}")


def scripts():
    try:
        p = subprocess.run(["bash", os.environ.get("FT_DECISION_HIL", f"{HERE}/ft-hil.sh"), "--pending", "--each"], capture_output=True, text=True, timeout=min(7.0, left()))
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ReadError(f"ft-hil.sh {type(e).__name__} {e}")
    if p.returncode != 0:
        raise ReadError(f"ft-hil.sh --pending rc={p.returncode} {p.stderr.strip()[:120]}")
    return sum(1 for ln in p.stdout.splitlines() if re.fullmatch(r"h\d+ \d+", ln))


def flag_off(wt):
    """(꺼진 플래그 미결정 수, 메모) — 기본 꺼짐 FE 플래그인데 배포 값이 없는 것 중 결정 기록(켬/끔 + 판정)이 없는 것 (R239)."""
    t = table("FT_DECISION_FLAG_DECISIONS", "FLAG-DECISIONS.md", wt)
    decided = set()
    if t:
        i, j, k = (column("FLAG-DECISIONS", t, c) for c in ("플래그", "결정(켬/끔)", "판정"))
        decided = {r[i] for r in t[0] if r[j] in ("켬", "끔") and r[k]}
    rows = open_flags(scan(os.environ.get("FT_FLAG_OFF_REPO", R), os.environ.get("FT_FLAG_OFF_REF", "origin/main"), min(7.0, left())), decided)
    return len(rows), (f"(꺼진 플래그 {len(rows)})" + ("" if t else " (플래그 결정 파일 없음)") if rows else "")


def summary(now):
    me, wt = planner()
    decide, team, old = inbox(me, now)
    mq, aq = table("FT_DECISION_MERGE_QUEUE", "MERGE-QUEUE.md", wt), table("FT_DECISION_AUTONOMY_QUEUE", "AUTONOMY-QUEUE.md", wt)
    a, note = autonomy_open(aq) if aq else (0, "(AUTONOMY-QUEUE 파일 없음)")
    f, fnote = flag_off(wt)
    notes = " ".join(x for x in (f"(옛 좌석 미닫힘 {old})" if old else "", fnote, note, "" if mq else "(MERGE-QUEUE 파일 없음)") if x)
    return {"me": me, "n": decide + (merge_waiting(mq) if mq else 0) + a + f, "m": scripts(), "team": team, "notes": notes}


def line(s):
    wait = f"팀 대기 {len(s['team'])}건" + (f"(가장 오래 {s['team'][0][1]} {s['team'][0][2]}분)" if s["team"] else "")
    return f"결정 인터뷰 {s['n']}건 · 스크립트 {s['m']}건 · {wait}" + (" " + s["notes"] if s["notes"] else "")


def main(argv):
    if argv not in ([], ["--detail"], ["--alarm"]):
        print("usage: ft-decision-count.sh [--detail | --alarm]", file=sys.stderr)
        return 2
    now = datetime.fromisoformat(os.environ["FT_DECISION_NOW"]) if os.environ.get("FT_DECISION_NOW") else datetime.now()
    try:
        s = summary(now)
        if argv == ["--alarm"]:
            return alarm(s) or 0
    except ReadError as e:
        print(f"ERROR ft-decision-count: {e}", file=sys.stderr)
        return 4
    print(line(s))
    for seq, frm, mins, bp in s["team"] if argv else []:
        print(f"  #{seq} {frm} {mins}분 {first_line(bp)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
