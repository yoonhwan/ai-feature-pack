"""ft_decision_alarm.py — ft_decision_count.py 의 --alarm 경로(30분 넘은 팀 대기 seq 마다 planner 쪽지 1통) + 공용 ReadError (R214 · 구조 분리 R239).
ReadError 는 여기 한 곳에서만 정의한다 — ft_decision_count 가 `__main__` 으로 돌 때 순환 import 로 클래스가 둘이 되는 것을 막는다.
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_inbox_core import R  # noqa: E402

WAIT_MIN = int(os.environ.get("FT_DECISION_WAIT_MIN", "30"))


class ReadError(Exception):
    pass


def first_line(path):
    try:
        return re.sub(r"^\[[^\]]*->[^\]]*\]\s*", "", open(path, encoding="utf-8").readline().strip())[:40]
    except OSError:
        return ""


def alarm(s):
    sf = f"{R}/.fable-team/state/decision-alarm.json"
    try:
        sent = json.load(open(sf, encoding="utf-8")) if os.path.exists(sf) else {}
    except (OSError, ValueError) as e:
        raise ReadError(f"경보 상태 파일 {sf}: {e}")
    live = {str(t[0]) for t in s["team"]}
    sent = {k: v for k, v in sent.items() if k in live}  # 닫히면 지운다(재무장)
    mbox, who = os.environ.get("FT_DECISION_MBOX", f"{R}/.fable-team/comm/mbox.sh"), os.environ.get("FT_DECISION_FROM", "ft-decision-count")
    new = [t for t in s["team"] if t[2] >= WAIT_MIN and str(t[0]) not in sent]
    err = ""
    if new:  # 실행 1회 = 쪽지 최대 1통(≤5줄)
        shown = [f"{frm} #{seq} {mins}분" for seq, frm, mins, _ in new[:3]]
        body = "\n".join([f"[결정 대기 경보] 새로 {WAIT_MIN}분 넘은 팀 대기 {len(new)}건 — 그 턴에 정하거나 오빠 인터뷰", *shown, *([f"외 {len(new) - 3}건"] if len(new) > 3 else [])])
        p = subprocess.run(["bash", mbox, "send", s["me"], who, body], capture_output=True, text=True, timeout=7)
        if p.returncode == 0:
            sent.update({str(t[0]): datetime.now().isoformat(timespec="seconds") for t in new})
            print(f"ALARM {len(new)}건 1통")
        else:
            err = f"mbox send rc={p.returncode} {p.stderr.strip()[:120]}"
    os.makedirs(os.path.dirname(sf), exist_ok=True)
    with open(sf, "w", encoding="utf-8") as f:
        json.dump(sent, f)  # 닫힌 seq 를 지운 상태도 여기서 저장(재무장)
    if err:
        raise ReadError(err)
