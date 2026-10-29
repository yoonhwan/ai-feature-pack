"""ft_decision_count.py — planner 가 오빠께 알려야 할 «결정 대기열» 을 한 줄로 센다 (R214 · 오빠 판정 1804).

출력 1줄: `결정 인터뷰 N건 · 스크립트 N건 · 팀 대기 N건(가장 오래 <팀 좌석> N분)`
  결정 인터뷰 = 인박스 미닫힘 중 머리 질문 표식(ft_decision_kind · R337) + MERGE-QUEUE 상태 «대기» 행 + AUTONOMY-QUEUE 행(파일 없음 = 0)
  스크립트 = ft-hil.sh --pending (R186 표식) · 팀 대기 = 그 질문 중 다른 팀 현역 좌석('#' 있는 이름)이 보낸 것 · 24시간 넘은 질문 = « · 묵은 M건»
--detail 현역 다른 팀 좌석 미닫힘 + 이유 낱말(질문표식/묵음/통보/본문 없음) · --alarm 30분(FT_DECISION_WAIT_MIN) 넘은 팀 대기 seq 마다 planner 에 쪽지 1통(상태 파일로 seq 당 1회).
읽기 실패 = stderr ERROR + rc 4 (숫자 지어내기 0) · 꺼진 플래그 칸의 git 실패·예산 초과만 그 칸 «판정 불가» 메모 + rc 0(r1135) · 본문 파일 없음 = «본문 없음 N건» 칸 + WARN 1줄(r738 · 건수 묶음 r1135). 시험 env: FT_ROOT · FT_DECISION_{NOW,MBOX,FROM,MERGE_QUEUE,AUTONOMY_QUEUE} · HIL_DIR.
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_decision_alarm import ReadError, alarm, first_line  # noqa: E402
from ft_flag_off import open_count  # noqa: E402
from ft_decision_kind import BODY_MISSING, ORDER, open_rows  # noqa: E402
from ft_inbox_core import R, answered_seqs, lineage, qpath, read_q  # noqa: E402
from ft_team_lib import TeamPathError, data_root, planner_queue, team_doc_ref, team_in  # noqa: E402

T0 = time.monotonic()
# 도구 1회 전체 예산 — 외부 조회(tmux·ft-hil.sh)는 남은 예산만큼만 기다린다. 2.0 → 5.0 (R303 · 판정 1395): 실측 중앙 1.47 s · 최대 1.59 s(CPU 28개 부하) · 실사용 rc4 62건 전부 ft-hil.sh 시간 초과(swap) · 호출자 ft_news_ledger 가 timeout=7 이라 그 밑(7초 룰)
# FT_DECISION_BUDGET_S = 시험 전용(예산 기전 시험이 짧은 값을 준다) — 라이브 plist·훅에는 넣지 않는다
BUDGET_S = 5.0
BUDGET_MAX_S = 6.0  # 호출자 timeout=7 밑 — 이 위 값은 7초 룰(판정 666) 밖이라 받지 않는다
HERE = os.path.dirname(os.path.abspath(__file__))
NO_MARK = "(자율 큐 처리 표식 없음)"


def budget_from_env():
    """FT_DECISION_BUDGET_S → 초. 빈 값 = 5.0 · 숫자 아님·`0 < v ≤ 6` 밖 = ValueError(조용한 대체 0 · R303 DA⑥ H2)."""
    raw = os.environ.get("FT_DECISION_BUDGET_S") or ""
    if not raw:
        return 5.0
    try:
        v = float(raw)
    except ValueError:
        v = 0.0
    if not 0 < v <= BUDGET_MAX_S:  # nan·inf 도 여기서 걸린다
        raise ValueError(raw)
    return v


def planner():
    try:
        with open(f"{R}/.fable-team/seats-planner.json", encoding="utf-8") as f:
            p = json.load(f)
        return p["_master"], p.get("_cards_wt", "")
    except (OSError, ValueError, KeyError) as e:
        raise ReadError(f"planner 좌석표 {type(e).__name__} {e}")


def table(env, name, wt, at=None, ref_at=None):
    """(데이터 행 목록, 머리 칸 목록) — 표가 없으면 None. 자리 = env 파일 → at(r515 큐 고정 자리) → 카드 워크트리 디스크(명단 있을 때 · 미착지 최신 행 · ref_at 이면 건너뜀) → ref 정본 본문(r517 · ref_at = 그 루트 · r839)."""
    try:  # r517: 루트 자리 = ref(FT_TEAMS_REF·origin/main) 명단 + ref 본문 — 공용 루트 체크아웃이 옛 main(명단 없음)이어도 읽힌다 · 체크아웃 명단 0
        cand = [os.environ[env]] if os.environ.get(env) else [str(at())] if at else []
        if not cand and not ref_at and os.path.isfile(f"{R}/.worktrees/{wt}/design/TEAMS.md"):
            cand.append(str(team_in(f"{R}/.worktrees/{wt}", "planner") / name))
        path = next((c for c in cand if os.path.isfile(c)), None)
        text = Path(path).read_text(encoding="utf-8") if path else None if os.environ.get(env) or at else team_doc_ref(ref_at() if ref_at else R, "planner", name, os.environ.get("FT_TEAMS_REF") or "origin/main")
    except TeamPathError as e:
        raise ReadError(f"{name} 위치를 못 풀었다: {e}")
    except (OSError, ValueError) as e:
        raise ReadError(f"{name} 읽기 실패: {type(e).__name__} {e}")
    if text is None:
        return None
    rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in text.splitlines() if ln.lstrip().startswith("|")]
    rows = [r for r in rows if not all(re.fullmatch(r":?-+:?", c) for c in r)]
    if not rows:
        raise ReadError(f"{name} 에 표가 없다(원천 손상): {path or 'ref:' + name}")  # 헤더만 있는 빈 표(=0)와 구분
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
    col = next((c for c in ("상태", "처리됨") if c in t[1]), None)   # r528: 상태 칸(옛 이름 처리됨) · 열린 줄 = 빈 칸(옛) 또는 «대기»
    if col is None:
        return len(t[0]), NO_MARK
    i = column("AUTONOMY-QUEUE", t, col)
    return sum(1 for r in t[0] if not r[i] or r[i].split("·")[0].split("—")[0].strip() == "대기"), ""


def inbox(me, now):
    if not os.path.exists(qpath(me)):
        raise ReadError(f"인박스 큐 없음: {qpath(me)}")
    try:
        rows = open_rows(read_q(qpath(me)), answered_seqs(me), now)
    except (OSError, ValueError, KeyError) as e:
        raise ReadError(f"인박스 {type(e).__name__} {e}")
    sessions = live_sessions() if any("#" in t[0]["from"] for t in rows) else set()  # tmux 조회는 실행당 1회
    asks = [x["from"] for x, k, _ in rows if k == "질문표식"]
    dead = sum(1 for f in asks if "#" in f and f not in sessions)  # 은퇴·죽은 좌석의 질문은 N·팀 대기가 아니다(메모로만)
    live = [t for t in rows if "#" in t[0]["from"] and t[0]["from"] in sessions and lineage(t[0]["from"]) != lineage(me)]
    return {"n": len(asks) - dead, "stale": sum(1 for t in rows if t[1] == "묵음"), "miss": sum(1 for t in rows if t[1] == BODY_MISSING),
            "team": sorted(((x["seq"], x["from"], m, x["body_path"]) for x, k, m in live if k == "질문표식"), key=lambda t: -t[2]),
            "detail": sorted(((x["seq"], x["from"], m, k, x["body_path"]) for x, k, m in live), key=lambda t: (ORDER[t[3]], -t[2])),
            "old": dead}


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
    rows, why = open_count(os.environ.get("FT_FLAG_OFF_REPO", R), os.environ.get("FT_FLAG_OFF_REF", "origin/main"), f"{R}/.fable-team/state/flag-off-cache.json", decided, deadline=T0 + BUDGET_S)
    return (0, why) if why else (len(rows), (f"(꺼진 플래그 {len(rows)})" + ("" if t else " (플래그 결정 파일 없음)") if rows else ""))


def summary(now):
    me, wt = planner()
    box = inbox(me, now)
    mq, aq = table("FT_DECISION_MERGE_QUEUE", "MERGE-QUEUE.md", wt), table("FT_DECISION_AUTONOMY_QUEUE", "AUTONOMY-QUEUE.md", wt, (lambda: planner_queue(data_root(R))) if os.environ.get("FT_PLANNER_DIR") else None, lambda: data_root(R))  # r839: 큐 본문 = origin/main 판(루트 체크아웃 디스크 0)
    a, note = autonomy_open(aq) if aq else (0, "")  # 리졸버가 낸 자리에 파일 없음 = 큐 0행(메모 0 · r2 ㉡) — 리졸버 실패만 ReadError
    m, (f, fnote) = scripts(), flag_off(wt)  # r1135: 꺼진 플래그 칸은 맨 끝 — 남은 예산만 쓰고 넘쳐도 그 칸만 «판정 불가»(앞 칸 예산을 굶기지 않는다)
    notes = " ".join(x for x in (f"(옛 좌석 미닫힘 {box['old']})" if box["old"] else "", fnote, note, "" if mq else "(MERGE-QUEUE 파일 없음)") if x)
    return {**box, "me": me, "n": box["n"] + (merge_waiting(mq) if mq else 0) + a + f, "m": m, "notes": notes}


def line(s):
    wait = f"팀 대기 {len(s['team'])}건" + (f"(가장 오래 {s['team'][0][1]} {s['team'][0][2]}분)" if s["team"] else "") + (f" · 묵은 {s['stale']}건" if s["stale"] else "")
    return f"결정 인터뷰 {s['n']}건 · 스크립트 {s['m']}건 · {wait}" + (f" · 본문 없음 {s['miss']}건" if s["miss"] else "") + (" " + s["notes"] if s["notes"] else "")


def main(argv):
    global BUDGET_S
    if argv not in ([], ["--detail"], ["--alarm"]):
        print("usage: ft-decision-count.sh [--detail | --alarm]", file=sys.stderr)
        return 2
    try:
        BUDGET_S = budget_from_env()
    except ValueError as e:
        print(f"ERROR ft-decision-count: FT_DECISION_BUDGET_S={e} — 0 초과 6 이하 숫자", file=sys.stderr)
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
    for seq, frm, mins, why, bp in s["detail"] if argv else []:
        print(f"  #{seq} {frm} {mins}분 {why} {first_line(bp)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
